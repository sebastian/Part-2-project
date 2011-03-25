%%%-------------------------------------------------------------------
%%% @author Sebastian Probst Eide
%%% @copyright (C) 2011, Kleio
%%% @doc
%%%
%%% @end
%%% Created : 2011-03-24 10:36:21.112725
%%%-------------------------------------------------------------------
-module(link_rec_db).

-behaviour(gen_server).

%% API
-export([start/0,
         create_entries/0,
         for_name/1]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-define(SERVER, ?MODULE).
-define(LINK_NAME_CHUNKS, 3).

-record(state, {
    db
  }).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%--------------------------------------------------------------------
%% @doc
%% Adds entries to the database
%%--------------------------------------------------------------------
create_entries() ->
  {ok, File} = file:open("/Users/seb/Downloads/facebook-names-original.txt", read),
  spawn(fun() ->
    insert_lines(File)
  end),
  working.

%%--------------------------------------------------------------------
%% @doc
%% Prints how many link records there are for a given name
%%--------------------------------------------------------------------
for_name(Name) ->
  lookup_link_records(Name, 1, []).
lookup_link_records(Name, End, LR) when End =< length(Name) ->
  Part = string:sub_string(Name, 1, End),
  LinkRecords = name_subsets(Part),
  NewLinkRecords = LinkRecords -- LR,
  % Finds how many link records there are for a given set of fragments
  Num = lists:foldl(fun(Frag, Acc) ->
    gen_server:call(?SERVER, {num_entries_for_link, Frag}) + Acc
  end, 0, NewLinkRecords),
  io:format("~p : ~p new link records~n", [Part, Num]),
  lookup_link_records(Name, End+1, NewLinkRecords ++ LR);
lookup_link_records(_Name, _End, _LR) ->
  ok.

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([]) ->
  {ok, C} = pgsql:connect("localhost", "postgres", "sebastian", [{database, "names"}]),
  {ok, #state{db = C}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call(get_db, _From, #state{db = Db} = State) ->
  {reply, Db, State};

handle_call({num_entries_for_link, Link}, _From, #state{db = Db} = State) ->
  {ok,_,[{Num}]} = pgsql:equery(Db, "select count(*) from links where link = $1", [Link]),
  {reply, Num, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast({add_entries, Entries}, #state{db = Db} = State) ->
  [pgsql:equery(Db, "insert into links (link, name) values ($1, $2)", [Link, Name]) || {Link, Name} <- Entries],
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info(_Info, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
  ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

insert_lines(File) -> 
  Db = gen_server:call(?SERVER, get_db),
  insert_lines(File, 0, Db).
insert_lines(_File, Count, _Db) when Count > 1000000 -> ok;
insert_lines(File, Count, Db) ->
  case Count rem 10000 of
    0 -> io:format("At item ~p~n", [Count]);
    _ -> ok
  end,
  case file:read_line(File) of
    eof ->
      ok;
    {ok, Name} ->
      NameSubsets = name_subsets(Name),
      [pgsql:equery(Db, "insert into links (link, name) values ($1, $2)", [Link, Name]) || Link <- NameSubsets],
      insert_lines(File, Count+1, Db)
  end.

name_subsets(Name) ->
  ListName = string_to_list(downcase_str(Name)),
  Words = lists:foldl(fun(W, A) -> get_parts(W,A) end, [], string:tokens(ListName, " ")),
  lists:map(fun(E) -> list_to_bitstring(E) end, Words).

get_parts(Name, Acc) ->
get_parts(Name, ?LINK_NAME_CHUNKS, Acc).
get_parts(Name, Place, Acc) ->
  case (Place < string:len(Name)) of
    true -> get_parts(Name, Place + ?LINK_NAME_CHUNKS, [string:left(Name, Place) | Acc]);
    false -> 
      [Name | Acc]
  end.

string_to_list(String) when is_bitstring(String) -> bitstring_to_list(String);
string_to_list(String) -> String.

downcase_str('undefined') ->
  'undefined';
downcase_str(String) ->
  ListString = string_to_list(String),
  LowerCaseStr = string:to_lower(ListString),
  list_to_bitstring(LowerCaseStr).
