%% @author Sebastian Probst Eide <sebastian.probst.eide@gmail.com>
%% @copyright 2010 Sebastian Probst Eide.
%% @doc Handles listing of local resources

-module(entries_resource).
-export([init/1, 
    allowed_methods/2,
    content_types_provided/2,
    to_json/2,
    process_post/2]).

-include_lib("webmachine/include/webmachine.hrl").
-include("../fs.hrl").

init([]) -> {ok, undefined}.

allowed_methods(R, S) -> 
  %% @todo: Should check if the path is /entries, then accept POST and GET,
  %% and only accept GET for /entries/KEY.
  {['POST', 'HEAD', 'GET'], R, S}.
  
process_post(ReqData, State) ->
  {struct, Data} = mochijson2:decode(wrq:req_body(ReqData)),
  NewPerson = #person{
    name = proplists:get_value(<<"name">>, Data),
    human_profile_url = proplists:get_value(<<"profile_url">>, Data),
    avatar_url = proplists:get_value(<<"avatar_url">>, Data)
  },
  io:format("******** Received new person: ~p ********* ~n", [NewPerson]),
  friendsearch_srv:add(NewPerson),
  {true, ReqData, State}.

content_types_provided(ReqData, State) ->
  {[{"application/json", to_json}], ReqData, State}.

to_json(ReqData, State) ->
  % All entries
  Results = friendsearch_srv:list(),
  People = [{struct, [
              {name, P#person.name},
              {profile_url, P#person.human_profile_url},
              {avatar_url, P#person.avatar_url}
             ]} || P <- Results],
  Value = iolist_to_binary(mochijson2:encode({struct, 
      [
        {<<"results">>, People}
      ]
    })),
  {Value, ReqData, State}.
