-module(pastry).
-behaviour(gen_server).

-define(SERVER, ?MODULE).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-include("../fs.hrl").
-include("pastry.hrl").

%% ------------------------------------------------------------------
%% Public API
%% ------------------------------------------------------------------

-export([start_link/0, start/0, stop/0]).
-export([lookup/1, set/2]).
-export([
    pastryInit/1,
    route/2
  ]).

%% ------------------------------------------------------------------
%% PRIVATE API Function Exports
%% ------------------------------------------------------------------

% For joining
-export([
    augment_routing_table/2,
    let_join/1
  ]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([
    init/1, 
    handle_call/3,
    handle_cast/2, 
    handle_info/2, 
    terminate/2, 
    code_change/3
  ]).

%% ------------------------------------------------------------------
%% PUBLIC API Function Definitions
%% ------------------------------------------------------------------

start() ->
  gen_server:start({local, ?SERVER}, ?MODULE, [], []).

start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

stop() ->
  gen_server:call(?MODULE, stop).

%% @doc: gets a value from the chord network
-spec(lookup/1::(Key::key()) -> [#entry{}]).
lookup(Key) ->
  ok.

%% @doc: stores a value in the chord network
-spec(set/2::(Key::key(), Entry::#entry{}) -> ok).
set(Key, Entry) ->
  ok.

pastryInit(Node) ->
  magic.

route(Msg, Key) ->
  {Msg, Key}.


%% ------------------------------------------------------------------
%% PRIVATE API Function Definitions
%% ------------------------------------------------------------------

augment_routing_table(RoutingTable, From) ->
  gen_server:cast(?SERVER, {augment_routing_table, RoutingTable, From}),
  thanks.


let_join(Node) ->
  % Forward the routing message to the next node
  route({join, Node}, Node#node.key),
  % Respond with our routing table
  % @todo: If this is the final destination of the join message, then
  % also send a special welcome message to the node to let
  % it know that is has received all the info it will receive for now.
  % Following that the node should broadcast its routing table to all
  % it knows about.
  % @todo: At this point we should also add the node to our table if it fits in
  gen_server:call(?SERVER, get_routing_table).


%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(Args) -> 
  B = proplists:get_value(b, Args),
  Port = proplists:get_value(port, Args),
  Ip = utilities:get_ip(),
  Key = utilities:key_for_node_with_b(Ip, Port, B),
  Self = #node{key = Key, port = Port, ip = Ip},

  {JoinIp, JoinPort} = proplists:get_value(joinNode, Args),

  State = #pastry_state{
    b = B,
    self = Self,
    routing_table = create_routing_table(Key)
  },
  {ok, State}.

% Call:
handle_call(get_routing_table, _From, State) ->
  {reply, State#pastry_state.routing_table, State};

handle_call(stop, _From, State) ->
  {stop, normal, ok, State}.


% Casts:
handle_cast({augment_routing_table, RoutingTable, From}, State) ->
  {noreply, augment_routing_table(RoutingTable, From, State)};

handle_cast(Msg, State) ->
  error_logger:error_msg("received unknown cast: ~p", [Msg]),
  {noreply, State}.


% Info:
handle_info(Info, State) ->
  error_logger:error_msg("Got info message: ~p", [Info]),
  {noreply, State}.


% Terminate:
terminate(_Reason, State) ->
  ok.


code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

create_routing_table(Key) ->
  [#routing_table_entry{value = none} | [#routing_table_entry{value = V} || V <- Key]].


augment_routing_table(RoutingTable, From, State) ->
  State.

merge_nodes(MyNodes, TheirNodes, SharedKey) ->
  TheirNodesWithDistance = [Node#node{distance = pastry_location:distance(Node#node.ip)} || Node <- TheirNodes],
  MyNodes ++ TheirNodesWithDistance.

%% ------------------------------------------------------------------
%% Tests
%% ------------------------------------------------------------------

-ifdef(TEST).

test_state() ->
  Key = [0,0,0,0],
  #pastry_state{
    self = #node{
      key = Key,
      ip = {1,2,3,4},
      port = 1234
    },
    routing_table = create_routing_table(Key)
  }.

create_routing_table_test() ->
  Key = [1,2,3],
  ?assertEqual([#routing_table_entry{value = none}, 
      #routing_table_entry{value = 1}, 
      #routing_table_entry{value = 2}, 
      #routing_table_entry{value = 3}],
    create_routing_table(Key)).

augment_routing_table_test() ->
  State = test_state(),
  From = #node{
    key = [0,1,0,0]
  },
  NewNodes = [#node{key=[1,2,3,4]}],
  NewRoutingTable = [#routing_table_entry{}].

merge_nodes_test() ->
  SharedKey = [1],
  MyNodes = [#node{key = [1,0]}],
  NodeIp = {1,2,3,4},
  ANode = #node{key = [1,1], ip = NodeIp},
  TheirNodes = [ANode],

  erlymock:start(),
  erlymock:strict(pastry_location, distance, [NodeIp], [{return, 3}]),
  erlymock:replay(), 
  [A,B] = merge_nodes(MyNodes, TheirNodes, SharedKey),
  erlymock:verify(),

  ?assertEqual(3, B#node.distance).

  
-endif.
