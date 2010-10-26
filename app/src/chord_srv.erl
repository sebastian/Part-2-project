-module(chord_srv).
-behaviour(gen_server).
-define(SERVER, ?MODULE).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-include("fs.hrl").

-record(finger_entry, {
    start :: integer(),
    interval :: {integer(), integer()},
    node :: integer()
  }).
-record(chord_state, {
    port = 4000 :: integer(),
    id :: key(),
    % The finger list is in inverse order from what is described
    % in the Chord paper. This is due to implementation reasons.
    fingers = [] :: [#finger_entry{}],
    successor :: key()
  }).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/1]).
-export([get/1, set/2]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link(Args) ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, Args, []).

-spec(get/1::(Key::key()) -> [#entry{}]).
get(Key) ->
  gen_server:call({get, Key}).

-spec(set/2::(Key::key(), Entry::#entry{}) -> ok | {error, server}).
set(Key, Entry) ->
  gen_server:call({set, Key, Entry}).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(Args) -> 
  Port = proplists:get_value(port, Args, 4000),
  NodeId = utilities:key_for_node(utilities:get_ip(), Port),
  State = #chord_state{port = Port, id = NodeId },
  {ok, State}.

handle_call(stop, _From, State) ->
  {stop, stop_signal, ok, State};

handle_call({get, _Key}, _From, State) ->
  % Do lookup
  Results = some_call,
  {reply, Results, State};

handle_call({set, _Key, _Entry}, _From, State) ->
  % Store value in network
  {reply, ok, State}.

handle_cast(_Msg, State) ->
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

-spec(closest_preceding_finger/2::(Key::key(), 
    State::#chord_state{}) -> key()).
closest_preceding_finger(Key, State) ->
  closest_preceding_finger(Key, 
    State#chord_state.fingers,
    State#chord_state.id).

-spec(closest_preceding_finger/3::(Key::key(), 
    [#finger_entry{}],
    CurrentId::key()) -> key()).
closest_preceding_finger(_Key, [], CurrentId) -> CurrentId;
closest_preceding_finger(Key, [Finger|Fingers], CurrentId) ->
  NodeId = Finger#finger_entry.node,
  case ((CurrentId < NodeId) and (NodeId < Key)) of
    true -> 
      NodeId;
    false -> closest_preceding_finger(Key, Fingers, CurrentId)
  end.


%% ------------------------------------------------------------------
%% Tests
%% ------------------------------------------------------------------

-ifdef(TEST).

n2b(Num) -> term_to_binary(Num).
test_get_state() ->
  #chord_state{
    fingers = [#finger_entry{start = n2b(4), interval = {n2b(4),n2b(0)}, node = n2b(0)},
              #finger_entry{start = n2b(2), interval = {n2b(2),n2b(4)}, node = n2b(3)},
              #finger_entry{start = n2b(1), interval = {n2b(1),n2b(2)}, node = n2b(1)}],
    id = n2b(0)
  }.

find_closest_preceding_finger_test() ->
  ?assertEqual(n2b(0), closest_preceding_finger(n2b(0), test_get_state())),
  ?assertEqual(n2b(0), closest_preceding_finger(n2b(1), test_get_state())),
  ?assertEqual(n2b(1), closest_preceding_finger(n2b(2), test_get_state())),
  ?assertEqual(n2b(1), closest_preceding_finger(n2b(3), test_get_state())),
  ?assertEqual(n2b(3), closest_preceding_finger(n2b(4), test_get_state())),
  ?assertEqual(n2b(3), closest_preceding_finger(n2b(5), test_get_state())),
  ?assertEqual(n2b(3), closest_preceding_finger(n2b(6), test_get_state())),
  ?assertEqual(n2b(3), closest_preceding_finger(n2b(7), test_get_state())).


-endif.
