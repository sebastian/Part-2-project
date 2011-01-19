%% @author Sebastian Probst Eide
%% @doc DataStore server module for storing and retrieving values.
-module(friendsearch_srv).
-behaviour(gen_server).
-define(SERVER, ?MODULE).

% Every 30 seconds we check if there are records about to time out
-define(KEEP_ALIVE_INTERVAL, 30*1000).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-include("../fs.hrl").

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([list/0, add/1, delete/1, find/1, keep_alive/0]).
-export([start_link/0, start/1, stop/0]).
-export([set_dht/1]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_cast/2, handle_call/3, terminate/2, code_change/3, handle_info/2]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start(Args) ->
  gen_server:start({local, ?SERVER}, ?MODULE, Args, []).

start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

stop() ->
  gen_server:call(?SERVER, stop).

%% ------------------------------------------------------------------
%% Public API
%% ------------------------------------------------------------------

%% @doc: lists all entries maintained by the local node.
-spec(list/0::() -> [#person{}]).
list() ->
  gen_server:call(?MODULE, list).

%% @doc: adds a new entry to the list of entries maintained by the local node.
-spec(add/1::(Entry::#person{}) -> none()).
add(Entry) ->
  gen_server:cast(?MODULE, {add, Entry}).

%% @doc: removes an entry from the list of entries maintained by the local node. 
%% The entry isn't removed from the global index before it times out.`
-spec(delete/1::(_) -> ok).
delete(Key) ->
  gen_server:call(?MODULE, {delete, Key}).

%% @doc: queries the storage network for entries matching some find.
-spec(find/1::(Query::bitstring()) -> [#person{}]).
find(Query) ->
  io:format("Performing: find for ~p~n", [Query]),
  gen_server:call(?MODULE, {find, Query}).

%% @doc: called by the timer module to ensure that the local entries are
%% kept alive in the Dht.
-spec(keep_alive/0::() -> none()).
keep_alive() ->
  gen_server:cast(?MODULE, keep_alive).

set_dht(Dht) ->
  gen_server:call(?MODULE, {set_dht, Dht}).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(_Args) -> 
  State = friendsearch:init(),
  {ok, TimerRef} = 
      timer:apply_interval(?KEEP_ALIVE_INTERVAL, ?MODULE, keep_alive, []),
  {ok, State#friendsearch_state{timerRefKeepAlive = TimerRef}}.

%% Call:
handle_call(list, _From, State) ->
  {reply, friendsearch:list(State), State};

handle_call({delete, Key}, _From, State) ->
  {reply, ok, friendsearch:delete(Key, State)};

handle_call({find, Query}, _From, State) ->
  {reply, friendsearch:find(Query, State), State};

handle_call({set_dht, {Mode,Pid}}, _From, State) ->
  io:format("Setting Dht: ~p with pid: ~p~n", [Mode, Pid]),
  {reply, ok, State#friendsearch_state{dht_pid = Pid, dht = Mode}};

handle_call(stop, _From, State) ->
  {stop, normal, ok, State}.

handle_cast(keep_alive, State) ->
  {noreply, friendsearch:keep_alive(State)};

handle_cast({add, Entry}, State) ->
  {noreply, friendsearch:add(Entry, State)}.

handle_info(_Msg, State) ->
  {noreply, State}.

terminate(_Reason, State) ->
  timer:cancel(State#friendsearch_state.timerRefKeepAlive),
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%% ------------------------------------------------------------------
%% Tests
%% ------------------------------------------------------------------

-ifdef(TEST).

add_list_test() ->
  {ok, Pid} = test_dht:start(),
  start([{dht, test_dht}]),
  set_dht({test_dht, Pid}),
  Person = test_utils:test_person_sebastianA(),
  ?assertNot(lists:member(Person, list())),
  add(Person),
  ?assert(lists:member(Person, list())),
  stop(),
  test_dht:stop(Pid).

find_test() ->
  {ok, Pid} = test_dht:start(),
  start([{dht, test_dht}]),
  set_dht({test_dht, Pid}),
  Person = test_utils:test_person_sebastianA(),
  PersonName = Person#person.name,
  ?assertEqual([], find(PersonName)),
  add(Person),
  ?assertEqual([Person], find(PersonName)),
  stop(),
  test_dht:stop(Pid).

find_by_surname_test() ->
  {ok, Pid} = test_dht:start(),
  start([{dht, test_dht}]),
  set_dht({test_dht, Pid}),
  Person = test_utils:test_person_sebastianA(),
  Surname = <<"Eide">>,
  ?assertEqual([], find(Surname)),
  add(Person),
  ?assertEqual([Person], find(Surname)),
  stop(),
  test_dht:stop(Pid).

find_multiple_test() ->
  {ok, Pid} = test_dht:start(),
  start([{dht, test_dht}]),
  set_dht({test_dht, Pid}),

  % Name: Sebastian Probst Eide
  Sebastian = test_utils:test_person_sebastianA(),

  % Name: Johan Wilhelm Eide
  Johan = (test_utils:test_person_sebastianA())#person{name = "Johan Wilhelm Eide"},

  % The query should return Sebastian and Johan, in that order
  Query = <<"Sebastian Eide">>,

  ?assertEqual([], find(Query)),

  add(Sebastian),
  add(Johan),

  ?assertEqual([Sebastian, Johan], find(Query)),

  stop(),
  test_dht:stop(Pid).

-endif.
