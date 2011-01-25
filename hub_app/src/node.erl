-module(node).
-behaviour(gen_server).

-include("records.hrl").

-import(lists, [foldl/3]).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-define(SERVER, ?MODULE).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/1, start/0, stop/0]).
-export([clear/0]).
% For performing rendevouz
-export([
    rendevouz_node/1,
    register_controller/1,
    remove_controller/1,
    set_state_for_controller/2
  ]).
% For front end
-export([
    live_nodes/0,
    switch_mode_to/1,
    start_nodes/1,
    stop_nodes/1
  ]).
% For logging
-export([
    start_logging/0,
    stop_logging/0,
    clear_logs/0,
    get_logs/0
  ]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

% -------------------------------------------------------------------
% General -----------------------------------------------------------

start() ->
  gen_server:start({local, ?SERVER}, ?MODULE, [], []).

start_link(Args) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Args, []).

stop() ->
  gen_server:call(?MODULE, stop).

clear() ->
  gen_server:call(?MODULE, clear).

remove_controller(Node) ->
  gen_server:cast(?MODULE, {remove_controller, Node}).

set_state_for_controller(Controller, State) ->
  gen_server:cast(?MODULE, {set_state_for_controller, Controller, State}).

% -------------------------------------------------------------------
% Controller --------------------------------------------------------

register_controller(Node) ->
  gen_server:cast(?MODULE, {register_controller, Node}).

% -------------------------------------------------------------------
% Rendevouz nodes (Chord and Pastry) --------------------------------

rendevouz_node(Node) ->
  gen_server:call(?MODULE, {rendevouz_node, Node}).

% -------------------------------------------------------------------
% Logging -----------------------------------------------------------

start_logging() ->
  gen_server:call(?MODULE, start_logging).

stop_logging() ->
  gen_server:call(?MODULE, stop_logging).

clear_logs() ->
  gen_server:call(?MODULE, clear_logs).

get_logs() ->
  gen_server:call(?MODULE, get_logs).

% -------------------------------------------------------------------
% Frontend ----------------------------------------------------------

live_nodes() ->
  gen_server:call(?MODULE, live_nodes).

switch_mode_to(Mode) ->
  gen_server:cast(?MODULE, {switch_mode_to, Mode}).

start_nodes(N) ->
  gen_server:cast(?MODULE, {start_nodes, N}).

stop_nodes(N) ->
  gen_server:cast(?MODULE, {stop_nodes, N}).


%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(_Args) -> 
  {ok, #state{}}.

%% Call:
handle_call(start_logging, _From, State) ->
  node_core:start_logging(State),
  {reply, ok, State};

handle_call(stop_logging, _From, State) ->
  node_core:stop_logging(State),
  {reply, ok, State};

handle_call(clear_logs, _From, State) ->
  node_core:clear_logs(State),
  {reply, ok, State};

handle_call(get_logs, _From, State) ->
  node_core:get_logs(State),
  {reply, ok, State#state{log_status = getting_logs}};

handle_call(live_nodes, _From, #state{controllers = Controllers, log_status = LogStatus} = State) ->
  {reply, live_state(Controllers, LogStatus), State};

handle_call(stop, _From, State) ->
  {stop, normal, ok, State};

handle_call({rendevouz_node, Node}, _From, State) ->
  {Reply, NewState} = node_core:register_node(Node, State),
  {reply, Reply, NewState};

handle_call(clear, _From, _State) ->
  % WARNING! NOT GOOD! SHOULD STOP LIVENESS CHECKERS!
  {reply, ok, #state{}}.

%% Casts:
handle_cast(logs_gotten, State) ->
  {noreply, State#state{log_status = logs_aquired}};

handle_cast({remove_controller, Controller}, State) ->
  {noreply, node_core:remove_controller(Controller, State)};

handle_cast({set_state_for_controller, Controller, ControllerState}, State) ->
  {noreply, node_core:update_controller_state(Controller, ControllerState, State)};

handle_cast({register_controller, Node}, State) ->
  {noreply, node_core:register_controller(Node, State)};

handle_cast({start_nodes, Count}, State) ->
  node_core:start_nodes(Count, State),
  {noreply, State};

handle_cast({stop_nodes, Count}, State) ->
  node_core:stop_nodes(Count, State),
  {noreply, State};

handle_cast({switch_mode_to, Mode}, State) ->
  node_core:switch_mode_to(Mode, State),
  {noreply, State};

handle_cast(_Msg, State) ->
  {noreply, State}.

%% Info:
handle_info(_Info, State) ->
  {noreply, State}.

terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

live_state(Controllers, LogStatus) ->
  {struct, [
      {<<"controllers">>, encode_controllers(Controllers)},
      {<<"log_status">>, LogStatus}
    ]}.

controllers_as_struct(Controllers) ->
  {struct,[{<<"controllers">>, encode_controllers(Controllers)}]}.

encode_controllers(Controllers) -> 
  [{struct, [
      {<<"ip">>, ip_to_binary(C#controller.ip)}, 
      {<<"port">>, code_port(C#controller.port)},
      {<<"mode">>, C#controller.mode},
      {<<"nodes">>, C#controller.ports}
    ]} || C <- Controllers].
ip_to_binary({A,B,C,D}) -> list_to_binary(lists:flatten(io_lib:format("~p.~p.~p.~p", [A,B,C,D]))).
code_port(Port) -> list_to_bitstring(integer_to_list(Port)).


-ifdef(TEST).
-endif.
