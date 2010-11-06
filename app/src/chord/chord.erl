-module(chord).
-behaviour(gen_server).
-define(SERVER, ?MODULE).
-define(NUMBER_OF_FINGERS, 160).

%% @doc: the interval in seconds at which the routine tasks are performed
-define(STABILIZER_INTERVAL, 3).
-define(FIX_FINGER_INTERVAL, 2).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-include("../fs.hrl").
-include("chord.hrl").

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/0, start/0, stop/0]).
-export([get/1, set/2, preceding_finger/1, find_successor/1, get_predecessor/0]).

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

-spec(preceding_finger/1::(Key::key()) -> {ok, {#node{}, #node{}}}).
preceding_finger(Key) ->
  gen_server:call(chord, {get_preceding_finger, Key}).

-spec(find_successor/1::(Key::key()) -> {ok, #node{}}).
find_successor(Key) ->
  gen_server:call(chord, {find_successor, Key}).

-spec(get_predecessor/0::() -> #node{}).
get_predecessor() ->
  gen_server:call(chord, get_predecessor).

%% @doc Notified receives messages from predecessors identifying themselves.
%%      If the node is a closer predecessor than the current one, then
%%      the internal state is updated.
-spec(notified/1::(Node::#node{}) -> ok).
notified(Node) ->
  gen_server:call(chord, {notified, Node}).

-spec(stabilize/0::() -> ok).
stabilize() ->
  gen_server:cast(stabilize),
  ok.

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
    fingers = FingerTable,

    % Admin stuff
    pidStabilizer = spawn(fun() -> stabilizer() end),
    pidFixFingers = spawn(fun() -> fingerFixer() end)
  },


  % Join chord network!
  % First we need to get a seed node:
  % SeedNode = ...
  % Now connect to it:
  {ok, ConnectedState} = {ok, State}, %join(State, SeedNode),

  {ok, ConnectedState}.

%% Call:
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

handle_call({get_preceding_finger, Key}, _From, State) ->
  Finger = closest_preceding_finger(Key, State),
  Succ = State#chord_state.successor,
  Msg = {ok, {Finger, Succ}},
  {reply, Msg, State};

handle_call({find_successor, Key}, From, State) ->
  spawn(fun() -> gen_server:reply(From, find_successor(Key, State)) end),
  {noreply, State};

handle_call(get_predecessor, _From, #chord_state{predecessor = Predecessor} = State) ->
  {reply, Predecessor, State}.

%% Casts:
handle_cast({notified, #node{key = NewKey} = Node}, 
    #chord_state{predecessor = Pred, self = Self} = State) ->
  NewState = case ((Pred =:= #node{}) or 
      utilities:in_range(NewKey, Pred#node.key, Self#node.key)) of
    true  -> Node#chord_state{predecessor = Node};
    false -> State
  end,
  {noreply, NewState};

handle_cast({set_finger, N, NewFinger},  #chord_state{fingers = Fingers} = State) ->
  NewFingers = lists:sublist(Fingers, 1, N-1) ++ NewFinger ++ lists:nthtail(N, Fingers),
  NewState = State#chord_state{fingers = NewFingers},
  {noreply, NewState};

handle_cast({set_successor, Pred}, State) ->
  {noreply, State#chord_state{successor = Pred}};

handle_cast(stabilize, State) ->
  spawn(fun() -> perform_stabilize(State) end),
  {noreply, State};

handle_cast(fix_fingers, State) ->
  FingerNumToFix = random:uniform(?NUMBER_OF_FINGERS),
  spawn(fun() -> fix_finger(FingerNumToFix, State) end),
  {noreply, State};

handle_cast(_Msg, State) ->
  {noreply, State}.

%% Info:
handle_info(_Info, State) ->
  {noreply, State}.

terminate(_Reason, State) ->
  % Tell the admin workers to stop what they are doing
  State#chord_state.pidStabilizer ! stop,
  State#chord_state.pidFixFingers ! stop,
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

%% @doc: This task runs in the background, and automatically executes
%% chord - stabilize at given intervals.
stabilizer() ->
  perform_task(stabilize, ?STABILIZER_INTERVAL).

%% @doc: This task runs in the background, and automatically executes
%% chord - fix_fingers at given intervals.
fingerFixer() ->
  perform_task(fix_fingers, ?FIX_FINGER_INTERVAL).

perform_task(Task, Interval) ->
  receive stop -> ok
  after Interval ->
    gen_server:cast(chord, Task),
    perform_task(Task, Interval)
  end.

-spec(fix_finger/2::(FingerNum::integer(), #chord_state{}) -> ok).
fix_finger(FingerNum, #chord_state{fingers = Fingers} = State) ->
  Finger = lists:nth(FingerNum, Fingers),
  {ok, Succ} = find_successor(Finger#finger_entry.start, State),
  UpdatedFinger = Finger#finger_entry{node = Succ},
  gen_server:cast(chord, {set_finger, FingerNum, UpdatedFinger}).


-spec(perform_stabilize/1::(#chord_state{}) -> #chord_state{}).
perform_stabilize(#chord_state{self = ThisNode, successor = Succ} = State) ->
  case chord_tcp:get_predecessor(Succ#node.ip, Succ#node.port) of
    {ok, Pred} ->
      % Check if predecessor is between ourselves and successor
      NewSuccessor = case utilities:in_range(Pred#node.key, ThisNode#node.key, Succ#node.key) of
        true  -> 
          % The successors predecessor is now our new successor
          gen_server:cast(chord, {set_successor, Pred}),
          Pred;
        false -> 
          State#chord_state.successor
      end,

      chord_tcp:notify_successor(NewSuccessor, ThisNode);

    {error, Reason} ->
      % @todo: Handle error and try another successor.
      ok

  end.

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
  % First check locally to see if it is in the range
  % of this node and this nodes successor.
  case utilities:in_inclusive_range(Key, NodeId, Succ#node.key) of
    true  -> {ok, Succ};
    % Try looking successively through successors successors.
    false -> find_successor(Key, Succ)
  end;
find_successor(Key, #node{key = NKey, ip = NIp, port = NPort}) ->
  case chord_tcp:rpc_get_closest_preceding_finger(Key, NIp, NPort) of
    {ok, {NextFinger, NSucc}} ->
      case utilities:in_inclusive_range(Key, NKey, NSucc#node.key) of
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


-spec(join/2::(State::#chord_state{}, NodeToAsk::#node{}) -> 
    {ok, #chord_state{}} | {error, atom(), #chord_state{}}).
join(State, NodeToAsk) ->
  PredState = State#chord_state{predecessor = #node{}},

  % Find state needed for request
  NIp = NodeToAsk#node.ip,
  NPort = NodeToAsk#node.port,
  OwnKey = (State#chord_state.self)#node.key,

  % Find the successor node
  case chord_tcp:rpc_find_successor(OwnKey, NIp, NPort) of
    {ok, Succ} ->
      {ok, PredState#chord_state{successor = Succ}};
    {error, Reason} ->
      {error, Reason, PredState}
  end.


%% ------------------------------------------------------------------
%% Tests
%% ------------------------------------------------------------------

-ifdef(TEST).

nForKey(Key) -> #node{key = Key}.
test_get_run_state() ->
  #chord_state{
    fingers = [#finger_entry{start = 5, interval = {5,1}, node = nForKey(6)},
               #finger_entry{start = 3, interval = {3,5}, node = nForKey(3)},
               #finger_entry{start = 2, interval = {2,3}, node = nForKey(3)}],
    self = #node{key = 1},
    predecessor = #node{key = 0},
    successor = #node{key = 5}
  }.
test_get_state() ->
  #chord_state{
    fingers = [#finger_entry{start = 4, interval = {4,0}, node = nForKey(0)},
              #finger_entry{start = 2, interval = {2,4}, node = nForKey(3)},
              #finger_entry{start = 1, interval = {1,2}, node = nForKey(1)}],
    self = #node{key = 0},
    % We have set the successors Id to 1. All request for keys > 1 will go to successor
    successor = #node{ip = {127,0,0,1}, port = 9234, key = 1}
  }.

%% @todo: Missing test for fix_finger

%% @todo: Missing test that checks that notify actually works!
%%        Missing test where the successors predecessor is not ourself.

find_closest_preceding_finger_test_() ->
  {inparallel, [
    ?_assertEqual(nForKey(0), closest_preceding_finger(0, test_get_state())),
    ?_assertEqual(nForKey(0), closest_preceding_finger(1, test_get_state())),
    ?_assertEqual(nForKey(1), closest_preceding_finger(2, test_get_state())),
    ?_assertEqual(nForKey(1), closest_preceding_finger(3, test_get_state())),
    ?_assertEqual(nForKey(3), closest_preceding_finger(4, test_get_state())),
    ?_assertEqual(nForKey(3), closest_preceding_finger(5, test_get_state())),
    ?_assertEqual(nForKey(3), closest_preceding_finger(6, test_get_state())),
    ?_assertEqual(nForKey(3), closest_preceding_finger(7, test_get_state()))
  ]}.

find_successor_on_same_node_test() ->
  State = test_get_state(),
  ?assertEqual({ok, State#chord_state.successor}, find_successor(1, State)).

find_successor_on_other_node_test_() ->
  {setup,
    fun setup_find_successor/0,
    fun teardown_find_successor/1, [
      fun successor_test1/0,
      fun successor_test2/0,
      fun successor_test3/0
    ]
  }.
successor_test1() ->
  State = test_get_state(),
  ?assertEqual({ok, #node{key = 5}}, find_successor(2, State)).
successor_test2() ->
  State = test_get_state(),
  ?assertEqual({ok, #node{key = 5}}, find_successor(4, State)).
successor_test3() ->
  State = test_get_state(),
  ?assertEqual({ok, #node{key = 5}}, find_successor(5, State)).

setup_find_successor() ->
  chord_tcp:start(),     
  start(),
  set_state(test_get_run_state()).

teardown_find_successor(_State) ->
  chord:stop(), 
  chord_tcp:stop().

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

join_test_() ->
  {setup,
    fun setup_find_successor/0,
    fun teardown_find_successor/1, [
      fun join_test1/0
  ]}.

join_test1() ->
  State = (test_get_state())#chord_state{predecessor = #node{key = 1234}, self = #node{key = 2}},
  {ok, NewState} = join(State, #node{ip = {127,0,0,1}, port = 9234}),
  % Ensure the precesseccor has been removed
  ?assert((NewState#chord_state.predecessor)#node.key =/= 1234),
  % Make sure that it has set the right successor
  ?assertEqual(#node{key = 5}, NewState#chord_state.successor).
    
-endif.
