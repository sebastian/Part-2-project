-module(node).
-behaviour(gen_server).

-include("records.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-define(SERVER, ?MODULE).
-define(CHECK_LIVENESS, 10000).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/1, start/0, stop/0]).
-export([clear/0]).
% For performing rendevouz
-export([
    rendevouz_chord/1,
    rendevouz_pastry/1,
    check_liveness/0,
    remove_node/1
  ]).
% For front end
-export([
    live_nodes/0
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

check_liveness() ->
  io:format("Check liveness method called. Calling server~n"),
  gen_server:cast(?MODULE, check_liveness).

remove_node(Node) ->
  gen_server:cast(?MODULE, {remove_node, Node}).

% -------------------------------------------------------------------
% Chord -------------------------------------------------------------

rendevouz_chord(Node) ->
  gen_server:call(?MODULE, {rendevouz_chord, Node}).

% -------------------------------------------------------------------
% Pastry ------------------------------------------------------------

rendevouz_pastry(Node) ->
  gen_server:call(?MODULE, {rendevouz_pastry, Node}).

% -------------------------------------------------------------------
% Frontend ----------------------------------------------------------

live_nodes() ->
  nodes_as_struct(gen_server:call(?MODULE, live_nodes)).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(_Args) -> 
  {ok, TimerRef} = timer:apply_interval(?CHECK_LIVENESS, ?MODULE, check_liveness, []),
  {ok, #state{timerRef = TimerRef}}.

%% Call:
handle_call(live_nodes, _From, #state{chord_nodes = CN, pastry_nodes = PN} = State) ->
  {reply, {CN, PN}, State};

handle_call(stop, _From, State) ->
  {stop, normal, ok, State};

handle_call({rendevouz_chord, Node}, _From, State) ->
  {Answer, NewState} = node_core:register_chord(Node, State),
  {reply, Answer, NewState};

handle_call({rendevouz_pastry, Node}, _From, State) ->
  {Answer, NewState} = node_core:register_pastry(Node, State),
  {reply, Answer, NewState};

handle_call(clear, _From, _State) ->
  {reply, ok, #state{}}.

%% Casts:
handle_cast({remove_node, Node}, State) ->
  {noreply, node_core:remove_node(Node, State)};

handle_cast(check_liveness, #state{chord_nodes = CN, pastry_nodes = PN} = State) ->
  io:format("checking liveness of ~p nodes~n", [length(CN ++ PN)]),
  node_core:check_liveness(CN ++ PN),
  io:format("returned from checking liveness~n"),
  {noreply, State};

handle_cast(_Msg, State) ->
  {noreply, State}.

%% Info:
handle_info(_Info, State) ->
  {noreply, State}.

terminate(_Reason, #state{timerRef = TimerRef}) ->
  timer:cancel(TimerRef),
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

nodes_as_struct({Chord, Pastry}) ->
  ChordNodes = {<<"chord_nodes">>, encode_nodes(Chord)},
  PastryNodes = {<<"pastry_nodes">>, encode_nodes(Pastry)},
  {struct,[ChordNodes, PastryNodes]}.

encode_nodes(Nodes) -> [{struct, [{<<"ip">>, ip_to_binary(N#node.ip)}, {<<"port">>, code_port(N#node.port)}]} || N <- Nodes].
ip_to_binary({A,B,C,D}) -> list_to_binary(lists:flatten(io_lib:format("~p.~p.~p.~p", [A,B,C,D]))).
code_port(Port) -> list_to_bitstring(integer_to_list(Port)).


-ifdef(TEST).
-endif.
