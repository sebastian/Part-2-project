%% @author Sebastian Probst Eide <sebastian.probst.eide@gmail.com>
%% @copyright 2010 Sebastian Probst Eide.
%% @doc Handles searches 

-module(search_resource).
-export([init/1, to_json/2, content_types_provided/2]).

-include_lib("webmachine/include/webmachine.hrl").

init([]) -> {ok, undefined}.

content_types_provided(ReqData, State) ->
  {[{"application/json", to_json}], ReqData, State}.

to_json(ReqData, State) ->
  % Get search query
  Query = wrq:get_qs_value("q", ReqData),
  PropList = proplists:property(<<"name">>, list_to_bitstring(Query)),
  Value = mochijson2:encode({struct, 
      [
        {<<"hops">>, 1},
        {<<"data">>, [{struct, [PropList]}]}
      ]
    }),
  {Value, ReqData, State}.


