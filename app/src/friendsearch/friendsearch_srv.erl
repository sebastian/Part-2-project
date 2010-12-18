%% @author Sebastian Probst Eide
%% @doc DataStore server module for storing and retrieving values.
-module(friendsearch_srv).
-behaviour(gen_server).
-define(SERVER, ?MODULE).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-include("../fs.hrl").

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([list/0, add/1, delete/1, find/1]).
-export([start_link/1, start/1, stop/0]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, terminate/2, code_change/3]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start(Dht) ->
  gen_server:start({local, ?SERVER}, ?MODULE, [Dht], []).

start_link(Dht) ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [Dht], []).

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
-spec(add/1::(Entry::#person{}) -> ok).
add(Entry) ->
  gen_server:call(?MODULE, {add, Entry}).

%% @doc: removes an entry from the list of entries maintained by the local node. 
%% The entry isn't removed from the global index before it times out.`
-spec(delete/1::(_) -> ok).
delete(Key) ->
  gen_server:call(?MODULE, {delete, Key}).

%% @doc: queries the storage network for entries matching some find.
-spec(find/1::(Query::bitstring()) -> [#person{}]).
find(Query) ->
  gen_server:call(?MODULE, {find, Query}).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(Dht) -> 
  State = friendsearch:init(Dht),
  {ok, State}.

%% Call:
handle_call(list, _From, State) ->
  {reply, friendsearch:list(State), State};

handle_call({add, Entry}, _From, State) ->
  {reply, ok, friendsearch:add(Entry, State)};

handle_call({delete, Key}, _From, State) ->
  {reply, ok, friendsearch:delete(Key, State)};

handle_call({find, Query}, _From, State) ->
  {reply, friendsearch:find(Query, State), State};

handle_call(stop, _From, State) ->
  {stop, normal, ok, State}.

terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%% ------------------------------------------------------------------
%% Tests
%% ------------------------------------------------------------------

-ifdef(TEST).

-endif.
