%% @author Sebastian Probst Eide
%% @doc Utility module with functionality
%%     used accross all Friend Search applications.
-module(utilities).
-export([get_key/1]).

-include("records.hrl").

-spec(get_key/1::(Entry::#entry{}) -> binary()).
get_key(Entry) ->
  crypto:sha(Entry).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Tests
%%

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

key_for_person_entry_test() ->
  ok.

-endif.
