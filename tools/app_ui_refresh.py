from pathlib import Path

path = Path('index.html')
s = path.read_text(encoding='utf-8')


def replace_once(old, new, label):
    global s
    if old not in s:
        raise SystemExit(f'pattern missing: {label}')
    s = s.replace(old, new, 1)


def replace_line(prefix, new, label=None):
    global s
    lines = s.splitlines()
    hits = [i for i, line in enumerate(lines) if line.startswith(prefix)]
    if len(hits) != 1:
        raise SystemExit(f'expected one line for {label or prefix}, found {len(hits)}')
    lines[hits[0]:hits[0]+1] = new.splitlines()
    s = '\n'.join(lines) + ('\n' if s.endswith('\n') else '')


# ---------------------------------------------------------------------------
# 1. Seasonal visual system, map lock, compact plant UI and micro-interactions
# ---------------------------------------------------------------------------
css_marker = '@media(max-width:850px)'
if '/* JGW UX V2 */' not in s:
    css = r'''
/* JGW UX V2 */
body[data-season="spring"]{--forest:#567f5a;--forest-dark:#3b6242;--sage:#9bbb86;--rose:#dfaeb8;--blush:#f7e3e8;--cream:#fbf7ef;--paper:#fffdf9;--petal:#faeef2;--gold:#d3b06d;--line:#e8dccf}
body[data-season="summer"]{--forest:#4f7a4e;--forest-dark:#365a39;--sage:#91ad67;--rose:#e1b285;--blush:#f8ead7;--cream:#fff8e9;--paper:#fffdf7;--petal:#fff0dc;--gold:#d3a447;--line:#e9dcc5}
body[data-season="autumn"]{--forest:#68734e;--forest-dark:#4d5939;--sage:#9b9564;--rose:#bf8067;--blush:#f1dfd4;--cream:#faf2e6;--paper:#fffaf4;--petal:#f5e5d8;--gold:#bc8747;--line:#e4d3bf}
body[data-season="winter"]{--forest:#607873;--forest-dark:#405d5b;--sage:#8fa7a4;--rose:#b8aab7;--blush:#ece8ed;--cream:#f4f6f4;--paper:#fbfcfb;--petal:#eef1f3;--gold:#a6a88f;--line:#d8e0de}
body[data-season="spring"] .head{background:linear-gradient(135deg,rgba(249,236,241,.98),rgba(238,248,235,.98))}
body[data-season="summer"] .head{background:linear-gradient(135deg,rgba(255,246,218,.98),rgba(239,248,225,.98))}
body[data-season="autumn"] .head{background:linear-gradient(135deg,rgba(247,230,216,.98),rgba(239,240,222,.98))}
body[data-season="winter"] .head{background:linear-gradient(135deg,rgba(239,244,245,.98),rgba(246,242,247,.98))}
body,.head,.box,.tab,.btn,.plantcard,.state-card{transition:background-color .35s ease,border-color .35s ease,color .35s ease,box-shadow .35s ease}
.seasonmark{font-size:22px;line-height:1;filter:saturate(.86);user-select:none}
.quickbtn,.syncmini{height:42px;border-radius:999px;border:1px solid rgba(200,165,106,.38);background:rgba(255,253,249,.92);color:var(--forest-dark);box-shadow:0 4px 14px rgba(109,135,104,.09)}
.quickbtn{width:42px;padding:0;font-size:25px;line-height:1;display:grid;place-items:center;font-weight:400}
.syncmini{padding:0 10px;display:flex;align-items:center;gap:6px;font-size:15px}
.syncmini-dot{width:8px;height:8px;border-radius:50%;background:#b6aea6;box-shadow:0 0 0 3px rgba(182,174,166,.14)}
.syncmini.ok .syncmini-dot{background:var(--forest);box-shadow:0 0 0 3px rgba(86,122,87,.13)}
.syncmini.warn .syncmini-dot{background:#d2a34b;box-shadow:0 0 0 3px rgba(210,163,75,.13)}
.syncmini.bad .syncmini-dot{background:#b16666;box-shadow:0 0 0 3px rgba(177,102,102,.13)}
.plant-search{min-height:40px;width:min(260px,55vw);border:1px solid #ddcfc0;border-radius:12px;padding:8px 11px;background:#fffdf9;color:var(--txt)}
.plant-summary{margin-top:7px;font-size:13px;color:var(--muted);line-height:1.4}
.plant-details{margin-top:9px;border-top:1px solid #f0e7dd;padding-top:8px}
.plant-details summary{font-size:12px}
.map-status{display:inline-flex;align-items:center;gap:6px;border-radius:999px;padding:6px 9px;background:var(--ok);color:var(--forest-dark);font-size:11px;font-weight:800}
.map-status.editing{background:var(--warn)}
.map-edit-note{padding:12px 13px;margin:10px 0;border-radius:14px;background:var(--warn);border:1px solid #ecd8a8;color:#6d5730;font-size:13px;line-height:1.45}
#map.map-locked{cursor:default}
#map.map-locked .leaflet-control-zoom,#map.map-locked .leaflet-control-layers,#map.map-locked .leaflet-draw{display:none!important}
#map.map-editing{outline:3px solid rgba(200,165,106,.18);outline-offset:2px}
.task.task-complete{animation:taskFinish .58s ease forwards;pointer-events:none}
@keyframes taskFinish{0%{transform:scale(1);opacity:1}35%{transform:scale(1.012)}100%{transform:translateY(-5px) scale(.985);opacity:0}}
.celebration{position:fixed;inset:0;z-index:9000;display:grid;place-items:center;pointer-events:none}
.celebration.hidden{display:none!important}
.celebrate-card{position:relative;min-width:150px;text-align:center;padding:18px 22px;border-radius:24px;background:rgba(255,253,249,.94);border:1px solid var(--line);box-shadow:0 18px 50px rgba(70,64,57,.20);animation:celebratePop .9s ease forwards}
.celebrate-check{width:52px;height:52px;border-radius:50%;margin:0 auto 7px;display:grid;place-items:center;background:linear-gradient(135deg,var(--forest),var(--sage));color:white;font-size:30px;font-weight:800;box-shadow:0 8px 20px rgba(86,122,87,.22)}
.celebrate-text{font-size:18px;font-weight:700;color:var(--forest-dark)}
.particle{position:absolute;left:50%;top:45%;font-size:18px;opacity:0;animation:particleFly .85s ease-out forwards;transform:translate(-50%,-50%)}
@keyframes celebratePop{0%{opacity:0;transform:scale(.72)}18%{opacity:1;transform:scale(1.05)}68%{opacity:1;transform:scale(1)}100%{opacity:0;transform:scale(.96)}}
@keyframes particleFly{0%{opacity:0;transform:translate(-50%,-50%) scale(.5) rotate(0)}18%{opacity:1}100%{opacity:0;transform:translate(calc(-50% + var(--dx)),calc(-50% + var(--dy))) scale(1.05) rotate(var(--rot))}}
.undo-toast{position:fixed;left:50%;bottom:max(18px,env(safe-area-inset-bottom));transform:translateX(-50%);z-index:8500;display:flex;align-items:center;gap:10px;background:#4e443a;color:white;border-radius:999px;padding:9px 11px 9px 15px;box-shadow:0 12px 30px rgba(40,35,31,.24);font-size:13px;max-width:calc(100vw - 24px)}
.undo-toast.hidden{display:none!important}.undo-toast button{border:0;border-radius:999px;padding:7px 10px;background:white;color:var(--forest-dark);font-weight:800}
.appearance-row{display:grid;grid-template-columns:1fr auto;align-items:center;gap:12px;margin-top:10px}.appearance-row select{min-width:150px;border:1px solid #ddcfc0;border-radius:11px;padding:9px;background:#fffdf9;color:var(--txt)}
.toggle-row{display:flex;align-items:center;gap:9px;margin-top:12px;font-size:13px}.toggle-row input{width:18px;height:18px;accent-color:var(--forest)}
@media(prefers-reduced-motion:reduce){*,*:before,*:after{scroll-behavior:auto!important;animation-duration:.001ms!important;animation-iteration-count:1!important;transition-duration:.001ms!important}}
@media(max-width:560px){.seasonmark{display:none}.syncmini{width:40px;padding:0;justify-content:center}.syncmini .syncmini-label{display:none}.quickbtn{width:40px;height:40px}.plant-search{width:100%}.mapbar>.actions{width:100%}.mapbar>.actions .btn{flex:1}.celebrate-card{min-width:135px}}
'''
    replace_once(css_marker, css + '\n' + css_marker, 'css marker')


# ---------------------------------------------------------------------------
# 2. Navigation, header quick actions, plant search
# ---------------------------------------------------------------------------
replace_once(
'''      <div class="locpill" id="headerLocation">Noch kein Standort</div>\n      <button class="gearbtn" id="settingsGear" type="button" aria-label="Einstellungen öffnen" title="Einstellungen">⚙</button>''',
'''      <div class="locpill" id="headerLocation">Noch kein Standort</div>\n      <span class="seasonmark" id="seasonMark" aria-hidden="true">🌿</span>\n      <button class="syncmini" id="syncMini" type="button" title="Synchronisation"><span aria-hidden="true">☁</span><span class="syncmini-label">Sync</span><span class="syncmini-dot" id="syncMiniDot"></span></button>\n      <button class="quickbtn" id="quickAddPlant" type="button" aria-label="Pflanze hinzufügen" title="Pflanze hinzufügen">+</button>\n      <button class="gearbtn" id="settingsGear" type="button" aria-label="Einstellungen öffnen" title="Einstellungen">⚙</button>''',
'header tools')

replace_once(
'''    <button class="tab active" data-view="today" type="button">Heute</button>\n    <button class="tab" data-view="map" type="button">Karte</button>\n    <button class="tab" data-view="plants" type="button">Pflanzen</button>''',
'''    <button class="tab active" data-view="today" type="button">Heute</button>\n    <button class="tab" data-view="plants" type="button">Pflanzen</button>\n    <button class="tab" data-view="map" type="button">Karte</button>''',
'tab order')

replace_once(
'''    <div class="topline"><div><h2>Meine Pflanzen</h2><div class="muted">Foto, Pflegeprofil, Standort und Historie werden nur in diesem Browser gespeichert.</div></div><button class="btn" id="newPlantBtn" type="button">+ Pflanze</button></div>''',
'''    <div class="topline"><div><h2>Meine Pflanzen</h2><div class="muted">Schnell finden, ansehen oder eine neue Pflanze hinzufügen.</div></div><div class="actions"><input class="plant-search" id="plantSearch" type="search" placeholder="Pflanze oder Gartenbereich suchen" aria-label="Pflanzen suchen"><button class="btn" id="newPlantBtn" type="button">+ Pflanze</button></div></div>''',
'plant search')


# ---------------------------------------------------------------------------
# 3. Garden map becomes a fixed personal garden plan by default
# ---------------------------------------------------------------------------
old_map = '''    <div class="topline"><div><h2>Gartenkarte</h2><div class="muted">Luftbild Baden-Württemberg · Pflanzen positionieren und Standortzonen markieren.</div></div></div>\n    <div class="mapbar">\n      <button class="btn" id="drawZoneBtn" type="button">Sonne-/Schattenzone zeichnen</button>\n      <button class="btn secondary" id="fitGardenBtn" type="button">Garten anzeigen</button>\n      <button class="btn ghost" id="setGardenCenterBtn" type="button">Gartenmitte setzen</button>\n      <span id="mapModeHint" class="maphint hidden"></span>\n    </div>'''
new_map = '''    <div class="topline"><div><h2>Mein Garten</h2><div class="muted">Dein gespeicherter Gartenausschnitt mit Pflanzen und Standortzonen.</div></div><span class="map-status" id="mapViewStatus">Fester Gartenausschnitt</span></div>\n    <div class="map-edit-note hidden" id="mapSetupHint"><b>Gartenausschnitt einmal festlegen:</b> Karte verschieben und zoomen, bis dein Garten gut sichtbar ist. Danach „Ausschnitt speichern“ wählen.</div>\n    <div class="mapbar">\n      <button class="btn secondary" id="mapEditToggle" type="button">Karte bearbeiten</button>\n      <button class="btn hidden" id="saveMapViewBtn" type="button">Ausschnitt speichern</button>\n      <div class="actions hidden" id="mapEditTools">\n        <button class="btn secondary" id="drawZoneBtn" type="button">Sonne-/Schattenzone</button>\n        <button class="btn secondary" id="fitGardenBtn" type="button">Alles anzeigen</button>\n        <button class="btn ghost" id="setGardenCenterBtn" type="button">Gartenmitte setzen</button>\n      </div>\n      <span id="mapModeHint" class="maphint hidden"></span>\n    </div>'''
replace_once(old_map, new_map, 'map controls')

# Add direct map editor shortcut to compact settings.
replace_once(
'''<button class="btn ghost small" id="openGardenCenter" type="button">Gartenmitte auf Karte</button>''',
'''<button class="btn ghost small" id="openMapEditor" type="button">Gartenausschnitt ändern</button><button class="btn ghost small" id="openGardenCenter" type="button">Gartenmitte setzen</button>''',
'map settings shortcuts')


# ---------------------------------------------------------------------------
# 4. Appearance settings and feedback layers
# ---------------------------------------------------------------------------
appearance = '''    <section class="settings-section" id="settingsAppearance">\n      <h3>Erscheinungsbild</h3>\n      <div class="muted">Die Gartenwelt passt ihre Farben automatisch an die Jahreszeit an. Die Bedienung bleibt immer gleich.</div>\n      <div class="appearance-row"><label for="seasonMode"><b>Jahreszeit</b></label><select id="seasonMode"><option value="auto">Automatisch</option><option value="spring">Frühling</option><option value="summer">Sommer</option><option value="autumn">Herbst</option><option value="winter">Winter</option></select></div>\n      <label class="toggle-row"><input id="animationToggle" type="checkbox" checked><span>Kleine Animation nach erledigten Aufgaben</span></label>\n      <div class="muted" id="seasonStatus" style="margin-top:8px"></div>\n    </section>\n\n'''
replace_once('    <section class="settings-section" id="settingsPlantnet">', appearance + '    <section class="settings-section" id="settingsPlantnet">', 'appearance settings')

feedback_html = '''<div class="celebration hidden" id="celebration" aria-live="polite">\n  <div class="celebrate-card"><div class="celebrate-check">✓</div><div class="celebrate-text" id="celebrateText">Erledigt</div><div id="celebrateParticles"></div></div>\n</div>\n<div class="undo-toast hidden" id="undoToast"><span id="undoText">Pflanze gelöscht</span><button id="undoDeleteBtn" type="button">Rückgängig</button></div>\n\n'''
replace_once('<div class="foot">Gießempfehlungen sind Modellschätzungen', feedback_html + '<div class="foot">Gießempfehlungen sind Modellschätzungen', 'feedback html')


# ---------------------------------------------------------------------------
# 5. State defaults. Appearance and map viewport remain local per device.
# ---------------------------------------------------------------------------
replace_line(
'var state=',
'var state={days:30,plz:"",loc:null,gardenCenter:null,weather:null,plants:[],zones:[],settings:{plantnetKey:DEFAULT_PLANTNET_KEY,seasonMode:"auto",animations:true,mapView:null},pendingZone:null,editingZoneId:null,map:null,zoneGroup:null,markerGroup:null,mapReady:false,mapEditMode:false,placePlantId:null,setCenterMode:false,photoData:"",photoFile:null,editPlantId:null};',
'state')

replace_line(
'function load(){',
'function load(){try{var raw=localStorage.getItem(STORE);if(raw){var d=JSON.parse(raw);state.plz=d.plz||"";state.loc=d.loc||null;state.gardenCenter=d.gardenCenter||null;state.plants=Array.isArray(d.plants)?d.plants:[];state.zones=Array.isArray(d.zones)?d.zones:[];state.settings=Object.assign({plantnetKey:DEFAULT_PLANTNET_KEY,seasonMode:"auto",animations:true,mapView:null},d.settings||{});if(!(state.settings.plantnetKey||"").trim())state.settings.plantnetKey=DEFAULT_PLANTNET_KEY;if(!["auto","spring","summer","autumn","winter"].includes(state.settings.seasonMode))state.settings.seasonMode="auto";if(state.settings.animations!==false)state.settings.animations=true;state.days=[7,14,30,60,90].includes(Number(d.days))?Number(d.days):30}else{var old=localStorage.getItem("giess_plz");if(old)state.plz=old}}catch(e){console.warn(e)}loadSync()}',
'load')

# Preserve snooze metadata while editing a plant.
replace_line(
'function plantFromForm(){',
'function plantFromForm(){var name=el("plantName").value.trim();if(!name)throw new Error("Bitte einen Pflanzenname eingeben.");var old=state.editPlantId?state.plants.find(function(x){return x.id===state.editPlantId}):null;var by=el("plantBirthYear").value.trim();if(by){var y=Number(by),now=new Date().getFullYear();if(!Number.isInteger(y)||y<1900||y>now)throw new Error("Bitte ein plausibles Pflanz-/Anzuchtjahr eingeben.")}return{id:old?old.id:uid(),name:name,scientific:el("plantScientific").value.trim(),area:el("plantArea").value.trim(),type:el("plantType").value||"bed",water:el("plantWater").value,size:el("plantSize").value||"medium",birthYear:by?Number(by):null,plantedSince:el("plantSince").value||null,transplanted:el("plantTransplanted").value||null,notes:el("plantNotes").value.trim(),fertMonths:checkedMonths("fert"),cutMonths:checkedMonths("cut"),photo:state.photoData||"",lat:old?old.lat:null,lon:old?old.lon:null,lastWatered:old?old.lastWatered:null,lastFertilized:old?old.lastFertilized:null,lastCut:old?old.lastCut:null,snoozed:old&&old.snoozed?old.snoozed:{},created:old?old.created:isoToday()}}',
'plant form')


# ---------------------------------------------------------------------------
# 6. Seasonal theme and small status helpers
# ---------------------------------------------------------------------------
helper_marker = 'function relativeDayLabel(date)'
helpers = r'''function automaticSeason(){var m=new Date().getMonth()+1;return m>=3&&m<=5?"spring":m>=6&&m<=8?"summer":m>=9&&m<=11?"autumn":"winter"}
function currentSeason(){var mode=state.settings&&state.settings.seasonMode||"auto";return mode==="auto"?automaticSeason():mode}
function seasonInfo(key){return{spring:{label:"Frühling",icon:"🌸",particles:["🌸","🌱","✿","🌿"]},summer:{label:"Sommer",icon:"☀️",particles:["☀️","🌿","✦","🌼"]},autumn:{label:"Herbst",icon:"🍂",particles:["🍂","🍁","✦","🌿"]},winter:{label:"Winter",icon:"❄️",particles:["❄️","✧","❅","🌿"]}}[key]||{label:"Garten",icon:"🌿",particles:["🌿","✦"]}}
function applyAppearance(){var key=currentSeason(),info=seasonInfo(key);document.body.dataset.season=key;var mark=el("seasonMark");if(mark){mark.textContent=info.icon;mark.title=info.label}var sm=el("seasonMode");if(sm)sm.value=state.settings.seasonMode||"auto";var at=el("animationToggle");if(at)at.checked=state.settings.animations!==false;var st=el("seasonStatus");if(st)st.textContent=(state.settings.seasonMode||"auto")==="auto"?"Aktuell: "+info.label+" · Wechsel automatisch am 1. März, 1. Juni, 1. September und 1. Dezember.":"Manuell gewählt: "+info.label+"."}
function renderSyncMini(){var b=el("syncMini");if(!b)return;var cls="warn",title="Synchronisation nicht eingerichtet";if(syncState.conflict){cls="bad";title="Synchronisationskonflikt"}else if(syncState.busy||syncState.dirty){cls="warn";title=syncState.busy?"Synchronisierung läuft":"Änderung wartet auf Synchronisierung"}else if(syncState.enabled){cls="ok";title="Garten synchronisiert"}b.className="syncmini "+cls;b.title=title;b.setAttribute("aria-label",title)}
function celebrateDone(label){if(state.settings.animations===false||window.matchMedia&&window.matchMedia("(prefers-reduced-motion: reduce)").matches){notice(label+" · erledigt");return}var box=el("celebration"),pt=el("celebrateParticles"),txt=el("celebrateText"),info=seasonInfo(currentSeason());txt.textContent=label+" · erledigt";pt.innerHTML="";var coords=[[-64,-54,-28],[-32,-78,22],[12,-82,-18],[55,-54,34],[-58,-10,18],[61,-4,-24],[0,-94,12]];coords.forEach(function(c,i){var sp=document.createElement("span");sp.className="particle";sp.textContent=info.particles[i%info.particles.length];sp.style.setProperty("--dx",c[0]+"px");sp.style.setProperty("--dy",c[1]+"px");sp.style.setProperty("--rot",c[2]+"deg");sp.style.animationDelay=(i*.035)+"s";pt.appendChild(sp)});show("celebration",true);setTimeout(function(){show("celebration",false);pt.innerHTML=""},950)}
var lastDeletedPlant=null,lastDeletedTimer=null;
function deletePlantWithUndo(id){var idx=state.plants.findIndex(function(x){return x.id===id});if(idx<0)return;var item=state.plants[idx];if(!confirm('Pflanze „'+item.name+'“ löschen?'))return;lastDeletedPlant={plant:item,index:idx};state.plants.splice(idx,1);save();renderAll();el("undoText").textContent=item.name+" gelöscht";show("undoToast",true);clearTimeout(lastDeletedTimer);lastDeletedTimer=setTimeout(function(){show("undoToast",false);lastDeletedPlant=null},6500)}
function undoDelete(){if(!lastDeletedPlant)return;var x=lastDeletedPlant;state.plants.splice(Math.min(x.index,state.plants.length),0,x.plant);lastDeletedPlant=null;clearTimeout(lastDeletedTimer);show("undoToast",false);save();renderAll();notice("Pflanze wiederhergestellt.")}
function taskSnoozed(p,kind){return !!(p.snoozed&&p.snoozed[kind]===isoToday())}
function snoozeTask(p,kind){p.snoozed=p.snoozed||{};p.snoozed[kind]=isoToday();save()}
function clearSnooze(p,kind){if(p.snoozed&&p.snoozed[kind])delete p.snoozed[kind]}
'''
replace_once(helper_marker, helpers + helper_marker, 'helper insertion')

# Sync status updates tiny header indicator as well.
s = s.replace('function renderSync(){if(!el("syncStatus"))return;', 'function renderSync(){renderSyncMini();if(!el("syncStatus"))return;', 1)


# ---------------------------------------------------------------------------
# 7. Map behavior: editable only deliberately, fixed viewport for daily use
# ---------------------------------------------------------------------------
map_helpers = r'''function mapInteraction(enabled){if(!state.map)return;["dragging","touchZoom","doubleClickZoom","scrollWheelZoom","boxZoom","keyboard"].forEach(function(k){if(state.map[k]&&state.map[k][enabled?"enable":"disable"])state.map[k][enabled?"enable":"disable"]()});var node=el("map");if(node){node.classList.toggle("map-editing",enabled);node.classList.toggle("map-locked",!enabled)}}
function renderMapMode(){var edit=!!state.mapEditMode,has=!!(state.settings&&state.settings.mapView);show("mapEditTools",edit);show("saveMapViewBtn",edit);show("mapSetupHint",edit&&!has);var b=el("mapEditToggle"),st=el("mapViewStatus");if(b)b.textContent=edit?(has?"Bearbeitung beenden":"Ausschnitt festlegen"):"Karte bearbeiten";if(st){st.className="map-status"+(edit?" editing":"");st.textContent=edit?(has?"Bearbeitung aktiv":"Ersteinrichtung"):"Fester Gartenausschnitt"}}
function setMapEditing(on){state.mapEditMode=!!on;mapInteraction(state.mapEditMode);renderMapMode();if(state.mapReady)renderMap()}
function applySavedMapView(){var mv=state.settings&&state.settings.mapView;if(!state.map||!mv)return;var lat=Number(mv.lat),lon=Number(mv.lon),zoom=Number(mv.zoom);if(Number.isFinite(lat)&&Number.isFinite(lon)&&Number.isFinite(zoom))state.map.setView([lat,lon],zoom,{animate:false})}
function saveMapViewport(){if(!state.map)return;var c=state.map.getCenter();state.settings.mapView={lat:c.lat,lon:c.lng,zoom:state.map.getZoom()};save();setMapEditing(false);notice("Gartenausschnitt gespeichert.")}
function toggleMapEditing(){if(!state.mapReady)initMap();if(!state.mapReady)return;if(state.mapEditMode){if(!state.settings.mapView){saveMapViewport();return}setMapEditing(false);applySavedMapView()}else setMapEditing(true)}
'''
replace_once('function switchView(name)', map_helpers + 'function switchView(name)', 'map helper insertion')

replace_line(
'function switchView(name){',
'function switchView(name){closeSettings();document.querySelectorAll(".view").forEach(function(v){v.classList.toggle("active",v.id==="view-"+name)});document.querySelectorAll(".tab").forEach(function(b){b.classList.toggle("active",b.dataset.view===name)});if(name==="map"){setTimeout(function(){initMap();if(state.map)state.map.invalidateSize();var forced=!!(state.placePlantId||state.setCenterMode);if(!state.settings.mapView||forced)setMapEditing(true);else{applySavedMapView();setMapEditing(false)}renderMap()},40)}if(name==="calendar")renderCalendar();if(name==="plants")renderPlants()}',
'switch view')

replace_line(
'function beginPlacePlant(id){',
'function beginPlacePlant(id){var p=state.plants.find(function(x){return x.id===id});if(!p)return;state.placePlantId=id;state.setCenterMode=false;switchView("map");setTimeout(function(){setMapEditing(true);el("mapModeHint").textContent=\'Auf das Luftbild tippen, um „\'+p.name+\'“ zu positionieren.\';show("mapModeHint",true)},90)}',
'begin plant placement')

replace_line(
'function initMap(){',
'function initMap(){if(state.mapReady)return;if(typeof L==="undefined"){globalError("Kartenbibliothek konnte nicht geladen werden. Bitte Internetverbindung prüfen.");return}var mv=state.settings&&state.settings.mapView,center=mv?[Number(mv.lat),Number(mv.lon)]:(state.gardenCenter?[state.gardenCenter.lat,state.gardenCenter.lon]:(state.loc?[state.loc.lat,state.loc.lon]:[48.7,9.1])),zoom=mv?Number(mv.zoom):((state.gardenCenter||state.loc)?19:8);state.map=L.map("map",{zoomControl:true}).setView(center,zoom);var osm=L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",{maxZoom:20,attribution:"© OpenStreetMap"});var dop=L.tileLayer.wms("https://owsproxy.lgl-bw.de/owsproxy/ows/WMS_LGL-BW_ATKIS_DOP_20_C",{layers:"IMAGES_DOP_20_RGB",format:"image/jpeg",transparent:false,version:"1.3.0",maxZoom:22,attribution:"Luftbild © LGL Baden-Württemberg"});dop.addTo(state.map);L.control.layers({"Luftbild BW":dop,"OpenStreetMap":osm},null,{collapsed:true}).addTo(state.map);state.zoneGroup=new L.FeatureGroup().addTo(state.map);state.markerGroup=new L.FeatureGroup().addTo(state.map);var dc=new L.Control.Draw({position:"topleft",draw:false,edit:{featureGroup:state.zoneGroup,remove:true}});state.map.addControl(dc);state.map.on("click",function(e){if(state.setCenterMode){state.gardenCenter={lat:e.latlng.lat,lon:e.latlng.lng};state.setCenterMode=false;show("mapModeHint",false);save();renderAll();refreshWeather(false);notice("Gartenmitte gespeichert. Wetter wird künftig für diese Position berechnet.");return}if(state.placePlantId){var p=state.plants.find(function(x){return x.id===state.placePlantId});if(p){p.lat=e.latlng.lat;p.lon=e.latlng.lng;state.placePlantId=null;show("mapModeHint",false);save();renderAll();notice("Pflanze auf der Karte positioniert.")}}});state.map.on(L.Draw.Event.CREATED,function(e){if(e.layerType!=="polygon")return;state.editingZoneId=null;state.pendingZone=e.layer.getLatLngs()[0].map(function(x){return{lat:x.lat,lon:x.lng}});state.map.addLayer(e.layer);e.layer._pendingZone=true;state._pendingLayer=e.layer;el("zoneName").value="";el("zoneLight").value="fullsun";el("zoneRain").value="open";el("zoneSoil").value="normal";show("zoneEditor",true);el("zoneEditor").scrollIntoView({behavior:"smooth",block:"nearest"})});state.map.on(L.Draw.Event.EDITED,function(e){e.layers.eachLayer(function(layer){if(!layer._zoneId)return;var z=state.zones.find(function(x){return x.id===layer._zoneId});if(z)z.points=layer.getLatLngs()[0].map(function(x){return{lat:x.lat,lon:x.lng}})});save();renderAll()});state.map.on(L.Draw.Event.DELETED,function(e){var ids=[];e.layers.eachLayer(function(layer){if(layer._zoneId)ids.push(layer._zoneId)});state.zones=state.zones.filter(function(z){return !ids.includes(z.id)});save();renderAll()});state.mapReady=true;setMapEditing(!state.settings.mapView);renderMap()}',
'init map')

replace_line(
'function renderMap(){',
'function renderMap(){if(!state.mapReady)return;state.zoneGroup.clearLayers();state.markerGroup.clearLayers();if(state.gardenCenter){L.circleMarker([state.gardenCenter.lat,state.gardenCenter.lon],{radius:6,color:"#17324d",weight:2,fillColor:"#fff",fillOpacity:1,interactive:state.mapEditMode}).addTo(state.markerGroup).bindTooltip("Gartenmitte")}state.zones.forEach(function(z){var poly=L.polygon(z.points.map(function(p){return[p.lat,p.lon]}),zoneStyle(z)).addTo(state.zoneGroup);poly._zoneId=z.id;poly.bindPopup(\'<b>\'+esc(z.name||lightLabel(z.light))+\'</b><br>\'+lightLabel(z.light)+\' · \'+rainLabel(z.rain)+\' · \'+soilLabel(z.soil))});state.plants.filter(function(p){return p.lat&&p.lon}).forEach(function(p){var wa=waterAssessment(p);var icon=L.divIcon({className:"",html:\'<div class="plant-marker \'+wa.level+\'">🌿</div>\',iconSize:[26,26],iconAnchor:[13,13]});var m=L.marker([p.lat,p.lon],{icon:icon,draggable:!!state.mapEditMode}).addTo(state.markerGroup);m.bindPopup(\'<b>\'+esc(p.name)+\'</b><br>\'+esc(wa.title)+(currentZoneForPlant(p)?\'<br>\'+lightLabel(currentZoneForPlant(p).light):\'\'));if(state.mapEditMode)m.on("dragend",function(){var q=m.getLatLng();p.lat=q.lat;p.lon=q.lng;save();renderAll()})});renderZoneList();renderMapMode()}',
'render map')

replace_line(
'function renderZoneList(){',
'function renderZoneList(){var edit=!!state.mapEditMode;el("zoneList").innerHTML=state.zones.length?state.zones.map(function(z){return \'<div class="zone-row"><div class="zmain"><b><span class="swatch" style="background:\'+zoneStyle(z).color+\'"></span>\'+esc(z.name||lightLabel(z.light))+\'</b><small>\'+lightLabel(z.light)+\' · \'+rainLabel(z.rain)+\' · \'+soilLabel(z.soil)+\'</small></div>\'+(edit?\'<div class="actions"><button class="btn secondary small zoneEdit" data-id="\'+z.id+\'" type="button">Bearbeiten</button><button class="btn ghost small zoneDelete" data-id="\'+z.id+\'" type="button">Löschen</button></div>\':\'\')+\'</div>\'}).join(""):\'\';document.querySelectorAll(".zoneEdit").forEach(function(b){b.addEventListener("click",function(){var z=state.zones.find(function(x){return x.id===b.dataset.id});if(!z)return;state.editingZoneId=z.id;state.pendingZone=z.points.map(function(p){return{lat:p.lat,lon:p.lon}});el("zoneName").value=z.name||"";el("zoneLight").value=z.light||"partial";el("zoneRain").value=z.rain||"open";el("zoneSoil").value=z.soil||"normal";show("zoneEditor",true);el("zoneEditor").scrollIntoView({behavior:"smooth",block:"nearest"})})});document.querySelectorAll(".zoneDelete").forEach(function(b){b.addEventListener("click",function(){state.zones=state.zones.filter(function(z){return z.id!==b.dataset.id});save();renderAll()})})}',
'render zone list')


# ---------------------------------------------------------------------------
# 8. Task comfort: Later + seasonal completion animation
# ---------------------------------------------------------------------------
replace_line(
'function getTodayTasks(){',
'function getTodayTasks(){var tasks=[],m=new Date().getMonth()+1;state.plants.forEach(function(p){var wa=waterAssessment(p);if(wa.level!=="ok"&&!taskSnoozed(p,"water"))tasks.push({plant:p,kind:"water",level:wa.level,icon:"💧",title:wa.title,why:wa.reason});if((p.fertMonths||[]).includes(m)&&daysSince(p.lastFertilized)>28&&establishmentInfo(p).days>42&&!taskSnoozed(p,"fert"))tasks.push({plant:p,kind:"fert",level:"warn",icon:"🌱",title:"Düngung vorgesehen",why:"Für diese Pflanze ist "+MONTHS[m-1]+" als Düngemonat hinterlegt."});if((p.cutMonths||[]).includes(m)&&daysSince(p.lastCut)>28&&!taskSnoozed(p,"cut"))tasks.push({plant:p,kind:"cut",level:"warn",icon:"✂️",title:"Schnittzeit prüfen",why:"Für diese Pflanze ist "+MONTHS[m-1]+" als Schnittmonat hinterlegt."})});return tasks}',
'today tasks')

replace_line(
'function renderToday(){',
'function renderToday(){el("todayDate").textContent=new Date().toLocaleDateString("de-DE",{weekday:"long",day:"2-digit",month:"long",year:"numeric"});var tw=el("todayWeather"),gs=el("gardenState"),gb=el("gardenStateBadge"),gt=el("gardenStateText"),gd=el("gardenDryDays"),gn=el("gardenNextRain"),gf=el("gardenFrost"),gfb=el("gardenFrostBox");var summary=gardenWeatherSummary();if(!summary){tw.className="state-card";gs.textContent="Noch keine Wetterdaten";gb.textContent="Standort fehlt";gt.innerHTML=\'Öffne oben rechts das <b>Zahnrad</b> und hinterlege einmal deine Postleitzahl.\';gd.textContent="–";gn.textContent="–";gf.textContent="–";gfb.classList.remove("frost")}else{tw.className="state-card "+summary.cls;gs.textContent=summary.name;gb.textContent=summary.name.toUpperCase();gt.textContent=summary.explanation;gd.textContent=summary.dryDays===0?"Heute Regen":summary.dryDays+" "+(summary.dryDays===1?"Tag":"Tage");gn.textContent=summary.nextRain?(relativeDayLabel(summary.nextRain.date)+" · "+de1(summary.nextRain.rain)+" mm"):"Nicht in 7 Tagen";if(summary.frost){gf.textContent=relativeDayLabel(summary.frost.date)+" · "+de1(summary.frost.min)+" °C";gfb.classList.add("frost")}else{gf.textContent="Kein Frost in Sicht";gfb.classList.remove("frost")}}var tasks=getTodayTasks();el("taskCount").textContent=tasks.length?tasks.length+" offen":"nichts offen";if(!state.plants.length){el("tasks").innerHTML=\'<div class="empty">Noch keine Pflanzen angelegt. Mit dem <b>+</b> oben kannst du direkt starten.</div>\';return}if(!tasks.length){el("tasks").innerHTML=\'<div class="empty">Heute ist nichts zu tun. 🌿</div>\';return}el("tasks").innerHTML=tasks.map(function(t){var action=t.kind==="water"?"Gegossen":t.kind==="fert"?"Gedüngt":"Geschnitten";return \'<div class="task \'+t.level+\'" data-task-id="\'+t.plant.id+\'" data-task-kind="\'+t.kind+\'"><div class="taskicon">\'+t.icon+\'</div><div><b>\'+esc(t.plant.name)+\' · \'+esc(t.title)+\'</b><div class="why">\'+esc(t.why)+\'</div></div><div class="actions"><button class="btn ghost small taskLater" data-id="\'+t.plant.id+\'" data-kind="\'+t.kind+\'" type="button">Später</button><button class="btn small taskDone" data-id="\'+t.plant.id+\'" data-kind="\'+t.kind+\'" type="button">\'+action+\'</button></div></div>\'}).join("");document.querySelectorAll(".taskDone").forEach(function(b){b.addEventListener("click",function(){var p=state.plants.find(function(x){return x.id===b.dataset.id});if(!p)return;var kind=b.dataset.kind,key=kind==="water"?"lastWatered":kind==="fert"?"lastFertilized":"lastCut",label=kind==="water"?"Gegossen":kind==="fert"?"Gedüngt":"Geschnitten",row=b.closest(".task");p[key]=isoToday();clearSnooze(p,kind);save();if(row)row.classList.add("task-complete");celebrateDone(label);setTimeout(renderAll,540)})});document.querySelectorAll(".taskLater").forEach(function(b){b.addEventListener("click",function(){var p=state.plants.find(function(x){return x.id===b.dataset.id});if(!p)return;var row=b.closest(".task");snoozeTask(p,b.dataset.kind);if(row)row.classList.add("task-complete");setTimeout(renderAll,420)})})}',
'render today')


# ---------------------------------------------------------------------------
# 9. Compact, searchable plant list with undo delete
# ---------------------------------------------------------------------------
replace_line(
'function renderPlants(){',
'function renderPlants(){var list=el("plantList"),q=String(el("plantSearch")?el("plantSearch").value:"").trim().toLowerCase();if(!state.plants.length){list.innerHTML=\'<div class="box empty" style="grid-column:1/-1">Noch keine Pflanzen gespeichert.</div>\';return}var plants=state.plants.filter(function(p){return !q||String(p.name||"").toLowerCase().includes(q)||String(p.scientific||"").toLowerCase().includes(q)||String(p.area||"").toLowerCase().includes(q)});if(!plants.length){list.innerHTML=\'<div class="box empty" style="grid-column:1/-1">Keine passende Pflanze gefunden.</div>\';return}list.innerHTML=plants.map(function(p){var wa=waterAssessment(p),z=currentZoneForPlant(p),photo=p.photo?\'<img src="\'+p.photo+\'" alt="\'+esc(p.name)+\'">\':\'🌿\',est=establishmentInfo(p);var area=p.area?esc(p.area):(z?esc(lightLabel(z.light)):"Standort noch nicht benannt");return \'<article class="plantcard"><div class="plantphoto">\'+photo+\'</div><div class="plantbody"><div class="plantname"><span class="statusdot \'+wa.level+\'"></span>\'+esc(p.name)+\'</div><div class="plant-summary">\'+area+\' · <b>\'+esc(wa.title)+\'</b></div><details class="plant-details"><summary>Details</summary><div class="latin" style="margin-top:7px">\'+esc(p.scientific||"")+\'</div><div class="chips"><span class="chip">\'+typeLabel(p.type)+\'</span><span class="chip">Größe: \'+sizeLabel(p.size)+\'</span><span class="chip">Wasser: \'+(p.water==="high"?"hoch":p.water==="low"?"niedrig":"normal")+\'</span>\'+(p.birthYear?\'<span class="chip">Jahrgang ca. \'+esc(String(p.birthYear))+\'</span>\':\'\')+(est.days<999?\'<span class="chip">\'+esc(est.label)+\'</span>\':\'\')+(z?\'<span class="chip">\'+lightLabel(z.light)+\'</span>\':\'\')+\'</div></details><div class="plantactions"><button class="btn small editPlant" data-id="\'+p.id+\'" type="button">Bearbeiten</button><button class="btn secondary small placePlant" data-id="\'+p.id+\'" type="button">\'+(p.lat?"Position ändern":"Auf Karte setzen")+\'</button><button class="btn ghost small deletePlant" data-id="\'+p.id+\'" type="button">Löschen</button></div></div></article>\'}).join("");document.querySelectorAll(".editPlant").forEach(function(b){b.addEventListener("click",function(){openPlantEditor(b.dataset.id)})});document.querySelectorAll(".placePlant").forEach(function(b){b.addEventListener("click",function(){beginPlacePlant(b.dataset.id)})});document.querySelectorAll(".deletePlant").forEach(function(b){b.addEventListener("click",function(){deletePlantWithUndo(b.dataset.id)})})}',
'render plants')


# ---------------------------------------------------------------------------
# 10. Header rendering, backup of local UX preferences
# ---------------------------------------------------------------------------
replace_line(
'function renderHeader(){',
'function renderHeader(){el("headerLocation").textContent=state.loc?(state.loc.name+" · "+state.plz):(state.plz?"PLZ "+state.plz:"Noch kein Standort");el("plz").value=state.plz||"";el("plantnetKey").value=state.settings.plantnetKey||"";var ps=el("plantnetStatus");if(ps){var active=!!String(state.settings.plantnetKey||"").trim();ps.className="section-status "+(active?"ok":"");ps.textContent=active?"Pflanzenerkennung aktiv":"Nicht eingerichtet"}applyAppearance();renderSyncMini()}',
'render header')

replace_line(
'function renderAll(){',
'function renderAll(){applyAppearance();renderHeader();renderToday();renderPlants();renderCalendar();renderWeather();renderSync();if(state.mapReady)renderMap()}',
'render all')

replace_line(
'function exportBackup(){',
'function exportBackup(){var data={version:7,exported:new Date().toISOString(),plz:state.plz,loc:state.loc,gardenCenter:state.gardenCenter,plants:state.plants,zones:state.zones,settings:{plantnetKey:state.settings.plantnetKey||"",seasonMode:state.settings.seasonMode||"auto",animations:state.settings.animations!==false,mapView:state.settings.mapView||null},days:state.days};var blob=new Blob([JSON.stringify(data,null,2)],{type:"application/json"}),a=document.createElement("a");a.href=URL.createObjectURL(blob);a.download="Johannas_Gartenwelt_Backup_"+isoToday()+".json";document.body.appendChild(a);a.click();setTimeout(function(){URL.revokeObjectURL(a.href);a.remove()},300)}',
'backup export')

replace_line(
'async function importBackup(file){',
'async function importBackup(file){try{var data=JSON.parse(await file.text());if(!Array.isArray(data.plants)||!Array.isArray(data.zones))throw new Error("Keine gültige Johanna´s-Gartenwelt-Sicherung");state.plz=data.plz||state.plz;state.loc=data.loc||null;state.gardenCenter=data.gardenCenter||null;state.plants=data.plants;state.zones=data.zones;state.days=[7,14,30,60,90].includes(Number(data.days))?Number(data.days):30;state.settings=Object.assign({plantnetKey:DEFAULT_PLANTNET_KEY,seasonMode:"auto",animations:true,mapView:null},state.settings||{},data.settings||{});if(data.settings&&Object.prototype.hasOwnProperty.call(data.settings,"plantnetKey"))state.settings.plantnetKey=data.settings.plantnetKey||"";save();renderAll();if(state.plz)refreshWeather(false);notice("Backup importiert.")}catch(e){globalError("Import fehlgeschlagen: "+e.message)}}',
'backup import')


# ---------------------------------------------------------------------------
# 11. Replace initialization line so all new controls are wired once.
# ---------------------------------------------------------------------------
init = r'''load();applyAppearance();buildMonthChecks("fertMonths","fert");buildMonthChecks("cutMonths","cut");
el("settingsGear").addEventListener("click",function(){openSettings()});
el("settingsClose").addEventListener("click",closeSettings);
el("settingsOverlay").addEventListener("click",function(e){if(e.target===this)closeSettings()});
document.addEventListener("keydown",function(e){if(e.key==="Escape")closeSettings()});
el("syncMini").addEventListener("click",function(){openSettings("settingsSync")});
el("quickAddPlant").addEventListener("click",function(){switchView("plants");setTimeout(function(){openPlantEditor(null)},50)});
el("seasonMode").addEventListener("change",function(){state.settings.seasonMode=this.value;save();applyAppearance()});
el("animationToggle").addEventListener("change",function(){state.settings.animations=!!this.checked;save()});
el("undoDeleteBtn").addEventListener("click",undoDelete);
el("plantSearch").addEventListener("input",renderPlants);
el("openMapEditor").addEventListener("click",function(){closeSettings();switchView("map");setTimeout(function(){setMapEditing(true)},100)});
el("openGardenCenter").addEventListener("click",function(){closeSettings();switchView("map");setTimeout(function(){setMapEditing(true);el("setGardenCenterBtn").click()},100)});
document.querySelectorAll(".tab").forEach(function(b){b.addEventListener("click",function(){switchView(b.dataset.view)})});
el("refreshWeather").addEventListener("click",function(){refreshWeather(true)});
el("locationForm").addEventListener("submit",function(e){e.preventDefault();var p=el("plz").value.replace(/\D/g,"").slice(0,5);el("plz").value=p;if(!/^\d{5}$/.test(p)){globalError("Bitte eine gültige 5-stellige deutsche PLZ eingeben.");return}state.plz=p;save();refreshWeather(true)});
el("newPlantBtn").addEventListener("click",function(){openPlantEditor(null)});
el("closePlantEditor").addEventListener("click",function(){show("plantEditor",false)});
el("plantPhoto").addEventListener("change",async function(){var f=this.files&&this.files[0];if(!f)return;state.photoFile=f;try{state.photoData=await compressPhoto(f);el("photoPreview").innerHTML='<img src="'+state.photoData+'" alt="Vorschau">'}catch(e){globalError(e.message)}});
el("identifyBtn").addEventListener("click",identifyPlant);
el("plantForm").addEventListener("submit",function(e){e.preventDefault();savePlant(false)});
el("saveAndPlaceBtn").addEventListener("click",function(){savePlant(true)});
el("saveApiKey").addEventListener("click",function(){state.settings.plantnetKey=el("plantnetKey").value.trim();save();renderHeader();notice("API-Schlüssel lokal gespeichert.")});
document.querySelectorAll(".period").forEach(function(b){b.addEventListener("click",function(){state.days=Number(b.dataset.days);save();renderWeather()})});
el("mapEditToggle").addEventListener("click",toggleMapEditing);
el("saveMapViewBtn").addEventListener("click",saveMapViewport);
el("drawZoneBtn").addEventListener("click",function(){initMap();if(!state.mapReady)return;setMapEditing(true);state.placePlantId=null;state.setCenterMode=false;show("mapModeHint",false);var drawer=new L.Draw.Polygon(state.map,{allowIntersection:false,showArea:true,shapeOptions:{color:"#2f6d8d",weight:2,fillOpacity:.2}});drawer.enable()});
el("saveZoneBtn").addEventListener("click",function(){if(!state.pendingZone)return;var z={id:state.editingZoneId||uid(),name:el("zoneName").value.trim()||lightLabel(el("zoneLight").value),light:el("zoneLight").value,rain:el("zoneRain").value,soil:el("zoneSoil").value,points:state.pendingZone};var zi=state.zones.findIndex(function(x){return x.id===z.id});if(zi>=0)state.zones[zi]=z;else state.zones.push(z);if(state._pendingLayer&&state.map){try{state.map.removeLayer(state._pendingLayer)}catch(e){}}state.pendingZone=null;state.editingZoneId=null;state._pendingLayer=null;show("zoneEditor",false);save();renderAll();notice("Standortzone gespeichert.")});
el("cancelZoneBtn").addEventListener("click",cancelPendingZone);
el("fitGardenBtn").addEventListener("click",function(){setMapEditing(true);fitGarden()});
el("setGardenCenterBtn").addEventListener("click",function(){initMap();if(!state.mapReady)return;setMapEditing(true);state.placePlantId=null;state.setCenterMode=true;el("mapModeHint").textContent="Auf die Mitte deines Gartens tippen. Diese Position wird gespeichert und für Wetterdaten verwendet.";show("mapModeHint",true)});
el("exportCareYear").addEventListener("click",function(){downloadCareICS(nextTwelveMonths(),"Johannas_Gartenwelt_Pflege_naechste_12_Monate.ics","Johanna´s Gartenwelt – Pflegejahr")});
el("exportBtn").addEventListener("click",exportBackup);
el("importFile").addEventListener("change",function(){var f=this.files&&this.files[0];if(f)importBackup(f);this.value=""});
el("clearBtn").addEventListener("click",function(){if(confirm("Alle Pflanzen, Zonen und Pflegehistorien löschen?")){state.plants=[];state.zones=[];save();renderAll();notice("Gartendaten gelöscht.")}});
el("generateGardenId").addEventListener("click",function(){el("syncGardenId").value=randomGardenId();syncReadForm();renderSync()});
el("saveSyncConfig").addEventListener("click",function(){syncReadForm();renderSync();notice("Sync-Zugang auf diesem Gerät gespeichert.")});
el("createCloudGarden").addEventListener("click",syncCreateGarden);
el("joinCloudGarden").addEventListener("click",syncJoinGarden);
el("syncNow").addEventListener("click",syncManual);
el("disconnectSync").addEventListener("click",syncDisconnect);
el("useCloudVersion").addEventListener("click",function(){syncPull(true)});
el("useLocalVersion").addEventListener("click",function(){syncPush(true)});
document.addEventListener("visibilitychange",function(){if(!document.hidden)syncCheckRemote()});
window.addEventListener("error",function(e){console.error(e.error||e.message)});
renderAll();syncBootstrap();if(state.plz)refreshWeather(false);'''
replace_line('load();buildMonthChecks(', init, 'initialization')

# Sanity checks for expected new UX markers.
for marker in ['id="quickAddPlant"','id="seasonMode"','id="mapEditToggle"','id="saveMapViewBtn"','id="animationToggle"','function celebrateDone(','function saveMapViewport(','data-view="plants" type="button">Pflanzen</button>']:
    if marker not in s:
        raise SystemExit(f'missing final marker: {marker}')

path.write_text(s, encoding='utf-8')
print('Johanna UX V2 applied')
