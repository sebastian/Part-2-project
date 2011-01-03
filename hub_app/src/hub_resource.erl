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

  Value = iolist_to_binary(mochijson2:encode({struct,
    case node_srv:reg_and_get_peer({ClientIp, ClientPort}) of
      first -> [{<<"first">>, true}];
      Peers -> 
        [{<<"peers">>, [{struct, [
              {<<"ip">>, list_to_bitstring(Ip)}, 
              {<<"port">>, list_to_integer(Port)}
            ]} || {Ip, Port} <- Peers]}]
    end
  })),
  
  {Value, ReqData, State}.
