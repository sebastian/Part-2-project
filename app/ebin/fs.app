%%-*- mode: erlang -*-
{application, fs,
 [
  {description, "Friend Search application"},
  {vsn, "0.0.1"},
  {modules, [
    fs, fs_app, fs_sup,
    fs_web_sup, entries_resource, search_resource, static_resource,
    chord, chord_sup, chord_tcp, chord_sofo,
    pastry, pastry_locality, pastry_utils, pastry_tcp, pastry_app, pastry_sup, pastry_sofo,
    gen_listener_tcp,
    datastore, datastore_srv, datastore_sup,
    utilities, tcp_utils, 
    friendsearch, friendsearch_srv, friendsearch_sup,
    test_dht, test_utils,
    controller, controller_tcp, controller_sup
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
