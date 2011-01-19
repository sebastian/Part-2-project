%% @author Sebastian Probst Eide <sebastian.probst.eide@gmail.com>
%% @copyright 2010 Sebastian Probst Eide

%% @doc Supervisor for the pastry application.

-module(pastry_sofo).
-author('Sebastian Probst Eide sebastian.probst.eide@gmail.com').

-behaviour(supervisor).

%% External exports
-export([start_link/1, upgrade/0]).

%% supervisor callbacks
-export([init/1]).

%% @spec start_link() -> ServerRet
%% @doc API for starting the supervisor.
start_link(Args) ->
    supervisor:start_link(?MODULE, Args).

%% @spec upgrade() -> ok
%% @doc Add processes if necessary.
upgrade() ->
    {ok, {_, Specs}} = init([]),

    Old = sets:from_list(
            [Name || {Name, _, _, _} <- supervisor:which_children(?MODULE)]),
    New = sets:from_list([Name || {Name, _, _, _, _, _} <- Specs]),
    Kill = sets:subtract(Old, New),

    sets:fold(fun (Id, ok) ->
                      supervisor:terminate_child(?MODULE, Id),
                      supervisor:delete_child(?MODULE, Id),
                      ok
              end, ok, Kill),

    [supervisor:start_child(?MODULE, Spec) || Spec <- Specs],
    ok.

init(Args) ->
  CreateSupWithArgs = fun(Name,ChildArgs) -> {Name,
      {Name, start_link, [ChildArgs]},
      permanent, infinity, supervisor,
      []}
    end,

  Pastry = CreateSupWithArgs(pastry_sup, Args),

  StartSpecs = {{simple_one_for_one, 0, 1}, [Pastry]},
  {ok, StartSpecs}.
