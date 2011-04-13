# Friend search in distributed social networks
This is the repository of my Part 2 project at the University of Cambridge.
I am creating a distributed social friend search application for online distributed decentralized social networks that allow the users to find their friends, independently of in which social network they have their profiles, and where that social network is hosted.

So far I have implemented the Distributed Hash Tables Chord and Pastry. My
implementation of Pastry greatly outperforms my implementation of Chord both in
terms of key lookup latency, lookup successrate and system utilization.

I have also developed a bare bones search application that uses either Chord or
Pastry as a backend datastore, and can find profile records in the search
network, and allows for predictive searching.

## Things to consider
- How can one avoid spammy entries in a distributed and decentralized network where anyone is free to join and contribute with data?
- How one can implement fuzzy search/predictive search more efficiently on top of a key-value datastore?
- How one can incorporate metadata like the a users social circles and friends of friends to give better prioritization in the search result when all the data is decentralized?

## Contact
If you have any questions, please contact me on:
sebastian.probst.eide@gmail.com
