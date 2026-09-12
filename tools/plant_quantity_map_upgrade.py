from pathlib import Path
import re

path=Path('index.html')
s=path.read_text(encoding='utf-8')

def once(old,new,label):
    global s
    n=s.count(old)
    if n!=1:
        raise SystemExit(f'{label}: expected 1 occurrence, found {n}')
    s=s.replace(old,new,1)

def between(start,end,new,label):
    global s
    a=s.find(start)
    if a<0:
        raise SystemExit(f'{label}: start marker not found')
    b=s.find(end,a)
    if b<0:
        raise SystemExit(f'{label}: end marker not found')
    s=s[:a]+new+s[b:]

once(
    '.plant-marker.bad{border-color:#c27b6d}.plant-marker.warn{border-color:#d2a34b}.plant-marker.ok{border-color:var(--forest)}',
    '.plant-marker.bad{border-color:#c27b6d}.plant-marker.warn{border-color:#d2a34b}.plant-marker.ok{border-color:var(--forest)}\n'
    '.plant-quantity-badge{position:absolute;right:8px;bottom:8px;z-index:4;min-width:28px;height:28px;padding:0 7px;border-radius:999px;display:grid;place-items:center;background:rgba(255,253,249,.95);border:1px solid rgba(63,95,67,.35);box-shadow:0 3px 10px rgba(54,49,44,.13);font-size:11px;font-weight:900;color:var(--forest-dark);backdrop-filter:blur(4px)}\n'
    '.plant-placement-marker{font-size:11px;font-weight:900;color:var(--forest-dark);border-color:var(--gold);background:#fff8df}',
    'quantity badge CSS')

once(
    '<div class="field"><label for="plantArea">Gartenbereich</label><select id="plantArea"></select><div class="area-select-note">Einheitliche Gartenbereiche für Pflanzen, Lebensräume und Tierbeobachtungen.</div></div>',
    '<div class="field"><label for="plantArea">Gartenbereich</label><select id="plantArea"></select><div class="area-select-note">Einheitliche Gartenbereiche für Pflanzen, Lebensräume und Tierbeobachtungen.</div></div>\n'
    '        <div class="field"><label for="plantQuantity">Anzahl</label><input id="plantQuantity" type="number" inputmode="numeric" min="1" max="99" step="1" value="1"><div class="area-select-note">Mehrere gleiche Pflanzen werden als eine Pflanzenkarte geführt.</div></div>',
    'plant quantity field')

once(
    '<span id="mapModeHint" class="maphint hidden"></span>',
    '<span id="mapModeHint" class="maphint hidden"></span><button class="btn ghost hidden" id="cancelPlacementBtn" type="button">Setzen abbrechen</button>',
    'placement cancel button')

once('placePlantId:null,placeHabitatId:null,placeAnimalId:null,setCenterMode:false,',
     'placePlantId:null,placePlantDraftPositions:[],placeHabitatId:null,placeAnimalId:null,setCenterMode:false,',
     'placement draft state')

between('function normalizePlantData(p){','\nfunction plantPhotoInfo', '''function normalizePlantData(p){
 p=p||{};
 if(typeof p.favorite!=="boolean")p.favorite=false;
 if(!Array.isArray(p.bloomMonths))p.bloomMonths=[];
 if(!p.ecoNative)p.ecoNative="auto";
 if(!p.ecoFlowerAccess)p.ecoFlowerAccess="auto";
 if(!p.created)p.created=isoToday();
 if(!p.family)p.family="";
 var q=parseInt(p.quantity,10);p.quantity=Number.isFinite(q)&&q>0?Math.min(99,q):1;
 var pos=Array.isArray(p.positions)?p.positions:[];
 pos=pos.map(function(x){return{lat:Number(x&&x.lat),lon:Number(x&&x.lon)}}).filter(function(x){return Number.isFinite(x.lat)&&Number.isFinite(x.lon)});
 if(!pos.length&&p.lat!=null&&p.lon!=null&&Number.isFinite(Number(p.lat))&&Number.isFinite(Number(p.lon)))pos=[{lat:Number(p.lat),lon:Number(p.lon)}];
 if(pos.length>p.quantity)pos=pos.slice(0,p.quantity);
 p.positions=pos;
 syncPlantLegacyPosition(p);
 return p
}
function plantPositions(p){return Array.isArray(p&&p.positions)?p.positions.filter(function(x){return x&&Number.isFinite(Number(x.lat))&&Number.isFinite(Number(x.lon))}).map(function(x){return{lat:Number(x.lat),lon:Number(x.lon)}}):((p&&p.lat!=null&&p.lon!=null&&Number.isFinite(Number(p.lat))&&Number.isFinite(Number(p.lon)))?[{lat:Number(p.lat),lon:Number(p.lon)}]:[])}
function syncPlantLegacyPosition(p){var pos=plantPositions(p);if(pos.length){p.lat=pos[0].lat;p.lon=pos[0].lon}else{p.lat=null;p.lon=null}}
function placementActive(){return !!(state.placePlantId||state.placeHabitatId||state.placeAnimalId)}''', 'normalize plant quantity and positions')

between('function plantMapStatus(p,z){','\nfunction typeLabel', 'function plantMapStatus(p,z){var n=plantPositions(p).length,q=Math.max(1,Number(p&&p.quantity||1));if(n){if(q>1)return n>=q?q+"× auf Karte":n+" von "+q+" auf Karte";return z?lightLabel(z.light)+" · auf Karte":"auf Karte positioniert"}return"nicht kartiert"}', 'plant map status')

between('function currentZoneForPlant(p){','\nfunction pointInPolygon', 'function currentZoneForPlant(p){var pos=plantPositions(p);if(!pos.length)return null;var first=pos[0];for(var i=state.zones.length-1;i>=0;i--){if(pointInPolygon(first.lat,first.lon,state.zones[i].points))return state.zones[i]}return null}', 'current zone compatibility')

old_badge = '''<span class="insect-badge '+ecoBadgeClass(e.score)+'">🐝 '+e.score+'</span>'''
new_badge = old_badge + ''''+(Number(p.quantity||1)>1?'<span class="plant-quantity-badge">×'+Number(p.quantity||1)+'</span>':'')+''' 
new_badge = new_badge[:-2]
once(old_badge,new_badge,'collection quantity badge')

once('el("plantSize").value="medium";el("plantId").value="";',
     'el("plantSize").value="medium";el("plantQuantity").value="1";el("plantId").value="";',
     'reset quantity')
once('el("plantSize").value=p.size||"medium";el("plantBirthYear").value=p.birthYear||"";',
     'el("plantSize").value=p.size||"medium";el("plantQuantity").value=String(p.quantity||1);el("plantBirthYear").value=p.birthYear||"";',
     'edit quantity')

once('var ar=areaSelection("plantArea");return normalizePlantData({',
     'var ar=areaSelection("plantArea"),qty=Math.max(1,Math.min(99,parseInt(el("plantQuantity").value,10)||1));return normalizePlantData({',
     'form quantity parse')
once('areaId:ar.id,area:ar.name,type:el("plantType").value||"bed",',
     'areaId:ar.id,area:ar.name,quantity:qty,type:el("plantType").value||"bed",',
     'form quantity persistence')
once('photo:state.photoData||"",lat:old?old.lat:null,lon:old?old.lon:null,',
     'photo:state.photoData||"",positions:old?plantPositions(old).slice(0,qty):[],lat:old?old.lat:null,lon:old?old.lon:null,',
     'form positions persistence')

between('function removePlantFromMap(id){','\nfunction taskSnoozed', 'function removePlantFromMap(id){var p=state.plants.find(function(x){return x.id===id});if(!p)return;p.positions=[];p.lat=null;p.lon=null;if(state.placePlantId===id)state.placePlantId=null;state.placePlantDraftPositions=[];save();renderAll();show("removePlantMapBtn",false);notice("Pflanze vollständig von der Karte entfernt.")}', 'remove all plant positions')

between('function renderMapMode(){','\nfunction setMapEditing', 'function renderMapMode(){var edit=!!state.mapEditMode,has=!!(state.settings&&state.settings.mapView),placing=placementActive();show("mapEditTools",edit&&!placing);show("saveMapViewBtn",edit&&!placing);show("mapEditToggle",!placing);show("cancelPlacementBtn",placing);show("mapSetupHint",edit&&!has&&!placing);var b=el("mapEditToggle"),st=el("mapViewStatus");if(b)b.textContent=edit?(has?"Bearbeitung beenden":"Ausschnitt festlegen"):"Karte bearbeiten";if(st){st.className="map-status"+(edit?" editing":"");st.textContent=placing?"Standort setzen":(edit?(has?"Bearbeitung aktiv":"Ersteinrichtung"):"Fester Gartenausschnitt")}}', 'focused map controls')

between('function beginPlacePlant(id){','\nfunction zoneStyle', '''function beginPlacePlant(id){var p=state.plants.find(function(x){return x.id===id});if(!p)return;state.placePlantId=id;state.placePlantDraftPositions=[];state.placeHabitatId=null;state.placeAnimalId=null;state.setCenterMode=false;switchView("map");setTimeout(function(){setMapEditing(true);var q=Math.max(1,Number(p.quantity||1));el("mapModeHint").textContent=q>1?'Position 1 von '+q+' für „'+p.name+'“ setzen. Vorhandene Pflanzen und Bereiche sind währenddessen ausgeblendet.':'Auf das Luftbild tippen, um „'+p.name+'“ zu positionieren. Vorhandene Pflanzen und Bereiche sind währenddessen ausgeblendet.';show("mapModeHint",true);renderMap()},90)}''', 'begin multi placement')

old_click='''if(state.placePlantId){var p=state.plants.find(function(x){return x.id===state.placePlantId});if(p){var id=p.id;p.lat=e.latlng.lat;p.lon=e.latlng.lng;state.placePlantId=null;show("mapModeHint",false);save();renderAll();finishNaturePlacement("plant",id,"Pflanze auf der Karte positioniert")}}else if(state.placeHabitatId)'''
new_click='''if(state.placePlantId){var p=state.plants.find(function(x){return x.id===state.placePlantId});if(p){var q=Math.max(1,Number(p.quantity||1));state.placePlantDraftPositions=Array.isArray(state.placePlantDraftPositions)?state.placePlantDraftPositions:[];state.placePlantDraftPositions.push({lat:e.latlng.lat,lon:e.latlng.lng});if(state.placePlantDraftPositions.length>=q){var id=p.id;p.positions=state.placePlantDraftPositions.slice(0,q);syncPlantLegacyPosition(p);state.placePlantId=null;state.placePlantDraftPositions=[];show("mapModeHint",false);save();renderAll();finishNaturePlacement("plant",id,q>1?q+" Pflanzen auf der Karte positioniert":"Pflanze auf der Karte positioniert")}else{el("mapModeHint").textContent="Position "+(state.placePlantDraftPositions.length+1)+" von "+q+" setzen.";renderMap()}}}else if(state.placeHabitatId)'''
once(old_click,new_click,'sequential plant placement click')

between('function renderMap(){','\nfunction renderZoneList', '''function renderMap(){
 if(!state.mapReady)return;
 state.zoneGroup.clearLayers();state.markerGroup.clearLayers();
 var placing=placementActive();
 if(placing){
   if(state.placePlantId){
     (state.placePlantDraftPositions||[]).forEach(function(pos,i){var icon=L.divIcon({className:"",html:'<div class="plant-marker ok plant-placement-marker">'+(i+1)+'</div>',iconSize:[26,26],iconAnchor:[13,13]});L.marker([pos.lat,pos.lon],{icon:icon,interactive:false}).addTo(state.markerGroup)});
   }
   renderZoneList();renderMapMode();return;
 }
 if(state.gardenCenter&&state.mapEditMode){L.circleMarker([state.gardenCenter.lat,state.gardenCenter.lon],{radius:6,color:"#17324d",weight:2,fillColor:"#fff",fillOpacity:1,interactive:state.mapEditMode}).addTo(state.markerGroup).bindTooltip("Gartenmitte")}
 state.zones.forEach(function(z){var poly=L.polygon(z.points.map(function(p){return[p.lat,p.lon]}),zoneStyle(z)).addTo(state.zoneGroup);poly._zoneId=z.id;poly.bindPopup('<b>'+esc(z.name||lightLabel(z.light))+'</b><br>'+lightLabel(z.light)+' · '+rainLabel(z.rain)+' · '+soilLabel(z.soil))});
 state.plants.forEach(function(p){var wa=waterAssessment(p),positions=plantPositions(p),qty=Math.max(1,Number(p.quantity||1));positions.forEach(function(pos,idx){var icon=L.divIcon({className:"",html:'<div class="plant-marker '+wa.level+'">🌿</div>',iconSize:[26,26],iconAnchor:[13,13]});var m=L.marker([pos.lat,pos.lon],{icon:icon,draggable:!!state.mapEditMode}).addTo(state.markerGroup);m.bindPopup('<b>'+esc(p.name)+'</b>'+(qty>1?'<br>Exemplar '+(idx+1)+' von '+qty:'')+'<br>'+esc(wa.title)+(currentZoneForPlant(p)?'<br>'+lightLabel(currentZoneForPlant(p).light):''));if(state.mapEditMode)m.on("dragend",function(){var q=m.getLatLng();p.positions=plantPositions(p);p.positions[idx]={lat:q.lat,lon:q.lng};syncPlantLegacyPosition(p);save();renderAll()})})});
 state.habitats.filter(function(h){return h.lat&&h.lon}).forEach(function(h){var d=habitatLibraryItem(h.type),icon=L.divIcon({className:"",html:'<div class="map-nature-marker">'+d.icon+'</div>',iconSize:[28,28],iconAnchor:[14,14]}),m=L.marker([h.lat,h.lon],{icon:icon,draggable:!!state.mapEditMode}).addTo(state.markerGroup);m.bindPopup('<b>'+esc(d.title)+'</b><br>'+esc(habitatStatusLabel(h.status)));if(state.mapEditMode)m.on("dragend",function(){var q=m.getLatLng();h.lat=q.lat;h.lon=q.lng;save();renderAll()})});
 state.animals.filter(function(a){return a.lat&&a.lon}).forEach(function(a){var icon=L.divIcon({className:"",html:'<div class="map-nature-marker map-animal-marker">'+animalGroupIcon(a.group)+'</div>',iconSize:[28,28],iconAnchor:[14,14]}),m=L.marker([a.lat,a.lon],{icon:icon,draggable:!!state.mapEditMode}).addTo(state.markerGroup);m.bindPopup('<b>'+esc(a.name)+'</b><br>beobachtet '+esc(a.date?fmtDate(a.date):''));if(state.mapEditMode)m.on("dragend",function(){var q=m.getLatLng();a.lat=q.lat;a.lon=q.lng;save();renderAll()})});
 renderZoneList();renderMapMode()
}''', 'clean placement render and multi markers')

once('function renderZoneList(){var edit=!!state.mapEditMode;',
     'function renderZoneList(){if(placementActive()){el("zoneList").innerHTML="";return}var edit=!!state.mapEditMode;',
     'hide zone list while placing')

once('state.plants.forEach(function(p){if(p.lat&&p.lon)pts.push([p.lat,p.lon])});',
     'state.plants.forEach(function(p){plantPositions(p).forEach(function(pos){pts.push([pos.lat,pos.lon])})});',
     'fit all plant positions')

once('el("mapEditToggle").addEventListener("click",toggleMapEditing);',
     'el("mapEditToggle").addEventListener("click",toggleMapEditing);\n'
     'el("cancelPlacementBtn").addEventListener("click",function(){state.placePlantId=null;state.placePlantDraftPositions=[];state.placeHabitatId=null;state.placeAnimalId=null;show("mapModeHint",false);if(state.settings.mapView){setMapEditing(false);applySavedMapView()}else setMapEditing(true);renderMap();notice("Standort setzen abgebrochen.")});',
     'placement cancel handler')

path.write_text(s,encoding='utf-8')
print('quantity and placement upgrade applied')
