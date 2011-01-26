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
function renderStatus(json){
  var cont = nodesRef(json);
	$("div#main-content").html(cont);
	$("span#log_status").html("Status: " + json.log_status);
	$("span#version").html("Version: " + json.hub_version);
}

/**
 * Ajax functions
 */
function getStatus() {
	$.get('/nodes', renderStatus);
};

function init(){
	nodesRef = compile();
  getStatus();
  setInterval(getStatus, 2000);

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
  $(".log_action").click(function() {
    var action = this.id;
    $.post('logging/' + action);
    return false;
  });
  $("#system_upgrade").click(function() {
    $.post('upgrade_systems');
    return false;
  });


}

$(document).ready(function(){
	init();
});
