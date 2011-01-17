-module(chord_tcp).
-behaviour(gen_listener_tcp).

-include("../fs.hrl").
-include("chord.hrl").

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

-export([start_link/1, start/0, stop/0]).
-export([rpc_get_closest_preceding_finger_and_succ/2, 
         rpc_find_successor/3,
         rpc_lookup_key/2, 
         rpc_set_key/3,
         notify_successor/2, 
         get_predecessor/1, 
         rpc_get_successor/1,
         rpc_send_entries/2,
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
  case perform_rpc({rendevouz, chord, SelfIp, SelfPort}, #node{ip = Ip, port = Port}) of
    {ok, Reply} -> Reply;
    Other -> Other
  end.

-spec(rpc_send_entries/2::(Entries::[#entry{}], Node::#node{}) ->
    {ok, done} | {error, _}).
rpc_send_entries(Entries, Node) ->
  perform_rpc({send_entries, Entries}, Node).

-spec(rpc_lookup_key/2::(Key::key(), Node::#node{}) ->
    {ok, [#entry{}]} | {error, _}).
rpc_lookup_key(Key, Node) ->
  perform_rpc({lookup_key, Key}, Node).

-spec(rpc_set_key/3::(Key::key(), Value::#entry{}, Node::#node{}) ->
    {ok, _} | {error, _}).
rpc_set_key(Key, Value, Node) ->
  perform_rpc({set_key, Key, Value}, Node).

-spec(rpc_get_closest_preceding_finger_and_succ/2::(Key::key(), Node::#node{}) 
    -> {ok, {_::#node{}, _::#node{}}} | {error, _}).
rpc_get_closest_preceding_finger_and_succ(Key, Node) ->
  perform_rpc({preceding_finger, Key}, Node).

-spec(rpc_find_successor/3::(Key::key(), Ip::ip(), Port::port_number()) ->
    {ok, #node{}} | {error, _}).
rpc_find_successor(Key, Ip, Port) ->
  perform_rpc({find_successor, Key}, #node{ip = Ip, port = Port}).

-spec(get_predecessor/1::(#node{}) ->
    {ok, #node{}} | {ok, undefined} | {error, _}).
get_predecessor(Node) ->
  perform_rpc(get_predecessor, Node).

-spec(rpc_get_successor/1::(#node{}) ->
    {ok, #node{}} | {ok, undefined} | {error, _}).
rpc_get_successor(Node) ->
  perform_rpc(get_successor, Node).

-spec(notify_successor/2::(#node{}, CurrentNode::#node{}) -> ok).
notify_successor(Node, CurrentNode) ->
  perform_rpc({notify_about_predecessor, CurrentNode}, Node),
  ok.

-spec(perform_rpc/2::(Message::term(), #node{}) ->
    {ok, _} | {error, _}).
perform_rpc(Message, #node{ip = Ip, port = Port}) ->
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
  gen_listener_tcp:call(chord_tcp, stop).

%% @doc Start the server.
start_link(Args) ->
  gen_listener_tcp:start_link({local, ?MODULE}, ?MODULE, Args, []).

%% @doc The echo client process.
chord_tcp_client(Socket) ->
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
  error_logger:info_msg("Initializing chord_tcp listening on port: ~p~n", [Port]),
  {ok, {Port, ?TCP_OPTS}, []}.

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

handle_msg({lookup_key, Key}) ->
  chord:local_lookup(Key);

handle_msg(get_successor) ->
  chord:get_successor();

handle_msg({send_entries, Entries}) ->
  chord:receive_entries(Entries);

handle_msg(ping) ->
  pong;

handle_msg(_) ->
  ?NYI.
