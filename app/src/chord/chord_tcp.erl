-module(chord_tcp).
-behaviour(gen_listener_tcp).

-include("../fs.hrl").
-include("chord.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-define(TCP_PORT, 9234).
-define(TCP_OPTS, [binary, inet,
                   {active,    false},
                   {backlog,   10},
                   {nodelay,   true},
                   {packet,    raw},
                   {reuseaddr, true}]).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/0, start/0, stop/0]).
-export([rpc_get_closest_preceding_finger/3, rpc_find_successor/3]).

%% ------------------------------------------------------------------
%% gen_listener_tcp Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_accept/2, handle_call/3, handle_cast/2]).
-export([handle_info/2, terminate/2, code_change/3]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

-spec(rpc_get_closest_preceding_finger/3::(Key::key(), Ip::ip(), Port::port()) ->
    {ok, {#node{}, key()}} | {error, term()}).
rpc_get_closest_preceding_finger(Key, Ip, Port) ->
  perform_rpc({preceding_finger, Key}, Ip, Port).

-spec(rpc_find_successor/3::(Key::key(), Ip::ip(), Port::port()) ->
    {ok, #node{}} | {error, term()}).
rpc_find_successor(Key, Ip, Port) ->
  perform_rpc({find_successor, Key}, Ip, Port).

-spec(perform_rpc/3::(Message::term(), Ip::ip(), Port::port()) ->
    {ok, term()} | {error, insatnce} | {error, timeout} | {error, atom()}).
perform_rpc(Message, Ip, Port) ->
  {ok, Socket} = gen_tcp:connect(Ip, Port, [binary, {packet, 0}]),
  gen_tcp:send(Socket, term_to_binary(Message)),
  Ret = receive 
    {tcp, Socket, Data} ->
      {ok, binary_to_term(Data, [safe])};
    {tcp_closed, Socket} ->
      {error, tcp_closed};
    {tcp_error, Socket, Reason} ->
      {error, Reason}
  after 2000 ->
    {error, timeout}
  end, 
  gen_tcp:close(Socket),
  Ret.

%% ------------------------------------------------------------------
%% gen_listener_tcp Function Definitions
%% ------------------------------------------------------------------

start() ->
  gen_listener_tcp:start({local, ?MODULE}, ?MODULE, [], []).

stop() ->
  gen_listener_tcp:call(chord_tcp, stop).

%% @doc Start the server.
start_link() ->
  gen_listener_tcp:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc The echo client process.
chord_tcp_client(Socket) ->
  error_logger:info_msg("client()~n"),
  ok = inet:setopts(Socket, [{active, once}]),
  receive
    {tcp, Socket, <<"quit", _R/binary>>} ->
      error_logger:info_msg("Quit Requested."),
      gen_tcp:send(Socket, "Bye now.\r\n"),
      gen_tcp:close(Socket);
    {tcp, Socket, Data} ->
      Message = binary_to_term(Data, [safe]),
      error_logger:info_msg("Got Data: ~p", [Message]),
      {ok, Value} = handle_msg(Message),
      gen_tcp:send(Socket, term_to_binary(Value)),
      chord_tcp_client(Socket);
    {tcp_closed, Socket} ->
      error_logger:info_msg("Client Disconnected.")
  end.

init([]) ->
  {ok, {?TCP_PORT, ?TCP_OPTS}, []}.

handle_accept(Sock, State) ->
  Pid = spawn(fun() -> chord_tcp_client(Sock) end),
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

handle_msg({preceding_finger, Key}) ->
  ?debugFmt("In handle_msg preceding_finger ~p", [Key]),
  chord:preceding_finger(Key);

handle_msg({find_successor, Key}) ->
  chord:find_successor(Key).
