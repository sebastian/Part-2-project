%% @author Sebastian Probst Eide <sebastian.probst.eide@gmail.com>
%% @copyright 2010 Sebastian Probst Eide.

%% @doc fs_web startup code

-module(fs_web).
-author('Sebastian Probst Eide <sebastian.probst.eide@gmail.com').
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
    fs_web_sup:start_link().

%% @spec start() -> ok
%% @doc Start the fs_web server.
start() ->
    ensure_started(crypto),
    ensure_started(mochiweb),
    application:set_env(webmachine, webmachine_logger_module, 
                        webmachine_logger),
    ensure_started(webmachine),
    application:start(fs_web).

%% @spec stop() -> ok
%% @doc Stop the fs_web server.
stop() ->
    Res = application:stop(fs_web),
    application:stop(webmachine),
    application:stop(mochiweb),
    application:stop(crypto),
    Res.
