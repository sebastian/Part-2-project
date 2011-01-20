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
    register_started_node/3,
    dht_failed_start/1,
    dht_successfully_started/1,
    register_pastry_app/2
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

register_started_node(DhtPid, TcpPid, AppPid) ->
  gen_server:cast(?MODULE, {register_node, {DhtPid, TcpPid, AppPid}}).

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
  {reply, {pong, node_count, length(Nodes), mode, Mode}, State};

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
  {noreply, State#controller_state{nodes = [Data|Nodes]}};

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
      end_init_dht(Mode, TcpPid, DhtPid, DhtCallbackPid)
  end.

end_init_dht(Mode, TcpPid, DhtPid, DhtCallbackPid) ->
  receive 
    dht_success ->
      start_app(Mode, TcpPid, DhtPid, DhtCallbackPid);
    dht_failed_start ->
      io:format("Failed to start dht. Should stop TCP!?~n")
  end.

start_app(chord, TcpPid, DhtPid, _DhtCallbackPid) ->
  controller:register_started_node(DhtPid, TcpPid, undefined);
start_app(pastry, TcpPid, DhtPid, DhtCallbackPid) ->
  receive 
    {reg_app, AppPid} ->
      AppPid ! {dht_pid, DhtPid},
      DhtCallbackPid ! {pastry_app_pid, AppPid}
  end,
  controller:register_started_node(DhtPid, TcpPid, AppPid).


perform_stop_nodes(#controller_state{nodes = Nodes} = State) -> foldl(fun(_N,S) -> stop_node(S) end, State, Nodes).

stop_node(#controller_state{mode = chord, nodes = [{ChordPid, ChordTcpPid, _}|Nodes]} = State) ->
  chord:stop(ChordPid), 
  chord_tcp:stop(ChordTcpPid),
  State#controller_state{nodes = Nodes};
stop_node(#controller_state{mode = pastry, nodes = [{PastryPid, PastryTcpPid, PastryAppPid}|Nodes]} = State) ->
  pastry:stop(PastryPid), 
  pastry_tcp:stop(PastryTcpPid),
  pastry_app:stop(PastryAppPid),
  State#controller_state{nodes = Nodes}.

%% ------------------------------------------------------------------
%% Tests
%% ------------------------------------------------------------------

-ifdef(TEST).

perform_stop_nodes_chord_test() ->
  State = #controller_state{
    mode = chord,
    nodes = [{node1pid, node1tcp, undefined},{node2pid, node2tcp, undefined}]
  },
  erlymock:start(),
  erlymock:o_o(chord, stop, [node1pid], [{return, ok}]),
  erlymock:o_o(chord, stop, [node2pid], [{return, ok}]),
  erlymock:o_o(chord_tcp, stop, [node1tcp], [{return, ok}]),
  erlymock:o_o(chord_tcp, stop, [node2tcp], [{return, ok}]),
  erlymock:replay(), 
  UpdatedState = perform_stop_nodes(State),
  erlymock:verify(),
  ?assertEqual([], UpdatedState#controller_state.nodes).

perform_stop_nodes_pastry_test() ->
  State = #controller_state{
    mode = pastry,
    nodes = [{node1pid, node1tcp, node1app},{node2pid, node2tcp, node2app}]
  },
  erlymock:start(),
  erlymock:o_o(pastry, stop, [node1pid], [{return, ok}]),
  erlymock:o_o(pastry, stop, [node2pid], [{return, ok}]),
  erlymock:o_o(pastry_tcp, stop, [node1tcp], [{return, ok}]),
  erlymock:o_o(pastry_tcp, stop, [node2tcp], [{return, ok}]),
  erlymock:o_o(pastry_app, stop, [node1app], [{return, ok}]),
  erlymock:o_o(pastry_app, stop, [node2app], [{return, ok}]),
  erlymock:replay(), 
  UpdatedState = perform_stop_nodes(State),
  erlymock:verify(),
  ?assertEqual([], UpdatedState#controller_state.nodes).

stop_node_pastry_test() ->
  State = #controller_state{
    mode = pastry,
    nodes = [{node1pid, node1tcp, node1app},{node2pid, node2tcp, node2app}]
  },
  erlymock:start(),
  erlymock:o_o(pastry, stop, [node1pid], [{return, ok}]),
  erlymock:o_o(pastry_tcp, stop, [node1tcp], [{return, ok}]),
  erlymock:o_o(pastry_app, stop, [node1app], [{return, ok}]),
  erlymock:replay(), 
  UpdatedState = stop_node(State),
  erlymock:verify(),
  ?assertEqual([{node2pid, node2tcp, node2app}], UpdatedState#controller_state.nodes).

stop_node_chord_test() ->
  State = #controller_state{
    mode = chord,
    nodes = [{node1pid, node1tcp, undefined},{node2pid, node2tcp, undefined}]
  },
  erlymock:start(),
  erlymock:o_o(chord, stop, [node1pid], [{return, ok}]),
  erlymock:o_o(chord_tcp, stop, [node1tcp], [{return, ok}]),
  erlymock:replay(), 
  UpdatedState = stop_node(State),
  erlymock:verify(),
  ?assertEqual([{node2pid, node2tcp, undefined}], UpdatedState#controller_state.nodes).

-endif.
