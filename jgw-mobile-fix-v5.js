(function(){
"use strict";
if(window.__jgwMobileFixV5)return;window.__jgwMobileFixV5=true;

var css=document.createElement("style");
css.id="jgwMobileFixV5Style";
css.textContent=`
@media(max-width:700px){
  .state-item{min-width:0!important}
  .state-item .state-label{white-space:normal!important;overflow-wrap:anywhere!important;line-height:1.08!important}
  #naturePlantsPane>.box:first-child .topline>.actions{
    display:grid!important;
    grid-template-columns:minmax(0,1fr) 44px!important;
    gap:8px!important;
    align-items:center!important;
    width:100%!important;
  }
  #naturePlantsPane #plantSearch{
    grid-column:1!important;
    width:100%!important;
    min-width:0!important;
  }
  #naturePlantsPane #newPlantBtn{
    display:grid!important;
    place-items:center!important;
    grid-column:2!important;
    width:44px!important;
    min-width:44px!important;
    height:44px!important;
    min-height:44px!important;
    padding:0!important;
    border-radius:50%!important;
    font-size:0!important;
  }
  #naturePlantsPane #newPlantBtn::before{
    content:"+";
    font-size:24px!important;
    line-height:1!important;
  }
  body.jgw-plants-active .jgw-fab{display:none!important}
  #plantList.list-mode .plant-list-main b{
    white-space:normal!important;
    display:-webkit-box!important;
    -webkit-box-orient:vertical!important;
    -webkit-line-clamp:2!important;
    overflow:hidden!important;
    line-height:1.15!important;
  }
}
`;
document.head.appendChild(css);

function state(){
  try{return window.JGWCore&&JGWCore.getState?JGWCore.getState():(window.state||null)}catch(e){return window.state||null}
}
function syncPlantActive(){
  var v=document.getElementById("view-plants");
  if(v)document.body.classList.toggle("jgw-plants-active",v.classList.contains("active"));
}
function migrateGallery(){
  try{
    var s=state();
    if(!s||!s.settings||s.settings.galleryViewV2)return;
    var b=document.getElementById("plantViewCollection");
    if(!b)return;
    s.settings.galleryViewV2=true;
    b.click();
  }catch(e){console.warn("Galerie-Migration übersprungen",e)}
}
function start(){
  syncPlantActive();
  var v=document.getElementById("view-plants");
  if(v)new MutationObserver(syncPlantActive).observe(v,{attributes:true,attributeFilter:["class"]});
  setTimeout(migrateGallery,1200);
  setTimeout(migrateGallery,3200);
  setTimeout(migrateGallery,5200);
}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",start,{once:true});else start();
window.addEventListener("pageshow",function(){syncPlantActive();setTimeout(migrateGallery,300)});
})();
