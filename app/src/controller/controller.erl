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
    dht_failed_start/1
  ]).
-export([
    start_node/0,
    stop_node/0,
    switch_mode_to/1
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

stop_node() ->
  gen_server:cast(?MODULE, stop_node).

switch_mode_to(Mode) ->
  gen_server:cast(?MODULE, {new_mode, Mode}).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(_Args) -> 
  {ok, #controller_state{}}.

%% Call:
handle_call(stop, _From, State) ->
  {stop, normal, ok, State}.

%% Casts:
handle_cast(start_node, #controller_state{mode = Mode} = State) ->
  start_node(Mode),
  {noreply, State};

handle_cast(stop_node, State) ->
  {noreply, stop_node(State)};

% When the mode is the same
handle_cast({new_mode, Mode}, #controller_state{mode = Mode} = State) -> {noreply, State};
% When actually changing mode
handle_cast({new_mode, NewMode}, State) ->
  % Stop all nodes
  NoNodeState = stop_nodes(State),
  {noreply, NoNodeState#controller_state{mode = NewMode}};

handle_cast({register_node, Data}, #controller_state{nodes = Nodes} = State) ->
  io:format("Registered node with data: ~p~n", [Data]),
  {noreply, State#controller_state{nodes = [Data|Nodes]}};

handle_cast(Msg, State) ->
  error_logger:error_msg("received unknown cast: ~p", [Msg]),
  {noreply, State}.

%% Info:
handle_info(_Info, State) ->
  {noreply, State}.

terminate(_Reason, State) ->
  % Stop all the nodes
  stop_nodes(State),
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

start_node(Mode) ->
  spawn(fun() -> start_tcp(Mode) end).

start_tcp(Mode) ->
  case Mode of
    chord ->
      chord_tcp:start_link_unnamed([{port,4000}, {controllingProcess, self()}]);
    pastry ->
      io:format("Pastry TCP not implemented yet~n")
  end,
  receive 
    {reg_tcp, TcpPid, TcpCallbackPid, Port} ->
      start_dht(Mode, TcpPid, TcpCallbackPid, Port)
  end.

start_dht(Mode, TcpPid, TcpCallbackPid, Port) ->
  case Mode of
    chord ->
      chord:start_link([{port,Port}, {controllingProcess, self()}]);
    pastry ->
      io:format("Pastry not implemented yet~n")
  end,
  receive
    {reg_dht, DhtPid, DhtCallbackPid} ->
      TcpCallbackPid ! {dht_pid, DhtPid},
      start_app(Mode, TcpPid, DhtPid, DhtCallbackPid);
    dht_failed_start ->
      io:format("Failed to start dht. Should stop TCP!?~n")
  end.

start_app(chord, TcpPid, DhtPid, _DhtCallbackPid) ->
  controller:register_started_node(TcpPid, DhtPid, undefined);
start_app(pastry, _TcpPid, _DhtPid, _DhtCallbackPid) ->
  io:format("Pastry start app not yet implemented~n").


stop_nodes(#controller_state{nodes = Nodes} = State) -> foldl(fun(_N,S) -> stop_node(S) end, State, Nodes).

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

stop_nodes_chord_test() ->
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
  UpdatedState = stop_nodes(State),
  erlymock:verify(),
  ?assertEqual([], UpdatedState#controller_state.nodes).

stop_nodes_pastry_test() ->
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
  UpdatedState = stop_nodes(State),
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
