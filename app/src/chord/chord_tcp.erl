-module(chord_tcp).
-behaviour(gen_listener_tcp).

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

-record(state, {
    ip, port, 
    pending_requests :: [{bitstring(), pid()}]
  }).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/0, start/0, stop/0]).
-export([get_closest_preceding_finger/3]).

%% ------------------------------------------------------------------
%% gen_listener_tcp Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_accept/2, handle_call/3, handle_cast/2]).
-export([handle_info/2, terminate/2, code_change/3]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

get_closest_preceding_finger(Key, Ip, Port) ->
  case try_get_socket(Ip, Port, 3) of
    {ok, Socket} ->
      gen_tcp:send(Socket, term_to_binary({predecing_finger, Key})),
      RVal = case gen_tcp:recv(Socket, 0, 1500) of
        {ok, Data} ->
          case binary_to_term(Data) of 
            {preceding_finger, Key, Finger, Succ} ->
              {ok, Finger, Succ};
            _ ->
              {error, instance}
          end;
        {error, _Reason} ->
          {error, timeout}
      end,
      gen_tcp:close(Socket),
      RVal;
    error -> 
      ?debugMsg("Failed to open socket"),
      {error, instance}
  end.

try_get_socket(_Ip, _Port, 0) -> error;
try_get_socket(Ip, Port, Retries) ->
  case gen_tcp:connect(Ip, Port, [binary, {packet, 0}]) of
    {error, _Reason} -> try_get_socket(Ip, Port, Retries - 1);
    Val -> Val
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
  error_logger:info_msg("client()~n"),
  ok = inet:setopts(Socket, [{active, once}]),
  receive
    {tcp, Socket, <<"quit", _R/binary>>} ->
      error_logger:info_msg("Quit Requested."),
      gen_tcp:send(Socket, "Bye now.\r\n"),
      gen_tcp:close(Socket);
    {tcp, Socket, Data} ->
      Message = binary_to_term(Data),
      {ok, Value} = handle_msg(Message),
      error_logger:info_msg("Got Data: ~p", [Data]),
      gen_tcp:send(Socket, term_to_binary(Value)),
      chord_tcp_client(Socket);
    {tcp_closed, Socket} ->
      error_logger:info_msg("Client Disconnected.")
  end.

init([]) ->
  State = #state{
    ip = utilities:get_ip(),
    port = ?TCP_PORT,
    pending_requests = []
  },
  {ok, {?TCP_PORT, ?TCP_OPTS}, State}.

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

handle_msg({predecing_finger, Key}) ->
  {ok, chord:preceding_finger(Key)}.
