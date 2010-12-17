%% @author Sebastian Probst Eide
%% @doc DataStore module for storing and retrieving values.
-module(friendsearch).

-include("../fs.hrl").

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([list/1, add/2, delete/2, find/2]).
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
delete(Key, State) -> State.

-spec(find/2::(Query::bitstring(), State::#friendsearch_state{}) -> [#entry{}]).
find(Query, State) -> [].

%% ------------------------------------------------------------------
%% Tests
%% ------------------------------------------------------------------

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

-endif.
