%% @author Sebastian Probst Eide
%% @doc DataStore module for storing and retrieving values.
-module(datastore).

-include("../fs.hrl").

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([set/3, lookup/2, spring_cleaning/1, get_entries_in_range/3]).
-export([init/0]).

%% ------------------------------------------------------------------
%% Public API
%% ------------------------------------------------------------------

init() ->
  dict:new().

%% @doc Adds a value for a key. A key can contain several entries
-spec(set/3::(Key::key(), Value::#entry{}, State::#datastore_state{}) 
    -> #datastore_state{}).
set(Key, Value, State) ->
  Data = State#datastore_state.data,
  Timeout = Value#entry.timeout,
  CurrTime = utilities:get_time(),
  case (Timeout > CurrTime andalso Timeout =< (CurrTime + ?ENTRY_TIMEOUT)) of
    true ->
      NewData = case dict:find(Key, Data) of
        {ok, Record} ->
          dict:store(Key, [Value | Record], Data);
        error -> 
          dict:store(Key, [Value], Data) 
      end,
      State#datastore_state{data = NewData};
    _ ->
      State
  end.

%% @doc Returns a list of values for a given key. The list
%%     might potentially be empty.
-spec(lookup/2::(Key::key(), State::#datastore_state{}) 
    -> [#entry{}]).
lookup(Key, State) ->
  io:format("Looking up ~p in datastore~n", [Key]),
  Data = State#datastore_state.data,
  case dict:find(Key, Data) of
    {ok, ValueList} ->
      ValueList;
    error ->
      []
  end.

%% @doc Filters out all items that have expired.
-spec(spring_cleaning/1::(State::#datastore_state{}) 
    -> {ok, #datastore_state{}}).
spring_cleaning(State) ->
  CurrentTime = utilities:get_time(),
  WithoutOldEntries = 
      dict:map(fun(_Key, Entries) -> 
          [Entry || Entry <- Entries, Entry#entry.timeout > CurrentTime] 
      end, State#datastore_state.data),
  WithoutEmtpyKeys = 
      dict:filter(fun(_Key, []) -> false; (_, _) -> true end, WithoutOldEntries), 
  State#datastore_state{data = WithoutEmtpyKeys}.

% @doc: Returns the data for all items with a key greater than start and less
% than or equal to end.
-spec(get_entries_in_range/3::(Start::key(), End::key(), State::#datastore_state{}) -> [#entry{}]).
get_entries_in_range(Start, End, State) ->
  Entries = dict:to_list(State#datastore_state.data),
  apply_range(Start, End, lists:flatten([E || {_Key, E} <- Entries])).
apply_range(Start, End, Entries) when Start < End ->
  [Entry || Entry <- Entries, Entry#entry.key > Start, Entry#entry.key =< End];
apply_range(Start, End, Entries) ->
  [Entry || Entry <- Entries, Entry#entry.key > Start orelse Entry#entry.key =< End].



%% ------------------------------------------------------------------
%% Tests
%% ------------------------------------------------------------------

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

test_state() ->
  #datastore_state{data = dict:new()}.

init_test() ->
  ?assertEqual(dict:new(), init()).

set_lookup_test() ->
  State = test_state(),
  Key = <<"Key">>,
  Value1 = test_utils:test_person_entry_1a(),
  Value2 = test_utils:test_person_entry_1b(),

  NewState = datastore:set(Key, Value1, State),
  ?assertEqual([Value1], datastore:lookup(Key, NewState)),

  NewState2 = datastore:set(Key, Value2, NewState),
  ?assertEqual([Value2, Value1],
      datastore:lookup(Key, NewState2)).

lookup_test() ->
  State = test_state(),
  ?assertEqual([], datastore:lookup(<<"Key">>, State)),

  State2 = datastore:set(<<"Key2">>, #entry{}, State),
  ?assertEqual([], datastore:lookup(<<"Key">>, State2)).

set_should_drop_outdated_records_test() ->
  State = test_state(),
  OldTime = utilities:get_time() - 10,
  TimedoutPerson = (test_utils:test_person_entry_1a())#entry{timeout = OldTime},
  NewState = set(<<"Key">>, TimedoutPerson, State),
  ?assertEqual(dict:size(State#datastore_state.data), 
      dict:size(NewState#datastore_state.data)).

set_should_drop_records_with_too_high_timeout_test() ->
  State = test_state(),
  TimeInFarFuture = utilities:get_time() + 10 * ?ENTRY_TIMEOUT, 
  IllegalRecord = (test_utils:test_person_entry_1a())#entry{timeout = TimeInFarFuture},
  NewState = set(<<"Key">>, IllegalRecord, State),
  ?assertEqual(dict:size(State#datastore_state.data), 
      dict:size(NewState#datastore_state.data)).

set_should_accept_records_with_timeout_starting_at_the_current_time_test() ->
  CurrentTime = utilities:get_time(),
  State = test_state(),
  Record = (test_utils:test_person_entry_1a())#entry{timeout = CurrentTime + ?ENTRY_TIMEOUT},
  
  erlymock:start(),
  erlymock:strict(utilities, get_time, [], [{return, CurrentTime}]),
  erlymock:replay(), 
  NewState = set(<<"Key">>, Record, State),
  erlymock:verify(),

  % It should have accepted the record
  ?assert(lists:member(Record, lookup(<<"Key">>, NewState))).

spring_cleaning_test() ->
  OldTime = utilities:get_time() - 10,
  FutureTime = utilities:get_time() + 10,
  State = test_state(),
  TimedoutPerson = (test_utils:test_person_entry_1a())#entry{timeout = OldTime},
  ValidPerson = (test_utils:test_person_entry_1a())#entry{timeout = FutureTime},

  Key = <<"Key">>,

  UpdatedState1 = State#datastore_state{
    data = dict:store(Key, [TimedoutPerson], State#datastore_state.data)
  },
  ?assertEqual(1, dict:size(UpdatedState1#datastore_state.data)),
  UpdatedState2 = datastore:spring_cleaning(UpdatedState1),
  ?assertEqual(0, dict:size(UpdatedState2#datastore_state.data)),

  UpdatedState3 = State#datastore_state{
      data = dict:store(Key, [ValidPerson], State#datastore_state.data)},
  ?assertEqual(1, dict:size(UpdatedState3#datastore_state.data)),
  UpdatedState4 = datastore:spring_cleaning(UpdatedState3),
  ?assertEqual(1, dict:size(UpdatedState4#datastore_state.data)).

entry_with_valid_timeout_and_key(Key) ->
  #entry{timeout = utilities:get_time() + 10, key = Key}.

assert_exclusively_contains_entries(Entries, Test) ->
  [?assert(lists:member(E, Test)) || E <- Entries],
  ?assertEqual(Test -- Entries, Entries -- Test).

get_entries_in_range_test() ->
  % State with entries with keys from 1 through 10
  Entries = [entry_with_valid_timeout_and_key(K) || K <- lists:seq(1,10)],
  State = lists:foldl(fun(E,A) -> datastore:set(E#entry.key, E, A) end, #datastore_state{data=datastore:init()}, Entries),
  
  % Out of range
  assert_exclusively_contains_entries([], get_entries_in_range(100, 9999, State)),
  % Normal direction
  assert_exclusively_contains_entries(Entries, get_entries_in_range(0, 100, State)),
  assert_exclusively_contains_entries(Entries, get_entries_in_range(0, 10, State)),
  assert_exclusively_contains_entries(lists:sublist(Entries, 2, 9), get_entries_in_range(1, 10, State)),
  assert_exclusively_contains_entries(lists:sublist(Entries, 1, 1), get_entries_in_range(0, 1, State)),
  % When start is after end (remember chord's keyspace is on a circle so this will happen!)
  assert_exclusively_contains_entries(Entries, get_entries_in_range(100000, 100, State)),
  assert_exclusively_contains_entries(lists:sublist(Entries, 1, 1) ++ lists:sublist(Entries, 10, 1), 
    get_entries_in_range(9, 1, State)).

-endif.
