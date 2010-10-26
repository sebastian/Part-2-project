%%-*- mode: erlang -*-
{application, fs,
 [
  {description, "Friend Search application"},
  {vsn, "1"},
  {modules, [
			 %%
			 %% Main application and general utilities
             fs,
             utilities,
             test_utils,

			 %%
			 %% The web frontend part of the application
             fs_web_app,
             fs_web_sup,
             search_resource,
             entries_resource,
             static_resource,

			 %%
             %% Datastore
             datastore,

			 %%
             %% The DHT's
             pastry_srv

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
