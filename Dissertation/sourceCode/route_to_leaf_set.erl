route_to_leaf_set(Msg, Key, #pastry_state{self = Self, pastry_pid = PastryPid, pastry_app_pid = PastryAppPid} = State) ->
  case node_in_leaf_set(Key, State) of
    none -> false;
    Node when Node =:= Self -> 
      pastry_app:deliver(PastryAppPid, Msg, Key),
      true;
    Node -> do_forward_msg(Msg, Key, Node, PastryPid)
  end.
