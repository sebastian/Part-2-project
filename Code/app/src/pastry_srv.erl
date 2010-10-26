-module(pastry_srv).
-behaviour(gen_server).
-define(SERVER, ?MODULE).
% Chord specific configuration parameters:
% ParamB should be a number that evenly divides 160.
%     It affects the number of rows in the routing table
%     and how many records are kept in each row.
-define(ParamB, 4).
-include("fs.hrl").

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/0]).
-export([get/1, set/2]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

-spec(get/1::(Key::key()) -> [#entry{}]).
get(Key) ->
  gen_server:call({get, Key}).

-spec(set/2::(Key::key(), Entry::#entry{}) -> ok | {error, server}).
set(Key, Entry) ->
  gen_server:call({set, Key, Entry}).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(Args) -> 
  % Check that the B parameter is valid.
  0 = 160 rem ?ParamB,

  {ok, Args}.

handle_call(stop, _From, State) ->
  {stop, stop_signal, ok, State};

handle_call({get, _Key}, _From, State) ->
  % Do lookup
  Results = some_call,
  {reply, Results, State};

handle_call({set, _Key, _Entry}, _From, State) ->
  % Store value in network
  {reply, ok, State}.

handle_cast(_Msg, State) ->
  {noreply, State}.

handle_info(_Info, State) ->
  {noreply, State}.

terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

%% ------------------------------------------------------------------
%% Tests
%% ------------------------------------------------------------------
