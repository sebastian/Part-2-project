-module(node_srv).
-behaviour(gen_server).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-define(SERVER, ?MODULE).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/0, start/0, stop/0]).
-export([reg_and_get_peer/1, clear/0]).

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
  gen_server:call(?MODULE, stop).

reg_and_get_peer(NodeDetails) ->
  gen_server:call(?MODULE, {register, NodeDetails}).

clear() ->
  gen_server:call(?MODULE, clear).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(_Args) -> 
  {ok, []}.

%% Call:
handle_call(stop, _From, State) ->
  {stop, normal, ok, State};

handle_call({register, {Ip, Port} = Details}, _From, State) ->
  Peers = get_not_me(Details, State),
  io:format("In node_srv with details: ~p. Returning peers: ~p~n", [Details, Peers]),
  NewState = case (Ip =:= undefined orelse Port =:= undefined orelse lists:member(Details, State)) of
    true -> State;
    false -> [Details|State]
  end,
  {reply, Peers, NewState};

handle_call(clear, _From, _State) ->
  {reply, ok, []}.

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

get_not_me(Details, State) ->
  NumToGet = 5,
  Peers = lists:sublist(State -- [Details], NumToGet),
  case Peers of
    [] -> first;
    _ -> Peers
  end.

-ifdef(TEST).
get_not_me_first_test() ->
  ?assertEqual(first, get_not_me({ip, port}, [])).

get_not_me_test() ->
  State = [{ip, port}, {otherIp, port}, {otherOtherIp, otherPort}],
  ?assertEqual([{otherIp, port}, {otherOtherIp, otherPort}], get_not_me({ip, port}, State)).

-endif.
