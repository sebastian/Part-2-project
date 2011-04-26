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
    predecessor :: #node{},
    fingers = array:new(160) :: array(),
    % ...
  }).
