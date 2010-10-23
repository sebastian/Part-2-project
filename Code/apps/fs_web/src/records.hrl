-type(key() :: binary()).
-type(binary_string() :: binary()).

-record(link,
  {
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
    timeout :: integer(),

    % The data part of the record. The record can
    %     either be a link to a full record, or
    %     a full record. Links can be used to
    %     have a persons record available under
    %     multiple keys.
    data :: #person{} | #link{}
  }).

