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
  State#friendsearch_state.entries.

-spec(add/2::(Person::#person{}, State::#friendsearch_state{}) -> #friendsearch_state{}).
add(Person, State) -> 
  AllPersonEntries = State#friendsearch_state.entries,
  AllLinkEntries = State#friendsearch_state.link_entries,

  % @todo: Create link entries for person
  LinkEntries = [],

  % Create entry for person record
  Entry = utilities:entry_for_record(Person),

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
find(Query, State) -> [].

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

add_test() ->
  State = init(chord),

  Person = test_utils:test_person_sebastianA(),
  Entry = utilities:entry_for_record(Person),

  erlymock:start(),
  erlymock:o_o(chord, set, [Entry#entry.key, Entry], [{return, ok}]),
  erlymock:replay(), 
  NewState = add(Person, State),
  ?assert(NewState =/= State),
  Entries = list(NewState),
  ?assert(lists:member(Entry, Entries)),
  erlymock:verify().
  

list_test() ->
  % Should return all entries currently in the store
  State = init(chord),
  PersonA = test_utils:test_person_sebastianA(),
  PersonB = test_utils:test_person_sebastianB(),
  EntryA = utilities:entry_for_record(PersonA),
  EntryB = utilities:entry_for_record(PersonB),

  erlymock:start(),
  erlymock:o_o(chord, set, [EntryA#entry.key, EntryA], [{return, ok}]),
  erlymock:o_o(chord, set, [EntryB#entry.key, EntryB], [{return, ok}]),
  erlymock:replay(), 
  State1 = add(PersonA, State),
  State2 = add(PersonB, State1),
  Elements = list(State2),
  ?assert(lists:member(EntryA, Elements)),
  ?assert(lists:member(EntryB, Elements)),
  erlymock:verify().

delete_test() ->
  State = init(chord),

  PersonA = test_utils:test_person_sebastianA(),
  PersonB = test_utils:test_person_sebastianB(),
  EntryA = utilities:entry_for_record(PersonA),
  EntryB = utilities:entry_for_record(PersonB),

  erlymock:start(),
  erlymock:o_o(chord, set, [EntryA#entry.key, EntryA], [{return, ok}]),
  erlymock:o_o(chord, set, [EntryB#entry.key, EntryB], [{return, ok}]),
  erlymock:replay(), 
  NewState = add(PersonB, add(PersonA, State)),
  erlymock:verify(),

  DeletedState = delete(EntryA#entry.key, NewState),
  ?assert(lists:member(EntryB, list(DeletedState))),
  ?assertNot(lists:member(EntryA, list(DeletedState))).

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
  lists:foreach(fun(E) -> ?assert(E#entry.timeout > TimeNow + 60) end, list(State1)).

-endif.
