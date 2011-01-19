var nodesRef = null;

function compile(){
	var nodesDirectives = {
    'div':{
      'set<-datasets':{
        'h1':'set.title',
          'ul li':{
          'node<-set.nodes':{
            '.':"Ip: #{node.ip}, port: #{node.port}"
          }
        }
      }
    }
	};
	return $p("div#templates div.nodes").compile(nodesDirectives);
}
function renderNodes(json){
	var data = {
    datasets: [
      {title: 'Chord nodes', nodes: json.chord_nodes},
    	{title: 'Pastry nodes', nodes: json.pastry_nodes}
    ]
  };
  var cont = nodesRef(data);
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
