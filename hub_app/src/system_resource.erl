%% @author author <author@example.com>
%% @copyright YYYY author.
%% @doc Example webmachine_resource.

-module(system_resource).
-export([
    init/1, 
    process_post/2,
    allowed_methods/2
  ]).

-include_lib("webmachine/include/webmachine.hrl").
-include("records.hrl").

init([]) -> {ok, []}.

allowed_methods(R, S) -> {['POST'], R, S}.

% --------------------------------------------------------------------------
% Change mode --------------------------------------------------------------

process_post(R, S) ->
  node:upgrade(),
  {true, R, S}.
