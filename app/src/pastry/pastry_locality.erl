-module(pastry_locality).
-behaviour(gen_server).

-define(SERVER, ?MODULE).

-include("../fs.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.


%% ------------------------------------------------------------------
%% Public API
%% ------------------------------------------------------------------

-export([start_link/0, start/0, stop/0]).
-export([distance/1]).

%% ------------------------------------------------------------------
%% PRIVATE API Function Exports
%% ------------------------------------------------------------------

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([
    init/1, 
    handle_call/3,
    handle_cast/2, 
    handle_info/2, 
    terminate/2, 
    code_change/3
  ]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start() ->
  gen_server:start({local, ?SERVER}, ?MODULE, [], []).

start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

stop() ->
  gen_server:call(?MODULE, stop).

% @doc: Looks up the distance to a given node.
% This metric is not necessarily Euclidian, that is the triangle
% inequality does not hold.
% Results are cached for increased performance
-spec(distance/1::(Ip::ip()) -> number()).
distance(Ip) ->
  gen_server:call(?SERVER, {get_distance, Ip}).


%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(_Args) -> 
  {ok, state}.

% Call:
handle_call({get_distance, {A,B,C,D}}, _From, State) ->
  {noreply, State};

handle_call(stop, _From, State) ->
  {stop, normal, ok, State}.


% Casts:
handle_cast(Msg, State) ->
  error_logger:error_msg("received unknown cast: ~p", [Msg]),
  {noreply, State}.


% Info:
handle_info(Info, State) ->
  error_logger:error_msg("Got info message: ~p", [Info]),
  {noreply, State}.


% Terminate:
terminate(_Reason, State) ->
  ok.


% Code change. Not yet implemented.
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

% @doc: calculates the distance from the current to a given node.
% The distance is based on a weighted sum of the number routing hops
% away a node is, and the latency of that node.
-spec(calculate_distance/1::(ip()) -> number()).
calculate_distance(Ip) ->
  Trace = pastry_utils:traceroute(Ip),
  5.

%% ------------------------------------------------------------------
%% Tests
%% ------------------------------------------------------------------

-ifdef(TEST).

calculate_distance_test() ->
  TracerouteReturn = "traceroute to aftenposten.no (80.91.37.212), 30 hops max, 72 byte packets\n 1  gw-129.net.cam.ac.uk (131.111.223.62)  10.721 ms  3.864 ms  2.108 ms\n 2  route-north.route-cent.net.cam.ac.uk (192.84.5.5)  1.003 ms  1.892 ms  0.907 ms\n 3  route-cent.route-enet.net.cam.ac.uk (192.153.213.193)  1.422 ms  2.337 ms  2.058 ms\n 4  gw-1981.net.cam.ac.uk (131.111.184.254)  1.390 ms  1.655 ms  1.894 ms\n 5  xe-11-3-0.camb-rbr1.eastern.ja.net (146.97.130.1)  18.969 ms  4.939 ms  5.564 ms\n 6  xe-2-0-0.lond-rbr1.eastern.ja.net (146.97.65.33)  7.080 ms  7.639 ms  6.457 ms\n 7  ae3.lond-sbr4.ja.net (146.97.35.125)  5.956 ms  4.633 ms  5.800 ms\n 8  if-5-0-0.core4.ldn-london.as6453.net (80.231.76.41)  4.695 ms  5.422 ms  9.747 ms\n 9  if-13-1-0.mcore3.ldn-london.as6453.net (195.219.195.149)  7.145 ms  6.761 ms  5.169 ms\n10  if-11-0-0-0.tcore2.av2-amsterdam.as6453.net (195.219.195.34)  38.152 ms  20.593 ms  22.748 ms\n11  if-7-1-0.core2.os1-oslo.as6453.net (80.231.152.42)  48.430 ms  81.323 ms  48.510 ms\n12  ix-6-0-0.core2.os1-oslo.as6453.net (80.231.89.14)  46.672 ms  45.941 ms  44.083 ms\n13  te0-0-0-2.oslo-san110-p2.as2116.net (193.75.2.101)  45.226 ms  44.669 ms  45.194 ms\n14  te0-1-0-4.oslo-oslos3da-p2.as2116.net (195.0.240.34)  44.853 ms  51.843 ms  49.836 ms\n15  te5-1-0.br1.osls.no.catchbone.net (193.75.3.134)  48.592 ms  48.957 ms  58.135 ms\n16  193.69.11.106 (193.69.11.106)  44.778 ms  44.747 ms  44.575 ms\n17  80.91.32.5 (80.91.32.5)  45.047 ms  92.425 ms  45.596 ms\n18  80.91.37.212 (80.91.37.212)  48.104 ms  45.385 ms  45.265 ms\n",
  
  Ip = {1,2,3,4},

  erlymock:start(),
  erlymock:strict(pastry_utils, traceroute, [Ip], [{return, TracerouteReturn}]),
  erlymock:replay(), 
  ?assertEqual(1, calculate_distance(Ip)),
  erlymock:verify().

-endif.
