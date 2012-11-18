%%%-------------------------------------------------------------------
%%% @author Heinz N. Gies <heinz@licenser.net>
%%% @copyright (C) 2012, Heinz N. Gies
%%% @doc
%%%
%%% @end
%%% Created : 20 Apr 2012 by Heinz N. Gies <heinz@licenser.net>
%%%-------------------------------------------------------------------
-module(wiggle_handler).

-behaviour(cowboy_http_handler).

%% Callbacks
-export([init/3, handle/2, terminate/2]).


%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% @spec
%% @end
%%--------------------------------------------------------------------

init({_Any, http}, Req, []) ->
    {ok, Req, undefined}.

%%--------------------------------------------------------------------
%% @doc
%% @spec
%% @end
%%--------------------------------------------------------------------

handle(Req, State) ->
    {Path, Req2} = cowboy_http_req:path(Req),
    {Method, Req3} = cowboy_http_req:method(Req2),
    try  wiggle_session:get(Req3) of
	 undefined ->
	    case Path of
		[<<"login">>] ->
		    request(Method, Path, undefined, Req3, State);
		_ ->
		    io:format("1~n"),
		    login(Req3, State)
	    end;
	 Auth ->
	    case libsnarl:user_cache(Auth, Auth) of
		{ok, Auth1} ->
		    case libsnarl:allowed(Auth, Auth1, [service, wiggle, login]) of
			true ->
			    request(Method, Path, Auth1, Req3, State);
			false ->
			    {ok, Req4} = wiggle_session:del(Req3),
			    login(Req4, State)
		    end;
		_ ->
		    case libsnarl:allowed(Auth, Auth, [service, wiggle, login]) of
			{ok, _} ->
			    request(Method, Path, Auth, Req3, State);
			_ ->
			    {ok, Req4} = wiggle_session:del(Req3),
			    io:format("3~n"),
			    login(Req4, State)
		    end
	    end
    catch
	_T:_E ->
	    {ok, Req5} = wiggle_session:del(Req3),
	    login(Req5, State)
    end.

login(Req, State) ->
    {ok, Req2} =  cowboy_http_req:reply(200, [{<<"Refresh">>, <<"0; url=/login">>}], <<"">>, Req),
    {ok, Req2, State}.

request('GET', [<<"login">>], undefined, Req, State) ->
    {ok, Page} = login_dtl:render([]),
    {ok, Req1} = cowboy_http_req:reply(200, [], Page, Req),
    {ok, Req1, State};


request('POST', [<<"login">>], undefined, Req, State) ->
    {Vals, Req1} = cowboy_http_req:body_qs(Req),
    User = proplists:get_value(<<"login">>, Vals),
    Pass = proplists:get_value(<<"pass">>, Vals),
    case libsnarl:auth(User, Pass) of
	{ok, Auth} ->
	    case libsniffle:list_keys(Auth) of 
		{ok, _} ->
		    {ok, Req2} = wiggle_session:set(Req1, Auth),
		    io:format("4:~p~n", [Req2]),
		    {ok, Req3} = cowboy_http_req:reply(200, [{<<"Refresh">>, <<"0; url=/">>}], <<"">>, Req2),
		    {ok, Req3, State};		
		_ ->
		    io:format("5~n"),
		    {ok, Req2} = wiggle_session:set(Req1, Auth),
		    {ok, Req3} = cowboy_http_req:reply(200, [{<<"Refresh">>, <<"0; url=/account">>}], <<"">>, Req2),
		    {ok, Req3, State}
		end;
	_ ->
	    {ok, Page} = login_dtl:render([{messages, 
					    [[{text, <<"Login failed">>},
					      {class, <<"error">>}]]}]),
	    {ok, Req2} = cowboy_http_req:reply(200, [], Page, Req1),
	    {ok, Req2, State}
    end;

request('GET', [<<"logout">>],  _Auth, Req, State) ->
    {ok, Req1} = wiggle_session:del(Req),
    {ok, Req2} = cowboy_http_req:reply(200, [{<<"Refresh">>, <<"0; url=/login">>}], <<"">>, Req1),
    {ok, Req2, State};

request('GET', [], Auth, Req, State) ->
    case libsnarl:allowed(Auth, Auth, [service, wiggle, module, home]) of
	false ->
	    error_page(403, Req, State);
	true ->
	    {ok, Page} = index_dtl:render(page_permissions(Auth)),
	    {ok, Req2} = cowboy_http_req:reply(200, [], Page, Req),
	    {ok, Req2, State}
    end;

request('GET', [<<"analytics">>], Auth, Req, State) ->
    case libsnarl:allowed(Auth, Auth ,[service, wiggle, module, analytics]) of
	false ->
	    error_page(403, Req, State);
	true ->
	    {ok, Page} = analytics_dtl:render(page_permissions(Auth) ++ [{page, "analytics"}]),
	    {ok, Req2} = cowboy_http_req:reply(200, [], Page, Req),
	    {ok, Req2, State}
    end;

request('GET', [<<"system">>], Auth, Req, State) ->
    case libsnarl:allowed(Auth, Auth, [service, wiggle, module, system]) of
	false ->
	    error_page(403, Req, State);
	true ->
	    {ok, Page} = system_dtl:render(page_permissions(Auth) ++ [{page, "system"}]),
	    {ok, Req2} = cowboy_http_req:reply(200, [], Page, Req),
	    {ok, Req2, State}
    end;

request('GET', [<<"about">>], Auth, Req, State) ->
    case libsnarl:allowed(Auth, Auth, [service, wiggle, module, about]) of
	false ->
	    error_page(403, Req, State);
	true ->
	    Versions = proplists:get_value(loaded, application:info()),
	    {wiggle, _, WiggleV} =lists:keyfind(wiggle, 1, Versions),
	    {ok, Page} = about_dtl:render(page_permissions(Auth) ++ 
					      [{versions, [[{name, <<"wiggle">>},
							    {version, list_to_binary(WiggleV)}]]},
					   {page, "about"}]),
	    {ok, Req2} = cowboy_http_req:reply(200, [], Page, Req),
	    {ok, Req2, State}
    end;

request('GET', [<<"admin">>], Auth , Req, State) ->
    case libsnarl:allowed(Auth, Auth, [service, wiggle, module, admin]) of
	false ->
	    error_page(403, Req, State);
	true ->
	    {ok, Page} = admin_dtl:render(page_permissions(Auth) ++ [{page, "admin"}]),
    	    {ok, Req2} = cowboy_http_req:reply(200, [], Page, Req),
	    {ok, Req2, State}
    end;

request('POST', [<<"admin">>], Auth , Req, State) ->
    case libsnarl:allowed(Auth, Auth, [service, wiggle, module, admin]) of
	false ->
	    error_page(403, Req, State);
	true ->
	    {Vals, Req1} = cowboy_http_req:body_qs(Req),
	    case proplists:get_value(<<"action">>, Vals) of
		<<"pass">> ->
		    Name = proplists:get_value(<<"name">>, Vals),
		    Pass = proplists:get_value(<<"pass">>, Vals),
		    {ok, _UUID} = libsnarl:user_add(Name, Pass)
	    end,
	    {ok, Page} = admin_dtl:render(page_permissions(Auth) ++ [{page, "admin"}]),
	    {ok, Req2} = cowboy_http_req:reply(200, [], Page, Req1),
	    {ok, Req2, State}
    end;

request('GET', [<<"account">>], Auth, Req, State) ->
    case libsnarl:allowed(Auth, Auth, [service, wiggle, module, account]) of
	false ->
	    error_page(403, Req, State);
	true ->
	    Messages = case libsniffle:list_keys(Auth) of 
			   {ok, _} ->
			       undefined;
			   _ ->
			       [[{text, <<"You are not authenticated with the API backend.">>}, {class, <<"error">>}]]
		       end,
	    {ok, Page} = account_dtl:render(page_permissions(Auth) ++ [{messages, Messages},
								       {page, "account"}]),
	    {ok, Req2} = cowboy_http_req:reply(200, [], Page, Req),
	    {ok, Req2, State}
    end;

request('POST', [<<"account">>], Auth, Req, State) ->
    case libsnarl:allowed(Auth, Auth, [service, wiggle, module, account]) of
	false ->
	    error_page(403, Req, State);
	true ->
	    {Vals, Req1} = cowboy_http_req:body_qs(Req),
	    case proplists:get_value(<<"action">>, Vals) of
		<<"pass">> ->
		    case proplists:get_value(<<"old">>, Vals) of
			Pass when is_binary(Pass) ->
			    case {proplists:get_value(<<"new">>, Vals), proplists:get_value(<<"confirm">>, Vals)} of				{New, New} ->
				    {ok, Name} = libsnarl:user_name(Auth, Auth),
				    case libsnarl:auth(Name, Pass) of
					{ok, _} ->
					    case libsnarl:user_passwd(Auth, Auth, New) of
						ok ->
						    {ok, Page} = account_dtl:render(
								   page_permissions(Auth) ++ 
								       [{messages,
									 [[{text, <<"Password changed.">>},
									   {class, <<"success">>}]]},
									{page, "account"}]),
						    {ok, Req2} = cowboy_http_req:reply(200, [], Page , Req1),
						    {ok, Req2, State};
						_ ->
						    {ok, Page} = account_dtl:render(
								   page_permissions(Auth) ++ 
								       [{messages,
									 [[{text, <<"Permission denied.">>},
									   {class, <<"error">>}]]},
									{page, "account"}]),
						    {ok, Req2} = cowboy_http_req:reply(200, [], Page , Req1),
						    {ok, Req2, State}
					    end;
					_ ->
					    {ok, Page} = account_dtl:render(
							   page_permissions(Auth) ++ 
							       [{messages,
								 [[{text, <<"Passwords incorrect.">>},
								   {class, <<"error">>}]]},
								{page, "account"}]),
					    {ok, Req2} = cowboy_http_req:reply(200, [], Page , Req1),
					    {ok, Req2, State}
				    end;
				_ ->
				    {ok, Page} = account_dtl:render(
						   page_permissions(Auth) ++ 
						   [{messages,
						     [[{text, <<"Passwords did not match.">>},
						       {class, <<"error">>}]]},
						    {page, "account"}]),
				    {ok, Req2} = cowboy_http_req:reply(200, [], Page , Req1),
				    {ok, Req2, State}
			end;
		_ ->
		    {ok, Page} = account_dtl:render(
				   page_permissions(Auth) ++ 
				   [{messages,
				     [[{text, <<"Old passwords was empty.">>},
				       {class, <<"error">>}]]},
				    {page, "account"}]),
			    {ok, Req2} = cowboy_http_req:reply(200, [], Page , Req1),
			    {ok, Req2, State}
		    end
	    end
    end;


request('GET', [<<"my">>, <<"users">>], Auth, Req, State) ->
    {ok, Res} = libsnarl:user_list(Auth),
    reply_json(Req, Res, State);

request('GET', [<<"my">>, <<"hosts">>], Auth, Req, State) ->
    {ok, Res} = libsniffle:list_hosts(Auth),
    reply_json(Req, Res, State);


request('GET', [<<"my">>, <<"users">>, User, <<"permissions">>], Auth, Req, State) ->
    case libsnarl:user_get(system, User) of
	{ok, UUID} ->
	    {ok, Res} = libsnarl:user_own_permissions(Auth, UUID),
	    reply_json(Req, encode_permissions(Res), State);
	_ ->
	    error_page(403, Req, State)
    end;

request('POST', [<<"my">>, <<"users">>], Auth, Req, State) ->
    {Vals, Req1} = cowboy_http_req:body_qs(Req),
    Login = proplists:get_value(<<"login">>, Vals),
    Pass = proplists:get_value(<<"pass">>, Vals),
    case libsnarl:user_add(Auth, Login, Pass) of
	{ok, _UUID} ->
	    reply_json(Req1, Login, State);
	_ ->
	    error_page(403, Req1, State)
    end;

request('POST', [<<"my">>, <<"users">>, User, <<"permissions">>], Auth, Req, State) ->
    case libsnarl:user_get(system, User) of
	{ok, UUID} ->	    
	    {Vals, Req1} = cowboy_http_req:body_qs(Req),
	    JSON = proplists:get_value(<<"perms">>, Vals),
	    Perm = decode_permission(JSON),
	    libsnarl:user_grant(Auth, UUID, Perm),
	    {ok, Res} = libsnarl:user_own_permissions(Auth, UUID),
	    reply_json(Req1, encode_permissions(Res), State);
	_ ->
	    error_page(403, Req, State)
    end;

request('DELETE', [<<"my">>, <<"users">>, User, <<"permissions">>], Auth, Req, State) ->
    case libsnarl:user_get(system, User) of
	{ok, UUID} ->	    
	    {Vals, Req1} = cowboy_http_req:body_qs(Req),
	    JSON = proplists:get_value(<<"perms">>, Vals),
	    Perm = decode_permission(JSON),
	    libsnarl:user_revoke(Auth, UUID, Perm),
	    {ok, Res} = libsnarl:user_own_permissions(Auth, UUID),
	    reply_json(Req1, encode_permissions(Res), State);
	_ ->
	    error_page(403, Req, State)
    end;

request('GET', [<<"my">>, <<"users">>, User, <<"groups">>], Auth, Req, State) ->
    case libsnarl:user_get(system, User) of
	{ok, UUID} ->
	    {ok, Res} = libsnarl:user_groups(Auth, UUID),
	    reply_json(Req,[Name ||
			       {ok, Name} <- [libsnarl:group_name(system, G) || G <- Res]], State);
	_ ->
	    error_page(403, Req, State)
    end;

request('POST', [<<"my">>, <<"users">>, User, <<"groups">>], Auth, Req, State) ->
    {Vals, Req1} = cowboy_http_req:body_qs(Req),
    Group = proplists:get_value(<<"group">>, Vals),
    case {libsnarl:user_get(system, User), libsnarl:group_get(Auth, Group)} of
	{{ok, UUID}, {ok, GUUID}} ->
	    case libsnarl:user_add_to_group(Auth, UUID, GUUID) of
		ok ->
		    reply_json(Req1,Group, State);
		_ ->
		    error_page(403, Req1, State)
	    end;
	_ ->
	    error_page(403, Req, State)
    end;

request('DELETE', [<<"my">>, <<"users">>, User, <<"groups">>, Group], Auth, Req, State) ->
    case {libsnarl:user_get(system, User), libsnarl:group_get(Auth, Group)} of
	{{ok, UUID}, {ok, GUUID}} ->
	    case libsnarl:user_delete_from_group(Auth, UUID, GUUID) of
		ok ->
		    {ok, Res} = libsnarl:user_groups(Auth, UUID),
		    reply_json(Req,[Name ||
				       {ok, Name} <- [libsnarl:group_name(system, G) || G <- Res]], State);
		_ ->
		    error_page(403, Req, State)
	    end;
	_ ->
	    error_page(403, Req, State)
    end;

request('DELETE', [<<"my">>, <<"users">>, User], Auth, Req, State) ->
    case libsnarl:user_get(Auth, User) of
	{ok, UUID} ->
	    case libsnarl:user_delete(Auth, UUID) of
		ok -> 
		    reply_json(Req, User, State);
		_ ->
		    error_page(403, Req, State)
	    end;
	_ ->
	    error_page(403, Req, State)
    end;

	      

request('GET', [<<"my">>, <<"groups">>], Auth, Req, State) ->
    {ok, Res} = libsnarl:group_list(Auth),
    reply_json(Req, Res, State);

request('DELETE', [<<"my">>, <<"groups">>, Group], Auth, Req, State) ->
    case libsnarl:group_get(Auth, Group) of
	{ok, UUID} ->
	    case libsnarl:group_delete(Auth, UUID) of
		ok -> 
		    reply_json(Req, Group, State);
		_ ->
		    error_page(403, Req, State)
	    end;
	_ ->
	    error_page(403, Req, State)
    end;

request('POST', [<<"my">>, <<"groups">>], Auth, Req, State) ->
    {Vals, Req1} = cowboy_http_req:body_qs(Req),
    Name = proplists:get_value(<<"name">>, Vals),
    case libsnarl:group_add(Auth, Name) of
	{ok, _UUID} ->
	    reply_json(Req1, Name, State);
	_ ->
	    error_page(403, Req1, State)
    end;


request('GET', [<<"my">>, <<"groups">>, Group, <<"permissions">>], Auth, Req, State) ->
    case libsnarl:group_get(system, Group) of
	{ok, UUID} ->
	    {ok, Res} = libsnarl:group_permissions(Auth, UUID),
	    reply_json(Req, encode_permissions(Res), State);
	_ ->
	    error_page(403, Req, State)
    end;

request('POST', [<<"my">>, <<"groups">>, Group, <<"permissions">>], Auth, Req, State) ->
    case libsnarl:group_get(system, Group) of
	{ok, UUID} ->	    
	    {Vals, Req1} = cowboy_http_req:body_qs(Req),
	    JSON = proplists:get_value(<<"perms">>, Vals),
	    Perm = decode_permission(JSON),
	    libsnarl:group_grant(Auth, UUID, Perm),
	    {ok, Res} = libsnarl:group_permissions(Auth, UUID),
	    reply_json(Req1, encode_permissions(Res), State);
	_ ->
	    error_page(403, Req, State)
    end;

request('DELETE', [<<"my">>, <<"groups">>, Group, <<"permissions">>], Auth, Req, State) ->
    case libsnarl:group_get(system, Group) of
	{ok, UUID} ->	    
	    {Vals, Req1} = cowboy_http_req:body_qs(Req),
	    JSON = proplists:get_value(<<"perms">>, Vals),
	    Perm = decode_permission(JSON),
	    libsnarl:group_revoke(Auth, UUID, Perm),
	    {ok, Res} = libsnarl:group_permissions(Auth, UUID),
	    reply_json(Req1, encode_permissions(Res), State);
	_ ->
	    error_page(403, Req, State)
    end;

request('GET', [<<"my">>, <<"groups">>, Group, <<"users">>], Auth, Req, State) ->
    case libsnarl:user_get(system, Group) of
	{ok, UUID} ->
	    {ok, Res} = libsnarl:group_users(Auth, UUID),
	    reply_json(Req, Res, State);
	_ ->
	    error_page(403, Req, State)
    end;

request('GET', [<<"my">>, <<"networks">>, <<"admin">>], Auth, Req, State) ->
    Res = case libsnarl:network_get(Auth, <<"admin">>) of
	      {ok, {Network, Mask, Gateway, _}} ->
		  [{network, libsnarl:ip_to_str(Network)},
		   {netmask, libsnarl:ip_to_str(Mask)},
		   {gateway, libsnarl:ip_to_str(Gateway)}];
	      _ ->
		  [{network, <<"0.0.0.0">>},
		   {netmask, <<"0.0.0.0">>},
		   {gateway, <<"0.0.0.0">>}]		  
	  end,
    reply_json(Req, Res, State);

request('POST', [<<"my">>, <<"networks">>, <<"admin">>], Auth, Req, State) ->
    {Vals, Req1} = cowboy_http_req:body_qs(Req),
    First = libsnarl:parse_ip(proplists:get_value(<<"first">>, Vals)),
    Mask = libsnarl:parse_ip(proplists:get_value(<<"netmask">>, Vals)),
    Gateway = libsnarl:parse_ip(proplists:get_value(<<"gateway">>, Vals)),
    libsnarl:network_delete(Auth, <<"admin">>),
    case libsnarl:network_add(Auth, <<"admin">>, First, Mask, Gateway) of
	ok ->
	    {ok, {NewNetwork, NewMask, NewGateway, _}} = libsnarl:network_get(Auth, <<"admin">>),
	    Res = [{network, libsnarl:ip_to_str(NewNetwork)},
		   {netmask, libsnarl:ip_to_str(NewMask)},
		   {gateway, libsnarl:ip_to_str(NewGateway)}],
	    reply_json(Req1, Res, State);
	_ ->
	    error_page(403, Req, State)
    end;
    
request('GET', [<<"my">>, <<"machines">>], Auth, Req, State) ->
    {ok, Res} = libsniffle:list_machines(Auth),
    reply_json(Req, Res, State);

request('GET', [<<"my">>, <<"machines">>, UUID], Auth, Req, State) ->
    {ok, Res} = libsniffle:get_machine(Auth, UUID),
    reply_json(Req, Res, State);

request('POST', [<<"my">>, <<"machines">>, UUID], Auth, Req, State) ->
    {Vals, Req1} = cowboy_http_req:body_qs(Req),
    case cowboy_http_req:qs_val(<<"action">>, Req1) of
	{<<"start">>, _} ->
	    case proplists:get_value(<<"image">>, Vals) of
		undefined ->
		    libsniffle:start_machine(Auth, UUID);
		<<"">> ->
		    libsniffle:start_machine(Auth, UUID);
		Image ->
		    io:format("Image: ~p~n", [Image]),
		    libsniffle:start_machine(Auth, UUID, Image)
	    end;
	{<<"reboot">>, _} ->
	    libsniffle:reboot_machine(Auth, UUID);
	{<<"stop">>, __} ->
	    libsniffle:stop_machine(Auth, UUID)
    end,
    {ok, Res} = libsniffle:get_machine(Auth, UUID),
    reply_json(Req1, Res, State);

request('POST', [<<"my">>, <<"machines">>], Auth, Req, State) ->
    {Vals, Req1} = cowboy_http_req:body_qs(Req),
    Name = proplists:get_value(<<"name">>, Vals),
    Package = proplists:get_value(<<"package">>, Vals),
    Dataset = proplists:get_value(<<"dataset">>, Vals),
    Host = proplists:get_value(<<"host">>, Vals),
    case Host of
	<<"">> ->
	    libsniffle:create_machine(Auth, Name, Package, Dataset, [], []);
	_ ->
	    libsniffle:create_machine(Auth, Host, Name, Package, Dataset, [], [])
    end,
    reply_json(Req1, [], State);


request('DELETE', [<<"my">>, <<"machines">>, VMUUID], Auth, Req, State) ->
    case libsniffle:delete_machine(Auth, VMUUID) of
	ok ->
	    {ok, Req1} = cowboy_http_req:reply(200, [], <<"">>, Req),
	    {ok, Req1, State};
	Error ->
	    io:format("~p~n", [Error]),
	    {ok, Req1} = cowboy_http_req:reply(500, [], <<"error">>, Req),
	    {ok, Req1, State}
    end;

request('GET', [<<"my">>, <<"datasets">>], Auth, Req, State) ->
    {ok, Res} = libsniffle:list_datasets(Auth),
    reply_json(Req, Res, State);

request('GET', [<<"my">>, <<"packages">>], Auth, Req, State) ->
    {ok, Res} = libsniffle:list_packages(Auth),
    reply_json(Req, Res, State);


request('DELETE', [<<"my">>, <<"packages">>, Name], Auth, Req, State) ->
    case libsniffle:delete_package(Auth, Name) of
	ok ->
	    reply_json(Req, [{result, <<"ok">>}], State);
	_ ->
	    {ok, Req1} = cowboy_http_req:reply(500, [], <<"error">>, Req),
	    {ok, Req1, State}
    end;
	

request('POST', [<<"my">>, <<"packages">>], Auth, Req, State) ->
    {Vals, Req1} = cowboy_http_req:body_qs(Req),
    Name = proplists:get_value(<<"name">>, Vals),
    Memory = proplists:get_value(<<"memory">>, Vals),
    Disk = proplists:get_value(<<"disk">>, Vals),
    Swap = proplists:get_value(<<"swap">>, Vals),

    case libsniffle:create_package(Auth, Name, Disk, Memory, Swap) of
	{ok, Res} ->
	    reply_json(Req1, Res, State);
	_ ->
	    {ok, Req1} = cowboy_http_req:reply(500, [], <<"error">>, Req),
	    {ok, Req1, State}
    end;

request('GET', [<<"my">>, <<"images">>], Auth, Req, State) ->
    {ok, Res} = libsniffle:list_images(Auth),
    reply_json(Req, Res, State);


request(_, _Path, _Auth, Req, State) ->
    error_page(404, Req, State).

%%--------------------------------------------------------------------
%% @doc
%% @spec
%% @end
%%--------------------------------------------------------------------

terminate(_Req, _State) ->
    ok.

%%%===================================================================
%%% Internal functions
%%%===================================================================

reply_json(Req, Data, State) ->
    {ok, Req2} = cowboy_http_req:reply(200,
				       [{<<"Content-Type">>, <<"application/json">>}], 
				       jsx:to_json(Data), Req),
    {ok, Req2, State}.


page_permissions(Auth) ->
    {ok, User} = libsnarl:user_name(Auth, Auth),
    [{<<"user">>, User},
     {<<"home">>, libsnarl:allowed(Auth, Auth, [service, wiggle, module, home])},
     {<<"admin">>, libsnarl:allowed(Auth, Auth, [service, wiggle, module, admin])},
     {<<"analytics">>, libsnarl:allowed(Auth, Auth, [service, wiggle, module, analytics])},
     {<<"system">>, libsnarl:allowed(Auth, Auth, [service, wiggle, module, system])},
     {<<"about">>, libsnarl:allowed(Auth, Auth, [service, wiggle, module, about])},
     {<<"account">>, libsnarl:allowed(Auth, Auth, [service, wiggle, module, account])}].

error_page(ErrorCode, Req, State) ->
    {ok, Page} = case ErrorCode of 
		     404 ->
			 error404_dtl:render([]);
		     403 ->
			 error403_dtl:render([]);
		     _ ->
			 {ok, <<"">>}
		 end,
    {ok, Req1} = cowboy_http_req:reply(ErrorCode, [], Page, Req),
    {ok, Req1, State}.

encode_permission(Permission) ->
    [case Perm of 
	 P when is_atom(P) ->
	     [{<<"perm">>, ensure_binary(P)}];
	 P when is_binary(P) ->
	     [{<<"placeholder">>, ensure_binary(P)}]
     end || Perm <- Permission].
    

encode_permissions(Permissions) ->
    [encode_permission(P) || P <- Permissions].
    
    
decode_permission(JSON) ->
    [case Type of
	 <<"perm">> -> 
	     list_to_atom(binary_to_list(Value));
	 <<"placeholder">> ->
	     case Value of
		 <<"_">> ->
		     list_to_atom(binary_to_list(Value));
		 <<"...">> ->
		     list_to_atom(binary_to_list(Value));
		 _ ->
		     Value
	     end
     end || [{Type, Value}] <- jsx:to_term(JSON)].

ensure_binary(A) when is_atom(A) ->
    list_to_binary(atom_to_list(A));
ensure_binary(L) when is_list(L)->
    list_to_binary(L);
ensure_binary(B) when is_binary(B)->
    B.