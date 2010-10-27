-module(chord_tcp).
-behaviour(gen_listener_tcp).

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

-export([start_link/0]).

%% ------------------------------------------------------------------
%% gen_listener_tcp Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_accept/2, handle_call/3, handle_cast/2]).
-export([handle_info/2, terminate/2, code_change/3]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

%% ------------------------------------------------------------------
%% gen_listener_tcp Function Definitions
%% ------------------------------------------------------------------

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
            error_logger:info_msg("Got Data: ~p", [Data]),
            gen_tcp:send(Socket, "I Received " ++ Data),
            chord_tcp_client(Socket);
        {tcp_closed, Socket} ->
            error_logger:info_msg("Client Disconnected.")
    end.

init([]) ->
    {ok, {?TCP_PORT, ?TCP_OPTS}, nil}.

handle_accept(Sock, State) ->
    Pid = spawn(fun() -> chord_tcp_client(Sock) end),
    gen_tcp:controlling_process(Sock, Pid),
    {noreply, State}.

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