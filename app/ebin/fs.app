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
	utilities, test_utils
  ]},
  {registered, []},
  {applications, [
                  kernel,
                  stdlib,
                  crypto,
                  mochiweb,
                  webmachine
                 ]},
  {mod, { fs_app, []}},
  {env, []}
 ]}.
