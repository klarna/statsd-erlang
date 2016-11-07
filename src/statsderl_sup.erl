-module(statsderl_sup).

%% public
-export([
    start_link/0
]).

-behaviour(supervisor).
-export([
    init/1
]).

-include("statsderl.hrl").

%% @doc Start supervisor for the default statsd reporter.
start_link() ->
  Args = application:get_all_env(?APPLICATION),
  supervisor:start_link({local, ?MODULE}, ?MODULE, Args).

%% supervisor callbacks
init(Args) ->
  NewArgs = statsderl:maybe_use_env(Args),
  case get_arg(hostname, NewArgs) of
      undefined ->
          %% No statsd server hostname configured in app env,
          %% start the supervisor empty.
          {ok, {{one_for_one, 5, 10}, []}};
      _ ->
          {ok, {{one_for_one, 5, 10}, child_specs(NewArgs)}}
  end.

%% @private Make children spec.
child_specs(Args) ->
  [ { _Id       = get_arg(name, Args),
      _Start    = {statsderl, start_link, [Args]},
      _Restart  = permanent,
      _Shutdown = 5000,
      _Type     = worker,
      _Modules  = [statsderl]
    } ].

get_arg(Name, Args) ->
  case lists:keyfind(Name, 1, Args) of
    {Name, Value} -> Value;
    false         -> erlang:error({badarg, Name, Args})
  end.

%%%_* Emacs ====================================================================
%%% Local Variables:
%%% allout-layout: t
%%% erlang-indent-level: 2
%%% End:
