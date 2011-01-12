-type(pastry_key() :: [integer()]).
-record(node, {
    key :: pastry_key(),
    ip :: ip(),
    port :: integer(),
    distance :: number()
  }).
-record(routing_table_entry, {
    value :: integer() | none,
    nodes = [] :: [#node{}]
  }).
-record(pastry_state, {
    b :: integer(),
    l :: integer(),

    % The routing table contains log base 2^b rows of 2^b - 1 
    % entries each. Entries at row n share the first n digits
    % with the current node, but differ in digit n + 1
    routing_table :: [#routing_table_entry{}],

    % The nieghborhood set contains the nodes closest to the 
    % given node according to the distance metric used.
    % The size of the table is roughly 2^b
    neighborhood_set = [] :: [#node{}],

    % The leaf set usually contains up to 2^b nodes in total
    leaf_set = {[], []} :: {[#node{}], [#node{}]},

    % Information about the current node
    self = #node{}
  }).
