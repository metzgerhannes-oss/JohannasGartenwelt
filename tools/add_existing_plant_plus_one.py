from pathlib import Path

path = Path('index.html')
s = path.read_text(encoding='utf-8')


def once(old, new, label):
    global s
    n = s.count(old)
    if n != 1:
        raise SystemExit(f'{label}: expected 1 occurrence, found {n}')
    s = s.replace(old, new, 1)

# Card/list controls.
once(
    '.plant-quantity-badge{position:absolute;right:8px;bottom:8px;z-index:4;min-width:28px;height:28px;padding:0 7px;border-radius:999px;display:grid;place-items:center;background:rgba(255,253,249,.95);border:1px solid rgba(63,95,67,.35);box-shadow:0 3px 10px rgba(54,49,44,.13);font-size:11px;font-weight:900;color:var(--forest-dark);backdrop-filter:blur(4px)}',
    '.plant-quantity-badge{position:absolute;right:8px;bottom:8px;z-index:4;min-width:28px;height:28px;padding:0 7px;border-radius:999px;display:grid;place-items:center;background:rgba(255,253,249,.95);border:1px solid rgba(63,95,67,.35);box-shadow:0 3px 10px rgba(54,49,44,.13);font-size:11px;font-weight:900;color:var(--forest-dark);backdrop-filter:blur(4px)}\n.plant-add-one{position:absolute;right:8px;bottom:42px;z-index:5;min-width:38px;height:30px;padding:0 9px;border-radius:999px;border:1px solid rgba(255,255,255,.86);background:rgba(63,95,67,.94);color:#fff;box-shadow:0 3px 10px rgba(54,49,44,.18);font-size:12px;font-weight:900;display:grid;place-items:center}.plant-add-one:active{transform:scale(.96)}\n.plant-add-one-list{min-width:36px;height:28px;padding:0 8px;border-radius:999px;border:1px solid #d8e3d2;background:#eef5e8;color:var(--forest-dark);font-size:11px;font-weight:900}.plant-list-actions{display:grid;justify-items:end;gap:4px}',
    'plus-one css'
)

# Placement state for adding exactly one additional specimen without touching existing positions.
once(
    'placePlantId:null,placePlantDraftPositions:[],placeHabitatId:null',
    'placePlantId:null,placePlantDraftPositions:[],placePlantAddId:null,placeHabitatId:null',
    'state add-one id'
)
once(
    'function placementActive(){return !!(state.placePlantId||state.placeHabitatId||state.placeAnimalId)}',
    'function placementActive(){return !!(state.placePlantId||state.placePlantAddId||state.placeHabitatId||state.placeAnimalId)}',
    'placement active'
)

# Add +1 directly to collection cards.
once(
    '+(Number(p.quantity||1)>1?\'<span class="plant-quantity-badge">×\'+Number(p.quantity||1)+\'</span>\':\'\')+\'</div><button class="collection-card-main plantOpen"',
    '+(Number(p.quantity||1)>1?\'<span class="plant-quantity-badge">×\'+Number(p.quantity||1)+\'</span>\':\'\')+\'<button class="plant-add-one" data-id="\'+p.id+\'" type="button" aria-label="Eine weitere Pflanze dieser Art hinzufügen">+1</button></div><button class="collection-card-main plantOpen"',
    'collection plus-one button'
)

# Add +1 to list view too.
once(
    '<div><div class="list-eco">🐝 \'+e.score+\'</div><button class="favorite-plant ',
    '<div class="plant-list-actions"><div class="list-eco">🐝 \'+e.score+\'</div><button class="plant-add-one-list" data-id="\'+p.id+\'" type="button" aria-label="Eine weitere Pflanze dieser Art hinzufügen">+1</button><button class="favorite-plant ',
    'list plus-one button'
)

# Bind the new controls.
once(
    'function bindPlantCollectionEvents(){document.querySelectorAll(".plantOpen").forEach(function(b){b.addEventListener("click",function(){openPlantDetail(b.dataset.id)})});document.querySelectorAll(".favorite-plant").forEach(function(b){b.addEventListener("click",function(e){e.preventDefault();e.stopPropagation();toggleFavorite(b.dataset.id)})})}',
    'function bindPlantCollectionEvents(){document.querySelectorAll(".plantOpen").forEach(function(b){b.addEventListener("click",function(){openPlantDetail(b.dataset.id)})});document.querySelectorAll(".favorite-plant").forEach(function(b){b.addEventListener("click",function(e){e.preventDefault();e.stopPropagation();toggleFavorite(b.dataset.id)})});document.querySelectorAll(".plant-add-one,.plant-add-one-list").forEach(function(b){b.addEventListener("click",function(e){e.preventDefault();e.stopPropagation();beginAddPlantInstance(b.dataset.id)})})}',
    'bind plus-one buttons'
)

# Show quantity and +1 in plant details as well.
once(
    '<div class="detail-kv"><span>Größe</span><b>\'+esc(sizeLabel(p.size))+\'</b></div><div class="detail-kv"><span>Standort</span>',
    '<div class="detail-kv"><span>Größe</span><b>\'+esc(sizeLabel(p.size))+\'</b></div><div class="detail-kv"><span>Anzahl</span><b>\'+Math.max(1,Number(p.quantity||1))+\'</b></div><div class="detail-kv"><span>Standort</span>',
    'detail quantity'
)
once(
    '<button class="btn secondary detailPlace" data-id="\'+p.id+\'" type="button">\'+(p.lat?\'Position ändern\':\'Auf Karte setzen\')+\'</button>',
    '<button class="btn secondary detailAddOne" data-id="\'+p.id+\'" type="button">+1 Pflanze</button><button class="btn secondary detailPlace" data-id="\'+p.id+\'" type="button">\'+(p.lat?\'Position ändern\':\'Auf Karte setzen\')+\'</button>',
    'detail add-one action'
)
once(
    'document.querySelectorAll(".detailPlace").forEach(function(b){b.addEventListener("click",function(){closePlantDetail();beginPlacePlant(b.dataset.id)})});',
    'document.querySelectorAll(".detailAddOne").forEach(function(b){b.addEventListener("click",function(){closePlantDetail();beginAddPlantInstance(b.dataset.id)})});document.querySelectorAll(".detailPlace").forEach(function(b){b.addEventListener("click",function(){closePlantDetail();beginPlacePlant(b.dataset.id)})});',
    'detail add-one binding'
)

# New placement mode: one click adds exactly one specimen and preserves all old mapped positions.
once(
    'function beginPlacePlant(id){var p=state.plants.find(function(x){return x.id===id});if(!p)return;state.placePlantId=id;state.placePlantDraftPositions=[];state.placeHabitatId=null;state.placeAnimalId=null;state.setCenterMode=false;switchView("map");setTimeout(function(){setMapEditing(true);var q=Math.max(1,Number(p.quantity||1));el("mapModeHint").textContent=q>1?\'Position 1 von \'+q+\' für „\'+p.name+\'“ setzen. Vorhandene Pflanzen und Bereiche sind währenddessen ausgeblendet.\':\'Auf das Luftbild tippen, um „\'+p.name+\'“ zu positionieren. Vorhandene Pflanzen und Bereiche sind währenddessen ausgeblendet.\';show("mapModeHint",true);renderMap()},90)}',
    'function beginAddPlantInstance(id){var p=state.plants.find(function(x){return x.id===id});if(!p)return;var q=Math.max(1,Number(p.quantity||1));if(q>=99){notice("Maximal 99 Pflanzen pro Karte möglich.");return}state.placePlantAddId=id;state.placePlantId=null;state.placePlantDraftPositions=[];state.placeHabitatId=null;state.placeAnimalId=null;state.setCenterMode=false;switchView("map");setTimeout(function(){setMapEditing(true);el("mapModeHint").textContent=\'Standort für eine weitere „\'+p.name+\'“ setzen. Vorhandene Pflanzen und Bereiche sind währenddessen ausgeblendet.\';show("mapModeHint",true);renderMap()},90)}\nfunction beginPlacePlant(id){var p=state.plants.find(function(x){return x.id===id});if(!p)return;state.placePlantId=id;state.placePlantAddId=null;state.placePlantDraftPositions=[];state.placeHabitatId=null;state.placeAnimalId=null;state.setCenterMode=false;switchView("map");setTimeout(function(){setMapEditing(true);var q=Math.max(1,Number(p.quantity||1));el("mapModeHint").textContent=q>1?\'Position 1 von \'+q+\' für „\'+p.name+\'“ setzen. Vorhandene Pflanzen und Bereiche sind währenddessen ausgeblendet.\':\'Auf das Luftbild tippen, um „\'+p.name+\'“ zu positionieren. Vorhandene Pflanzen und Bereiche sind währenddessen ausgeblendet.\';show("mapModeHint",true);renderMap()},90)}',
    'begin add-one placement'
)

# Map click: add one location and then increase quantity by exactly one.
once(
    'return}if(state.placePlantId){var p=state.plants.find(function(x){return x.id===state.placePlantId});',
    'return}if(state.placePlantAddId){var ap=state.plants.find(function(x){return x.id===state.placePlantAddId});if(ap){var aq=Math.max(1,Number(ap.quantity||1));if(aq>=99){state.placePlantAddId=null;show("mapModeHint",false);renderMap();notice("Maximal 99 Pflanzen pro Karte möglich.");return}var aid=ap.id,apos=plantPositions(ap);apos.push({lat:e.latlng.lat,lon:e.latlng.lng});ap.quantity=aq+1;ap.positions=apos;syncPlantLegacyPosition(ap);state.placePlantAddId=null;show("mapModeHint",false);save();renderAll();finishNaturePlacement("plant",aid,"Weitere Pflanze hinzugefügt · jetzt "+ap.quantity+"×")}return}if(state.placePlantId){var p=state.plants.find(function(x){return x.id===state.placePlantId});',
    'map click add-one'
)

# Other placement modes must cancel the add-one mode cleanly.
once(
    'function beginPlaceHabitat(id){var h=state.habitats.find(function(x){return x.id===id});if(!h)return;state.placeHabitatId=id;state.placePlantId=null;state.placeAnimalId=null;',
    'function beginPlaceHabitat(id){var h=state.habitats.find(function(x){return x.id===id});if(!h)return;state.placeHabitatId=id;state.placePlantId=null;state.placePlantAddId=null;state.placeAnimalId=null;',
    'habitat clears add-one'
)
once(
    'function beginPlaceAnimal(id){var a=state.animals.find(function(x){return x.id===id});if(!a)return;state.placeAnimalId=id;state.placePlantId=null;state.placeHabitatId=null;',
    'function beginPlaceAnimal(id){var a=state.animals.find(function(x){return x.id===id});if(!a)return;state.placeAnimalId=id;state.placePlantId=null;state.placePlantAddId=null;state.placeHabitatId=null;',
    'animal clears add-one'
)
once(
    'if(state.placePlantId===id)state.placePlantId=null;state.placePlantDraftPositions=[];',
    'if(state.placePlantId===id)state.placePlantId=null;if(state.placePlantAddId===id)state.placePlantAddId=null;state.placePlantDraftPositions=[];',
    'remove map clears add-one'
)
once(
    'el("cancelPlacementBtn").addEventListener("click",function(){state.placePlantId=null;state.placePlantDraftPositions=[];state.placeHabitatId=null;',
    'el("cancelPlacementBtn").addEventListener("click",function(){state.placePlantId=null;state.placePlantAddId=null;state.placePlantDraftPositions=[];state.placeHabitatId=null;',
    'cancel add-one'
)
once(
    'el("drawZoneBtn").addEventListener("click",function(){initMap();if(!state.mapReady)return;setMapEditing(true);state.placePlantId=null;state.setCenterMode=false;',
    'el("drawZoneBtn").addEventListener("click",function(){initMap();if(!state.mapReady)return;setMapEditing(true);state.placePlantId=null;state.placePlantAddId=null;state.setCenterMode=false;',
    'zone draw clears add-one'
)

path.write_text(s, encoding='utf-8')
print('add-existing-plant +1 patch applied')
