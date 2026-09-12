from pathlib import Path

p=Path('index.html')
s=p.read_text(encoding='utf-8')
orig=s

# 1) Button wording
old='''<button class="btn secondary small" id="refreshPlantDataBtn" type="button">Pflanzendaten neu laden</button>'''
new='''<button class="btn secondary small" id="refreshPlantDataBtn" type="button">Pflanzendaten prüfen &amp; aktualisieren</button>'''
assert old in s
s=s.replace(old,new,1)

# 2) CSS for update chooser
marker='''/* /JGW PLANT DATA ENRICHMENT */'''
css=r'''
/* JGW SELECTIVE PLANT UPDATE */
.plant-update-overlay{position:fixed;inset:0;z-index:1400;background:rgba(46,54,43,.48);display:grid;place-items:center;padding:18px;backdrop-filter:blur(3px)}
.plant-update-dialog{width:min(720px,100%);max-height:min(82vh,760px);overflow:auto;background:var(--paper);border:1px solid var(--line);border-radius:22px;box-shadow:0 22px 60px rgba(40,50,38,.24);padding:18px}
.plant-update-dialog h3{margin:0;color:var(--forest-dark)}
.plant-update-tools{display:flex;gap:8px;flex-wrap:wrap;margin:12px 0}
.plant-update-list{display:grid;gap:8px;margin:12px 0}
.plant-update-row{display:grid;grid-template-columns:auto 1fr;gap:10px;align-items:start;padding:11px 12px;border:1px solid var(--line);border-radius:14px;background:#fffdf9}
.plant-update-row input{width:22px;height:22px;margin-top:2px;accent-color:var(--forest)}
.plant-update-label{font-weight:800;color:var(--forest-dark)}
.plant-update-values{display:grid;grid-template-columns:1fr auto 1fr;gap:8px;align-items:center;margin-top:5px;font-size:12px}
.plant-update-old{color:var(--muted)}.plant-update-new{color:var(--forest-dark);font-weight:700}.plant-update-arrow{color:var(--gold);font-weight:800}
.plant-update-source{font-size:11px;color:var(--muted);margin-top:5px;line-height:1.35}
.plant-update-empty{padding:16px;border-radius:14px;background:var(--ok);color:var(--forest-dark);font-weight:700;text-align:center}
@media(max-width:560px){.plant-update-overlay{padding:10px}.plant-update-dialog{max-height:88vh;padding:14px;border-radius:18px}.plant-update-values{grid-template-columns:1fr}.plant-update-arrow{display:none}.plant-update-dialog>.actions .btn{flex:1 1 100%}}
/* /JGW SELECTIVE PLANT UPDATE */
'''
assert marker in s
s=s.replace(marker,css+'\n'+marker,1)

# 3) Selective preview/update functions directly after enrichPlantForm
needle='''async function applyPlantSearchResult(x){'''
assert needle in s
functions=r'''
function plantFormDataSnapshot(){return{scientific:el("plantScientific").value,family:el("plantFamily").value,water:el("plantWater").value,fert:fieldMonths("fert"),cut:fieldMonths("cut"),bloom:fieldMonths("bloom"),native:el("plantNative").value,flower:el("plantFlowerAccess").value,meta:state.plantDataMeta?JSON.parse(JSON.stringify(state.plantDataMeta)):null}}
function restorePlantFormData(x){x=x||{};el("plantScientific").value=x.scientific||"";el("plantFamily").value=x.family||"";el("plantWater").value=x.water||"normal";setCheckedMonths("fert",x.fert||[]);setCheckedMonths("cut",x.cut||[]);setCheckedMonths("bloom",x.bloom||[]);el("plantNative").value=x.native||"auto";el("plantFlowerAccess").value=x.flower||"auto";state.plantDataMeta=x.meta?JSON.parse(JSON.stringify(x.meta)):null}
function plantUpdateValueText(key,v){if(key==="fert"||key==="cut"||key==="bloom")return(v&&v.length)?v.map(function(m){return MONTHS[m-1]}).join(", "):"–";if(key==="water")return v==="high"?"hoch":v==="low"?"niedrig":v==="normal"?"normal":"–";if(key==="native")return v==="yes"?"heimisch / regional":v==="no"?"nicht heimisch":"unbekannt";if(key==="flower")return v==="open"?"offen / gut zugänglich":v==="partial"?"teilweise zugänglich":v==="closed"?"gefüllt / eingeschränkt":"unbekannt";if(key==="refPhoto")return v?"iNaturalist-Referenzbild":"–";return String(v||"–")}
function plantUpdateMissing(key,v){if(key==="fert"||key==="cut"||key==="bloom")return!v||!v.length;if(key==="native"||key==="flower")return!v||v==="auto";if(key==="refPhoto")return!v;return!String(v||"").trim()}
function plantUpdateSame(a,b){if(Array.isArray(a)||Array.isArray(b))return JSON.stringify(a||[])===JSON.stringify(b||[]);return String(a==null?"":a)===String(b==null?"":b)}
function ensurePlantUpdateDialog(){var o=el("plantUpdateOverlay");if(o)return o;o=document.createElement("div");o.id="plantUpdateOverlay";o.className="plant-update-overlay hidden";o.setAttribute("aria-hidden","true");o.innerHTML='<div class="plant-update-dialog" role="dialog" aria-modal="true" aria-labelledby="plantUpdateTitle"><div class="topline"><div><h3 id="plantUpdateTitle">Pflanzendaten aktualisieren</h3><div class="muted" id="plantUpdateIntro">Gefundene Änderungen auswählen.</div></div><button class="btn ghost small" id="plantUpdateClose" type="button">Schließen</button></div><div class="plant-update-tools"><button class="btn secondary small" id="plantUpdateSelectMissing" type="button">Nur fehlende auswählen</button><button class="btn secondary small" id="plantUpdateSelectAll" type="button">Alle Änderungen auswählen</button><button class="btn ghost small" id="plantUpdateSelectNone" type="button">Keine</button></div><div class="plant-update-list" id="plantUpdateList"></div><div class="actions" style="margin-top:12px"><button class="btn" id="plantUpdateApply" type="button">Ausgewählte ins Formular übernehmen</button><button class="btn ghost" id="plantUpdateCancel" type="button">Abbrechen</button></div></div>';document.body.appendChild(o);function close(){o.classList.add("hidden");o.setAttribute("aria-hidden","true")}el("plantUpdateClose").addEventListener("click",close);el("plantUpdateCancel").addEventListener("click",close);o.addEventListener("click",function(e){if(e.target===o)close()});el("plantUpdateSelectAll").addEventListener("click",function(){o.querySelectorAll('input[data-update-key]').forEach(function(c){c.checked=true})});el("plantUpdateSelectNone").addEventListener("click",function(){o.querySelectorAll('input[data-update-key]').forEach(function(c){c.checked=false})});el("plantUpdateSelectMissing").addEventListener("click",function(){o.querySelectorAll('input[data-update-key]').forEach(function(c){c.checked=c.dataset.missing==="1"})});el("plantUpdateApply").addEventListener("click",applySelectedPlantUpdates);return o}
var pendingPlantUpdate=null;
function showPlantUpdateChooser(before,after,meta){var defs=[
 {key:"scientific",label:"Botanischer Name",field:"Botanischer Name"},
 {key:"family",label:"Familie",field:"Familie"},
 {key:"water",label:"Wasserbedarf",field:"Wasserbedarf"},
 {key:"fert",label:"Düngemonate",field:"Düngemonate"},
 {key:"cut",label:"Schnittmonate",field:"Schnittmonate"},
 {key:"bloom",label:"Blühmonate",field:"Blühmonate"},
 {key:"native",label:"Herkunft",field:"Herkunft"},
 {key:"flower",label:"Blütenzugang",field:"Blütenzugang"}
],fields=new Set(meta&&meta.fields||[]),rows=[];defs.forEach(function(d){if(!fields.has(d.field))return;var ov=before[d.key],nv=after[d.key];if(plantUpdateSame(ov,nv))return;rows.push({key:d.key,label:d.label,old:ov,newv:nv,missing:plantUpdateMissing(d.key,ov)})});var oldRef=before.meta&&before.meta.refPhoto||"",newRef=meta&&meta.refPhoto||"";if(newRef&&!plantUpdateSame(oldRef,newRef)&&!state.photoData)rows.push({key:"refPhoto",label:"Referenzbild",old:oldRef,newv:newRef,missing:!oldRef});pendingPlantUpdate={before:before,after:after,meta:meta,rows:rows};var o=ensurePlantUpdateDialog(),list=el("plantUpdateList"),src=(meta&&meta.sources||[]).join(" · ");el("plantUpdateIntro").textContent=rows.length?"Gefundene Änderungen einzeln auswählen. Bereits gepflegte Werte bleiben standardmäßig unangetastet.":"Die verfügbaren Quellen liefern derzeit keine abweichenden Werte.";list.innerHTML=rows.length?rows.map(function(r){return'<label class="plant-update-row"><input type="checkbox" data-update-key="'+r.key+'" data-missing="'+(r.missing?'1':'0')+'" '+(r.missing?'checked':'')+'><span><span class="plant-update-label">'+esc(r.label)+'</span><span class="plant-update-values"><span class="plant-update-old">Aktuell: '+esc(plantUpdateValueText(r.key,r.old))+'</span><span class="plant-update-arrow">→</span><span class="plant-update-new">Neu: '+esc(plantUpdateValueText(r.key,r.newv))+'</span></span>'+(src?'<span class="plant-update-source">Quelle: '+esc(src)+'</span>':'')+'</span></label>'}).join(""):'<div class="plant-update-empty">Keine neuen oder abweichenden Werte gefunden.</div>';show("plantUpdateApply",rows.length>0);show("plantUpdateSelectMissing",rows.length>0);show("plantUpdateSelectAll",rows.length>0);show("plantUpdateSelectNone",rows.length>0);o.classList.remove("hidden");o.setAttribute("aria-hidden","false")}
function applySelectedPlantUpdates(){if(!pendingPlantUpdate)return;var o=ensurePlantUpdateDialog(),keys=Array.from(o.querySelectorAll('input[data-update-key]:checked')).map(function(c){return c.dataset.updateKey});if(!keys.length){notice("Keine Werte ausgewählt.");return}var a=pendingPlantUpdate.after,m=pendingPlantUpdate.meta||{},oldMeta=pendingPlantUpdate.before.meta||{};keys.forEach(function(k){if(k==="scientific")el("plantScientific").value=a.scientific||"";else if(k==="family")el("plantFamily").value=a.family||"";else if(k==="water")el("plantWater").value=a.water||"normal";else if(k==="fert")setCheckedMonths("fert",a.fert||[]);else if(k==="cut")setCheckedMonths("cut",a.cut||[]);else if(k==="bloom")setCheckedMonths("bloom",a.bloom||[]);else if(k==="native")el("plantNative").value=a.native||"auto";else if(k==="flower")el("plantFlowerAccess").value=a.flower||"auto"});var merged=Object.assign({},oldMeta,m);if(!keys.includes("refPhoto")){merged.refPhoto=oldMeta.refPhoto||"";merged.refAttribution=oldMeta.refAttribution||"";merged.refLicense=oldMeta.refLicense||""}state.plantDataMeta=merged;o.classList.add("hidden");o.setAttribute("aria-hidden","true");renderPlantDataStatus(state.plantDataMeta,"Ausgewählte Werte wurden ins Formular übernommen. Bitte anschließend speichern.","good");renderPlantEcoPreview();notice(keys.length+" Wert"+(keys.length===1?"":"e")+" übernommen · jetzt speichern.");pendingPlantUpdate=null}
async function previewPlantDataUpdate(){var btn=el("refreshPlantDataBtn");if(!state.editPlantId){await enrichPlantForm({common:el("plantName").value.trim(),sci:el("plantScientific").value.trim(),family:el("plantFamily").value.trim(),source:"manuell"},true);return}var before=plantFormDataSnapshot(),base={common:el("plantName").value.trim(),sci:before.scientific,family:before.family,source:"manuell"};if(btn){btn.disabled=true;btn.textContent="Pflanzendaten werden geprüft …"}try{el("plantScientific").value="";el("plantFamily").value="";el("plantNative").value="auto";el("plantFlowerAccess").value="auto";setCheckedMonths("fert",[]);setCheckedMonths("cut",[]);setCheckedMonths("bloom",[]);state.plantDataMeta=null;var meta=await enrichPlantForm(base,true),after=plantFormDataSnapshot();restorePlantFormData(before);renderPlantDataStatus(before.meta);renderPlantEcoPreview();if(meta)showPlantUpdateChooser(before,after,meta);else notice("Pflanzendaten konnten gerade nicht geprüft werden.")}finally{if(btn){btn.disabled=false;btn.innerHTML="Pflanzendaten prüfen &amp; aktualisieren"}}}

'''
s=s.replace(needle,functions+needle,1)

# 4) Replace direct refresh handler with selective preview
old_handler='''el("refreshPlantDataBtn").addEventListener("click",function(){enrichPlantForm({common:el("plantName").value.trim(),sci:el("plantScientific").value.trim(),family:el("plantFamily").value.trim(),source:"manuell"},true)});'''
new_handler='''el("refreshPlantDataBtn").addEventListener("click",previewPlantDataUpdate);'''
assert old_handler in s
s=s.replace(old_handler,new_handler,1)

# 5) Add a direct "Daten prüfen" action in plant detail and listener.
old_action='''<button class="btn detailEdit" data-id="'+p.id+'" type="button">Bearbeiten</button><button class="btn secondary detailPlace"'''
new_action='''<button class="btn detailEdit" data-id="'+p.id+'" type="button">Bearbeiten</button><button class="btn ghost detailRefresh" data-id="'+p.id+'" type="button">Daten prüfen</button><button class="btn secondary detailPlace"'''
assert old_action in s
s=s.replace(old_action,new_action,1)
old_listener='''document.querySelectorAll(".detailEdit").forEach(function(b){b.addEventListener("click",function(){closePlantDetail();openPlantEditor(b.dataset.id)})});document.querySelectorAll(".detailPlace")'''
new_listener='''document.querySelectorAll(".detailEdit").forEach(function(b){b.addEventListener("click",function(){closePlantDetail();openPlantEditor(b.dataset.id)})});document.querySelectorAll(".detailRefresh").forEach(function(b){b.addEventListener("click",function(){var id=b.dataset.id;closePlantDetail();openPlantEditor(id);if(el("plantAdvanced"))el("plantAdvanced").open=true;setTimeout(previewPlantDataUpdate,80)})});document.querySelectorAll(".detailPlace")'''
assert old_listener in s
s=s.replace(old_listener,new_listener,1)

assert s!=orig
p.write_text(s,encoding='utf-8')
print('patched',len(orig),'->',len(s))
