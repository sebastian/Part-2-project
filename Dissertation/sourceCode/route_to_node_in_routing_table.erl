route_to_node_in_routing_table(Msg, Key, #pastry_state{pastry_pid = PastryPid, pastry_app_pid = PastryAppPid} = State) ->
  {#routing_table_entry{nodes = Nodes}, [none|PreferredKeyMatch]} = 
      find_corresponding_routing_table(Key, State),
  case filter(fun(Node) -> is_valid_key_path(Node, PreferredKeyMatch) end, Nodes) of
    [] -> false;
    [Node] -> 
      case Node =:= State#pastry_state.self of
        true -> pastry_app:deliver(PastryAppPid, Msg, Key);
        false -> do_forward_msg(Msg, Key, Node, PastryPid)
      end
  end.
