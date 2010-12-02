-record(node, {
    ip :: ip(),
    port :: port_number(),
    key :: key()
  }).
-record(finger_entry, {
    start :: key(),
    interval :: {key(), key()},
    node :: #node{}
  }).
-record(chord_state, {
    self :: #node{},
    successor :: #node{},
    predecessor :: #node{},

    % The finger list is in inverse order from what is described
    % in the Chord paper. This is due to implementation reasons,
    % since the method closest_preceding_finger, which is the
    % only method using the finger table directly, traverses
    % it from the back to the front.
    fingers = array:new(160) :: array(),

    % Administrative information
    pidStabilizer :: pid(),
    pidFixFingers :: pid()
  }).
