%% @author Sebastian Probst Eide <sebastian.probst.eide@gmail.com>
%% @copyright 2010 Sebastian Probst Eide

%% @doc Supervisor for the chord application.

-module(logger_sup).
-author('Sebastian Probst Eide sebastian.probst.eide@gmail.com').

-behaviour(supervisor).

%% External exports
-export([start_link/0, upgrade/0]).

%% supervisor callbacks
-export([init/1]).

%% @spec start_link() -> ServerRet
%% @doc API for starting the supervisor.
start_link() -> supervisor:start_link(?MODULE, []).

%% @spec upgrade() -> ok
%% @doc Add processes if necessary.
upgrade() ->
  {ok, {_, Specs}} = init([]),

  Old = sets:from_list([Name || {Name, _, _, _} <- supervisor:which_children(?MODULE)]),
  New = sets:from_list([Name || {Name, _, _, _, _, _} <- Specs]),
  Kill = sets:subtract(Old, New),

  sets:fold(fun (Id, ok) ->
                    supervisor:terminate_child(?MODULE, Id),
                    supervisor:delete_child(?MODULE, Id),
                    ok
            end, ok, Kill),

  [supervisor:start_child(?MODULE, Spec) || Spec <- Specs],
  ok.

%% @spec init([]) -> SupervisorTree
%% @doc supervisor callback.
init(_Args) ->
  % The controller process that interlinks the processes

  CreateChild = fun(Name) -> {Name,
      {Name, start_link, []},
      permanent, 2000, worker,
      [Name]}
    end,

  Processes = [
    CreateChild(logger)
  ],

  {ok, { {one_for_one, 10, 10}, Processes} }.
