%% @author Sebastian Probst Eide
%% @doc Utility module with functionality
%%     used accross all Friend Search applications.
-module(utilities).
-compile(export_all). 

-include("records.hrl").

-spec(downcase_str/1::(binary() | 'undefined') -> binary()).
downcase_str('undefined') ->
  'undefined';
downcase_str(BitStr) ->
  list_to_bitstring(string:to_lower(bitstring_to_list(BitStr))).

%% @doc Before a person record is being used to make a key
%%     it is normalised to ensure that small changes in
%%     otherwise identical profiles, don't affect its location
%%     in the storage network.
-spec(downcase_person/1::(Person::#person{}) -> #person{}).
downcase_person(Person = #person{}) ->
  Person#person{
    name = downcase_str(Person#person.name),
    human_profile_url = downcase_str(Person#person.human_profile_url),
    machine_profile_url = downcase_str(Person#person.machine_profile_url),
    profile_protocol = downcase_str(Person#person.profile_protocol),
    avatar_url = downcase_str(Person#person.avatar_url)
  }.

-spec(term_to_sha/1::(Term::any()) -> binary()).
term_to_sha(Term) ->
  crypto:sha(term_to_binary(Term)).

-spec(key_for_record/1::(Person::#person{}) -> binary()).
key_for_record(Person) ->
  crypto:sha(term_to_binary(Person)).

-spec(entry_for_record/1::(#person{} | #link{}) -> #entry{}).
entry_for_record(#person{} = Person) ->
  DowncasePerson = downcase_person(Person),
  #entry{
    key = key_for_record(DowncasePerson),
    timeout = ?ENTRY_TIMEOUT,
    data = Person
  };
entry_for_record(#link{name_fragment = NameFrag} = Link) ->
  #entry{
    key = key_for_record(downcase_str(NameFrag)),
    timeout = ?ENTRY_TIMEOUT,
    data = Link
  }.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Tests
%%

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

lowercase_string_test() ->
  ?assertEqual(<<"seb">>, downcase_str(<<"Seb">>)),
  ?assertEqual(<<"sebastian probst eide">>, downcase_str(<<"Sebastian Probst Eide">>)).

downcase_person_test() ->
  Person = test_utils:test_person_sebastianA(),
  DP = downcase_person(Person),
  ?assertEqual(downcase_str(Person#person.name), DP#person.name),
  ?assertEqual(downcase_str(Person#person.human_profile_url), DP#person.human_profile_url),
  ?assertEqual(downcase_str(Person#person.machine_profile_url), DP#person.machine_profile_url),
  ?assertEqual(downcase_str(Person#person.profile_protocol), DP#person.profile_protocol),
  ?assertEqual(downcase_str(Person#person.avatar_url), DP#person.avatar_url).

term_to_sha_test() ->
  Person = test_utils:test_person_sebastianA(),
  ?assertEqual(crypto:sha(term_to_binary(Person)), term_to_sha(Person)).

key_for_record_test() ->
  Person = test_utils:test_person_sebastianA(),
  Hash = crypto:sha(term_to_binary(Person)),
  ?assertEqual(Hash, key_for_record(Person)).

entry_for_person_test() ->
  Person = test_utils:test_person_sebastianA(),
  EntryHash = term_to_sha(downcase_person(Person)),
  #entry{key = Key, timeout = Timeout, data = Person } = entry_for_record(Person),
  ?assertEqual(EntryHash, Key),
  ?assertEqual(Timeout, ?ENTRY_TIMEOUT).

entry_for_link_test() ->
  Link = test_utils:test_link1(),
  EntryHash = term_to_sha(Link#link.name_fragment),
  #entry{key = Key, timeout = Timeout, data = Link } = entry_for_record(Link),
  ?assertEqual(EntryHash, Key),
  ?assertEqual(Timeout, ?ENTRY_TIMEOUT).

-endif.
