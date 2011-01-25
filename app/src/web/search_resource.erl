%% @author Sebastian Probst Eide <sebastian.probst.eide@gmail.com>
%% @copyright 2010 Sebastian Probst Eide.
%% @doc Handles searches 

-module(search_resource).
-export([init/1, to_json/2, content_types_provided/2]).

-include_lib("webmachine/include/webmachine.hrl").
-include("../fs.hrl").

init([]) -> {ok, undefined}.

content_types_provided(ReqData, State) ->
  {[{"application/json", to_json}], ReqData, State}.

to_json(ReqData, State) ->
  % Get search query
  Query = wrq:get_qs_value("q", ReqData),
  Results = friendsearch_srv:find(Query),
  People = [{struct, [
                        {name, P#person.name},
                        {profile_url, P#person.human_profile_url},
                        {avatar_url, P#person.avatar_url}
                     ]} || P <- Results],
  Value = iolist_to_binary(mochijson2:encode({struct, 
      [
        {<<"hops">>, 1},
        {<<"results">>, People}
      ]
    })),
  {Value, ReqData, State}.
