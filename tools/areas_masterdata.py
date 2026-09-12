from pathlib import Path

p=Path('index.html')
s=p.read_text(encoding='utf-8')

def repl(old,new,count=1):
    global s
    if old not in s:
        raise SystemExit('missing anchor: '+old[:140])
    s=s.replace(old,new,count)

# CSS
css='''\n/* JGW AREA MASTER DATA */\n.area-select-note{font-size:11px;color:var(--muted);line-height:1.35;margin-top:2px}\n.area-manager-add{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:8px;margin-top:11px}\n.area-manager-add input{width:100%;min-height:44px;border:1px solid #ddcfc0;border-radius:12px;padding:10px 12px;background:#fffdf9;color:var(--txt)}\n.area-master-list{display:grid;gap:7px;margin-top:10px}\n.area-master-row{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:10px;align-items:center;padding:10px 11px;border:1px solid var(--line);border-radius:13px;background:#fffdf9}\n.area-master-row b{display:block;color:var(--forest-dark);font-size:13px}\n.area-master-row small{display:block;color:var(--muted);font-size:11px;margin-top:2px}\n.area-master-actions{display:flex;gap:5px;flex-wrap:wrap;justify-content:flex-end}\n.area-master-empty{padding:11px 12px;border-radius:12px;background:#f7f3ec;color:var(--muted);font-size:12px}\n@media(max-width:560px){.area-manager-add{grid-template-columns:1fr}.area-manager-add .btn{width:100%}.area-master-row{grid-template-columns:1fr}.area-master-actions{justify-content:flex-start}.area-master-actions .btn{min-height:40px}}\n/* /JGW AREA MASTER DATA */\n'''
repl('</style>',css+'\n</style>')

# Replace free-text garden area fields with shared master-data selects.
repl('<div class="field"><label for="plantArea">Gartenbereich</label><input id="plantArea" placeholder="z. B. Vorgarten"></div>',
     '<div class="field"><label for="plantArea">Gartenbereich</label><select id="plantArea"></select><div class="area-select-note">Einheitliche Gartenbereiche für Pflanzen, Lebensräume und Tierbeobachtungen.</div></div>')
repl('<div class="field"><label for="habitatArea">Gartenbereich</label><input id="habitatArea" placeholder="z. B. hinteres Beet"></div>',
     '<div class="field"><label for="habitatArea">Gartenbereich</label><select id="habitatArea"></select><div class="area-select-note">Aus der gemeinsamen Bereichsliste.</div></div>')
repl('<div class="field"><label for="animalArea">Gartenbereich</label><input id="animalArea" placeholder="z. B. Wildbeet"></div>',
     '<div class="field"><label for="animalArea">Gartenbereich</label><select id="animalArea"></select><div class="area-select-note">Aus der gemeinsamen Bereichsliste.</div></div>')

# Settings manager before sync section.
anchor='''    <section class="settings-section" id="settingsSync">\n      <h3>Geräte & Synchronisation</h3>'''
area_settings='''    <section class="settings-section" id="settingsAreas">\n      <h3>Gartenbereiche</h3>\n      <div class="muted">Zentrale Liste für Pflanzen, Lebensräume und Tierbeobachtungen. Bestehende Freitexte werden automatisch übernommen und zusammengeführt.</div>\n      <div class="area-manager-add"><input id="areaNewName" autocomplete="off" placeholder="z. B. Vorgarten"><button class="btn secondary small" id="areaAddBtn" type="button">Bereich hinzufügen</button></div>\n      <div class="area-master-list" id="areaMasterList"></div>\n    </section>\n\n'''+anchor
repl(anchor,area_settings)

# State: add central areas table.
repl('var state={days:30,plz:"",loc:null,gardenCenter:null,weather:null,plants:[],habitats:[],animals:[],zones:[],',
     'var state={days:30,plz:"",loc:null,gardenCenter:null,weather:null,plants:[],habitats:[],animals:[],areas:[],zones:[],')

# Area master-data helpers.
old='function normalizeAnimalObservation(a){a=a||{};if(!a.id)a.id=uid();if(!a.date)a.date=isoToday();if(!a.created)a.created=isoToday();if(!a.group)a.group="other";return a}\n'
new=old+'''function normalizeAreaRecord(a,i){a=a||{};var name=String(a.name||"").trim();return{id:a.id||uid(),name:name,sort:Number.isFinite(Number(a.sort))?Number(a.sort):(i||0),active:a.active!==false}}\nfunction areaKey(v){return String(v||"").trim().toLocaleLowerCase("de-DE")}\nfunction sortedAreas(){return(state.areas||[]).filter(function(a){return a&&a.name&&a.active!==false}).slice().sort(function(a,b){var d=Number(a.sort||0)-Number(b.sort||0);return d||a.name.localeCompare(b.name,"de")})}\nfunction areaById(id){return(state.areas||[]).find(function(a){return a.id===id})||null}\nfunction areaByName(name){var k=areaKey(name);return(state.areas||[]).find(function(a){return areaKey(a.name)===k})||null}\nfunction areaUsageCount(id){var n=0;[state.plants,state.habitats,state.animals].forEach(function(arr){(arr||[]).forEach(function(x){if(x.areaId===id)n++})});return n}\nfunction migrateAreaMasterData(){var changed=false,seen={};state.areas=(Array.isArray(state.areas)?state.areas:[]).map(normalizeAreaRecord).filter(function(a){if(!a.name)return false;var k=areaKey(a.name);if(seen[k]){changed=true;return false}seen[k]=a.id;return true});var maxSort=state.areas.reduce(function(m,a){return Math.max(m,Number(a.sort||0))},-1);[state.plants,state.habitats,state.animals].forEach(function(arr){(arr||[]).forEach(function(x){var ar=x.areaId?areaById(x.areaId):null;if(!ar&&x.area){ar=areaByName(x.area);if(!ar){ar=normalizeAreaRecord({name:String(x.area).trim(),sort:++maxSort},maxSort);state.areas.push(ar);changed=true}}if(ar){if(x.areaId!==ar.id||x.area!==ar.name)changed=true;x.areaId=ar.id;x.area=ar.name}else{if(x.areaId||x.area)changed=true;x.areaId="";x.area=""}})});return changed}\nfunction areaSelection(selectId){var node=el(selectId),id=node&&node.value&&node.value!=="__new__"?node.value:"",a=areaById(id);return{id:a?a.id:"",name:a?a.name:""}}\nfunction populateAreaSelect(selectId,selectedId,legacyName){var node=el(selectId);if(!node)return;var id=selectedId||"",legacy=legacyName||"",a=id?areaById(id):areaByName(legacy);if(a)id=a.id;node.innerHTML='<option value="">– ohne Zuordnung –</option>'+sortedAreas().map(function(x){return'<option value="'+esc(x.id)+'">'+esc(x.name)+'</option>'}).join('')+'<option value="__new__">＋ Neuen Bereich anlegen …</option>';node.value=id&&areaById(id)?id:""}\nfunction refreshAreaSelects(){[["plantArea",state.editPlantId&&state.plants.find(function(x){return x.id===state.editPlantId})],["habitatArea",state.editHabitatId&&state.habitats.find(function(x){return x.id===state.editHabitatId})],["animalArea",state.editAnimalId&&state.animals.find(function(x){return x.id===state.editAnimalId})]].forEach(function(x){var n=el(x[0]);if(!n)return;var current=n.value!=="__new__"?n.value:"",entry=x[1];populateAreaSelect(x[0],current||(entry&&entry.areaId)||"",entry&&entry.area||"")})}\nfunction addGardenArea(name,selectId){name=String(name||"").trim();if(!name)return null;var a=areaByName(name);if(!a){var sort=state.areas.reduce(function(m,x){return Math.max(m,Number(x.sort||0))},-1)+1;a=normalizeAreaRecord({name:name,sort:sort},sort);state.areas.push(a);save();notice('Gartenbereich „'+name+'“ angelegt.')}renderAreaManager();refreshAreaSelects();if(selectId&&el(selectId))el(selectId).value=a.id;return a}\nfunction bindAreaSelect(selectId){var node=el(selectId);if(!node||node.dataset.areaBound)return;node.dataset.areaBound="1";node.addEventListener("change",function(){if(node.value!=="__new__")return;var name=prompt("Neuen Gartenbereich anlegen:");if(name&&name.trim())addGardenArea(name,selectId);else node.value=""})}\nfunction renameGardenArea(id){var a=areaById(id);if(!a)return;var name=prompt("Gartenbereich umbenennen:",a.name);if(!name||!name.trim()||name.trim()===a.name)return;var existing=areaByName(name);if(existing&&existing.id!==id){globalError("Ein Gartenbereich mit diesem Namen existiert bereits.");return}a.name=name.trim();[state.plants,state.habitats,state.animals].forEach(function(arr){arr.forEach(function(x){if(x.areaId===id)x.area=a.name})});save();renderAll();notice("Gartenbereich umbenannt.")}\nfunction deleteGardenArea(id){var a=areaById(id);if(!a)return;var used=areaUsageCount(id),msg=used?'„'+a.name+'“ wird bei '+used+' Eintrag'+(used===1?'':'en')+' verwendet. Beim Löschen werden diese Einträge auf „ohne Zuordnung“ gesetzt. Fortfahren?':'Gartenbereich „'+a.name+'“ löschen?';if(!confirm(msg))return;[state.plants,state.habitats,state.animals].forEach(function(arr){arr.forEach(function(x){if(x.areaId===id){x.areaId="";x.area=""}})});state.areas=state.areas.filter(function(x){return x.id!==id});save();renderAll();notice("Gartenbereich gelöscht.")}\nfunction renderAreaManager(){var box=el("areaMasterList");if(!box)return;var items=sortedAreas();box.innerHTML=items.length?items.map(function(a){var n=areaUsageCount(a.id);return'<div class="area-master-row"><div><b>'+esc(a.name)+'</b><small>'+n+' Zuordnung'+(n===1?'':'en')+'</small></div><div class="area-master-actions"><button class="btn ghost small areaRename" data-id="'+a.id+'" type="button">Umbenennen</button><button class="btn ghost small areaDelete" data-id="'+a.id+'" type="button">Löschen</button></div></div>'}).join(''):'<div class="area-master-empty">Noch keine Gartenbereiche. Beim ersten bestehenden Bereich oder über „Bereich hinzufügen“ wird die Liste angelegt.</div>';box.querySelectorAll('.areaRename').forEach(function(b){b.addEventListener('click',function(){renameGardenArea(b.dataset.id)})});box.querySelectorAll('.areaDelete').forEach(function(b){b.addEventListener('click',function(){deleteGardenArea(b.dataset.id)})})}\n'''
repl(old,new)

# Form reset/open/save integration.
repl('function resetPlantForm(){el("plantForm").reset();el("plantType").value="bed";',
     'function resetPlantForm(){el("plantForm").reset();populateAreaSelect("plantArea","","");el("plantType").value="bed";')
repl('el("plantScientific").value=p.scientific||"";el("plantArea").value=p.area||"";el("plantType")',
     'el("plantScientific").value=p.scientific||"";populateAreaSelect("plantArea",p.areaId||"",p.area||"");el("plantType")')
old_pf='return normalizePlantData({id:old?old.id:uid(),name:name,scientific:el("plantScientific").value.trim(),family:el("plantFamily").value.trim()||(old?old.family||"":""),area:el("plantArea").value.trim(),type:'
new_pf='var ar=areaSelection("plantArea");return normalizePlantData({id:old?old.id:uid(),name:name,scientific:el("plantScientific").value.trim(),family:el("plantFamily").value.trim()||(old?old.family||"":""),areaId:ar.id,area:ar.name,type:'
repl(old_pf,new_pf)

repl('function resetHabitatForm(){el("habitatForm").reset();el("habitatId").value="";',
     'function resetHabitatForm(){el("habitatForm").reset();populateAreaSelect("habitatArea","","");el("habitatId").value="";')
repl('el("habitatStatus").value=h.status||"present";el("habitatArea").value=h.area||"";el("habitatNotes")',
     'el("habitatStatus").value=h.status||"present";populateAreaSelect("habitatArea",h.areaId||"",h.area||"");el("habitatNotes")')
old_hf='return normalizeHabitatEntry({id:old?old.id:uid(),type:el("habitatType").value,status:el("habitatStatus").value,area:el("habitatArea").value.trim(),photo:'
new_hf='var ar=areaSelection("habitatArea");return normalizeHabitatEntry({id:old?old.id:uid(),type:el("habitatType").value,status:el("habitatStatus").value,areaId:ar.id,area:ar.name,photo:'
repl(old_hf,new_hf)

repl('function resetAnimalForm(){el("animalForm").reset();el("animalId").value="";',
     'function resetAnimalForm(){el("animalForm").reset();populateAreaSelect("animalArea","","");el("animalId").value="";')
repl('el("animalDate").value=a.date||isoToday();el("animalArea").value=a.area||"";el("animalLinkedPlant")',
     'el("animalDate").value=a.date||isoToday();populateAreaSelect("animalArea",a.areaId||"",a.area||"");el("animalLinkedPlant")')
old_af='return normalizeAnimalObservation({id:old?old.id:uid(),taxonId:el("animalTaxonId").value||"",name:name,scientific:el("animalScientific").value.trim(),group:el("animalGroup").value,date:el("animalDate").value||isoToday(),area:el("animalArea").value.trim(),linkedPlantId:'
new_af='var ar=areaSelection("animalArea");return normalizeAnimalObservation({id:old?old.id:uid(),taxonId:el("animalTaxonId").value||"",name:name,scientific:el("animalScientific").value.trim(),group:el("animalGroup").value,date:el("animalDate").value||isoToday(),areaId:ar.id,area:ar.name,linkedPlantId:'
repl(old_af,new_af)

# Storage, sync and backup.
repl('state.animals=(Array.isArray(d.animals)?d.animals:[]).map(normalizeAnimalObservation);state.zones=',
     'state.animals=(Array.isArray(d.animals)?d.animals:[]).map(normalizeAnimalObservation);state.areas=(Array.isArray(d.areas)?d.areas:[]).map(normalizeAreaRecord);migrateAreaMasterData();state.zones=')
repl('function cloudPayload(){return{version:3,plz:',
     'function cloudPayload(){return{version:4,plz:')
repl('animals:state.animals||[],zones:state.zones||[],ecology:',
     'animals:state.animals||[],areas:state.areas||[],zones:state.zones||[],ecology:')
repl('plants:state.plants,habitats:state.habitats,animals:state.animals,zones:state.zones,ecology:',
     'plants:state.plants,habitats:state.habitats,animals:state.animals,areas:state.areas,zones:state.zones,ecology:')
repl('state.animals=(Array.isArray(p.animals)?p.animals:[]).map(normalizeAnimalObservation);state.zones=',
     'state.animals=(Array.isArray(p.animals)?p.animals:[]).map(normalizeAnimalObservation);state.areas=(Array.isArray(p.areas)?p.areas:[]).map(normalizeAreaRecord);migrateAreaMasterData();state.zones=')
repl('function exportBackup(){var data={version:9,',
     'function exportBackup(){var data={version:10,')
repl('plants:state.plants,habitats:state.habitats,animals:state.animals,zones:state.zones,ecology:',
     'plants:state.plants,habitats:state.habitats,animals:state.animals,areas:state.areas,zones:state.zones,ecology:',1)
repl('state.animals=(Array.isArray(data.animals)?data.animals:[]).map(normalizeAnimalObservation);state.zones=data.zones;',
     'state.animals=(Array.isArray(data.animals)?data.animals:[]).map(normalizeAnimalObservation);state.areas=(Array.isArray(data.areas)?data.areas:[]).map(normalizeAreaRecord);migrateAreaMasterData();state.zones=data.zones;')

# Render manager and initialize shared selects.
repl('function renderAll(){applyAppearance();renderOnboardingGuide();renderHeader();renderToday();renderPlants();',
     'function renderAll(){applyAppearance();renderOnboardingGuide();renderHeader();renderAreaManager();renderToday();renderPlants();')
repl('load();applyAppearance();buildMonthChecks("fertMonths","fert");buildMonthChecks("cutMonths","cut");buildMonthChecks("bloomMonths","bloom");populateHabitatTypes();populateAnimalLinks();',
     'load();migrateAreaMasterData();applyAppearance();buildMonthChecks("fertMonths","fert");buildMonthChecks("cutMonths","cut");buildMonthChecks("bloomMonths","bloom");populateHabitatTypes();populateAnimalLinks();populateAreaSelect("plantArea","","");populateAreaSelect("habitatArea","","");populateAreaSelect("animalArea","","");bindAreaSelect("plantArea");bindAreaSelect("habitatArea");bindAreaSelect("animalArea");renderAreaManager();')

# Area manager events and clear behavior.
repl('el("settingsGear").addEventListener("click",function(){openSettings()});',
     'el("settingsGear").addEventListener("click",function(){renderAreaManager();openSettings()});\nel("areaAddBtn").addEventListener("click",function(){var a=addGardenArea(el("areaNewName").value);if(a)el("areaNewName").value=""});\nel("areaNewName").addEventListener("keydown",function(e){if(e.key==="Enter"){e.preventDefault();el("areaAddBtn").click()}});')
repl('if(confirm("Alle Pflanzen, Lebensräume, Tierbeobachtungen, Zonen und Pflegehistorien löschen?")){state.plants=[];state.habitats=[];state.animals=[];state.zones=[];',
     'if(confirm("Alle Pflanzen, Lebensräume, Tierbeobachtungen, Gartenbereiche, Zonen und Pflegehistorien löschen?")){state.plants=[];state.habitats=[];state.animals=[];state.areas=[];state.zones=[];')

# Update backup copy wording.
repl('Zusätzliche lokale Sicherung von Pflanzen, Fotos, Zonen und Pflegehistorie.',
     'Zusätzliche lokale Sicherung von Pflanzen, Fotos, Gartenbereichen, Zonen und Pflegehistorie.')

# Sanity assertions.
required=['id="settingsAreas"','id="plantArea"></select>','id="habitatArea"></select>','id="animalArea"></select>','function migrateAreaMasterData','areas:state.areas','version:10','function renderAreaManager']
for x in required:
    assert x in s,x
assert '<input id="plantArea"' not in s
assert '<input id="habitatArea"' not in s
assert '<input id="animalArea"' not in s
p.write_text(s,encoding='utf-8')
print('patched',len(s))
