-module(chord_tcp).
-behaviour(gen_listener_tcp).

-include("../fs.hrl").
-include("chord.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

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
-export([rpc_get_closest_preceding_finger_and_succ/2, rpc_find_successor/3]).
-export([rpc_get_key/2, rpc_set_key/3]).
-export([notify_successor/2, get_predecessor/1]).

%% ------------------------------------------------------------------
%% gen_listener_tcp Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_accept/2, handle_call/3, handle_cast/2]).
-export([handle_info/2, terminate/2, code_change/3]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

-spec(rpc_get_key/2::(Key::key(), Node::#node{}) ->
    {ok, [#entry{}]} | {error, _}).
rpc_get_key(Key, #node{ip=Ip, port=Port}) ->
  perform_rpc({get_key, Key}, Ip, Port).

-spec(rpc_set_key/3::(Key::key(), Value::#entry{}, Node::#node{}) ->
    {ok, _} | {error, _}).
rpc_set_key(Key, Value, #node{ip=Ip, port=Port}) ->
  perform_rpc({set_key, Key, Value}, Ip, Port).

-spec(rpc_get_closest_preceding_finger_and_succ/2::(Key::key(), Node::#node{}) 
    -> {ok, {_::#node{}, _::#node{}}} | {error, _}).
rpc_get_closest_preceding_finger_and_succ(Key, #node{ip=Ip, port=Port}) ->
  perform_rpc({preceding_finger, Key}, Ip, Port).

-spec(rpc_find_successor/3::(Key::key(), Ip::ip(), Port::port_number()) ->
    {ok, #node{}} | {error, _}).
rpc_find_successor(Key, Ip, Port) ->
  perform_rpc({find_successor, Key}, Ip, Port).

-spec(get_predecessor/1::(#node{}) ->
    {ok, #node{}} | {ok, undefined} | {error, _}).
get_predecessor(#node{ip=Ip, port=Port}) ->
  perform_rpc(get_predecessor, Ip, Port).

-spec(notify_successor/2::(#node{}, CurrentNode::#node{}) -> ok).
notify_successor(#node{ip = Ip, port = Port}, CurrentNode) ->
  perform_rpc({notify_about_predecessor, CurrentNode}, Ip, Port),
  ok.

-spec(perform_rpc/3::(Message::term(), Ip::ip(), Port::port_number()) ->
    {ok, _} | {error, _}).
perform_rpc(Message, Ip, Port) ->
  perform_rpc(Message, Ip, Port, 3, none).

-spec(perform_rpc/5::(Message::term(), Ip::ip(), Port::port_number(), 
    Tries::integer(), PreviousResponse::term()) -> {ok, _} | {error, _}).
perform_rpc(Message, _Ip, _Port, 0, PreviousResponse) ->
  error_logger:error_msg("Failed perform_rpc for message: ~p~n", [Message]),
  PreviousResponse;
perform_rpc(Message, Ip, Port, Tries, _PreviousResponse) ->
  case gen_tcp:connect(Ip, Port, [binary, {packet, 0}]) of
    {ok, Socket} ->
      gen_tcp:send(Socket, term_to_binary(Message)),
      Ret = receive 
        {tcp, Socket, Data} ->
          {ok, binary_to_term(Data, [safe])};
        {tcp_closed, Socket} ->
          error_logger:info_msg("TCP connection closed"),
          {ok, closed};
        Msg -> 
          error_logger:error_msg("Unknown message: ~p~n", [Msg])
      after 2000 ->
        perform_rpc(Message, Ip, Port, Tries - 1, {error, timeout})
      end, 
      gen_tcp:close(Socket),
      Ret;
    {error, econnrefused} ->
      perform_rpc(Message, Ip, Port, Tries - 1, {error, econnrefused})
  end.

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
  ok = inet:setopts(Socket, [{active, once}]),
  receive
    {tcp, Socket, <<"quit", _R/binary>>} ->
      gen_tcp:send(Socket, "Bye now.\r\n"),
      gen_tcp:close(Socket);
    {tcp, Socket, Data} ->
      Message = binary_to_term(Data, [safe]),
      RetValue = handle_msg(Message),
      gen_tcp:send(Socket, term_to_binary(RetValue)),
      chord_tcp_client(Socket);
    {tcp_closed, Socket} ->
      ok
  end.

init([]) ->
  {ok, {utilities:get_chord_port(), ?TCP_OPTS}, []}.

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
  chord:preceding_finger(Key);

handle_msg({find_successor, Key}) ->
  chord:find_successor(Key);

handle_msg(get_predecessor) ->
  chord:get_predecessor();

handle_msg({notify_about_predecessor, CurrentNode}) ->
  chord:notified(CurrentNode);

handle_msg({set_key, Key, Value}) ->
  chord:local_set(Key, Value);

handle_msg({get_key, Key}) ->
  chord:local_get(Key);

handle_msg(Msg) ->
  ?NYI.
