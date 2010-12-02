-module(tcp_utils).
-compile([export_all]).

-spec(get_url/1::(Url::string()) -> {ok, _}).
get_url(Url) ->
  httpc:request(Url).
