-record(state, {
          module,
          path,
          method,
          version,
          token,
          content,
          reply,
          obj,
          body,
          start,
          path_bin,
          etag,
          %% If we don't have a scope aka don't use oatuh2 we always allow
          %% everything from a scope pov.
          cached_perms,
          scope_perms = [[<<"...">>]],
          full_list = false,
          full_list_fields=[]
         }).

-define(P(State), State#state.path_bin).
-define(MEx(Path, Service, Start), io_lib:format("~p~p", [Path, Start])).
%%-define(MEx(Path, Service, Start),
%%        statman_histogram:record_value({Path, {ext, Service}}, Start)).
-define(MSnarl(Path, Start), ?MEx(Path, <<"snarl">>, Start)).
-define(MSniffle(Path, Start), ?MEx(Path, <<"sniffle">>, Start)).
-define(MHowl(Path, Start), ?MEx(Path, <<"howl">>, Start)).
-define(M(Path, Start), ok).
-define(UUID(N), <<N:36/binary>>).

%-define(M(Path, Start), statman_histogram:record_value({Path, total}, Start)).
%-define(M(Path, Start), statman_histogram:record_value({Path, total}, Start)).
