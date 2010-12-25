%% @author Sebastian Probst Eide
%% @doc DataStore module for storing and retrieving values.
-module(datastore).

-include("../fs.hrl").

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([set/3, get/2, spring_cleaning/1]).
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
      io:format("Datastore is discarding record.~n"),
      State
  end.

%% @doc Returns a list of values for a given key. The list
%%     might potentially be empty.
-spec(get/2::(Key::key(), State::#datastore_state{}) 
    -> [#entry{}]).
get(Key, State) ->
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

%% ------------------------------------------------------------------
%% Tests
%% ------------------------------------------------------------------

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

test_state() ->
  #datastore_state{data = dict:new()}.

init_test() ->
  ?assertEqual(dict:new(), init()).

set_get_test() ->
  State = test_state(),
  Key = <<"Key">>,
  Value1 = test_utils:test_person_entry_1a(),
  Value2 = test_utils:test_person_entry_1b(),

  NewState = datastore:set(Key, Value1, State),
  ?assertEqual([Value1], datastore:get(Key, NewState)),

  NewState2 = datastore:set(Key, Value2, NewState),
  ?assertEqual([Value2, Value1],
      datastore:get(Key, NewState2)).

get_missing_key_test() ->
  State = test_state(),
  ?assertEqual([], datastore:get(<<"Key">>, State)),

  State2 = datastore:set(<<"Key2">>, #entry{}, State),
  ?assertEqual([], datastore:get(<<"Key">>, State2)).

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
  ?assert(lists:member(Record, get(<<"Key">>, NewState))).

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

-endif.
