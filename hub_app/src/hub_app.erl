%% @author author <author@example.com>
%% @copyright YYYY author.

%% @doc Callbacks for the hub application.

-module(hub_app).
-author('author <author@example.com>').

-behaviour(application).
-export([start/2,stop/1]).


%% @spec start(_Type, _StartArgs) -> ServerRet
%% @doc application start callback for hub.
start(_Type, _StartArgs) ->
    hub_sup:start_link().

%% @spec stop(_State) -> ServerRet
%% @doc application stop callback for hub.
stop(_State) ->
    ok.
