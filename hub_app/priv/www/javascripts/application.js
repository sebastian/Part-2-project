var nodesRef = null;

function compile(){
	var nodesDirectives = {
    'div':{
      'controller<-controllers':{
        'a@href':"http://#{controller.ip}:11385/",
        'a':'controller.ip',
        'span':"#{controller.mode} - #{controller.nodes.length} nodes",
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
function getNodes() {
	$.get('/nodes', cbNodes);
};

function init(){
	nodesRef = compile();
  getNodes();
  setInterval(getNodes, 2000);

  $("#switch_to_chord").click(function() {
    $.post('switch_mode/chord');
    return false;
  });
  $("#switch_to_pastry").click(function() {
    $.post('switch_mode/pastry');
    return false;
  });
  $("#start_node").click(function() {
    $.post('nodes/start/1');
    return false;
  });
  $("#stop_node").click(function() {
    $.post('nodes/stop/1');
    return false;
  });

}

$(document).ready(function(){
	init();
});
