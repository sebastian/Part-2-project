perform_find_successor(Key, #chord_state{self = Self} = State) -> 
  % in the case we are the only party in a chord circle,
  % then we are also our own successors.
  case closest_preceding_finger(Key, State) of
    Self -> {ok, Self};
    OtherNode -> 
      case perform_find_predecessor(Key, OtherNode) of
        error -> error;
        Predecessor-> {ok, Predecessor#pred_info.successor}
      end
  end.

perform_find_predecessor(Key, Node) ->
  case chord_tcp:rpc_get_closest_preceding_finger_and_succ(Key, Node) of
    {ok, {NextClosest, NodeSuccessor}} ->
      case utilities:in_right_inclusive_range(Key, Node#node.key, NodeSuccessor#node.key) of
        true -> 
          #pred_info{
            node = Node,
            successor = NodeSuccessor
          };
        false ->
          perform_find_predecessor(Key, NextClosest)
      end;
    {error, _Reason} ->
      error
  end.
