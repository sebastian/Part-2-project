%% @author Sebastian Probst Eide
%% @doc DataStore server module for storing and retrieving values.
-module(datastore_srv).
-behaviour(gen_server).
-define(SERVER, ?MODULE).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-include("../fs.hrl").

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([set/2, get/1, spring_cleaning/0]).
-export([start_link/0, start/0, stop/0]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2, terminate/2, code_change/3]).

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
-spec(get/1::(Key::key()) -> [#entry{}]).
get(Key) ->
  gen_server:call(?MODULE, {get, Key}).

%% @doc Filters out all items that have expired.
-spec(spring_cleaning/0::() -> ok).
spring_cleaning() ->
  gen_server:cast(?MODULE, spring_cleaning). 

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(_Args) -> 
  State = datastore:init(),
  {ok, State}.

%% Call:
handle_call({get, Key}, _From, State) ->
  {reply, datastore:get(Key, State), State};

handle_call({set, Key, Value}, _From, State) ->
  {ok, NewState} = datastore:set(Key, Value, State),
  {reply, ok, NewState};

handle_call(stop, _From, State) ->
  {stop, normal, ok, State}.

handle_cast(spring_cleaning, State) ->
  {noreply, datastore:spring_cleaning(State)}.

terminate(_Reason, _State) ->
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
  ?assertEqual([], datastore_srv:get(<<"unknown key">>)),
  ?assertEqual(ok, datastore_srv:set(<<"key">>, Value)),
  ?assertEqual([Value], datastore_srv:get(<<"key">>)),
  stop().

-endif.
