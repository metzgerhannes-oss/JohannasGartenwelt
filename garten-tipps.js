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
function start(){
  installTodayPolish();
}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",start,{once:true});
else start();
window.addEventListener("load",installTodayPolish,{once:true});
})();
