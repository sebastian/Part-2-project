-module(pastry).
-behaviour(gen_server).

-define(SERVER, ?MODULE).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-include("../fs.hrl").

%% ------------------------------------------------------------------
%% Public API
%% ------------------------------------------------------------------

-export([start_link/0, start/0, stop/0]).
-export([lookup/1, set/2]).

%% ------------------------------------------------------------------
%% PRIVATE API Function Exports
%% ------------------------------------------------------------------

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([
    init/1, 
    handle_call/3,
    handle_cast/2, 
    handle_info/2, 
    terminate/2, 
    code_change/3
  ]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start() ->
  gen_server:start({local, ?SERVER}, ?MODULE, [], []).

start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

stop() ->
  gen_server:call(?MODULE, stop).

%% @doc: gets a value from the chord network
-spec(lookup/1::(Key::key()) -> [#entry{}]).
lookup(Key) ->
  ok.

%% @doc: stores a value in the chord network
-spec(set/2::(Key::key(), Entry::#entry{}) -> ok).
set(Key, Entry) ->
  ok.

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(_Args) -> 
  {ok, state}.

% Call:
handle_call(stop, _From, State) ->
  {stop, normal, ok, State}.


% Casts:
handle_cast(Msg, State) ->
  error_logger:error_msg("received unknown cast: ~p", [Msg]),
  {noreply, State}.


% Info:
handle_info(Info, State) ->
  error_logger:error_msg("Got info message: ~p", [Info]),
  {noreply, State}.


% Terminate:
terminate(_Reason, State) ->
  ok.


code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------


%% ------------------------------------------------------------------
%% Tests
%% ------------------------------------------------------------------

-ifdef(TEST).

%   erlymock:start(),
%   erlymock:strict(chord_tcp, rpc_get_closest_preceding_finger_and_succ, [Key, get_successor(State)], [{return, RpcReturn}]),
%   erlymock:replay(), 
%   % Methods invoking whatever.
%   erlymock:verify().

-endif.
