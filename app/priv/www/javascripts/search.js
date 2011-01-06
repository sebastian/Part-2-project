///////////////////////////////////////////////////////////////////////////////
// Person class
angular.service('PersonResource', function($resource){
  this.Person = $resource('/entries/:key', {key:"@key"});
}, {inject:['$resource']});


///////////////////////////////////////////////////////////////////////////////
// Person class
angular.service('QueryResource', function($resource){
  this.Search = $resource('/search', {}, {
    find: {method:'GET'}
  });
}, {inject:['$resource']});


///////////////////////////////////////////////////////////////////////////////
// Search class

/**
 * Class that handles searches
 */
SearchController = function() {
  // Show different parts of site conditionally
  this.location = {'home' : true};
  this.$watch('$location.hashPath', this.changeOfLocation);

  // Bind to the search text field
  this.$watch('q', this.find);
  
  // The profile URL to show
  this.currentProfile = {'name': "Please perform a search"};
};


/**
 * Performs a search for a query, and uses the 
 * delegate to update the page with the results.
 * @param {string} query The string to search for
 * @void
 */
SearchController.prototype.changeOfLocation = function() {
  var loc = this.$location.hashPath;
  if (loc == "addPerson") {this.location = {'addPerson' : true};}
  else if (loc == "home") {this.location = {'home' : true};}
  else if (loc == "profile") {this.location = {'profile' : true};}
  else {this.location = {'home' : true};}
};


/**
 * Performs a search for a query, and uses the 
 * delegate to update the page with the results.
 * @param {string} query The string to search for
 * @void
 */
SearchController.prototype.find = function(query) {
  this.searchResults = this.Search.find({q: query});
};


/**
 * Adds a new person record to the Dht
 * @void
 */
SearchController.prototype.addPerson = function() {
  var person = new this.Person(this.new_person);
  person.$save();
  // Reset the form
  this.new_person = {};
};


/**
 * Sets the current profile Url. It will automatically be reflected
 * on the page
 * @void
 */
SearchController.prototype.setProfile = function(Profile) {
  this.currentProfile = Profile;
  this.$location.hash = "profile";
};


/**
 * Adds a new person record to the Dht
 * @void
 */
SearchController.prototype.addTestData = function() {
  $("#addTestDataLi").fadeOut();

  (new this.Person({
    'name': 'Seb',
    'profile_url': 'http://www.facebook.com/sebastianprobsteide',
    'avatar_url':'http://profile.ak.fbcdn.net/hprofile-ak-snc4/hs450.snc4/49456_804615650_6743_q.jpg'
  })).$save();

  (new this.Person({
    'name': 'Sebastian Probst Eide',
    'profile_url': 'http://www.facebook.com/sebastianprobsteide',
    'avatar_url':'http://profile.ak.fbcdn.net/hprofile-ak-snc4/hs450.snc4/49456_804615650_6743_q.jpg'
  })).$save();

  (new this.Person({
    'name': 'Maria Catrin Larell Eide',
    'profile_url': 'http://www.facebook.com/profile.php?id=802600709',
    'avatar_url':'http://profile.ak.fbcdn.net/hprofile-ak-snc4/hs468.snc4/49292_802600709_2834_q.jpg'
  })).$save();

  (new this.Person({
    'name': 'Johan Wilhelm Eide',
    'profile_url': 'http://www.facebook.com/johan.eide',
    'avatar_url':'http://profile.ak.fbcdn.net/hprofile-ak-snc4/hs224.ash2/48979_805620594_8564_q.jpg'
  })).$save();

  (new this.Person({
    'name': 'Eugene Chan',
    'profile_url': 'http://www.facebook.com/weexian',
    'avatar_url':'http://profile.ak.fbcdn.net/hprofile-ak-snc4/hs1340.snc4/161192_510634457_1815111_q.jpg'
  })).$save();

  (new this.Person({
    'name': 'Felix Bauer',
    'profile_url': 'http://www.facebook.com/fjab1',
    'avatar_url':'http://profile.ak.fbcdn.net/hprofile-ak-snc4/hs1433.snc4/173429_571400595_4547011_q.jpg'
  })).$save();

  (new this.Person({
    'name': 'Sabine Anna Katharina',
    'profile_url': 'http://www.facebook.com/sabineannakatharina',
    'avatar_url':'http://profile.ak.fbcdn.net/hprofile-ak-snc4/hs1319.snc4/161103_578015554_8226379_q.jpg'
  })).$save();

  (new this.Person({
    'name': 'Martina Probst Eide',
    'profile_url': 'http://www.facebook.com/profile.php?id=1104439214',
    'avatar_url':'http://profile.ak.fbcdn.net/hprofile-ak-snc4/hs718.ash1/161506_1104439214_1398174_q.jpg'
  })).$save();

  (new this.Person({
    'name': 'Josh Ward',
    'profile_url': 'http://www.facebook.com/joshua.m.ward',
    'avatar_url':'http://profile.ak.fbcdn.net/hprofile-ak-snc4/hs442.snc4/48826_17115867_2152666_q.jpg'
  })).$save();

  (new this.Person({
    'name': 'Armita Atabaki',
    'profile_url': 'http://www.facebook.com/profile.php?id=1262811286',
    'avatar_url':'http://profile.ak.fbcdn.net/hprofile-ak-snc4/hs1328.snc4/161829_1262811286_4989806_q.jpg'
  })).$save();
};
