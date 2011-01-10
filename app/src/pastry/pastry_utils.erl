-module(pastry_utils).
-compile([export_all]).

-import(lists, [flatten/1]).

-include("../fs.hrl").

% @doc: Performs traceroute on the given Url
-spec(traceroute/1::(ip()) -> string()).
traceroute({A,B,C,D}) ->
  Cmd = flatten(io_lib:format("traceroute -I -m 30 ~p.~p.~p.~p", [A,B,C,D])),
  os:cmd(Cmd).

