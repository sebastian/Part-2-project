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
-export([notified/1]).
-export([get_state/0]).

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

-spec(get_state/0::() -> #chord_state{}).
get_state() ->
  gen_server:call(chord, get_state).

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
%% If the node is a closer predecessor than the current one, then
%% the internal state is updated.
%% Additionally, and this is a hack to bootstrap the system,
%% if the current node doesn't have any successor, then add the predecessor
%% as the successor.
-spec(notified/1::(Node::#node{}) -> ok).
notified(Node) ->
  gen_server:call(chord, {notified, Node}), ok.

-spec(stabilize/0::() -> ok).
stabilize() ->
  gen_server:cast(stabilize),
  ok.

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(_Args) -> 
  Port = utilities:get_chord_port(),
  Ip = utilities:get_ip(),
  NodeId = utilities:key_for_node(Ip, Port),

  % We initialize the finger table with 160 records since
  % we have 160-bit keys.
  FingerTable = create_finger_table(NodeId),
  
  State = #chord_state{self =
    #node{
      ip = Ip,
      port = Port, 
      key = NodeId 
    },
    fingers = FingerTable,

    % Admin stuff
    pidStabilizer = spawn(fun() -> stabilizer() end),
    pidFixFingers = spawn(fun() -> fingerFixer() end)
  },

  % Get node that can be used to join the chord network:
  case utilities:get_join_node(Ip, Port) of
    {JoinIp, JoinPort} ->
      % Connect to the new node.
      SeedNode = #node{ip = JoinIp, port = JoinPort},
      {ok, NewState} = join(State, SeedNode),
      {ok, NewState};
    first ->
      % We are the first in the network. Return the current state.
      {ok, State}
  end.

%% Call:
handle_call(get_state, _From, State) ->
  {reply, State, State};

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
  io:format("Getting preceding finger for ~p, from State: ~p", [Key, State]),
  Finger = closest_preceding_finger(Key, State),
  Succ = get_successor(State),
  Msg = {ok, {Finger, Succ}},
  {reply, Msg, State};

handle_call({find_successor, Key}, _From, State) ->
  {reply, find_successor(Key,State), State};

handle_call(get_predecessor, _From, #chord_state{predecessor = Predecessor} = State) ->
  {reply, {ok, Predecessor}, State}.

%% Casts:
handle_cast({notified, #node{key = NewKey} = Node}, 
    #chord_state{predecessor = Pred, self = Self} = State) ->
  State1 = case ((Pred =:= #node{}) orelse
      utilities:in_range(NewKey, Pred#node.key, Self#node.key)) of
    true  -> State#chord_state{predecessor = Node};
    false -> State
  end,
  % If the current node doesn't have any successor,
  % then use the predecessor as the successor.
  % This is only done when the network is bootstrapped.
  State2 = case get_successor(State1) of
    undefined -> set_successor(Node, State1);
    _ -> State1
  end,
  {noreply, State2};

handle_cast({set_finger, N, NewFinger},  #chord_state{fingers = Fingers} = State) ->
  NewFingers = lists:sublist(Fingers, 1, N-1) ++ NewFinger ++ lists:nthtail(N, Fingers),
  NewState = State#chord_state{fingers = NewFingers},
  {noreply, NewState};

handle_cast({set_successor, Pred}, State) ->
  {noreply, set_successor(Pred, State)};

handle_cast(stabilize, #chord_state{self = Us} = State) ->
  Stabilize = fun() ->
    Succ = case perform_stabilize(State) of
      {updated_succ, NewSucc} ->
        gen_server:cast(chord, {set_successor, NewSucc});
      {ok, S} -> S
    end,
    chord_tcp:notify_successor(Succ, Us)
  end,
  % Perform stabilization    
  spawn(Stabilize),
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
  ok.
  %perform_task(stabilize, ?STABILIZER_INTERVAL).

%% @doc: This task runs in the background, and automatically executes
%% chord - fix_fingers at given intervals.
fingerFixer() ->
  ok.
  %perform_task(fix_fingers, ?FIX_FINGER_INTERVAL).

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


-spec(perform_stabilize/1::(#chord_state{}) -> 
    {ok, #node{}} | {updated_succ, #node{}}).
perform_stabilize(#chord_state{self = ThisNode} = State) ->
  Succ = get_successor(State),
  {ok, SuccPred} = chord_tcp:get_predecessor(Succ),
  % Check if predecessor is between ourselves and successor
  case utilities:in_range(SuccPred#node.key, ThisNode#node.key, Succ#node.key) of
    true  -> 
      {updated_succ, SuccPred};
    false -> 
      % We still have the same successor.
      {ok, Succ}
  end.


-spec(create_finger_table/1::(NodeKey::key()) -> [#finger_entry{}]).
create_finger_table(NodeKey) ->
  create_start_entries(NodeKey, 0, array:new(160)).


-spec(create_start_entries/3::(NodeKey::key(), N::integer(), Array::array()) -> 
    [#finger_entry{}]).
create_start_entries(_NodeKey, 160, Array) -> Array;
create_start_entries(NodeKey, N, Array) ->
  create_start_entries(NodeKey, N+1, array:set(N, finger_entry_node(NodeKey, N), Array)).


-spec(finger_entry_node/2::(NodeKey::key(), Number::integer()) ->
    #finger_entry{}).
finger_entry_node(NodeKey, Number) ->
  #finger_entry{
    start = get_start(NodeKey, Number),
    interval = interval_for(NodeKey, Number)
  }.


-spec(interval_for/2::(NodeKey::key(), Number::integer()) ->
    {integer(), integer()}).
interval_for(NodeKey, 159) ->
  % If it is the last node entry, then its interval loops around
  % to the first finger entry.
  {get_start(NodeKey, 159), get_start(NodeKey, 0)};
interval_for(NodeKey, Number) ->
  {get_start(NodeKey, Number), get_start(NodeKey, Number+1)}.


-spec(get_start/2::(NodeKey::key(), N::integer()) -> key()).
get_start(NodeKey, N) ->
  (NodeKey + (1 bsl N)) rem (1 bsl 160).


%% @doc: Returns the node succeeding a key.
-spec(find_successor/2::(Key::key(), #chord_state{} | #node{})
    -> {ok, #node{}} | {error, instance}).
find_successor(Key, 
    #chord_state{self = #node{key = NodeId}} = State) ->
  case get_successor(State) of
    undefined -> 
      % This case only happens when the chord circle is new
      % and the second node joins. Then the first node does
      % not yet have any successors.
      State#chord_state.self;
    Succ ->
      % First check locally to see if it is in the range
      % of this node and this nodes successor.
      case utilities:in_inclusive_range(Key, NodeId, Succ#node.key) of
        true  -> {ok, Succ};
        % Try looking successively through successors successors.
        false -> find_successor(Key, Succ)
      end
  end;
find_successor(Key, #node{key = NKey} = CurrentNext) ->
  {ok, {NextFinger, NSucc}} = chord_tcp:rpc_get_closest_preceding_finger_and_succ(Key, CurrentNext),
  case utilities:in_inclusive_range(Key, NKey, NSucc#node.key) of
    true  -> {ok, NSucc};
    false -> find_successor(Key, NextFinger)
  end.


-spec(closest_preceding_finger/2::(Key::key(), 
    State::#chord_state{}) -> _::#node{}).
closest_preceding_finger(Key, State) ->
  closest_preceding_finger(Key, 
    State#chord_state.fingers, array:size(State#chord_state.fingers) - 1,
    State#chord_state.self).


-spec(closest_preceding_finger/4::(Key::key(), 
    array(), CurrentFinger::integer(),
    CurrentNode::#node{}) -> #node{}).
closest_preceding_finger(_Key, _Fingers, -1, CurrentNode) -> CurrentNode;
closest_preceding_finger(Key, Fingers, CurrentFinger, CurrentNode) ->
  Finger = array:get(CurrentFinger, Fingers),
  case Finger#finger_entry.node of
    undefined ->
      % The finger entry is empty. We skip it
      closest_preceding_finger(Key, Fingers, CurrentFinger-1, CurrentNode);
    Node ->
      NodeId = Node#node.key,
      case ((CurrentNode#node.key < NodeId) andalso (NodeId < Key)) of
        true -> Node;
        false -> closest_preceding_finger(Key, Fingers, CurrentFinger-1, CurrentNode)
      end
  end.


%% @doc: joins another chord node and returns the updated chord state
-spec(join/2::(State::#chord_state{}, NodeToAsk::#node{}) -> 
    {ok, #chord_state{}} | {error, atom(), #chord_state{}}).
join(State, NodeToAsk) ->
  PredState = State#chord_state{predecessor = #node{}},

  % Find state needed for request
  NIp = NodeToAsk#node.ip,
  NPort = NodeToAsk#node.port,
  OwnKey = (State#chord_state.self)#node.key,

  % Find the successor node
  {ok, Succ} = chord_tcp:rpc_find_successor(OwnKey, NIp, NPort),
  {ok, set_successor(Succ, PredState)}.


%% @doc: returns the successor in the local finger table
-spec(get_successor/1::(State::#chord_state{}) -> #node{}).
get_successor(State) ->
  Fingers = State#chord_state.fingers,
  (array:get(0, Fingers))#finger_entry.node.


%% @doc: sets the successor and returns the updated state.
-spec(set_successor/2::(Successor::#node{}, State::#chord_state{}) ->
    #chord_state{}).
set_successor(Successor, State) ->
  Fingers = State#chord_state.fingers,
  SuccessorFinger = (array:get(0, Fingers))#finger_entry{node=Successor},
  State#chord_state{fingers = array:set(0, SuccessorFinger, Fingers)}.

%% ------------------------------------------------------------------
%% Tests
%% ------------------------------------------------------------------

-ifdef(TEST).

nForKey(Key) -> #node{key = Key}.

%% @todo: Missing test for fix_finger

%% @todo: Missing test that checks that notify actually works!
%%        Missing test where the successors predecessor is not ourself.

test_get_state() ->
  Fingers = array:set(0, #finger_entry{start = 1, interval = {1,2}, node = nForKey(1)},
            array:set(1, #finger_entry{start = 2, interval = {2,4}, node = nForKey(3)},
            array:set(2, #finger_entry{start = 4, interval = {4,0}, node = nForKey(0)},
                array:new(3)))),
  #chord_state{
    fingers = Fingers,
    self = nForKey(0)
  }.

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

% When finger table entries are empty, they should be skipped rather than cause an exception
closest_preceding_finger_for_empty_fingers_test() ->
  Self = #node{key=1234},
  State = #chord_state{self = Self, fingers = create_finger_table(Self#node.key)},
  ?assertEqual(Self, closest_preceding_finger(0, State)).


%% *** find_successor tests ***

% Test when the successor is directly in our finger table
find_successor_on_same_node_test() ->
  State = test_get_state(),
  ?assertEqual({ok, get_successor(State)}, find_successor(1, State)).

% Test when the successor is one hop away
find_successor_next_hop_test() ->
  % Our current successor is node 1.
  State = test_get_state(),

  NextFinger = #node{},
  NextSuccessor = #node{key = 6},
  RpcReturn = {ok, {NextFinger, NextSuccessor}},

  Key = 4,

  erlymock:start(),
  erlymock:strict(chord_tcp, rpc_get_closest_preceding_finger_and_succ, [Key, get_successor(State)], [{return, RpcReturn}]),
  erlymock:replay(), 
  ?assertEqual({ok, NextSuccessor}, find_successor(Key, State)),
  erlymock:verify().

% Test when the successor is multiple hops away
find_successor_subsequent_hop_test() ->
  % Our current successor is node 1.
  State = test_get_state(),

  FirstNextFinger = #node{},
  FirstNextSuccessor = #node{key = 6},
  FirstRpcReturn = {ok, {FirstNextFinger, FirstNextSuccessor}},

  SecondNextFinger = #node{},
  SecondNextSuccessor = #node{key = 14},
  SecondRpcReturn = {ok, {SecondNextFinger, SecondNextSuccessor}},

  Key = 10,

  erlymock:start(),
  erlymock:strict(chord_tcp, rpc_get_closest_preceding_finger_and_succ, [Key, get_successor(State)], [{return, FirstRpcReturn}]),
  erlymock:strict(chord_tcp, rpc_get_closest_preceding_finger_and_succ, [Key, FirstNextFinger], [{return, SecondRpcReturn}]),
  erlymock:replay(), 
  ?assertEqual({ok, SecondNextSuccessor}, find_successor(Key, State)),
  erlymock:verify().

% When a node has no known successor, then we are
% working with a fresh chord ring, and return ourselves.
find_successor_for_missing_successor_test() ->
  Self = #node{key = 1234},
  Id = 100,
  State = #chord_state{self = Self, fingers = create_finger_table(Id)},
  ?assertEqual(Self, find_successor(0, State)).


%% *** perform_stabilize tests ***
get_state_for_node_with_successor(NodeId, Succ) ->
  set_successor(Succ, #chord_state{self=nForKey(NodeId), fingers = create_finger_table(0)}).

% The successor hasn't changed
perform_stabilize_same_successor_test() ->
  % Successor is 5, own id is 0
  Succ = nForKey(5),
  State = get_state_for_node_with_successor(0, Succ),

  erlymock:start(),
  erlymock:strict(chord_tcp, get_predecessor, [Succ], [{return, {ok, Succ}}]),
  erlymock:replay(),

  ?assertEqual({ok, Succ}, perform_stabilize(State)),

  erlymock:verify().

% The successor has changed
perform_stabilize_updated_successor_test() ->
  % Successor is 5, own id is 0
  Succ = nForKey(10),
  State = get_state_for_node_with_successor(0, Succ),
  NewSuccessor = #node{key=3},

  erlymock:start(),
  erlymock:strict(chord_tcp, get_predecessor, [Succ], [{return, {ok, NewSuccessor}}]),
  erlymock:replay(),

  ?assertEqual({updated_succ, NewSuccessor}, perform_stabilize(State)),

  erlymock:verify().


%% *** Getting and setting the successor ***
get_successor_test() ->
  Id = 0,
  Self = nForKey(Id),
  Successor = nForKey(successorKey),
  Fingers = array:set(0, #finger_entry{node=Successor}, create_finger_table(Id)),
  State = #chord_state{self = Self, fingers = Fingers},
  ?assertEqual(Successor, get_successor(State)).
set_successor_test() ->
  Id = 0,
  Self = nForKey(Id),
  SuccessorOrig = nForKey(oldSuccessorKey),
  Fingers = array:set(0, #finger_entry{node=SuccessorOrig}, create_finger_table(Id)),
  State = #chord_state{self = Self, fingers = Fingers},
  NewSuccessor = nForKey(newSuccessor),
  ?assertEqual(NewSuccessor, get_successor(set_successor(NewSuccessor,State))).


%% *** Setting up finger table tests ***
% Test data from Chord paper.
get_start_test_() ->
  {inparallel,
   [
    ?_assertEqual(1, get_start(0, 0)),
    ?_assertEqual(2, get_start(0, 1)),
    ?_assertEqual(4, get_start(0, 2)),

    ?_assertEqual(2, get_start(1, 0)),
    ?_assertEqual(3, get_start(1, 1)),
    ?_assertEqual(5, get_start(1, 2)),
    
    ?_assertEqual(4, get_start(3, 0)),
    ?_assertEqual(5, get_start(3, 1)),
    ?_assertEqual(7, get_start(3, 2))
  ]}.
create_start_entries_test() ->
  NodeId = 0,
  Entries = create_start_entries(NodeId, 0, array:new(160)),
  ?assertEqual(get_start(NodeId, 0), (array:get(0,Entries))#finger_entry.start),
  ?assertEqual(get_start(NodeId, 1), (array:get(1,Entries))#finger_entry.start).
finger_entry_node_test_() ->
  {inparallel,
    [
      % For first node (k=1 (but thought of as 0 in this system)).
      ?_assertEqual(1, (finger_entry_node(0,0))#finger_entry.start),
      ?_assertEqual({1,2}, (finger_entry_node(0,0))#finger_entry.interval),

      % The last node (k=160 (but thought of as 159 in this system)).
      ?_assertEqual(trunc(math:pow(2,159)), (finger_entry_node(0,159))#finger_entry.start),
      ?_assertEqual({trunc(math:pow(2,159)),1}, (finger_entry_node(0,159))#finger_entry.interval),

      % Node with other Id (k=2 (but thought of as 1 in this system)).
      ?_assertEqual(7, (finger_entry_node(5,1))#finger_entry.start),
      ?_assertEqual({7,9}, (finger_entry_node(5,1))#finger_entry.interval),

      % It should not have defined the node itself
      ?_assertEqual(undefined, (finger_entry_node(0,0))#finger_entry.node)
    ]
  }.
create_finger_table_test() ->
  Id = 0,
  FingerTable = create_finger_table(Id),
  ?assertEqual(160, array:size(FingerTable)).

%% *** join tests ***
join_test() ->
  % Initial state
  Key = 1234,
  Predecessor = #node{key = 1234567890},
  State = #chord_state{predecessor = Predecessor, self = #node{key = Key}, fingers = create_finger_table(Key)},

  % The node to join
  JoinIp = {1,2,3,4},
  JoinPort = 4321,
  JoinNode = #node{ip = JoinIp, port=JoinPort},

  % Our successor node as given by the system
  SuccessorNode = #node{key = 20},

  erlymock:start(),
  erlymock:strict(chord_tcp, rpc_find_successor, [Key, JoinIp, JoinPort], [{return, {ok, SuccessorNode}}]),
  erlymock:replay(),

  {ok, NewState} = join(State, JoinNode),
  % Ensure the precesseccor has been removed
  ?assert((NewState#chord_state.predecessor)#node.key =/= 1234567890),
  % Make sure that it has set the right successor
  ?assertEqual(SuccessorNode, get_successor(NewState)),

  erlymock:verify().
    
-endif.
