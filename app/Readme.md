# Planned structure of app:

## Search app
Should have:

* a web component (using webmachine) interacting with a backend.
* a backend using the DHT as a data storage to find values given a key

The web component should be a website with a simple form communicating via JSON or another suitable format with the server. API of backend server is still to be determined.

The server should support the following actions:
1. Adding, listing and removing local users
2. Performing searches

### Adding or removing user entries that should be stored in the index
1. Adding user entries:
[POST] /entries
  Structured JSON data following pattern discussed below

1. Removing a user entry
[DELETE] /entries/{KEY}
  Always returns OK regardless of it the entry exists or not

1. Listing user entries
[GET] /entries
  Returns a list of structured data of all the user entries maintained
  by the local search system

1. Get a particular user entry
[GET] /entries/{KEY}
  Returns user entry either from local or remote store

### querying the global search index

1. Search for user
[GET] /search?q={URL encoded search query}
  Returns a (potentially empty) list of results.


### Potential structure of data stored in DHTs
#### User record:
* Key (hash of full name)
* Full name of user
* Url of avatar
* Url of profile
* Timeout value (decremented by storage node)
* Protocol used for profile (in case that exists at some point in the future)

#### Link record for partial matches
These kinds of records can be stored for partial names in order to give the system a predictive behaviour. These should only be added as an extension.

* Key (hash of partial name)
* partial name searched for (redundant info, but might be useful in cases where several requests are in flight to differentiate responses. Remove?)
* full name of user
* Timeout value (decremented by storage node)
* key of full user record (hash of full name of user) (this is potentially redundant, but might speed things up lookups? Should remove?)


## DHT layer
The distributed hash tables should all implement the following common erlang
API:

start/0
  Synchronous call starting a supervised DHT node
  Returns:
    ok - if everything works
    {error, Reason} if it fails, where Reason is one of
      instance - for internal errors
      network - for network connection errors

stop/0
  Stops the current DHT node
  Returns:
    ok

set/3
  Sets a value for a key in the system. Please note that the system uses a bag
  approach where a key might have several values.
  Args:
    Key : Key by which to store the items
    Value : Some data
    Timeout : The timeout value for the value in seconds
  Returns:
    ok
    {error, Reason} where Reason might be one of:
      instance - internal error
      network - no network connection

get/1
  Gets a list of values for a given key.
  Arg:
    Key : The key of the item to retrieve
  Returns:
    {ok, ListOfValues} where ListOfValues is a list of the data corresponding to key Key
    {error, Reason} where Reason might be one of:
      instance - internal error
      network - no network connection

## Shared utility functions

key_for_data/1
  Computes a key for a data item
  Arg:
    Data : Erlang data record
  Returns:
    key

key_for_node/2
  Returns the current nodes key
  Arg:
    IP : The nodes public IP
    Port : The nodes port number
  Returns:
    Unique key locating the node in the DHT
