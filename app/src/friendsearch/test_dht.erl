-module(test_dht).
-compile([export_all]).
-export([set/3, lookup/2, start/0, stop/1, init/1]).
-behaviour(gen_server).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

%% ------------------------------------------------------------------
%% gen_server exports
%% ------------------------------------------------------------------

-export([handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% ------------------------------------------------------------------
%% gen_server start/stop calls
%% ------------------------------------------------------------------

start() ->
  gen_server:start(?MODULE, [], []).

stop(Pid) ->
  gen_server:call(Pid, stop).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

set(Pid, Key, Entry) ->
  gen_server:call(Pid, {set, Key, Entry}),
  ok.

lookup(Pid, Key) ->
  gen_server:call(Pid, {lookup, Key}).

init(_Args) -> 
  {ok, []}.

handle_call({set, Key, Entry}, _From, State) ->
  {reply, ok, [{Key, Entry} | State]};

handle_call({lookup, Key}, _From, State) ->
  ReturnValue = case proplists:get_value(Key, State) of
    undefined -> [];
    Val -> [Val]
  end,
  {reply, ReturnValue, State};

handle_call(stop, _From, State) ->
  {stop, normal, ok, State}.

handle_cast(_Msg, State) ->
  {noreply, State}.

handle_info(_Info, State) ->
  {noreply, State}.

terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.
