%% @author author <author@example.com>
%% @copyright YYYY author.
%% @doc Example webmachine_resource.

-module(hub_resource).
-export([
    init/1, 
    content_types_provided/2,
    to_json/2,
    to_text/2,
    is_authorized/2
  ]).

-include_lib("webmachine/include/webmachine.hrl").
-include("records.hrl").

init([]) -> {ok, []}.

% --------------------------------------------------------------------------
% Getting nodes ------------------------------------------------------------

content_types_provided(R, S) ->
  {[{"application/json", to_json}, {"text/plain", to_text}], R, S}.
  
to_json(R, S) ->
  HostStruct = node:live_nodes(),
  Ret = mochijson2:encode(HostStruct),
  {Ret, R, S}.

to_text(R, S) -> to_json(R,S).

% --------------------------------------------------------------------------
% Authentication -----------------------------------------------------------

-define(AUTH_HEAD, "Basic realm=FriendSearch").

is_authorized(R, S) -> 
    case wrq:get_req_header("Authorization", R) of
        "Basic "++Base64 ->
            case string:tokens(base64:mime_decode_to_string(Base64), ":") of
                [Username, Password] -> {auth:authenticate(Username, Password), R, S};
                _ -> {?AUTH_HEAD, R, S}
            end;
        _ -> {?AUTH_HEAD, R, S}
    end.
