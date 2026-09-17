(function(){
"use strict";

var BAR_ID="jgwTaskBulkActionsV3";
var WATER_ID="jgwAllWateredV3";
var LATER_ID="jgwAllLaterV3";
var observer=null;

function taskRows(){
  var list=document.getElementById("tasks");
  if(!list)return [];
  return Array.prototype.slice.call(list.querySelectorAll(".task[data-task-id][data-task-kind]"));
}

function buildBar(list){
  var bar=document.getElementById(BAR_ID);
  if(bar)return bar;

  bar=document.createElement("div");
  bar.id=BAR_ID;
  bar.className="jgw-task-bulk-actions";
  bar.setAttribute("aria-label","Alle offenen Aufgaben bearbeiten");
  bar.style.display="none";
  bar.style.gridTemplateColumns="1fr 1fr";
  bar.style.gap="8px";
  bar.style.margin="0 0 10px";

  var water=document.createElement("button");
  water.id=WATER_ID;
  water.type="button";
  water.className="btn small";
  water.textContent="💧 Alle gegossen";
  water.style.width="100%";
  water.style.minHeight="40px";

  var later=document.createElement("button");
  later.id=LATER_ID;
  later.type="button";
  later.className="btn ghost small";
  later.textContent="Alle später";
  later.style.width="100%";
  later.style.minHeight="40px";

  bar.appendChild(water);
  bar.appendChild(later);
  list.parentNode.insertBefore(bar,list);
  return bar;
}

function refresh(){
  var list=document.getElementById("tasks");
  if(!list)return;
  var bar=buildBar(list);
  var rows=taskRows();
  var waterRows=rows.filter(function(row){return row.dataset.taskKind==="water";});
  var water=document.getElementById(WATER_ID);
  var later=document.getElementById(LATER_ID);

  bar.style.display=rows.length?"grid":"none";
  if(water){
    water.disabled=!waterRows.length;
    water.title=waterRows.length?waterRows.length+" offene Gießaufgabe"+(waterRows.length===1?"":"n")+" erledigen":"Keine Gießaufgabe offen";
  }
  if(later){
    later.disabled=!rows.length;
    later.title=rows.length?rows.length+" offene Aufgabe"+(rows.length===1?"":"n")+" auf später setzen":"Keine Aufgabe offen";
  }
}

function clickAllWatered(){
  var rows=taskRows().filter(function(row){return row.dataset.taskKind==="water";});
  rows.forEach(function(row){
    var button=row.querySelector(".taskDone[data-kind='water']");
    if(button&&!button.disabled)button.click();
  });
  setTimeout(refresh,950);
}

function clickAllLater(){
  var rows=taskRows();
  rows.forEach(function(row){
    var button=row.querySelector(".taskLater");
    if(button&&!button.disabled)button.click();
  });
  setTimeout(refresh,750);
}

function bind(){
  document.addEventListener("click",function(e){
    var target=e.target&&e.target.closest?e.target.closest("button"):null;
    if(!target)return;
    if(target.id===WATER_ID){e.preventDefault();clickAllWatered();}
    if(target.id===LATER_ID){e.preventDefault();clickAllLater();}
  });
}

function watch(){
  var list=document.getElementById("tasks");
  if(!list)return false;
  if(observer)observer.disconnect();
  observer=new MutationObserver(function(){refresh();});
  observer.observe(list,{childList:true,subtree:true});
  refresh();
  return true;
}

function start(){
  bind();
  if(watch())return;
  var rootObserver=new MutationObserver(function(){
    if(watch())rootObserver.disconnect();
  });
  rootObserver.observe(document.documentElement,{childList:true,subtree:true});
}

if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",start,{once:true});
else start();
window.addEventListener("load",function(){watch();refresh();},{once:true});
window.addEventListener("pageshow",function(){setTimeout(refresh,0);});
})();
