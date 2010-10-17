Planned structure of app:

## Search app
Should have:

* a web component (using webmachine) interacting with a backend.
* a backend using the DHT as a data storage to find values given a key

The web component should be a website with a simple form communicating via JSON or another suitable format with the server. API of backend server is still to be determined.

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


