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
    CreateSupWithArgs = fun(Name,Args) -> {Name,
        {Name, start_link, [Args]},
        permanent, infinity, supervisor,
        []}
      end,

    Processes = 
    % General things we want to start
    [
      CreateSup(datastore_sup),
      CreateSup(friendsearch_sup)
    ] ++
    case utilities:get_pastry_port() of
      none -> [];
      Port -> [CreateSupWithArgs(pastry_sup, [{port, Port}])]
    end ++
    case utilities:get_chord_port() of
      none -> [];
      Port -> [CreateSupWithArgs(chord_sup, [{port, Port}])]
    end ++
    % Check if the webmachine should be launched too:
    % Only launch webmachine if it is explicitly asked for.
    case utilities:get_webmachine_port() of 
      none ->
        % It shouldn't launch webmachine
        [];
      Port -> [CreateSupWithArgs(fs_web_sup, Port)]
    end, 

    {ok, { {one_for_one, 10, 10}, Processes} }.
