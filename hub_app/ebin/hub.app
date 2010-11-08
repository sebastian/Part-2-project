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

             node_srv
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
