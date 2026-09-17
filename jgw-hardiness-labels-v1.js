(function(){
"use strict";
if(window.__jgwHardinessLabelsV1)return;window.__jgwHardinessLabelsV1=true;

function state(){return window.JGWCore&&window.JGWCore.getState?window.JGWCore.getState():window.state}
function de1(n){return Number(n).toLocaleString("de-DE",{minimumFractionDigits:1,maximumFractionDigits:1}).replace("-","−")}
function zoneBounds(zone){
  var m=String(zone||"").trim().toLowerCase().match(/^(\d{1,2})([ab])$/);if(!m)return null;
  var n=Number(m[1]);if(n<1||n>13)return null;
  var idx=(n-1)*2+(m[2]==="b"?1:0),lowF=-60+idx*5,highF=lowF+5;
  return{low:(lowF-32)*5/9,high:(highF-32)*5/9}
}
function clearZone(zone){
  var b=zoneBounds(zone);return b?"Zone "+zone+" ("+de1(b.low)+" bis "+de1(b.high)+" °C)":"Zone "+zone
}
function locationText(){
  var s=state()||{},parts=[];
  if(s.loc&&s.loc.name)parts.push(String(s.loc.name));
  if(s.plz)parts.push("PLZ "+String(s.plz));
  return parts.length?parts.join(" · "):"Gartenstandort"
}
function zoneFromText(text){var m=String(text||"").match(/Zone\s+(\d{1,2}[ab])/i);return m?m[1].toLowerCase():""}
function cleanTemperatureText(text){return String(text||"").replace(/-/g,"−")}
function enhance(){
  var sec=document.querySelector("#plantDetailContent .jgw-hardiness-section");if(!sec)return;
  var sub=sec.querySelector(".jgw-hardiness-sub"),siteZone=sub?zoneFromText(sub.textContent):"";
  if(sub&&siteZone)sub.textContent=locationText()+" · "+clearZone(siteZone);
  var boxes=sec.querySelectorAll(".jgw-hardiness-kv");
  Array.prototype.forEach.call(boxes,function(box){
    var label=box.querySelector("span"),value=box.querySelector("b");if(!label||!value)return;
    var zone=zoneFromText(value.textContent);if(!zone)return;
    var t=cleanTemperatureText(value.textContent).replace(/\s*·\s*Zone\s+\d{1,2}[ab].*$/i,"");
    value.textContent=t+" · "+clearZone(zone);
    if(label.textContent.trim().toLowerCase()==="standort")label.textContent="Standort · "+locationText();
  });
}
function queue(){requestAnimationFrame(enhance)}
function start(){
  queue();
  var host=document.getElementById("plantDetailContent");if(host)new MutationObserver(queue).observe(host,{childList:true,subtree:true,characterData:true});
  document.addEventListener("click",function(e){if(e.target&&e.target.closest&&e.target.closest(".plantOpen"))setTimeout(queue,120)},true)
}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",start,{once:true});else start();
})();