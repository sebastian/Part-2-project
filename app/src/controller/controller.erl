-module(controller).
-behaviour(gen_server).

-import(lists, [foldl/3]).
-include("../fs.hrl").

-define(SERVER, ?MODULE).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-record(controller_state, {
    mode = chord,
    nodes = [],
    hub_ping,
    experiment_pid :: pid(),
    ip
  }).
%% ------------------------------------------------------------------
%% Public API
%% ------------------------------------------------------------------

-export([get_dht/0]).

-export([start_link/1, start/1, stop/0]).
-export([
    register_tcp/4,
    register_dht/3,
    register_started_node/1,
    dht_failed_start/1,
    dht_successfully_started/1,
    register_pastry_app/2,
    send_dht_to_friendsearch/0
  ]).
-export([
    start_node/0,
    stop_node/0,
    start_nodes/1,
    stop_nodes/1,
    ensure_n_nodes_running/1,
    switch_mode_to/1,
    get_controlling_process/0,
    ping/0,
    perform_update/0,
    reset_node_count/0,
    rereg_with_hub/1,
    % For experiments
    run_rampup/0,
    increase_rate/0,
    set_rate/1,
    stop_experimental_phase/0,
    output_diagnostics/0
  ]).

%% ------------------------------------------------------------------
%% PRIVATE API Function Exports
%% ------------------------------------------------------------------

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start(Args) ->
  gen_server:start({local, ?SERVER}, ?MODULE, Args, []).

start_link(Args) ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, Args, []).

stop() ->
  gen_server:call(?MODULE, stop).

register_started_node(Node) ->
  gen_server:cast(?MODULE, {register_node, Node}).

start_node() ->
  gen_server:cast(?MODULE, start_node).

stop_node() ->
  gen_server:cast(?MODULE, stop_node).

start_nodes(N) -> 
  spawn(fun() -> [
    begin
      Spacing = random:uniform(3000),
      receive after Spacing -> ok end,
      start_node()
    end || _ <- lists:seq(1, N)
  ] end).

stop_nodes(N) -> 
  [stop_node() || _ <- lists:seq(1, N)].

switch_mode_to(Mode) ->
  gen_server:cast(?MODULE, {new_mode, Mode}).

get_controlling_process() ->
  gen_server:call(?MODULE, get_new_controlling_process).

send_dht_to_friendsearch() ->
  gen_server:cast(?MODULE, send_dht_to_friendsearch).

ping() ->
  gen_server:call(?MODULE, ping).

perform_update() ->
  spawn(fun() ->
    io:format("Upgrading system...~n"),
    io:format(" Downloading new code~n"),
    os:cmd("git pull"),
    io:format("System upgrade complete!~n"),
    io:format("Restarting system!~n"),
    restart_sofos()
  end),
  ok.

reset_node_count() ->
  gen_server:cast(?MODULE, reset_node_count).

ensure_n_nodes_running(N) ->
  gen_server:cast(?MODULE, {ensure_n_nodes_running, N}).

run_rampup() ->
  gen_server:cast(?MODULE, run_rampup).

set_rate(Rate) ->
  gen_server:cast(?MODULE, {set_rate, Rate}).

increase_rate() ->
  gen_server:cast(?MODULE, increase_rate).

stop_experimental_phase() ->
  gen_server:cast(?MODULE, stop_experimental_phase).

get_dht() ->
  gen_server:call(?MODULE, get_dht).

output_diagnostics() ->
  gen_server:cast(?MODULE, output_diagnostics).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(Args) -> 
  Port = proplists:get_value(port, Args),
  case controller_tcp:register_controller(Port, ?RENDEVOUZ_HOST, ?RENDEVOUZ_PORT) of
    {ok, Ip} -> 
      % In case the controller breaks down we want to reregister with it
      {ok, HomingDevice} = timer:apply_interval(3600000, ?MODULE, rereg_with_hub, [Port]),
      logger:set_ip(Ip),
      {ok, #controller_state{ip = Ip, hub_ping = HomingDevice}};
    {error, Reason} -> 
      error_logger:error_msg("Couldn't register controller because: ~p~n", [Reason]),
      {stop, couldnt_register_node}
  end.

%% Call:
handle_call(get_dht, _From, S) ->
  Nodes = S#controller_state.nodes,
  Node = hd(Nodes),
  Pid = Node#controller_node.dht_pid,
  {reply, Pid, S};

handle_call(get_new_controlling_process, _From, #controller_state{mode = Mode} = State) ->
  {reply, start_node(Mode), State};

handle_call(ping, _From, #controller_state{nodes = Nodes, mode = Mode} = State) ->
  {reply, {pong, node_count, length(Nodes), mode, Mode, ports, all_ports(Nodes), version, ?VERSION}, State};

handle_call(stop, _From, State) ->
  {stop, normal, ok, State}.

%% Casts:
handle_cast(output_diagnostics, #controller_state{nodes = Nodes, mode = Dht} = S) ->
  io:format("Diagnostics:~n"),
  [ io:format("   ~p~n", [Dht:output_diagnostics(N#controller_node.dht_pid)]) || N <- Nodes],
  {noreply, S};

handle_cast(reset_node_count, State) ->
  {noreply, State#controller_state{nodes = []}};

handle_cast(run_rampup, State) ->
  Pid = spawn_link(fun() -> perform_rampup(State) end),
  io:format("~nexperimental pid is = ~p~n", [Pid]),
  stop_dht_table_maintenance(State),
  {noreply, State#controller_state{experiment_pid = Pid}};

handle_cast({set_rate, _Rate}, #controller_state{experiment_pid = undefined} = State) ->
  io:format("~n#################### IGNORING set_rate ##################################~n"),
  {noreply, State};
handle_cast({set_rate, Rate}, #controller_state{experiment_pid = Pid} = State) ->
  Pid ! {set_rate, Rate},
  {noreply, State};

handle_cast(increase_rate, #controller_state{experiment_pid = undefined} = State) ->
  io:format("~n#################### IGNORING increase_rate ##################################~n"),
  {noreply, State};
handle_cast(increase_rate, #controller_state{experiment_pid = Pid} = State) ->
  Pid ! increase_rate,
  {noreply, State};

handle_cast(stop_experimental_phase, #controller_state{experiment_pid = undefined} = State) ->
  io:format("~n#################### IGNORING STOP EXPERIMENTAL PHASE ########################~n"),
  {noreply, State};
handle_cast(stop_experimental_phase, #controller_state{experiment_pid = Pid} = State) ->
  Pid ! stop,
  start_dht_table_maintenance(State),
  {noreply, State};

handle_cast({ensure_n_nodes_running, N}, #controller_state{nodes = Nodes} = State) ->
  spawn(fun() ->
    NodeCount = length(Nodes),
    NodeDiff = abs(NodeCount - N),
    case NodeCount > N of
      true -> stop_nodes(NodeDiff);
      false -> start_nodes(NodeDiff)
    end
  end),
  {noreply, State};

handle_cast(start_node, #controller_state{mode = Mode} = State) ->
  spawn(fun() ->
    case Mode of
      chord -> chord_sup:start_node();
      pastry -> pastry_sup:start_node()
    end
  end),
  {noreply, State};

handle_cast(stop_node, State) ->
  {noreply, stop_node(State)};

% When the mode is the same
handle_cast({new_mode, Mode}, #controller_state{mode = Mode} = State) -> {noreply, State};
% When actually changing mode
handle_cast({new_mode, NewMode}, State) when NewMode =:= pastry ; NewMode =:= chord ->
  % Stop all nodes
  NoNodeState = perform_stop_nodes(State),
  datastore_srv:clear(),
  restart_sofos(),
  {noreply, NoNodeState#controller_state{mode = NewMode}};

handle_cast({register_node, Node}, #controller_state{mode = Mode, nodes = Nodes} = State) ->
  case length(Nodes) of
    0 -> send_dht_to_friendsearch();
    _ -> ok % FriendSearch should be fine
  end,
  NodeController = monitor_node(Node),
  % Set mapping in logger for propper logging
  Pid = case Mode of
    chord -> Node#controller_node.dht_pid;
    pastry -> Node#controller_node.app_pid
  end,
  logger:set_mapping(Pid, Node#controller_node.port),
  {noreply, State#controller_state{nodes = [Node#controller_node{controller_pid = NodeController}|Nodes]}};

handle_cast(send_dht_to_friendsearch, #controller_state{mode = Mode, nodes = Nodes} = State) ->
  case Nodes of
    [] -> ok;
    [#controller_node{dht_pid = DhtPid, app_pid = DhtAppPid}|_] ->
      {Type, Pid} = case Mode of
        pastry -> {pastry_app, DhtAppPid};
        OtherDht -> {OtherDht, DhtPid}
      end,
      friendsearch_srv:set_dht({Type, Pid})
  end,
  {noreply, State};

handle_cast(Msg, State) ->
  error_logger:error_msg("received unknown cast: ~p", [Msg]),
  {noreply, State}.

%% Info:
handle_info(_Info, State) ->
  {noreply, State}.

terminate(_Reason, #controller_state{hub_ping = HomingDevice} = State) ->
  % Stop all the nodes
  timer:cancel(HomingDevice),
  perform_stop_nodes(State),
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

start_dht_table_maintenance(State) ->
  start_stop_table_maintenance(State, start_timers).
stop_dht_table_maintenance(State) ->
  start_stop_table_maintenance(State, stop_timers).
start_stop_table_maintenance(#controller_state{mode = Mode, nodes = Nodes}, Action) ->
  [spawn(fun() ->
           % Wait before telling nodes to restart, so they don't all
           % start communicating at the very same time
           receive after trunc(random:uniform() * 1000) -> ok end,
           Mode:Action(N#controller_node.dht_pid)
         end) || N <- Nodes].

restart_sofos() ->
  supervisor:terminate_child(fs_sup, chord_sofo),
  supervisor:terminate_child(fs_sup, pastry_sofo),
  supervisor:restart_child(fs_sup, chord_sofo),
  supervisor:restart_child(fs_sup, pastry_sofo),
  reset_node_count().

rereg_with_hub(Port) ->
  controller_tcp:register_controller(Port, ?RENDEVOUZ_HOST, ?RENDEVOUZ_PORT).

monitor_node(Node) ->
  spawn(fun() -> perform_monitoring(Node) end).

perform_monitoring(#controller_node{dht_pid = DhtPid} = Node) ->
  receive 
    kill -> 
      io:format("Received kill message~n"),
      kill_node(Node)
  after 1000 -> 
    % time_to_check_liveness 
    ok
  end,
  case gen_server:call(DhtPid, ping, 200) of
    pong -> perform_monitoring(Node);
    {timeout, _} -> kill_and_restart(Node)
  end.

kill_and_restart(Node) ->
  kill_node(Node), 
  start_node(),
  ok.

kill_node(#controller_node{dht_pid = DhtPid, tcp_pid = TcpPid, app_pid = AppPid}) when is_pid(AppPid) ->
  % Killing a pastry node:
  pastry:stop(DhtPid),
  pastry_tcp:stop(TcpPid),
  pastry_app:stop(AppPid);
kill_node(#controller_node{dht_pid = DhtPid, tcp_pid = TcpPid}) ->
  io:format("Killing chord node~n"),
  % Killing a chord node:
  chord:stop(DhtPid),
  chord_tcp:stop(TcpPid).

all_ports(Nodes) ->
  [Node#controller_node.port || Node <- Nodes].

% -------------------------------------------------------------------
% Experiment --------------------------------------------------------

-record(exp_info, {
    dht :: pastry_app | chord,
    dht_pids :: [pid()],
    control_pid :: pid(),
    ip
  }).
perform_rampup(#controller_state{ip = Ip, nodes = Nodes, mode = Mode}) ->
  {Type, Pids} = case Mode of
    pastry -> {pastry_app, [Node#controller_node.app_pid || Node <- Nodes]};
    OtherDht -> {OtherDht, [Node#controller_node.dht_pid || Node <- Nodes]}
  end,
  io:format("Running experiment on ~p~n", [Type]),
  SelfPid = self(),
  RunState = #exp_info{ip = Ip, dht_pids = Pids, dht = Type, control_pid = SelfPid},
  InitialRate = 1, % per second
  DeadManCheck = spawn_link(fun() -> dead_man(SelfPid) end),
  % start the rator at slightly offset times so that we don't get
  % all the requests queueing up at exactly the same time
  Wait = random:uniform(1000),
  receive after Wait -> start end,
  RunPid = spawn_link(fun() -> rator(InitialRate, RunState) end),
  experiment_loop(RunPid, DeadManCheck, [], false).

experiment_loop(RunPid, DeadManCheck, History, HasInformedControllerAboutStop) ->
  receive 
    stop ->
      io:format("Stopping experiment_loop~n"),
      RunPid ! stop,
      DeadManCheck ! stop;
    increase_rate ->
      io:format("Received increase rate~n"),
      RunPid ! increase_rate,
      DeadManCheck ! alive,
      experiment_loop(RunPid, DeadManCheck, History, HasInformedControllerAboutStop);
    {set_rate, Rate} ->
      io:format("Received set rate for rate ~p~n", [Rate]),
      RunPid ! {set_rate, Rate},
      DeadManCheck ! alive,
      experiment_loop(RunPid, DeadManCheck, History, HasInformedControllerAboutStop);
    request_success ->
      RunPid ! ended_request,
      io:format("S"),
      NewHistory = update_history(History, success),
      experiment_loop(RunPid, DeadManCheck, NewHistory, HasInformedControllerAboutStop);
    request_failed ->
      RunPid ! ended_request,
      io:format("F"),
      NewHistory = update_history(History, failed),
      case good_history(NewHistory) orelse HasInformedControllerAboutStop of
        true ->
          experiment_loop(RunPid, DeadManCheck, NewHistory, HasInformedControllerAboutStop);
        false ->
          % Tell the controller that we want to stop the experiment
          controller_tcp:stop_experimental_phase(),
          experiment_loop(RunPid, DeadManCheck, NewHistory, true)
      end
  end.

% Prevents the host from staying in experimental mode
% indefinitely in case of it loosing contact with the master
dead_man(Controller) ->
  receive
    alive ->
      dead_man(Controller);
    stop ->
      ok
  after 15 * 60 * 1000 ->
      error_logger:error_msg("Running experiment, but haven't heard from controller. Abort"),
      Controller ! stop,
      controller:stop_experimental_phase()
  end.

rator(Rate, State) ->
  Stopper = spawn(fun() ->
      receive 
        cant_sustain_rate ->
          io:format("Letting controller know that we can't sustain the rate~n"),
          controller_tcp:stop_experimental_phase()
      end
  end),
  rator(Rate, State, 0, Stopper).
rator(Rate, #exp_info{dht_pids = Pids} = State, OutstandingRequests, Stopper) ->
  receive 
    stop -> 
      io:format("Stopping rator with ~p outstanding requests~n", [OutstandingRequests]),
      ok;
    ended_request ->
      rator(Rate, State, OutstandingRequests - 1, Stopper)
  after 0 -> 
    receive
      increase_rate ->
        NewRate = Rate * 2,
        rator(NewRate, State, OutstandingRequests, Stopper);
      {set_rate, NewRate} ->
        rator(NewRate, State, OutstandingRequests, Stopper)
    after trunc(1000 / Rate) ->
      % We allow for two times the rate, because we want
      % to allow the requests to take up to two seconds.
      case OutstandingRequests > (trunc(Rate*5.1) + 5) of
        true ->
          io:format("~nHas too many outstanding requests: ~p~n", [OutstandingRequests]),
          Stopper ! cant_sustain_rate;
        false -> good
      end,
      % Get the next DhtPid
      NextPid = hd(Pids),
      RestPids = tl(Pids),
      UpdatedState = State#exp_info{dht_pids = RestPids ++ [NextPid]},
      new_request(State, NextPid),
      rator(Rate, UpdatedState, OutstandingRequests+1, Stopper)
    end
  end.

new_request(#exp_info{ip = Ip, dht = Dht, control_pid = CtrlPid}, DhtPid) ->
  io:format("n"),
  spawn_link(fun() ->
    Key = utilities:key_for_data({Ip, now()}),
    ReturnPid = self(),
    spawn_link(fun() ->
      try 
        Dht:lookup(DhtPid, Key),
        ReturnPid ! ok
      catch Error:Reason ->
        io:format("Lookup failed: ~p:~p", [Error, Reason]),
        CtrlPid ! request_failed
      end
    end),
    receive
      ok -> 
        logger:log_success(Key),
        CtrlPid ! request_success
    % Allow requests to take up to a certain amount of time before timing out
    after 5000 -> 
        io:format("request timed out~n"),
        CtrlPid ! request_failed
    end
  end).

update_history([], Result) -> [Result];
update_history(History, Result) ->
  Length = length(History),
  case Length >= 50 of
    true -> [Result|lists:sublist(History, 1, Length - 1)];
    false -> [Result|History]
  end.

good_history(History) when length(History) < 40 -> true;
good_history(History) ->
  Failed = [R || R <- History, R =:= failed],
  length(Failed) < 0.25 * length(History).

% -------------------------------------------------------------------
% Start node statemachine -------------------------------------------
register_tcp(ControllingProcess, TcpPid, TcpCallbackPid, Port) ->
  ControllingProcess ! {reg_tcp, TcpPid, TcpCallbackPid, Port}.

register_dht(ControllingProcess, DhtPid, DhtCallbackPid) ->
  ControllingProcess ! {reg_dht, DhtPid, DhtCallbackPid}.

dht_failed_start(ControllingProcess) ->
  ControllingProcess ! dht_failed_start.

dht_successfully_started(ControllingProcess) ->
  ControllingProcess ! dht_success.

register_pastry_app(ControllingProcess, AppPid) ->
  ControllingProcess ! {reg_app, AppPid}.

start_node(Mode) ->
  spawn(fun() -> start_tcp(Mode) end).

start_tcp(Mode) ->
  Node = #controller_node{},
  receive 
    {reg_tcp, TcpPid, TcpCallbackPid, Port} ->
      init_dht(Mode, Node#controller_node{tcp_pid = TcpPid, port = Port}, TcpCallbackPid)
  end.

init_dht(Mode, Node, TcpCallbackPid) ->
  receive
    {reg_dht, DhtPid, DhtCallbackPid} ->
      DhtPid ! {port, Node#controller_node.port},
      TcpCallbackPid ! {dht_pid, DhtPid},
      end_init_dht(Mode, Node#controller_node{dht_pid = DhtPid}, DhtCallbackPid)
  end.

end_init_dht(Mode, Node, DhtCallbackPid) ->
  receive 
    dht_success ->
      start_app(Mode, Node, DhtCallbackPid);
    dht_failed_start ->
      TcpPid = Node#controller_node.tcp_pid,
      case Mode of
        pastry -> 
          pastry_tcp:stop(TcpPid);
        chord ->
          chord_tcp:stop(TcpPid)
      end
  end.

start_app(chord, Node, _DhtCallbackPid) ->
  controller:register_started_node(Node);
start_app(pastry, Node, DhtCallbackPid) ->
  receive 
    {reg_app, AppPid} ->
      AppPid ! {dht_pid, Node#controller_node.dht_pid},
      DhtCallbackPid ! {pastry_app_pid, AppPid}
  end,
  controller:register_started_node(Node#controller_node{app_pid = AppPid}).

perform_stop_nodes(#controller_state{nodes = Nodes} = State) -> 
  [Controller ! kill || #controller_node{controller_pid = Controller} <- Nodes],
  State#controller_state{nodes = []}.

stop_node(#controller_state{nodes = []} = State) -> State;
stop_node(#controller_state{nodes = [#controller_node{controller_pid = NodeController}|Nodes]} = State) ->
  NodeController ! kill,
  State#controller_state{nodes = Nodes}.

%% ------------------------------------------------------------------
%% Tests
%% ------------------------------------------------------------------

-ifdef(TEST).

cp(PidName) ->
  list_to_pid(lists:flatten(io_lib:format("<0.~p>", [PidName]))).
cn1pastry() ->
  Node1Pid = cp(1.1),
  Node1Tcp = cp(1.2),
  Node1App = cp(1.3),
  Node = #controller_node{
    dht_pid = Node1Pid, 
    tcp_pid = Node1Tcp,
    app_pid = Node1App, 
    port = 1000
  },
  Node1Controller = monitor_node(Node),
  Node#controller_node{controller_pid = Node1Controller}.
cn2pastry() ->
  Node2Pid = cp(2.1),
  Node2Tcp = cp(2.2),
  Node2App = cp(2.3),
  Node = #controller_node{
    dht_pid = Node2Pid, 
    tcp_pid = Node2Tcp,
    app_pid = Node2App, 
    port = 2000
  },
  Node2Controller = monitor_node(Node),
  Node#controller_node{controller_pid = Node2Controller}.
cn1chord() ->
  Node1Pid = cp(1.1),
  Node1Tcp = cp(1.2),
  Node = #controller_node{
    dht_pid = Node1Pid, 
    tcp_pid = Node1Tcp,
    port = 1000
  },
  Node1Controller = monitor_node(Node),
  Node#controller_node{controller_pid = Node1Controller}.
cn2chord() ->
  Node2Pid = cp(2.1),
  Node2Tcp = cp(2.2),
  Node = #controller_node{
    dht_pid = Node2Pid, 
    tcp_pid = Node2Tcp,
    port = 2000
  },
  Node2Controller = monitor_node(Node),
  Node#controller_node{controller_pid = Node2Controller}.

perform_stop_nodes_chord_test() ->
  Node1 = cn1chord(),
  Node2 = cn2chord(),
  State = #controller_state{
    mode = chord,
    nodes = [Node1, Node2]
  },
  erlymock:start(),
  erlymock:o_o(chord, stop, [Node1#controller_node.dht_pid], [{return, ok}]),
  erlymock:o_o(chord, stop, [Node2#controller_node.dht_pid], [{return, ok}]),
  erlymock:o_o(chord_tcp, stop, [Node1#controller_node.tcp_pid], [{return, ok}]),
  erlymock:o_o(chord_tcp, stop, [Node2#controller_node.tcp_pid], [{return, ok}]),
  erlymock:replay(), 
  UpdatedState = perform_stop_nodes(State),
  erlymock:verify(),
  ?assertEqual([], UpdatedState#controller_state.nodes).

perform_stop_nodes_pastry_test() ->
  Node1 = cn1pastry(),
  Node2 = cn2pastry(),
  State = #controller_state{
    mode = pastry,
    nodes = [Node1, Node2]
  },
  erlymock:start(),
  erlymock:o_o(pastry, stop, [Node1#controller_node.dht_pid], [{return, ok}]),
  erlymock:o_o(pastry, stop, [Node2#controller_node.dht_pid], [{return, ok}]),
  erlymock:o_o(pastry_tcp, stop, [Node1#controller_node.tcp_pid], [{return, ok}]),
  erlymock:o_o(pastry_tcp, stop, [Node2#controller_node.tcp_pid], [{return, ok}]),
  erlymock:o_o(pastry_app, stop, [Node1#controller_node.app_pid], [{return, ok}]),
  erlymock:o_o(pastry_app, stop, [Node2#controller_node.app_pid], [{return, ok}]),
  erlymock:replay(), 
  UpdatedState = perform_stop_nodes(State),
  erlymock:verify(),
  ?assertEqual([], UpdatedState#controller_state.nodes).

stop_node_pastry_test() ->
  Node1 = cn1pastry(),
  Node2 = cn2pastry(),
  State = #controller_state{
    mode = pastry,
    nodes = [Node1,Node2]
  },
  erlymock:start(),
  erlymock:o_o(pastry, stop, [Node1#controller_node.dht_pid], [{return, ok}]),
  erlymock:o_o(pastry_tcp, stop, [Node1#controller_node.tcp_pid], [{return, ok}]),
  erlymock:o_o(pastry_app, stop, [Node1#controller_node.app_pid], [{return, ok}]),
  erlymock:replay(), 
  UpdatedState = stop_node(State),
  erlymock:verify(),
  ?assertEqual([Node2], UpdatedState#controller_state.nodes),
  % For good measure, kill the other monitor as well
  Node2#controller_node.controller_pid ! kill.

stop_node_chord_test() ->
  Node1 = cn1chord(),
  Node2 = cn2chord(),
  State = #controller_state{
    mode = chord,
    nodes = [Node1,Node2]
  },
  erlymock:start(),
  erlymock:o_o(chord, stop, [Node1#controller_node.dht_pid], [{return, ok}]),
  erlymock:o_o(chord_tcp, stop, [Node1#controller_node.tcp_pid], [{return, ok}]),
  erlymock:replay(), 
  UpdatedState = stop_node(State),
  erlymock:verify(),
  ?assertEqual([Node2], UpdatedState#controller_state.nodes),
  % For good measure, kill the other monitor as well
  Node2#controller_node.controller_pid ! kill.

stop_node_no_nodes_test() ->
  State = #controller_state{
    mode = chord,
    nodes = []
  },
  erlymock:start(),
  erlymock:replay(), 
  State = stop_node(State),
  erlymock:verify().

all_ports_test() ->
  Node1 = cn1pastry(),
  Node2 = cn2pastry(),
  Nodes = [Node1, Node2],
  ?assertEqual([1000, 2000], all_ports(Nodes)).

update_history_test() ->
  Hist = [],
  UpdatedHist = update_history(Hist, success),
  ?assertEqual([success], UpdatedHist),
  UpdatedHist2 = update_history(UpdatedHist, success),
  ?assertEqual([success, success], UpdatedHist2),
  FullHistory = lists:seq(1,100),
  ?assertEqual(100, length(FullHistory)),
  UpdatedFullHistory = update_history(FullHistory, failed),
  ?assertEqual(100, length(UpdatedFullHistory)),
  ?assertEqual(failed, hd(UpdatedFullHistory)).

create_fail_rate(Percent) ->
  create_fail_rate(40- trunc(Percent * 0.4), trunc(Percent * 0.4), []).
create_fail_rate(0, 0, Acc) -> Acc;
create_fail_rate(0, N, Acc) -> create_fail_rate(0, N-1, [failed|Acc]);
create_fail_rate(N, M, Acc) -> create_fail_rate(N-1, M, [success|Acc]).
good_history_test() ->
  ?assert(good_history(create_fail_rate(24))),
  ?assert(good_history(create_fail_rate(20))),
  ?assert(good_history(create_fail_rate(0))),
  ?assert(good_history([])),
  ?assertNot(good_history(create_fail_rate(25))),
  ?assertNot(good_history(create_fail_rate(26))),
  ?assertNot(good_history(create_fail_rate(100))).

-endif.
