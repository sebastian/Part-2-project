%%-*- mode: erlang -*-
{application, fs_web,
 [
  {description, "fs_web"},
  {vsn, "1"},
  {modules, [
             fs_web,
             fs_web_app,
             fs_web_sup,

             % Search resource
             search_resource,

             % Entry resource
             entries_resource,

             % Resource serving static content
             static_resource,

             % Datastore
             datastore
            ]},
  {registered, []},
  {applications, [
                  kernel,
                  stdlib,
                  crypto,
                  mochiweb,
                  webmachine
                 ]},
  {mod, { fs_web_app, []}},
  {env, []}
 ]}.
