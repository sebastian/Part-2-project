-module(node_core).
-include("records.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-export([
    register_chord/2,
    register_pastry/2,
    remove_node/2
  ]).

-import(lists, [member/2]).

%% ------------------------------------------------------------------
%% Implementation
%% ------------------------------------------------------------------

register_chord(Node, State = #state{chord_nodes = Chord}) -> 
  keep_while_alive(Node),
  {get_not_me(Node, Chord), State#state{chord_nodes = update_node_list(Node, Chord)}}.

register_pastry(Node, State = #state{pastry_nodes = PastryNodes}) -> 
  keep_while_alive(Node),
  {get_not_me(Node, PastryNodes), State#state{pastry_nodes = update_node_list(Node, PastryNodes)}}.

register_controller(Controller, State) ->
  State.

update_node_list(Node, Nodes) ->
  case member(Node, Nodes) of
    true -> Nodes;
    false -> [Node|Nodes]
  end.

get_not_me(Node, Nodes) ->
  NumToGet = 5,
  Peers = lists:sublist(Nodes -- [Node], NumToGet),
  case Peers of
    [] -> first;
    _ -> [{Ip, Port} || #node{ip = Ip, port = Port} <- Peers]
  end.

remove_node(Node, #state{chord_nodes = CN, pastry_nodes = PN} = State) ->
  State#state{chord_nodes = CN -- [Node], pastry_nodes = PN -- [Node]}.

keep_while_alive(Node) ->
  spawn(fun() -> liveness_checker(Node, 2000) end).

liveness_checker(Node, Interval) ->
  receive after Interval -> ok end,
  NextInterval = case Interval < 60000 of
    true -> Interval * 2;
    false -> Interval
  end,
  io:format("Checking liveness of node ~p~n", [Node]),
  case hub_tcp:is_node_alive(Node) of
    false -> node:remove_node(Node);
    _ -> liveness_checker(Node, NextInterval)
  end.

%% ------------------------------------------------------------------
%% Tests
%% ------------------------------------------------------------------

-ifdef(TEST).

get_not_me_first_test() ->
  ?assertEqual(first, get_not_me({ip, port}, [])).

get_not_me_test() ->
  N1 = #node{ip = ip, port = port}, N2 = #node{ip = other_ip, port = other_port},
  Nodes = [N1, N2],
  ?assertEqual([{other_ip, other_port}], get_not_me(N1, Nodes)).

register_chord_test() ->
  Node = #node{ip = {1,2,3,4}, port = 1234},
  State = #state{},
  NewState = #state{chord_nodes = [Node]},
  Result = {first, NewState},
  ?assertEqual(Result, register_chord(Node, State)),
  ?assertEqual(Result, register_chord(Node, NewState)).

liveness_checker_test() ->
  N = #node{port=1},
  erlymock:start(),
  erlymock:strict(hub_tcp, is_node_alive, [N], [{return, true}]),
  erlymock:strict(hub_tcp, is_node_alive, [N], [{return, false}]),
  erlymock:strict(node, remove_node, [N], [{return, ok}]),
  erlymock:replay(), 
  liveness_checker(N, 1),
  erlymock:verify().

remove_node_test() ->
  Node = #node{},
  State = #state{chord_nodes = [Node], pastry_nodes = [Node]},
  NewState = remove_node(Node, State),
  ?assertEqual([], NewState#state.chord_nodes),
  ?assertEqual([], NewState#state.pastry_nodes).

register_controller_test() ->
  State = #state{},
  ?assert(false).

-endif.
