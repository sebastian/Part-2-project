-type(key() :: binary()).
-type(binary_string() :: binary()).

-record(entry, {
    key :: key(),
    name :: binary_string()
  }).

