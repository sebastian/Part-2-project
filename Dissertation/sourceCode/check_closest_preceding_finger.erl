% We check if the node for a given finger entry is between 
% ourselves and the key we are looking for. Since we are 
% looking through the finger table for nodes that are 
% successively closer to ourself, we are bound to end up 
% with the node most closely preceding the key that we know about.
check_closest_preceding_finger(Key, undefined, Fingers, FingerIndex, Self) ->
  % The finger entry is empty. We skip it
  closest_preceding_finger(Key, Fingers, FingerIndex-1, Self);
check_closest_preceding_finger(Key, Node, Fingers, FingerIndex, Self) ->
  case utilities:in_range(Node#node.key, Self#node.key, Key) of
    true -> 
      % This is the key in our routing table that is closest
      % to the destination key. Return it.
      Node;
    false -> 
      % The current finger is greater than the key. Try closer fingers
      closest_preceding_finger(Key, Fingers, FingerIndex-1, Self)
  end.
