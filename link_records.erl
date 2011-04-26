-module(link_records).
-compile([export_all]).

-define(TABLE, links).

start() ->
  ets:new(?TABLE, [duplicate_bag, public, named_table]).
  
stop() ->
  ets:delete_all_objects(?TABLE).

setup(LinkLength) ->
  {ok, File} = file:open("names.txt", [read]),
  Router = setup_router(LinkLength),
  read_file(File, Router).

read_file(File, Router) ->
  read_file(File, Router, 0).
read_file(_File, Router, Count) when Count > 120000000 ->
  io:format("Quitting due to high count~n"),
  Router ! stop;
read_file(File, Router, Count) when Count rem 2 =:= 1 ->
  read_file(File, Router, Count+1);
read_file(File, Router, Count) ->
  case Count rem 100000 of
    0 -> io:format("Have read ~p names~n", [Count]);
    _ -> ok
  end,
  case file:read_line(File) of
    {ok, Data} ->
      Router ! Data,
      read_file(File, Router, Count+1);
    eof -> 
      Router ! stop,
      done
  end.

lookup(Name, LL) ->
  io:format("Looking up ~p:~n", [Name]),
  lookup_part(Name, 1, [], LL).

lookup_part(Name, UpTo, _SeenKeys, _LL) when length(Name) < UpTo ->
  io:format("~n");
lookup_part(Name, UpTo, SeenKeys, LL) ->
  SubString = string:sub_string(Name, 1, UpTo),
  Keys = name_subsets(SubString, LL) -- SeenKeys,
  {ForSubString, TotalLinks} = lists:foldl(fun(Key, {ForString, Total}) ->
    case ets:lookup(?TABLE, Key) of
      {error, Reason} ->
        io:format("Got error: ~p~n", [Reason]);
      Data ->
        Matches = length([N || {_, N} <- Data, N =:= downcase_str(Name)]),
        {ForString + Matches, Total + length(Data)}
    end
  end, {0,0}, Keys),
  io:format("~p: ~p links (~p matches for name)~n", [SubString, TotalLinks, ForSubString]),
  lookup_part(Name, UpTo+1, name_subsets(SubString, LL), LL).

setup_router(LinkLength) ->
  Slaves = [spawn(fun() -> slave([], LinkLength) end) || _ <- lists:seq(0,100)],
  spawn(fun() -> router(Slaves) end).

router([Next|Slaves]) ->
  receive
    stop -> 
      [S ! stop || S <- [Next|Slaves]],
      ok;
    Name ->
      Next ! Name,
      router(Slaves ++ [Next])
  end.

slave(Names, LinkLength) when length(Names) > 100 ->
  save_names(Names),
  slave([], LinkLength);
slave(Names, LinkLength) ->
  receive
    stop ->
      save_names(Names),
      ok;
    Name ->
      % Work with name
      TrimmedName = downcase_str(string:left(Name, string:len(Name)-1)),
      slave(add_links_for_name(TrimmedName, Names, LinkLength), LinkLength)
  end.

save_names(Names) ->
  ets:insert(?TABLE, Names).

add_links_for_name(Name, Links, LinkLength) ->
  Keys = name_subsets(Name, LinkLength),
  lists:flatten([{K, downcase_str(Name)} || K <- Keys] ++ [Links]).

%-----------------------------------------------------
% Supporting functions
%-----------------------------------------------------

name_subsets(Name, LL) ->
  ListName = string_to_list(downcase_str(Name)),
  Words = lists:foldl(fun(W, A) -> get_parts(W,A,LL) end, [], 
      string:tokens(ListName, " ")),
  lists:map(fun(E) -> list_to_bitstring(E) end, Words).

get_parts(Name, Acc, LL) ->
  get_parts(Name, LL, LL, Acc).
get_parts(Name, Place, LL, Acc) ->
  case (Place < string:len(Name)) of
    true -> get_parts(Name, Place + LL, LL, [string:left(Name, Place) | Acc]);
    false -> 
      [Name | Acc]
  end.

-spec(downcase_str/1::(binary() | 'undefined') -> binary()).
downcase_str('undefined') ->
  'undefined';
downcase_str(String) ->
  ListString = string_to_list(String),
  LowerCaseStr = string:to_lower(ListString),
  list_to_bitstring(LowerCaseStr).

string_to_list(String) when is_bitstring(String) -> bitstring_to_list(String);
string_to_list(String) -> String.
