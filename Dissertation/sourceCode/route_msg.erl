route_msg(Msg, Key, State) ->
  spawn(fun() ->
    route_to_leaf_set(Msg, Key, State) orelse
    route_to_node_in_routing_table(Msg, Key, State) orelse
    route_to_closer_node(Msg, Key, State)
  end).
