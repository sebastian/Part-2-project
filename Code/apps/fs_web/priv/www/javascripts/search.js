// Variables holding class instances used throughout the application
var page = null;
var search = null;

/*
 * The top level Friend Search javascript namespace
 */
var fs = {};


/*
 * Main method of javascript
 * Initializes the global search and page objects, and adds
 * listeners to the page.
 */
$(document).ready(function() {
  // Setup search instance
  search = new fs.Search();

  // Setup page instance
  page = new fs.Page();
  // Make it listen for changes
  page.addListeners();

});


///////////////////////////////////////////////////////////////////////////////
// Page class

/*
 * Class that encapsulates the page
 * and handles events as they happen.
 */
fs.Page = function() {
  // Dom elements for inputting search
  // queries
  this.searchBox = $('#search'); 
  this.submitButton = $('#searchBtn');

  // Record the value of the search box
  // so we can monitor if it changes on
  // keypress
  this.currentSearchBoxValue = '';
};


/*
 * Adds event listeners in order to 
 * handle searches correctly
 * @void
 */
fs.Page.prototype.addListeners = function() {
  var that = this;
  this.searchBox.keypress(function() {
    if (that.searchBox.val() != this.currentSearchBoxValue) {
      that.currentSearchBoxValue = that.searchBox.val();
      that.performSearch();
    }
  });
  this.searchBox.submit(this.performSearch);
  this.submitButton.click(this.performSearch);
};


/*
 * Is called whenever there is a change.
 * The result of the call is a search invocation.
 */
fs.Page.prototype.performSearch = function() {
  var currentSearchValue = this.searchBox.val();
  search.find(currentSearchValue, this);
};


/*
 * Handles results from the search server
 */
fs.Page.prototype.updateWithResponse = function(response) {
  // Do clever presentation of results...
};


///////////////////////////////////////////////////////////////////////////////
// Search class

/*
 * Class that handles searches
 */
fs.Search = function() {
  // Cache search results. Keyed on query
  this.searchCache = {};
};


/*
 * Performs a search for a query, and uses the 
 * delegate to update the page with the results.
 * @param {string} query The string to search for
 * @param {object} delegate The delegate object
 * @void
 */
fs.Search.prototype.find = function(query, delegate) {
  // Check if there is a cached result for the query
  if (this.searchCache[query] != null) {
    delegate.updateWithResponse(this.searchCache[query]);
    return;
  }  
  
  // There is no cached result, perform search

  var that = this;
  $.get('/search', {'q':query}, function(result) {
    delegate.updateWithResponse(result);

    // Now cache the result
   that.searchCache[query] = result; 
  });
};
