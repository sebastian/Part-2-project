%% @author Sebastian Probst Eide <sebastian.probst.eide@gmail.com>
%% @copyright 2010 Sebastian Probst Eide

%% @doc Supervisor for the chord application.

-module(pastry_sup).
-author('Sebastian Probst Eide sebastian.probst.eide@gmail.com').

-behaviour(supervisor).

%% External exports
-export([start_link/1, upgrade/0]).

%% supervisor callbacks
-export([init/1]).

%% @spec start_link() -> ServerRet
%% @doc API for starting the supervisor.
start_link(Args) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, Args).

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
init(Args) ->
  io:format("Got args in sup init: ~p~n", [Args]),
  PastryLocality = {pastry_locality, {pastry_locality, start_link, []},
      permanent, 2000, worker, [pastry_locality]},
  PastryTcp = {pastry_tcp, {pastry_tcp, start_link, [Args]},
      permanent, 2000, worker, [pastry_tcp]},
  Pastry = {pastry, {pastry, start_link, [Args]},
      permanent, 2000, worker, [pastry]},

  Processes = [PastryLocality, PastryTcp, Pastry],

  {ok, { {one_for_one, 10, 10}, Processes} }.
