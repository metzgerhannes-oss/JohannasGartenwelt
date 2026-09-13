from pathlib import Path
import re

p = Path('index.html')
s = p.read_text(encoding='utf-8')

direct = r'''<script id="jgw-photo-storage-direct">
(function(){
"use strict";
var STORE="giess_check_garten_v3",SYNC_STORE="johannas_gartenwelt_sync_v1";
function byId(id){return document.getElementById(id)}
function read(key){try{return JSON.parse(localStorage.getItem(key)||"{}")}catch(e){return{}}}
function configured(c){return !!(c&&c.enabled&&/^https:\/\/[^/]+\.supabase\.co$/i.test(String(c.url||"").replace(/\/+$/,""))&&String(c.key||"").length>10&&String(c.gardenId||"").length>=6&&String(c.pin||"").length>=6)}
function counts(data){var cloud=0,local=0;["plants","habitats","animals"].forEach(function(k){(Array.isArray(data[k])?data[k]:[]).forEach(function(it){if(it&&it.photoRef)cloud++;if(it&&/^data:image\//.test(String(it.photo||"")))local++})});return{cloud:cloud,local:local}}
function status(msg){var s=byId("photoStorageStatus");if(s)s.textContent=msg}
function syncPayload(d){return{version:4,plz:d.plz||"",loc:d.loc||null,gardenCenter:d.gardenCenter||null,plants:Array.isArray(d.plants)?d.plants:[],habitats:Array.isArray(d.habitats)?d.habitats:[],animals:Array.isArray(d.animals)?d.animals:[],areas:Array.isArray(d.areas)?d.areas:[],zones:Array.isArray(d.zones)?d.zones:[],ecology:d.ecology||{}}}
function hash32(v){var s=typeof v==="string"?v:JSON.stringify(v),h=2166136261;for(var i=0;i<s.length;i++){h^=s.charCodeAt(i);h=Math.imul(h,16777619)}return("00000000"+(h>>>0).toString(16)).slice(-8)}
async function sha256(v){var b=await crypto.subtle.digest("SHA-256",new TextEncoder().encode(v));return Array.from(new Uint8Array(b)).map(function(x){return x.toString(16).padStart(2,"0")}).join("")}
async function secret(c){return sha256(String(c.gardenId||"").trim().toLowerCase()+"|"+String(c.pin||""))}
async function api(c,action,extra){var u=String(c.url).replace(/\/+$/,""),body=Object.assign({action:action,garden_id:String(c.gardenId).trim().toLowerCase(),secret_hash:await secret(c)},extra||{});var r=await fetch(u+"/functions/v1/jgw-photo",{method:"POST",headers:{"Content-Type":"application/json","apikey":c.key},body:JSON.stringify(body)}),t=await r.text(),d={};try{d=t?JSON.parse(t):{}}catch(e){}if(!r.ok||!d.ok){var msg=d.error||("HTTP "+r.status);if(d.detail)msg+=" – "+d.detail;throw new Error(msg)}return d}
async function refresh(){var d=read(STORE),c=read(SYNC_STORE),n=counts(d);if(!configured(c)){status("Cloud-Fotospeicher noch nicht verbunden · noch lokal: "+n.local);return n}status("Verbindung zum Fotospeicher wird geprüft …");try{var r=await api(c,"status");status("Supabase-Fotospeicher bereit · Cloud: "+Number(r.refs||0)+" · noch lokal: "+Number(r.inline||0));return{cloud:Number(r.refs||0),local:Number(r.inline||0)}}catch(e){status("Fotospeicher nicht erreichbar: "+e.message);return n}}
function applyMigrated(data,items){var map={plants:"plants",habitats:"habitats",animals:"animals"};(items||[]).forEach(function(m){var list=Array.isArray(data[map[m.type]])?data[map[m.type]]:[];var it=list.find(function(x){return String(x&&x.id)===String(m.id)});if(it){it.photoRef=m.ref;it.photo=m.url}})}
async function optimize(){var btn=byId("optimizePhotoStorageBtn"),data=read(STORE),c=read(SYNC_STORE);if(!configured(c)){status("Cloud-Fotospeicher noch nicht verbunden. Bitte zuerst Geräte-Sync vollständig einrichten.");return}if(btn){btn.disabled=true;btn.textContent="Fotos werden ausgelagert …"}status("Fotos werden sicher in Supabase ausgelagert …");try{var r=await api(c,"migrate");applyMigrated(data,r.migrated||[]);localStorage.setItem(STORE,JSON.stringify(data));c.revision=Number(r.revision||c.revision||0);c.lastSync=r.updated_at||new Date().toISOString();c.lastPayloadHash=hash32(syncPayload(data));c.dirty=false;localStorage.setItem(SYNC_STORE,JSON.stringify(c));if(Number(r.failed||0)>0){var first=(r.errors&&r.errors[0]&&r.errors[0].error)||"unbekannter Fehler";status("Teilweise fertig: "+Number(r.done||0)+" Fotos ausgelagert · "+Number(r.failed||0)+" Fehler · "+first);return}if(Number(r.done||0)===0){status("Keine lokalen Fotos mehr auszulagern.");return}status("Fertig: "+Number(r.done||0)+" Fotos in Supabase ausgelagert. App wird neu geladen …");setTimeout(function(){location.reload()},900)}catch(e){status("Migration fehlgeschlagen: "+e.message)}finally{if(btn){btn.disabled=false;btn.textContent="Speicher optimieren"}}}
window.JGWPhotoStorageDirect={refresh:refresh,optimize:optimize};
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",refresh,{once:true});else refresh();
setTimeout(refresh,300);
var adv=byId("settingsAdvanced");if(adv)adv.addEventListener("toggle",function(){if(adv.open)refresh()});
})();
</script>'''

s, n = re.subn(r'<script id="jgw-photo-storage-direct">.*?</script>', direct, s, count=1, flags=re.S)
if n != 1:
    raise SystemExit(f'direct photo helper not replaced: {n}')

old = '''function installSettings(){var btn=document.getElementById("optimizePhotoStorageBtn");if(btn){if(!btn.dataset.storageBound){btn.dataset.storageBound="1";btn.addEventListener("click",optimize)}updateStatus();return}var exp=document.getElementById("exportBtn");if(!exp)return;var actions=exp.closest(".actions"),box=actions&&actions.parentElement;if(!box)return;var wrap=document.createElement("div");wrap.style.marginTop="10px";wrap.innerHTML='<button class="btn secondary small" id="optimizePhotoStorageBtn" type="button">Speicher optimieren</button><div class="muted" id="photoStorageStatus" style="margin-top:7px"></div>';box.appendChild(wrap);btn=document.getElementById("optimizePhotoStorageBtn");if(btn&&!btn.dataset.storageBound){btn.dataset.storageBound="1";btn.addEventListener("click",optimize)}updateStatus()}'''
new = '''function installSettings(){var btn=document.getElementById("optimizePhotoStorageBtn");if(btn){updateStatus();return}var exp=document.getElementById("exportBtn");if(!exp)return;var actions=exp.closest(".actions"),box=actions&&actions.parentElement;if(!box)return;var wrap=document.createElement("div");wrap.style.marginTop="10px";wrap.innerHTML='<button class="btn secondary small" id="optimizePhotoStorageBtn" type="button">Speicher optimieren</button><div class="muted" id="photoStorageStatus" style="margin-top:7px"></div>';box.appendChild(wrap);updateStatus()}'''
if old not in s:
    raise SystemExit('legacy installSettings block not found')
s = s.replace(old, new, 1)

old_init = 'function init(){Object.keys(specs).forEach(bindType);installSettings();installErrorAction();bindDeletes();refreshSigned();setTimeout(updateStatus,800)}'
new_init = 'function init(){Object.keys(specs).forEach(bindType);installSettings();installErrorAction();bindDeletes();refreshSigned()}'
if old_init not in s:
    raise SystemExit('legacy photo init block not found')
s = s.replace(old_init, new_init, 1)
s = s.replace('Fotospeicher bereit · Status wird geladen …', 'Verbindung zum Fotospeicher wird geprüft …', 1)

assert 'api(c,"migrate")' in s
assert 'api(c,"status")' in s
assert 'setTimeout(updateStatus,800)' not in s
p.write_text(s, encoding='utf-8')
