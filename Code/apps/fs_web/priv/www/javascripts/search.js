///////////////////////////////////////////////////////////////////////////////
// Search class

/*
 * Class that handles searches
 */
SearchController = function() {
  // Cache search results. Keyed on query
  this.searchCache = {};

  // Current search results
  this.searchResults = [{name: 'Sebastian'}];

  // Bind to the search text field
  this.$watch('q', this.find);
};


/*
 * Performs a search for a query, and uses the 
 * delegate to update the page with the results.
 * @param {string} query The string to search for
 * @void
 */
SearchController.prototype.find = function(query) {
  // Check if there is a cached result for the query
  if (this.searchCache[query] != null) {
    this.searchResults = this.searchCache[query].data;
    return;
  }  
  
  // There is no cached result, perform search
  var that = this;
  $.getJSON('/search', {'q':query}, function(result) {
    that.searchResults = result.data;

    // Now cache the result
    that.searchCache[query] = result; 
  });
};
