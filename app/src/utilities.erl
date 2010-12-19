%% @author Sebastian Probst Eide
%% @doc Utility module with functionality
%%     used accross all Friend Search applications.
-module(utilities).
-compile(export_all). 

-define(CHORD_PORT, 4000).

-include_lib("kernel/include/inet.hrl").
-include("fs.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

%% @doc: returns the current time in gregorian seconds
-spec(get_time/0::() -> integer()).
get_time() ->
  calendar:datetime_to_gregorian_seconds(erlang:universaltime()).

-spec(get_join_node/2::(Ip::ip(), Port::port_number()) -> {ip(), port_number()} | first).
get_join_node(Ip, Port) ->
  Url = get_join_node_url(Ip, Port),
  {ok, Result} = tcp_utils:get_url(Url),
  Body = case Result of 
    {_, _, B} -> B;
    {_, B} -> B
  end,
  {struct, Data} = mochijson2:decode(Body),
  case proplists:get_value(<<"ip">>, Data) of
    undefined ->
      % Check if we are the first to join, if not, fail.
      case proplists:get_value(<<"first">>, Data) of
        true ->
          first
      end;
    IpVal ->
      % We have an Ip value. Extract the port and return the pair.
      JoinIp = get_ip_from_data(IpVal),
      JoinPort = proplists:get_value(<<"port">>, Data),
      {JoinIp, JoinPort}
  end.

-spec(get_ip_from_data/1::(Ip::bitstring()) -> ip()).
get_ip_from_data(Ip) ->
  erlang:list_to_tuple(
      lists:map(fun(S) -> list_to_integer(S) end, 
          string:tokens(erlang:bitstring_to_list(Ip), "."))).

%% @doc: Returns the Url of the server used to find nodes to join.
%% The default server is used unless the -joinsrvaddr and -joinsrvport
%% have been specified.
%% @todo: Have it check for user values.
-spec(get_join_node_url/2::(ip(), Port::integer()) ->
    string()).
get_join_node_url(Ip, Port) ->
  Host = "http://127.0.0.1:8000",
  Host ++ "/?port=" ++ integer_to_list(Port) ++ "&ip=" ++ ip_to_string(Ip).

-spec(ip_to_string/1::(ip()) -> string()).
ip_to_string({A,B,C,D}) ->
  lists:flatten(io_lib:format("~p.~p.~p.~p", [A,B,C,D])).

%% @doc: returns the port number at which chord is listening.
-spec(get_chord_port/0::() -> number()).
get_chord_port() ->
  case init:get_argument(chord_port) of
    {ok, [[PortNumber]]} ->
      list_to_integer(PortNumber);
    _ -> ?CHORD_PORT
  end.

%% @doc: returns the port number at which the webserver should be listening.
-spec(get_webmachine_port/0::() -> number() | none).
get_webmachine_port() ->
  case init:get_argument(fs_web_port) of
    {ok, [[PortNumber]]} ->
      list_to_integer(PortNumber);
    _ -> none
  end.

%% @doc Returns true if Key is in the range of Start and End. Since the
%%      values are along a circle, the numerical value of End might be less
%%      than that of Start.
%%      Otherwise it returns false.
-spec(in_range/3::(Key::key(), Start::key(), End::key()) -> boolean()).
in_range(Key, Start, End) ->
  case (Start < End) of
    true ->
      % Check that Key is in the range of Start and End
      (Start < Key) and (Key < End);
    false ->
      % Check that Key is greater than Start, or greater than 0 and less than End
      (Start < Key) or ((0 =< Key) and (Key < End))
  end.

%% @doc Returns true if Key is in the range of Start and up to and including End. 
%%      Since the values are along a circle, the numerical value of End might be less
%%      than that of Start.
%%      Otherwise it returns false.
-spec(in_inclusive_range/3::(Key::key(), Start::key(), End::key()) -> boolean()).
in_inclusive_range(Key, Start, End) ->
  case (Start < End) of
    true ->
      % Check that Key is in the range of Start and up to and including End
      (Start < Key) and (Key =< End);
    false ->
      % Check that Key is greater than Start, or greater than 0 and less than 
      % or equal to End
      (Start < Key) or ((0 =< Key) and (Key =< End))
  end.

-spec(add_bitstrings/2::(Bin1::bitstring(), Bin2::bitstring()) -> bitstring()).
add_bitstrings(Bin1, Bin2) when bit_size(Bin1) =:= bit_size(Bin2) ->
  add_bit_with_carry(bit_size(Bin1), Bin1, Bin2, false).


-spec(add_bit_with_carry/4::(integer(), bitstring(), bitstring(), atom()) ->
    bitstring()).
add_bit_with_carry(0, Acc, _Bin, _Carry) -> Acc;
add_bit_with_carry(BitNumber, AccBin1, Bin2, Carry) ->
  Bit = BitNumber - 1,
  <<Beginning:Bit/bitstring, B1:1/bitstring, Rest/bitstring>> = AccBin1,
  <<_DontYetCare:Bit/bitstring, B2:1/bitstring, _Rest/bitstring>> = Bin2,
  {NextBit, NextCarry} = case {B1, B2, Carry} of
    {<<0:1>>, <<0:1>>, true}  -> {1, false};
    {<<0:1>>, <<0:1>>, false} -> {0, false};
    {<<0:1>>, <<1:1>>, true}  -> {0, true};
    {<<0:1>>, <<1:1>>, false} -> {1, false};
    {<<1:1>>, <<0:1>>, true}  -> {0, true};
    {<<1:1>>, <<0:1>>, false} -> {1, false};
    {<<1:1>>, <<1:1>>, true}  -> {1, true};
    {<<1:1>>, <<1:1>>, false} -> {0, true}
  end,
  <<_:7/bitstring, B:1/bitstring>> = <<NextBit>>,
  add_bit_with_carry(Bit, 
      <<Beginning:Bit/bitstring, B:1/bitstring, Rest/bitstring>>, 
      Bin2, NextCarry).
  

-spec(bitstring_to_number/1::(BitString::bitstring()) -> number()).
bitstring_to_number(BitString) ->
  bitstring_to_number(BitString, bit_size(BitString), 0).
-spec(bitstring_to_number/3::(bitstring(), integer(), number()) -> number()).
bitstring_to_number(_BitString, 0, Acc) -> Acc;
bitstring_to_number(BitString, CurrBitNum, Acc) ->
  BitsToSkip = bit_size(BitString) - CurrBitNum,
  <<_:BitsToSkip/bitstring, CurrentBit:1/bitstring, _/bitstring>> = BitString,
  Addition = case CurrentBit of
    <<1:1>> -> 1 bsl (CurrBitNum - 1);
    _ -> 0
  end,
  bitstring_to_number(BitString, CurrBitNum - 1, Acc + Addition).
  

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


-spec(entry_for_record/1::(#person{} | #link{}) -> #entry{}).
entry_for_record(#person{} = Person) ->
  DowncasePerson = downcase_person(Person),
  #entry{
    key = key_for_data(DowncasePerson),
    timeout = get_time() + ?ENTRY_TIMEOUT,
    data = Person
  };
entry_for_record(#link{name_fragment = NameFrag} = Link) ->
  #entry{
    key = key_for_data(downcase_str(NameFrag)),
    timeout = get_time() + ?ENTRY_TIMEOUT,
    data = Link
  }.


-spec(get_ip/0::() -> ip_address()).
get_ip() ->
  case inet:gethostname() of
    {ok, HostName} ->
      case inet:gethostbyname(HostName) of
        {ok, Hostent} ->
          hd(Hostent#hostent.h_addr_list)
      end
  end.
     

-spec(key_for_node/2::(Ip::ip(), Port::port_number()) -> number()).
key_for_node(Ip, Port) ->
  key_for_data({Ip, Port}).


-spec(key_for_data/1::(Data::term()) -> number()).
key_for_data(Data) ->
  bitstring_to_number(term_to_sha(Data)).

%% ------------------------------------------------------------------
%% Tests
%% ------------------------------------------------------------------

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

in_range_test_() ->
  {inparallel, [
    ?_assertEqual(false, in_range(1,1,2)),
    ?_assertEqual(false,  in_range(2,1,2)),
    ?_assertEqual(false, in_range(2,2,4)),
    ?_assertEqual(true,  in_range(3,2,4)),
    ?_assertEqual(false,  in_range(4,2,4)),
    ?_assertEqual(false, in_range(4,4,0)),
    ?_assertEqual(true,  in_range(5,4,0)),
    ?_assertEqual(true,  in_range(5,4,0)),
    ?_assertEqual(true,  in_range(0,4,3)),
    ?_assertEqual(false,  in_range(0,4,0)),
    ?_assertEqual(true,  in_range(5,4,0))
  ]}.

in_inclusive_range_test_() ->
  {inparallel, [
    ?_assertEqual(false, in_inclusive_range(1,1,2)),
    ?_assertEqual(true,  in_inclusive_range(2,1,2)),
    ?_assertEqual(false, in_inclusive_range(2,2,4)),
    ?_assertEqual(true,  in_inclusive_range(3,2,4)),
    ?_assertEqual(true,  in_inclusive_range(4,2,4)),
    ?_assertEqual(false, in_inclusive_range(4,4,0)),
    ?_assertEqual(true,  in_inclusive_range(5,4,0)),
    ?_assertEqual(true,  in_inclusive_range(6,4,0)),
    ?_assertEqual(true,  in_inclusive_range(7,4,0)),
    ?_assertEqual(true, in_inclusive_range(0,4,0))
  ]}.

key_for_data_test() ->
  Data = {some, random, data},
  CalculatedKey = key_for_data(Data),
  ?assert(is_number(CalculatedKey)),
  ManuallyCreatedKey = bitstring_to_number(term_to_sha(Data)),
  ?assertEqual(ManuallyCreatedKey, CalculatedKey).

add_bitstrings_test_() ->
  {inparallel,
  [?_assertEqual(<<2>>, add_bitstrings(<<1>>, <<1>>)),
   ?_assertEqual(<<1>>, add_bitstrings(<<0>>, <<1>>)),
   ?_assertEqual(<<1>>, add_bitstrings(<<1>>, <<0>>)),
   ?_assertEqual(<<0>>, add_bitstrings(<<255>>, <<1>>))]}.

bitstring_to_num_test_() ->
  {inparallel,
    [?_assertEqual(1, bitstring_to_number(<<1>>)),
     ?_assertEqual(2, bitstring_to_number(<<2>>)),
     ?_assertEqual(255, bitstring_to_number(<<255>>)),
     ?_assertEqual(65535, bitstring_to_number(<<255,255>>)),
     ?_assertEqual(1461501637330902918203684832716283019655932542975, bitstring_to_number(<<255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255>>))
   ]}.

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

should_roughly_equal(A, B, Delta) ->
    A < (B + Delta) andalso A > (B - Delta).

entry_for_person_test() ->
  Person = test_utils:test_person_sebastianA(),
  EntryHash = bitstring_to_number(term_to_sha(downcase_person(Person))),
  TimeNow = get_time(),
  #entry{key = Key, timeout = Timeout, data = Person } = entry_for_record(Person),
  ?assertEqual(EntryHash, Key),
  ?assert(should_roughly_equal(Timeout, TimeNow + ?ENTRY_TIMEOUT, 5)).

entry_for_link_test() ->
  Link = test_utils:test_link1(),
  TimeNow = get_time(),
  EntryHash = bitstring_to_number(term_to_sha(Link#link.name_fragment)),
  #entry{key = Key, timeout = Timeout, data = Link } = entry_for_record(Link),
  ?assertEqual(EntryHash, Key),
  ?assert(should_roughly_equal(Timeout, TimeNow + ?ENTRY_TIMEOUT, 5)).

get_ip_test() ->
  % Should return a set of IP values
  {_A, _B, _C, _D} = get_ip().

key_for_node_test() ->
  IP1 = {1,2,3,4},
  IP2 = {2,3,4,5},
  Port1 = 1234,
  Port2 = 2345,
  ?assert(key_for_node(IP1, Port1) =/= key_for_node(IP2, Port1)),
  ?assert(key_for_node(IP1, Port1) =/= key_for_node(IP2, Port2)),
  ?assert(key_for_node(IP1, Port1) =/= key_for_node(IP1, Port2)),
  ?assert(key_for_node(IP1, Port1) =:= key_for_node(IP1, Port1)).

get_join_node_url_test() ->
  Ip = {1,2,3,4}, Port = 2,
  ?assertEqual("http://127.0.0.1:8000/?port=2&ip=1.2.3.4",
    get_join_node_url(Ip, Port)).

get_join_node_not_first_test() ->
  Ip = {127,0,0,1}, Port = 5678,

  ServerReturn = {{"HTTP/1.1",200,"OK"},
   [{"date","Thu, 18 Nov 2010 10:47:54 GMT"},
    {"server",
     "MochiWeb/1.1 WebMachine/1.7.3 (participate in the frantic)"},
    {"content-length","34"},
    {"content-type","text/html"}],
   "{\"ip\":\"127.0.0.2\",\"port\":1234}"},

  Url = get_join_node_url(Ip, Port),

  erlymock:start(),
  erlymock:strict(tcp_utils, get_url, [Url], [{return, {ok, ServerReturn}}]),
  erlymock:replay(), 
  ?assertEqual({{127,0,0,2}, 1234}, get_join_node(Ip, Port)),
  erlymock:verify().

get_join_node_first_test() ->
  Ip = {127,0,0,1}, Port = 5678,

  ServerReturn = {{"HTTP/1.1",200,"OK"},
     [{"date","Wed, 01 Dec 2010 09:25:54 GMT"},
      {"server",
       "MochiWeb/1.1 WebMachine/1.7.3 (participate in the frantic)"},
      {"content-length","14"},
      {"content-type","text/html"}],
     "{\"first\":true}"},
 
  Url = get_join_node_url(Ip, Port),

  erlymock:start(),
  erlymock:strict(tcp_utils, get_url, [Url], [{return, {ok, ServerReturn}}]),
  erlymock:replay(), 
  ?assertEqual(first, get_join_node(Ip, Port)),
  erlymock:verify().

get_ip_from_data_test_() ->
  [
    ?_assertEqual({1,2,3,4}, get_ip_from_data(<<"1.2.3.4">>)),
    ?_assertEqual({127,0,0,1}, get_ip_from_data(<<"127.0.0.1">>))
  ].

ip_to_string_test() ->
  ?assertEqual("127.0.0.1", ip_to_string({127,0,0,1})).

-endif.
