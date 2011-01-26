-define(HUB_VERSION, 1).

-record(node, {
  ip,
  port
}).
-record(controller, {
    ip,
    port,
    mode = chord :: chord | pastry,
    ports = [] :: [number()],
    version
  }).
-record(state, {
    log_status = not_logging,
    mode,
    controllers = [] :: [#controller{}]
}).
