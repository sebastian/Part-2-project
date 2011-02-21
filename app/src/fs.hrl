-compile([debug_info]).

% Version number returned by controller app to see if a node is
% running the latest release
-define(VERSION, 13).

% Rendevouz host
%-define(RENDEVOUZ_HOST, "localhost").
-define(RENDEVOUZ_HOST, "hub.probsteide.com").
-define(RENDEVOUZ_PORT, 6001).

-define(TCP_TIMEOUT, 5000).

-type(key() :: number()).
-type(binary_string() :: bitstring()).
-type(port_number() :: integer()).
-type(ip() :: {byte(),byte(),byte(),byte()}).

% Records timeout after 5 hours.
-define(ENTRY_TIMEOUT, 60*60*5).

-record(link,
  {
    % The name fragment used to match search results
    name_fragment :: binary_string(),

    % The full name of the user this link points to.
    name :: binary_string(),

    % The key under which the users full profile can be found.
    profile_key :: key()
  }).
-record(person,
  {
    % The persons full name
    name :: binary_string(),

    % Url to a human readable version
    %     of the users profile
    human_profile_url :: binary_string(),

    % Url to a machine readable version
    %     of the users profile, and a string
    %     determining the format of the profile
    machine_profile_url :: binary_string(),
    profile_protocol :: binary_string(),

    % Url to the persons avatar image displayed
    %     alongside search results.
    avatar_url :: binary_string()
  }).
-record(entry, {
    key :: key(),
    
    % This is the TTL for the record in seconds.
    %     The server that stores the record is
    %     responsible for decrementing the value
    %     and delete expired records.
    timeout = ?ENTRY_TIMEOUT :: integer(),

    % The data part of the record. The record can
    %     either be a link to a full record, or
    %     a full record. Links can be used to
    %     have a persons record available under
    %     multiple keys.
    data :: #person{} | #link{}
  }).

-record(datastore_state, {
    timer,
    data
  }).
-record(friendsearch_state, {
    dht, 
    dht_pid,
    entries = [],
    link_entries = [],
    timerRefKeepAlive
  }).
-record(controller_node, {
    dht_pid = undefined :: pid(),
    tcp_pid = undefined :: pid(),
    app_pid = undefined :: pid(),
    controller_pid = undefined :: pid(),
    port = undefined :: port_number()
  }).
-define(NYI, exit({not_yet_implemented, ?MODULE, ?LINE})).
