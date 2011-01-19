-module(controller_tcp).
-behaviour(gen_listener_tcp).

-define(TIMEOUT, 2000).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-include("../fs.hrl").

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

%% ------------------------------------------------------------------
%% gen_listener_tcp Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_accept/2, handle_call/3, handle_cast/2]).
-export([handle_info/2, terminate/2, code_change/3]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

-spec(perform_rpc/3::(Message::term(), _, _) ->
    {ok, _} | {error, _}).
perform_rpc(Message, Ip, Port) ->
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
      case SoFar =:= <<>> of
        true -> {ok, ok};
        false ->
          try {ok, binary_to_term(list_to_binary(lists:reverse(SoFar)))}
          catch error:badarg -> {error, badarg}
          end
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
  gen_listener_tcp:call(controller_tcp, stop).

%% @doc Start the server.
start_link(Args) ->
  gen_listener_tcp:start_link({local, ?MODULE}, ?MODULE, Args, []).

%% @doc The echo client process.
controller_tcp_client(Socket) ->
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
  error_logger:info_msg("Initializing controller_tcp listening on port: ~p~n", [Port]),
  {ok, {Port, ?TCP_OPTS}, []}.

handle_accept(Sock, State) ->
  Pid = spawn(fun() -> controller_tcp_client(Sock) end),
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

handle_msg(ping) ->
  pong;

handle_msg(Msg) ->
  error_logger:error_msg("Message not handled ~p", [Msg]),
  error.
