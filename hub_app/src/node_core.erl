-module(node_core).

-include("records.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-export([
    register_node/2,
    register_controller/2,
    remove_controller/2,
    update_controller_state/3
  ]).

-import(lists, [member/2]).

%% ------------------------------------------------------------------
%% Implementation
%% ------------------------------------------------------------------

register_node(Node, #state{controllers = Controllers}) -> 
  get_not_me(Node, Controllers).

register_controller(Controller, #state{controllers = Controllers} = State) ->
  keep_while_alive(Controller),
  State#state{controllers = [Controller | Controllers]}.

get_not_me(Node, Controllers) ->
  NumToGet = 5,
  ControllersNotMyOwn = [Cntrl || Cntrl <- Controllers, Cntrl#controller.ip =/= Node#node.ip],
  case ControllersNotMyOwn of
    [] ->
      % There is only one controller, our own. So we are first
      [Controller] = Controllers,
      Nodes = get_diverse_nodes([{Controller#controller.ip, Controller#controller.ports}], NumToGet),
      case Nodes of
        [] -> first;
        Vals -> Vals
      end;
    Controllers ->
      % Try to return nodes with a good spread. They should not all be hosted on the same machine
      Nodes = [{Ip, Ports} || #controller{ip = Ip, ports = Ports} <- Controllers],
      get_diverse_nodes(Nodes, NumToGet)
  end.

get_diverse_nodes(Nodes, NumToGet) -> get_diverse_nodes(Nodes, NumToGet, []).
get_diverse_nodes(_, 0, Acc) -> Acc;
get_diverse_nodes([],_, Acc) -> Acc;
get_diverse_nodes([{_Ip, []}|Nodes], NumToGet, Acc) -> get_diverse_nodes(Nodes, NumToGet, Acc);
get_diverse_nodes([{Ip, [Port|Ports]}|Nodes], NumToGet, Acc) -> 
  get_diverse_nodes(Nodes ++ [{Ip, Ports}], NumToGet - 1, [{Ip, Port}|Acc]).

remove_controller(Controller, #state{controllers = Controllers} = State) ->
  State#state{controllers = Controllers -- [Controller]}.

keep_while_alive(Node) ->
  spawn(fun() -> liveness_checker(Node, 1000) end).

liveness_checker(Controller, Interval) ->
  receive after Interval -> ok end,
  NextInterval = case Interval < 30000 of
    true -> Interval * 2;
    false -> Interval
  end,
  io:format("Checking liveness of controller ~p~n", [Controller]),
  case hub_tcp:get_update(Controller) of
    dead -> node:remove_controller(Controller);
    Update -> 
      {pong, node_count, _NumNodes, mode, Mode, ports, Ports} = Update,
      node:set_state_for_controller(Controller, {Mode, Ports}),
      liveness_checker(Controller, NextInterval)
  end.

update_controller_state(Controller, {Mode, Ports}, #state{controllers = Controllers} = State) ->
  NewControllers = (Controllers -- [Controller]) ++ [Controller#controller{mode = Mode, ports = Ports}],
  State#state{controllers = NewControllers}.

%% ------------------------------------------------------------------
%% Tests
%% ------------------------------------------------------------------

-ifdef(TEST).

get_not_me_first_test() ->
  Ip = {1,2,3,4},
  Port = 1234,
  Node = #node{
    ip = Ip,
    port = Port
  },
  Controller = #controller{
    ip = Ip,
    port = Port,
    mode = chord,
    ports = []
  },
  ?assertEqual(first, get_not_me(Node, [Controller])).

get_not_me_when_only_one_host_test() ->
  Ip = {1,2,3,4},
  Port = 1234,
  Node = #node{
    ip = Ip,
    port = Port
  },
  ReturnPort1 = 4444,
  ReturnPort2 = 4445,
  ReturnPort3 = 4446,
  Controller = #controller{
    ip = Ip,
    port = Port,
    mode = chord,
    ports = [ReturnPort1, ReturnPort2, ReturnPort3]
  },
  ReturnValues = [
    {Ip, ReturnPort1}, {Ip, ReturnPort2},{Ip, ReturnPort3}
  ],
  Returned = get_not_me(Node, [Controller]),
  [?assert(member(N, ReturnValues)) || N <- Returned].

get_not_me_test() ->
  Ip = {1,2,3,4},
  Ip2 = {2,2,3,4},
  Ip3 = {3,2,3,4},
  Port = 1234,
  Port2 = 1235,
  Port3 = 1236,
  Node = #node{
    ip = Ip,
    port = Port
  },
  ReturnPort1 = 4444,
  ReturnPort2 = 4445,
  ReturnPort3 = 4446,
  ReturnPort4 = 4447,
  ReturnPort5 = 4448,
  ReturnPort6 = 4449,

  Controller = #controller{
    ip = Ip2,
    port = Port2,
    mode = chord,
    ports = [ReturnPort1, ReturnPort2]
  },
  Controller2 = #controller{
    ip = Ip3,
    port = Port3,
    mode = chord,
    ports = [ReturnPort3, ReturnPort4, ReturnPort5, ReturnPort6]
  },
  ReturnValues = [
    {Ip2, ReturnPort1}, {Ip2, ReturnPort2},
    {Ip3, ReturnPort3}, {Ip3, ReturnPort4}, {Ip3, ReturnPort5}
  ],
  Returned = get_not_me(Node, [Controller, Controller2]),
  [?assert(member(N, ReturnValues)) || N <- Returned].

liveness_checker_test() ->
  C = #controller{port=1, ip = {1,2,3,4}},
  erlymock:start(),
  erlymock:strict(hub_tcp, get_update, [C], [{return, {pong, node_count, 1, mode, chord, ports, [1]}}]),
  erlymock:strict(node, set_state_for_controller, [C, {chord, [1]}], [{return, ok}]),
  erlymock:strict(hub_tcp, get_update, [C], [{return, dead}]),
  erlymock:strict(node, remove_controller, [C], [{return, ok}]),
  erlymock:replay(), 
  liveness_checker(C, 1),
  erlymock:verify().

remove_controller_test() ->
  Controller = #controller{
    ip = {1,2,3,4},
    port = 1234,
    mode = chord,
    ports = []
  },
  State = #state{controllers = [Controller]},
  NewState = remove_controller(Controller, State),
  ?assertNot(member(Controller, NewState#state.controllers)).

register_controller_test() ->
  State = #state{},
  Controller = #controller{
    ip = {1,2,3,4},
    port = 1234,
    mode = chord,
    ports = []
  },
  NewState = register_controller(Controller, State),
  ?assert(member(Controller, NewState#state.controllers)).

update_controller_state_test() ->
  Controller = #controller{
    ip = {1,2,3,4},
    port = 1234,
    mode = chord,
    ports = [1,2,3]
  },
  State = #state{controllers = [Controller]},
  #state{controllers = [C]} =
    update_controller_state(Controller, {pastry, [1,4]}, State),
  ?assertEqual([1,4], C#controller.ports),
  ?assertEqual(pastry, C#controller.mode).

-endif.
