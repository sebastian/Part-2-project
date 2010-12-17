# Planned structure of app:

## Search app
Should have:

* a web component (using webmachine) interacting with a backend.
* a backend using the DHT as a data storage to find values given a key

### Public facing webserver
1. Should produce output in JSON format to plain text queries.
2. Should allow the user to add user records that are maintained in the index.

#### Querying 

1. Search for user
[GET] /search?q={URL encoded search query}
  Returns a (potentially empty) list of results. All in JSON format.

#### Adding or removing user entries
1. Adding user entries:
[POST] /entries
  Structured JSON data following pattern discussed below

1. Removing a user entry
[DELETE] /entries/{KEY}
  Always returns OK regardless of it the entry exists or not.
  The entry will only be deleted from the local index, and will
  vanish from the global search index once it times out.

1. Listing user entries
[GET] /entries
  Returns a list of structured data of all the user entries maintained
  by the local search system

#### Accessing a particular entry
1. Get a particular user entry
[GET] /entries/{KEY}
  Returns user entry from the search index. It will hit the global index
  unless it has a local cache.


### Potential structure of data stored in DHTs
#### User record:
* Key (hash of full name)
* Full name of user
* Url of avatar
* Url of profile
* Timeout (time value)
* Protocol used for profile (in case that exists at some point in the future)

#### Link record for partial matches
These kinds of records can be stored for partial names in order to allow predictive search, or searches for partial names.

* Key (hash of partial name)
* partial name searched for (redundant info, but might be useful in cases where several requests are in flight to differentiate responses. Remove?)
* full name of user
* Timeout value (decremented by storage node)
* key of full user record (hash of full name of user) (this is potentially redundant, but might speed things up lookups? Should remove?)


## FriendSearch
The friend search module keeps a list of records owned by the current instance
and is responsible for keeping them allive in the search index by using the DHT
set methods.
It is also used to query the search network.
Additionally the friend index also alows the system to swap which DHT is to be
used.

## DHT layer
The distributed hash tables should all implement the following common erlang
API:

set/3
  Sets a value for a key in the system. Please note that the system uses a bag
  approach where a key might have several values.
  Args:
    Key : Key by which to store the items
    Value : Some data
    Timeout : The timeout value for the value in seconds
  Returns:
    ok
    {error, Reason} 

get/1
  Gets a list of values for a given key.
  Arg:
    Key : The key of the item to retrieve
  Returns:
    {ok, ListOfValues} where ListOfValues is a potentially empty list of the data corresponding to key Key
    {error, Reason} where Reason might be one of:
      instance - internal error
      network - no network connection

### DataStore
The datastore is used by the DHTs to store data that is associated with the
keyspace that is the responsibility of the given DHT node.
It automatically removes entries that time out.
It has a notion of records that it is responsible for, and records it is only
maintaining copies of for others.
Upon receiving a new data item it ensures that the items timeout value doesn't
exceed a system wide allowed maximum value.
