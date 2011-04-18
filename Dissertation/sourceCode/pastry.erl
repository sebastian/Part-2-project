-module(pastry).
-behaviour(gen_server).
-compile({no_auto_import,[min/2, max/2]}).
-define(SERVER, ?MODULE).
-define(NEIGHBORHOODWATCH_TIMER, 5000).

-include("../fs.hrl").
-include("pastry.hrl").

-import(lists, [reverse/1, foldl/3, member/2, flatten/1, filter/2, sort/2, sublist/2]).
% Some erlang installs don't know where to find min/max
-import(erlang, [min/2, max/2]).

%% ---------------------------------------------
%% Public API
%% ---------------------------------------------

-export([start_link/1, start/1, stop/1]).
-export([
    route/3
  ]).

%% ---------------------------------------------
%% PRIVATE API Function Exports
%% ---------------------------------------------

% For joining
-export([
    augment_routing_table/2,
    let_join/2,
    welcomed/1,
    welcome/2
  ]).

% For exchanging nodes
-export([
    get_leafset/1,
    get_routing_table/1,
    get_neighborhoodset/1,
    get_self/1,
    add_nodes/2,
    discard_dead_node/2
  ]).

% For use by other modules
-export([
    value_of_key/2,
    max_for_keylength/2,
    neighborhood_watch/1,
    ping/1
  ]).

% For use by controller to stop communication during experiments
-export([
    start_timers/1,
    stop_timers/1
  ]).
% For debugging
-export([output_diagnostics/1]).

%% ---------------------------------------------
%% gen_server Function Exports
%% ---------------------------------------------

-export([
    init/1, 
    handle_call/3,
    handle_cast/2, 
    handle_info/2, 
    terminate/2, 
    code_change/3
  ]).

%% ---------------------------------------------
%% PUBLIC API Function Definitions
%% ---------------------------------------------

start(Args) ->
  supervisor:start_child(pastry_sofo, Args).

start_link(Args) ->
  gen_server:start_link(?MODULE, Args, []).

stop(Pid) ->
  gen_server:call(Pid, stop).

route(Pid, Msg, Key) ->
  gen_server:cast(Pid, {route, Msg, Key}),
  ok.

%% ---------------------------------------------
%% PRIVATE API Function Definitions
%% ---------------------------------------------

start_timers(Pid) ->
  gen_server:cast(Pid, start_timer).

stop_timers(Pid) ->
  gen_server:cast(Pid, stop_timer).

output_diagnostics(Pid) ->
  gen_server:call(Pid, output_diagnostics).

neighborhood_watch(Pid) ->
  gen_server:cast(Pid, perform_neighborhood_watch),
  gen_server:cast(Pid, perform_neighborhood_expansion).

augment_routing_table(Pid, RoutingTable) ->
  gen_server:call(Pid, {augment_routing_table, RoutingTable}).

let_join(Pid, Node) ->
  % Send the newcomer our routing table
  spawn(fun() ->
    case pastry_tcp:send_routing_table(gen_server:call(Pid, get_routing_table), Node) of
      {ok, NewNodes} ->
        % The node returns nodes that we can add to our own table
        add_nodes(Pid, NewNodes);
      _ -> ohoh
    end,
    pastry_tcp:send_nodes(gen_server:call(Pid, get_self), Node),
    % Forward the routing message to the next node
    route(Pid, {join, Node}, Node#node.key),
    % We add the node to our routing table so we can route to it later.
    add_nodes(Pid, Node)
  end),
  ok.

% @doc: Once a node has joined a pastry network and the join
% message has reached the final destination, the final node
% welcomes the newcomer. Following the welcoming message
% the node broadcasts its routing table to all the nodes
% it knows about.
welcomed(Pid) ->
  gen_server:cast(Pid, welcomed),
  ok.

add_nodes(Pid, Nodes) ->
  gen_server:cast(Pid, {add_nodes, Nodes}),
  ok.

welcome(Pid, Node) ->
  gen_server:cast(Pid, {welcome, Node}).

get_leafset(Pid) ->
  gen_server:call(Pid, get_leafset).

get_routing_table(Pid) ->
  gen_server:call(Pid, get_routing_table).

get_neighborhoodset(Pid) ->
  gen_server:call(Pid, get_neighborhoodset).

get_self(Pid) ->
  gen_server:call(Pid, get_self).

discard_dead_node(Pid, Node) ->
  gen_server:cast(Pid, {discard_dead_node, Node}).

ping(Pid) ->
  gen_server:call(Pid, ping).

%% ---------------------------------------------
%% gen_server Function Definitions
%% ---------------------------------------------

% Sample args:
% pastry:start([{b,10},{port,3001},{joinNode,{{172,21,229,189},3000}}]).
init(Args) -> 
  SelfPid = self(),
  ControllingProcess = 
      proplists:get_value(controllingProcess, Args),

  spawn(fun() ->
    controller:register_dht(ControllingProcess, SelfPid, self()),
    receive {pastry_app_pid, PastryAppPid} -> 
      % register with the tcp_listener so we can contact the Dht
      gen_server:call(SelfPid, 
          {set_pastry_app_pid, PastryAppPid}) 
    end
  end),

  Port = receive {port, TcpPort} -> TcpPort end,
  rendevouz(Port, ControllingProcess, Args).

rendevouz(Port, ControllingProcess, Args) ->
  try_to_rendevouz(Port, ControllingProcess, Args, undefined, 5).

try_to_rendevouz(_Port, ControllingProcess, _Args, Reason, 0) ->
  controller:dht_failed_start(ControllingProcess),
  {stop, {couldnt_rendevouz, Reason}};
try_to_rendevouz(Port, ControllingProcess, Args, _Reason, N) ->
  case pastry_tcp:rendevouz(Port, ?RENDEVOUZ_HOST, ?RENDEVOUZ_PORT) of
    {MyIp, first} -> 
      controller:dht_successfully_started(ControllingProcess),
      {ok, post_rendevouz_state_update(MyIp, Port, Args)};
    {error, Reason} -> 
      % The hub_controller must be overloaded. Wait and try again
      error_logger:error_msg("Couldn't rendevouz. Retrying after a little while. ~p more attempts~n", [N]),
      receive after random:uniform(10) * 1000 -> ok end,
      try_to_rendevouz(Port, ControllingProcess, Args, Reason, N-1);
    {MyIp, Nodes} -> perform_join(Nodes, post_rendevouz_state_update(MyIp, Port, Args), ControllingProcess)
  end.

post_rendevouz_state_update(Ip, Port, Args) ->
  B = proplists:get_value(b, Args, 4),
  Key = utilities:key_for_node_with_b(Ip, Port, B),
  Self = #node{key = Key, port = Port, ip = Ip},
  start_timer(#pastry_state{
    b = B,
    self = Self,
    routing_table = create_routing_table(Key),
    pastry_pid = self()
  }).

perform_join([], _State, ControllingProcess) -> 
  controller:dht_failed_start(ControllingProcess),
  {stop, couldnt_join_pastry_network};
perform_join([{JoinIp, JoinPort}|Ps], 
    #pastry_state{self = Self} = State, ControllingProcess) ->
  case pastry_tcp:perform_join(Self, #node{ip = JoinIp, port = JoinPort}) of
    {error, _} -> perform_join(Ps, State, ControllingProcess);
    {ok, _} -> 
      controller:dht_successfully_started(ControllingProcess),
      {ok, State}
  end.

% Call:
handle_call({augment_routing_table, RoutingTable}, From, 
    #pastry_state{pastry_pid = PastryPid} = State) ->
  spawn(fun() ->
    % add the nodes we have received to our own routing table
    add_nodes(PastryPid, nodes_in_routing_table(RoutingTable)),
    % respond with all our own nodes
    OurNodes = all_known_nodes(State),
    gen_server:reply(From, OurNodes)
  end),
  {noreply, State};

handle_call(output_diagnostics, _From, State) ->
  Nodes = all_known_nodes(State),
  {reply, Nodes, State};

handle_call(ping, _From, State) ->
  {reply, pong, State};

handle_call({set_pastry_app_pid, PastryAppPid}, _From, #pastry_state{self = Self, b = B} = State) ->
  pastry_app:pastry_init(PastryAppPid, Self, B),
  {reply, thanks, State#pastry_state{pastry_app_pid = PastryAppPid}};

handle_call(get_leafset, _From, State) ->
  {reply, State#pastry_state.leaf_set, State};

handle_call(get_self, _From, State) ->
  {reply, State#pastry_state.self, State};

handle_call(get_neighborhoodset, _From, State) ->
  {reply, State#pastry_state.neighborhood_set, State};

handle_call(get_routing_table, _From, State) ->
  {reply, State#pastry_state.routing_table, State};

handle_call(stop, _From, State) ->
  {stop, normal, ok, State}.

% Casts:
handle_cast(perform_neighborhood_expansion, State) ->
  perform_neighborhood_set_expansion(State),
  {noreply, State};

handle_cast(perform_neighborhood_watch, State) ->
  perform_neighborhood_watch(State),
  {noreply, State};

handle_cast({welcome, Node}, 
    #pastry_state{leaf_set = {LSS, LSG}} = State) ->
  spawn(fun() ->
    % We send the node our leafset
    pastry_tcp:send_nodes(LSS ++ LSG, Node)
  end),
  {noreply, State};

handle_cast(welcomed, State) ->
  perform_welcomed(State),
  {noreply, State};

handle_cast({route, Msg, Key}, 
    #pastry_state{pastry_app_pid = PastryAppPid} = State) ->
  LoggableKey = case Msg of
    {lookup_key, NumericKey, _, _} -> NumericKey;
    _ -> Key
  end,
  logger:log(PastryAppPid, LoggableKey, route),
  route_msg(Msg, Key, State),
  {noreply, State};

handle_cast({add_nodes, Nodes}, 
    #pastry_state{pastry_pid = Pid} = State) ->
  prepare_nodes_for_adding(Nodes, Pid),
  {noreply, State};

handle_cast({update_local_state_with_nodes, Nodes}, 
    #pastry_state{routing_table = RT, neighborhood_set = NS, b = B} = State) ->
  UpdatedLeafSetState = foldl(fun(Node, PrevState) ->
    merge_node_in_leaf_set(Node, PrevState)
  end, State, Nodes),
  NewRT = foldl(fun(Node, PrevRoutingTable) ->
    merge_node_in_rt(Node, PrevRoutingTable)
  end, RT, Nodes),
  NewNeighborhoodSet = foldl(fun(Node, PrevNHS) ->
    merge_node_in_nhs(Node, PrevNHS, B, State#pastry_state.self)
  end, NS, Nodes),
  UpdatedState = UpdatedLeafSetState#pastry_state{routing_table = NewRT, 
      neighborhood_set = NewNeighborhoodSet},
  {noreply, UpdatedState};

handle_cast({discard_dead_node, Node}, State) ->
  {noreply, perform_discard_dead_node(Node, State)};

handle_cast(start_timer, State) ->
  {noreply, start_timer(State)};

handle_cast(stop_timer, State) ->
  {noreply, stop_timer(State)};

handle_cast(Msg, State) ->
  error_logger:error_msg("received unknown cast: ~p", [Msg]),
  {noreply, State}.

% Info:
handle_info(Info, State) ->
  error_logger:error_msg("Got info message: ~p", [Info]),
  {noreply, State}.

% Terminate:
terminate(_Reason, State) ->
  stop_timer(State).

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%% ---------------------------------------------
%% Internal Function Definitions
%% ---------------------------------------------

start_timer(#pastry_state{pastry_pid = Pid, neighborhood_watch_ref = undefined} = State) ->
  io:format("Starting timer~n"),
  {ok, TimerRef} = timer:apply_interval(?NEIGHBORHOODWATCH_TIMER, ?MODULE, neighborhood_watch, [Pid]),
  State#pastry_state{neighborhood_watch_ref = TimerRef};
start_timer(State) ->
  io:format("avoiding duplicating timers~n"),
  State.

stop_timer(#pastry_state{neighborhood_watch_ref = NWR} = State) ->
  io:format("Stopping timer~n"),
  timer:cancel(NWR),
  State#pastry_state{neighborhood_watch_ref = undefined}.

perform_neighborhood_watch(#pastry_state{pastry_pid = Pid, neighborhood_set = NHS}) ->
  [spawn(fun() ->
      case pastry_tcp:is_node_alive(Node) of
        true -> awesome;
        false -> discard_dead_node(Pid, Node)
      end
  end) || Node <- NHS].

perform_neighborhood_set_expansion(#pastry_state{neighborhood_set = []}) -> ok; % can't expand from non-existant neighbor.
perform_neighborhood_set_expansion(#pastry_state{pastry_pid = PastryPid, b = B, neighborhood_set = NHS}) ->
  spawn(fun() ->
    case length(NHS) < (1 bsl B) of
      true ->
        case pastry_tcp:request_neighborhood_set(hd(NHS)) of
          {ok, Nodes} -> add_nodes(PastryPid, Nodes);
          {error, _} -> ok
        end;
      false -> ok % We are fine
    end
  end).

create_routing_table(Key) ->
  [#routing_table_entry{value = none} | [#routing_table_entry{value = V} || V <- Key]].

merge_node_in_nhs(Node, NeighborHoodSet, _B, Self) when Node#node.key =:= Self#node.key -> NeighborHoodSet;
merge_node_in_nhs(Node, NeighborHoodSet, B, _) -> 
  MaxNeighbors = 1 bsl B,
  case member(Node, NeighborHoodSet) of
    true -> NeighborHoodSet;
    false -> sublist(sort(fun(N, M) -> N#node.distance < M#node.distance end, [Node|NeighborHoodSet]), MaxNeighbors)
  end.

merge_node_in_leaf_set(Node, #pastry_state{self = Self} = State) when Node#node.key =:= Self#node.key -> State;
merge_node_in_leaf_set(Node, #pastry_state{b = B, self = Self, leaf_set = {LSS, LSG}, pastry_app_pid = PAPid} = State) ->
  case member(Node, LSS) orelse member(Node, LSG) of
    true -> State;
    false -> 
      LeafSetSize = trunc((1 bsl B)/2),
      case is_node_less_than_me(Node, Self, B) of
        true ->
          % Wow this is ugly and inefficient, but OK, these lists are short anyway, but still... TODO!
          NewLSS = reverse(sublist(reverse(sort_leaves([Node|LSS], B)), LeafSetSize)),
          case NewLSS =/= LSS of
            true -> pastry_app:new_leaves(PAPid, {NewLSS, LSG});
            false -> ok
          end,
          State#pastry_state{leaf_set = {NewLSS, LSG}};
        false ->
          NewLSG = sublist(sort_leaves([Node|LSG], B), LeafSetSize),
          case NewLSG =/= LSG of
            true -> pastry_app:new_leaves(PAPid, {LSS, NewLSG});
            false -> ok
          end,
          State#pastry_state{leaf_set = {LSS, NewLSG}}
      end
  end.

sort_leaves(Leaves, B) -> sort(fun(N, M) -> is_node_less_than_me(N, M, B) end, Leaves).

is_node_less_than_me(#node{key = Key}, Self, B) ->
  Max = max_for_keylength(Key, B),
  KeyVal = value_of_key(Key, B),
  SelfVal = value_of_key(Self#node.key, B),
  HalfPoint = trunc(Max/2),
  NewPos = SelfVal + HalfPoint,
  case NewPos > Max of
    true -> key_in_range(KeyVal, NewPos - Max, SelfVal, B);
    false -> key_in_range(KeyVal, NewPos, SelfVal, B)
  end.

% @doc: Adds a node to the routing table. If there is already a node
% occupying the location, then the closer of the two is kept.
merge_node_in_rt(#node{key = Key} = OtherNode, RoutingTable) ->
  merge_node_in_rt(RoutingTable, empty, [none|Key], [], OtherNode).
% Last routing table entry. Since we have a match, the node must be us.
% We don't want to include ourselves in the list.
merge_node_in_rt([], R, _, _, _Node) ->
  [R];
% The keypath matches, so nothing to do as of yet.
merge_node_in_rt([#routing_table_entry{value = I} = R|RR], PrevR, [I|Is], KeySoFar, Node) ->
  case PrevR of
    empty -> merge_node_in_rt(RR, R, Is, [I], Node);
    Prev -> [Prev|merge_node_in_rt(RR, R, Is, [I|KeySoFar], Node)]
  end;
% At this point there is no longer a match between our key and the key 
% of the node. Conditionally change it in place.
merge_node_in_rt(RR, #routing_table_entry{nodes = Nodes} = PrevR, [I|_], KeySoFar, Node) ->
  [PrevR#routing_table_entry{nodes = conditionally_replace_node(Node, Nodes, reverse([I|KeySoFar] -- [none]))} | RR].
 
conditionally_replace_node(N, [], _) -> [N];
conditionally_replace_node(#node{distance = D1} = N1, [#node{distance = D2} = N2|Ns] = NNs, KeySoFar) ->
  case is_valid_key_path(N2, KeySoFar) of
    true -> 
      case D1 < D2 of
        true -> [N1|Ns];
        false -> NNs
      end;
    false -> [N2 | conditionally_replace_node(N1, Ns, KeySoFar)]
  end.

is_valid_key_path(#node{key=Key}, KeyPath) ->
  check_path(Key, KeyPath).
check_path(_, []) -> true;
check_path([K|Ks], [K|KPs]) -> check_path(Ks, KPs);
check_path(_, _) -> false.

nodes_in_routing_table(RoutingTable) ->
  flatten(collect_all_nodes(RoutingTable)).
collect_all_nodes([]) -> [];
collect_all_nodes([#routing_table_entry{nodes = N}|R]) ->
  [N|collect_all_nodes(R)].

prepare_nodes_for_adding(Nodes, Pid) when is_list(Nodes) ->
  % Get the local distance of the nodes before adding them
  % to our own routing table.
  spawn(fun() ->
    LiveNodes = [Node || Node <- Nodes, pastry_tcp:is_node_alive(Node)],
    gen_server:cast(Pid, {
      update_local_state_with_nodes, 
      [N#node{distance = pastry_locality:distance(N#node.ip)} || N <- LiveNodes]
    })
  end);
prepare_nodes_for_adding(Node, Pid) -> prepare_nodes_for_adding([Node], Pid).

route_msg(Msg, Key, State) ->
  spawn(fun() ->
    route_to_leaf_set(Msg, Key, State) orelse
    route_to_node_in_routing_table(Msg, Key, State) orelse
    route_to_closer_node(Msg, Key, State)
  end).

route_to_closer_node(Msg, Key, #pastry_state{self = Self, b = B, pastry_app_pid = PAPid, pastry_pid = PastryPid} = State) ->
  SharedKeySegment = shared_key_segment(Self, Key),
  Nodes = filter(
    fun(N) -> is_valid_key_path(N, SharedKeySegment) end, 
    all_known_nodes(State)
  ),
  case foldl(fun(N, CurrentClosest) -> closer_node(Key, N, CurrentClosest, B) end, Self, Nodes) of
    Self -> pastry_app:deliver(PAPid, Msg, Key);
    Node -> do_forward_msg(Msg, Key, Node, PastryPid)
  end.

shared_key_segment(#node{key = NodeKey}, Key) -> shared_key_segment(NodeKey, Key, []).
shared_key_segment([A|As], [A|Bs], Acc) -> shared_key_segment(As, Bs, [A|Acc]);
shared_key_segment(_, _, Acc) -> reverse(Acc).

route_to_node_in_routing_table(Msg, Key, #pastry_state{pastry_pid = PastryPid, pastry_app_pid = PastryAppPid} = State) ->
  {#routing_table_entry{nodes = Nodes}, [none|PreferredKeyMatch]} = find_corresponding_routing_table(Key, State),
  case filter(fun(Node) -> is_valid_key_path(Node, PreferredKeyMatch) end, Nodes) of
    [] -> false;
    [Node] -> 
      case Node =:= State#pastry_state.self of
        true -> pastry_app:deliver(PastryAppPid, Msg, Key);
        false -> do_forward_msg(Msg, Key, Node, PastryPid)
      end
  end.

find_corresponding_routing_table(Key, #pastry_state{routing_table = [R|Rs]}) ->
  find_corresponding_routing_table([none|Key], [R|Rs], R, []).
find_corresponding_routing_table([Key|Ks], [#routing_table_entry{value = Key} = R|Rs], _, KeySoFar) ->
  find_corresponding_routing_table(Ks, Rs, R, [Key|KeySoFar]);
find_corresponding_routing_table([Key|_], _, Previous, KeySoFar) -> {Previous, reverse([Key|KeySoFar])}.

route_to_leaf_set(Msg, Key, #pastry_state{self = Self, pastry_pid = PastryPid, pastry_app_pid = PastryAppPid} = State) ->
  case node_in_leaf_set(Key, State) of
    none -> false;
    Node when Node =:= Self -> 
      pastry_app:deliver(PastryAppPid, Msg, Key),
      true;
    Node -> do_forward_msg(Msg, Key, Node, PastryPid)
  end.

do_forward_msg(Msg, Key, Node, PastryPid) ->
  case pastry_app:forward(Msg, Key, Node) of
    {_, null} -> true; % Message shouldn't be forwarded.
    {NewMsg, NewNode} ->
      case pastry_tcp:route_msg(NewMsg, Key, NewNode) of
        {ok, _} -> true;
        {error, _Reason} ->
          % Remove the node from our routing table, and retry
          discard_dead_node(PastryPid, NewNode),
          route(PastryPid, Msg, Key),
          true
      end
  end.

% Returns the node closest to the key in the leaf set, or none if
% the key is outside the leafset
node_in_leaf_set(_, #pastry_state{leaf_set = {[], []}, self = Self}) -> Self;
node_in_leaf_set(Key, #pastry_state{leaf_set = {LeafSetSmaller, []}, self = Self} = State) ->
  node_in_leaf_set(Key, State#pastry_state{leaf_set = {LeafSetSmaller, [Self]}});
node_in_leaf_set(Key, #pastry_state{leaf_set = {[], LeafSetGreater}, self = Self} = State) ->
  node_in_leaf_set(Key, State#pastry_state{leaf_set = {[Self], LeafSetGreater}});
node_in_leaf_set(Key, #pastry_state{leaf_set = {LeafSetSmaller, LeafSetGreater}, b = B, self = Self}) ->
  % Is it in the leaf set in the first place?
  case key_in_range(Key, (hd(LeafSetSmaller))#node.key, (hd(reverse(LeafSetGreater)))#node.key, B) of
    false -> none;
    true ->
      case node_closest_to_key(Key, LeafSetSmaller ++ [Self], B) of
        none -> node_closest_to_key(Key, [Self|LeafSetGreater], B);
        Node -> Node
      end
  end.

% @doc: returns the node from the list that has a key numerically
% closest to the given key. none is returned if the key falls 
% outside the range of what is covered by the nodes.
-spec(node_closest_to_key/3::(Key::pastry_key(), [#node{}], B::integer())
  -> #node{} | none).
node_closest_to_key(Key, [Node1,Node2|Ns], B) ->
  case key_in_range(Key, Node1#node.key, Node2#node.key, B) of
    false -> node_closest_to_key(Key, [Node2|Ns], B);
    true -> closer_node(Key, Node1, Node2, B)
  end;
node_closest_to_key(_, _, _) -> none.

% @doc: Inclusive range check. Returns true if Key is greater or equal to start and
% less or equal to end.
key_in_range(Key, NKey, NKey, _) when NKey =/= Key -> false;
key_in_range(Key, Start, End, B) ->
  ValKey = value_of_key(Key, B), ValStart = value_of_key(Start, B), ValEnd = value_of_key(End, B),
  case ValStart < ValEnd of
    true -> (ValStart =< ValKey) andalso (ValKey =< ValEnd);
    false -> (ValStart =< ValKey) orelse ((0 =< ValKey) andalso (ValKey =< ValEnd))
  end.

closer_node(Key, #node{key = Ka} = NodeA, #node{key = Kb} = NodeB, B) ->
  case key_diff(Key, Ka, B) =< key_diff(Key, Kb, B) of
    true -> NodeA;
    false -> NodeB
  end.

key_diff(K1, K2, B) -> 
  K1Val = value_of_key(K1, B),
  K2Val = value_of_key(K2, B),
  Max = max_for_keylength(K1, B),
  min(abs(K1Val-K2Val), Max - max(K1Val,K2Val) + min(K1Val,K2Val)).

value_of_key(Key, B) when is_list(Key) -> value_of_key(Key, 1 bsl B, 0);
value_of_key(KeyVal, _) -> KeyVal.
value_of_key([], _, Val) -> Val;
value_of_key([A|As], Mul, Acc) -> value_of_key(As, Mul, Acc * Mul + A).

max_for_keylength(SampleKey, B) -> max_for_keylength(SampleKey, 1 bsl B, 0).
max_for_keylength([], _, Val) -> Val;
max_for_keylength([_|K], Mul, Acc) -> max_for_keylength(K, Mul, Acc * Mul + Mul-1).

% @doc: When a node has joined it is welcomed.
% When a welcome message is received, the newcomer
% broadcasts its routing table so other nodes get
% a chance to update their own.
perform_welcomed(#pastry_state{routing_table = RT, pastry_pid = Pid} = State) ->
  [spawn(fun() -> 
      case pastry_tcp:send_routing_table(RT, N) of
        {ok, NewNodes} -> add_nodes(Pid, NewNodes);
        _ -> ohoh
      end
  end) || N <- all_known_nodes(State)].

all_known_nodes(#pastry_state{routing_table = RT, leaf_set = {LSS, LSG}, neighborhood_set = NS}) ->
  nodes_in_routing_table(RT) ++ LSS ++ LSG ++ NS.
  
discard_dead_node_from_leafset(Node, #pastry_state{pastry_app_pid = PAPid, leaf_set = LS, pastry_pid = PastryPid} = State) ->
  {LSS, LSG} = LS,
  NewLSS = LSS -- [Node],
  NewLSG = LSG -- [Node],
  NewLS = {NewLSS, NewLSG},
  case NewLS =/= LS of
    true -> 
      pastry_app:new_leaves(PAPid, NewLS),
      % We should also ask the largest / smallest leaf
      % for their leaf set so we can expand our own leaf
      % set again
      case NewLSS =/= LSS of
        true -> request_new_leaves(NewLSS, PastryPid);
        false -> request_new_leaves(reverse(NewLSG), PastryPid)
      end;
    false -> ok
  end,
  State#pastry_state{leaf_set = NewLS}.
request_new_leaves([], _) -> ok;
request_new_leaves(LeafList, PastryPid) ->
  spawn(fun() ->
    Node = hd(LeafList),
    case pastry_tcp:request_leaf_set(Node) of
      {ok, {LSS, LSG}} -> add_nodes(PastryPid, LSS ++ LSG);
      {error, _} -> discard_dead_node(PastryPid, Node)
    end
  end).

discard_dead_node_from_neighborhoodset(Node, #pastry_state{neighborhood_set = NS} = State) ->
  State#pastry_state{neighborhood_set = NS -- [Node]}.

discard_dead_node_from_routing_table(Node, #pastry_state{routing_table = RT} = State) ->
  % This can be done better. But for now it works.
  % Could do an approach more similar to the one in merge_node_in_rt to
  % find the right routing table.
  State#pastry_state{routing_table = routing_table_without(Node, RT, [])}.
routing_table_without(_Node, [], Acc) -> reverse(Acc);
routing_table_without(Node, [#routing_table_entry{nodes = N} = R|Rt], Acc) ->
  routing_table_without(Node, Rt, [R#routing_table_entry{nodes = N -- [Node]}|Acc]).

perform_discard_dead_node(Node, State) ->
  discard_dead_node_from_neighborhoodset(Node,
    discard_dead_node_from_routing_table(Node,
      discard_dead_node_from_leafset(Node, State))).
