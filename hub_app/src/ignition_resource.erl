%% @author author <author@example.com>
%% @copyright YYYY author.
%% @doc Example webmachine_resource.

-module(ignition_resource).
-export([
    init/1, 
    process_post/2,
    is_authorized/2,
    allowed_methods/2
  ]).

-include_lib("webmachine/include/webmachine.hrl").
-include("records.hrl").

init([]) -> {ok, []}.

allowed_methods(R, S) -> {['POST'], R, S}.

% --------------------------------------------------------------------------
% Change mode --------------------------------------------------------------

process_post(R, S) ->
  {ok, ActionVerb} = dict:find(action, wrq:path_info(R)),
  {ok, Count} = dict:find(count, wrq:path_info(R)),
  Action = list_to_atom(ActionVerb ++ "_nodes"),
  io:format("Action: ~p, at count: ~p~n", [Action, Count]),
  node:Action(list_to_integer(Count)),
  {true, R, S}.

% --------------------------------------------------------------------------
% Authentication -----------------------------------------------------------

-define(AUTH_HEAD, "Basic realm=FriendSearch").

is_authorized(R, S) -> 
    case wrq:get_req_header("Authorization", R) of
        "Basic "++Base64 ->
            case string:tokens(base64:mime_decode_to_string(Base64), ":") of
                [Username, Password] -> {auth_mod:authenticate(Username, Password), R, S};
                _ -> {?AUTH_HEAD, R, S}
            end;
        _ -> {?AUTH_HEAD, R, S}
    end.
