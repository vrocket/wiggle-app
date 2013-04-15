%% Feel free to use, reuse and abuse the code in this file.

%% @doc Hello world handler.
-module(wiggle_hypervisor_handler).

-export([init/3,
         rest_init/2]).

-export([content_types_provided/2,
         content_types_accepted/2,
         allowed_methods/2,
         resource_exists/2,
         forbidden/2,
         service_available/2,
         options/2,
         delete_resource/2,
         is_authorized/2]).

-export([to_json/2,
         from_json/2,
         to_msgpack/2,
         from_msgpack/2]).

-ignore_xref([to_json/2,
              from_json/2,
              from_msgpack/2,
              to_msgpack/2,
              allowed_methods/2,
              content_types_accepted/2,
              content_types_provided/2,
              delete_resource/2,
              forbidden/2,
              init/3,
              is_authorized/2,
              options/2,
              service_available/2,
              resource_exists/2,
              rest_init/2]).

-record(state, {path, method, version, token, content, reply, obj, body}).

init(_Transport, _Req, []) ->
    {upgrade, protocol, cowboy_rest}.

rest_init(Req, _) ->
    wiggle_handler:initial_state(Req).

service_available(Req, State) ->
    case {libsniffle:servers(), libsnarl:servers()} of
        {[], _} ->
            {false, Req, State};
        {_, []} ->
            {false, Req, State};
        _ ->
            {true, Req, State}
    end.

options(Req, State) ->
    Methods = allowed_methods(State#state.version, State#state.token, State#state.path),
    Req1 = cowboy_req:set_resp_header(
             <<"Access-Control-Allow-Methods">>,
             string:join(
               lists:map(fun erlang:atom_to_list/1,
                         [<<"HEAD">>, <<"OPTIONS">> | Methods]), ", "), Req),
    {ok, Req1, State}.

content_types_provided(Req, State) ->
    {[
      {<<"application/json">>, to_json},
      {<<"application/x-msgpack">>, to_msgpack}
     ], Req, State}.

content_types_accepted(Req, State) ->
    {wiggle_handler:accepted(), Req, State}.

allowed_methods(Req, State) ->
    {[<<"HEAD">>, <<"OPTIONS">> | allowed_methods(State#state.version, State#state.token, State#state.path)], Req, State}.

allowed_methods(_Version, _Token, []) ->
    [<<"GET">>];

allowed_methods(_Version, _Token, [_Hypervisor]) ->
    [<<"GET">>];

allowed_methods(_Version, _Token, [_Hypervisor, <<"characteristics">>|_]) ->
    [<<"PUT">>, <<"DELETE">>];

allowed_methods(_Version, _Token, [_Hypervisor, <<"metadata">>|_]) ->
    [<<"PUT">>, <<"DELETE">>].

resource_exists(Req, State = #state{path = []}) ->
    {true, Req, State};

resource_exists(Req, State = #state{path = [Hypervisor | _]}) ->
    case libsniffle:hypervisor_get(Hypervisor) of
        not_found ->
            {false, Req, State};
        {ok, Obj} ->
            {true, Req, State#state{obj = Obj}}
    end.

is_authorized(Req, State = #state{method = <<"OPTIONS">>}) ->
    {true, Req, State};

is_authorized(Req, State = #state{token = undefined}) ->
    {{false, <<"X-Snarl-Token">>}, Req, State};

is_authorized(Req, State) ->
    {true, Req, State}.

forbidden(Req, State = #state{method = <<"OPTIONS">>}) ->
    {false, Req, State};

forbidden(Req, State = #state{token = undefined}) ->
    {true, Req, State};

forbidden(Req, State = #state{path = []}) ->
    {allowed(State#state.token, [<<"cloud">>, <<"hypervisors">>, <<"list">>]), Req, State};

forbidden(Req, State = #state{method = <<"GET">>, path = [Hypervisor]}) ->
    {allowed(State#state.token, [<<"hypervisors">>, Hypervisor, <<"get">>]), Req, State};

forbidden(Req, State = #state{method = <<"PUT">>, path = [Hypervisor, <<"metadata">> | _]}) ->
    {allowed(State#state.token, [<<"hypervisors">>, Hypervisor, <<"edit">>]), Req, State};

forbidden(Req, State = #state{method = <<"DELETE">>, path = [Hypervisor, <<"metadata">> | _]}) ->
    {allowed(State#state.token, [<<"hypervisors">>, Hypervisor, <<"edit">>]), Req, State};

forbidden(Req, State = #state{method = <<"PUT">>, path = [Hypervisor, <<"characteristics">> | _]}) ->
    {allowed(State#state.token, [<<"hypervisors">>, Hypervisor, <<"edit">>]), Req, State};

forbidden(Req, State = #state{method = <<"DELETE">>, path = [Hypervisor, <<"characteristics">> | _]}) ->
    {allowed(State#state.token, [<<"hypervisors">>, Hypervisor, <<"edit">>]), Req, State};

forbidden(Req, State) ->
    {true, Req, State}.

%%--------------------------------------------------------------------
%% GET
%%--------------------------------------------------------------------

to_json(Req, State) ->
    {Reply, Req1, State1} = handle_request(Req, State),
    {jsx:encode(Reply), Req1, State1}.

to_msgpack(Req, State) ->
    {Reply, Req1, State1} = handle_request(Req, State),
    {msgpack:pack(Reply, [jsx]), Req1, State1}.

handle_request(Req, State = #state{token = Token, path = []}) ->
    {ok, Permissions} = libsnarl:user_cache({token, Token}),
    {ok, Res} = libsniffle:hypervisor_list([{must, 'allowed', [<<"hypervisors">>, {<<"res">>, <<"name">>}, <<"get">>], Permissions}]),
    {lists:map(fun ({E, _}) -> E end,  Res), Req, State};

handle_request(Req, State = #state{path = [_Hypervisor], obj = Obj}) ->
    {Obj, Req, State}.

%%--------------------------------------------------------------------
%% PUT
%%--------------------------------------------------------------------

from_json(Req, State) ->
    {ok, Body, Req1} = cowboy_req:body(Req),
    {Reply, Req2, State1} = case Body of
                                <<>> ->
                                    handle_write(Req1, State, []);
                                _ ->
                                    Decoded = jsx:decode(Body),
                                    handle_write(Req1, State, Decoded)
                            end,
    {Reply, Req2, State1}.

from_msgpack(Req, State) ->
    {ok, Body, Req1} = cowboy_req:body(Req),
    {Reply, Req2, State1} = case Body of
                                <<>> ->
                                    handle_write(Req1, State, []);
                                _ ->
                                    Decoded = msgpack:unpack(Body, [jsx]),
                                    handle_write(Req1, State, Decoded)
                            end,
    {Reply, Req2, State1}.

handle_write(Req, State = #state{path = [Hypervisor, <<"characteristics">> | Path]}, [{K, V}]) ->
    libsniffle:hypervisor_set(Hypervisor, [<<"characteristics">> | Path] ++ [K], jsxd:from_list(V)),
    {true, Req, State};

handle_write(Req, State = #state{path = [Hypervisor, <<"metadata">> | Path]}, [{K, V}]) ->
    libsniffle:hypervisor_set(Hypervisor, [<<"metadata">> | Path] ++ [K], jsxd:from_list(V)),
    {true, Req, State};

handle_write(Req, State, _Body) ->
    {false, Req, State}.


%%--------------------------------------------------------------------
%% DELETE
%%--------------------------------------------------------------------

delete_resource(Req, State = #state{path = [Hypervisor, <<"characteristics">> | Path]}) ->
    libsniffle:hypervisor_set(Hypervisor, [<<"characteristics">> | Path], delete),
    {true, Req, State};

delete_resource(Req, State = #state{path = [Hypervisor, <<"metadata">> | Path]}) ->
    libsniffle:hypervisor_set(Hypervisor, [<<"metadata">> | Path], delete),
    {true, Req, State}.


%% Internal Functions

allowed(Token, Perm) ->
    case libsnarl:allowed({token, Token}, Perm) of
        not_found ->
            true;
        true ->
            false;
        false ->
            true
    end.
