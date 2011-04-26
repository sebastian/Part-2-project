-module(chord).
-behaviour(gen_server).

-define(SERVER, ?MODULE).
-define(NUMBER_OF_FINGERS, 160).
-define(MAX_NUM_OF_SUCCESSORS, 5).

%% @doc: the interval in miliseconds at which the routine tasks are performed
-define(FIX_FINGER_INTERVAL, 1000).
-define(STABILIZER_INTERVAL, 5000).

-include("../fs.hrl").
-include("chord.hrl").

%% ------------------------------------------------------------------
%% Public API
%% ------------------------------------------------------------------

-export([start_link/1, start/1, stop/1]).
-export([lookup/2, set/3]).

%% ------------------------------------------------------------------
%% PRIVATE API Function Exports
%% ------------------------------------------------------------------

-export([preceding_finger/2, find_successor/2, get_predecessor/1, get_successor/1]).
-export([local_set/3, local_lookup/2]).
-export([notified/2]).
% Methods that need to be exported to me used by timers and local rpc's. Not for external use.
-export([
    stabilize/1, 
    fix_fingers/1, 
    check_node_for_predecessor/4,
    receive_entries/2,
    ping/1
  ]).
% For use by the controller to limit the amount of traffic
% during experiments
-export([
    start_timers/1,
    stop_timers/1
  ]).
% For debugging
-export([output_diagnostics/1]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start(Args) ->
  supervisor:start_child(chord_sofo, Args).

start_link(Args) ->
  gen_server:start_link(?MODULE, Args, []).

stop(Pid) ->
  gen_server:call(Pid, stop).

%% @doc: gets a value from the chord network
-spec(lookup/2::(pid(), Key::key()) -> [#entry{}]).
lookup(Pid, Key) ->
  logger:log(Pid, Key, start_lookup),
  case find_successor(Pid, Key) of
    error ->
      io:format("Failed at finding the successor...~n"),
      error;
    {ok, Successor} ->
      {ok, Return} = chord_tcp:rpc_lookup_key(Key, Successor),
      logger:log(Pid, Key, end_lookup),
      Return
  end.

%% @doc: stores a value in the chord network
-spec(set/3::(pid(), Key::key(), Entry::#entry{}) -> ok).
set(Pid, Key, Entry) ->
  case find_successor(Pid, Key) of
    error ->
      io:format("Couldn't store the value. Failed to find owner.~n");
    {ok, Successor} ->
      chord_tcp:rpc_set_key(Key, Entry, Successor),
      ok
  end.

%% @doc: get's a value from the local chord node
-spec(local_lookup/2::(pid(), Key::key()) -> {ok, [#entry{}]}).
local_lookup(Pid, Key) ->
  logger:log(Pid, Key, lookup_datastore),
  gen_server:call(Pid, {local_lookup, Key}).

%% @doc: stores a value in the current local chord node
-spec(local_set/3::(pid(), Key::key(), Entry::#entry{}) -> {ok, ok}).
local_set(Pid, Key, Entry) ->
  logger:log(Pid, Key, set_datastore),
  gen_server:call(Pid, {local_set, Key, Entry}).

-spec(preceding_finger/2::(pid(), Key::key()) -> {ok, {#node{}, #node{}}}).
preceding_finger(Pid, Key) ->
  gen_server:call(Pid, {get_preceding_finger, Key}).

-spec(find_successor/2::(pid(), Key::key()) -> {ok, #node{}}).
find_successor(Pid, Key) ->
  gen_server:call(Pid, {find_successor, Key}).

-spec(get_successor/1::(pid()) -> #node{}).
get_successor(Pid) ->
  gen_server:call(Pid, get_successor).

-spec(get_predecessor/1::(pid()) -> #node{}).
get_predecessor(Pid) ->
  gen_server:call(Pid, get_predecessor).

-spec(receive_entries/2::(pid(), Entries::[#entry{}]) -> ok).
receive_entries(Pid, Entries) ->
  gen_server:cast(Pid, {receive_entries, Entries}),
  ok.

ping(Pid) ->
  gen_server:call(Pid, ping).

%% @doc Notified receives messages from predecessors identifying themselves.
%% If the node is a closer predecessor than the current one, then
%% the internal state is updated.
%% Additionally, and this is a hack to bootstrap the system,
%% if the current node doesn't have any successor, then add the predecessor
%% as the successor.
-spec(notified/2::(pid(), Node::#node{}) -> {ok, ignore}).
notified(Pid, Node) ->
  gen_server:cast(Pid, {notified, Node}), 
  ignore.

start_timers(Pid) ->
  gen_server:cast(Pid, start_timers).

stop_timers(Pid) ->
  gen_server:cast(Pid, stop_timers).

output_diagnostics(Pid) ->
  gen_server:call(Pid, output_diagnostics).

%% ------------------------------------------------------------------
%% To be called by timer
%% ------------------------------------------------------------------

stabilize(Pid) -> gen_server:cast(Pid, stabilize).
fix_fingers(Pid) -> gen_server:cast(Pid, fix_fingers).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(Args) -> 
  SelfPid = self(),
  ControllingProcess = proplists:get_value(controllingProcess, Args),
  controller:register_dht(ControllingProcess, SelfPid, undefined),
  Port = receive {port, TcpPort} -> TcpPort end,

  case join(Port, ControllingProcess) of
    {ok, State} ->
      controller:dht_successfully_started(ControllingProcess),
      {ok, do_start_timers(State)};

    error ->
      controller:dht_failed_start(ControllingProcess),
      {stop, couldnt_join_chord_network}
  end.

%% @doc: joins another chord node and returns the updated chord state
-spec(join/2::(number(), pid()) -> {ok, #chord_state{}} | error).
join(Port, ControllingProcess) -> 
  repeatedly_try_to_join(Port, ControllingProcess, undefined, 5).

repeatedly_try_to_join(_Port, ControllingProcess, Reason, 0) ->
  controller:dht_failed_start(ControllingProcess),
  {stop, {couldnt_rendevouz, Reason}};
repeatedly_try_to_join(Port, ControllingProcess, _Reason, N) ->
  case chord_tcp:rendevouz(Port, ?RENDEVOUZ_HOST, ?RENDEVOUZ_PORT) of
    {MyIp, first} -> {ok, post_rendevouz_state_update(MyIp, Port)};
    {error, Reason} -> 
      % The hub_controller must be overloaded. Wait and try again
      error_logger:error_msg("Couldn't rendevouz. Retrying after a little while. ~p more attempts~n", [N]),
      receive after random:uniform(10) * 1000 -> ok end,
      repeatedly_try_to_join(Port, ControllingProcess, Reason, N - 1);
    {MyIp, Nodes} -> perform_join(Nodes, post_rendevouz_state_update(MyIp, Port))
  end.

post_rendevouz_state_update(Ip, Port) ->
  io:format("Setting up node with Ip: ~p, Port: ~p~n", [Ip, Port]),
  Self = #node{
    ip = Ip,
    port = Port,
    key = utilities:key_for_node(Ip, Port)
  },
  #chord_state{
    self = Self,
    fingers = create_finger_table(Self#node.key),
    chord_pid = self()
  }.

perform_join([], _State) -> error;
perform_join([{JoinIp, JoinPort}|Ps], #chord_state{self = #node{key = OwnKey}} = State) ->
  % Find the successor node using the given node
  case chord_tcp:rpc_find_successor(OwnKey, JoinIp, JoinPort) of
    {ok, Succ} -> {ok, set_successor(Succ, State)};
    {error, _} ->
      perform_join(Ps, State)
  end.


%% Call:
handle_call(output_diagnostics, _From, State) ->
  Successors = perform_get_successor(State),
  {reply, Successors, State};

handle_call(ping, _From, State) ->
  {reply, pong, State};

handle_call({remove_node, BadNode}, _From, State) ->
  NewState = perform_remove_node(BadNode, State),
  {reply, NewState, NewState};

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
  % Now we need to replicate the entry to our successors:
  replicate_entry(Entry, State),
  {reply, ok, State};

handle_call({get_preceding_finger, Key}, _From, State) ->
  Msg = {
    closest_preceding_finger(Key, State),
    perform_get_successor(State)
  },
  {reply, Msg, State};

handle_call({find_successor, Key}, From, State) ->
  spawn(fun() ->
    gen_server:reply(From, perform_find_successor(Key, State))
  end),
  {noreply, State};

handle_call(get_successor, _From, State) ->
  {reply, perform_get_successor(State), State};

handle_call(get_predecessor, _From, #chord_state{predecessor = Predecessor} = State) ->
  {reply, Predecessor, State}.

%% Casts:
handle_cast(start_timers, State) ->
  {noreply, do_start_timers(State)};

handle_cast(stop_timers, State) ->
  {noreply, do_stop_timers(State)};

handle_cast({notified, Node}, State) ->
  {noreply, perform_notify(Node, State)};

handle_cast({set_finger, N, NewFinger},  #chord_state{fingers = Fingers} = State) ->
  NewFingers = array:set(N, NewFinger, Fingers),
  NewState = State#chord_state{fingers = NewFingers},
  {noreply, NewState};

handle_cast({set_successor, Succ}, State) ->
  {noreply, set_successor(Succ, State)};

handle_cast(stabilize, #chord_state{self = Us, chord_pid = Pid} = State) ->
  Stabilize = fun() ->
    SuccessorsToUpdate = lists:flatten(perform_stabilize(State)),
    % Update our own state with the new successors
    [gen_server:cast(Pid, {set_successor, Succ}) || {add_succ, Succ} <- SuccessorsToUpdate],
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

handle_cast({receive_entries, Entries}, State) ->
  spawn(fun() -> [datastore_srv:set(E#entry.key, E) || E <- Entries] end),
  {noreply, State};

handle_cast(Msg, State) ->
  error_logger:error_msg("received unknown cast: ~p", [Msg]),
  {noreply, State}.

%% Info:
handle_info(_Info, State) ->
  {noreply, State}.

terminate(_Reason, State) ->
  do_stop_timers(State).

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

do_start_timers(#chord_state{chord_pid = SelfPid, timerRefStabilizer = undefined, timerRefFixFingers = undefined} = State) ->
  io:format("Starting timer~n"),
  {ok, TimerRefStabilizer} = 
      timer:apply_interval(?STABILIZER_INTERVAL, ?MODULE, stabilize, [SelfPid]),
  {ok, TimerRefFixFingers} = 
      timer:apply_interval(?FIX_FINGER_INTERVAL, ?MODULE, fix_fingers, [SelfPid]),

  State#chord_state{
    % Admin stuff
    timerRefStabilizer = TimerRefStabilizer,
    timerRefFixFingers = TimerRefFixFingers
  };
do_start_timers(State) -> 
  io:format("avoiding timer duplicated start~n"),
  State.

do_stop_timers(#chord_state{timerRefStabilizer = T1, timerRefFixFingers = T2} = State) ->
  io:format("Stopping timer~n"),
  timer:cancel(T1),
  timer:cancel(T2),
  State#chord_state{timerRefStabilizer = undefined, timerRefFixFingers = undefined}.

% @doc: Fixes a given finger entry. If it's the 0th finger entry
% (ie: the successor list) then it is not fixed as that is done
% through the notify function.
-spec(fix_finger/2::(FingerNum::integer(), #chord_state{}) -> none()).
fix_finger(0, _) -> ok;
fix_finger(FingerNum, #chord_state{chord_pid = Pid, fingers = Fingers} = State) ->
  Finger = array:get(FingerNum, Fingers),
  case perform_find_successor(Finger#finger_entry.start, State) of
    {ok, Succ} ->
      case is_record(Succ, node) of
        true ->
          % If the successor is in the interval for the finger,
          % then update it, otherwise drop the successor.
          {Start, End} = Finger#finger_entry.interval,
          case (utilities:in_right_inclusive_range(Succ#node.key, Start, End)) of
            true ->
              UpdatedFinger = Finger#finger_entry{node = Succ},
              gen_server:cast(Pid, {set_finger, FingerNum, UpdatedFinger});
            _ -> void
          end;
        false ->
          ok
      end;
    error ->
      io:format("Failed at fixing finger, because couldn't lookup the successor node~n")
  end.


-spec(perform_stabilize/1::(#chord_state{}) -> 
    {ok, #node{}} | {ok, undefined} | {updated_succ, #node{}}).
perform_stabilize(#chord_state{chord_pid = Pid, self = ThisNode, fingers=Fingers}) ->
  % Get all our successors
  Successors = [F#finger_entry.node || F <- array:get(0, Fingers)],
  lists:filter(fun(undefined) -> false; (_) -> true end,
    rpc:pmap({?MODULE, check_node_for_predecessor}, [ThisNode, Successors, Pid], Successors)).

check_node_for_predecessor(Succ, ThisNode, KnownSuccessors, Pid) ->
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
      remove_node(Pid, Succ),
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


-record(pred_info, {
    node,
    successor
  }).

%% @doc: Returns the node succeeding a key.
-spec(perform_find_successor/2::(Key::key(), #chord_state{}) -> {ok, #node{}} | error).
perform_find_successor(Key, #chord_state{self = Self} = State) -> 
  % in the case we are the only party in a chord circle,
  % then we are also our own successors.
  case closest_preceding_finger(Key, State) of
    Self -> {ok, Self};
    OtherNode -> 
      case perform_find_predecessor(Key, OtherNode) of
        error -> error;
        Predecessor-> {ok, Predecessor#pred_info.successor}
      end
  end.

perform_find_predecessor(Key, Node) ->
  case chord_tcp:rpc_get_closest_preceding_finger_and_succ(Key, Node) of
    {ok, {NextClosest, NodeSuccessor}} ->
      case utilities:in_right_inclusive_range(Key, Node#node.key, NodeSuccessor#node.key) of
        true -> 
          #pred_info{
            node = Node,
            successor = NodeSuccessor
          };
        false ->
          perform_find_predecessor(Key, NextClosest)
      end;
    {error, _Reason} ->
      error
  end.


% @doc: calls the server and has it remove a bad node.
remove_node(Pid, BadNode) -> gen_server:call(Pid, {remove_node, BadNode}).

perform_remove_node(BadNode, State) ->
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


% Returns the node in the finger table of the current node
% that most closely precedes a given key.
closest_preceding_finger(Key, #chord_state{chord_pid = Pid} = State) ->
  logger:log(Pid, Key, route), % This means it will be logged once per node that is touched
  closest_preceding_finger(Key, 
    State#chord_state.fingers, array:size(State#chord_state.fingers) - 1,
    State#chord_state.self).

closest_preceding_finger(_Key, _Fingers, -1, Self) -> Self;
closest_preceding_finger(Key, Fingers, 0, Self) ->
  % The current finger is the successor finger.
  % Get the closest successor from the list of successors
  FingerNode = get_first_successor(array:get(0, Fingers)),
  check_closest_preceding_finger(Key, FingerNode, Fingers, 0, Self);
closest_preceding_finger(Key, Fingers, FingerIndex, Self) ->
  FingerNode = (array:get(FingerIndex, Fingers))#finger_entry.node,
  check_closest_preceding_finger(Key, FingerNode, Fingers, FingerIndex, Self).

% We check if the node for a given finger entry is between ourselves
% and the key we are looking for. Since we are looking through the finger
% table for nodes that are successively closer to ourself, we are bound
% to end up with the node most closely preceding the key that we know about.
check_closest_preceding_finger(Key, undefined, Fingers, FingerIndex, Self) ->
  % The finger entry is empty. We skip it
  closest_preceding_finger(Key, Fingers, FingerIndex-1, Self);
check_closest_preceding_finger(Key, Node, Fingers, FingerIndex, Self) ->
  case utilities:in_range(Node#node.key, Self#node.key, Key) of
    true -> 
      % This is the key in our routing table that is closest
      % to the destination key. Return it.
      Node;
    false -> 
      % The current finger is greater than the key. Try closer fingers
      closest_preceding_finger(Key, Fingers, FingerIndex-1, Self)
  end.


%% @doc: returns the successor in the local finger table
-spec(perform_get_successor/1::(State::#chord_state{}) -> #node{} | undefined).
perform_get_successor(State) ->
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
set_successor(undefined, State) -> State;
set_successor(Successor, #chord_state{self = Self} = State) when Successor =:= Self -> State;
set_successor(Successor, #chord_state{predecessor = Predecessor, self = Self} = State) ->
  Fingers = State#chord_state.fingers,
  FingerList = array:get(0, Fingers),
  Self = State#chord_state.self,
  UpdatedFingers = array:set(0, 
    case lists:member(Successor, [F#finger_entry.node || F <- FingerList]) of
      true -> FingerList;
      false -> 
        % We have to transfer our data to this successor for replication
        if Predecessor =/= undefined ->
            transfer_data_in_range(Predecessor#node.key, Self#node.key, Successor);
          true -> ok
        end,
        sort_successors([#finger_entry{node=Successor} | FingerList], Self)
    end, Fingers),
  State#chord_state{fingers = UpdatedFingers}.


% @doc: sorts the successor list such that the successors are in order
% of increasing distance along the chord key space.
-spec(sort_successors/2::(FingerList::[#finger_entry{}], Self::#node{}) -> [#finger_entry{}]).
sort_successors(FingerList, Self) -> 
  NodeList = lists:filter(fun(N) -> is_record(N#finger_entry.node, node) end, FingerList),
  SortedList = lists:sort(
    fun(#finger_entry{node=A},#finger_entry{node=B}) -> A#node.key =< B#node.key end,
    NodeList),
  Smaller = lists:takewhile(
    fun(#finger_entry{node=Node}) -> Node#node.key < Self#node.key end,
    SortedList),
  lists:sublist((SortedList -- Smaller) ++ Smaller, ?MAX_NUM_OF_SUCCESSORS).


-spec(perform_notify/2::(Node::#node{}, State::#chord_state{}) ->
    #chord_state{}).
perform_notify(Node, #chord_state{predecessor = undefined} = State) ->
  set_predecessor(Node, set_successor(Node, State));
perform_notify(#node{key = NewKey} = Node, 
    #chord_state{predecessor = Pred, self = Self} = State) ->
  case utilities:in_range(NewKey, Pred#node.key, Self#node.key) of
    true  -> set_predecessor(Node, State);
    false -> State
  end.


-spec(set_predecessor/2::(Predecessor::#node{}, State::#chord_state{}) -> #chord_state{}).
set_predecessor(Predecessor, #chord_state{self = Self} = State) -> 
  case transfer_data_in_range(Self#node.key, Predecessor#node.key, Predecessor) of
    ok -> State#chord_state{predecessor = Predecessor};
    error -> perform_remove_node(Predecessor, State)
  end.


transfer_data_in_range(Start, End, Node) ->
  case datastore_srv:get_entries_in_range(Start, End) of
    [] -> ok; % no data to transfer
    Data -> case chord_tcp:rpc_send_entries(Data, Node) of
        {ok, _} -> ok; 
        {error, _} -> error 
      end
  end.


% @doc: Extends the successor list if it isn't as long as desired
-spec(extend_successor_list/1::(State::#chord_state{}) -> ok).
extend_successor_list(#chord_state{chord_pid = Pid, fingers = Fingers}) ->
  Successors = array:get(0, Fingers),
  case length(Successors) < ?MAX_NUM_OF_SUCCESSORS andalso Successors =/= [] of 
    true ->
      LastSuccessorNode = (hd(lists:reverse(Successors)))#finger_entry.node,
      case chord_tcp:rpc_get_successor(LastSuccessorNode) of
        {ok, NextSucc} -> gen_server:cast(Pid, {set_successor, NextSucc});
        {error, _} -> remove_node(Pid, LastSuccessorNode)
      end;
    false ->
      % Successor list is up to date!
      ok
  end.


% @doc: Sends copy of a new item to successors for replication
-spec(replicate_entry/2::(Entry::#entry{}, State::#chord_state{}) -> ok).
replicate_entry(Entry, State) ->
  SuccessorNodes = [F#finger_entry.node || F <- array:get(0, State#chord_state.fingers)],
  [spawn(fun() -> chord_tcp:rpc_send_entries([Entry], Succ) end) || Succ <- SuccessorNodes],
  ok.
