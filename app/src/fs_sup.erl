%% @author author <author@example.com>
%% @copyright YYYY author.

%% @doc Supervisor for the fs_web application.

-module(fs_sup).
-author('Sebastian Probst Eide sebastian.probst.eide@gmail.com').

-behaviour(supervisor).

%% External exports
-export([start_link/0, upgrade/0]).

%% supervisor callbacks
-export([init/1]).

%% @spec start_link() -> ServerRet
%% @doc API for starting the supervisor.
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

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

%% @spec init([]) -> SupervisorTree
%% @doc supervisor callback.
init([]) ->
  CreateSup = fun(Name) -> {Name,
      {Name, start_link, []},
      permanent, infinity, supervisor,
      []}
    end,

  CreateChild = fun(Name,ChildArgs) -> {Name,
      {Name, start_link, [ChildArgs]},
      permanent, 2000, worker,
      [Name]}
    end,

  CreateSupWithArgs = fun(Name,Args) -> {Name,
      {Name, start_link, [Args]},
      permanent, infinity, supervisor,
      []}
    end,
  
  Processes = [
    CreateSup(logger_sup),
    CreateChild(pastry_locality, []),
    CreateSupWithArgs(fs_web_sup, 11385),
    CreateSup(datastore_sup),
    CreateSup(friendsearch_sup),
    CreateSup(controller_sup),
    CreateSup(chord_sofo),
    CreateSup(pastry_sofo)
  ],

  {ok, { {one_for_one, 10, 10}, Processes} }.
