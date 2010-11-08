-module(node_srv).
-behaviour(gen_server).

-define(SERVER, ?MODULE).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/0, start/0, stop/0]).
-export([reg_and_get_peer/1]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start() ->
  gen_server:start({local, ?SERVER}, ?MODULE, [], []).

start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

stop() ->
  gen_server:call(chord, stop).

reg_and_get_peer(NodeDetails) ->
  gen_server:call(node_srv, {register, NodeDetails}).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(_Args) -> 
  {ok, []}.

%% Call:
handle_call(stop, _From, State) ->
  {stop, normal, ok, State};

handle_call({register, Details}, _From, State) ->
  Peer = get_not_me(Details, State),
  io:format("In node_srv with details: ~p. Returning peer: ~p~n", [Details, Peer]),
  NewState = case lists:member(Details, State) of
    true -> State;
    false -> [Details|State]
  end,
  {reply, Peer, NewState}.


%% Casts:
handle_cast(_Msg, State) ->
  {noreply, State}.

%% Info:
handle_info(_Info, State) ->
  {noreply, State}.

terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

get_not_me(_Details, []) -> first;
get_not_me(Details, [Details|Hs]) -> get_not_me(Details, Hs);
get_not_me(_Details, [Peer|_Hs]) -> Peer. 
