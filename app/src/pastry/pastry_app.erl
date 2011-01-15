-module(pastry_app).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-include("../fs.hrl").
-include("pastry.hrl").

%% ------------------------------------------------------------------
%% Public API
%% ------------------------------------------------------------------

-export([
    deliver/2,
    forward/3,
    new_leaves/1
  ]).

%% ------------------------------------------------------------------
%% PRIVATE API Function Exports
%% ------------------------------------------------------------------


%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

% @doc: Called by pastry when the current node is the numerically
% closest to the key among all live nodes.
-spec(deliver/2::(_, pastry_key()) -> ok).
deliver({join, Node}, _Key) ->
  io:format("Received a join message. Welcome stranger~n"),
  % Hurrah, there is a new node in the network.
  % We have to send it our leaf set, and 
  % wholeheartedly welcome it!
  pastry:welcome(Node);

deliver(Msg, _Key) ->
  error_logger:error_msg("Unknown message delivered: ~p~n", [Msg]),
  ok.


% @doc: Called by Pastry before a message is forwarded to NextId.
% The message and the NextNode can be changed. 
% The message is not forwarded if the returned NextNode is null.
-spec(forward/3::(Msg::#entry{}, Key::pastry_key(), NextNode::#node{})
  -> {#entry{}, #node{}} | {_, null}).
forward(Msg, _Key, NextNode) ->
  {Msg, NextNode}.


% @doc: Called by pastry whenever there is a change in the local node's leaf set.
-spec(new_leaves/1::({[#node{}], [#node{}]}) -> ok).
new_leaves(LeafSet) ->
  io:format("Received new leaf set: ~p~n", [LeafSet]),
  ok.

%% ------------------------------------------------------------------
%% Tests
%% ------------------------------------------------------------------

-ifdef(TEST).

%   erlymock:start(),
%   erlymock:strict(chord_tcp, rpc_get_closest_preceding_finger_and_succ, [Key, get_successor(State)], [{return, RpcReturn}]),
%   erlymock:replay(), 
%   % Methods invoking whatever.
%   erlymock:verify().

-endif.
