% Returns the node in the current nodes finger table
% most closely preceding the key.
closest_preceding_finger(Key, #chord_state{chord_pid = Pid} = State) ->
  closest_preceding_finger(Key, 
    State#chord_state.fingers, array:size(State#chord_state.fingers) - 1,
    State#chord_state.self).

closest_preceding_finger(_Key, _Fingers, -1, Self) -> Self;
closest_preceding_finger(Key, Fingers, 0, Self) ->
  % The current finger is the successor finger.
  % Get the closest successor from the list of successors
  FingerNode = get_first_successor(array:get(0, Fingers)),
  check_closest_preceding_finger(Key, FingerNode, Fingers, 0, Self);
closest_preceding_finger(Key, Fingers, FingerIndex, Self) ->
  FingerNode = (array:get(FingerIndex, Fingers))#finger_entry.node,
  check_closest_preceding_finger(Key, FingerNode, Fingers, FingerIndex, Self).
