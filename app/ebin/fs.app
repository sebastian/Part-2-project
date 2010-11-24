%%-*- mode: erlang -*-
{application, fs,
 [
  {description, "Friend Search application"},
  {vsn, "0.0.1"},
  {modules, [
    fs, fs_app, fs_sup,
 	fs_web_sup, entries_resource, search_resource, static_resource,
	chord, chord_sup, chord_tcp, 
	gen_listener_tcp,
	datastore,
	utilities, test_utils,
  % For testing
  erlymock, erlymock_tcp, erlymock_recorder
  ]},
  {registered, []},
  {applications, [
                  kernel,
                  stdlib,
                  crypto,
                  mochiweb,
                  webmachine,
                  inets
                 ]},
  {mod, { fs_app, []}},
  {env, []}
 ]}.
