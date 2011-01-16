-record(node, {
  ip,
  port
}).
-record(state, {
    chord_nodes = [],
    pastry_nodes = [],
    timerRef
}).
