-module(pastry_tcp).
-behaviour(gen_listener_tcp).

-include("../fs.hrl").
-include("pastry.hrl").

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
    send_msg/2
  ]).

%% ------------------------------------------------------------------
%% gen_listener_tcp Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_accept/2, handle_call/3, handle_cast/2]).
-export([handle_info/2, terminate/2, code_change/3]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

deliver_in_bulk(Entries, #node{ip = Ip, port = Port}) ->
  perform_rpc({bulk_delivery, Entries}, Ip, Port).

perform_join(JoinNode, #node{ip = Ip, port = Port}) ->
  perform_rpc({join, JoinNode}, Ip, Port).

send_routing_table(RoutingTable, #node{ip = Ip, port = Port}) ->
  perform_rpc({send_routing_table, RoutingTable}, Ip, Port).

route_msg(Msg, Key, #node{ip = Ip, port = Port}) ->
  perform_rpc({route, Msg, Key}, Ip, Port).

welcome({LSS, LSG}, #node{ip = Ip, port = Port}) ->
  perform_rpc({welcome, LSS ++ LSG}, Ip, Port).

request_routing_table(#node{ip = Ip, port = Port}) ->
  perform_rpc(request_routing_table, Ip, Port).

request_leaf_set(#node{ip = Ip, port = Port}) ->
  perform_rpc(request_leaf_set, Ip, Port).

request_neighborhood_set(#node{ip = Ip, port = Port}) ->
  perform_rpc(request_neighborhood_set, Ip, Port).

send_nodes(Nodes, #node{ip = Ip, port = Port}) ->
  perform_rpc({add_nodes, Nodes}, Ip, Port).

send_msg(Msg, #node{ip = Ip, port = Port}) ->
  perform_rpc(Msg, Ip, Port).

-spec(perform_rpc/3::(Message::term(), Ip::ip(), Port::port_number()) ->
    {ok, _} | {error, _}).
perform_rpc(Message, Ip, Port) ->
  case gen_tcp:connect(Ip, Port, [binary, {packet, 0}, {active, true}]) of
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
      try {ok, binary_to_term(list_to_binary(lists:reverse(SoFar)), [safe])}
      catch error:badarg ->
        error_logger:error_msg("Response returned by other part couldn't be parsed"),
        {error, badarg}
      end
  after 5000 ->
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
        Message = binary_to_term(list_to_binary(FinalBin), [safe]),
        RetValue = handle_msg(Message),
        ok = gen_tcp:send(Socket, term_to_binary(RetValue)),
        gen_tcp:close(Socket)
      catch
        error:badarg ->
          io:format("Couldn't be made into anything legible...~n"),
          % The packet got fragmented somehow...
          receive_incoming(Socket, [Bin|SoFar])
      end;
    {tcp_closed, _Socket} ->
      ok;
    {tcp_error, Socket, _Reason} ->
      % Something is wrong. We aggresively close the socket.
      gen_tcp:close(Socket),
      ok
  after 2000 ->
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

handle_msg(_) ->
  ?NYI.
