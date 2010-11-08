%% @author author <author@example.com>
%% @copyright YYYY author.

%% @doc hub startup code

-module(hub).
-author('author <author@example.com>').
-export([start/0, start_link/0, stop/0]).

ensure_started(App) ->
    case application:start(App) of
        ok ->
            ok;
        {error, {already_started, App}} ->
            ok
    end.

%% @spec start_link() -> {ok,Pid::pid()}
%% @doc Starts the app for inclusion in a supervisor tree
start_link() ->
    ensure_started(crypto),
    ensure_started(mochiweb),
    application:set_env(webmachine, webmachine_logger_module, 
                        webmachine_logger),
    ensure_started(webmachine),
    hub_sup:start_link().

%% @spec start() -> ok
%% @doc Start the hub server.
start() ->
    ensure_started(crypto),
    ensure_started(mochiweb),
    application:set_env(webmachine, webmachine_logger_module, 
                        webmachine_logger),
    ensure_started(webmachine),
    application:start(hub).

%% @spec stop() -> ok
%% @doc Stop the hub server.
stop() ->
    Res = application:stop(hub),
    application:stop(webmachine),
    application:stop(mochiweb),
    application:stop(crypto),
    Res.
