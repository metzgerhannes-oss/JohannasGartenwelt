(function(){
"use strict";
/*
  Legacy advisor retired.
  Current recommendations live in jgw-library-v4.js.
  This compatibility module only adds mobile task polish and DOM-based
  task helpers. It deliberately does not depend on private functions from
  the main app bundle because index.html runs inside an IIFE.
*/
window.JGWLegacyAdvisorRetired=true;

var STYLE_ID="jgw-today-polish";

function installTodayPolish(){
  var old=document.getElementById(STYLE_ID);
  if(old)old.remove();
  

  var task=document.querySelector("#view-calendar .dashboard-task-box");
  if(task){
    var title=task.querySelector("h3");
    var subtitle=task.querySelector(".topline .muted");
    if(title)title.textContent="Heute wichtig";
    if(subtitle)subtitle.textContent="Nur das, was heute wirklich ansteht.";
  }
}

function start(){
  installTodayPolish();
}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",start,{once:true});
else start();
window.addEventListener("load",installTodayPolish,{once:true});
})();
