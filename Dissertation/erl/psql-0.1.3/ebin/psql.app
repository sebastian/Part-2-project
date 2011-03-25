%% copyright 2006 Reliance Commnication inc
%% author  Martin Carlson
%% version $Rev$
%% psql spec
%% OBS: Make sure the postgres server uses MD5 authentication
%%-------------------------------------------------------------------
{application, psql, [{description, "psql $Rev$"},
		     {vsn, "0.1.3"},
		     {modules, [psql, psql_app, psql_con_sup, psql_connection, psql_lib,  psql_logic, psql_pool, psql_protocol, psql_sup ]},
		     {registered, [psql_sup]},
		     {applications, [kernel, stdlib]},
		     {mod, {psql, []}},
		     {env, [{default, 
			     {"127.0.0.1", 5432, "user", "password", "db"}},
    		            {pools, [{default, 1}]}]}]}.
