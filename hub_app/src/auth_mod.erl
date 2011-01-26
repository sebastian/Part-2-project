-module(auth_mod).

-export([authenticate/2]).

authenticate("sebastian", "eide") -> true;
authenticate(_, _) -> false.
