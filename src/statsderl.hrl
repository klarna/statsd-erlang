-ifndef(STATSDERL_HRL_).
-define(STATSDERL_HRL_, true).

-define(DEFAULT_PORT,           8125).
-define(DEFAULT_REPORTER_NAME,  default_statsd_reporter).
-define(DEFAULT_BASE_KEY,       undefined).
%% UDP payload size limit, not including the header
-define(MAX_PACKET_BYTES,       1024).
%% report every second by default
-define(MAX_REPORT_INTERVAL_MS, 1000).

%% in case not given, statsderl_sup starts without children
-define(DEFAULT_ARGS,
        [{hostname,               undefined},
         {port,                   ?DEFAULT_PORT},
         {name,                   ?DEFAULT_REPORTER_NAME},
         {base_key,               ?DEFAULT_BASE_KEY},
         {max_packet_bytes,       ?MAX_PACKET_BYTES},
         {max_report_interval_ms, ?MAX_REPORT_INTERVAL_MS}
        ]).
-endif.

