-module(wiggle_cloud_h).

-include("wiggle_version.hrl").
-include("wiggle.hrl").

-export([allowed_methods/3,
         permission_required/1,
         authorization_required/1,
         get/1,
         read/2]).

-ignore_xref([allowed_methods/3,
              permission_required/1,
              authorization_required/1,
              get/1,
              read/2]).

allowed_methods(_Version, _Token, [<<"connection">>]) ->
    [<<"GET">>];

allowed_methods(_Version, _Token, []) ->
    [<<"GET">>].

get(_) ->
    {ok, undefined}.

authorization_required(#state{path = [<<"connection">>]}) ->
    false;

authorization_required(_) ->
    true.

permission_required(#state{path = [<<"connection">>]}) ->
    {ok, always};

permission_required(#state{path = []}) ->
    {ok, [<<"cloud">>, <<"cloud">>, <<"status">>]};

permission_required(_State) ->
    undefined.

%%--------------------------------------------------------------------
%% GET
%%--------------------------------------------------------------------
read(Req, State = #state{path = [<<"connection">>]}) ->
    Res = [
           {<<"sniffle">>, length(libsniffle:servers())},
           {<<"snarl">>, length(libsnarl:servers())}
          ],
    {Res, Req, State};

read(Req, State = #state{path = []}) ->
    {Versions1, Metrics1, Warnings1} =
        case {libsnarl:version(), libsnarl:status()} of
            {{ok, SnaVer}, {ok, {MetricsSna, WarningsSna}}}
              when is_binary(SnaVer) ->
                {[{snarl, SnaVer}], MetricsSna, WarningsSna};
            _ ->
                {[], [], [[{<<"category">>, <<"snarl">>},
                           {<<"element">>, <<"all">>},
                           {<<"message">>, <<"The Snarl subsystem could not be reached.">>}
                          ]]}
        end,
    {Versions3, Metrics3, Warnings3} =
        case {libsniffle:version(), libsniffle:cloud_status()} of
            {{ok, SniVer}, {ok, {MetricsSni, WarningsSni}}}
              when is_binary(SniVer) ->
                {[{sniffle, SniVer} | Versions1],
                 MetricsSni ++ Metrics1,
                 WarningsSni ++ Warnings1};
            _ ->
                {Versions1, Metrics1,
                 [[{<<"category">>, <<"sniffle">>},
                   {<<"element">>, <<"all">>},
                   {<<"message">>, <<"The Sniffle subsystem could not be reached.">>}
                  ] | Warnings1]}
        end,
    {[{versions, [{wiggle, ?VERSION} | Versions3]},
      {metrics,  Metrics3},
      {warnings, Warnings3}], Req, State}.
