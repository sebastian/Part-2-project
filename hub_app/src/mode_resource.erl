%% @author author <author@example.com>
%% @copyright YYYY author.
%% @doc Example webmachine_resource.

-module(mode_resource).
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
  {ok, Mode} = dict:find(mode, wrq:path_info(R)),
  io:format("Switching mode to: ~p~n", [Mode]),
  NewMode = list_to_atom(Mode),
  io:format("Switching mode to: ~p~n", [NewMode]),
  node:switch_mode_to(NewMode),
  {true, R, S}.

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
