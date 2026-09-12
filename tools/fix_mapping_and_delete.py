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

# 1) Make mapped state independent from whether the plant happens to sit inside a drawn zone.
one(
"function typeLabel(v){return v===\"pot\"?\"Kübel / Topf\":v===\"raised\"?\"Hochbeet\":v===\"balcony\"?\"Balkonkasten\":v===\"other\"?\"Sonstige Pflanzung\":\"Gartenboden\"}",
"function plantMapStatus(p,z){if(z)return lightLabel(z.light)+\" · auf Karte\";if(p&&p.lat!=null&&p.lon!=null&&Number.isFinite(Number(p.lat))&&Number.isFinite(Number(p.lon)))return \"auf Karte positioniert\";return \"nicht kartiert\"}\nfunction typeLabel(v){return v===\"pot\"?\"Kübel / Topf\":v===\"raised\"?\"Hochbeet\":v===\"balcony\"?\"Balkonkasten\":v===\"other\"?\"Sonstige Pflanzung\":\"Gartenboden\"}",
'map status helper')
one("<div class=\"detail-kv\"><span>Standort</span><b>'+esc(z?lightLabel(z.light):'nicht kartiert')+'</b></div>","<div class=\"detail-kv\"><span>Standort</span><b>'+esc(plantMapStatus(p,z))+'</b></div>",'plant detail map label')

# 2) Explicit destructive actions in all three editors.
one(
'<div class="actions" style="margin-top:14px"><button class="btn" type="submit">Speichern</button><button class="btn secondary" id="saveAndPlaceBtn" type="button">Speichern & auf Karte setzen</button></div>',
'<div class="actions" style="margin-top:14px"><button class="btn" type="submit">Speichern</button><button class="btn secondary" id="saveAndPlaceBtn" type="button">Speichern & auf Karte setzen</button><button class="btn secondary hidden" id="removePlantMapBtn" type="button">Von Karte entfernen</button><button class="btn danger hidden" id="deletePlantBtn" type="button">Pflanze löschen</button></div>',
'plant editor actions')
one(
'<div class="actions" style="margin-top:14px"><button class="btn" type="submit">Speichern</button><button class="btn secondary" id="saveHabitatAndPlaceBtn" type="button">Speichern & auf Karte setzen</button></div>',
'<div class="actions" style="margin-top:14px"><button class="btn" type="submit">Speichern</button><button class="btn secondary" id="saveHabitatAndPlaceBtn" type="button">Speichern & auf Karte setzen</button><button class="btn secondary hidden" id="removeHabitatMapBtn" type="button">Von Karte entfernen</button><button class="btn danger hidden" id="deleteHabitatBtn" type="button">Lebensraum löschen</button></div>',
'habitat editor actions')
one(
'<div class="actions" style="margin-top:14px"><button class="btn" type="submit">Beobachtung speichern</button><button class="btn secondary" id="saveAnimalAndPlaceBtn" type="button">Speichern & auf Karte setzen</button></div>',
'<div class="actions" style="margin-top:14px"><button class="btn" type="submit">Beobachtung speichern</button><button class="btn secondary" id="saveAnimalAndPlaceBtn" type="button">Speichern & auf Karte setzen</button><button class="btn secondary hidden" id="removeAnimalMapBtn" type="button">Von Karte entfernen</button><button class="btn danger hidden" id="deleteAnimalBtn" type="button">Beobachtung löschen</button></div>',
'animal editor actions')

# Show delete/remove-map controls only when editing an existing mapped item.
one('renderPlantDataStatus(state.plantDataMeta);renderPlantEcoPreview();el("plantEditor").scrollIntoView({behavior:"smooth",block:"start"})}',
    'renderPlantDataStatus(state.plantDataMeta);renderPlantEcoPreview();show("deletePlantBtn",!!p);show("removePlantMapBtn",!!(p&&p.lat!=null&&p.lon!=null));el("plantEditor").scrollIntoView({behavior:"smooth",block:"start"})}',
    'plant editor control visibility')
one('show("habitatEditor",true);renderHabitatImpactPreview();el("habitatEditor").scrollIntoView({behavior:"smooth",block:"start"})}',
    'show("habitatEditor",true);show("deleteHabitatBtn",!!h);show("removeHabitatMapBtn",!!(h&&h.lat!=null&&h.lon!=null));renderHabitatImpactPreview();el("habitatEditor").scrollIntoView({behavior:"smooth",block:"start"})}',
    'habitat editor control visibility')
one('show("animalEditor",true);el("animalEditor").scrollIntoView({behavior:"smooth",block:"start"})}',
    'show("animalEditor",true);show("deleteAnimalBtn",!!a);show("removeAnimalMapBtn",!!(a&&a.lat!=null&&a.lon!=null));el("animalEditor").scrollIntoView({behavior:"smooth",block:"start"})}',
    'animal editor control visibility')

# Make existing detail delete actions unmistakable.
s=s.replace('class="btn ghost detailDelete"','class="btn danger detailDelete"')
s=s.replace('class="btn ghost habitatDetailDelete"','class="btn danger habitatDetailDelete"')
s=s.replace('class="btn ghost small animalObsDelete" data-id="'+"'"+'+o.id+"'"+'">×</button>','class="btn danger small animalObsDelete" data-id="'+"'"+'+o.id+"'"+'">Löschen</button>')

# Shared deletion / map-removal helpers.
one(
'function saveHabitat(placeAfter){var h=habitatFromForm(),i=state.habitats.findIndex(function(x){return x.id===h.id});if(i>=0)state.habitats[i]=h;else state.habitats.push(h);if(!save())return;show("habitatEditor",false);renderAll();if(placeAfter)beginPlaceHabitat(h.id)}',
'function saveHabitat(placeAfter){var h=habitatFromForm(),i=state.habitats.findIndex(function(x){return x.id===h.id});if(i>=0)state.habitats[i]=h;else state.habitats.push(h);if(!save())return;show("habitatEditor",false);renderAll();if(placeAfter)beginPlaceHabitat(h.id)}\nfunction deleteHabitatEntry(id){var h=state.habitats.find(function(x){return x.id===id});if(!h)return;if(!confirm("Diesen Lebensraum löschen?"))return;state.habitats=state.habitats.filter(function(x){return x.id!==id});state.animals.forEach(function(a){if(a.linkedHabitatId===id)a.linkedHabitatId=""});if(state.placeHabitatId===id)state.placeHabitatId=null;show("habitatEditor",false);save();renderAll();notice("Lebensraum gelöscht.")}\nfunction removeHabitatFromMap(id){var h=state.habitats.find(function(x){return x.id===id});if(!h)return;h.lat=null;h.lon=null;if(state.placeHabitatId===id)state.placeHabitatId=null;save();renderAll();show("removeHabitatMapBtn",false);notice("Lebensraum von der Karte entfernt.")}',
'habitat delete helpers')
one(
'function saveAnimal(placeAfter){try{var a=animalFromForm(),i=state.animals.findIndex(function(x){return x.id===a.id});if(i>=0)state.animals[i]=a;else state.animals.push(a);if(!save())return;show("animalEditor",false);renderAll();if(placeAfter)beginPlaceAnimal(a.id)}catch(e){globalError(e.message)}}',
'function saveAnimal(placeAfter){try{var a=animalFromForm(),i=state.animals.findIndex(function(x){return x.id===a.id});if(i>=0)state.animals[i]=a;else state.animals.push(a);if(!save())return;show("animalEditor",false);renderAll();if(placeAfter)beginPlaceAnimal(a.id)}catch(e){globalError(e.message)}}\nfunction deleteAnimalObservation(id){var a=state.animals.find(function(x){return x.id===id});if(!a)return;if(!confirm("Diese Beobachtung löschen?"))return;state.animals=state.animals.filter(function(x){return x.id!==id});if(state.placeAnimalId===id)state.placeAnimalId=null;show("animalEditor",false);save();renderAll();notice("Beobachtung gelöscht.")}\nfunction removeAnimalFromMap(id){var a=state.animals.find(function(x){return x.id===id});if(!a)return;a.lat=null;a.lon=null;if(state.placeAnimalId===id)state.placeAnimalId=null;save();renderAll();show("removeAnimalMapBtn",false);notice("Beobachtung von der Karte entfernt.")}',
'animal delete helpers')

# Plant map-removal helper near existing delete/undo behavior.
one(
'function undoDelete(){if(!lastDeletedPlant)return;var x=lastDeletedPlant;state.plants.splice(Math.min(x.index,state.plants.length),0,x.plant);lastDeletedPlant=null;clearTimeout(lastDeletedTimer);show("undoToast",false);save();renderAll();notice("Pflanze wiederhergestellt.")}',
'function undoDelete(){if(!lastDeletedPlant)return;var x=lastDeletedPlant;state.plants.splice(Math.min(x.index,state.plants.length),0,x.plant);lastDeletedPlant=null;clearTimeout(lastDeletedTimer);show("undoToast",false);save();renderAll();notice("Pflanze wiederhergestellt.")}\nfunction removePlantFromMap(id){var p=state.plants.find(function(x){return x.id===id});if(!p)return;p.lat=null;p.lon=null;if(state.placePlantId===id)state.placePlantId=null;save();renderAll();show("removePlantMapBtn",false);notice("Pflanze von der Karte entfernt.")}',
'plant map removal helper')

# Hook editor buttons.
one(
'el("saveAndPlaceBtn").addEventListener("click",function(){savePlant(true)});',
'el("saveAndPlaceBtn").addEventListener("click",function(){savePlant(true)});\nel("deletePlantBtn").addEventListener("click",function(){if(!state.editPlantId)return;var id=state.editPlantId;show("plantEditor",false);deletePlantWithUndo(id)});\nel("removePlantMapBtn").addEventListener("click",function(){if(state.editPlantId)removePlantFromMap(state.editPlantId)});',
'plant editor listeners')
one(
'el("saveHabitatAndPlaceBtn").addEventListener("click",function(){saveHabitat(true)});',
'el("saveHabitatAndPlaceBtn").addEventListener("click",function(){saveHabitat(true)});\nel("deleteHabitatBtn").addEventListener("click",function(){if(state.editHabitatId)deleteHabitatEntry(state.editHabitatId)});\nel("removeHabitatMapBtn").addEventListener("click",function(){if(state.editHabitatId)removeHabitatFromMap(state.editHabitatId)});',
'habitat editor listeners')
one(
'el("saveAnimalAndPlaceBtn").addEventListener("click",function(){saveAnimal(true)});',
'el("saveAnimalAndPlaceBtn").addEventListener("click",function(){saveAnimal(true)});\nel("deleteAnimalBtn").addEventListener("click",function(){if(state.editAnimalId)deleteAnimalObservation(state.editAnimalId)});\nel("removeAnimalMapBtn").addEventListener("click",function(){if(state.editAnimalId)removeAnimalFromMap(state.editAnimalId)});',
'animal editor listeners')

# Reuse shared deletion helpers from details so behavior stays consistent.
s=s.replace('if(confirm("Diesen Lebensraum löschen?")){closePlantDetail();state.habitats=state.habitats.filter(function(x){return x.id!==h.id});save();renderAll()}', 'closePlantDetail();deleteHabitatEntry(h.id)')
s=s.replace('if(confirm("Diese Beobachtung löschen?")){state.animals=state.animals.filter(function(x){return x.id!==b.dataset.id});save();closePlantDetail();renderAll()}', 'closePlantDetail();deleteAnimalObservation(b.dataset.id)')

assert s!=orig
for marker in ['plantMapStatus(p,z)','id="deletePlantBtn"','id="deleteHabitatBtn"','id="deleteAnimalBtn"','id="removePlantMapBtn"','function deleteHabitatEntry','function deleteAnimalObservation']:
    assert marker in s, marker
p.write_text(s,encoding='utf-8')
print('patched',len(orig),'->',len(s))
