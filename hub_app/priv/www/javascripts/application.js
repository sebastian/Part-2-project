var nodesRef = null;

function compile(){
	var nodesDirectives = {
    'div':{
      'controller<-controllers':{
        'h1':"#{controller.ip} in #{controller.mode} mode",
          'ul li':{
          'node<-controller.nodes':{
            '.':'node'
          }
        }
      }
    }
	};
	return $p("div#templates div.controllers").compile(nodesDirectives);
}
function renderNodes(json){
  var cont = nodesRef(json);
	$("div#main-content").html(cont);
}
function cbNodes(json) {
	renderNodes(json)
};

/**
 * Ajax functions
 */
function get(url, callback) {
	$.get(url, callback);
};

function init(){
	nodesRef = compile();
	get('/nodes', cbNodes);
}

$(document).ready(function(){
	init();
});
