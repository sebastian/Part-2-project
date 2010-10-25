-module(dht_pastry_server).
-behaviour(gen_server).

-include("records.hrl").

% Chord specific configuration parameters:
% ParamB should be a number that evenly divides 160.
%     It affects the number of rows in the routing table
%     and how many records are kept in each row.
-define(ParamB, 4).

% Gen server functionality
-export([init/1, handle_call/3, terminate/2, code_change/3]).
% gen_server functionality not being used
-export([handle_cast/2, handle_info/2]).

% Public exported DHT api
-export([get/1, set/2]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Public API
%%

-spec(get/1::(Key::key()) -> [#entry{}]).
get(Key) ->
  gen_server:call({get, Key}).

-spec(set/2::(Key::key(), Entry::#entry{}) -> ok | {error, server}).
set(Key, Entry) ->
  gen_server:call({set, Key, Entry}).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Gen server functionality
%%

%% Invoked by start and start_link to start the server
init(_Args) -> 
  % Check that the B parameter is valid.
  0 = 160 rem ?ParamB,

  % initialize DHT server
  State = some_state,
  {ok, State}.

%% Handling synchronous calls

% Terminates the server
handle_call(stop, _From, State) ->
  {stop, stop_signal, ok, State};

handle_call({get, _Key}, _From, State) ->
  % Do lookup
  Results = some_call,
  {reply, Results, State};

handle_call({set, _Key, _Entry}, _From, State) ->
  % Store value in network
  {reply, ok, State}.


%% Server doesn't handle async request.
handle_cast(_Msg, State) ->
  {noreply, State}.

%% Server doens't handle info messages.
handle_info(_Info, State) ->
  {noreply, State}.

%% Termination of the server
terminate(_Reason, _State) ->
  % Do state cleanup as needed
  ok.

%% Called upon changing of the code
code_change(_OldVsn, State, _Extra) ->
  NewState = State,
  {ok, NewState}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Private API
%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Tests
%%
