-ifdef(TEST).
-module(test_utils).
-compile([export_all]).

-include("records.hrl").

test_person_sebastianA() ->
  #person{
    name = <<"Sebastian Probst Eide">>,
    human_profile_url = <<"http://somesite.com">>
    % etc
  }.

test_person_sebastianB() ->
  #person{
    name = <<"Sebastian Probst Eide">>,
    human_profile_url = <<"http://othersite.com">>
  }.

test_person_entry_1a() ->
  #entry{
    key = <<"ABCD">>,
    timeout = 60*60*5,
    data = test_person_sebastianA()
  }.

test_person_entry_1b() ->
  #entry{
    key = <<"ABCD">>,
    timeout = 60*60*5,
    data = test_person_sebastianB()
  }.

-endif.
