(function(){
"use strict";
/*
  Legacy advisor retired.
  Current recommendations live in jgw-library-v4.js (Bibliothek / Was passt noch?).
  This small compatibility module now contains mobile UI polish plus lightweight
  today-task fixes that do not require touching the main index.html bundle.
*/
window.JGWLegacyAdvisorRetired=true;

var STYLE_ID="jgw-today-polish";
function installTodayPolish(){
  var old=document.getElementById(STYLE_ID);
  if(old)old.remove();
  var css=document.createElement("style");
  css.id=STYLE_ID;
  css.textContent=`
/* Gartenlage: three compact cards must stay readable on narrow iPhones. */
@media(max-width:700px){
  .state-grid{
    grid-template-columns:minmax(0,.9fr) minmax(0,1.1fr) minmax(0,1fr)!important;
    gap:7px!important;
  }
  .state-item{padding:10px 8px!important;min-width:0!important}
  .state-item .state-label{
    font-size:9px!important;
    letter-spacing:.035em!important;
    line-height:1.1!important;
    white-space:nowrap!important;
  }
  .state-item .state-value{
    font-size:13px!important;
    line-height:1.25!important;
    overflow-wrap:anywhere;
  }

  /* Today tasks: compact, readable cards instead of a three-column squeeze. */
  #view-calendar .dashboard-task-box{
    padding:15px!important;
    border-radius:18px!important;
    background:rgba(255,253,249,.98)!important;
    border-color:#e6dbcf!important;
    box-shadow:0 4px 14px rgba(65,77,59,.055)!important;
  }
  #view-calendar .dashboard-task-box>.topline{
    align-items:flex-start!important;
    flex-wrap:nowrap!important;
    gap:10px!important;
    margin-bottom:10px!important;
  }
  #view-calendar .dashboard-task-box>.topline>div{min-width:0}
  #view-calendar .dashboard-task-box h3{
    font-size:23px!important;
    line-height:1.05!important;
    margin:0 0 4px!important;
  }
  #view-calendar .dashboard-task-box .topline .muted{
    font-size:12px!important;
    line-height:1.35!important;
  }
  #view-calendar .dashboard-task-count{
    flex:0 0 auto!important;
    min-width:auto!important;
    padding:7px 10px!important;
    border-radius:999px!important;
    background:#eef5e8!important;
    color:var(--forest-dark)!important;
    font-size:11px!important;
    font-weight:850!important;
    line-height:1!important;
    white-space:nowrap!important;
  }
  #view-calendar .tasklist{gap:8px!important}
  #view-calendar .task{
    display:grid!important;
    grid-template-columns:40px minmax(0,1fr)!important;
    grid-auto-rows:auto!important;
    gap:8px 10px!important;
    align-items:start!important;
    padding:12px!important;
    border-radius:15px!important;
    min-width:0!important;
    box-shadow:none!important;
  }
  #view-calendar .task.bad{
    background:#fff8f5!important;
    border-color:#ead9d1!important;
    box-shadow:inset 3px 0 0 #cc8f7b!important;
  }
  #view-calendar .task.warn{
    background:#fffaf0!important;
    border-color:#eadfca!important;
    box-shadow:inset 3px 0 0 #d5ad61!important;
  }
  #view-calendar .task.ok{
    background:#f6faf3!important;
    border-color:#dce7d6!important;
    box-shadow:inset 3px 0 0 #82a477!important;
  }
  #view-calendar .taskicon{
    grid-column:1!important;
    grid-row:1!important;
    width:40px!important;
    height:40px!important;
    border-radius:12px!important;
    display:grid!important;
    place-items:center!important;
    background:rgba(255,255,255,.78)!important;
    border:1px solid rgba(90,100,80,.09)!important;
    font-size:19px!important;
    line-height:1!important;
  }
  #view-calendar .task>div:nth-child(2){
    grid-column:2!important;
    grid-row:1!important;
    min-width:0!important;
  }
  #view-calendar .task b{
    display:block!important;
    font-size:15px!important;
    line-height:1.28!important;
    color:var(--txt)!important;
    overflow-wrap:normal!important;
    word-break:normal!important;
    hyphens:auto;
  }
  #view-calendar .task .why{
    margin-top:4px!important;
    font-size:12px!important;
    line-height:1.42!important;
    color:var(--muted)!important;
  }
  #view-calendar .task>.jgw-moisture-feedback{
    grid-column:2!important;
    width:auto!important;
    margin:0!important;
    font-size:11px!important;
    line-height:1.35!important;
  }
  #view-calendar .task>.actions{
    grid-column:2!important;
    width:100%!important;
    display:grid!important;
    grid-template-columns:1fr 1fr!important;
    gap:7px!important;
    margin:0!important;
  }
  #view-calendar .task>.actions .btn{
    width:100%!important;
    min-height:40px!important;
    padding:8px 10px!important;
    font-size:11.5px!important;
  }
  #view-calendar .empty{padding:16px 8px!important}
  #view-calendar .jgw-task-bulk-actions{
    display:grid!important;
    grid-template-columns:1fr 1fr!important;
    gap:7px!important;
    margin:0 0 10px!important;
  }
  #view-calendar .jgw-task-bulk-actions .btn{
    width:100%!important;
    min-height:40px!important;
    padding:8px 10px!important;
    font-size:11.5px!important;
  }
}
@media(max-width:370px){
  .state-grid{gap:5px!important}
  .state-item{padding:9px 6px!important}
  .state-item .state-label{font-size:8.5px!important;letter-spacing:.02em!important}
  .state-item .state-value{font-size:12px!important}
  #view-calendar .dashboard-task-box{padding:13px!important}
  #view-calendar .task{grid-template-columns:36px minmax(0,1fr)!important;padding:10px!important;gap:7px 9px!important}
  #view-calendar .taskicon{width:36px!important;height:36px!important;border-radius:11px!important;font-size:17px!important}
}
.jgw-task-bulk-actions{
  display:flex;
  align-items:center;
  gap:8px;
  flex-wrap:wrap;
  margin:0 0 10px;
}
.jgw-task-bulk-actions .btn{box-shadow:none}
`;
  document.head.appendChild(css);

  var task=document.querySelector(".dashboard-task-box");
  if(task){
    var title=task.querySelector("h3");
    var subtitle=task.querySelector(".topline .muted");
    if(title)title.textContent="Heute wichtig";
    if(subtitle)subtitle.textContent="Nur das, was heute wirklich ansteht.";
  }
}

var taskPatchInstalled=false;
function installTodayTaskPatch(){
  if(taskPatchInstalled)return true;
  if(typeof getTodayTasks!=="function"||typeof renderToday!=="function"||typeof isoToday!=="function")return false;
  taskPatchInstalled=true;

  var originalGetTodayTasks=getTodayTasks;
  getTodayTasks=function(){
    var today=isoToday();
    return originalGetTodayTasks().filter(function(t){
      return !(t&&t.kind==="water"&&t.plant&&t.plant.lastWatered===today);
    });
  };

  var originalRenderToday=renderToday;
  renderToday=function(){
    originalRenderToday();
    renderTaskBulkActions();
  };
  return true;
}

function renderTaskBulkActions(){
  var host=document.querySelector("#view-calendar .dashboard-task-box")||document.querySelector(".dashboard-task-box");
  var list=document.getElementById("tasks");
  var old=document.getElementById("jgwTaskBulkActions");
  if(old)old.remove();
  if(!host||!list||typeof getTodayTasks!=="function")return;

  var tasks=getTodayTasks();
  if(!tasks.length)return;
  var waterTasks=tasks.filter(function(t){return t&&t.kind==="water"});
  var bar=document.createElement("div");
  bar.id="jgwTaskBulkActions";
  bar.className="jgw-task-bulk-actions";

  var watered=document.createElement("button");
  watered.type="button";
  watered.className="btn small";
  watered.textContent="💧 Alle gegossen";
  watered.disabled=!waterTasks.length;
  watered.title=waterTasks.length?waterTasks.length+" Gießaufgabe"+(waterTasks.length===1?"":"n")+" erledigen":"Keine Gießaufgabe offen";

  var later=document.createElement("button");
  later.type="button";
  later.className="btn ghost small";
  later.textContent="Alle später";
  later.title=tasks.length+" offene Aufgabe"+(tasks.length===1?"":"n")+" für heute ausblenden";

  watered.addEventListener("click",function(){
    var current=getTodayTasks().filter(function(t){return t&&t.kind==="water"});
    if(!current.length)return;
    var today=isoToday();
    current.forEach(function(t){
      t.plant.lastWatered=today;
      if(typeof clearSnooze==="function")clearSnooze(t.plant,"water");
    });
    if(typeof save==="function")save();
    if(typeof celebrateDone==="function")celebrateDone("Alle gegossen");
    if(typeof renderCareViews==="function")renderCareViews();
    else renderToday();
  });

  later.addEventListener("click",function(){
    var current=getTodayTasks();
    if(!current.length)return;
    var today=isoToday();
    current.forEach(function(t){
      if(!t||!t.plant)return;
      t.plant.snoozed=t.plant.snoozed||{};
      t.plant.snoozed[t.kind]=today;
    });
    if(typeof save==="function")save();
    if(typeof renderCareViews==="function")renderCareViews();
    else renderToday();
    if(typeof notice==="function")notice("Alle offenen Aufgaben auf später gesetzt.");
  });

  bar.appendChild(watered);
  bar.appendChild(later);
  list.parentNode.insertBefore(bar,list);
}

function schedule(){
  setTimeout(function(){
    installTodayPolish();
    if(installTodayTaskPatch()){
      try{renderToday()}catch(e){console.warn("Today task patch render failed",e)}
    }
  },0);
}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",schedule,{once:true});
else schedule();
window.addEventListener("load",function(){
  installTodayPolish();
  installTodayTaskPatch();
  renderTaskBulkActions();
},{once:true});
})();