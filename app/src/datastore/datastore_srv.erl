%% @author Sebastian Probst Eide
%% @doc DataStore server module for storing and retrieving values.
-module(datastore_srv).
-behaviour(gen_server).
-define(SERVER, ?MODULE).

% Clear out old data once every minute
-define(CLEAN_INTERVAL, 60 * 1000).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-include("../fs.hrl").

%% ------------------------------------------------------------------
%% PUBLIC API Function Exports
%% ------------------------------------------------------------------

-export([set/2, lookup/1, spring_cleaning/0, get_entries_in_range/2]).
-export([start_link/0, start/0, stop/0]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2, terminate/2, code_change/3, handle_info/2]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start() ->
  gen_server:start({local, ?SERVER}, ?MODULE, [], []).

start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

stop() ->
  gen_server:call(?SERVER, stop).

%% ------------------------------------------------------------------
%% Public API
%% ------------------------------------------------------------------

%% @doc Adds a value for a key. A key can contain several entries
-spec(set/2::(Key::key(), Value::#entry{}) -> ok).
set(Key, Value) ->
  gen_server:call(?MODULE, {set, Key, Value}).

%% @doc Returns a list of values for a given key. The list
%%     might potentially be empty.
-spec(lookup/1::(Key::key()) -> [#entry{}]).
lookup(Key) ->
  gen_server:call(?MODULE, {lookup, Key}).

%% @doc Filters out all items that have expired.
-spec(spring_cleaning/0::() -> ok).
spring_cleaning() ->
  gen_server:cast(?MODULE, spring_cleaning). 

% @doc Returns all entries with keys greater than start, and less than
% or equal to end.
-spec(get_entries_in_range/2::(Start::key(), End::key()) -> [#entry{}]).
get_entries_in_range(Start, End) ->
  gen_server:call(?MODULE, {get_entries_in_range, Start, End}).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(_Args) -> 
  {ok, TimerRef} = timer:apply_interval(?CLEAN_INTERVAL, ?MODULE, spring_cleaning, []),
  {ok, #datastore_state{timer = TimerRef, data = datastore:init()}}.

handle_call({get_entries_in_range, Start, End}, _From, State) ->
  {reply, datastore:get_entries_in_range(Start, End, State), State};

handle_call({lookup, Key}, _From, State) ->
  {reply, datastore:lookup(Key, State), State};

handle_call({set, Key, Value}, _From, State) ->
  {reply, ok, datastore:set(Key, Value, State)};

handle_call(get_state, _From, State) ->
  {reply, State, State};

handle_call(stop, _From, State) ->
  {stop, normal, ok, State}.

handle_cast(spring_cleaning, State) ->
  {noreply, datastore:spring_cleaning(State)}.

handle_info(_Info, State) ->
  {noreply, State}.

terminate(_Reason, State) ->
  timer:cancel(State#datastore_state.timer),
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%% ------------------------------------------------------------------
%% Tests
%% ------------------------------------------------------------------

-ifdef(TEST).

datastore_srv_integration_test() ->
  start(),
  Value = #entry{timeout = utilities:get_time() + 20},
  ?assertEqual([], datastore_srv:lookup(<<"unknown key">>)),
  ?assertEqual(ok, datastore_srv:set(<<"key">>, Value)),
  ?assertEqual([Value], datastore_srv:lookup(<<"key">>)),
  ?assertEqual([], datastore_srv:lookup(<<"unknown key">>)),
  stop().

-endif.
