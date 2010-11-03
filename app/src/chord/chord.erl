-module(chord).
-behaviour(gen_server).
-define(SERVER, ?MODULE).
-define(NUMBER_OF_FINGERS, 160).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-include("../fs.hrl").

-record(node, {
    ip :: ip(),
    port :: port_number(),
    key :: key()
  }).
-record(finger_entry, {
    start :: key(),
    interval :: {key(), key()},
    node :: #node{}
  }).
-record(chord_state, {
    self :: #node{},
    successor :: #node{},

    % The finger list is in inverse order from what is described
    % in the Chord paper. This is due to implementation reasons,
    % since the method closest_preceding_finger, which is the
    % only method using the finger table directly, traverses
    % it from the back to the front.
    fingers = [] :: [#finger_entry{}]
  }).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/0, start/0, stop/0]).
-export([get/1, set/2, preceding_finger/1]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start() ->
  gen_server:start({local, ?SERVER}, ?MODULE, [], []).

start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

stop() ->
  gen_server:call(chord, stop).

-spec(set_state/1::(#chord_state{}) -> ok).
set_state(NewState) ->
  gen_server:call(chord, {set_state, NewState}).

-spec(get/1::(Key::key()) -> [#entry{}]).
get(Key) ->
  gen_server:call(chord, {get, Key}).

-spec(set/2::(Key::key(), Entry::#entry{}) -> ok | {error, server}).
set(Key, Entry) ->
  gen_server:call(chord, {set, Key, Entry}).

-spec(preceding_finger/1::(Key::key()) -> {ok, {#node{}, key()}}).
preceding_finger(Key) ->
  Finger = gen_server:call(chord, {lookup_preceding_finger, Key}),
  Succ = gen_server:call(chord, get_successor),
  {ok, {Finger, Succ#node.key}}.

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(Args) -> 
  Port = proplists:get_value(port, Args, 4000),
  NodeId = utilities:key_for_node(utilities:get_ip(), Port),

  % We initialize the finger table with 160 records.
  % Since we are using 160-bit keys, we will also use
  % 160 entries for the table.
  % We reverse the list since find predecessor accesses them
  % from the end.
  FingerTable = lists:reverse(create_finger_table(NodeId)),
  
  State = #chord_state{self =
    #node{
      ip = utilities:get_ip(),
      port = Port, 
      key = NodeId 
    },
    fingers = FingerTable
  },

  {ok, State}.

handle_call({set_state, NewState}, _From, _State) ->
  {reply, ok, NewState};

handle_call(stop, _From, State) ->
  {stop, normal, ok, State};

handle_call({get, _Key}, _From, State) ->
  % Do lookup
  Results = some_call,
  {reply, Results, State};

handle_call({set, _Key, _Entry}, _From, State) ->
  % Store value in network
  {reply, ok, State};

handle_call({lookup_preceding_finger, Key}, _From, State) ->
  {reply, closest_preceding_finger(Key, State), State};

handle_call(get_successor, _From, #chord_state{successor = Succ} = State) ->
  {reply, Succ, State}.

handle_cast(_Msg, State) ->
  {noreply, State}.

handle_info(_Info, State) ->
  {noreply, State}.

terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

-spec(create_finger_table/1::(NodeKey::key()) -> [#finger_entry{}]).
create_finger_table(NodeKey) ->
  StartEntries = create_start_entry(NodeKey, ?NUMBER_OF_FINGERS),
  add_interval(StartEntries, NodeKey).


-spec(create_start_entry/2::(NodeKey::key(), N::integer()) -> 
    [#finger_entry{}]).
create_start_entry(_NodeKey, 0) -> [];
create_start_entry(NodeKey, N) ->
  [#finger_entry{
    % Get start entry for each node from 1 upto and including 160
    start = get_start(NodeKey, ?NUMBER_OF_FINGERS - N + 1)
  } | create_start_entry(NodeKey, N-1)].


-spec(get_start/2::(NodeKey::key(), N::integer()) -> key()).
get_start(NodeKey, N) ->
  (NodeKey + (1 bsl (N-1))) rem (1 bsl 160).


-spec(add_interval/2::(Entries::[#finger_entry{}], CurrentKey::key()) ->
    [#finger_entry{}]).
add_interval([Last], CurrentKey) ->
  [Last#finger_entry{
    interval = {
      Last#finger_entry.start, CurrentKey 
    }
  }];
add_interval([Current, Next | Rest], CurrentKey) ->
  [Current#finger_entry{
    interval = {
      Current#finger_entry.start, Next#finger_entry.start 
    }}
   | add_interval([Next | Rest], CurrentKey)].


-spec(find_successor/2::(Key::key(), #chord_state{} | #node{})
    -> {ok, #node{}} | {error, instance}).
find_successor(Key, 
    #chord_state{self = #node{key = NodeId}, successor = Succ}) ->
  case ((Key > NodeId) and (Key =< Succ#node.key)) of
    true  -> {ok, Succ};
    false -> find_successor(Key, Succ)
  end;
find_successor(Key, #node{key = NKey, ip = NIp, port = NPort}) ->
  case chord_tcp:get_closest_preceding_finger(Key, NIp, NPort) of
    {ok, {NextFinger, NSucc}} ->
      case ((Key > NKey) and (Key =< NSucc)) of
        true  -> {ok, NSucc};
        false -> find_successor(Key, NextFinger)
      end;
    {error, Reason} ->
      {error, Reason}
  end.


-spec(closest_preceding_finger/2::(Key::key(), 
    State::#chord_state{}) -> #node{}).
closest_preceding_finger(Key, State) ->
  closest_preceding_finger(Key, 
    State#chord_state.fingers,
    State#chord_state.self).


-spec(closest_preceding_finger/3::(Key::key(), 
    [#finger_entry{}],
    CurrentNode::key()) -> key()).
closest_preceding_finger(_Key, [], CurrentNode) -> CurrentNode;
closest_preceding_finger(Key, [Finger|Fingers], CurrentNode) ->
  Node = Finger#finger_entry.node,
  NodeId = Node#node.key,
  case ((CurrentNode#node.key < NodeId) and (NodeId < Key)) of
    true -> 
      Node;
    false -> closest_preceding_finger(Key, Fingers, CurrentNode)
  end.


%% ------------------------------------------------------------------
%% Tests
%% ------------------------------------------------------------------

-ifdef(TEST).

n2b(Num) -> term_to_binary(Num).
nForKey(Key) -> #node{key = n2b(Key)}.
test_get_run_state() ->
  #chord_state{
    fingers = [#finger_entry{start = n2b(4), interval = {n2b(4),n2b(0)}, node = nForKey(0)},
              #finger_entry{start = n2b(2), interval = {n2b(2),n2b(4)}, node = nForKey(3)},
              #finger_entry{start = n2b(1), interval = {n2b(1),n2b(2)}, node = nForKey(1)}],
    self = #node{key = n2b(1)},
    successor = #node{ip = {127,0,0,1}, port = 9234, key = n2b(3)}
  }.
test_get_state() ->
  #chord_state{
    fingers = [#finger_entry{start = n2b(4), interval = {n2b(4),n2b(0)}, node = nForKey(0)},
              #finger_entry{start = n2b(2), interval = {n2b(2),n2b(4)}, node = nForKey(3)},
              #finger_entry{start = n2b(1), interval = {n2b(1),n2b(2)}, node = nForKey(1)}],
    self = #node{key = n2b(0)},
    successor = #node{ip = {127,0,0,1}, port = 9234, key = n2b(1)}
  }.

find_closest_preceding_finger_test() ->
  ?assertEqual(nForKey(0), closest_preceding_finger(n2b(0), test_get_state())),
  ?assertEqual(nForKey(0), closest_preceding_finger(n2b(1), test_get_state())),
  ?assertEqual(nForKey(1), closest_preceding_finger(n2b(2), test_get_state())),
  ?assertEqual(nForKey(1), closest_preceding_finger(n2b(3), test_get_state())),
  ?assertEqual(nForKey(3), closest_preceding_finger(n2b(4), test_get_state())),
  ?assertEqual(nForKey(3), closest_preceding_finger(n2b(5), test_get_state())),
  ?assertEqual(nForKey(3), closest_preceding_finger(n2b(6), test_get_state())),
  ?assertEqual(nForKey(3), closest_preceding_finger(n2b(7), test_get_state())).

find_successor_on_same_node_test() ->
  State = test_get_state(),
  ?assertEqual({ok, State#chord_state.successor}, find_successor(n2b(1), State)).

find_successor_on_other_node_test_() ->
  {setup,
    fun() ->
      chord_tcp:start(),
      start(),
      set_state(test_get_run_state())
    end,
    fun(_) ->
      chord:stop(), 
      chord_tcp:stop()
    end,
    fun() ->
      State = test_get_run_state(),
      ?assertEqual({ok, State#chord_state.successor}, find_successor(n2b(2), State))
    end
  }.

% Test data from Chord paper.
get_start_test_() ->
  {inparallel,
   [
    ?_assertEqual(1, get_start(0, 1)),
    ?_assertEqual(2, get_start(0, 2)),
    ?_assertEqual(4, get_start(0, 3)),

    ?_assertEqual(2, get_start(1, 1)),
    ?_assertEqual(3, get_start(1, 2)),
    ?_assertEqual(5, get_start(1, 3)),
    
    ?_assertEqual(4, get_start(3, 1)),
    ?_assertEqual(5, get_start(3, 2)),
    ?_assertEqual(7, get_start(3, 3))
  ]}.

create_start_entry_test() ->
  NodeId = 0,
  [E1,E2 | _Rest] = create_start_entry(NodeId, ?NUMBER_OF_FINGERS),
  ?assertEqual(get_start(NodeId, 1), E1#finger_entry.start),
  ?assertEqual(get_start(NodeId, 2), E2#finger_entry.start).

add_interval_test() ->
  CurrentNodeId = 0,
  CreateEntry = fun(N) -> #finger_entry{ start = N } end,
  FingerEntries = [CreateEntry(1), CreateEntry(2), CreateEntry(4)],
  [E1, E2, E3] = add_interval(FingerEntries, CurrentNodeId),
  ?assertEqual({1,2}, E1#finger_entry.interval),
  ?assertEqual({2,4}, E2#finger_entry.interval),
  ?assertEqual({4,0}, E3#finger_entry.interval).


-endif.
