%%%-------------------------------------------------------------------
%%% @author Sebastian Probst Eide
%%% @copyright (C) 2011, Kleio
%%% @doc
%%%
%%% @end
%%% Created : 2011-03-23 10:01:01.965103
%%%-------------------------------------------------------------------
-module(ets_lr).

-define(LINK_NAME_CHUNKS, 3).

%% API
-export([
    start/0,
    stop/0,
    create_table/0,
    link_records/1
  ]).

start() ->
  io:format("creating ets table~n"),
  Opts = [
    duplicate_bag,
    public,
    named_table,
    {write_concurrency,true}
  ],
  case ets:new(?MODULE, Opts) of
    {error, Reason} ->
      io:format("Cannot open dets file for reason: ~p~n", [Reason]),
      false;
    _TableName ->
      true
  end.

stop() ->
  ets:close(?MODULE).


% -------------------------------------------------------------
% Link record for a given name
% -------------------------------------------------------------
link_records(Name) ->
  lookup_link_records(Name, 1, []).
lookup_link_records(Name, End, LR) when End =< length(Name) ->
  Part = string:sub_string(Name, 1, End),
  LinkRecords = name_subsets(Part),
  NewLinkRecords = LinkRecords -- LR,
  Num = lists:foldl(fun(Frag, Acc) ->
    % case dets:lookup(?MODULE, Frag) of
    case ets:lookup(?MODULE, Frag) of
      {error, _Reason} -> Acc;
      Res -> length(Res) + Acc
    end
  end, 0, NewLinkRecords),
  io:format("~p : ~p new link records~n", [Part, Num]),
  lookup_link_records(Name, End+1, NewLinkRecords ++ LR);
lookup_link_records(_Name, _End, _LR) ->
  ok.

% -------------------------------------------------------------
% Create the table with the link records
% -------------------------------------------------------------
create_table() ->
  {ok, File} = file:open("/Users/seb/Downloads/facebook-names-original.txt", read),
  io:format("Starting to read~n"),
  ok = insert_lines(File),
  io:format("Finished reading file~n").

insert_lines(File) -> insert_lines(File, 0, []).
insert_lines(File, Count, Acc) when length(Acc) > 100000 ->
  io:format("Writing"),
  ets:insert(?MODULE, Acc),
  io:format("...done at name count (~p)~n", [Count]),
  insert_lines(File, Count, []);
insert_lines(File, Count, Acc) ->
  case Count rem 100000 of
    0 -> io:format("At name number ~p~n", [Count]);
    _ -> ok
  end,
  case file:read_line(File) of
    eof ->
      ok;
    {ok, Name} ->
      NameSubsets = name_subsets(Name),
      NewAcc = [{Fragment, Name} || Fragment <- NameSubsets] ++ Acc,
      insert_lines(File, Count+1, NewAcc)
  end.

% -------------------------------------------------------------
% Internal functions
% -------------------------------------------------------------
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
