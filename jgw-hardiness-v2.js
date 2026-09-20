(function(){
"use strict";

var CACHE_KEY="jgw_hardiness_cache_v2";
var SYNC_KEY="johannas_gartenwelt_sync_v1";
var STYLE_ID="jgw-hardiness-style-v2";
var SITE_TTL=365*24*60*60*1000;
var PLANT_TTL=365*24*60*60*1000;
var inflightSite=null,inflightPlants={},renderSeq=0;

function esc(s){return String(s==null?"":s).replace(/[&<>"']/g,function(c){return{"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"}[c]})}
function de1(n){return Number(n).toLocaleString("de-DE",{minimumFractionDigits:1,maximumFractionDigits:1})}
function now(){return Date.now()}
function appState(){return window.JGWCore&&window.JGWCore.getState?window.JGWCore.getState():window.state}
function norm(v){return String(v||"").trim().replace(/\s+/g," ").toLowerCase()}
function readCache(){try{var x=JSON.parse(localStorage.getItem(CACHE_KEY)||"{}");if(!x||typeof x!=="object")x={};x.sites=x.sites||{};x.plants=x.plants||{};return x}catch(e){return{sites:{},plants:{}}}}
function writeCache(x){try{localStorage.setItem(CACHE_KEY,JSON.stringify(x))}catch(e){}}
function fresh(x,ttl){return!!(x&&Number(x.fetchedAt)&&now()-Number(x.fetchedAt)<ttl)}

function tempC(v){
  if(v==null)return null;
  if(typeof v==="number"&&Number.isFinite(v))return v;
  if(typeof v==="string"){var n=Number(v.replace(",","."));return Number.isFinite(n)?n:null}
  if(typeof v!=="object")return null;
  var c=[v.deg_c,v.celsius,v.c,v.value_c,v.value_celsius].map(Number).find(Number.isFinite);
  if(Number.isFinite(c))return c;
  var unit=String(v.unit||v.units||"").toLowerCase(),value=Number(v.value);
  if(Number.isFinite(value))return(unit.indexOf("f")===0||unit.indexOf("fahren")>=0)?(value-32)*5/9:value;
  var f=[v.deg_f,v.fahrenheit,v.f].map(Number).find(Number.isFinite);
  return Number.isFinite(f)?(f-32)*5/9:null
}
function zoneFromC(c){
  if(!Number.isFinite(c))return"–";
  var f=c*9/5+32,idx=Math.floor((f+60)/5);
  idx=Math.max(0,Math.min(25,idx));
  return String(Math.floor(idx/2)+1)+(idx%2?"b":"a")
}
function zoneColdC(zone){
  var m=String(zone||"").trim().toLowerCase().match(/^(\d{1,2})([ab])?$/);
  if(!m)return null;
  var n=Number(m[1]);if(n<1||n>13)return null;
  var idx=(n-1)*2+((m[2]||"a")==="b"?1:0),f=-60+idx*5;
  return Math.round(((f-32)*5/9)*10)/10
}
function coords(){
  var s=appState(),p=s&&(s.gardenCenter||s.loc);
  if(!p)return null;
  var lat=Number(p.lat),lon=Number(p.lon);
  return Number.isFinite(lat)&&Number.isFinite(lon)?{lat:lat,lon:lon}:null
}
function fetchTimeout(url,opts,ms){
  var c=new AbortController(),t=setTimeout(function(){c.abort()},ms||20000);
  return fetch(url,Object.assign({},opts||{},{signal:c.signal})).finally(function(){clearTimeout(t)})
}
async function siteHardiness(){
  var p=coords();if(!p)throw new Error("Standort fehlt");
  var key=p.lat.toFixed(3)+","+p.lon.toFixed(3),cache=readCache(),hit=cache.sites[key];
  if(fresh(hit,SITE_TTL))return hit;
  if(inflightSite&&inflightSite.key===key)return inflightSite.promise;
  var promise=(async function(){
    var url="https://archive-api.open-meteo.com/v1/archive?latitude="+encodeURIComponent(p.lat)+"&longitude="+encodeURIComponent(p.lon)+"&start_date=1991-01-01&end_date=2020-12-31&daily=temperature_2m_min&timezone=Europe%2FBerlin";
    var r=await fetchTimeout(url,{headers:{Accept:"application/json"}},30000);
    if(!r.ok)throw new Error("Klimadaten HTTP "+r.status);
    var d=await r.json(),daily=d&&d.daily||{},dates=daily.time||[],mins=daily.temperature_2m_min||[],years={};
    for(var i=0;i<dates.length;i++){var y=String(dates[i]||"").slice(0,4),v=Number(mins[i]);if(!/^\d{4}$/.test(y)||!Number.isFinite(v))continue;if(!Number.isFinite(years[y])||v<years[y])years[y]=v}
    var annual=Object.keys(years).filter(function(y){return Number(y)>=1991&&Number(y)<=2020}).map(function(y){return years[y]});
    if(annual.length<20)throw new Error("Zu wenige Klimajahre verfügbar");
    var avg=annual.reduce(function(a,b){return a+b},0)/annual.length;
    var out={avgExtremeC:Math.round(avg*10)/10,zone:zoneFromC(avg),years:annual.length,period:"1991–2020",fetchedAt:now()};
    cache=readCache();cache.sites[key]=out;writeCache(cache);return out
  })();
  inflightSite={key:key,promise:promise};
  try{return await promise}finally{if(inflightSite&&inflightSite.key===key)inflightSite=null}
}

function profileFor(p){
  var db=window.JGWHardinessProfiles||{},sci=norm(p&&p.scientific),name=norm(p&&p.name),hit=db[sci]||db[name];
  if(hit)return Object.assign({},hit);
  if(sci.indexOf(" ")>0){var genus=sci.split(" ")[0];if(db[genus]&&db[genus].zone)return Object.assign({},db[genus],{quality:"genus"})}
  return null
}
function localHardiness(p){
  var x=profileFor(p);if(!x)return null;
  if(x.kind)return{kind:x.kind,label:x.label||"",source:"Gartenwelt-Pflanzenprofil",quality:x.kind,fetchedAt:now()};
  var minC=zoneColdC(x.zone);if(!Number.isFinite(minC))return null;
  return{minC:minC,zone:x.zone,source:"Gartenwelt-Richtwert",quality:x.quality||"profile",fetchedAt:now()}
}
function syncConfig(){try{return JSON.parse(localStorage.getItem(SYNC_KEY)||"{}")}catch(e){return{}}}
async function sha256Hex(s){
  if(!window.crypto||!crypto.subtle)throw new Error("HTTPS erforderlich");
  var b=await crypto.subtle.digest("SHA-256",new TextEncoder().encode(s));
  return Array.from(new Uint8Array(b)).map(function(x){return x.toString(16).padStart(2,"0")}).join("")
}
function trefleMinC(data){
  if(!data||typeof data!=="object")return null;
  var g=data.growth||{},sp=data.specifications||{},a=[g.minimum_temperature,g.minimum_temperature_deg_c,sp.minimum_temperature,sp.minimum_temperature_deg_c,data.minimum_temperature,data.minimum_temperature_deg_c];
  for(var i=0;i<a.length;i++){var c=tempC(a[i]);if(Number.isFinite(c))return c}
  return null
}
async function trefleHardiness(p){
  var sci=String(p&&p.scientific||"").trim();if(!sci)throw new Error("Botanischer Name fehlt");
  var cfg=syncConfig(),url=String(cfg.url||"").trim().replace(/\/+$/,""),gardenId=String(cfg.gardenId||"").trim().toLowerCase(),pin=String(cfg.pin||"");
  if(!/^https:\/\/[^/]+\.supabase\.co$/i.test(url)||gardenId.length<6||pin.length<6)throw new Error("Trefle-Zusatzdaten benötigen die eingerichtete Geräte-Synchronisierung");
  var secret=await sha256Hex(gardenId+"|"+pin);
  var r=await fetchTimeout(url+"/functions/v1/trefle-enrich",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({scientific_name:sci,garden_id:gardenId,secret_hash:secret})},12000);
  var d=null;try{d=await r.json()}catch(e){}
  if(!r.ok||!d||d.ok!==true||!d.found)throw new Error("Keine Trefle-Daten gefunden");
  var minC=trefleMinC(d.data);if(!Number.isFinite(minC))throw new Error("Trefle enthält für diese Art keine Mindesttemperatur");
  return{minC:Math.round(minC*10)/10,zone:zoneFromC(minC),source:"Trefle",quality:"direct",fetchedAt:now()}
}
async function plantHardiness(p){
  var key=norm(p&&p.scientific||p&&p.name),cache=readCache(),hit=cache.plants[key];
  if(fresh(hit,PLANT_TTL))return hit;
  var local=localHardiness(p);
  if(local){cache.plants[key]=local;writeCache(cache);return local}
  if(inflightPlants[key])return inflightPlants[key];
  var promise=(async function(){var out=await trefleHardiness(p);cache=readCache();cache.plants[key]=out;writeCache(cache);return out})();
  inflightPlants[key]=promise;
  try{return await promise}finally{delete inflightPlants[key]}
}
function penalty(p){var t=String(p&&p.type||"bed");return(t==="pot"||t==="balcony")?5:t==="raised"?2:0}
function assess(p,plant,site){
  var pen=penalty(p),margin=site.avgExtremeC-plant.minC-pen;
  if(margin>=3)return{level:"ok",icon:"✓",title:"Für deinen Standort geeignet",note:pen?"Die Bewertung berücksichtigt den geringeren Frostschutz im "+(p.type==="raised"?"Hochbeet":"Kübel / Topf")+".":"Die Pflanze hat gegenüber dem örtlichen Klimamittel eine gute Frostreserve."};
  if(margin>=-2)return{level:"warn",icon:"!",title:"Grenzbereich – Winterschutz sinnvoll",note:pen?"Im "+(p.type==="raised"?"Hochbeet":"Kübel / Topf")+" sind die Wurzeln stärker frostgefährdet.":"Ein geschützter Standort und Winterschutz bei starken Frösten sind sinnvoll."};
  return{level:"bad",icon:"×",title:"Für deinen Standort kritisch",note:pen?"Für diese Pflanzform ist frostfreie oder deutlich geschützte Überwinterung sinnvoll.":"Starke Fröste können unter der angegebenen Toleranz der Pflanze liegen."}
}

function installStyle(){
  if(document.getElementById(STYLE_ID))return;
  }
function currentPlant(){
  var content=document.getElementById("plantDetailContent"),s=appState();if(!content||!s||!Array.isArray(s.plants))return null;
  var marker=content.querySelector(".detailRefresh[data-id],.detailEdit[data-id]");if(!marker)return null;
  return s.plants.find(function(p){return p.id===marker.dataset.id})||null
}
function sectionFor(p){
  var content=document.getElementById("plantDetailContent");if(!content)return null;
  var old=content.querySelector(".jgw-hardiness-section");if(old&&old.dataset.plantId===p.id)return old;if(old)old.remove();
  var sec=document.createElement("div");sec.className="detail-section jgw-hardiness-section";sec.dataset.plantId=p.id;sec.innerHTML='<h4>❄️ Winterhärte</h4><div class="jgw-hardiness-loading">Standort und Pflanzendaten werden geprüft …</div>';
  var sections=content.querySelectorAll(".detail-section"),anchor=null;
  Array.prototype.some.call(sections,function(x){var h=x.querySelector("h4");if(h&&h.textContent.trim()==="Steckbrief"){anchor=x;return true}return false});
  if(anchor&&anchor.nextSibling)anchor.parentNode.insertBefore(sec,anchor.nextSibling);else if(anchor)anchor.parentNode.appendChild(sec);else content.appendChild(sec);
  return sec
}
function renderUnavailable(sec,title,text){sec.innerHTML='<h4>❄️ Winterhärte</h4><div class="jgw-hardiness-card warn"><div class="jgw-hardiness-head"><div class="jgw-hardiness-icon">?</div><div><div class="jgw-hardiness-title">'+esc(title)+'</div><div class="jgw-hardiness-sub">'+esc(text)+'</div></div></div></div>'}
function renderSpecial(sec,plant){
  if(plant.kind==="seasonal"){sec.innerHTML='<h4>❄️ Winterhärte</h4><div class="jgw-hardiness-card info"><div class="jgw-hardiness-head"><div class="jgw-hardiness-icon">↻</div><div><div class="jgw-hardiness-title">Winterhärte hier nicht maßgeblich</div><div class="jgw-hardiness-sub">'+esc(plant.label||"Einjährige Kultur")+'</div></div></div><div class="jgw-hardiness-note">Diese Pflanze wird üblicherweise saisonal bzw. einjährig kultiviert. Deshalb ist ein dauerhafter Winterhärte-Status weniger aussagekräftig.</div></div>';return}
  sec.innerHTML='<h4>❄️ Winterhärte</h4><div class="jgw-hardiness-card warn"><div class="jgw-hardiness-head"><div class="jgw-hardiness-icon">?</div><div><div class="jgw-hardiness-title">Art genauer bestimmen</div><div class="jgw-hardiness-sub">'+esc(plant.label||"Die gespeicherte Bestimmung ist zu grob.")+'</div></div></div><div class="jgw-hardiness-note">Innerhalb dieser Pflanzengruppe kann die Frosthärte stark schwanken. Für einen verlässlichen Status wird die genaue Art benötigt.</div></div>'
}
function qualityText(p){return p.source==="Trefle"?"Direktwert aus Trefle":p.quality==="genus"?"Gattungs-Richtwert":p.quality==="alias"?"Richtwert über botanisches Synonym":"USDA-Richtwert aus Gartenwelt-Pflanzenprofil"}
function renderResult(sec,p,plant,site){
  var a=assess(p,plant,site),s=appState(),plz=s&&s.plz?"PLZ "+s.plz:"Gartenstandort";
  sec.innerHTML='<h4>❄️ Winterhärte</h4><div class="jgw-hardiness-card '+a.level+'"><div class="jgw-hardiness-head"><div class="jgw-hardiness-icon">'+a.icon+'</div><div><div class="jgw-hardiness-title">'+esc(a.title)+'</div><div class="jgw-hardiness-sub">'+esc(plz)+' · USDA-Zone '+esc(site.zone)+'</div></div></div><div class="jgw-hardiness-grid"><div class="jgw-hardiness-kv"><span>Pflanze</span><b>bis ca. '+esc(de1(plant.minC))+' °C · Zone '+esc(plant.zone)+'</b></div><div class="jgw-hardiness-kv"><span>Standort</span><b>Ø '+esc(de1(site.avgExtremeC))+' °C · Zone '+esc(site.zone)+'</b></div></div><div class="jgw-hardiness-note">'+esc(a.note)+'</div><div class="jgw-hardiness-source">'+esc(qualityText(plant))+' · Standortzone: Open-Meteo, mittleres jährliches Extremminimum '+esc(site.period)+' ('+site.years+' Klimajahre). USDA-Zonen sind Orientierungswerte; Sorte, Mikroklima, Wind und Bodenfeuchte können die tatsächliche Winterhärte verändern.</div></div>'
}
async function enhance(){
  var p=currentPlant();if(!p)return;installStyle();var sec=sectionFor(p);if(!sec)return;
  var seq=++renderSeq,plant=null,site=null,pe=null,se=null;
  try{plant=await plantHardiness(p)}catch(e){pe=e}
  if(seq!==renderSeq||!currentPlant()||currentPlant().id!==p.id)return;
  if(plant&&plant.kind){renderSpecial(sec,plant);return}
  try{site=await siteHardiness()}catch(e){se=e}
  if(seq!==renderSeq||!currentPlant()||currentPlant().id!==p.id)return;
  if(plant&&site){renderResult(sec,p,plant,site);return}
  if(!plant)renderUnavailable(sec,"Winterhärte der Pflanze noch unbekannt",pe&&pe.message?pe.message:"Für diese Pflanze liegt noch kein belastbarer Richtwert vor.");
  else renderUnavailable(sec,"Standortzone noch nicht verfügbar",se&&se.message?se.message:"Bitte Standort prüfen.")
}
function start(){
  installStyle();var host=document.getElementById("plantDetailContent");if(!host)return;
  new MutationObserver(function(){var p=currentPlant(),sec=host.querySelector(".jgw-hardiness-section");if(p&&(!sec||sec.dataset.plantId!==p.id))setTimeout(enhance,0)}).observe(host,{childList:true,subtree:true});
  document.addEventListener("click",function(e){var b=e.target&&e.target.closest?e.target.closest(".plantOpen"):null;if(b)setTimeout(enhance,80)},true);
  setTimeout(enhance,0)
}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",start,{once:true});else start()
})();