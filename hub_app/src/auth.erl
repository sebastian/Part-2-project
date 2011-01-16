-module(auth).

-export([authenticate/2]).

authenticate("sebastian", "eide") -> true;
authenticate(_, _) -> false.
