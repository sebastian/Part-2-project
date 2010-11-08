%% @author author <author@example.com>
%% @copyright YYYY author.
%% @doc Example webmachine_resource.

-module(hub_resource).
-export([init/1, to_html/2]).

-include_lib("webmachine/include/webmachine.hrl").

init([]) -> {ok, []}.

to_html(ReqData, State) ->
  ClientIp = wrq:get_qs_value("ip", ReqData),
  ClientPort = wrq:get_qs_value("port", ReqData),
  Data = {ClientIp, ClientPort},
  ReturnValue = node_srv:reg_and_get_peer(Data),
  {term_to_binary(ReturnValue), ReqData, State}.
