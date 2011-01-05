-module(chord).
-behaviour(gen_server).

-define(SERVER, ?MODULE).
-define(NUMBER_OF_FINGERS, 160).
-define(MAX_NUM_OF_SUCCESSORS, 2).

%% @doc: the interval in miliseconds at which the routine tasks are performed
-define(FIX_FINGER_INTERVAL, 200).
-define(STABILIZER_INTERVAL, 500).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-include("../fs.hrl").
-include("chord.hrl").

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/0, start/0, stop/0]).
-export([lookup/1, set/2, preceding_finger/1, find_successor/1, get_predecessor/0, get_successor/0]).
-export([local_set/2, local_lookup/1]).
-export([notified/1]).
% Methods that need to be exported to me used by timers and local rpc's. Not for external use.
-export([stabilize/0, fix_fingers/0, check_node_for_predecessor/3]).

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

%% @doc: gets a value from the chord network
-spec(lookup/1::(Key::key()) -> [#entry{}]).
lookup(Key) ->
  Return = chord_tcp:rpc_lookup_key(Key, find_successor(Key)),
  {ok, Values} = Return,
  Values.

%% @doc: stores a value in the chord network
-spec(set/2::(Key::key(), Entry::#entry{}) -> ok).
set(Key, Entry) ->
  chord_tcp:rpc_set_key(Key, Entry, find_successor(Key)),
  ok.

%% @doc: get's a value from the local chord node
-spec(local_lookup/1::(Key::key()) -> {ok, [#entry{}]}).
local_lookup(Key) ->
  gen_server:call(chord, {local_lookup, Key}).

%% @doc: stores a value in the current local chord node
-spec(local_set/2::(Key::key(), Entry::#entry{}) -> {ok, ok}).
local_set(Key, Entry) ->
  gen_server:call(chord, {local_set, Key, Entry}).

-spec(preceding_finger/1::(Key::key()) -> {ok, {#node{}, #node{}}}).
preceding_finger(Key) ->
  gen_server:call(chord, {get_preceding_finger, Key}).

-spec(find_successor/1::(Key::key()) -> {ok, #node{}}).
find_successor(Key) ->
  gen_server:call(chord, {find_successor, Key}).

-spec(get_successor/0::() -> #node{}).
get_successor() ->
  gen_server:call(chord, get_successor).

-spec(get_predecessor/0::() -> #node{}).
get_predecessor() ->
  gen_server:call(chord, get_predecessor).

%% @doc Notified receives messages from predecessors identifying themselves.
%% If the node is a closer predecessor than the current one, then
%% the internal state is updated.
%% Additionally, and this is a hack to bootstrap the system,
%% if the current node doesn't have any successor, then add the predecessor
%% as the successor.
-spec(notified/1::(Node::#node{}) -> {ok, ignore}).
notified(Node) ->
  gen_server:cast(chord, {notified, Node}), 
  ignore.

%% ------------------------------------------------------------------
%% To be called by timer
%% ------------------------------------------------------------------

stabilize() -> gen_server:cast(chord, stabilize).
fix_fingers() -> gen_server:cast(chord, fix_fingers).

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
    fingers = FingerTable
  },

  case join(State) of
    {ok, JoinedState} ->
      % Create the tasks that run routinely
      {ok, TimerRefStabilizer} = 
          timer:apply_interval(?STABILIZER_INTERVAL, ?MODULE, stabilize, []),
      {ok, TimerRefFixFingers} = 
          timer:apply_interval(?FIX_FINGER_INTERVAL, ?MODULE, fix_fingers, []),

      State3 = JoinedState#chord_state{
        % Admin stuff
        timerRefStabilizer = TimerRefStabilizer,
        timerRefFixFingers = TimerRefFixFingers
      },
      
      {ok, State3};

    error ->
      {stop, couldnt_join_chord_network}
  end.

%% Call:
handle_call({remove_node, BadNode}, _From, State) ->
  {reply, ok, remove_node(BadNode, State)};

handle_call(get_state, _From, State) ->
  {reply, State, State};

handle_call({set_state, NewState}, _From, _State) ->
  {reply, ok, NewState};

handle_call(stop, _From, State) ->
  {stop, normal, ok, State};

handle_call({local_lookup, Key}, _From, State) ->
  {reply, datastore_srv:lookup(Key), State};

handle_call({local_set, Key, Entry}, _From, State) ->
  datastore_srv:set(Key, Entry),
  {reply, ok, State};

handle_call({get_preceding_finger, Key}, _From, State) ->
  Finger = closest_preceding_finger(Key, State),
  Succ = get_successor(State),
  Msg = {Finger, Succ},
  {reply, Msg, State};

handle_call({find_successor, Key}, From, State) ->
  spawn(fun() ->
    gen_server:reply(From, find_successor(Key, State))
  end),
  {noreply, State};

handle_call(get_successor, _From, State) ->
  {reply, get_successor(State), State};

handle_call(get_predecessor, _From, #chord_state{predecessor = Predecessor} = State) ->
  {reply, Predecessor, State}.

%% Casts:
handle_cast({notified, Node}, State) ->
  {noreply, perform_notify(Node, State)};

handle_cast({set_finger, N, NewFinger},  #chord_state{fingers = Fingers} = State) ->
  NewFingers = array:set(N, NewFinger, Fingers),
  NewState = State#chord_state{fingers = NewFingers},
  {noreply, NewState};

handle_cast({set_successor, Succ}, State) ->
  {noreply, set_successor(Succ, State)};

handle_cast(stabilize, #chord_state{self = Us} = State) ->
  Stabilize = fun() ->
    SuccessorsToUpdate = lists:flatten(perform_stabilize(State)),
    % Update our own state with the new successors
    [gen_server:cast(chord, {set_successor, Succ}) || {add_succ, Succ} <- SuccessorsToUpdate],
    % For good measure, we also notify the new nodes about our presence.
    [chord_tcp:notify_successor(Succ, Us) || {notify, Succ} <- SuccessorsToUpdate],
    % Extend the successor list so it is as long as we wish it to be
    extend_successor_list(State)
  end,
  % Perform stabilization    
  spawn(Stabilize),
  {noreply, State};

handle_cast(fix_fingers, State) ->
  FingerNumToFix = random:uniform(?NUMBER_OF_FINGERS) - 1,
  spawn(fun() -> fix_finger(FingerNumToFix, State) end),
  {noreply, State};

handle_cast(_Msg, State) ->
  {noreply, State}.

%% Info:
handle_info(_Info, State) ->
  {noreply, State}.

terminate(_Reason, State) ->
  % Tell the admin workers to stop what they are doing
  timer:cancel(State#chord_state.timerRefStabilizer),
  timer:cancel(State#chord_state.timerRefFixFingers).

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

% @doc: Fixes a given finger entry. If it's the 0th finger entry
% (ie: the successor list) then it is not fixed as that is done
% through the notify function.
-spec(fix_finger/2::(FingerNum::integer(), #chord_state{}) -> none()).
fix_finger(0, _) -> ok;
fix_finger(FingerNum, #chord_state{fingers = Fingers} = State) ->
  Finger = array:get(FingerNum, Fingers),
  Succ = find_successor(Finger#finger_entry.start, State),
  % If the successor is in the interval for the finger,
  % then update it, otherwise drop the successor.
  {Start, End} = Finger#finger_entry.interval,
  case (utilities:in_right_inclusive_range(Succ#node.key, Start, End)) of
    true ->
      UpdatedFinger = Finger#finger_entry{node = Succ},
      gen_server:cast(chord, {set_finger, FingerNum, UpdatedFinger});
    _ -> void
  end.


-spec(perform_stabilize/1::(#chord_state{}) -> 
    {ok, #node{}} | {ok, undefined} | {updated_succ, #node{}}).
perform_stabilize(#chord_state{self = ThisNode, fingers=Fingers}) ->
  % Get all our successors
  Successors = [F#finger_entry.node || F <- array:get(0, Fingers)],
  lists:filter(fun(undefined) -> false; (_) -> true end,
    rpc:pmap({?MODULE, check_node_for_predecessor}, [ThisNode, Successors], Successors)).

check_node_for_predecessor(Succ, ThisNode, KnownSuccessors) ->
  case chord_tcp:get_predecessor(Succ) of
    {ok, undefined} ->
      % The other node doesn't have a predecessor yet.
      % That is the case when it is a new chord ring.
      % By setting the node as a new successor we update
      % the state in ourselves and the successor.
      {notify, Succ};
    {ok, SuccPred} ->
      % Check if predecessor is between ourselves and successor
      case utilities:in_range(SuccPred#node.key, ThisNode#node.key, Succ#node.key) of 
        true  -> 
          % Do we already have this successor in our list?
          case lists:member(SuccPred, KnownSuccessors) of
            true ->
              % It is in range, but it is already known to us. Nothing that needs to be done.
              undefined;
            false ->
              % it is a successor in range that we didn't know about! Make ourselves known.
              [{notify, SuccPred}, {add_succ, SuccPred}]
          end;
        false -> 
          % This node is a predecessor of our successor, but is not between us and
          % our successor. Hence it must be anti clockwise of us in the chord key space.
          case SuccPred =:= ThisNode of
            true ->
              % Nothing to do. Aal izz wel.
              undefined;
            false ->
              % Our successor doesn't know about us.
              {notify, Succ}
          end
      end;
    {error, _Reason} ->
      % Something is wrong with this node, remove it
      remove_node(Succ),
      % There is not really anything to do... 
      undefined
  end.


-spec(create_finger_table/1::(NodeKey::key()) -> array()).
create_finger_table(NodeKey) ->
  create_start_entries(NodeKey, 0, array:new(160)).


-spec(create_start_entries/3::(NodeKey::key(), N::integer(), Array::array()) -> 
    array()).
create_start_entries(_NodeKey, 160, Array) -> Array;
create_start_entries(NodeKey, 0, Array) ->
  N = 0, % This is the successor list
  create_start_entries(NodeKey, N+1, array:set(N, [], Array));
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
    -> #node{}).
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
      case utilities:in_right_inclusive_range(Key, NodeId, Succ#node.key) of
        true  -> Succ;
        % Try looking successively through successors successors.
        false -> 
          case find_successor(Key, Succ) of
            % finding successor failed in the first instance.
            % Remove the offending node and try again.
            {error, bad_node, BadNode} ->
              io:format("Couldn't connect to bad node: ~p. Remove it.~n", [BadNode]),
              remove_node(BadNode),
              % Now that that is done, try again
              find_successor(Key, State);

            % We successfully found a good value. Now return it.
            Val -> Val
          end
      end
  end;
find_successor(Key, #node{key = NKey} = CurrentNext) ->
  case chord_tcp:rpc_get_closest_preceding_finger_and_succ(Key, CurrentNext) of
    {ok, {NextFinger, NSucc}} ->
      case utilities:in_right_inclusive_range(Key, NKey, NSucc#node.key) of
        true  -> NSucc;
        false -> find_successor(Key, NextFinger)
      end;
    {error, _Reason} ->
      % We couldn't connect to a node.
      % We remove it from our tables.
      {error, bad_node, CurrentNext}
  end.


% @doc: calls the server and has it remove a bad node.
-spec(remove_node/1::(BadNode::#node{}) -> ok).
remove_node(BadNode) ->
  gen_server:call(?MODULE, {remove_node, BadNode}).
-spec(remove_node/2::(BadNode::#node{}, State::#chord_state{}) -> #chord_state{}).
remove_node(BadNode, State) ->
  io:format("Removing bad node: ~p~n", [BadNode]),
  NoPred = remove_node_from_predecessor(BadNode, State),
  remove_node_from_fingers(BadNode, NoPred).

remove_node_from_predecessor(BadNode, #chord_state{predecessor = Node} = State) when BadNode =:= Node ->
  State#chord_state{predecessor = undefined};
remove_node_from_predecessor(_, State) -> State.

remove_node_from_fingers(BadNode, #chord_state{fingers = Fingers} = State) ->
  State#chord_state{fingers = 
    array:map(
      fun(_, #finger_entry{node = Node} = Finger) when BadNode =:= Node -> Finger#finger_entry{node = undefined};
         (_, Successors) when is_list(Successors) -> 
           lists:filter(fun(#finger_entry{node=N}) when N =:= BadNode -> false; (_) -> true end, Successors);
         (_, F) -> F
      end,
      Fingers)
  }.


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
closest_preceding_finger(Key, Fingers, 0, CurrentNode) ->
  FingerNode = get_first_successor(array:get(0, Fingers)),
  check_closest_preceding_finger(Key, FingerNode, Fingers, 0, CurrentNode);
closest_preceding_finger(Key, Fingers, CurrentFinger, CurrentNode) ->
  FingerNode = (array:get(CurrentFinger, Fingers))#finger_entry.node,
  check_closest_preceding_finger(Key, FingerNode, Fingers, CurrentFinger, CurrentNode).

check_closest_preceding_finger(Key, undefined, Fingers, CurrentFinger, CurrentNode) ->
  % The finger entry is empty. We skip it
  closest_preceding_finger(Key, Fingers, CurrentFinger-1, CurrentNode);
check_closest_preceding_finger(Key, #node{key = NodeId} = Node, Fingers, CurrentFinger, CurrentNode) ->
  case ((CurrentNode#node.key < NodeId) andalso (NodeId < Key)) of
    true -> Node;
    false -> closest_preceding_finger(Key, Fingers, CurrentFinger-1, CurrentNode)
  end.


%% @doc: joins another chord node and returns the updated chord state
-spec(join/1::(State::#chord_state{}) -> 
    {ok, #chord_state{}} | error).
join(State) -> 
  OwnIp = (State#chord_state.self)#node.ip,
  OwnPort = (State#chord_state.self)#node.port,

  % We are joining the network, so we don't yet have a predecessor
  PredState = State#chord_state{predecessor = undefined},

  % Get node that can be used to join the chord network:
  case utilities:get_join_nodes(OwnIp, OwnPort) of
    first ->
      % We are the first in the network. Return the current state.
      {ok, PredState};
    JoinNodes ->
      perform_join(JoinNodes, PredState)
  end.

perform_join([], _State) -> error;
perform_join([{JoinIp, JoinPort}|Ps], State) ->
  io:format("Trying to join ~p:~p~n", [JoinIp, JoinPort]),
  OwnKey = (State#chord_state.self)#node.key,
  % Find the successor node using the given node
  case chord_tcp:rpc_find_successor(OwnKey, JoinIp, JoinPort) of
    {ok, Succ} ->
      {ok, set_successor(Succ, State)};
    {error, _} ->
      perform_join(Ps, State)
  end.


%% @doc: returns the successor in the local finger table
-spec(get_successor/1::(State::#chord_state{}) -> #node{} | undefined).
get_successor(State) ->
  Fingers = State#chord_state.fingers,
  SuccessorFingers = array:get(0, Fingers),
  get_first_successor(SuccessorFingers).
get_first_successor(SuccessorFingers) ->
  case lists:sublist(SuccessorFingers, 1) of
    [] -> undefined;
    [Finger] -> Finger#finger_entry.node
  end.


% @doc: sets the successor and returns the updated state.
-spec(set_successor/2::(Successor::#node{}, State::#chord_state{}) ->
    #chord_state{}).
set_successor(Successor, #chord_state{self = Self} = State) when Successor =:= Self -> State;
set_successor(Successor, State) ->
  Fingers = State#chord_state.fingers,
  FingerList = array:get(0, Fingers),
  Self = State#chord_state.self,
  UpdatedFingers = array:set(0, 
    case lists:member(Successor, [F#finger_entry.node || F <- FingerList]) of
      true -> FingerList;
      false -> sort_successors([#finger_entry{node=Successor} | FingerList], Self)
    end, Fingers),
  State#chord_state{fingers = UpdatedFingers}.


% @doc: sorts the successor list such that the successors are in order
% of increasing distance along the chord key space.
-spec(sort_successors/2::(FingerList::[#finger_entry{}], Self::#node{}) -> [#finger_entry{}]).
sort_successors(FingerList, Self) -> 
  SortedList = lists:sort(
    fun(#finger_entry{node=A},#finger_entry{node=B}) -> A#node.key =< B#node.key end,
    FingerList),
  Smaller = lists:takewhile(
    fun(#finger_entry{node=Node}) -> Node#node.key < Self#node.key end,
    SortedList),
  lists:sublist((SortedList -- Smaller) ++ Smaller, ?MAX_NUM_OF_SUCCESSORS).


-spec(perform_notify/2::(Node::#node{}, State::#chord_state{}) ->
    #chord_state{}).
perform_notify(Node, #chord_state{predecessor = undefined} = State) ->
  set_successor(Node, State#chord_state{predecessor = Node});
perform_notify(#node{key = NewKey} = Node, 
    #chord_state{predecessor = Pred, self = Self} = State) ->
  case utilities:in_range(NewKey, Pred#node.key, Self#node.key) of
    true  -> State#chord_state{predecessor = Node};
    false -> State
  end.


% @doc: Extends the successor list if it isn't as long as desired
-spec(extend_successor_list/1::(State::#chord_state{}) -> ok).
extend_successor_list(#chord_state{fingers = Fingers}) ->
  Successors = array:get(0, Fingers),
  case length(Successors) < ?MAX_NUM_OF_SUCCESSORS andalso Successors =/= [] of 
    true ->
      LastSuccessorNode = (hd(lists:reverse(Successors)))#finger_entry.node,
      case chord_tcp:rpc_get_successor(LastSuccessorNode) of
        {ok, NextSucc} -> gen_server:cast(?MODULE, {set_successor, NextSucc});
        {error, _} -> remove_node(LastSuccessorNode)
      end;
    false ->
      % Successor list is up to date!
      ok
  end.


%% ------------------------------------------------------------------
%% Tests
%% ------------------------------------------------------------------

-ifdef(TEST).

nForKey(Key) -> #node{key = Key}.
  
%% @todo: Missing test that checks that notify actually works!
%%        Missing test where the successors predecessor is not ourself.

test_get_empty_state() ->
  #chord_state{fingers = create_finger_table(0), self = nForKey(0)}.

test_get_state() ->
  Fingers = array:set(0, [#finger_entry{start = 1, interval = {1,2}, node = nForKey(1)}],
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
  ?assertEqual(get_successor(State), find_successor(1, State)).

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
  ?assertEqual(NextSuccessor, find_successor(Key, State)),
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
  ?assertEqual(SecondNextSuccessor, find_successor(Key, State)),
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

perform_stabilize_with_empty_state_test() ->
  State = test_get_empty_state(),
  ?assertEqual(undefined, get_successor(State)),
  ?assertEqual([], perform_stabilize(State)).

perform_stabilize_successor_has_earlier_predecessor_test() ->
  % Successor is 5, own id is 0
  OurId = 1,
  EarlierNode = nForKey(0),

  Succ = nForKey(5),
  State = get_state_for_node_with_successor(OurId, Succ),

  erlymock:start(),
  erlymock:strict(chord_tcp, get_predecessor, [Succ], [{return, {ok, EarlierNode}}]),
  erlymock:replay(),

  % As the successor hasn't changed, we don't need to do any work
  ?assertEqual([{notify, Succ}], perform_stabilize(State)),

  erlymock:verify().

% The successor hasn't changed
perform_stabilize_same_successor_test() ->
  % Successor is 5, own id is 0
  OurId = 0,
  Us = nForKey(OurId),

  Succ = nForKey(5),
  State = get_state_for_node_with_successor(OurId, Succ),

  erlymock:start(),
  erlymock:strict(chord_tcp, get_predecessor, [Succ], [{return, {ok, Us}}]),
  erlymock:replay(),

  % As the successor hasn't changed, we don't need to do any work
  ?assertEqual([], perform_stabilize(State)),

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

  ?assertEqual([[{notify, NewSuccessor},{add_succ, NewSuccessor}]], perform_stabilize(State)),

  erlymock:verify().


%% *** Getting and setting the successor ***
get_successor_test() ->
  Id = 0,
  Self = nForKey(Id),
  Successor = nForKey(1),
  Fingers = array:set(0, [#finger_entry{node=Successor}], create_finger_table(Id)),
  State = #chord_state{self = Self, fingers = Fingers},
  ?assertEqual(Successor, get_successor(State)).
set_successor_test() ->
  Id = 0,
  Self = nForKey(Id),
  SuccessorOrig = nForKey(5),
  Fingers = array:set(0, [#finger_entry{node=SuccessorOrig}], create_finger_table(Id)),
  State = #chord_state{self = Self, fingers = Fingers},
  NewSuccessor = nForKey(2),
  UpdatedState = set_successor(NewSuccessor, State),
  ?assertEqual(NewSuccessor, get_successor(UpdatedState)),
  % Update with a successor that is not closer...
  NotClosest = nForKey(4),
  UpdatedState2 = set_successor(NotClosest, UpdatedState),
  % Should not set the successor that is further away as the successor
  ?assertEqual(NewSuccessor, get_successor(UpdatedState2)),
  % Try updating again with one that isn't closer, but additionally that
  % we already have in the successor list
  UpdatedState3 = set_successor(NotClosest, UpdatedState2),
  % Should not set the successor that is further away as the successor
  ?assertEqual(NewSuccessor, get_successor(UpdatedState3)).
set_successor_shouldnt_allow_self_test() ->
  Id = 0,
  Self = nForKey(Id),
  Fingers = create_finger_table(Id),
  State = #chord_state{self = Self, fingers = Fingers},
  ?assertEqual(undefined, get_successor(State)),

  UpdatedState = set_successor(Self, State),

  ?assertEqual(undefined, get_successor(UpdatedState)).


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
  ?assertEqual([], array:get(0,Entries)),
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
  OwnIp = {1,2,3,4},
  OwnPort = 88,
  Key = 1234,
  Predecessor = #node{key = 1234567890},
  State = #chord_state{
    predecessor = Predecessor, 
    self = #node{
      key = Key,
      ip = OwnIp,
      port = OwnPort
    }, 
    fingers = create_finger_table(Key)
  },

  % The nodes to join
  FailingJoinIp = {1,2,3,4},
  FailingJoinPort = 4321,
  JoinIp = {1,2,3,4},
  JoinPort = 4321,
  HubNodes = [{FailingJoinIp, FailingJoinPort}, {JoinIp, JoinPort}],

  % Our successor node as given by the system
  SuccessorNode = #node{key = 20},

  erlymock:start(),
  erlymock:strict(utilities, get_join_nodes, [OwnIp, OwnPort], [{return, HubNodes}]),
  erlymock:strict(chord_tcp, rpc_find_successor, [Key, FailingJoinIp, FailingJoinPort], [{return, {error, timeout}}]),
  erlymock:strict(chord_tcp, rpc_find_successor, [Key, JoinIp, JoinPort], [{return, {ok, SuccessorNode}}]),
  erlymock:replay(),

  {ok, NewState} = join(State),
  % Ensure the precesseccor has been removed
  ?assert(NewState#chord_state.predecessor =/= Predecessor),
  % Make sure that it has set the right successor
  ?assertEqual(SuccessorNode, get_successor(NewState)),

  erlymock:verify().

    
%% *** cast notified tests ***
perform_notify_no_previous_predecessor_test() ->
  % Being notified when you have no previous predecessor
  % should set the predecessor.
  State = test_get_empty_state(),
  NewNode = nForKey(1234),
  NewState = perform_notify(NewNode, State),
  ?assertEqual(NewNode, NewState#chord_state.predecessor).
perform_notify_no_successor_test() ->
  % If there is no successor in the state, then the predecessor
  % should also become the successor.
  State = test_get_empty_state(),
  NewNode = #node{key=1234},
  NewState = perform_notify(NewNode, State),
  ?assertEqual(NewNode, get_successor(NewState)).
perform_notify_should_update_newer_predecessors_test() ->
  % If the predecessor is closer in the chord ring than
  % the one currently in the state, then update the state.
  OldPred = nForKey(1),
  NewPred = nForKey(2),
  State = #chord_state{predecessor = OldPred, self=nForKey(3)},
  NewState = perform_notify(NewPred, State),
  ?assertEqual(NewPred, NewState#chord_state.predecessor).

remove_node_test() ->
  % The bad node is both a successor, predecessor AND a normal finger... get that if you can :)
  BadNode = nForKey(1),
  State = (test_get_state())#chord_state{predecessor = BadNode},
  Fingers = State#chord_state.fingers,
  BadFinger = (array:get(1,Fingers))#finger_entry{node=BadNode},
  BadState = State#chord_state{fingers = array:set(1, BadFinger, Fingers)},
  ?assert(doesnt_contain_node(BadNode, remove_node(BadNode, BadState))).

doesnt_contain_node(Node, State) ->
  State#chord_state.predecessor =/= Node andalso
    no_bad_fingers(Node, State#chord_state.fingers).

no_bad_fingers(Node, Fingers) ->
  array:foldl(
    fun(_, _, false) -> false;
       (_, F, _) when is_list(F) -> 
         F =:= lists:filter(fun(#finger_entry{node=A}) -> A =/= Node end, F);
       (_, F, _) when is_record(F, finger_entry) ->
          F#finger_entry.node =/= Node
    end, true, Fingers).

sort_successors_test() ->
  Self = nForKey(10),
  Successors = [
    #finger_entry{node = nForKey(20)},
    #finger_entry{node = nForKey(80)},
    #finger_entry{node = nForKey(15)},
    #finger_entry{node = nForKey(9)},
    #finger_entry{node = nForKey(0)}
  ],
  ?assertEqual([
    #finger_entry{node = nForKey(15)},
    #finger_entry{node = nForKey(20)},
    #finger_entry{node = nForKey(80)},
    #finger_entry{node = nForKey(0)},
    #finger_entry{node = nForKey(9)}
  ], sort_successors(Successors, Self)).

extend_successor_list_test() ->
  OurId = 1,
  Succ = nForKey(5),
  State = get_state_for_node_with_successor(OurId, Succ),
  SuccSucc = nForKey(10),

  erlymock:start(),
  erlymock:strict(chord_tcp, rpc_get_successor, [Succ], [{return, {ok, SuccSucc}}]),
  erlymock:replay(),

  extend_successor_list(State),

  erlymock:verify().

extend_successor_list_enough_successor_test() ->
  OurId = 1,
  Succ = nForKey(2),
  Successors = [nForKey(Id) || Id <- lists:seq(3, ?MAX_NUM_OF_SUCCESSORS + 2)],

  State = lists:foldl(fun(NS, CS) -> set_successor(NS, CS) end, 
    get_state_for_node_with_successor(OurId, Succ), Successors),

  erlymock:start(),
  % Shouldn't call anything... enough successors already!
  erlymock:replay(),

  extend_successor_list(State),

  erlymock:verify().

-endif.
