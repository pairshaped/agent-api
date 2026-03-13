-module(time_ffi).
-export([system_time_seconds/0]).

system_time_seconds() ->
    erlang:system_time(second).
