route_to_closer_node(Msg, Key, #pastry_state{self = Self, b = B, pastry_app_pid = PAPid, pastry_pid = PastryPid} = State) ->
  SharedKeySegment = shared_key_segment(Self, Key),
  Nodes = filter(
    fun(N) -> is_valid_key_path(N, SharedKeySegment) end, 
    all_known_nodes(State)
  ),
  case foldl(fun(N, CurrentClosest) -> 
          closer_node(Key, N, CurrentClosest, B) end, Self, Nodes) of
    Self -> pastry_app:deliver(PAPid, Msg, Key);
    Node -> do_forward_msg(Msg, Key, Node, PastryPid)
  end.
