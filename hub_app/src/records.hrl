-record(node, {
  ip,
  port
}).
-record(controller, {
    ip,
    port,
    mode = chord :: chord | pastry,
    ports = [] :: [number()]
  }).
-record(state, {
    mode,
    controllers = [] :: [#controller{}]
}).
