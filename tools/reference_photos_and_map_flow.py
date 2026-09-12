from pathlib import Path
import re

p=Path('index.html')
s=p.read_text(encoding='utf-8')
orig=s

def one(old,new,label):
    global s
    n=s.count(old)
    assert n==1, f'{label}: expected 1 occurrence, got {n}'
    s=s.replace(old,new,1)

# Reference-photo badge styling.
needle='/* JGW PHOTO DISPLAY UPGRADE */\n'
assert needle in s
s=s.replace(needle, needle+'''.reference-photo-badge{position:absolute;left:8px;bottom:8px;z-index:4;background:rgba(40,54,38,.78);color:#fff;border:1px solid rgba(255,255,255,.36);border-radius:999px;padding:4px 7px;font:700 9px/1.1 system-ui,-apple-system,sans-serif;letter-spacing:.02em;backdrop-filter:blur(7px)}\n.reference-photo-note{font-size:10px;line-height:1.35;color:var(--muted);margin-top:5px}\n''',1)

# Shared plant display-photo helpers. Reference photos live in careMeta to remain backward compatible.
one(
'function normalizePlantData(p){p=p||{};if(typeof p.favorite!=="boolean")p.favorite=false;if(!Array.isArray(p.bloomMonths))p.bloomMonths=[];if(!p.ecoNative)p.ecoNative="auto";if(!p.ecoFlowerAccess)p.ecoFlowerAccess="auto";if(!p.created)p.created=isoToday();if(!p.family)p.family="";return p}',
'''function normalizePlantData(p){p=p||{};if(typeof p.favorite!=="boolean")p.favorite=false;if(!Array.isArray(p.bloomMonths))p.bloomMonths=[];if(!p.ecoNative)p.ecoNative="auto";if(!p.ecoFlowerAccess)p.ecoFlowerAccess="auto";if(!p.created)p.created=isoToday();if(!p.family)p.family="";return p}\nfunction plantPhotoInfo(p){var m=p&&p.careMeta||{},own=p&&p.photo||"",ref=m.refPhoto||"";return{src:own||ref,isReference:!own&&!!ref,attribution:m.refAttribution||"",license:m.refLicense||""}}\nfunction plantPhotoMarkup(p,alt,badge){var ph=plantPhotoInfo(p);if(!ph.src)return'';return '<img src="'+esc(ph.src)+'" alt="'+esc(alt||p.name||'Pflanze')+'">'+(ph.isReference&&badge?'<span class="reference-photo-badge">Referenz · iNaturalist</span>':'')}\nfunction plantReferenceNote(p){var ph=plantPhotoInfo(p);if(!ph.isReference)return'';var a=ph.attribution||"Bildnachweis beim Quellbild",lic=ph.license?" · "+ph.license:"";return '<div class="reference-photo-note">Referenzbild aus iNaturalist · '+esc(a+lic)+'</div>'}''',
'plant photo helpers')

# Store the iNaturalist default photo with enrichment metadata.
one(
'state.plantDataMeta={sources:ctx.sources,fields:ctx.fields,enrichedAt:new Date().toISOString(),inatTaxonId:tax&&tax.id||null,gbifKey:gb&&gb.key||null};',
'''var rp=tax&&tax.default_photo||{};state.plantDataMeta={sources:ctx.sources,fields:ctx.fields,enrichedAt:new Date().toISOString(),inatTaxonId:tax&&tax.id||null,gbifKey:gb&&gb.key||null,refPhoto:rp.medium_url||rp.large_url||rp.square_url||"",refAttribution:rp.attribution||"",refLicense:rp.license_code||""};''',
'plant enrichment reference photo')

# Cards/list use own photo first, then reference image.
start=s.index('function plantCardHtml(p,feature)')
end=s.index('function bindPlantCollectionEvents()',start)
new_cards='''function plantCardHtml(p,feature){var wa=waterAssessment(p),z=currentZoneForPlant(p),e=plantInsectValue(p),photo=plantPhotoMarkup(p,p.name,true)||'<div class="collection-no-photo">🌿<small>Foto ergänzen</small></div>',area=p.area?esc(p.area):(z?esc(lightLabel(z.light)):"Standort noch nicht benannt"),chips=[];if(p.type&&p.type!=="bed")chips.push(typeLabel(p.type));if(establishmentInfo(p).days<=90)chips.push("Anwachsphase");if(e.bloomMonths.includes(new Date().getMonth()+1))chips.push("blüht jetzt");return'<article class="collection-card'+(feature?' feature':'')+'"><div class="collection-photo"><button class="collection-card-main plantOpen" data-id="'+p.id+'" type="button" aria-label="'+esc(p.name)+' öffnen">'+photo+'</button><button class="favorite-plant '+(p.favorite?'on':'')+'" data-id="'+p.id+'" type="button" aria-label="'+(p.favorite?'Favorit entfernen':'Als Favorit markieren')+'">'+(p.favorite?'★':'☆')+'</button><span class="insect-badge '+ecoBadgeClass(e.score)+'">🐝 '+e.score+'</span></div><button class="collection-card-main plantOpen" data-id="'+p.id+'" type="button"><div class="collection-body"><div class="collection-name">'+esc(p.name)+'</div><div class="collection-latin">'+esc(p.scientific||'')+'</div><div class="collection-area">'+area+'</div><div class="collection-status"><span class="statusdot '+wa.level+'"></span>'+esc(wa.title)+'</div>'+(chips.length?'<div class="collection-chips">'+chips.map(function(c){return'<span class="collection-chip">'+esc(c)+'</span>'}).join('')+'</div>':'')+'</div></button></article>'}\nfunction plantListRowHtml(p){var wa=waterAssessment(p),e=plantInsectValue(p),photo=plantPhotoMarkup(p,"",false)||'🌿';return'<article class="plant-list-row"><div class="plant-list-thumb">'+photo+'</div><button class="plant-list-main plantOpen" data-id="'+p.id+'" type="button"><b><span class="statusdot '+wa.level+'"></span>'+esc(p.name)+'</b><small>'+esc(p.area||'Ohne Bereich')+' · '+esc(wa.title)+'</small></button><div><div class="list-eco">🐝 '+e.score+'</div><button class="favorite-plant '+(p.favorite?'on':'')+'" style="position:static;margin-top:4px;width:30px;height:30px" data-id="'+p.id+'" type="button">'+(p.favorite?'★':'☆')+'</button></div></article>'}\n'''
s=s[:start]+new_cards+s[end:]

# Detail hero uses fallback reference photo and visibly credits it.
one(
'function renderPlantDetail(p){var e=plantInsectValue(p),wa=waterAssessment(p),z=currentZoneForPlant(p),photo=p.photo?\'<img src="\'+p.photo+\'" alt="\'+esc(p.name)+\'">\':\'🌿\',lasts=',
'function renderPlantDetail(p){var e=plantInsectValue(p),wa=waterAssessment(p),z=currentZoneForPlant(p),photo=plantPhotoMarkup(p,p.name,true)||\'🌿\',lasts=',
'plant detail photo fallback')
one(
"<div class=\"muted\" style=\"margin-top:5px\">'+esc(p.area||'Standort noch nicht benannt')+'</div></div><button class=\"favorite-plant ",
"<div class=\"muted\" style=\"margin-top:5px\">'+esc(p.area||'Standort noch nicht benannt')+'</div>'+plantReferenceNote(p)+'</div><button class=\"favorite-plant ",
'plant detail photo credit')

# Existing plants: silently fill missing reference photos once per session.
insert_before='function renderPlantEcoPreview(){'
assert insert_before in s
backfill='''var plantRefBackfillRunning=false,plantRefBackfillDone=false;\nasync function backfillPlantReferencePhotos(){if(plantRefBackfillRunning||plantRefBackfillDone)return;var items=state.plants.filter(function(p){return !p.photo&&!(p.careMeta&&p.careMeta.refPhoto)&&(p.scientific||p.name)}).slice(0,40);if(!items.length){plantRefBackfillDone=true;return}plantRefBackfillRunning=true;var changed=false;for(var i=0;i<items.length;i+=4){await Promise.all(items.slice(i,i+4).map(async function(p){try{var q=p.scientific||p.name,r=await fetch("https://api.inaturalist.org/v1/taxa/autocomplete?q="+encodeURIComponent(q)+"&taxon_id=47126&locale=de&per_page=6",{headers:{Accept:"application/json"}});if(!r.ok)return;var d=await r.json(),a=(d.results||[]).filter(function(t){return String(t.iconic_taxon_name||"").toLowerCase()==="plantae"}),tax=a.find(function(t){return p.scientific&&String(t.name||"").toLowerCase()===String(p.scientific).toLowerCase()})||a[0],ph=tax&&tax.default_photo||{},src=ph.medium_url||ph.large_url||ph.square_url||"";if(!src)return;p.careMeta=Object.assign({},p.careMeta||{},{inatTaxonId:(p.careMeta&&p.careMeta.inatTaxonId)||tax.id||null,refPhoto:src,refAttribution:ph.attribution||"",refLicense:ph.license_code||""});changed=true}catch(e){}}))}plantRefBackfillRunning=false;plantRefBackfillDone=true;if(changed){save();renderPlants()}}\n'''
s=s.replace(insert_before,backfill+insert_before,1)

# After placing anything on the map, return to the relevant Naturgarten tab and show its detail.
insert='function beginPlacePlant(id){'
assert insert in s
flow='''function finishNaturePlacement(kind,id,message){setMapEditing(false);switchView("plants");var tab=kind==="habitat"?"habitats":kind==="animal"?"animals":"plants";setNatureTab(tab,false);setTimeout(function(){if(kind==="habitat")openHabitatDetail(id);else if(kind==="animal"){var a=state.animals.find(function(x){return x.id===id});if(a)openAnimalDetail(animalGroupKey(a))}else openPlantDetail(id);notice(message+" · Zurück in Naturgarten.")},90)}\nfunction animalGroupKey(a){return a.taxonId?"taxon:"+a.taxonId:"group:"+String(a.name||"").trim().toLowerCase()+"|"+String(a.group||"other")}\n'''
s=s.replace(insert,flow+insert,1)

# Replace placement branches only, leave center/zone behavior untouched.
old='''if(state.placePlantId){var p=state.plants.find(function(x){return x.id===state.placePlantId});if(p){p.lat=e.latlng.lat;p.lon=e.latlng.lng;state.placePlantId=null;show("mapModeHint",false);save();renderAll();notice("Pflanze auf der Karte positioniert.")}}else if(state.placeHabitatId){var h=state.habitats.find(function(x){return x.id===state.placeHabitatId});if(h){h.lat=e.latlng.lat;h.lon=e.latlng.lng;state.placeHabitatId=null;show("mapModeHint",false);save();renderAll();notice("Lebensraum auf der Karte positioniert.")}}else if(state.placeAnimalId){var a=state.animals.find(function(x){return x.id===state.placeAnimalId});if(a){a.lat=e.latlng.lat;a.lon=e.latlng.lng;state.placeAnimalId=null;show("mapModeHint",false);save();renderAll();notice("Beobachtungsort gespeichert.")}}'''
new='''if(state.placePlantId){var p=state.plants.find(function(x){return x.id===state.placePlantId});if(p){var id=p.id;p.lat=e.latlng.lat;p.lon=e.latlng.lng;state.placePlantId=null;show("mapModeHint",false);save();renderAll();finishNaturePlacement("plant",id,"Pflanze auf der Karte positioniert")}}else if(state.placeHabitatId){var h=state.habitats.find(function(x){return x.id===state.placeHabitatId});if(h){var hid=h.id;h.lat=e.latlng.lat;h.lon=e.latlng.lng;state.placeHabitatId=null;show("mapModeHint",false);save();renderAll();finishNaturePlacement("habitat",hid,"Lebensraum auf der Karte positioniert")}}else if(state.placeAnimalId){var a=state.animals.find(function(x){return x.id===state.placeAnimalId});if(a){var aid=a.id;a.lat=e.latlng.lat;a.lon=e.latlng.lng;state.placeAnimalId=null;show("mapModeHint",false);save();renderAll();finishNaturePlacement("animal",aid,"Beobachtungsort gespeichert")}}'''
one(old,new,'map placement completion flow')

# Trigger existing-record photo backfill after startup and after cloud payload application.
one('renderAll();syncBootstrap();if(state.plz)refreshWeather(false);','renderAll();syncBootstrap();setTimeout(backfillPlantReferencePhotos,1400);if(state.plz)refreshWeather(false);','startup reference photo backfill')
one('syncState.applying=false;renderAll();if(state.plz)refreshWeather(false)}','syncState.applying=false;renderAll();plantRefBackfillDone=false;setTimeout(backfillPlantReferencePhotos,500);if(state.plz)refreshWeather(false)}','cloud reference photo backfill')

assert s!=orig
for marker in ['function plantPhotoInfo','Referenz · iNaturalist','refPhoto:rp.medium_url','function backfillPlantReferencePhotos','function finishNaturePlacement','Zurück in Naturgarten']:
    assert marker in s, marker
p.write_text(s,encoding='utf-8')
print('patched',len(orig),'->',len(s))
