(function(){
"use strict";

var CACHE_KEY="jgw_hardiness_cache_v1";
var SYNC_KEY="johannas_gartenwelt_sync_v1";
var STYLE_ID="jgw-hardiness-style";
var SITE_TTL=365*24*60*60*1000;
var PLANT_TTL=180*24*60*60*1000;
var inflightSite=null;
var inflightPlants={};
var renderSeq=0;

function esc(s){
  return String(s==null?"":s).replace(/[&<>"']/g,function(c){
    return {"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"}[c];
  });
}
function de1(n){return Number(n).toLocaleString("de-DE",{minimumFractionDigits:1,maximumFractionDigits:1});}
function now(){return Date.now();}
function state(){return window.JGWCore&&window.JGWCore.getState?window.JGWCore.getState():window.state;}
function readCache(){
  try{
    var x=JSON.parse(localStorage.getItem(CACHE_KEY)||"{}");
    if(!x||typeof x!=="object")x={};
    if(!x.sites||typeof x.sites!=="object")x.sites={};
    if(!x.plants||typeof x.plants!=="object")x.plants={};
    return x;
  }catch(_e){return{sites:{},plants:{}};}
}
function writeCache(x){try{localStorage.setItem(CACHE_KEY,JSON.stringify(x));}catch(_e){}}
function cacheFresh(x,ttl){return !!(x&&Number(x.fetchedAt)&&now()-Number(x.fetchedAt)<ttl);}
function tempC(v){
  if(v==null)return null;
  if(typeof v==="number"&&Number.isFinite(v))return v;
  if(typeof v==="string"){
    var n=Number(v.replace(",","."));
    return Number.isFinite(n)?n:null;
  }
  if(typeof v!=="object")return null;
  var c=[v.deg_c,v.celsius,v.c,v.value_c,v.value_celsius].map(Number).find(Number.isFinite);
  if(Number.isFinite(c))return c;
  var unit=String(v.unit||v.units||"").toLowerCase(),value=Number(v.value);
  if(Number.isFinite(value)){
    if(unit.indexOf("f")===0||unit.indexOf("fahren")>=0)return(value-32)*5/9;
    return value;
  }
  var f=[v.deg_f,v.fahrenheit,v.f].map(Number).find(Number.isFinite);
  return Number.isFinite(f)?(f-32)*5/9:null;
}
function zoneFromC(c){
  if(!Number.isFinite(c))return"–";
  var f=c*9/5+32,idx=Math.floor((f+60)/5);
  idx=Math.max(0,Math.min(25,idx));
  var number=Math.floor(idx/2)+1;
  return String(number)+(idx%2?"b":"a");
}
function coords(){
  var s=state();if(!s)return null;
  var p=s.gardenCenter||s.loc;
  if(!p)return null;
  var lat=Number(p.lat),lon=Number(p.lon);
  return Number.isFinite(lat)&&Number.isFinite(lon)?{lat:lat,lon:lon}:null;
}
function siteKey(p){return p.lat.toFixed(3)+","+p.lon.toFixed(3);}
function fetchWithTimeout(url,opts,ms){
  var c=new AbortController(),t=setTimeout(function(){c.abort();},ms||20000);
  opts=Object.assign({},opts||{},{signal:c.signal});
  return fetch(url,opts).finally(function(){clearTimeout(t);});
}
async function fetchSiteHardiness(){
  var p=coords();
  if(!p)throw new Error("Standort fehlt");
  var key=siteKey(p),cache=readCache(),hit=cache.sites[key];
  if(cacheFresh(hit,SITE_TTL))return hit;
  if(inflightSite&&inflightSite.key===key)return inflightSite.promise;
  var promise=(async function(){
    var url="https://archive-api.open-meteo.com/v1/archive?latitude="+encodeURIComponent(p.lat)+"&longitude="+encodeURIComponent(p.lon)+"&start_date=1991-01-01&end_date=2020-12-31&daily=temperature_2m_min&timezone=Europe%2FBerlin";
    var res=await fetchWithTimeout(url,{headers:{Accept:"application/json"}},30000);
    if(!res.ok)throw new Error("Klimadaten HTTP "+res.status);
    var d=await res.json(),daily=d&&d.daily||{},dates=daily.time||[],mins=daily.temperature_2m_min||[],years={};
    for(var i=0;i<dates.length;i++){
      var y=String(dates[i]||"").slice(0,4),v=Number(mins[i]);
      if(!/^\d{4}$/.test(y)||!Number.isFinite(v))continue;
      if(!Number.isFinite(years[y])||v<years[y])years[y]=v;
    }
    var annual=Object.keys(years).filter(function(y){return Number(y)>=1991&&Number(y)<=2020;}).map(function(y){return years[y];});
    if(annual.length<20)throw new Error("Zu wenige Klimajahre verfügbar");
    var avg=annual.reduce(function(a,b){return a+b;},0)/annual.length;
    var out={avgExtremeC:Math.round(avg*10)/10,zone:zoneFromC(avg),years:annual.length,period:"1991–2020",fetchedAt:now(),lat:p.lat,lon:p.lon};
    cache=readCache();cache.sites[key]=out;writeCache(cache);return out;
  })();
  inflightSite={key:key,promise:promise};
  try{return await promise;}finally{if(inflightSite&&inflightSite.key===key)inflightSite=null;}
}
function syncConfig(){
  try{return JSON.parse(localStorage.getItem(SYNC_KEY)||"{}");}catch(_e){return{};}
}
async function sha256Hex(s){
  if(!window.crypto||!crypto.subtle)throw new Error("HTTPS erforderlich");
  var b=await crypto.subtle.digest("SHA-256",new TextEncoder().encode(s));
  return Array.from(new Uint8Array(b)).map(function(x){return x.toString(16).padStart(2,"0");}).join("");
}
function plantCacheKey(p){return String(p.scientific||"").trim().toLowerCase();}
async function fetchPlantHardiness(p){
  var sci=String(p&&p.scientific||"").trim();
  if(!sci)throw new Error("Botanischer Name fehlt");
  var key=plantCacheKey(p),cache=readCache(),hit=cache.plants[key];
  if(cacheFresh(hit,PLANT_TTL))return hit;
  if(inflightPlants[key])return inflightPlants[key];
  var promise=(async function(){
    var cfg=syncConfig(),url=String(cfg.url||"").trim().replace(/\/+$/,""),gardenId=String(cfg.gardenId||"").trim().toLowerCase(),pin=String(cfg.pin||"");
    if(!/^https:\/\/[^/]+\.supabase\.co$/i.test(url)||gardenId.length<6||pin.length<6)throw new Error("Trefle-Zusatzdaten benötigen die eingerichtete Geräte-Synchronisierung");
    var secret=await sha256Hex(gardenId+"|"+pin);
    var res=await fetchWithTimeout(url+"/functions/v1/trefle-enrich",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({scientific_name:sci,garden_id:gardenId,secret_hash:secret})},18000);
    var data=null;try{data=await res.json();}catch(_e){}
    if(!res.ok||!data||data.ok!==true||!data.found)throw new Error("Keine Winterhärtedaten gefunden");
    var growth=data.data&&data.data.growth||{},minC=tempC(growth.minimum_temperature);
    if(!Number.isFinite(minC))throw new Error("Trefle enthält für diese Art keine Mindesttemperatur");
    var out={minC:Math.round(minC*10)/10,zone:zoneFromC(minC),fetchedAt:now(),source:"Trefle"};
    cache=readCache();cache.plants[key]=out;writeCache(cache);return out;
  })();
  inflightPlants[key]=promise;
  try{return await promise;}finally{delete inflightPlants[key];}
}
function containerPenalty(p){
  var t=String(p&&p.type||"bed");
  if(t==="pot"||t==="balcony")return 5;
  if(t==="raised")return 2;
  return 0;
}
function assess(p,plant,site){
  var raw=site.avgExtremeC-plant.minC,penalty=containerPenalty(p),margin=raw-penalty;
  if(margin>=3)return{level:"ok",icon:"✓",title:"Für deinen Standort geeignet",note:penalty?"Die Bewertung berücksichtigt den geringeren Frostschutz im "+(p.type==="raised"?"Hochbeet":"Kübel / Topf")+".":"Die Pflanze hat gegenüber dem örtlichen Klimamittel eine gute Frostreserve.",margin:margin};
  if(margin>=-2)return{level:"warn",icon:"!",title:"Grenzbereich – Winterschutz sinnvoll",note:penalty?"Im "+(p.type==="raised"?"Hochbeet":"Kübel / Topf")+" sind die Wurzeln stärker frostgefährdet.":"Ein geschützter Standort und Winterschutz bei starken Frösten sind sinnvoll.",margin:margin};
  return{level:"bad",icon:"×",title:"Für deinen Standort kritisch",note:penalty?"Für diese Pflanzform ist frostfreie oder deutlich geschützte Überwinterung sinnvoll.":"Starke Fröste können unter der angegebenen Toleranz der Pflanze liegen.",margin:margin};
}
function installStyle(){
  if(document.getElementById(STYLE_ID))return;
  var s=document.createElement("style");s.id=STYLE_ID;s.textContent=`
.jgw-hardiness-card{border:1px solid var(--line);border-radius:15px;padding:12px;background:#f7faf8}
.jgw-hardiness-card.ok{background:#eef6eb;border-color:#d1e2cb}.jgw-hardiness-card.warn{background:#fff5df;border-color:#ead6a5}.jgw-hardiness-card.bad{background:#faece7;border-color:#e6c7bd}
.jgw-hardiness-head{display:grid;grid-template-columns:42px minmax(0,1fr);gap:10px;align-items:center}.jgw-hardiness-icon{width:42px;height:42px;border-radius:12px;display:grid;place-items:center;font-size:24px;font-weight:900;background:#fff;color:var(--forest-dark);border:1px solid rgba(80,100,72,.12)}
.jgw-hardiness-card.ok .jgw-hardiness-icon{background:#4f8959;color:#fff}.jgw-hardiness-card.warn .jgw-hardiness-icon{background:#d0a13e;color:#fff}.jgw-hardiness-card.bad .jgw-hardiness-icon{background:#b7675d;color:#fff}
.jgw-hardiness-title{font-weight:850;color:var(--forest-dark);line-height:1.25}.jgw-hardiness-sub{font-size:11px;color:var(--muted);margin-top:3px;line-height:1.35}
.jgw-hardiness-grid{display:grid;grid-template-columns:1fr 1fr;gap:7px;margin-top:10px}.jgw-hardiness-kv{padding:9px;border-radius:11px;background:rgba(255,255,255,.68);border:1px solid rgba(120,110,95,.08)}.jgw-hardiness-kv span{display:block;font-size:9px;font-weight:850;text-transform:uppercase;letter-spacing:.05em;color:var(--muted)}.jgw-hardiness-kv b{display:block;margin-top:3px;color:#5d5349;font-size:12px}
.jgw-hardiness-note{font-size:11px;color:var(--muted);line-height:1.45;margin-top:9px}.jgw-hardiness-loading{font-size:12px;color:var(--muted);padding:3px 0}.jgw-hardiness-source{font-size:9.5px;color:var(--muted);line-height:1.35;margin-top:7px}
@media(max-width:420px){.jgw-hardiness-grid{grid-template-columns:1fr 1fr}.jgw-hardiness-head{grid-template-columns:38px minmax(0,1fr)}.jgw-hardiness-icon{width:38px;height:38px;border-radius:11px;font-size:21px}}
`;
  document.head.appendChild(s);
}
function currentPlantFromDetail(){
  var content=document.getElementById("plantDetailContent"),s=state();
  if(!content||!s||!Array.isArray(s.plants))return null;
  var marker=content.querySelector(".detailRefresh[data-id],.detailEdit[data-id]");
  if(!marker)return null;
  return s.plants.find(function(p){return p.id===marker.dataset.id;})||null;
}
function ensureSection(p){
  var content=document.getElementById("plantDetailContent");if(!content)return null;
  var old=content.querySelector(".jgw-hardiness-section");
  if(old&&old.dataset.plantId===p.id)return old;
  if(old)old.remove();
  var sec=document.createElement("div");sec.className="detail-section jgw-hardiness-section";sec.dataset.plantId=p.id;sec.innerHTML='<h4>❄️ Winterhärte</h4><div class="jgw-hardiness-loading">Standort und Pflanzendaten werden geprüft …</div>';
  var sections=content.querySelectorAll(".detail-section"),anchor=null;
  Array.prototype.some.call(sections,function(x){var h=x.querySelector("h4");if(h&&h.textContent.trim()==="Steckbrief"){anchor=x;return true;}return false;});
  if(anchor&&anchor.nextSibling)anchor.parentNode.insertBefore(sec,anchor.nextSibling);else if(anchor)anchor.parentNode.appendChild(sec);else content.appendChild(sec);
  return sec;
}
function renderUnavailable(sec,title,text){
  sec.innerHTML='<h4>❄️ Winterhärte</h4><div class="jgw-hardiness-card warn"><div class="jgw-hardiness-head"><div class="jgw-hardiness-icon">?</div><div><div class="jgw-hardiness-title">'+esc(title)+'</div><div class="jgw-hardiness-sub">'+esc(text)+'</div></div></div></div>';
}
function renderResult(sec,p,plant,site){
  var a=assess(p,plant,site),plz=state()&&state().plz?"PLZ "+state().plz:"Gartenstandort",plantZone=plant.zone,siteZone=site.zone;
  sec.innerHTML='<h4>❄️ Winterhärte</h4><div class="jgw-hardiness-card '+a.level+'"><div class="jgw-hardiness-head"><div class="jgw-hardiness-icon">'+a.icon+'</div><div><div class="jgw-hardiness-title">'+esc(a.title)+'</div><div class="jgw-hardiness-sub">'+esc(plz)+' · USDA-Zone '+esc(siteZone)+'</div></div></div><div class="jgw-hardiness-grid"><div class="jgw-hardiness-kv"><span>Pflanze</span><b>bis ca. '+esc(de1(plant.minC))+' °C · Zone '+esc(plantZone)+'</b></div><div class="jgw-hardiness-kv"><span>Standort</span><b>Ø '+esc(de1(site.avgExtremeC))+' °C · Zone '+esc(siteZone)+'</b></div></div><div class="jgw-hardiness-note">'+esc(a.note)+'</div><div class="jgw-hardiness-source">Pflanzentoleranz: Trefle · Standortzone: Open-Meteo, mittleres jährliches Extremminimum '+esc(site.period)+' ('+site.years+' Klimajahre). Mikroklima, Wind und Bodenfeuchte können die tatsächliche Winterhärte beeinflussen.</div></div>';
}
async function enhanceCurrentDetail(){
  var p=currentPlantFromDetail();if(!p)return;
  installStyle();var sec=ensureSection(p);if(!sec)return;
  var seq=++renderSeq,site=null,plant=null,siteErr=null,plantErr=null;
  try{site=await fetchSiteHardiness();}catch(e){siteErr=e;}
  if(seq!==renderSeq||!currentPlantFromDetail()||currentPlantFromDetail().id!==p.id)return;
  try{plant=await fetchPlantHardiness(p);}catch(e){plantErr=e;}
  if(seq!==renderSeq||!currentPlantFromDetail()||currentPlantFromDetail().id!==p.id)return;
  if(site&&plant){renderResult(sec,p,plant,site);return;}
  if(!site)renderUnavailable(sec,"Standortzone noch nicht verfügbar",siteErr&&siteErr.message?siteErr.message:"Bitte Standort prüfen.");
  else renderUnavailable(sec,"Winterhärte der Pflanze noch unbekannt",plantErr&&plantErr.message?plantErr.message:"Für diese Pflanze liegen keine belastbaren Temperaturdaten vor.");
}
function start(){
  installStyle();
  var host=document.getElementById("plantDetailContent");
  if(!host)return;
  new MutationObserver(function(){
    var p=currentPlantFromDetail(),sec=host.querySelector(".jgw-hardiness-section");
    if(p&&(!sec||sec.dataset.plantId!==p.id))setTimeout(enhanceCurrentDetail,0);
  }).observe(host,{childList:true,subtree:true});
  document.addEventListener("click",function(e){var b=e.target&&e.target.closest?e.target.closest(".plantOpen"):null;if(b)setTimeout(enhanceCurrentDetail,80);},true);
  setTimeout(enhanceCurrentDetail,0);
}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",start,{once:true});else start();
})();
