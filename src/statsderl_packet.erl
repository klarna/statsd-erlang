
-module(statsderl_packet).

-export([ new/3
        , maybe_send/2
        , flush_send/1
        , get_timeout/1
        ]).

-export_type([ packet/0 ]).

-record(packet,
        { max_bytes %% maximum bytes for the payload (header not included)
        , max_age_micro %% maximum time to keep buffering metrics
        , send_fun %% sned function to send the payload
        , data = [] %% Accumulated payload (metrics) to be sent
        , bytes = 0 %% Accumulated payload size
        , birth_micro = os_micro_now() %% time when the packet was created
        }).

-opaque packet() :: #packet{}.

%%%_* APIs =====================================================================

%% @doc Return timeout after wich the packet reaches max age.
-spec get_timeout(packet()) -> timer:time().
get_timeout(#packet{ birth_micro = BirthMicro
                   , max_age_micro = MaxAgeMicro
                   }) ->
  Now = os_micro_now(),
  case (MaxAgeMicro - (Now - BirthMicro)) of
    T when T < 1000 -> 0;
    T               -> T div 1000
  end.

%% @doc Initialize a new packet.
-spec new(pos_integer(), non_neg_integer(), fun((iodata()) -> ok)) -> packet().
new(MaxBytes, MaxAgeMs, SendFun) when is_integer(MaxBytes) andalso
                                      is_integer(MaxAgeMs) ->
  true = (MaxAgeMs > 0), %% assert
  do_new(MaxBytes, MaxAgeMs * 1000, SendFun).

%% @doc Send if packet size reaches limit.
-spec maybe_send(packet(), iodata()) -> packet().
maybe_send(P, Line) when is_list(Line) ->
  maybe_send(P, iolist_to_binary(Line));
maybe_send(P, <<>>) ->
  %% no data to send, maybe send by timeout
  maybe_send(P);
maybe_send(#packet{max_bytes = Max} = P, Line) when size(Line) > Max ->
  %% larger than limit, flush first
  error_logger:error_msg(
    "discarded due to packet size overflow:\nmetric=~p", [Line]),
  maybe_send(P);
maybe_send(#packet{ bytes     = Bytes
                  , data      = Data
                  , max_bytes = MaxBytes
                  } = P, Line) when is_binary(Line) ->
  NewBytes = concatenated_size(Bytes, size(Line)),
  case NewBytes > MaxBytes of
    true ->
      %% appending this line would overflow the packet size
      %% send it right away
      NewP = flush_send(P),
      maybe_send(NewP, Line);
    false ->
      NewP = P#packet{ data  = concatenate(Data, Line)
                     , bytes = NewBytes
                     },
      maybe_send(NewP)
  end.

%% @doc Send if packet age reaches limit.
-spec maybe_send(packet()) -> packet().
maybe_send(#packet{} = P) ->
  case get_timeout(P) =:= 0 of
    true  -> flush_send(P);
    false -> P
  end.

%% @doc Flush all accumulated lines.
-spec flush_send(packet()) -> packet().
flush_send(#packet{ data          = Data
                  , bytes         = Bytes
                  , max_bytes     = MaxBytes
                  , max_age_micro = MaxAgeMicro
                  , send_fun      = SendFun
                  }) ->
  Bytes > 0 andalso SendFun(Data),
  do_new(MaxBytes, MaxAgeMicro, SendFun).

%%%_* Internal functions =======================================================

%% @private Create a new packet.
do_new(MaxBytes, MaxAgeMicro, SendFun) ->
  #packet{ max_bytes     = MaxBytes
         , max_age_micro = MaxAgeMicro
         , send_fun      = SendFun
         , data          = []
         , bytes         = 0
         , birth_micro   = os_micro_now()
         }.

%% @private Packet size after the new line is concatenated.
concatenated_size(0, NewLineBytes) -> NewLineBytes;
concatenated_size(AccumulatedBytes, NewLineBytes) ->
  AccumulatedBytes + NewLineBytes + 1.

%% @private Concatenate the new line to accumulated lines.
concatenate([], Line)       -> [Line];
concatenate(AccLines, Line) -> [AccLines, $\n, Line].

%% @private Get current timestamp.
-spec os_micro_now() -> integer().
os_micro_now() ->
    {Mega, Sec, Micro} = os:timestamp(),
    ((Mega * 1000000) + Sec) * 1000000 + Micro.

%%%_* Emacs ====================================================================
%%% Local Variables:
%%% allout-layout: t
%%% erlang-indent-level: 2
%%% End:
