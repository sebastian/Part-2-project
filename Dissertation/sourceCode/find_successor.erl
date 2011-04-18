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
