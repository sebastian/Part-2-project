-module(node_core).

-include("records.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-export([
    register_node/2,
    register_controller/2,
    remove_controller/2,
    update_controller_state/3,
    switch_mode_to/2,
    ensure_running_n/2,
    start_nodes/2,
    stop_nodes/2,
    start_logging/1,
    stop_logging/1,
    clear_logs/1,
    get_logs/1,
    upgrade_systems/1,
    experimental_runner/1,
    stop_experimental_phase/1
  ]).

-import(lists, [member/2, sort/1, sort/2, reverse/1]).

%% ------------------------------------------------------------------
%% Implementation
%% ------------------------------------------------------------------

register_node(Node, #state{controllers = Controllers} = State) ->
  UpdatedControllersList = register_node_in_controllers(Node, Controllers),
  {get_not_me(Node, Controllers), State#state{controllers = UpdatedControllersList}}.

register_node_in_controllers(Node, Controllers) ->
  AllPorts = lists:foldl(fun(#controller{ports = P}, Ps) -> P ++ Ps end, [], Controllers),
  case length(AllPorts) of
    0 ->
      % This is the first node that is registering.
      % We add the port to the list even before we get to know about it
      % through pinging the nodes so that the other nodes trying to connect
      % have a node to connect to.
      MatchingControllers = [C || C <- Controllers, C#controller.ip =:= Node#node.ip],
      MatchingController = hd(MatchingControllers),
      [MatchingController#controller{ports = [Node#node.port]} | (Controllers -- [MatchingController])];
    _ ->
      % There are already ports in the list, hence this node is not the first.
      % We will be notified about it when we ping its controller the next time
      Controllers
  end.

register_controller(Controller, #state{controllers = Controllers} = State) ->
  keep_while_alive(Controller),
  UpdatedControllers = case [C || C <- Controllers, C#controller.ip =:= Controller#controller.ip] of
    [] -> sort(fun(A,B) -> A#controller.ip =< B#controller.ip end, [Controller | Controllers]);
    _SameController -> Controllers
  end,
  State#state{controllers = UpdatedControllers}.

get_not_me(Node, Controllers) ->
  ControllersNotMyOwn = [Cntrl || Cntrl <- Controllers, Cntrl#controller.ip =/= Node#node.ip],
  case rendevouz_nodes_from_controllers(ControllersNotMyOwn) of
    [] ->
      % We didn't get a match for match nodes only in other controllers: widen search
      case rendevouz_nodes_from_controllers(randomize_starting_point(Controllers)) of
        [] -> first;
        RendevouzNodes -> RendevouzNodes
      end;
    RendevouzNodes -> RendevouzNodes
  end.

randomize_starting_point(List) when length(List) < 2 -> List;
randomize_starting_point(List) ->
  Length = length(List),
  Num = random:uniform(Length),
  lists:sublist(List, Num + 1, Length - Num) ++ lists:sublist(List, Num). 

rendevouz_nodes_from_controllers(Controllers) ->
  NumToGet = 10,
  case Controllers of
    [] -> [];
    _ ->
      % Try to return nodes with a good spread. They should not all be hosted on the same machine
      Nodes = [{Ip, Ports} || #controller{ip = Ip, ports = Ports} <- Controllers],
      get_diverse_nodes(Nodes, NumToGet)
  end.

get_diverse_nodes(Nodes, NumToGet) -> get_diverse_nodes(Nodes, NumToGet, []).
get_diverse_nodes(_, 0, Acc) -> reverse(Acc);
get_diverse_nodes([],_, Acc) -> reverse(Acc);
get_diverse_nodes([{_Ip, []}|Nodes], NumToGet, Acc) -> get_diverse_nodes(Nodes, NumToGet, Acc);
get_diverse_nodes([{Ip, [Port|Ports]}|Nodes], NumToGet, Acc) -> 
  get_diverse_nodes(Nodes ++ [{Ip, Ports}], NumToGet - 1, [{Ip, Port}|Acc]).

remove_controller(Controller, #state{controllers = Controllers} = State) ->
  Match = [C || C <- Controllers, 
    C#controller.ip =:= Controller#controller.ip, 
    C#controller.port =:= Controller#controller.port],
  State#state{controllers = Controllers -- Match}.

keep_while_alive(Controller) ->
  spawn(fun() -> liveness_checker(Controller, 1000) end).

liveness_checker(Controller, Interval) ->
  receive after Interval -> ok end,
  NextInterval = case Interval < 10000 of
    true -> Interval * 2;
    false -> Interval
  end,
  case hub_tcp:get_update(Controller) of
    dead -> node:remove_controller(Controller);
    empty ->
      % Got an empty response. The node is probably overloaded.
      % Try again.
      liveness_checker(Controller, NextInterval);
    Update -> 
      {pong, node_count, _NumNodes, mode, Mode, ports, Ports, version, Version} = Update,
      node:set_state_for_controller(Controller, {Mode, Ports, Version}),
      liveness_checker(Controller, NextInterval)
  end.

update_controller_state(CC, {Mode, Ports, Version}, #state{controllers = Controllers} = State) ->
  UpdateController = 
    fun(#controller{port = Port, ip = CIp} = C) when Port =:= CC#controller.port, CIp =:= CC#controller.ip ->
          C#controller{mode = Mode, ports = sort(Ports), version = Version};
       (C) -> C
    end,
  NewControllers = [UpdateController(C) || C <- Controllers],
  State#state{controllers = NewControllers}.

-define(MASTER_LOG, "priv/www/dht.log").

logFun(Action, Controller) -> hub_tcp:rpc_logger(Action, Controller).
start_logging(State) -> perform(fun logFun/2, start_logging, State).
stop_logging(State) -> perform(fun logFun/2, stop_logging, State).
clear_logs(State) -> 
  file:delete(?MASTER_LOG),
  perform(fun logFun/2, clear_log, State).
get_logs(#state{controllers = Controllers}) -> 
  spawn(fun() -> perform_get_logs(Controllers) end).

perform_get_logs(Controllers) ->
  F = fun(Controller, IoWriter, RetPid) ->
    spawn(fun() ->
      case hub_tcp:rpc_logger(get_data, Controller) of
        {ok, Data} -> file:write(IoWriter, Data);
        {error, Reason} -> 
          error_logger:error_msg("Couldn't receive log data for reason ~p from controller ~p~n",
            [Reason, Controller])
      end,
      RetPid ! done
    end)
  end,

  {ok, File} = file:open(?MASTER_LOG, [append, delayed_write]),
  [F(C, File, self()) || C <- Controllers],
  close_file_after(length(Controllers), File).

close_file_after(0, File) -> 
  file:close(File),
  node:logs_gotten();
close_file_after(N, File) -> receive _Msg -> close_file_after(N-1, File) end.

upgrade_systems(State) -> perform(fun(_, C) -> hub_tcp:upgrade_system(C) end, undefined, State).
switch_mode_to(Mode, State) -> perform(fun(M, C) -> hub_tcp:switch_mode_to(M, C) end, Mode, State).
ensure_running_n(Count, State) -> slow_perform(fun(N, C) -> hub_tcp:ensure_running_n(N, C) end, Count, State).
start_nodes(Count, State) -> slow_perform(fun(N, C) -> hub_tcp:start_nodes(N, C) end, Count, State).
stop_nodes(Count, State) -> slow_perform(fun(N, C) -> hub_tcp:stop_nodes(N, C) end, Count, State).

perform(Fun, Args, #state{controllers = Controllers}) -> 
  [spawn(fun() -> Fun(Args, C) end) || C <- Controllers].

slow_perform(Fun, Args, #state{controllers = Controllers}) -> 
  [
    % We want to spread out the communication a little bit, so that nodes starting can
    % have more time to join, and we don't overload nodes
    begin
      Time = random:uniform(400),
      receive after Time -> ok end,
      % Now contact the other node
      spawn(fun() -> Fun(Args, C) end) 
    end || C <- Controllers
  ].

% Called to initiate an experimental run
experimental_runner(State) ->
  node:experiment_update("--- Experimental run ---"),
  node:experiment_update("Telling hosts to clear their logs"),
  node:clear_logs(),
  node:experiment_update("Telling hosts to start logging"),
  node:start_logging(),
  % We want to append timestamps to log
  {ok, LogFile} = file:open(?MASTER_LOG, [append]),
  % Phase 1
  node:experiment_update("Telling hosts to run 1 node"),
  node:ensure_running_n_nodes(1),
  node:experiment_update("Waiting 3 minutes"),
  wait_minutes(3),
  node:experiment_update("Starting phase 1"),
  logPhaseStart(LogFile),
  Res = start_experimental_phase(State, LogFile),
  logPhaseDone(LogFile),
  experimental_runner_phase2(State, LogFile, Res).

experimental_runner_phase2(State, LogFile, terminate) -> clean_up_experiment(State, LogFile);
experimental_runner_phase2(State, LogFile, go) ->
  % Phase 2
  node:experiment_update("Telling hosts to run 2 nodes"),
  node:ensure_running_n_nodes(2),
  node:experiment_update("Waiting 3 minutes"),
  wait_minutes(3),
  node:experiment_update("Starting phase 2"),
  logPhaseStart(LogFile),
  Res = start_experimental_phase(State, LogFile),
  logPhaseDone(LogFile),
  experimental_runner_phase3(State, LogFile, Res).

experimental_runner_phase3(State, LogFile, terminate) -> clean_up_experiment(State, LogFile);
experimental_runner_phase3(State, LogFile, go) ->
  % Phase 3
  node:experiment_update("Telling hosts to run 4 nodes"),
  node:ensure_running_n_nodes(4),
  node:experiment_update("Waiting 3 minutes"),
  wait_minutes(3),
  node:experiment_update("Starting phase 3"),
  logPhaseStart(LogFile),
  Res = start_experimental_phase(State, LogFile),
  logPhaseDone(LogFile),
  experimental_runner_phase4(State, LogFile, Res).

experimental_runner_phase4(State, LogFile, terminate) -> clean_up_experiment(State, LogFile);
experimental_runner_phase4(State, LogFile, go) ->
  % Phase 4
  node:experiment_update("Telling hosts to run 8 nodes"),
  node:ensure_running_n_nodes(8),
  node:experiment_update("Waiting 3 minutes"),
  wait_minutes(3),
  node:experiment_update("Starting phase 4"),
  logPhaseStart(LogFile),
  start_experimental_phase(State, LogFile),
  logPhaseDone(LogFile),
  clean_up_experiment(State, LogFile).

clean_up_experiment(_State, LogFile) ->
  % Clean up
  node:experiment_update("--- Experiments done ---"),
  node:experiment_update("Stopping logging"),
  node:stop_logging(),
  node:experiment_update("Getting logs"),
  node:get_logs(),
  node:experiment_update("Shutting down nodes"),
  node:ensure_running_n_nodes(0),
  node:experiment_update("Experiment done. Thanks!"),
  file:close(LogFile).

logPhaseStart(LogFile) -> logPhaseWrite(LogFile, start).
logPhaseDone(LogFile) -> logPhaseWrite(LogFile, done).
logIncreaseRate(LogFile) -> logPhaseWrite(LogFile, increase_rate).

logPhaseWrite(LogFile, Message) ->
  {_, S, Ms} = erlang:now(),
  Time = S * 1000 + trunc(Ms / 1000),
  {NumHosts, NumNodes} = node:get_num_of_hosts_and_nodes(),
  LogEntry = lists:flatten(io_lib:format("ctrl;~p;~p;~p;~p~n", [Message, Time, NumHosts, NumNodes])),
  file:write(LogFile, LogEntry).

start_experimental_phase(State, LogFile) ->
  run_rampup(State),
  run_experimental_phase(State, LogFile).

run_experimental_phase(State, LogFile) ->
  {Hosts, _N} = node:get_num_of_hosts_and_nodes(),
  % Run the experiment until 5% of the nodes fail
  RateIncreaser = spawn(fun() -> perform_increase_rate(State, LogFile) end),
  run_experimental_phase(State, RateIncreaser, trunc(Hosts/20) + 1).

perform_increase_rate(State, LogFile) ->
  receive 
    stop -> ok
  after 10 * 1000 ->
    io:format("Increasing rate~n"),
    logIncreaseRate(LogFile),
    increase_rate(State),
    perform_increase_rate(State, LogFile)
  end.

run_experimental_phase(State, RateIncreaser, 0) ->
  node:experiment_update("Current experimental phase completed"),
  terminate_exp(State, RateIncreaser),
  go; % Tells the experiment that it died of natural cause, and continues to the next phase
run_experimental_phase(State, RateIncreaser, ToGo) ->
  receive 
    stop_current_run ->
      run_experimental_phase(State, RateIncreaser, ToGo - 1);
    killed_by_user ->
      terminate_exp(State, RateIncreaser),
      terminate; % Tells the experiment that the experiment was willfully terminated
    Msg ->
      error_logger:error_msg("Received unknown message in experimental runner: ~p", [Msg]),
      run_experimental_phase(State, RateIncreaser, ToGo)
  after 30*60*1000 ->
    node:experiment_update("Experimental run timed out"),
    stop_experimental_phase(State)
  end.

terminate_exp(State, RateIncreaser) ->
  RateIncreaser ! stop,
  stop_experimental_phase(State).

increase_rate(State) -> perform(fun(_, C) -> hub_tcp:increase_rate(C) end, undefined, State).
run_rampup(State) -> perform(fun(_, C) -> hub_tcp:run_rampup(C) end, undefined, State).
stop_experimental_phase(State) -> perform(fun(_, C) -> hub_tcp:stop_experimental_phase(C) end, undefined, State).
    
wait_minutes(Minutes) ->
  %receive after Minutes * 60 * 10 -> ok end.
  receive after Minutes * 60 * 1000 -> ok end.

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

get_not_me_when_multiple_controllers_but_only_self_controller_has_nodes_test() ->
  Ip = {1,2,3,4},
  Port = 1234,
  Node = #node{
    ip = Ip,
    port = Port
  },
  Controller1 = #controller{
    ip = Ip,
    port = Port,
    mode = chord,
    ports = [1234]
  },
  Controller2 = #controller{
    ip = {2,3,4,5},
    port = Port,
    mode = chord,
    ports = []
  },
  [{Ip, 1234}] = get_not_me(Node, [Controller1, Controller2]).

get_not_me_when_multiple_controllers_but_no_nodes_test() ->
  Ip = {1,2,3,4},
  Port = 1234,
  Node = #node{
    ip = Ip,
    port = Port
  },
  Controller1 = #controller{
    ip = Ip,
    port = Port,
    mode = chord,
    ports = []
  },
  Controller2 = #controller{
    ip = {2,3,4,5},
    port = Port,
    mode = chord,
    ports = []
  },
  first = get_not_me(Node, [Controller1, Controller2]).

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
  ReturnPort7 = 44410,
  ReturnPort8 = 44411,
  ReturnPort9 = 44412,
  ReturnPort10 = 44413,
  ReturnPort11 = 44414,

  Controller = #controller{
    ip = Ip2,
    port = Port2,
    mode = chord,
    ports = [ReturnPort1, ReturnPort2, ReturnPort7, ReturnPort8, ReturnPort9]
  },
  Controller2 = #controller{
    ip = Ip3,
    port = Port3,
    mode = chord,
    ports = [ReturnPort3, ReturnPort4, ReturnPort5, ReturnPort6, ReturnPort10, ReturnPort11]
  },
  ReturnValues = [
    {Ip2, ReturnPort1}, {Ip2, ReturnPort2}, {Ip2, ReturnPort7}, {Ip2, ReturnPort8}, {Ip2, ReturnPort9},
    {Ip3, ReturnPort3}, {Ip3, ReturnPort4}, {Ip3, ReturnPort5}, {Ip3, ReturnPort6}, {Ip3, ReturnPort10}
  ],
  Returned = get_not_me(Node, [Controller, Controller2]),
  [?assert(member(N, ReturnValues)) || N <- Returned].

liveness_checker_test() ->
  C = #controller{port=1, ip = {1,2,3,4}},
  erlymock:start(),
  erlymock:strict(hub_tcp, get_update, [C], [{return, {pong, node_count, 1, mode, chord, ports, [1], version, 1}}]),
  erlymock:strict(node, set_state_for_controller, [C, {chord, [1], 1}], [{return, ok}]),
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
  UpdateController = Controller#controller{mode = pastry, ports = [12,13,14]},
  State = #state{controllers = [UpdateController]},
  NewState = remove_controller(Controller, State),
  ?assertNot(member(UpdateController, NewState#state.controllers)).

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

register_controller_controller_registers_repeatedly_is_ok_test() ->
  State = #state{},
  Controller = #controller{
    ip = {1,2,3,4},
    port = 1234,
    mode = chord,
    ports = []
  },
  NewState = register_controller(Controller, State),
  ?assert(member(Controller, NewState#state.controllers)),
  NewState = register_controller(Controller, NewState).

update_controller_state_test() ->
  Controller = #controller{
    ip = {1,2,3,4},
    port = 1234,
    mode = chord,
    ports = [1,2,3]
  },
  AlreadyUpdatedController = Controller#controller{ports = [1,2,3,4,5,6,7]},
  State = #state{controllers = [AlreadyUpdatedController]},
  #state{controllers = [C]} =
    update_controller_state(Controller, {pastry, [1,4], 1}, State),
  ?assertEqual([1,4], C#controller.ports),
  ?assertEqual(pastry, C#controller.mode),
  ?assertEqual(1, C#controller.version).

switch_mode_to_test() ->
  C1 = #controller{
    ip = {1,2,3,4},
    port = 1234
  },
  C2 = #controller{
    ip = {2,2,3,4},
    port = 2234
  },
  Mode = chord,
  State = #state{controllers = [C1, C2]},
  erlymock:start(),
  erlymock:strict(hub_tcp, switch_mode_to, [Mode, C1], [{return, {ok, ok}}]),
  erlymock:strict(hub_tcp, switch_mode_to, [Mode, C2], [{return, {ok, ok}}]),
  erlymock:replay(), 
  switch_mode_to(Mode, State),
  erlymock:verify().

start_node_test() ->
  C1 = #controller{
    ip = {1,2,3,4},
    port = 1234
  },
  C2 = #controller{
    ip = {2,2,3,4},
    port = 2234
  },
  State = #state{controllers = [C1, C2]},
  erlymock:start(),
  erlymock:strict(hub_tcp, start_nodes, [1, C1], [{return, {ok, ok}}]),
  erlymock:strict(hub_tcp, start_nodes, [1, C2], [{return, {ok, ok}}]),
  erlymock:replay(), 
  start_nodes(1, State),
  erlymock:verify().

stop_node_test() ->
  C1 = #controller{
    ip = {1,2,3,4},
    port = 1234
  },
  C2 = #controller{
    ip = {2,2,3,4},
    port = 2234
  },
  State = #state{controllers = [C1, C2]},
  erlymock:start(),
  erlymock:strict(hub_tcp, stop_nodes, [1, C1], [{return, {ok, ok}}]),
  erlymock:strict(hub_tcp, stop_nodes, [1, C2], [{return, {ok, ok}}]),
  erlymock:replay(), 
  stop_nodes(1, State),
  erlymock:verify().

register_node_in_controllers_first_node_test() ->
  SharedIp = {1,2,3,4},
  C1 = #controller{
    ip = SharedIp,
    port = 1234,
    ports = []
  },
  C2 = #controller{
    ip = {2,2,3,4},
    port = 2234,
    ports = []
  },
  ControllerList = [C1, C2],
  Node = #node{ip = SharedIp, port = 2},
  [#controller{ports = Ports}, _C2N] = register_node_in_controllers(Node, ControllerList),
  % There are no ports in the system. We therefore register
  % this node so that subsequent nodes have someone to randevouz with
  ?assert(member(2, Ports)).

register_node_in_controllers_not_first_node_test() ->
  SharedIp = {1,2,3,4},
  C1 = #controller{
    ip = SharedIp,
    port = 1234,
    ports = [1]
  },
  C2 = #controller{
    ip = {2,2,3,4},
    port = 2234,
    ports = [4,5,6]
  },
  ControllerList = [C1, C2],
  Node = #node{ip = SharedIp, port = 2},
  [#controller{ports = Ports}, _C2N] = register_node_in_controllers(Node, ControllerList),
  % It should not register a port unless there are absolutely no 
  % other ports in the system.
  ?assertNot(member(2, Ports)).

assert_same_items(As, Bs) ->
  [?assert(lists:member(A, Bs)) || A <- As].

randomize_starting_point_test() ->
  List = [a,b,c,d],
  RandomOrder = randomize_starting_point(List),
  ?assertNot(List =:= RandomOrder),
  ?assertEqual(length(List), length(RandomOrder)),
  assert_same_items(List, RandomOrder).

randomize_starting_point_short_lists_test() ->
  ?assertEqual([], randomize_starting_point([])),
  ?assertEqual([a], randomize_starting_point([a])).

-endif.
