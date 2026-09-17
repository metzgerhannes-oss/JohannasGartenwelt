(function(){
"use strict";
if(window.__jgwHardinessLabelsV1)return;window.__jgwHardinessLabelsV1=true;

function state(){return window.JGWCore&&window.JGWCore.getState?window.JGWCore.getState():window.state}
function locationText(){
  var s=state()||{},parts=[];
  if(s.loc&&s.loc.name)parts.push(String(s.loc.name));
  if(s.plz)parts.push("PLZ "+String(s.plz));
  return parts.length?parts.join(" · "):"Gartenstandort"
}
function cleanTemperatureText(text){
  return String(text||"")
    .replace(/-/g,"−")
    .replace(/\s*·\s*Zone\s+\d{1,2}[ab].*$/i,"")
    .trim()
}
function currentPlant(){
  var s=state()||{},host=document.getElementById("plantDetailContent");
  if(!host||!Array.isArray(s.plants))return null;
  var marker=host.querySelector(".detailRefresh[data-id],.detailEdit[data-id]");
  if(!marker)return null;
  return s.plants.find(function(p){return String(p.id)===String(marker.dataset.id)})||null
}
function plantAreaName(p){
  if(!p)return"";
  if(String(p.area||"").trim())return String(p.area).trim();
  var s=state()||{};
  if(p.areaId&&Array.isArray(s.areas)){
    var a=s.areas.find(function(x){return String(x.id)===String(p.areaId)});
    if(a&&String(a.name||"").trim())return String(a.name).trim()
  }
  return""
}
function isMapped(p){
  if(!p)return false;
  if(Array.isArray(p.positions)&&p.positions.some(function(x){return x&&Number.isFinite(Number(x.lat))&&Number.isFinite(Number(x.lon))}))return true;
  return Number.isFinite(Number(p.lat))&&Number.isFinite(Number(p.lon))
}
function setText(el,text){if(el&&el.textContent!==text)el.textContent=text}
function enhanceHardiness(){
  var sec=document.querySelector("#plantDetailContent .jgw-hardiness-section");if(!sec)return;
  var sub=sec.querySelector(".jgw-hardiness-sub");
  if(sub&&/zone\s+\d/i.test(sub.textContent))setText(sub,locationText());
  var boxes=sec.querySelectorAll(".jgw-hardiness-kv");
  Array.prototype.forEach.call(boxes,function(box){
    var value=box.querySelector("b");if(!value)return;
    var cleaned=cleanTemperatureText(value.textContent);
    setText(value,cleaned)
  });
  var source=sec.querySelector(".jgw-hardiness-source");
  if(source){
    var t=String(source.textContent||"")
      .replace(/\s*USDA-Zonen sind Orientierungswerte;?/i,"")
      .replace(/USDA-Richtwert/gi,"Winterhärte-Richtwert")
      .replace(/Standortzone:/i,"Standortklima:");
    setText(source,t.trim())
  }
}
function enhancePlantLocation(){
  var p=currentPlant(),host=document.getElementById("plantDetailContent");if(!p||!host)return;
  var sections=host.querySelectorAll(".detail-section"),steck=null;
  Array.prototype.some.call(sections,function(sec){var h=sec.querySelector("h4");if(h&&h.textContent.trim()==="Steckbrief"){steck=sec;return true}return false});
  if(!steck)return;
  var rows=steck.querySelectorAll(".detail-kv");
  Array.prototype.forEach.call(rows,function(row){
    var label=row.querySelector("span"),value=row.querySelector("b");if(!label||!value)return;
    if(label.textContent.trim().toLowerCase()!=="standort")return;
    var area=plantAreaName(p),txt=area||(isMapped(p)?"Auf Karte positioniert":"Nicht kartiert");
    setText(value,txt)
  })
}
function enhance(){enhanceHardiness();enhancePlantLocation()}
function queue(){requestAnimationFrame(enhance)}
function start(){
  queue();
  var host=document.getElementById("plantDetailContent");if(host)new MutationObserver(queue).observe(host,{childList:true,subtree:true,characterData:true});
  document.addEventListener("click",function(e){if(e.target&&e.target.closest&&e.target.closest(".plantOpen"))setTimeout(queue,120)},true)
}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",start,{once:true});else start();
})();