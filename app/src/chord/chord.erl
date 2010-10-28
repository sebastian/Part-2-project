-module(chord).
-behaviour(gen_server).
-define(SERVER, ?MODULE).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-include("../fs.hrl").

-record(node, {
    ip :: ip(),
    port :: port_number(),
    key :: key()
  }).
-record(finger_entry, {
    start :: key(),
    interval :: {key(), key()},
    node :: #node{}
  }).
-record(chord_state, {
    self :: #node{},
    successor :: #node{},

    % The finger list is in inverse order from what is described
    % in the Chord paper. This is due to implementation reasons,
    % since the method closest_preceding_finger, which is the
    % only method using the finger table directly, traverses
    % it from the back to the front.
    fingers = [] :: [#finger_entry{}]
  }).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/0, start/0, stop/0]).
-export([get/1, set/2, preceding_finger/1]).

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

-spec(set_state/1::(#chord_state{}) -> ok).
set_state(NewState) ->
  gen_server:call(chord, {set_state, NewState}).

-spec(get/1::(Key::key()) -> [#entry{}]).
get(Key) ->
  gen_server:call(chord, {get, Key}).

-spec(set/2::(Key::key(), Entry::#entry{}) -> ok | {error, server}).
set(Key, Entry) ->
  gen_server:call(chord, {set, Key, Entry}).

-spec(preceding_finger/1::(Key::key()) -> {ok, {#node{}, key()}}).
preceding_finger(Key) ->
  Finger = gen_server:call(chord, {lookup_preceding_finger, Key}),
  Succ = gen_server:call(chord, get_successor),
  {ok, {Finger, Succ#node.key}}.

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(Args) -> 
  Port = proplists:get_value(port, Args, 4000),
  NodeId = utilities:key_for_node(utilities:get_ip(), Port),
  State = #chord_state{self =
    #node{
      ip = utilities:get_ip(),
      port = Port, 
      key = NodeId 
    }
  },
  {ok, State}.

handle_call({set_state, NewState}, _From, _State) ->
  {reply, ok, NewState};

handle_call(stop, _From, State) ->
  {stop, normal, ok, State};

handle_call({get, _Key}, _From, State) ->
  % Do lookup
  Results = some_call,
  {reply, Results, State};

handle_call({set, _Key, _Entry}, _From, State) ->
  % Store value in network
  {reply, ok, State};

handle_call({lookup_preceding_finger, Key}, _From, State) ->
  {reply, closest_preceding_finger(Key, State), State};

handle_call(get_successor, _From, #chord_state{successor = Succ} = State) ->
  {reply, Succ, State}.

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

-spec(find_predecessor/2::(Key::key(), #chord_state{} | #node{})
    -> {ok, key()} | {error, instance}).
find_predecessor(Key, #chord_state{self = #node{key = NodeId}, successor = Succ}) ->
  case ((Key > NodeId) and (Key =< Succ#node.key)) of
    true  -> {ok, NodeId};
    false -> find_predecessor(Key, Succ)
  end;

find_predecessor(Key, #node{key = NKey, ip = NIp, port = NPort}) ->
  case chord_tcp:get_closest_preceding_finger(Key, NIp, NPort) of
    {ok, {NextFinger, NSucc}} ->
      case ((Key > NKey) and (Key =< NSucc)) of
        true  -> {ok, NKey};
        false -> find_predecessor(Key, NextFinger)
      end;
    {error, Reason} ->
      {error, Reason}
  end.


-spec(closest_preceding_finger/2::(Key::key(), 
    State::#chord_state{}) -> #node{}).
closest_preceding_finger(Key, State) ->
  closest_preceding_finger(Key, 
    State#chord_state.fingers,
    State#chord_state.self).

-spec(closest_preceding_finger/3::(Key::key(), 
    [#finger_entry{}],
    CurrentNode::key()) -> key()).
closest_preceding_finger(_Key, [], CurrentNode) -> CurrentNode;
closest_preceding_finger(Key, [Finger|Fingers], CurrentNode) ->
  Node = Finger#finger_entry.node,
  NodeId = Node#node.key,
  case ((CurrentNode#node.key < NodeId) and (NodeId < Key)) of
    true -> 
      Node;
    false -> closest_preceding_finger(Key, Fingers, CurrentNode)
  end.


%% ------------------------------------------------------------------
%% Tests
%% ------------------------------------------------------------------

-ifdef(TEST).

n2b(Num) -> term_to_binary(Num).
nForKey(Key) -> #node{key = n2b(Key)}.
test_get_run_state() ->
  #chord_state{
    fingers = [#finger_entry{start = n2b(4), interval = {n2b(4),n2b(0)}, node = nForKey(0)},
              #finger_entry{start = n2b(2), interval = {n2b(2),n2b(4)}, node = nForKey(3)},
              #finger_entry{start = n2b(1), interval = {n2b(1),n2b(2)}, node = nForKey(1)}],
    self = #node{key = n2b(1)},
    successor = #node{ip = {127,0,0,1}, port = 9234, key = n2b(3)}
  }.
test_get_state() ->
  #chord_state{
    fingers = [#finger_entry{start = n2b(4), interval = {n2b(4),n2b(0)}, node = nForKey(0)},
              #finger_entry{start = n2b(2), interval = {n2b(2),n2b(4)}, node = nForKey(3)},
              #finger_entry{start = n2b(1), interval = {n2b(1),n2b(2)}, node = nForKey(1)}],
    self = #node{key = n2b(0)},
    successor = #node{ip = {127,0,0,1}, port = 9234, key = n2b(1)}
  }.

find_closest_preceding_finger_test() ->
  ?assertEqual(nForKey(0), closest_preceding_finger(n2b(0), test_get_state())),
  ?assertEqual(nForKey(0), closest_preceding_finger(n2b(1), test_get_state())),
  ?assertEqual(nForKey(1), closest_preceding_finger(n2b(2), test_get_state())),
  ?assertEqual(nForKey(1), closest_preceding_finger(n2b(3), test_get_state())),
  ?assertEqual(nForKey(3), closest_preceding_finger(n2b(4), test_get_state())),
  ?assertEqual(nForKey(3), closest_preceding_finger(n2b(5), test_get_state())),
  ?assertEqual(nForKey(3), closest_preceding_finger(n2b(6), test_get_state())),
  ?assertEqual(nForKey(3), closest_preceding_finger(n2b(7), test_get_state())).

find_predecessor_on_same_node_test() ->
  State = test_get_state(),
  ?assertEqual({ok, (State#chord_state.self)#node.key}, find_predecessor(n2b(1), State)).

find_predecessor_on_other_node_test() ->
  chord_tcp:start(),
  start(), 
  set_state(test_get_run_state()),

  ?assertEqual({ok, n2b(1)}, find_predecessor(n2b(2), test_get_state())),
    
  fun(_) -> chord:stop(), chord_tcp:stop() end.

-endif.
