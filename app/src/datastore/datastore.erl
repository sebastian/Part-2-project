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
-spec(set/3::(Key::key(), Value::#entry{}, State::dict()) -> dict()).
set(Key, Value, State) ->
  Timeout = Value#entry.timeout,
  CurrTime = utilities:get_time(),
  case (Timeout > CurrTime andalso Timeout < (CurrTime + ?ENTRY_TIMEOUT)) of
    true ->
      case dict:find(Key, State) of
        {ok, Record} ->
          {ok, dict:store(Key, [Value | Record], State)};
        error -> 
          {ok, dict:store(Key, [Value], State)} 
      end;
    _ ->
      {ok, State}
  end.

%% @doc Returns a list of values for a given key. The list
%%     might potentially be empty.
-spec(get/2::(Key::key(), State::dict()) -> [#entry{}]).
get(Key, State) ->
  case dict:find(Key, State) of
    {ok, ValueList} ->
      ValueList;
    error ->
      []
  end.

%% @doc Filters out all items that have expired.
-spec(spring_cleaning/1::(State::dict()) -> dict()).
spring_cleaning(State) ->
  CurrentTime = utilities:get_time(),
  WithoutOldEntries = 
      dict:map(fun(_Key, Entries) -> 
          [Entry || Entry <- Entries, Entry#entry.timeout > CurrentTime] 
      end, State),
  WithoutEmtpyKeys = dict:filter(fun(_Key, []) -> false; (_, _) -> true end, WithoutOldEntries), 
  {ok, WithoutEmtpyKeys}.

%% ------------------------------------------------------------------
%% Tests
%% ------------------------------------------------------------------

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

init_test() ->
  ?assertEqual(dict:new(), init()).

set_get_test() ->
  Dict = dict:new(),
  Key = <<"Key">>,
  Value1 = test_utils:test_person_entry_1a(),
  Value2 = test_utils:test_person_entry_1b(),

  {ok, NewDict} = datastore:set(Key, Value1, Dict),
  ?assertEqual([Value1], datastore:get(Key, NewDict)),

  {ok, NewDict2} = datastore:set(Key, Value2, NewDict),
  ?assertEqual([Value2, Value1],
      datastore:get(Key, NewDict2)).

get_missing_key_test() ->
  Dict = dict:new(),
  ?assertEqual([], datastore:get(<<"Key">>, Dict)),

  {ok, Dict2} = datastore:set(<<"Key2">>, #entry{}, dict:new()),
  ?assertEqual([], datastore:get(<<"Key">>, Dict2)).

set_should_drop_outdated_records_test() ->
  Dict = dict:new(),
  OldTime = utilities:get_time() - 10,
  TimedoutPerson = (test_utils:test_person_entry_1a())#entry{timeout = OldTime},
  {ok, NewDict} = set(<<"Key">>, TimedoutPerson, Dict),
  ?assertEqual(dict:size(Dict), dict:size(NewDict)).

set_should_drop_records_with_too_high_timeout_test() ->
  Dict = dict:new(),
  TimeInFarFuture = utilities:get_time() + 10 * ?ENTRY_TIMEOUT, 
  IllegalRecord = (test_utils:test_person_entry_1a())#entry{timeout = TimeInFarFuture},
  {ok, NewDict} = set(<<"Key">>, IllegalRecord, Dict),
  ?assertEqual(dict:size(Dict), dict:size(NewDict)).

spring_cleaning_test() ->
  OldTime = utilities:get_time() - 10,
  FutureTime = utilities:get_time() + 10,
  Dict = dict:new(),
  TimedoutPerson = (test_utils:test_person_entry_1a())#entry{timeout = OldTime},
  ValidPerson = (test_utils:test_person_entry_1a())#entry{timeout = FutureTime},

  Key = <<"Key">>,

  UpdatedDict1 = dict:store(Key, [TimedoutPerson], Dict),
  ?assertEqual(1, dict:size(UpdatedDict1)),
  {ok, UpdatedDict2} = datastore:spring_cleaning(UpdatedDict1),
  ?assertEqual(0, dict:size(UpdatedDict2)),

  UpdatedDict3 = dict:store(Key, [ValidPerson], Dict),
  ?assertEqual(1, dict:size(UpdatedDict3)),
  {ok, UpdatedDict4} = datastore:spring_cleaning(UpdatedDict3),
  ?assertEqual(1, dict:size(UpdatedDict4)).

-endif.
