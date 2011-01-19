-module(hub_tcp).
-behaviour(gen_listener_tcp).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-include("records.hrl").

-define(TCP_OPTS, [binary, inet,
                   {active,    true},
                   {backlog,   50},
                   {nodelay,   true},
                   {packet,    0},
                   {reuseaddr, true}]).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/1, start/0, stop/0]).
-export([
    is_node_alive/1
  ]).

%% ------------------------------------------------------------------
%% gen_listener_tcp Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_accept/2, handle_call/3, handle_cast/2]).
-export([handle_info/2, terminate/2, code_change/3]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

is_node_alive(Node) ->
  case perform_rpc(ping, Node) of
    {ok, pong} -> true;
    _ -> false
  end.

-spec(perform_rpc/2::(Message::term(), #node{}) ->
    {ok, _} | {error, _}).
perform_rpc(Message, #node{ip = Ip, port = Port}) ->
  Timeout = 400,
  case gen_tcp:connect(Ip, Port, [binary, {packet, 0}, {active, true}], Timeout) of
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
      try
        {ok, binary_to_term(list_to_binary(lists:reverse(SoFar)))}
      catch
        error:badarg ->
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

start() ->
  gen_listener_tcp:start({local, ?MODULE}, ?MODULE, [], []).

stop() ->
  gen_listener_tcp:call(hub, stop).

%% @doc Start the server.
start_link(Args) ->
  gen_listener_tcp:start_link({local, ?MODULE}, ?MODULE, Args, []).

%% @doc The echo client process.
hub_client(Socket) ->
  receive_incoming(Socket, []).

receive_incoming(Socket, SoFar) ->
  receive
    {tcp, Socket, Bin} ->
      try
        FinalBin = lists:reverse([Bin | SoFar]),
        Message = binary_to_term(list_to_binary(FinalBin)),
        {ok, {RemoteIp, _RemotePort}} = inet:peername(Socket),
        RetValue = handle_msg(Message, RemoteIp),
        ok = gen_tcp:send(Socket, term_to_binary(RetValue)),
        gen_tcp:close(Socket)
      catch
        error:badarg ->
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
  error_logger:info_msg("Initializing hub listening on port: ~p~n", [Port]),
  {ok, {Port, ?TCP_OPTS}, []}.

handle_accept(Sock, State) ->
  Pid = spawn(fun() -> hub_client(Sock) end),
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

handle_msg({rendevouz, pastry, Port}, Ip) ->
  Node = #node{ip = Ip, port = Port},
  {Ip, node:rendevouz_pastry(Node)};

handle_msg({rendevouz, chord, Port}, Ip) ->
  Node = #node{ip = Ip, port = Port},
  {Ip, node:rendevouz_chord(Node)};

handle_msg(_, _) ->
  error_logger:error_msg("Unimplemented message type"),
  404.
