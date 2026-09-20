(function(){
"use strict";
if(window.__jgwMobileFixV5)return;window.__jgwMobileFixV5=true;



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
