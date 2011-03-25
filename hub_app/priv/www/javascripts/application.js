var nodesRef = null;
var expRef = null;

function compileNodes(){
	var nodesDirectives = {
    'div':{
      'controller<-controllers':{
        'a@href':"http://#{controller.ip}:11385/",
        'a':'controller.ip',
        'span span#tn':"#{controller.mode} - #{controller.node_count} nodes",
        'span span#vsn':"version #{controller.version}",
      }
    }
	};
	return $p("div#templates div.controllers").compile(nodesDirectives);
}
function compileExperiment(){
	var experimentDirectives = {
    'ul':{
      'status<-experiments':{
        'li':'status'
      }
    }
	};
	return $p("div#templates div.experiment").compile(experimentDirectives);
}
function renderStatus(json){
  var cont = nodesRef(json);
	$("div#hosts").html(cont);
  exp = expRef(json);
	$("div#experiment").html(exp);
	$("span#log_status").html("Status: " + json.log_status);
	$("span#version").html("Version: " + json.hub_version + ", Hosts: " + json.controllers.length);
}

/**
 * Ajax functions
 */
function getStatus() {
	$.get('/nodes', renderStatus);
};

function init(){
	nodesRef = compileNodes();
	expRef = compileExperiment();
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
  $("#ensure_running_n").click(function() {
    var count = $("#num_nodes").val();
    $.post('nodes/ensure_running_n/' + count);
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
  $(".experiment_action").click(function() {
    var action = this.id;
    $.post('experiment/' + action);
    return false;
  });
  $("#fixed_rate_experiment").click(function() {
    var time = $("#exp_time").val();
    var rate = $("#exp_rate").val();
    $.post('fixed_rate/' + rate + '/for_time/' + time);
    return false;
  });
}

$(document).ready(function(){
	init();
});
