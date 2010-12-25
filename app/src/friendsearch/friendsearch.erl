%% @author Sebastian Probst Eide
%% @doc DataStore module for storing and retrieving values.
-module(friendsearch).

-include("../fs.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([list/1, add/2, delete/2, find/2, keep_alive/1]).
-export([lookup_link/2]).
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

  % Create entry for person record
  Entry = utilities:entry_for_record(Person),

  % Create main link entry for person that she can be found under
  MainLink = #link{
    name_fragment = Person#person.name,
    name = Person#person.name,
    profile_key = Entry#entry.key
  },
  MainLinkEntry = utilities:entry_for_record(MainLink),
  LinkEntries = [MainLinkEntry],

  % Add all entries to the Dht
  AllEntries = [Entry | LinkEntries],
  Dht = State#friendsearch_state.dht,
  lists:foreach(fun(E) -> Dht:set(E#entry.key, E) end, AllEntries),

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
find(Query, State) ->
  KeyForQuery = utilities:key_for_normalized_string(Query),
  Dht = State#friendsearch_state.dht,
  % Look up key in Dht
  Entries = Dht:get(KeyForQuery),
  Entries1 = lists:flatten(rpc:pmap({friendsearch, lookup_link}, [Dht], Entries)),
  [E#entry.data || E <- Entries1, is_record(E#entry.data, person)].

%% @doc: if the element is a link, then the corresponding record is
%% looked up in the Dht network.
-spec(lookup_link/2::(Entry::#entry{}, _) -> #entry{}).
lookup_link(#entry{data = #person{}} = Entry, _Dht) -> Entry;
lookup_link(#entry{data = #link{profile_key = Key}}, Dht) -> 
  Dht:get(Key).

-spec(keep_alive/1::(State::#friendsearch_state{}) -> #friendsearch_state{}).
keep_alive(State) ->
  TimeNow = utilities:get_time(),
  Entries = lists:map(fun(Entry) -> 
      case (Entry#entry.timeout < TimeNow + 60)of
        true -> 
          % Times out within a minute. Update it
          UpdatedEntry = Entry#entry{timeout = TimeNow + ?ENTRY_TIMEOUT},
          Dht = State#friendsearch_state.dht,
          Dht:set(UpdatedEntry#entry.key, UpdatedEntry),
          UpdatedEntry;
        false ->
          Entry
      end
    end, State#friendsearch_state.entries),
  State#friendsearch_state{entries = Entries}.

%% ------------------------------------------------------------------
%% Tests
%% ------------------------------------------------------------------

-ifdef(TEST).

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
  LinkEntry = utilities:entry_for_record(Link),
  erlymock:o_o(chord, set, [Entry#entry.key, Entry], [{return, ok}]),
  erlymock:o_o(chord, set, [LinkEntry#entry.key, LinkEntry], [{return, ok}]).

add_test() ->
  State = init(chord),

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
  State = init(chord),
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
  State = init(chord),

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
  State = (init(chord))#friendsearch_state{entries = [EntryA, EntryB]},

  UpdatedEntryA = EntryA#entry{timeout = TimeNow + ?ENTRY_TIMEOUT},

  erlymock:start(),
  erlymock:strict(utilities, get_time, [], [{return, TimeNow}]),
  erlymock:strict(chord, set, [UpdatedEntryA#entry.key, UpdatedEntryA], [{return, ok}]),
  erlymock:replay(), 
  State1 = keep_alive(State),
  erlymock:verify(),

  % No timeouts should be less than 5 minutes after a keep_alive run
  lists:foreach(fun(E) -> ?assert(E#entry.timeout > TimeNow + 60) end,
      State1#friendsearch_state.entries).

find_test() ->
  State = init(chord),

  Query = <<"Sebastian">>,
  Key = utilities:key_for_normalized_string(Query),
  ProfileKey = <<"ProfileKey">>,

  Link = #entry{data = #link{profile_key = ProfileKey}, key = Key},
  Person = #person{name = <<"Sebastian">>},
  Profile = #entry{data = Person, key = ProfileKey},

  erlymock:start(),
  erlymock:strict(chord, get, [Key], [{return, [Link]}]),
  erlymock:strict(chord, get, [ProfileKey], [{return, [Profile]}]),
  erlymock:replay(), 
  ?assertEqual([Person], find(Query, State)),
  erlymock:verify().

lookup_link_person_test() ->
  Entry = test_utils:test_person_entry_1a(),
  ?assertEqual(Entry, lookup_link(Entry, some_dht)).

lookup_link_link_test() ->
  ProfileKey = <<"SomeKey">>,
  Entry = #entry{data = #link{profile_key = ProfileKey}},
  ReturnEntry = test_utils:test_person_entry_1a(),

  erlymock:start(),
  erlymock:strict(chord, get, [ProfileKey], [{return, [ReturnEntry]}]),
  erlymock:replay(), 
  ?assertEqual([ReturnEntry], lookup_link(Entry, chord)),
  erlymock:verify().

-endif.
