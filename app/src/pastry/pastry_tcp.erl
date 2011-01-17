-module(pastry_tcp).
-behaviour(gen_listener_tcp).

-include("../fs.hrl").
-include("pastry.hrl").
-define(TIMEOUT, 2000).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-define(TCP_OPTS, [binary, inet,
                   {active,    true},
                   {backlog,   50},
                   {nodelay,   true},
                   {packet,    0},
                   {reuseaddr, true}]).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/1, start/1, stop/0]).
-export([
    perform_join/2,
    send_routing_table/2,
    route_msg/3,
    welcome/2,
    request_routing_table/1,
    request_leaf_set/1,
    request_neighborhood_set/1,
    send_nodes/2,
    deliver_in_bulk/2,
    send_msg/2,
    is_node_alive/1,
    rendevouz/3
  ]).

%% ------------------------------------------------------------------
%% gen_listener_tcp Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_accept/2, handle_call/3, handle_cast/2]).
-export([handle_info/2, terminate/2, code_change/3]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

% Performs a randevouz with the hub_app which returns nodes to
% connect to
rendevouz(#node{ip = SelfIp, port = SelfPort}, Ip, Port) ->
  case perform_rpc({rendevouz, pastry, SelfIp, SelfPort}, #node{ip = Ip, port = Port}) of
    {ok, Reply} -> Reply;
    Other -> Other
  end.

is_node_alive(Node) ->
  case perform_rpc(ping, Node) of
    {ok, pong} -> true;
    _ -> false
  end.

deliver_in_bulk(Entries, Node) ->
  perform_rpc({bulk_delivery, Entries}, Node).

perform_join(JoinNode, Node) ->
  perform_rpc({join, JoinNode}, Node).

send_routing_table(RoutingTable, Node) ->
  perform_rpc({send_routing_table, RoutingTable}, Node).

route_msg(Msg, Key, Node) ->
  perform_rpc({route, Msg, Key}, Node).

welcome({LSS, LSG}, Node) ->
  perform_rpc({welcome, LSS ++ LSG}, Node).

request_routing_table(Node) ->
  perform_rpc(request_routing_table, Node).

request_leaf_set(Node) ->
  perform_rpc(request_leaf_set, Node).

request_neighborhood_set(Node) ->
  perform_rpc(request_neighborhood_set, Node).

send_nodes(Nodes, Node) ->
  perform_rpc({add_nodes, Nodes}, Node).

send_msg(Msg, Node) ->
  perform_rpc(Msg, Node).

-spec(perform_rpc/2::(Message::term(), #node{}) ->
    {ok, _} | {error, _}).
perform_rpc(Message, #node{ip = Ip, port = Port}) ->
  case gen_tcp:connect(Ip, Port, [binary, {packet, 0}, {active, true}], ?TIMEOUT) of
    {ok, Socket} ->
      ok = gen_tcp:send(Socket, term_to_binary(Message)),
      receive_data(Socket, []);
    {error, Reason} ->
      % Handle error somehow
      {error, Reason}
  end.

receive_data(Socket, SoFar) ->
  receive
    {tcp, Socket, Bin} ->
      receive_data(Socket, [Bin | SoFar]);
    {tcp_closed, Socket} ->
      try {ok, binary_to_term(list_to_binary(lists:reverse(SoFar)))}
      catch error:badarg ->
        error_logger:error_msg("Response returned by other part couldn't be parsed"),
        {error, badarg}
      end
  after 2 * ?TIMEOUT ->
    error_logger:info_msg("PerformRPC times out~n"),
    {error, timeout}
  end.


%% ------------------------------------------------------------------
%% gen_listener_tcp Function Definitions
%% ------------------------------------------------------------------

start(Port) ->
  gen_listener_tcp:start({local, ?MODULE}, ?MODULE, [Port], []).

stop() ->
  gen_listener_tcp:call(pastry_tcp, stop).

%% @doc Start the server.
start_link(Args) ->
  gen_listener_tcp:start_link({local, ?MODULE}, ?MODULE, Args, []).

%% @doc The echo client process.
pastry_tcp_client(Socket) ->
  receive_incoming(Socket, []).

receive_incoming(Socket, SoFar) ->
  receive
    {tcp, Socket, Bin} ->
      try
        FinalBin = lists:reverse([Bin | SoFar]),
        Message = binary_to_term(list_to_binary(FinalBin)),
        RetValue = handle_msg(Message),
        ok = gen_tcp:send(Socket, term_to_binary(RetValue)),
        gen_tcp:close(Socket)
      catch
        error:badarg ->
          % Partial data received? Continue
          receive_incoming(Socket, [Bin|SoFar])
      end;
    {tcp_closed, _Socket} ->
      ok;
    {tcp_error, Socket, _Reason} ->
      % Something is wrong. We aggresively close the socket.
      gen_tcp:close(Socket),
      ok
  after ?TIMEOUT ->
    % Client hasn't sent us data for a while, close connection.
    gen_tcp:close(Socket)
  end.

init(Args) ->
  Port = proplists:get_value(port, Args),
  error_logger:info_msg("Initializing pastry_tcp listening on port: ~p~n", [Port]),
  {ok, {Port, ?TCP_OPTS}, []}.

handle_accept(Sock, State) ->
  Pid = spawn(fun() -> pastry_tcp_client(Sock) end),
  gen_tcp:controlling_process(Sock, Pid),
  {noreply, State}.

handle_call(stop, _From, State) ->
  {stop, normal, ok, State};

handle_call(Request, _From, State) ->
  {reply, {illegal_request, Request}, State}.

handle_cast(_Request, State) ->
  {noreply, State}.

handle_info(_Info, State) ->
  {noreply, State}.

terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.
    
%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

handle_msg({send_routing_table, RoutingTable}) ->
  pastry:augment_routing_table(RoutingTable);

handle_msg({join, JoinNode}) ->
  % This call only happens when a node explicitly asks
  % another node to join the network. As a node nearby
  % the other node, we should sent it our neighborhood list
  spawn(fun() -> send_nodes(pastry:get_neighborhoodset(), JoinNode) end),
  % Now forward the join message
  pastry:let_join(JoinNode),
  ok;
handle_msg({route, {join, JoinNode}, _Key}) ->
  % Nodes forward a join message as any other message, we therefore
  % intercept it here and give it the special join treatment
  pastry:let_join(JoinNode),
  ok;

handle_msg({route, Msg, Key}) ->
  pastry:route(Msg, Key),
  ok;

handle_msg({welcome, Leafs}) ->
  pastry:add_nodes(Leafs),
  pastry:welcomed();

handle_msg(request_routing_table) ->
  pastry:get_routing_table();

handle_msg(request_neighborhood_set) ->
  pastry:get_neighborhoodset();

handle_msg(request_leaf_set) ->
  pastry:get_leafset();

handle_msg({add_nodes, Nodes}) ->
  pastry:add_nodes(Nodes);

handle_msg({data, {Pid, Ref}, Data}) ->
  Pid ! {data, Ref, Data},
  ok;

handle_msg({bulk_delivery, Entries}) ->
  spawn(fun() -> pastry_app:bulk_delivery(Entries) end),
  ok;

handle_msg(ping) ->
  pong;

handle_msg(_) ->
  ?NYI.
