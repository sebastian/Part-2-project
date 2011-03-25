%%%-------------------------------------------------------------------
%%% @author Sebastian Probst Eide
%%% @copyright (C) 2011, Kleio
%%% @doc
%%%
%%% @end
%%% Created : 2011-03-23 10:01:01.965103
%%%-------------------------------------------------------------------
-module(num_link_rec).

-define(LINK_NAME_CHUNKS, 3).

-include("ct.hrl").

%% API
-export([
    start/0,
    stop/0,
    create_table/0,
    link_records/1
  ]).

start() ->
  File = "/Users/seb/Documents/Part2Project/Dissertation/erl/names.db",
  % io:format("opening dets file at ~p~n", [File]),
  io:format("opening ets table~n"),
%   Opts = [
%     {estimated_no_objects, 100000000},
%     {type, duplicate_bag}
%   ],
  Opts = [
    duplicate_bag,
    public,
    named_table,
    {write_concurrency,true}
  ],
  % case dets:open_file(?MODULE, Opts) of
  case ets:new(?MODULE, Opts) of
    {ok, ?MODULE} ->
      true;
    {error, Reason} ->
      io:format("Cannot open dets file for reason: ~p~n", [Reason]),
      false;
    Other ->
      io:format("Got other message: ~p~n", [Other]),
      Other
  end.

stop() ->
  ets:close(?MODULE).
  % dets:close(?MODULE).

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

create_table() ->
  {ok, File} = file:open("/Users/seb/Downloads/facebook-names-original.txt", read),
  io:format("Starting to read~n"),
  ok = insert_lines(File),
  io:format("Finished reading file~n").

insert_lines(File) -> insert_lines(File, 0, []).
insert_lines(_File, Count, _Acc) when Count > 1000000 -> ok;
insert_lines(File, Count, Acc) when length(Acc) > 10000 ->
  io:format("Writing"),
  ets:insert(?MODULE, Acc),
  % dets:insert(?MODULE, Acc),
  io:format("...done~n"),
  insert_lines(File, Count, []);
insert_lines(File, Count, Acc) ->
  case Count rem 10000 of
    0 -> io:format("At item ~p~n", [Count]);
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
