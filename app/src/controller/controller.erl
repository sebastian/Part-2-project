-module(controller).
-behaviour(gen_server).

-import(lists, [foldl/3]).

-define(SERVER, ?MODULE).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-record(controller_state, {
    mode = chord,
    nodes = []
  }).
%% ------------------------------------------------------------------
%% Public API
%% ------------------------------------------------------------------

-export([start_link/1, start/1, stop/0]).
-export([
    register_tcp/4,
    register_dht/3,
    register_started_node/4,
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
    switch_mode_to/1,
    get_controlling_process/0,
    ping/0
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

register_started_node(DhtPid, TcpPid, AppPid, Port) ->
  gen_server:cast(?MODULE, {register_node, {DhtPid, TcpPid, AppPid, Port}}).

start_node() ->
  gen_server:cast(?MODULE, start_node).

start_nodes(N) ->
  [start_node() || _ <- lists:seq(1, N)].

stop_node() ->
  gen_server:cast(?MODULE, stop_node).

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

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(Args) -> 
  Port = proplists:get_value(port, Args),
  RendevouzHost = "hub.probsteide.com",
  RendevouzPort = "6001",
  case controller:register_controller(Port, RendevouzHost, RendevouzPort) of
    {ok, _} -> {ok, #controller_state{}};
    {error, _} -> {stop, couldnt_register_node}
  end.

%% Call:
handle_call(get_new_controlling_process, _From, #controller_state{mode = Mode} = State) ->
  {reply, start_node(Mode), State};

handle_call(ping, _From, #controller_state{nodes = Nodes, mode = Mode} = State) ->
  {reply, {pong, node_count, length(Nodes), mode, Mode, ports, all_ports(Nodes)}, State};

handle_call(stop, _From, State) ->
  {stop, normal, ok, State}.

%% Casts:
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

handle_cast({register_node, Data}, #controller_state{nodes = Nodes} = State) ->
  case length(Nodes) of
    0 -> send_dht_to_friendsearch();
    _ -> ok % Dht should be fine
  end,
  NodeController = monitor_node(Data),
  {noreply, State#controller_state{nodes = [{Data, NodeController}|Nodes]}};

handle_cast(send_dht_to_friendsearch, #controller_state{nodes = [{DhtPid, _, DhtAppPid}|_], mode = Mode} = State) ->
  % There were previously no node, but now there is, so tell friend search
  {Type, Pid} = case Mode of
    pastry -> {pastry_app, DhtAppPid};
    OtherDht -> {OtherDht, DhtPid}
  end,
  friendsearch_srv:set_dht({Type, Pid}),
  {noreply, State};

handle_cast(Msg, State) ->
  error_logger:error_msg("received unknown cast: ~p", [Msg]),
  {noreply, State}.

%% Info:
handle_info(_Info, State) ->
  {noreply, State}.

terminate(_Reason, State) ->
  % Stop all the nodes
  perform_stop_nodes(State),
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

monitor_node(Node) ->
  spawn(fun() -> perform_monitoring(Node) end).

perform_monitoring({DhtPid, _, _, _} = Node) ->
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

kill_node({DhtPid, TcpPid, AppPid, _Port}) when is_pid(AppPid) ->
  % Killing a pastry node:
  pastry:stop(DhtPid),
  pastry_tcp:stop(TcpPid),
  pastry_app:stop(AppPid);
kill_node({DhtPid, TcpPid, _AppPid, _Port}) ->
  % Killing a chord node:
  chord:stop(DhtPid),
  chord_tcp:stop(TcpPid).

all_ports(Nodes) ->
  [Port || {_,_,_,Port} <- Nodes].

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
  receive 
    {reg_tcp, TcpPid, TcpCallbackPid, Port} ->
      init_dht(Mode, TcpPid, TcpCallbackPid, Port)
  end.

init_dht(Mode, TcpPid, TcpCallbackPid, Port) ->
  receive
    {reg_dht, DhtPid, DhtCallbackPid} ->
      DhtPid ! {port, Port},
      TcpCallbackPid ! {dht_pid, DhtPid},
      end_init_dht(Mode, TcpPid, DhtPid, DhtCallbackPid, Port)
  end.

end_init_dht(Mode, TcpPid, DhtPid, DhtCallbackPid, Port) ->
  receive 
    dht_success ->
      start_app(Mode, TcpPid, DhtPid, DhtCallbackPid, Port);
    dht_failed_start ->
      io:format("Failed to start dht. Should stop TCP!?~n")
  end.

start_app(chord, TcpPid, DhtPid, _DhtCallbackPid, Port) ->
  controller:register_started_node(DhtPid, TcpPid, undefined, Port);
start_app(pastry, TcpPid, DhtPid, DhtCallbackPid, Port) ->
  receive 
    {reg_app, AppPid} ->
      AppPid ! {dht_pid, DhtPid},
      DhtCallbackPid ! {pastry_app_pid, AppPid}
  end,
  controller:register_started_node(DhtPid, TcpPid, AppPid, Port).

perform_stop_nodes(#controller_state{nodes = Nodes} = State) -> foldl(fun(_N,S) -> stop_node(S) end, State, Nodes).

stop_node(#controller_state{nodes = [{_Node, NodeController}|Nodes]} = State) ->
  NodeController ! kill,
  State#controller_state{nodes = Nodes}.

%% ------------------------------------------------------------------
%% Tests
%% ------------------------------------------------------------------

-ifdef(TEST).

perform_stop_nodes_chord_test() ->
  Node1Pid = cp(1.1),
  Node1Tcp = cp(1.2),
  Node2Pid = cp(2.1),
  Node2Tcp = cp(2.2),
  Node1 = {Node1Pid, Node1Tcp, undefined, port},
  Node2 = {Node2Pid, Node2Tcp, undefined, port},
  Node1Controller = monitor_node(Node1),
  Node2Controller = monitor_node(Node2),
  State = #controller_state{
    mode = chord,
    nodes = [{Node1, Node1Controller},{Node2, Node2Controller}]
  },
  erlymock:start(),
  erlymock:o_o(chord, stop, [Node1Pid], [{return, ok}]),
  erlymock:o_o(chord, stop, [Node2Pid], [{return, ok}]),
  erlymock:o_o(chord_tcp, stop, [Node1Tcp], [{return, ok}]),
  erlymock:o_o(chord_tcp, stop, [Node2Tcp], [{return, ok}]),
  erlymock:replay(), 
  UpdatedState = perform_stop_nodes(State),
  erlymock:verify(),
  ?assertEqual([], UpdatedState#controller_state.nodes).

cp(PidName) ->
  list_to_pid(lists:flatten(io_lib:format("<0.~p>", [PidName]))).

perform_stop_nodes_pastry_test() ->
  Node1Pid = cp(1.1),
  Node1Tcp = cp(1.2),
  Node2Pid = cp(2.1),
  Node2Tcp = cp(2.2),
  Node1App = cp(1.3),
  Node2App = cp(2.3),
  Node1 = {Node1Pid, Node1Tcp, Node1App, port},
  Node2 = {Node2Pid, Node2Tcp, Node2App, port},
  Node1Controller = monitor_node(Node1),
  Node2Controller = monitor_node(Node2),
  State = #controller_state{
    mode = pastry,
    nodes = [{Node1, Node1Controller},{Node2, Node2Controller}]
  },
  erlymock:start(),
  erlymock:o_o(pastry, stop, [Node1Pid], [{return, ok}]),
  erlymock:o_o(pastry, stop, [Node2Pid], [{return, ok}]),
  erlymock:o_o(pastry_tcp, stop, [Node1Tcp], [{return, ok}]),
  erlymock:o_o(pastry_tcp, stop, [Node2Tcp], [{return, ok}]),
  erlymock:o_o(pastry_app, stop, [Node1App], [{return, ok}]),
  erlymock:o_o(pastry_app, stop, [Node2App], [{return, ok}]),
  erlymock:replay(), 
  UpdatedState = perform_stop_nodes(State),
  erlymock:verify(),
  ?assertEqual([], UpdatedState#controller_state.nodes).

stop_node_pastry_test() ->
  Node1Pid = cp(1.1),
  Node1Tcp = cp(1.2),
  Node2Pid = cp(2.1),
  Node2Tcp = cp(2.2),
  Node1App = cp(1.3),
  Node2App = cp(2.3),
  Node1 = {Node1Pid, Node1Tcp, Node1App, port},
  Node2 = {Node2Pid, Node2Tcp, Node2App, port},
  Node1Controller = monitor_node(Node1),
  Node2Controller = monitor_node(Node2),
  State = #controller_state{
    mode = pastry,
    nodes = [{Node1, Node1Controller},{Node2, Node2Controller}]
  },
  erlymock:start(),
  erlymock:o_o(pastry, stop, [Node1Pid], [{return, ok}]),
  erlymock:o_o(pastry_tcp, stop, [Node1Tcp], [{return, ok}]),
  erlymock:o_o(pastry_app, stop, [Node1App], [{return, ok}]),
  erlymock:replay(), 
  UpdatedState = stop_node(State),
  erlymock:verify(),
  ?assertEqual([{Node2, Node2Controller}], UpdatedState#controller_state.nodes),
  % For good measure, kill the other monitor as well
  Node2Controller ! kill.

stop_node_chord_test() ->
  Node1Pid = cp(1.1),
  Node1Tcp = cp(1.2),
  Node2Pid = cp(2.1),
  Node2Tcp = cp(2.2),
  Node1 = {Node1Pid, Node1Tcp, undefined, port},
  Node2 = {Node2Pid, Node2Tcp, undefined, port},
  Node1Controller = monitor_node(Node1),
  Node2Controller = monitor_node(Node2),
  State = #controller_state{
    mode = chord,
    nodes = [{Node1, Node1Controller},{Node2, Node2Controller}]
  },
  erlymock:start(),
  erlymock:o_o(chord, stop, [Node1Pid], [{return, ok}]),
  erlymock:o_o(chord_tcp, stop, [Node1Tcp], [{return, ok}]),
  erlymock:replay(), 
  UpdatedState = stop_node(State),
  erlymock:verify(),
  ?assertEqual([{Node2, Node2Controller}], UpdatedState#controller_state.nodes),
  % For good measure, kill the other monitor as well
  Node2Controller ! kill.

all_ports_test() ->
  Nodes = [{dhtPid1, tcpPid1, appPid1, port1},{dhtPid2, tcpPid2, appPid2, port2}],
  ?assertEqual([port1, port2], all_ports(Nodes)).

-endif.
