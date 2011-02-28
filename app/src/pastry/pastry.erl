-module(pastry).
-behaviour(gen_server).
-compile({no_auto_import,[min/2, max/2]}).
-define(SERVER, ?MODULE).
-define(NEIGHBORHOODWATCH_TIMER, 30000).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-include("../fs.hrl").
-include("pastry.hrl").

-import(lists, [reverse/1, foldl/3, member/2, flatten/1, filter/2, sort/2, sublist/2]).
% Some erlang installs don't know where to find min/max
-import(erlang, [min/2, max/2]).

%% ------------------------------------------------------------------
%% Public API
%% ------------------------------------------------------------------

-export([start_link/1, start/1, stop/1]).
-export([
    route/3
  ]).

%% ------------------------------------------------------------------
%% PRIVATE API Function Exports
%% ------------------------------------------------------------------

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

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([
    init/1, 
    handle_call/3,
    handle_cast/2, 
    handle_info/2, 
    terminate/2, 
    code_change/3
  ]).

%% ------------------------------------------------------------------
%% PUBLIC API Function Definitions
%% ------------------------------------------------------------------

start(Args) ->
  supervisor:start_child(pastry_sofo, Args).

start_link(Args) ->
  gen_server:start_link(?MODULE, Args, []).

stop(Pid) ->
  gen_server:call(Pid, stop).

route(Pid, Msg, Key) ->
  gen_server:cast(Pid, {route, Msg, Key}),
  ok.

%% ------------------------------------------------------------------
%% PRIVATE API Function Definitions
%% ------------------------------------------------------------------

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
  gen_server:cast(Pid, {augment_routing_table, RoutingTable}),
  ok.

let_join(Pid, Node) ->
  % Send the newcomer our routing table
  spawn(fun() ->
    pastry_tcp:send_routing_table(gen_server:call(Pid, get_routing_table), Node),
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

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

% Sample args:
% pastry:start([{b,10},{port,3001},{joinNode,{{172,21,229,189},3000}}]).
init(Args) -> 
  SelfPid = self(),
  ControllingProcess = proplists:get_value(controllingProcess, Args),

  spawn(fun() ->
    controller:register_dht(ControllingProcess, SelfPid, self()),
    receive {pastry_app_pid, PastryAppPid} -> 
      % register the pid with the tcp_listener so we can contact the Dht
      gen_server:call(SelfPid, {set_pastry_app_pid, PastryAppPid}) 
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
perform_join([{JoinIp, JoinPort}|Ps], #pastry_state{self = Self} = State, ControllingProcess) ->
  case pastry_tcp:perform_join(Self, #node{ip = JoinIp, port = JoinPort}) of
    {error, _} -> perform_join(Ps, State, ControllingProcess);
    {ok, _} -> 
      controller:dht_successfully_started(ControllingProcess),
      {ok, State}
  end.

% Call:
handle_call(output_diagnostics, _From, State) ->
  {reply, ok, State};

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

handle_cast({welcome, Node}, #pastry_state{leaf_set = {LSS, LSG}} = State) ->
  spawn(fun() ->
    % We send the node our leafset
    pastry_tcp:send_nodes(LSS ++ LSG, Node)
  end),
  {noreply, State};

handle_cast(welcomed, State) ->
  perform_welcomed(State),
  {noreply, State};

handle_cast({route, Msg, Key}, #pastry_state{pastry_app_pid = PastryAppPid} = State) ->
  LoggableKey = case Msg of
    {lookup_key, NumericKey, _, _} -> NumericKey;
    _ -> Key
  end,
  logger:log(PastryAppPid, LoggableKey, route),
  route_msg(Msg, Key, State),
  {noreply, State};

handle_cast({augment_routing_table, RoutingTable}, #pastry_state{pastry_pid = PastryPid} = State) ->
  add_nodes(PastryPid, nodes_in_routing_table(RoutingTable)),
  {noreply, State};

handle_cast({add_nodes, Nodes}, #pastry_state{pastry_pid = Pid} = State) ->
  prepare_nodes_for_adding(Nodes, Pid),
  {noreply, State};

handle_cast({update_local_state_with_nodes, Nodes}, #pastry_state{routing_table = RT, neighborhood_set = NS, b = B} = State) ->
  UpdatedLeafSetState = foldl(fun(Node, PrevState) ->
    merge_node_in_leaf_set(Node, PrevState)
  end, State, Nodes),
  NewRT = foldl(fun(Node, PrevRoutingTable) ->
    merge_node_in_rt(Node, PrevRoutingTable)
  end, RT, Nodes),
  NewNeighborhoodSet = foldl(fun(Node, PrevNHS) ->
    merge_node_in_nhs(Node, PrevNHS, B, State#pastry_state.self)
  end, NS, Nodes),
  {noreply, UpdatedLeafSetState#pastry_state{routing_table = NewRT, neighborhood_set = NewNeighborhoodSet}};

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

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

start_timer(#pastry_state{pastry_pid = Pid} = State) ->
  io:format("Starting timer~n"),
  {ok, TimerRef} = timer:apply_interval(?NEIGHBORHOODWATCH_TIMER, ?MODULE, neighborhood_watch, [Pid]),
  State#pastry_state{neighborhood_watch_ref = TimerRef}.

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
perform_welcomed(#pastry_state{routing_table = RT} = State) ->
  [spawn(fun() -> pastry_tcp:send_routing_table(RT, N) end) || N <- all_known_nodes(State)].

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

%% ------------------------------------------------------------------
%% Tests
%% ------------------------------------------------------------------

-ifdef(TEST).

test_state() ->
  Key = [0,0,0,0],
  #pastry_state{
    self = #node{
      key = Key,
      ip = {1,2,3,4},
      port = 1234
    },
    routing_table = create_routing_table(Key),
    leaf_set = {[#node{key = [6,0,0,0]}, #node{key=[7,0,0,0]}], [#node{key = [1,0,0,0]}, #node{key = [2,0,0,0]}]},
    b = 3,
    pastry_app_pid = self() % not logical... but atleast a pid.
  }.

create_routing_table_test() ->
  Key = [1,2,3],
  ?assertEqual([#routing_table_entry{value = none}, 
      #routing_table_entry{value = 1}, 
      #routing_table_entry{value = 2}, 
      #routing_table_entry{value = 3}],
    create_routing_table(Key)).

level_for_key_path_contains_node([KeyItem], Node, [#routing_table_entry{value=KeyItem, nodes = Nodes}|_]) ->
  lists:member(Node, Nodes);
level_for_key_path_contains_node([KeyItem|RestPath], Node, [#routing_table_entry{value=KeyItem}|RestRouting]) ->
  level_for_key_path_contains_node(RestPath, Node, RestRouting); 
level_for_key_path_contains_node(_, _, _) -> false.
  

merge_node_in_rt_no_shared_test() ->
  MyKey = [0,0],
  RoutingTable = create_routing_table(MyKey),

  ANode = #node{key = [1,1]},
  BNode = #node{key = [0,1], distance = 12},
  CNode = #node{key = [0,1], distance = 2},
  DNode = #node{key = [0,2], distance = 12},
  Self  = #node{key = MyKey, distance = 0},

  ?assert(level_for_key_path_contains_node([none], ANode, merge_node_in_rt(ANode, RoutingTable))),
  RoutingTableWithB = merge_node_in_rt(BNode, RoutingTable),
  ?assert(level_for_key_path_contains_node([none,0], BNode, RoutingTableWithB)),
  % Now we add node C, which should replace node B.
  RoutingTableWithC = merge_node_in_rt(CNode, RoutingTableWithB),
  ?assert(level_for_key_path_contains_node([none,0], CNode, RoutingTableWithC)),
  ?assertNot(level_for_key_path_contains_node([none,0], BNode, RoutingTableWithC)),
  % Now we add node D which doesn't conflict. It should therefore have both C and D
  RoutingTableWithCandD = merge_node_in_rt(DNode, RoutingTableWithC),
  ?assert(level_for_key_path_contains_node([none,0], CNode, RoutingTableWithCandD)),
  ?assert(level_for_key_path_contains_node([none,0], DNode, RoutingTableWithCandD)),

  % Try to add myself, but that shouldn't affect the table
  ?assertNot(level_for_key_path_contains_node([none], Self, merge_node_in_rt(Self, RoutingTable))),
  ?assertNot(level_for_key_path_contains_node([none,0], Self, merge_node_in_rt(Self, RoutingTable))),
  ?assertNot(level_for_key_path_contains_node([none,0,0], Self, merge_node_in_rt(Self, RoutingTable))).

conditionally_replace_node_test() ->
  % Our key could in this case be [0,0,0,...]
  Nodes = [
    #node{
      key = [0,0,1,1],
      distance = 12
    },
    #node{
      key = [0,0,2,0],
      distance = 3
    },
    #node{
      key = [0,0,3,9],
      distance = 30
    }
  ],

  NotReplace = #node{
    key = [0,0,1,2],
    distance = 13
  },
  NotReplace2 = #node{
    key = [0,0,1,0],
    distance = 12
  },
  Replace = #node{
    key = [0,0,4,1],
    distance = 100
  },
  Replace2 = #node{
    key = [0,0,3,2],
    distance = 15
  },

  ?assertEqual(Nodes, conditionally_replace_node(NotReplace, Nodes, [0,0,1])),
  ?assertEqual(Nodes, conditionally_replace_node(NotReplace2, Nodes, [0,0,1])),
  ?assertNot(Nodes =:= conditionally_replace_node(Replace, Nodes, [0,0,4])),
  ?assertNot(Nodes =:= conditionally_replace_node(Replace2, Nodes, [0,0,3])). 

is_valid_key_path_test() ->
  CheckKey = [0,0,1],
  TrueNode = #node{
    key = [0,0,1,2,3]
  },
  TrueNode2 = #node{
    key = [0,0,1,4,2]
  },
  FalseNode = #node{
    key = [0,0,2,1,1]
  },
  FalseNode2 = #node{
    key = [1,0,0,0,0]
  },
  ?assert(is_valid_key_path(TrueNode, CheckKey)),
  ?assert(is_valid_key_path(TrueNode2, CheckKey)),
  ?assertNot(is_valid_key_path(FalseNode, CheckKey)),
  ?assertNot(is_valid_key_path(FalseNode2, CheckKey)).

nodes_in_routing_table_test() ->
  MyKey = [0,0],
  RoutingTable = create_routing_table(MyKey),
  N1 = #node{
    key = [1,1]
  },
  N2 = #node{
    key = [0,1]
  },
  N3 = #node{
    key = [2,1]
  },
  N4 = #node{
    key = [0,4]
  },
  FullRoutingTable = merge_node_in_rt(N1, merge_node_in_rt(N2, merge_node_in_rt(N3, merge_node_in_rt(N4, RoutingTable)))),
  NodesInTable = nodes_in_routing_table(FullRoutingTable),
  ?assert(member(N1, NodesInTable)),
  ?assert(member(N2, NodesInTable)),
  ?assert(member(N3, NodesInTable)),
  ?assert(member(N4, NodesInTable)).

route_to_leaf_set_test() ->
  State = test_state(),
  Msg = test_msg,
  GoodKey = [1,0,0,1],
  GoodKeyToSelf = [0,0,0,1],
  BadKey = [5,0,0,0],

  RouteToNode = #node{
    key = [1,0,0,0]
  },

  erlymock:start(),
  % This is for the message with the GoodKey
  erlymock:strict(pastry_app, forward, [Msg, GoodKey, RouteToNode], [{return, {Msg, RouteToNode}}]),
  erlymock:strict(pastry_tcp, route_msg, [Msg, GoodKey, RouteToNode], [{return, {ok, ok}}]),

  % This is for the message that should be delivered rather than routed
  erlymock:strict(pastry_app, deliver, [self(), Msg, GoodKeyToSelf], [{return, ok}]),
  erlymock:replay(), 

  ?assertEqual(true, route_to_leaf_set(Msg, GoodKey, State)),
  ?assertEqual(true, route_to_leaf_set(Msg, GoodKeyToSelf, State)),
  ?assertEqual(false, route_to_leaf_set(Msg, BadKey, State)),

  erlymock:verify().
  

node_in_leaf_set_test() ->
  State = test_state(),
  Self = State#pastry_state.self,
  ?assertEqual(#node{key=[1,0,0,0]}, node_in_leaf_set([1,0,2,3], State)),
  ?assertEqual(#node{key=[2,0,0,0]}, node_in_leaf_set([1,7,2,3], State)),
  ?assertEqual(Self, node_in_leaf_set([0,0,0,1], State)),
  ?assertEqual(Self, node_in_leaf_set([7,7,7,7], State)),
  ?assertEqual(none, node_in_leaf_set([5,0,0,0], State)).
node_in_leaf_set_when_leaf_set_is_empty_test() ->
  State = (test_state())#pastry_state{leaf_set = {[], []}},
  Self = State#pastry_state.self,
  % Regardless what the key, self should be returned if the leaf set is empty
  ?assertEqual(Self, node_in_leaf_set([0,1,2,3], State)),
  ?assertEqual(Self, node_in_leaf_set([4,3,2,1], State)).

node_closest_to_key_test() ->
  B = 1,
  NodeA = #node{
    key = [0,0,0,1]
  },
  NodeB = #node{
    key = [1,0,0,0]
  },
  Nodes = [NodeA, NodeB],
  ?assertEqual(NodeA, node_closest_to_key([0,0,0,1], Nodes, B)),
  ?assertEqual(NodeA, node_closest_to_key([0,0,0,2], Nodes, B)),
  ?assertEqual(none, node_closest_to_key([1,1,1,1], Nodes, B)),
  ?assertEqual(none, node_closest_to_key([0,0,0,0], Nodes, B)),
  ?assertEqual(none, node_closest_to_key([0,0,0,0], [NodeA,NodeA], B)),
  ?assertEqual(NodeA, node_closest_to_key([0,0,1,0], Nodes, B)).

key_in_range_test() ->
  B = 2,
  ?assert(key_in_range([1,1], [0,0], [2,2], B)),
  ?assert(key_in_range([0,0], [0,0], [2,2], B)),
  ?assert(key_in_range([2,2], [0,0], [2,2], B)),
  ?assert(key_in_range([4,1], [3,0], [2,2], B)),
  ?assert(key_in_range([0,0], [8,0], [2,2], B)),
  ?assert(key_in_range([0,0,0,0], [0,0,0,0], [1,0,0,0], B)),
  ?assertNot(key_in_range([1,1], [2,0], [2,3], B)),
  ?assertNot(key_in_range([1,1], [2,0], [2,0], B)),
  ?assertNot(key_in_range([1,1], [2,0], [2,2], B)),
  ?assertNot(key_in_range([4,1], [2,0], [2,3], 3)).

closer_node_test() ->
  B = 1,
  NodeA = #node{
    key = [0,0,0]
  },
  NodeB = #node{
    key = [1,0,0]
  },
  ?assertEqual(NodeA, closer_node([0,0,0], NodeA, NodeB, B)),
  ?assertEqual(NodeA, closer_node([0,0,1], NodeA, NodeB, B)),
  ?assertEqual(NodeA, closer_node([0,1,0], NodeA, NodeB, B)),
  ?assertEqual(NodeB, closer_node([0,1,1], NodeA, NodeB, B)),
  ?assertEqual(NodeB, closer_node([1,0,0], NodeA, NodeB, B)),

  HighB = 3,
  Node1 = #node{
    key = [7,0,0]
  },
  ?assertEqual(NodeA, closer_node([7,7,7], NodeA, Node1, HighB)).

key_diff_test() ->
  B = 2,
  ?assertEqual(4, key_diff([2,0], [1,0], B)),
  ?assertEqual(0, key_diff([3,3], [0,0], B)),
  ?assertEqual(4, key_diff([1,0], [2,0], B)),
  ?assertEqual(4, key_diff([-1,0], [0,0], B)),
  ?assertEqual(85, key_diff([1,1,1,1], [2,2,2,2], B)),
  ?assertEqual(0, key_diff([2,0], [2,0], B)).

find_corresponding_routing_table_test() ->
  MyKey = [1,2,3,4],
  State = (test_state())#pastry_state{routing_table = create_routing_table(MyKey)},
  {#routing_table_entry{value = none}, [none,2]} = find_corresponding_routing_table([2,4,0,0], State),
  {#routing_table_entry{value = 1}, [none, 1, 4]} = find_corresponding_routing_table([1,4,0,0], State),
  {#routing_table_entry{value = 2}, [none, 1, 2, 0]} = find_corresponding_routing_table([1,2,0,0], State),
  {#routing_table_entry{value = 3}, [none, 1, 2, 3, 0]} = find_corresponding_routing_table([1,2,3,0], State).

route_to_node_in_routing_table_test() ->
  State = test_state(),
  Node = #node{
    key = [0,1,4,0]
  },
  UpdatedState = State#pastry_state{routing_table = merge_node_in_rt(Node, State#pastry_state.routing_table)},
  Msg = msg,

  ?assertNot(route_to_node_in_routing_table(Msg, [0,2,0,0], UpdatedState)),

  GoodKey = [0,1,5,0],
  erlymock:start(),
  erlymock:strict(pastry_app, forward, [Msg, GoodKey, Node], [{return, {Msg, Node}}]),
  erlymock:strict(pastry_tcp, route_msg, [Msg, GoodKey, Node], [{return, {ok, ok}}]),
  erlymock:replay(), 
  ?assert(route_to_node_in_routing_table(Msg, GoodKey, UpdatedState)),
  erlymock:verify().

route_to_closer_node_test() ->
  State = test_state(),
  Msg = msg,
  CloserNode = #node{
    key = [3,0,0,0]
  },
  % This node is already in the State from test_state()
  LeafNode = #node{
    key = [6,0,0,0]
  },

  NeighborNode = #node{
    key = [5,2,0,0]
  },

  UpdatedState = State#pastry_state{
    routing_table = merge_node_in_rt(CloserNode, State#pastry_state.routing_table),
    neighborhood_set = [NeighborNode]
  },

  erlymock:start(),
  % When called with key = [4,0,0,0]
  Key1 = [4,0,0,0],
  erlymock:strict(pastry_app, forward, [Msg, Key1, CloserNode], [{return, {Msg, CloserNode}}]),
  erlymock:strict(pastry_tcp, route_msg, [Msg, Key1, CloserNode], [{return, {ok, ok}}]),

  % When called with key = [5,5,5,5]
  Key2 = [5,5,5,5],
  erlymock:strict(pastry_app, forward, [Msg, Key2, LeafNode], [{return, {Msg, LeafNode}}]),
  erlymock:strict(pastry_tcp, route_msg, [Msg, Key2, LeafNode], [{return, {ok, ok}}]),
  
  % When called with key = [5,0,0,0]
  Key3 = [5,0,0,0],
  erlymock:strict(pastry_app, forward, [Msg, Key3, NeighborNode], [{return, {Msg, NeighborNode}}]),
  erlymock:strict(pastry_tcp, route_msg, [Msg, Key3, NeighborNode], [{return, {ok, ok}}]),

  erlymock:replay(), 
  ?assert(route_to_closer_node(Msg, Key1, UpdatedState)),
  ?assert(route_to_closer_node(Msg, Key2, UpdatedState)),
  ?assert(route_to_closer_node(Msg, Key3, UpdatedState)),
  erlymock:verify().

shared_key_segment_test() ->
  Node = #node{
    key = [1,2,3,4]
  },
  ?assertEqual([], shared_key_segment(Node, [2,3,4,0])),
  ?assertEqual([1], shared_key_segment(Node, [1,3,4,0])),
  ?assertEqual([1,2], shared_key_segment(Node, [1,2,4,0])),
  ?assertEqual([1,2,3], shared_key_segment(Node, [1,2,3,0])),
  ?assertEqual([1,2,3,4], shared_key_segment(Node, [1,2,3,4])).

perform_welcomed_test() ->
  MyId = [1,0],
  Self = #node{
    key = MyId
  },
  SmallerLeaf = #node{
    key = [0,7]
  },
  GreaterLeaf = #node{
    key = [1,1]
  },
  OtherNode1 = #node{
    key = [2,0]
  },
  OtherNode2 = #node{
    key = [1,4]
  },
  NeighborNode = #node{
    key = [4,1]
  },

  RoutingTable = merge_node_in_rt(OtherNode1, merge_node_in_rt(OtherNode2, create_routing_table(MyId))),
  State = #pastry_state{
    self = Self,
    routing_table = RoutingTable, 
    neighborhood_set = [NeighborNode],
    leaf_set = {[SmallerLeaf], [GreaterLeaf]},
    b = 4
  },

  Nodes = [SmallerLeaf, GreaterLeaf, OtherNode1, OtherNode2, NeighborNode],

  erlymock:start(),
  [erlymock:o_o(pastry_tcp, send_routing_table, [RoutingTable, Node], [{return, {ok, ok}}]) || Node <- Nodes],
  erlymock:replay(), 
  perform_welcomed(State),
  erlymock:verify().

all_known_nodes_test() ->
  MyId = [1,0],
  Self = #node{
    key = MyId
  },
  SmallerLeaf = #node{
    key = [0,7]
  },
  GreaterLeaf = #node{
    key = [1,1]
  },
  OtherNode1 = #node{
    key = [2,0]
  },
  OtherNode2 = #node{
    key = [1,4]
  },
  NeighborNode = #node{
    key = [4,1]
  },

  RoutingTable = merge_node_in_rt(OtherNode1, merge_node_in_rt(OtherNode2, create_routing_table(MyId))),
  State = #pastry_state{
    self = Self,
    routing_table = RoutingTable, 
    neighborhood_set = [NeighborNode],
    leaf_set = {[SmallerLeaf], [GreaterLeaf]},
    b = 4
  },

  Nodes = [SmallerLeaf, GreaterLeaf, OtherNode1, OtherNode2, NeighborNode],
  KnownNodes = all_known_nodes(State),
  Nodes -- KnownNodes =:= KnownNodes -- Nodes.

assert_member_of_smaller_leaf_set(Node, State) ->
  {LS,_} = State#pastry_state.leaf_set,
  ?assert(member(Node, LS)).
assert_not_member_of_smaller_leaf_set(Node, State) ->
  {LS,_} = State#pastry_state.leaf_set,
  ?assertNot(member(Node, LS)).
assert_member_of_greater_leaf_set(Node, State) ->
  {_,LSG} = State#pastry_state.leaf_set,
  ?assert(member(Node, LSG)).
assert_not_member_of_greater_leaf_set(Node, State) ->
  {_,LSG} = State#pastry_state.leaf_set,
  ?assertNot(member(Node, LSG)).

merge_node_in_leaf_set_test() ->
  MyKey = [1,0],
  Self = #node{
    key = MyKey
  },
  State = #pastry_state{b = 2, self = Self, pastry_app_pid = papid},
  SmallerNode1 = #node{key = [3,0]},
  SmallerNode2 = #node{key = [0,0]},
  SmallerNode3 = #node{key = [0,3]},
  GreaterNode1 = #node{key = [2,0]},
  GreaterNode2 = #node{key = [1,3]},
  GreaterNode3 = #node{key = [1,1]},

  erlymock:start(),
  erlymock:o_o(pastry_app, new_leaves, [papid, {[SmallerNode1],[]}], [{return, ok}]),
  erlymock:o_o(pastry_app, new_leaves, [papid, {[SmallerNode1, SmallerNode2],[]}], [{return, ok}]),
  erlymock:o_o(pastry_app, new_leaves, [papid, {[SmallerNode2, SmallerNode3],[]}], [{return, ok}]),
  erlymock:o_o(pastry_app, new_leaves, [papid, {[SmallerNode2, SmallerNode3],[GreaterNode1]}], [{return, ok}]),
  erlymock:o_o(pastry_app, new_leaves, [papid, {[SmallerNode2, SmallerNode3],[GreaterNode2, GreaterNode1]}], [{return, ok}]),
  erlymock:o_o(pastry_app, new_leaves, [papid, {[SmallerNode2, SmallerNode3],[GreaterNode3, GreaterNode2]}], [{return, ok}]),
  erlymock:replay(), 

  NewState = merge_node_in_leaf_set(SmallerNode1, State),
  assert_member_of_smaller_leaf_set(SmallerNode1, NewState),
  assert_not_member_of_greater_leaf_set(SmallerNode1, NewState),
  NewState2 = merge_node_in_leaf_set(SmallerNode2, NewState),
  assert_member_of_smaller_leaf_set(SmallerNode1, NewState2),
  assert_member_of_smaller_leaf_set(SmallerNode2, NewState2),
  assert_not_member_of_greater_leaf_set(SmallerNode2, NewState2),
  NewState3 = merge_node_in_leaf_set(SmallerNode3, NewState2),
  assert_not_member_of_smaller_leaf_set(SmallerNode1, NewState3),
  assert_member_of_smaller_leaf_set(SmallerNode2, NewState3),
  assert_member_of_smaller_leaf_set(SmallerNode3, NewState3),

  NewState4 = merge_node_in_leaf_set(GreaterNode1, NewState3),
  assert_member_of_greater_leaf_set(GreaterNode1, NewState4),
  assert_not_member_of_smaller_leaf_set(GreaterNode1, NewState4),
  NewState5 = merge_node_in_leaf_set(GreaterNode2, NewState4),
  assert_member_of_greater_leaf_set(GreaterNode1, NewState5),
  assert_member_of_greater_leaf_set(GreaterNode2, NewState5),
  assert_not_member_of_smaller_leaf_set(GreaterNode2, NewState5),
  NewState6 = merge_node_in_leaf_set(GreaterNode3, NewState5),
  assert_not_member_of_greater_leaf_set(GreaterNode1, NewState6),
  assert_member_of_greater_leaf_set(GreaterNode2, NewState6),
  assert_member_of_greater_leaf_set(GreaterNode3, NewState6),

  % This one should not affect the leaf set, and hence not
  % result in a call to pastry_app
  merge_node_in_leaf_set(GreaterNode3, NewState6),

  % It should never add itself to the leaf set
  AlterEgo = Self#node{distance = 20},
  NewState7 = merge_node_in_leaf_set(AlterEgo, NewState6),
  assert_not_member_of_smaller_leaf_set(AlterEgo, NewState7),
  assert_not_member_of_greater_leaf_set(AlterEgo, NewState7),
  erlymock:verify().
merge_node_in_leaf_set_should_not_allow_duplicates_test() ->
  MyKey = [1,0],
  Self = #node{
    key = MyKey
  },
  State = #pastry_state{b = 2, self = Self},
  SmallerNode1 = #node{key = [3,0]},
  NewState = merge_node_in_leaf_set(SmallerNode1, State),
  NewState = merge_node_in_leaf_set(SmallerNode1, NewState).
merge_node_in_leaf_set_should_not_self_in_leafset_test() ->
  MyKey = [1,0],
  Self = #node{
    key = MyKey
  },
  State = #pastry_state{b = 2, self = Self},
  State = merge_node_in_leaf_set(Self, State).

is_node_less_than_me_test() ->
  Self = #node{key = [0,0,0,0]},
  B = 3,
  ?assert(is_node_less_than_me(#node{key=[7,7,7,7]},Self,B)),
  ?assert(is_node_less_than_me(#node{key=[6,7,7,7]},Self,B)),
  ?assert(is_node_less_than_me(#node{key=[5,0,0,0]},Self,B)),
  ?assert(is_node_less_than_me(#node{key=[4,0,0,0]},Self,B)),
  ?assertNot(is_node_less_than_me(#node{key=[3,0,0,0]},Self,B)),
  ?assertNot(is_node_less_than_me(#node{key=[2,0,0,0]},Self,B)),
  ?assertNot(is_node_less_than_me(#node{key=[1,0,0,0]},Self,B)).

merge_node_in_nhs_test() ->
  B = 1,
  Self = #node{key =[1,2,3]},
  Node1 = #node{distance=4},
  Node2 = #node{distance=3},
  Node3 = #node{distance=2},
  NewNHS = merge_node_in_nhs(Node1, [], B, Self),
  ?assert(member(Node1, NewNHS)),
  NewNHS2 = merge_node_in_nhs(Node2, NewNHS, B, Self),
  ?assert(member(Node1, NewNHS2)),
  ?assert(member(Node2, NewNHS2)),
  NewNHS3 = merge_node_in_nhs(Node3, NewNHS2, B, Self),
  ?assertNot(member(Node1, NewNHS3)),
  ?assert(member(Node2, NewNHS3)),
  ?assert(member(Node3, NewNHS3)),
  % The same node should not be added if already present
  [Node1] = merge_node_in_nhs(Node1, [Node1], B, Self),
  % Should not add self
  [] = merge_node_in_nhs(Self, [], B, Self).

discard_dead_node_from_leafset_test() ->
  DeadNode = #node{key = [1,2,3,4]},
  OtherNode = #node{key = [1,2,2,2]},
  RequestNode = #node{key = [1,2,2,0]},

  State = (test_state())#pastry_state{pastry_app_pid = papid, leaf_set = {[DeadNode, RequestNode], [OtherNode]}},
  ?assert(member(DeadNode, all_known_nodes(State))),
  erlymock:start(),
  erlymock:o_o(pastry_app, new_leaves, [papid, {[RequestNode],[OtherNode]}], [{return, ok}]),
  erlymock:o_o(pastry_tcp, request_leaf_set, [RequestNode], [{return, {ok,{[#node{}],[#node{}]}}}]),
  erlymock:replay(), 
  UpdatedState = discard_dead_node_from_leafset(DeadNode, State),
  % This second time it should not call out to pastry_app again.
  discard_dead_node_from_leafset(DeadNode, UpdatedState),
  erlymock:verify(),
  ?assertNot(member(DeadNode, all_known_nodes(UpdatedState))).

discard_dead_node_from_neighborhoodset_test() ->
  DeadNode = #node{
    key = [1,2,3,4]
  },
  State = (test_state())#pastry_state{neighborhood_set = [DeadNode]},
  ?assert(member(DeadNode, all_known_nodes(State))),
  UpdatedState = discard_dead_node_from_neighborhoodset(DeadNode, State),
  ?assertNot(member(DeadNode, all_known_nodes(UpdatedState))).

discard_dead_node_from_routing_table_test() ->
  DeadNode = #node{
    key = [1,2,3,4]
  },
  State = test_state(),
  OrigRoutingTable = State#pastry_state.routing_table,
  StateWithRoutingTable = State#pastry_state{routing_table = merge_node_in_rt(DeadNode, OrigRoutingTable)},
  ?assert(member(DeadNode, all_known_nodes(StateWithRoutingTable))),
  UpdatedState = discard_dead_node_from_routing_table(DeadNode, StateWithRoutingTable),
  ?assertNot(member(DeadNode, all_known_nodes(UpdatedState))),
  ?assertEqual(OrigRoutingTable, UpdatedState#pastry_state.routing_table).

perform_discard_dead_node_test() ->
  DeadNode1 = #node{key = [0,0,1]},
  DeadNode2 = #node{key = [0,0,2]},
  DeadNode3 = #node{key = [0,0,3]},
  State = (test_state())#pastry_state{leaf_set = {[DeadNode1], []}, neighborhood_set = [DeadNode3]},
  OrigRoutingTable = State#pastry_state.routing_table,
  StateWithNodes = State#pastry_state{routing_table = merge_node_in_rt(DeadNode2, OrigRoutingTable)},
  % At this point we have three dead nodes in the mix,
  ?assert(member(DeadNode1, all_known_nodes(StateWithNodes))),
  ?assert(member(DeadNode2, all_known_nodes(StateWithNodes))),
  ?assert(member(DeadNode3, all_known_nodes(StateWithNodes))),
  UpdatedState = perform_discard_dead_node(DeadNode1, 
    perform_discard_dead_node(DeadNode2, 
      perform_discard_dead_node(DeadNode3, StateWithNodes))),
  ?assertNot(member(DeadNode1, all_known_nodes(UpdatedState))),
  ?assertNot(member(DeadNode2, all_known_nodes(UpdatedState))),
  ?assertNot(member(DeadNode3, all_known_nodes(UpdatedState))).

perform_neighborhood_watch_test() ->
  State = test_state(),
  N1 = #node{key = [1,2,3,4]},
  N2 = #node{key = [2,3,4,5]},
  erlymock:start(),
  erlymock:o_o(pastry_tcp, is_node_alive, [N1], [{return, true}]),
  erlymock:o_o(pastry_tcp, is_node_alive, [N2], [{return, false}]),
  % The should remove the node... can't easily test for this... dang.
  erlymock:replay(), 
  perform_neighborhood_watch(State#pastry_state{neighborhood_set = [N1, N2]}),
  erlymock:verify().

perform_neighborhood_set_expansion_test() ->
  % B = 3, so it won't be happy unless there are 2^b neihgbors (8)
  N = #node{key = [1,2,3,4]},
  State = (test_state())#pastry_state{neighborhood_set = [N]},
  NHS = [#node{key = [2,3,4,5]}],
  erlymock:start(),
  erlymock:o_o(pastry_tcp, request_neighborhood_set, [N], [{return, {ok, NHS}}]),
  % Second call does not, because the set is already big enough
  erlymock:replay(), 
  perform_neighborhood_set_expansion(State),
  perform_neighborhood_set_expansion(State#pastry_state{neighborhood_set = [N, N, N, N, N, N, N, N]}),
  erlymock:verify().

-endif.
