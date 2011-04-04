%% @author Sebastian Probst Eide <sebastian.probst.eide@gmail.com>
%% @copyright 2010 Sebastian Probst Eide

%% @doc Supervisor for the pastry application.

-module(pastry_sup).
-author('Sebastian Probst Eide sebastian.probst.eide@gmail.com').

-behaviour(supervisor).

%% External exports
-export([start_link/0, upgrade/0, start_node/0]).

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
  ControllingProcess = controller:get_controlling_process(),
  ControllingProcessArg = [{controllingProcess, ControllingProcess}],
  PortArg = [{port, 20000}],

  CreateChild = fun(Name,ChildArgs) -> {Name,
      {Name, start_link, [ChildArgs]},
      transient, 2000, worker,
      [Name]}
    end,

  Processes = [
    CreateChild(pastry_tcp, ControllingProcessArg ++ PortArg),
    CreateChild(pastry, ControllingProcessArg),
    CreateChild(pastry_app, ControllingProcessArg)
  ],

  {ok, { {one_for_all, 10, 10}, Processes} }.

start_node() -> start_node(4).

start_node(0) -> supervisor:start_child(pastry_sofo, []);
start_node(N) -> 
  case supervisor:start_child(pastry_sofo, []) of
    {error, _Reason} -> start_node(N-1);
    Msg -> Msg
  end.
