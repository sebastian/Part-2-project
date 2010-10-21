%% @author Sebastian Probst Eide
%% @doc DataStore module for storing and retrieving values.
-module(datastore).

-export([set/3, get/2, clean/1]).

-include("records.hrl").

%% @doc Adds a value for a key. A key can contain several entries
-spec(set/3::(Key::key(), Value::#entry{}, State::dict()) -> {ok, dict()}).
set(Key, Value, State) ->
  case dict:find(Key, State) of
    {ok, Record} ->
      {ok, dict:store(Key, [Value | Record], State)};
    error -> 
      {ok, dict:store(Key, [Value], State)} 
  end.

%% @doc Returns a list of values for a given key. The list
%%     might potentially be empty.
-spec(get/2::(Key::key(), State::dict()) -> {[#entry{}], dict()}).
get(Key, State) ->
  case dict:find(Key, State) of
    {ok, ValueList} ->
      {ValueList, State};
    error ->
      {[], State}
  end.

%% @doc Filters out all items that have expired.
-spec(clean/1::(State::dict()) -> {ok, dict()}).
clean(State) ->
  %% @todo: implement functionality that
  %%     removes all items that are too old.
  {ok, State}.


%%
%% Tests
%%

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

set_get_test() ->
  Dict = dict:new(),
  Key = <<"Key">>,
  Value1 = #entry{key = Key, name = <<"Name1">>},
  Value2 = #entry{key = Key, name = <<"Name2">>},

  {ok, NewDict} = datastore:set(Key, Value1, Dict),
  ?assertEqual({[Value1], NewDict}, datastore:get(Key, NewDict)),

  {ok, NewDict2} = datastore:set(Key, Value2, NewDict),
  ?assertEqual({[Value2, Value1], NewDict2},
      datastore:get(Key, NewDict2)).

get_missing_key_test() ->
  Dict = dict:new(),
  ?assertEqual({[], Dict}, datastore:get(<<"Key">>, Dict)),

  {ok, Dict2} = datastore:set(<<"Key2">>, #entry{}, dict:new()),
  ?assertEqual({[], Dict2}, datastore:get(<<"Key">>, Dict2)).
      
clean_test() ->
  %% @todo: implement test that ensures old items are removed.
  ok.

-endif.
