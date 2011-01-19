-module(node_core).
-include("records.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-export([
    register_chord/2,
    register_pastry/2,
    check_liveness/1,
    remove_node/2
  ]).

-import(lists, [member/2]).

%% ------------------------------------------------------------------
%% Implementation
%% ------------------------------------------------------------------

register_chord(Node, State = #state{chord_nodes = Chord}) -> 
  {get_not_me(Node, Chord), State#state{chord_nodes = update_node_list(Node, Chord)}}.

register_pastry(Node, State = #state{pastry_nodes = PastryNodes}) -> 
  {get_not_me(Node, PastryNodes), State#state{pastry_nodes = update_node_list(Node, PastryNodes)}}.

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

check_liveness(Nodes) ->
  F = fun(N) ->
    spawn(fun() ->
      io:format("Checking liveness of node ~p~n", [N]),
      case hub_tcp:is_node_alive(N) of
        false -> 
          io:format("Node is dead: ~p~n", [N]),
          node:remove_node(N);
        _ -> 
          io:format("Node is alive: ~p~n", [N])
      end
    end)
  end,
  [F(Node) || Node <- Nodes].

remove_node(Node, #state{chord_nodes = CN, pastry_nodes = PN} = State) ->
  State#state{chord_nodes = CN -- [Node], pastry_nodes = PN -- [Node]}.

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

check_liveness_test() ->
  N1 = #node{port=1},
  N2 = #node{port=2},
  N3 = #node{port=3},
  N4 = #node{port=4},
  Nodes = [N1, N2, N3, N4],
  erlymock:start(),
  erlymock:o_o(hub_tcp, is_node_alive, [N1], [{return, true}]),
  erlymock:o_o(hub_tcp, is_node_alive, [N2], [{return, true}]),
  erlymock:o_o(hub_tcp, is_node_alive, [N3], [{return, true}]),
  erlymock:o_o(hub_tcp, is_node_alive, [N4], [{return, false}]),
  erlymock:o_o(node, remove_node, [N4], [{return, ok}]),
  erlymock:replay(), 
  check_liveness(Nodes),
  erlymock:verify().

remove_node_test() ->
  Node = #node{},
  State = #state{chord_nodes = [Node], pastry_nodes = [Node]},
  NewState = remove_node(Node, State),
  ?assertEqual([], NewState#state.chord_nodes),
  ?assertEqual([], NewState#state.pastry_nodes).

-endif.
