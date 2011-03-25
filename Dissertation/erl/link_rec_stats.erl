-module(link_rec_stats).
-compile([export_all]).

-define(LINK_NAME_CHUNKS, 3).

run() ->
  {ok, File} = file:open("/Users/seb/Downloads/facebook-names-original.txt", read),
  io:format("Starting to read~n"),
  Sizes = read_file(File, []),
  io:format("Finished reading file~n"),

  LinkNums = [Link || {Link, _} <- Sizes],
  AverageNumLinks = calculate_average(LinkNums),
  NumLinksStDev = calc_std_dev(LinkNums, AverageNumLinks),

  NameLengths = [NameLength || {_, NameLength} <- Sizes],
  AverageNameLength = calculate_average(NameLengths),
  NameLengthStDev = calc_std_dev(NameLengths, AverageNameLength),

  io:format("Experiment run on ~p names~n", [length(LinkNums)]),
  io:format("Average num links: ~p, StdDev: ~p~n", [AverageNumLinks, NumLinksStDev]),
  io:format("Average name length: ~p, StdDev: ~p~n", [AverageNameLength, NameLengthStDev]).

calc_std_dev(Items, Average) ->
  Count = length(Items),
  Variance = lists:foldl(
    fun(Item, Acc) -> (Item - Average)*(Item - Average)/(Count-1) + Acc end, 
    0, Items),
  math:sqrt(Variance).

calculate_average(Nums) ->
  Sum = lists:foldl(fun(Num, Acc) -> Num + Acc end, 0, Nums),
  Sum / length(Nums).

read_file(File, Items) ->
  read_file(File, Items, 0).
read_file(_File, Items, Count) when Count > 40000000 -> Items;
read_file(File, Items, Count) ->
  case (Count rem 10000) of
    0 -> 
      io:format("Line ~p~n", [Count]);
    _ -> ok
  end,
  case file:read_line(File) of
    eof ->
      Items;
    {ok, _Line} ->
      case file:read_line(File) of
        eof ->
          Items;
        {ok, Line} ->
          read_file(File, [size_for_user(Line) | Items], Count+1)
      end
  end.
  
size_for_user(Name) ->
  {length(name_subsets(Name)), length(Name)}.

name_subsets(Name) ->
  ListName = utilities:string_to_list(utilities:downcase_str(Name)),
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
