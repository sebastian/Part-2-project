%% @author Sebastian Probst Eide <sebastian.probst.eide@gmail.com>
%% @copyright 2010 Sebastian Probst Eide.

%% @doc Starts up the Friend Search application

-module(fs).
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
  ensure_started(inets),
  ensure_started(crypto),
  ensure_started(mochiweb),
  application:set_env(webmachine, webmachine_logger_module, 
                      webmachine_logger),
  ensure_started(webmachine),
  fs_sup:start_link().

%% @spec start() -> ok
%% @doc Start the fs server.
start() ->
  ensure_started(inets),
  ensure_started(crypto),
  ensure_started(mochiweb),
  application:set_env(webmachine, webmachine_logger_module, 
                      webmachine_logger),
  ensure_started(webmachine),
  application:start(fs).

%% @spec stop() -> ok
%% @doc Stop the fs_web server.
stop() ->
  Res = application:stop(fs),
  application:stop(webmachine),
  application:stop(mochiweb),
  application:stop(crypto),
  application:stop(inets),
  Res.
