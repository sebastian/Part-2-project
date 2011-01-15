-module(pastry_app).
-behaviour(gen_server).

-define(SERVER, ?MODULE).
-define(TIMEOUT, 2000).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-include("../fs.hrl").
-include("pastry.hrl").
-import(lists, [reverse/1]).
-import(pastry, [value_of_key/2, max_for_keylength/2]).

%% ------------------------------------------------------------------
%% Public API
%% ------------------------------------------------------------------

-export([
    set/2,
    lookup/1
  ]).
% For pastry
-export([
    deliver/2,
    forward/3,
    new_leaves/1,
    pastry_init/2
  ]).
% For gen_server
-export([
    start/1,
    start_link/1,
    stop/0
  ]).
% For pastry_tcp
-export([bulk_delivery/1]).

%% ------------------------------------------------------------------
%% Gen_server exports
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
%% PRIVATE API Function Exports and definitions
%% ------------------------------------------------------------------

-record(pastry_app_state, {
    leaf_set = {[],[]},
    self,
    b
  }).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

% Used by 3rd party apps --------------------------------------------

%% @doc: gets a value from the chord network
-spec(lookup/1::(Key::key()) -> [#entry{}]).
lookup(Key) ->
  gen_server:call(?SERVER, {lookup, Key}).

%% @doc: stores a value in the chord network
-spec(set/2::(Key::key(), Entry::#entry{}) -> ok).
set(Key, Entry) ->
  gen_server:call(?SERVER, {set, Key, Entry}).

% Used by supervisor ------------------------------------------------

start(Args) ->
  gen_server:start({local, ?SERVER}, ?MODULE, Args, []).

start_link(Args) ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, Args, []).

stop() ->
  gen_server:call(?MODULE, stop).

pastry_init(Node, B) ->
  gen_server:call(?SERVER, {init_with_data, Node, B}).

% Used by pastry_core -----------------------------------------------

% @doc: Called by pastry when the current node is the numerically
% closest to the key among all live nodes.
-spec(deliver/2::(_, pastry_key()) -> ok).
deliver({join, Node}, _Key) ->
  io:format("Received a join message. Welcome stranger~n"),
  % Hurrah, there is a new node in the network.
  % We have to send it our leaf set, and 
  % wholeheartedly welcome it!
  pastry:welcome(Node);

deliver({lookup_key, Key, Node, Ref}, _Key) ->
  pastry_tcp:send_msg({data, Ref, datastore:lookup(Key)}, Node);

deliver({set, Key, Entry}, _Key) ->
  datastore:set(Key, Entry);

deliver(Msg, _Key) ->
  error_logger:error_msg("Unknown message delivered: ~p~n", [Msg]),
  ok.

% @doc: Called by Pastry before a message is forwarded to NextId.
% The message and the NextNode can be changed. 
% The message is not forwarded if the returned NextNode is null.
-spec(forward/3::(Msg::#entry{}, Key::pastry_key(), NextNode::#node{})
  -> {#entry{}, #node{}} | {_, null}).
forward(Msg, _Key, NextNode) ->
  {Msg, NextNode}.

% @doc: Called by pastry whenever there is a change in the local node's leaf set.
-spec(new_leaves/1::({[#node{}], [#node{}]}) -> ok).
new_leaves(LeafSet) ->
  gen_server:cast(?SERVER, {new_leaves, LeafSet}),
  ok.

% Used by pastry_tcp ------------------------------------------------

bulk_delivery(Entries) ->
  [datastore:set(Entry#entry.key, Entry) || Entry <- Entries].

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(_Args) -> 
  {ok, #pastry_app_state{}}.

% Call:
handle_call({set, Key, Entry}, _From, #pastry_app_state{b = B} = State) ->
  PastryKey = utilities:number_to_pastry_key_with_b(Key, B),
  pastry:route({set, Key, Entry}, PastryKey),
  {reply, ok, State};

handle_call({lookup, Key}, From, #pastry_app_state{b = B} = State) ->
  spawn(fun() ->
    PastryKey = utilities:number_to_pastry_key_with_b(Key, B),
    Ref = make_ref(),
    pastry:route(PastryKey, {lookup_key, Key, pastry:get_self(), {self(), Ref}}),
    ReturnValue = receive
      {data, Ref, Data} -> Data
    after ?TIMEOUT -> {error, timeout}
    end,
    gen_server:reply(From, ReturnValue)
  end),
  {noreply, State};

handle_call({init_with_data, Self, B}, _From, State) ->
  {reply, ok, State#pastry_app_state{self = Self, b = B}};

handle_call(stop, _From, State) ->
  {stop, normal, ok, State};

handle_call(Msg, _From, State) ->
  error_logger:error_msg("Received unknown call: ~p", [Msg]),
  {reply, unknown_message, State}.

% Casts:
handle_cast({new_leaves, _LeafSet}, State) ->
  io:format("pastry_app received new leaves~n"),
  {noreply, State};

handle_cast(Msg, State) ->
  error_logger:error_msg("received unknown cast: ~p", [Msg]),
  {noreply, State}.

% Info:
handle_info(Info, State) ->
  error_logger:error_msg("Got info message: ~p", [Info]),
  {noreply, State}.

% Terminate:
terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%% ------------------------------------------------------------------
%% Private functions
%% ------------------------------------------------------------------

ownership_range(#pastry_app_state{leaf_set = {[], []}}) -> all;
ownership_range(#pastry_app_state{b = B, self = #node{key = SelfKey}, leaf_set = {LSS, []}}) -> 
  LSSKey = (hd(reverse(LSS)))#node.key,
  {half_between_keys(LSSKey, SelfKey, B), half_between_keys(SelfKey, LSSKey, B)};
ownership_range(#pastry_app_state{b = B, self = #node{key = SelfKey}, leaf_set = {[], LSG}}) -> 
  LSGKey = (hd(LSG))#node.key,
  {half_between_keys(LSGKey, SelfKey, B), half_between_keys(SelfKey, LSGKey, B)};
ownership_range(#pastry_app_state{self = #node{key = SelfKey}, b = B, leaf_set = {LSS, LSG}}) ->
  LSSKey = (hd(reverse(LSS)))#node.key,
  LSGKey = (hd(LSG))#node.key,
  {half_between_keys(LSSKey, SelfKey, B), half_between_keys(SelfKey, LSGKey, B)}.
half_between_keys(Key1, Key2, B) ->
  MaxVal = max_for_keylength(Key1, B),
  HM = MaxVal bsr 1 + 1,
  VK1 = value_of_key(Key1, B), VK2 = value_of_key(Key2, B),
  HP = VK1 + VK2 bsr 1,
  case Key1 < Key2 of
    true -> HP;
    false -> 
      case HM > HP of
        true -> HP + HM;
        false -> HP - HM
      end
  end.

deliver_in_bulk(Entries, Node) ->
  pastry_tcp:deliver_in_bulk(Entries, Node).

%% ------------------------------------------------------------------
%% Tests
%% ------------------------------------------------------------------

-ifdef(TEST).

test_state() ->
  Self = #node{key = [1,0]},
  LesserNode = #node{key = [0,0]},
  GreaterNode = #node{key = [2,0]},
  #pastry_app_state{b = 2, self = Self, leaf_set = {[LesserNode], [GreaterNode]}}.

ownership_range_test() ->
  State = test_state(),
  {2,6} = ownership_range(State),
  all = ownership_range(State#pastry_app_state{leaf_set = {[],[]}}),
  {LSS, LSG} = State#pastry_app_state.leaf_set,
  {14, 6} = ownership_range(State#pastry_app_state{leaf_set = {[], LSG}}),
  {2, 10} = ownership_range(State#pastry_app_state{leaf_set = {LSS, []}}),
  NewLesser = #node{key = [3,0]},
  {0, 6} = ownership_range(State#pastry_app_state{leaf_set = {[NewLesser], LSG}}).


%   erlymock:start(),
%   erlymock:strict(chord_tcp, rpc_get_closest_preceding_finger_and_succ, [Key, get_successor(State)], [{return, RpcReturn}]),
%   erlymock:replay(), 
%   % Methods invoking whatever.
%   erlymock:verify().

-endif.
