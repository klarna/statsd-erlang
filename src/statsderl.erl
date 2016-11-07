-module(statsderl).

%% public
-export([
    batch_report/2,
    batch_report/3,
    gauge/3,
    gauge/4,
    increment/3,
    increment/4,
    start_link/1,
    timing/3,
    timing/4,
    timing_fun/3,
    timing_fun/4,
    timing_now/3,
    timing_now/4
]).

-export([maybe_use_env/1]).

-behaviour(gen_server).

-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

-include("statsderl.hrl").

-type ipv4() :: {byte(), byte(), byte(), byte()}.

-record(state, { name     :: undefind | atom()
               , hostname :: ipv4() | string()
               , port     :: integer()
               , basekey  :: binary()
               , packet   :: statsderl_packet:packet()
               }).

%%%_* APIs =====================================================================

%% @doc Start reporter process. The process is registered to the given
%% name if it is found in the args.
%% @end
-spec start_link([{Key, any()}]) -> {ok, pid()} | {error, any()}
        when Key :: name | hostname | port | base_key |
                    max_packet_bytes | max_report_interval_ms.
start_link(Args0) ->
  Args = maybe_use_env(Args0),
  case lists:keyfind(name, 1, Args) of
    {name, RegName} ->
      gen_server:start_link({local, RegName}, ?MODULE, Args, []);
    false ->
      gen_server:start_link(?MODULE, Args, [])
  end.

%% @doc Maybe use env variables if the required arguments are not given.
-spec maybe_use_env([{atom(), any()}]) -> [{atom(), any()}].
maybe_use_env(Args) ->
  maybe_use_env([{hostname, undefined} | ?DEFAULT_ARGS], Args).

gauge(Key, Value, SampleRate) ->
  gauge(?DEFAULT_REPORTER_NAME, Key, Value, SampleRate).

gauge(Reporter, Key, Value, SampleRate) ->
  send_by_rate(Reporter, gauge, Key, Value, SampleRate).

increment(Key, Value, SampleRate) ->
  increment(?DEFAULT_REPORTER_NAME, Key, Value, SampleRate).

increment(Reporter, Key, Value, SampleRate) ->
  send_by_rate(Reporter, increment, Key, Value, SampleRate).

timing(Key, Value, SampleRate) ->
  timing(?DEFAULT_REPORTER_NAME, Key, Value, SampleRate).

timing(Reporter, Key, Value, SampleRate) ->
  send_by_rate(Reporter, timing, Key, Value, SampleRate).

timing_fun(Key, Fun, SampleRate) ->
  timing_fun(?DEFAULT_REPORTER_NAME, Key, Fun, SampleRate).

timing_fun(Reporter, Key, Fun, SampleRate) ->
  Timestamp = os:timestamp(),
  Result = Fun(),
  timing_now(Reporter, Key, Timestamp, SampleRate),
  Result.

timing_now(Key, Timestamp, SampleRate) ->
  timing_now(?DEFAULT_REPORTER_NAME, Key, Timestamp, SampleRate).

timing_now(Reporter, Key, Timestamp, SampleRate) ->
  timing(Reporter, Key, now_diff_ms(Timestamp), SampleRate).


%% @doc Report many metrics in one message.
%% Same sample rate is used for all metrics in the batch
%% @end
-spec batch_report([{Method, Key, Value}], SampleRate) -> ok
        when Method     :: increment | gauge | timing,
             Key        :: iodata(),
             Value      :: number(),
             SampleRate :: number().
batch_report(Metrics, SampleRate) ->
  batch_report(?DEFAULT_REPORTER_NAME, Metrics, SampleRate).

batch_report(Reporter, Metrics, SampleRate) ->
  eval_by_rate(SampleRate,
    fun() ->
      MapFun = fun({Method, Key, Value}) ->
                 iolist_to_binary(new_line(Method, Key, Value, SampleRate))
               end,
      Lines = lists:map(MapFun, Metrics),
      gen_server:cast(Reporter, {send, Lines})
    end).

%%%_* gen_server callbacks =====================================================

init(Args) ->
  ArgF = fun(Name) ->
           case lists:keyfind(Name, 1, Args) of
             {Name, Value} -> Value;
             false         -> erlang:error({arg_not_found, Name, Args})
           end
         end,
  Hostname = ArgF(hostname),
  Port = ArgF(port),
  Name = try ArgF(name)
           catch error : {arg_not_found, _, _} ->
              undefined
           end,
  BaseKey = iolist_to_binary(get_base_key(ArgF(base_key))),
  {ok, Socket} = gen_udp:open(0, [{active, false}]),
  Header = make_udp_header(Hostname, Port),
  SendFun =
    fun(Lines) ->
      true = erlang:port_command(Socket, [Header, Lines])
    end,
  Packet = statsderl_packet:new(ArgF(max_packet_bytes),
                                ArgF(max_report_interval_ms),
                                SendFun),
  State = #state{ name     = Name
                , hostname = Hostname
                , port     = Port
                , basekey  = BaseKey
                , packet   = Packet
                },
  {ok, State, statsderl_packet:get_timeout(Packet)}.

handle_call(_Request, _From, State) ->
  noreply(State).

handle_cast({send, Line}, State) ->
  noreply(maybe_send(State, Line));
handle_cast(_Msg, State) ->
  noreply(State).

handle_info(timeout, State) ->
  noreply(flush_send(State));
handle_info(_Info, State) ->
  noreply(State).

terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.


%%%_* Internal functions =======================================================

maybe_send(#state{} = State, Line) when is_binary(Line) ->
  maybe_send(State, [Line]);
maybe_send(#state{packet = Packet, basekey = BaseKey} = State, Lines) ->
  FoldFun = fun(Line, P) -> statsderl_packet:maybe_send(P, [BaseKey, Line]) end,
  NewPacket = lists:foldl(FoldFun, Packet, Lines),
  State#state{packet = NewPacket}.

flush_send(#state{packet = P} = State) ->
  NewPacket = statsderl_packet:flush_send(P),
  State#state{packet = NewPacket}.

noreply(#state{packet = P} = State) ->
  {noreply, State, statsderl_packet:get_timeout(P)}.

%% private
get_base_key(undefined) ->
  <<"">>;
get_base_key(hostname) ->
  {ok, Hostname} = inet:gethostname(),
  [Hostname, $.];
get_base_key(sname) ->
  Name = atom_to_list(node()),
  SName = string:sub_word(Name, 1, $@),
  [SName, $.];
get_base_key(name) ->
  Name = atom_to_list(node()),
  Value = re:replace(Name, "@", ".", [global, {return, list}]),
  [Value, $.];
get_base_key(Key) ->
  [Key, $.].

format_sample_rate(1) -> [];
format_sample_rate(SampleRate) ->
  ["|@", float_to_list(SampleRate, [{decimals, 3}])].

new_line(Type, Key, Value, SampleRate) when is_number(Value) ->
  ValueStr =
    case Value of
      _ when is_integer(Value) -> integer_to_list(Value);
      _ when is_float(Value)   -> float_to_list(Value, [{decimals, 3}])
    end,
  new_line(Type, Key, ValueStr, SampleRate);
new_line(increment, Key, Value, SampleRate) ->
  [Key, <<":">>, Value, <<"|c">> | format_sample_rate(SampleRate)];
new_line(timing, Key, Value, SampleRate) ->
  [Key, <<":">>, Value, <<"|ms">> | format_sample_rate(SampleRate)];
new_line(gauge, Key, Value, _SampleRate) ->
  [Key, <<":">>, Value, <<"|g">>].

eval_by_rate(Rate, _Fun) when Rate =< 0 -> ok;
eval_by_rate(Rate,  Fun) when Rate >= 1 -> Fun();
eval_by_rate(Rate,  Fun) ->
  case rand1000() =< Rate * 1000 of
    true  -> Fun();
    false -> ok
  end.

send_by_rate(Reporter, Method, Key, Value, SampleRate) ->
  eval_by_rate(SampleRate,
               fun() ->
                 send(Reporter, Method, Key, Value, SampleRate)
               end).

now_diff_ms(Timestamp) ->
  timer:now_diff(os:timestamp(), Timestamp) / 1000.

send(Reporter, Method, Key, Value, SampleRate) ->
  Line = new_line(Method, Key, Value, SampleRate),
  gen_server:cast(Reporter, {send, iolist_to_binary(Line)}).

-spec maybe_use_env([atom() | {atom(), any()}], [{atom(), any()}]) ->
        [{atom(), any()}].
maybe_use_env([], Args) ->
  Args;
maybe_use_env([{Name, DefaultValue} | Rest], Args) ->
  case lists:keyfind(Name, 1, Args) of
    false -> maybe_use_env(Rest, use_env_or_default(Name, DefaultValue, Args));
    _     -> maybe_use_env(Rest, Args)
  end.

%% @private Use application env variables in arg list.
use_env_or_default(Name, DefaultValue, Args) ->
  [{Name, get_env(Name, DefaultValue)} | Args].

%% @private Get application env variable,
%% return default value in case not found.
%% @end
-spec get_env(atom(), any()) -> any().
get_env(Name, DefaultValue) ->
  case application:get_env(statsderl, Name) of
    {ok, Value} -> Value;
    undefined   -> DefaultValue
  end.

-spec make_udp_header(string(), integer()) -> binary().
make_udp_header(Hostname, Port) ->
  {A, B, C, D} = lookup_hostname(Hostname),
  Tag = case is_otp_19_or_later() of
          true  -> 1; % see macro INET_AF_INET in kernel/src/inet_int.hrl
          false -> []
        end,
  iolist_to_binary(
    [ Tag
    , Port bsr 8
    , Port band 16#ff
    , A, B, C, D
    ]).

-spec is_otp_19_or_later() -> boolean().
is_otp_19_or_later() ->
  case erlang:system_info(otp_release) of
    "R"  ++ _ -> false;
    "19" ++ _ -> true;
    "1"  ++ _ -> false;
    _         -> true
  end.

lookup_hostname(Address) when is_tuple(Address) ->
  Address;
lookup_hostname(Hostname) ->
  case inet:gethostbyname(Hostname) of
    {ok, {_, _, _, _, _, [Address | _]}} ->
      Address;
    _Else ->
      {127, 0, 0, 1}
  end.

%% @private Return a random in range [0, 1000]
%% with precision of 3 digits after floating point.
%% @end
-spec rand1000() -> 0..1000.
rand1000() -> crypto:rand_uniform(0, 1001).

%%%_* Emacs ====================================================================
%%% Local Variables:
%%% allout-layout: t
%%% erlang-indent-level: 2
%%% End:
