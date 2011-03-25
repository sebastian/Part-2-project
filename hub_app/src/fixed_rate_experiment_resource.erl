%% @author author <author@example.com>
%% @copyright YYYY author.
%% @doc Example webmachine_resource.

-module(fixed_rate_experiment_resource).
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
  {ok, RL} = dict:find(rate, wrq:path_info(R)),
  {ok, TL} = dict:find(time, wrq:path_info(R)),
  Rate = list_to_integer(RL),
  Time = list_to_integer(TL),
  io:format("About to start an experiment at rate ~p for ~p minutes~n", [Rate, Time]),
  node:start_single_rate_for_time(Rate, Time),
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
