%%-*- mode: erlang -*-
{application, hub,
 [
  {description, "hub"},
  {vsn, "1"},
  {modules, [
             hub,
             hub_app,
             hub_sup,
             hub_resource,
             hub_tcp,
             gen_listener_tcp,

             node, node_core,
             struct,
             static_resource,
             mode_resource,
             ignition_resource,
             logging_resource,
             system_resource,
             experiment_resource,
             auth_mod
            ]},
  {registered, []},
  {applications, [
                  kernel,
                  stdlib,
                  crypto,
                  mochiweb,
                  webmachine
                 ]},
  {mod, { hub_app, []}},
  {env, []}
 ]}.
