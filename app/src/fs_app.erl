%% @author Sebastian Probst Eide <sebastian.probst.eide@gmail.com>
%% @copyright 2010 Sebastian Probst Eide.

%% @doc Callbacks for the fs application.

-module(fs_app).
-author('Sebastian Probst Eide <sebastian.probst.eide@gmail.com>').

-behaviour(application).
-export([start/2,stop/1]).


%% @spec start(_Type, _StartArgs) -> ServerRet
%% @doc application start callback for fs_web.
start(_Type, _StartArgs) ->
    fs_sup:start_link().

%% @spec stop(_State) -> ServerRet
%% @doc application stop callback for fs_web.
stop(_State) ->
    ok.
