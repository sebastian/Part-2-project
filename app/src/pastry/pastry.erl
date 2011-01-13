-module(pastry).
-behaviour(gen_server).

-define(SERVER, ?MODULE).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-include("../fs.hrl").
-include("pastry.hrl").

-import(lists, [reverse/1, foldl/3, member/2, flatten/1, filter/2]).

%% ------------------------------------------------------------------
%% Public API
%% ------------------------------------------------------------------

-export([start_link/0, start/0, stop/0]).
-export([lookup/1, set/2]).
-export([
    pastryInit/1,
    route/2
  ]).

%% ------------------------------------------------------------------
%% PRIVATE API Function Exports
%% ------------------------------------------------------------------

% For joining
-export([
    augment_routing_table/1,
    let_join/1
  ]).

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

start() ->
  gen_server:start({local, ?SERVER}, ?MODULE, [], []).

start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

stop() ->
  gen_server:call(?MODULE, stop).

%% @doc: gets a value from the chord network
-spec(lookup/1::(Key::key()) -> [#entry{}]).
lookup(_Key) ->
  ok.

%% @doc: stores a value in the chord network
-spec(set/2::(Key::key(), Entry::#entry{}) -> ok).
set(_Key, _Entry) ->
  ok.

pastryInit(_Node) ->
  magic.

route(Msg, Key) ->
  gen_server:cast({route, Msg, Key}),
  ok.


%% ------------------------------------------------------------------
%% PRIVATE API Function Definitions
%% ------------------------------------------------------------------

augment_routing_table(RoutingTable) ->
  gen_server:cast(?SERVER, {augment_routing_table, RoutingTable}),
  thanks.


let_join(Node) ->
  % Forward the routing message to the next node
  route({join, Node}, Node#node.key),
  % @todo: If this is the final destination of the join message, then
  % also send a special welcome message to the node to let
  % it know that is has received all the info it will receive for now.
  % Following that the node should broadcast its routing table to all
  % it knows about.
  % We add the node to our routing table so we can route to it later.
  add_nodes(Node),
  % Respond with our routing table
  gen_server:call(?SERVER, get_routing_table).


add_nodes(Nodes) ->
  gen_server:cast(?SERVER, {add_nodes, Nodes}).


%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(Args) -> 
  B = proplists:get_value(b, Args),
  Port = proplists:get_value(port, Args),
  Ip = utilities:get_ip(),
  Key = utilities:key_for_node_with_b(Ip, Port, B),
  Self = #node{key = Key, port = Port, ip = Ip},

  {_JoinIp, _JoinPort} = proplists:get_value(joinNode, Args),

  State = #pastry_state{
    b = B,
    self = Self,
    routing_table = create_routing_table(Key)
  },
  {ok, State}.

% Call:
handle_call(get_routing_table, _From, State) ->
  {reply, State#pastry_state.routing_table, State};

handle_call(stop, _From, State) ->
  {stop, normal, ok, State}.


% Casts:
handle_cast({route, Msg, Key}, State) ->
  route_msg(Msg, Key, State),
  {noreply, State};

handle_cast({augment_routing_table, RoutingTable}, State) ->
  add_nodes(nodes_in_routing_table(RoutingTable)),
  {noreply, State};

handle_cast({add_nodes, Nodes}, State) ->
  prepare_nodes_for_adding(Nodes),
  {noreply, State};

handle_cast({update_local_state_with_nodes, Nodes}, #pastry_state{routing_table = RT} = State) ->
  NewRT = foldl(fun(Node, PrevRoutingTable) ->
    merge_node(Node, PrevRoutingTable)
  end, RT, Nodes),
  {noreply, State#pastry_state{routing_table = NewRT}};

handle_cast(Msg, State) ->
  error_logger:error_msg("received unknown cast: ~p", [Msg]),
  {noreply, State}.


% Info:
handle_info(Info, State) ->
  error_logger:error_msg("Got info message: ~p", [Info]),
  {noreply, State}.


% Terminate:
terminate(_Reason, _State) ->
  ok.


code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

create_routing_table(Key) ->
  [#routing_table_entry{value = none} | [#routing_table_entry{value = V} || V <- Key]].


% @doc: Adds a node to the routing table. If there is already a node
% occupying the location, then the closer of the two is kept.
merge_node(#node{key = Key} = OtherNode, RoutingTable) ->
  merge_node(RoutingTable, empty, [none|Key], [], OtherNode).
% Last routing table entry. Since we have a match, the node must be us.
% We don't want to include ourselves in the list.
merge_node([], R, _, _, _Node) ->
  [R];
% The keypath matches, so nothing to do as of yet.
merge_node([#routing_table_entry{value = I} = R|RR], PrevR, [I|Is], KeySoFar, Node) ->
  case PrevR of
    empty -> merge_node(RR, R, Is, [I], Node);
    Prev -> [Prev|merge_node(RR, R, Is, [I|KeySoFar], Node)]
  end;
% At this point there is no longer a match between our key and the key 
% of the node. Conditionally change it in place.
merge_node(RR, #routing_table_entry{nodes = Nodes} = PrevR, [I|_], KeySoFar, Node) ->
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


prepare_nodes_for_adding(Nodes) when is_list(Nodes) ->
  % Get the local distance of the nodes before adding them
  % to our own routing table.
  spawn(fun() ->
    gen_server:cast(?SERVER, {
      update_local_state_with_nodes, 
      [N#node{distance = pastry_locality:distance(N#node.ip)} || N <- Nodes]
    })
  end);
prepare_nodes_for_adding(Node) -> prepare_nodes_for_adding([Node]).


route_msg(Msg, Key, State) ->
  route_to_leaf_set(Msg, Key, State) orelse
  route_to_node_in_routing_table(Msg, Key, State) orelse
  route_to_closer_node(Msg, Key, State).


route_to_closer_node(Msg, Key, #pastry_state{
    self = Self, 
    routing_table = RoutingTable,
    leaf_set = {LeafSetSmaller, LeafSetLarger},
    neighborhood_set = NeighborHoodSet,
    b = B}) ->
  SharedKeySegment = shared_key_segment(Self, Key),
  Nodes = filter(
    fun(N) -> is_valid_key_path(N, SharedKeySegment) end, 
    nodes_in_routing_table(RoutingTable) ++ LeafSetSmaller ++ LeafSetLarger ++ NeighborHoodSet
  ),
  ClosestNode = foldl(fun(N, CurrentClosest) -> closer_node(Key, N, CurrentClosest, B) end, Self, Nodes),
  do_forward_msg(Msg, Key, ClosestNode).


shared_key_segment(#node{key = NodeKey}, Key) -> shared_key_segment(NodeKey, Key, []).
shared_key_segment([A|As], [A|Bs], Acc) -> shared_key_segment(As, Bs, [A|Acc]);
shared_key_segment(_, _, Acc) -> reverse(Acc).


route_to_node_in_routing_table(Msg, Key, State) ->
  {#routing_table_entry{nodes = Nodes}, [none|PreferredKeyMatch]} = find_corresponding_routing_table(Key, State),
  case filter(fun(Node) -> is_valid_key_path(Node, PreferredKeyMatch) end, Nodes) of
    [] -> false;
    [Node] -> do_forward_msg(Msg, Key, Node)
  end.


find_corresponding_routing_table(Key, #pastry_state{routing_table = [R|Rs]}) ->
  find_corresponding_routing_table([none|Key], [R|Rs], R, []).
find_corresponding_routing_table([Key|Ks], [#routing_table_entry{value = Key} = R|Rs], _, KeySoFar) ->
  find_corresponding_routing_table(Ks, Rs, R, [Key|KeySoFar]);
find_corresponding_routing_table([Key|_], _, Previous, KeySoFar) -> {Previous, reverse([Key|KeySoFar])}.


route_to_leaf_set(Msg, Key, #pastry_state{self = Self} = State) ->
  case node_in_leaf_set(Key, State) of
    none -> false;
    Self -> 
      pastry_app:deliver(Msg, Key),
      true;
    Node -> do_forward_msg(Msg, Key, Node)
  end.


do_forward_msg(Msg, Key, Node) ->
  case pastry_app:forward(Msg, Key, Node) of
    {_, null} -> true; % Message shouldn't be forwarded.
    {NewMsg, NewNode} ->
      case pastry_tcp:route_msg(NewMsg, Key, NewNode) of
        {ok, _} -> true;
        {error, Reason} ->
          % TODO
          error_logger:error_msg("Couldn't forward a message. Need to handle error mesage: ~p", [Reason]),
          true
      end
  end.

% Returns the node closest to the key in the leaf set, or none if
% the key is outside the leafset
node_in_leaf_set(Key, #pastry_state{leaf_set = {LeafSetSmaller, LeafSetGreater}, b = B, self = Self}) ->
  % Is it in the leaf set in the first place?
  case key_in_range(Key, (hd(LeafSetSmaller))#node.key, (hd(reverse(LeafSetGreater)))#node.key) of
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
  case key_in_range(Key, Node1#node.key, Node2#node.key) of
    false -> node_closest_to_key(Key, [Node2|Ns], B);
    true -> closer_node(Key, Node1, Node2, B)
  end;
node_closest_to_key(_, _, _) -> none.


% @doc: Inclusive range check. Returns true if Key is greater or equal to start and
% less or equal to end.
key_in_range(Key, Start, End) ->
  case Start < End of
    true -> (Start =< Key) andalso (Key =< End);
    false -> (Start =< Key) orelse ((0 =< Key) andalso (Key =< End))
  end.


closer_node(Key, #node{key = Ka} = NodeA, #node{key = Kb} = NodeB, B) ->
  case key_diff(Key, Ka, B) =< key_diff(Key, Kb, B) of
    true -> NodeA;
    false -> NodeB
  end.


key_diff(K1, K2, B) -> key_diff(K1, K2, 1 bsl B, {0,0}, 0).
% This slightly more complex formula comes from the following problem.
% Suppose you have a b = 3 and you want the difference between keys
% [7] and [0]. That difference, since the keyspace wraps at 7, should
% be 0 rather than 1.
key_diff([], [], _, {A,B}, Max) -> min(abs(A-B), Max - max(A,B) + min(A,B));
key_diff([A|As], [B|Bs], Mul, {K1, K2}, Max) -> key_diff(As, Bs, Mul, {K1 * Mul + A, K2 * Mul + B}, Max * Mul + Mul-1). 


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
    b = 3
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
  

merge_node_no_shared_test() ->
  MyKey = [0,0],
  RoutingTable = create_routing_table(MyKey),

  ANode = #node{key = [1,1]},
  BNode = #node{key = [0,1], distance = 12},
  CNode = #node{key = [0,1], distance = 2},
  DNode = #node{key = [0,2], distance = 12},
  Self  = #node{key = MyKey, distance = 0},

  ?assert(level_for_key_path_contains_node([none], ANode, merge_node(ANode, RoutingTable))),
  RoutingTableWithB = merge_node(BNode, RoutingTable),
  ?assert(level_for_key_path_contains_node([none,0], BNode, RoutingTableWithB)),
  % Now we add node C, which should replace node B.
  RoutingTableWithC = merge_node(CNode, RoutingTableWithB),
  ?assert(level_for_key_path_contains_node([none,0], CNode, RoutingTableWithC)),
  ?assertNot(level_for_key_path_contains_node([none,0], BNode, RoutingTableWithC)),
  % Now we add node D which doesn't conflict. It should therefore have both C and D
  RoutingTableWithCandD = merge_node(DNode, RoutingTableWithC),
  ?assert(level_for_key_path_contains_node([none,0], CNode, RoutingTableWithCandD)),
  ?assert(level_for_key_path_contains_node([none,0], DNode, RoutingTableWithCandD)),

  % Try to add myself, but that shouldn't affect the table
  ?assertNot(level_for_key_path_contains_node([none], Self, merge_node(Self, RoutingTable))),
  ?assertNot(level_for_key_path_contains_node([none,0], Self, merge_node(Self, RoutingTable))),
  ?assertNot(level_for_key_path_contains_node([none,0,0], Self, merge_node(Self, RoutingTable))).


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
  FullRoutingTable = merge_node(N1, merge_node(N2, merge_node(N3, merge_node(N4, RoutingTable)))),
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
  erlymock:strict(pastry_app, deliver, [Msg, GoodKeyToSelf], [{return, ok}]),
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
  ?assertEqual(NodeA, node_closest_to_key([0,0,1,0], Nodes, B)).


key_in_range_test() ->
  ?assert(key_in_range([1,1], [0,0], [2,2])),
  ?assert(key_in_range([0,0], [0,0], [2,2])),
  ?assert(key_in_range([2,2], [0,0], [2,2])),
  ?assert(key_in_range([4,1], [3,0], [2,2])),
  ?assert(key_in_range([0,0], [8,0], [2,2])),
  ?assert(key_in_range([0,0,0,0], [0,0,0,0], [1,0,0,0])),
  ?assertNot(key_in_range([1,1], [2,0], [2,3])),
  ?assertNot(key_in_range([4,1], [2,0], [2,3])).


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
  UpdatedState = State#pastry_state{routing_table = merge_node(Node, State#pastry_state.routing_table)},
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
    routing_table = merge_node(CloserNode, State#pastry_state.routing_table),
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

-endif.
