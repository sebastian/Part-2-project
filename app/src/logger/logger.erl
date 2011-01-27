-module(logger).
-behaviour(gen_server).
-define(SERVER, ?MODULE).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-record(state, {
    filename,
    file,
    should_log_to_file,
    id_lookup,
    ip
  }).
%% ------------------------------------------------------------------
%% Public API
%% ------------------------------------------------------------------

-export([start_link/0, start/0, stop/0]).
-export([
    log/3,
    start_logging/0,
    stop_logging/0,
    get_data/0,
    clear_log/0,
    set_ip/1,
    set_mapping/2
  ]).

%% ------------------------------------------------------------------
%% PRIVATE API Function Exports
%% ------------------------------------------------------------------

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start() ->
  gen_server:start({local, ?SERVER}, ?MODULE, [], []).

start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

stop() ->
  gen_server:call(?MODULE, stop).

% Action should be one of:
%   start_lookup,
%   end_lookup,
%   route,
%   lookup_datastore,
%   set_datastore
log(NodeId, Key, Action) ->
  TimeNow = utilities:get_time(),
  gen_server:cast(?MODULE, {log, NodeId, Key, Action, TimeNow}).

start_logging() ->
  gen_server:call(?MODULE, start_logging).

stop_logging() ->
  gen_server:call(?MODULE, stop_logging).

get_data() ->
  gen_server:call(?MODULE, get_data).

clear_log() ->
  gen_server:call(?MODULE, clear_log).

set_ip(Ip) ->
  gen_server:call(?MODULE, {set_ip, Ip}).

set_mapping(Pid, Port) ->
  gen_server:call(?MODULE, {set_mapping, Pid, Port}).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(_Args) -> 
  Filename = "dht.log",
  State = #state{
    filename = Filename,
    should_log_to_file = false,
    id_lookup = dict:new()
  },
  {ok, State}.

%% Call:
handle_call(stop, _From, State) ->
  {stop, normal, ok, State};

handle_call(get_data, _From, #state{filename = Filename} = State) ->
  {ok, Data} = file:read_file(Filename),
  {reply, Data, State};

handle_call({set_ip, Ip}, _From, State) ->
  io:format("Got set_ip in logger"),
  {reply, ok, State#state{ip = Ip}};

handle_call({set_mapping, Pid, Port}, _From, #state{id_lookup = LookupTable} = State) ->
  NewLookupTable = dict:store(Pid, Port, LookupTable),
  {reply, ok, State#state{id_lookup = NewLookupTable}};

handle_call(clear_log, _From, #state{filename = Filename, should_log_to_file = Should} = State) ->
  close_file(State),
  file:delete(Filename),
  NewState = case Should of
    true -> 
      {ok, NewFile} = file:open(Filename, [append, delayed_write]),
      State#state{file = NewFile};
    false ->
      State
  end,
  {reply, ok, NewState};

handle_call(stop_logging, _From, State) ->
  close_file(State),
  NewState = State#state{should_log_to_file = false, file = undefined},
  {reply, ok, NewState};

handle_call(start_logging, _From, #state{filename = Filename} = State) ->
  {ok, File} = file:open(Filename, [append, delayed_write]),
  NewState = State#state{should_log_to_file = true, file = File},
  {reply, ok, NewState}.

%% Casts:
handle_cast({log, NodeId, Key, Action, TimeNow}, 
    #state{file = File, should_log_to_file = ShouldLogToFile, ip = {A,B,C,D}, id_lookup = Table} = State) ->
  Port = case dict:find(NodeId, Table) of
    {ok, Val} -> Val;
    error -> unknown
  end,
  Id = lists:flatten(io_lib:format("~p~p~p~p_~p", [A,B,C,D,Port])),
  case ShouldLogToFile of
    true ->
      LogEntry = lists:flatten(io_lib:format("~p;~p;~p;~p~n", [Key, TimeNow, Id, Action])),
      case file:write(File, LogEntry) of
        {error, Reason} ->
          error_logger:error_msg("Couldn't log because of ~p~n", [Reason]);
        ok -> ok
      end;
    false ->
      ok % Silent... Don't log visually
      %io:format("Node: ~p,  Key: ~p,  Action: ~p, Time: ~p~n", [Id, Key, Action, TimeNow])
  end,
  {noreply, State};
  
handle_cast(Msg, State) ->
  error_logger:error_msg("received unknown cast: ~p", [Msg]),
  {noreply, State}.

%% Info:
handle_info(_Info, State) ->
  {noreply, State}.

terminate(_Reason, State) ->
  close_file(State),
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

close_file(#state{file = File}) ->
  file:close(File).

%% ------------------------------------------------------------------
%% Tests
%% ------------------------------------------------------------------

-ifdef(TEST).

-endif.
