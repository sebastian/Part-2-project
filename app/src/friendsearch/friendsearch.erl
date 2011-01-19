%% @author Sebastian Probst Eide
%% @doc DataStore module for storing and retrieving values.
-module(friendsearch).

-define(LINK_NAME_CHUNKS, 3).

-include("../fs.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([list/1, add/2, delete/2, find/2, keep_alive/1]).
-export([lookup_link/3, get_item/3]).
-export([init/1]).

%% ------------------------------------------------------------------
%% Public API
%% ------------------------------------------------------------------

init(Dht) -> 
  #friendsearch_state{
    dht = Dht,
    entries = [],
    link_entries = []
  }.

-spec(list/1::(State::#friendsearch_state{}) -> [#entry{}]).
list(State) -> 
  [E#entry.data || E <- State#friendsearch_state.entries].

-spec(add/2::(Person::#person{}, State::#friendsearch_state{}) -> #friendsearch_state{}).
add(Person, State) -> 
  AllPersonEntries = State#friendsearch_state.entries,
  AllLinkEntries = State#friendsearch_state.link_entries,
  DhtPid = State#friendsearch_state.dht_pid,

  % Create entry for person record
  Entry = utilities:entry_for_record(Person),

  % Create main link entry for person that she can be found under
  MainLink = #link{
    name_fragment = Person#person.name,
    name = Person#person.name,
    profile_key = Entry#entry.key
  },
  MainLinkEntry = utilities:entry_for_record(MainLink),
  LinkEntries = [MainLinkEntry | generate_link_items(Entry)],

  % Add all entries to the Dht
  AllEntries = [Entry | LinkEntries],
  Dht = State#friendsearch_state.dht,
  [spawn(fun() -> Dht:set(DhtPid, E#entry.key, E) end) || E <- AllEntries],

  % Update state
  State#friendsearch_state{
    entries = [Entry | AllPersonEntries],
    link_entries = AllLinkEntries ++ LinkEntries
  }.

-spec(delete/2::(Key::key(), State::#friendsearch_state{}) -> #friendsearch_state{}).
delete(Key, State = #friendsearch_state{entries = Entries}) -> 
  State#friendsearch_state{entries =
    lists:filter(fun(#entry{key=K}) when K =:= Key -> false; (_) -> true end,
        Entries)
  }.

-spec(find/2::(Query::bitstring(), State::#friendsearch_state{}) -> [#entry{}]).
find([], _State) -> [];
find(Query, State) ->
  KeyForQuery = utilities:key_for_normalized_string(Query),
  SearchKeysWithScore = [{KeyForQuery, 10} | 
      [{utilities:key_for_normalized_string(K), 1} || K <-name_subsets(Query)]],
  #friendsearch_state{dht = Dht, dht_pid = DhtPid} = State,
  % Look up keys in Dht
  Entries = lists:flatten(rpc:pmap({friendsearch, get_item}, [Dht, DhtPid], SearchKeysWithScore)),
  EntriesToLookUp = profile_list_by_priority(Entries),
  [E#entry.data || E <- 
    lists:flatten(rpc:pmap({friendsearch, lookup_link}, [Dht, DhtPid], EntriesToLookUp)),
      is_record(E#entry.data, person)].

-spec(keep_alive/1::(State::#friendsearch_state{}) -> #friendsearch_state{}).
keep_alive(#friendsearch_state{dht_pid = DhtPid} = State) ->
  TimeNow = utilities:get_time(),
  Entries = lists:map(fun(Entry) -> 
      case (Entry#entry.timeout < TimeNow + 60)of
        true -> 
          % Times out within a minute. Update it
          UpdatedEntry = Entry#entry{timeout = TimeNow + ?ENTRY_TIMEOUT},
          Dht = State#friendsearch_state.dht,
          Dht:set(DhtPid, UpdatedEntry#entry.key, UpdatedEntry),
          UpdatedEntry;
        false ->
          Entry
      end
    end, State#friendsearch_state.entries),
  State#friendsearch_state{entries = Entries}.

%% ------------------------------------------------------------------
%% Private methods
%% ------------------------------------------------------------------

get_item({Key, Score}, Dht, DhtPid) ->
  [{(E#entry.data)#link.profile_key, Score} || E <- Dht:lookup(DhtPid, Key)].

profile_list_by_priority(PropList) ->
  ScoreDict = lists:foldl(
    fun({Key, Score}, Dict) ->
        case dict:find(Key, Dict) of
          {ok, ExistingScore} ->
            dict:store(Key, ExistingScore + Score, Dict);
          error -> dict:store(Key, Score, Dict)
        end
    end, dict:new(), PropList),
  [Key || {Key, _Score} <- 
    lists:sort(fun({_, SA}, {_, SB}) -> SA >= SB end, dict:to_list(ScoreDict))].
  

%% @doc: if the element is a link, then the corresponding record is
%% looked up in the Dht network.
-spec(lookup_link/3::(Key::key(), _, pid()) -> #entry{}).
lookup_link(Key, Dht, DhtPid) -> 
  Dht:lookup(DhtPid, Key).


-spec(generate_link_items/1::(Person::#person{}) -> [#entry{}]).
generate_link_items(#entry{key = Key, data = Person}) ->
  [utilities:entry_for_record(#link{
      name_fragment = Frag,
      name = Person#person.name,
      profile_key = Key
    }) || Frag <- name_subsets(Person)].

name_subsets(#person{name = Name}) ->
  name_subsets(Name);
name_subsets(Name) ->
  ListName = utilities:string_to_list(utilities:downcase_str(Name)),
  Words = lists:foldl(fun(W, A) -> get_parts(W,A) end, [], string:tokens(ListName, " ")),
  lists:map(fun(E) -> list_to_bitstring(E) end, Words).

get_parts(Name, Acc) ->
  get_parts(Name, ?LINK_NAME_CHUNKS, Acc).
get_parts(Name, Place, Acc) ->
  case (Place < string:len(Name)) of
    true -> get_parts(Name, Place + ?LINK_NAME_CHUNKS, [string:left(Name, Place) | Acc]);
    false -> 
      [Name | Acc]
  end.

%% ------------------------------------------------------------------
%% Tests
%% ------------------------------------------------------------------

-ifdef(TEST).

get_parts_test() ->
  Parts = get_parts("sebastian", []),
  ?assert(lists:member("seb", Parts)),
  ?assert(lists:member("sebast", Parts)),
  ?assert(lists:member("sebastian", Parts)),
  
  Parts2 = get_parts("eide", []),
  ?assert(lists:member("eid", Parts2)),
  ?assert(lists:member("eide", Parts2)).

name_permutations_test() ->
  Person = #person{name = <<"Sebastian Probst Eide">>},
  NameClippings = name_subsets(Person),
  ?assert(lists:member(<<"seb">>, NameClippings)),
  ?assert(lists:member(<<"sebast">>, NameClippings)),
  ?assert(lists:member(<<"sebastian">>, NameClippings)),
  ?assert(lists:member(<<"pro">>, NameClippings)),
  ?assert(lists:member(<<"probst">>, NameClippings)),
  ?assert(lists:member(<<"eid">>, NameClippings)),
  ?assert(lists:member(<<"eide">>, NameClippings)).

contains_link_for_namefrag(Frag, List) ->
  proplists:get_value(Frag, [{(E#entry.data)#link.name_fragment, true} || E <- List], false).

generate_link_items_test() ->
  Person = test_utils:test_person_sebastianA(),
  Entry = utilities:entry_for_record(Person),
  Entries = generate_link_items(Entry),
  ?assert(contains_link_for_namefrag(<<"seb">>, Entries)),
  ?assert(contains_link_for_namefrag(<<"sebast">>, Entries)),
  ?assert(contains_link_for_namefrag(<<"sebastian">>, Entries)),
  ?assert(contains_link_for_namefrag(<<"pro">>, Entries)),
  ?assert(contains_link_for_namefrag(<<"probst">>, Entries)),
  ?assert(contains_link_for_namefrag(<<"eid">>, Entries)),
  ?assert(contains_link_for_namefrag(<<"eide">>, Entries)),
  % They should all link to the same entry:
  lists:foreach(
    fun(E) -> ?assert((E#entry.data)#link.profile_key =:= Entry#entry.key) end,
    Entries).

init_test() ->
  Dht = the_dht,
  ?assertEqual(Dht, (init(Dht))#friendsearch_state.dht).

assumptions_for_add(Person) ->
  Entry = utilities:entry_for_record(Person),
  Link = #link{
    name_fragment = Person#person.name, 
    name = Person#person.name, 
    profile_key = Entry#entry.key
  },
  DhtPid = self(),
  LinkEntry = utilities:entry_for_record(Link),
  erlymock:o_o(chord, set, [DhtPid, Entry#entry.key, Entry], [{return, ok}]),
  erlymock:o_o(chord, set, [DhtPid, LinkEntry#entry.key, LinkEntry], [{return, ok}]),
  lists:foreach(fun(E) -> 
      erlymock:o_o(chord, set, [DhtPid, E#entry.key, E], [{return, ok}])
    end, generate_link_items(Entry)).

add_test() ->
  State = (init(chord))#friendsearch_state{dht_pid = self()},

  Person = test_utils:test_person_sebastianA(),

  erlymock:start(),
  assumptions_for_add(Person),
  erlymock:replay(), 
  NewState = add(Person, State),
  ?assert(NewState =/= State),
  Entries = list(NewState),
  ?assert(lists:member(Person, Entries)),
  erlymock:verify().
  

list_test() ->
  % Should return all entries currently in the store
  State = (init(chord))#friendsearch_state{dht_pid = self()},
  PersonA = test_utils:test_person_sebastianA(),
  PersonB = test_utils:test_person_sebastianB(),

  erlymock:start(),
  assumptions_for_add(PersonA),
  assumptions_for_add(PersonB),
  erlymock:replay(), 
  State1 = add(PersonA, State),
  State2 = add(PersonB, State1),
  Elements = list(State2),
  ?assert(lists:member(PersonA, Elements)),
  ?assert(lists:member(PersonB, Elements)),
  erlymock:verify().

delete_test() ->
  State = (init(chord))#friendsearch_state{dht_pid = self()},

  PersonA = test_utils:test_person_sebastianA(),
  PersonB = test_utils:test_person_sebastianB(),
  PersonAKey = (utilities:entry_for_record(PersonA))#entry.key,

  erlymock:start(),
  assumptions_for_add(PersonA),
  assumptions_for_add(PersonB),
  erlymock:replay(), 
  NewState = add(PersonB, add(PersonA, State)),
  erlymock:verify(),

  DeletedState = delete(PersonAKey, NewState),
  ?assert(lists:member(PersonB, list(DeletedState))),
  ?assertNot(lists:member(PersonA, list(DeletedState))).

keep_alive_test() ->
  % Records that are about to expire should be refreshed
  PersonA = test_utils:test_person_sebastianA(),
  PersonB = test_utils:test_person_sebastianB(),

  TimeNow = utilities:get_time(),

  % EntryA expires in 5 seconds, EntryB does not
  EntryA = (utilities:entry_for_record(PersonA))#entry{timeout = TimeNow + 5},
  EntryB = (utilities:entry_for_record(PersonB))#entry{timeout = TimeNow + ?ENTRY_TIMEOUT},
  DhtPid = self(),
  State = (init(chord))#friendsearch_state{dht_pid = DhtPid, entries = [EntryA, EntryB]},

  UpdatedEntryA = EntryA#entry{timeout = TimeNow + ?ENTRY_TIMEOUT},

  erlymock:start(),
  erlymock:strict(utilities, get_time, [], [{return, TimeNow}]),
  erlymock:strict(chord, set, [DhtPid, UpdatedEntryA#entry.key, UpdatedEntryA], [{return, ok}]),
  erlymock:replay(), 
  State1 = keep_alive(State),
  erlymock:verify(),

  % No timeouts should be less than 5 minutes after a keep_alive run
  lists:foreach(fun(E) -> ?assert(E#entry.timeout > TimeNow + 60) end,
      State1#friendsearch_state.entries).

profile_list_by_priority_test() ->
  List = [{a, 10}, {b, 1}, {a,1}, {b,1}],
  ?assertEqual([a, b], profile_list_by_priority(List)),
  List2 = [{a, 10}, {b, 1}, {a,1}, {b,1}, {b,1}, {b,1}, 
    {b,1}, {b,1}, {b,1}, {b,1}, {b,1}, {b,1}, {b,1}, {b,1}],
  ?assertEqual([b, a], profile_list_by_priority(List2)).

find_test() ->
  {ok, Pid} = test_dht:start(),
  State = (init(test_dht))#friendsearch_state{dht_pid = Pid},

  Person = test_utils:test_person_sebastianA(),
  UpdatedState = add(Person, State),

  Query = <<"Sebastian">>,
  ?assertEqual([Person], find(Query, UpdatedState)),
  test_dht:stop(Pid).

-endif.
