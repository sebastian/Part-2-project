%% @author author <author@example.com>
%% @copyright YYYY author.

%% @doc Callbacks for the fs_web application.

-module(fs_web_app).
-author('author <author@example.com>').

-behaviour(application).
-export([start/2,stop/1]).


%% @spec start(_Type, _StartArgs) -> ServerRet
%% @doc application start callback for fs_web.
start(_Type, _StartArgs) ->
    fs_web_sup:start_link().

%% @spec stop(_State) -> ServerRet
%% @doc application stop callback for fs_web.
stop(_State) ->
    ok.
