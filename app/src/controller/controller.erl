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
    experiment_pid :: pid()
  }).
%% ------------------------------------------------------------------
%% Public API
%% ------------------------------------------------------------------

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
    rereg_with_hub/1,
    % For experiments
    run_rampup/0,
    stop_experimental_phase/0
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
      Spacing = random:uniform(300),
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
    io:format("System upgrade complete!~n")
  end),
  ok.

ensure_n_nodes_running(N) ->
  gen_server:cast(?MODULE, {ensure_n_nodes_running, N}).

run_rampup() ->
  gen_server:cast(?MODULE, run_rampup).

stop_experimental_phase() ->
  gen_server:cast(?MODULE, stop_experimental_phase).

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
      {ok, #controller_state{hub_ping = HomingDevice}};
    {error, Reason} -> 
      error_logger:error_msg("Couldn't register controller because: ~p~n", [Reason]),
      {stop, couldnt_register_node}
  end.

%% Call:
handle_call(get_new_controlling_process, _From, #controller_state{mode = Mode} = State) ->
  {reply, start_node(Mode), State};

handle_call(ping, _From, #controller_state{nodes = Nodes, mode = Mode} = State) ->
  {reply, {pong, node_count, length(Nodes), mode, Mode, ports, all_ports(Nodes), version, ?VERSION}, State};

handle_call(stop, _From, State) ->
  {stop, normal, ok, State}.

%% Casts:
handle_cast(run_rampup, State) ->
  Pid = spawn(fun() -> perform_rampup(State) end),
  {noreply, State#controller_state{experiment_pid = Pid}};

handle_cast(stop_experimental_phase, #controller_state{experiment_pid = Pid} = State) ->
  Pid ! stop,
  {noreply, State#controller_state{experiment_pid = undefined}};

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
  {noreply, NoNodeState#controller_state{mode = NewMode}};

handle_cast({register_node, Node}, #controller_state{mode = Mode, nodes = Nodes} = State) ->
  case length(Nodes) of
    0 -> send_dht_to_friendsearch();
    _ -> ok % Dht should be fine
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

rereg_with_hub(Port) ->
  controller_tcp:register_controller(Port, ?RENDEVOUZ_HOST, ?RENDEVOUZ_PORT).

monitor_node(Node) ->
  spawn(fun() -> perform_monitoring(Node) end).

perform_monitoring(#controller_node{dht_pid = DhtPid} = Node) ->
  receive 
    kill -> kill_node(Node)
  after 1000 -> 
    time_to_check_liveness 
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
  % Killing a chord node:
  chord:stop(DhtPid),
  chord_tcp:stop(TcpPid).

all_ports(Nodes) ->
  [Node#controller_node.port || Node <- Nodes].

% -------------------------------------------------------------------
% Experiment --------------------------------------------------------

-record(exp_info, {
    req_id = 0,
    dht,
    dht_pid,
    history = []
  }).
perform_rampup(#controller_state{nodes = Nodes, mode = Mode}) ->
  Node = hd(Nodes),
  {Type, Pid} = case Mode of
    pastry -> {pastry_app, Node#controller_node.app_pid};
    OtherDht -> {OtherDht, Node#controller_node.dht_pid}
  end,
  io:format("Running experiment on ~p~n", [Type]),
  RunState = #exp_info{dht_pid = Pid, dht = Type},
  SelfPid = self(),
  RunPid = spawn(fun() -> perform_run(RunState, SelfPid) end),
  rampup_runloop(RunPid).

rampup_runloop(RunPid) ->
  receive 
    stop ->
      io:format("Stopping rampup_runloop~n"),
      RunPid ! stop;
    local_stop ->
      controller_tcp:stop_experimental_phase()
  after 10 * 1000 ->
    RunPid ! increase_level,
    rampup_runloop(RunPid)
  end.

perform_run(#exp_info{history = History} = State, ControlPid) ->
  receive
    stop -> ok
  after 0 ->
    receive
      increase_level ->
        io:format("Ramping up~n"),
        % Make additional request
        new_request_if_good(History, State, ControlPid);
      request_success ->
        % Make new request
        NewHistory = update_history(History, success),
        new_request_if_good(NewHistory, State, ControlPid);
      request_failed ->
        NewHistory = update_history(History, failed),
        new_request_if_good(NewHistory, State, ControlPid)
    end
  end.

new_request_if_good(History, State, ControlPid) ->
  case good_history(History) of
    true ->
      perform_run(new_request(State#exp_info{history = History}), ControlPid);
    false ->
      ControlPid ! local_stop
  end.

update_history([], Result) -> [Result];
update_history(History, Result) ->
  Length = length(History),
  case Length >= 100 of
    true -> [Result|lists:sublist(History, 1, Length - 1)];
    false -> [Result|History]
  end.

good_history(History) when length(History) < 10 -> true;
good_history(History) ->
  Failed = [R || R <- History, R =:= failed],
  length(Failed) < 0.25 * length(History).

new_request(#exp_info{req_id = Id, dht = Dht, dht_pid = DhtPid} = State) ->
  ControllingPid = self(),
  Key = utilities:key_for_data({utilities:get_ip(), Id + 1}),
  spawn(fun() ->
    ReturnPid = self(),
    spawn(fun() ->
      Dht:lookup(DhtPid, Key),
      ReturnPid ! ok
    end),
    receive
      ok -> ControllingPid ! request_success
    after 1000 -> ControllingPid ! request_failed
    end
  end),
  State#exp_info{req_id = Id + 1}.

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

good_history_test() ->
  ?assert(good_history([success, success, failed, success, success, success, success, success, success, success])),
  ?assert(good_history([failed, success, failed, success, success, success, success, success, success, success])),
  ?assert(good_history([])),
  ?assertNot(good_history([failed, failed, failed, success, success, success, success, success, success, success])).

-endif.
