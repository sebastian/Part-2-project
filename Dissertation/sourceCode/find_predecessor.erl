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
