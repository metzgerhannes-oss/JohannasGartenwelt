from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def read(name):
    return (ROOT / name).read_text(encoding="utf-8")


def write(name, text):
    (ROOT / name).write_text(text, encoding="utf-8")


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly 1 match, found {count}")
    return text.replace(old, new, 1)


# ---------------------------------------------------------------------------
# index.html: lazy map dependencies, one photo-storage path, targeted renders
# ---------------------------------------------------------------------------
idx = read("index.html")

for tag in (
    '<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.css">\n',
    '<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/leaflet-draw@1.0.4/dist/leaflet.draw.css">\n',
    '<script src="https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.js"></script>\n',
    '<script src="https://cdn.jsdelivr.net/npm/leaflet-draw@1.0.4/dist/leaflet.draw.js"></script>\n',
):
    idx = replace_once(idx, tag, "", f"remove eager Leaflet resource {tag[:30]}")

# Cache-bust the visible mobile polish shipped in this round.
idx = re.sub(
    r'<script src="\./garten-tipps\.js\?v=[^"]+"></script>',
    '<script src="./garten-tipps.js?v=20260914-2"></script>',
    idx,
    count=1,
)

# The settings button is handled by the V2 module; remove the old inline click.
idx, n = re.subn(
    r'(<button class="btn secondary small" id="optimizePhotoStorageBtn" type="button")\s+onclick="[^"]*"',
    r'\1',
    idx,
    count=1,
)
if n != 1:
    raise RuntimeError(f"photo settings onclick: expected 1 match, found {n}")

# Replace both legacy inline photo-storage generations with the maintained V2 file.
photo_pattern = re.compile(
    r'\n<script>\n\(function\(\)\{\n"use strict";\nvar STORE="giess_check_garten_v3",SYNC_STORE="johannas_gartenwelt_sync_v1";\nvar specs=\{.*?</script>\n<script id="jgw-photo-storage-direct">.*?</script>',
    re.S,
)
idx, n = photo_pattern.subn(
    '\n<script src="./jgw-photo-storage-v2.js?v=20260914-2"></script>',
    idx,
    count=1,
)
if n != 1:
    raise RuntimeError(f"legacy photo storage removal: expected 1 block, found {n}")

loader = r'''var leafletPromise=null;
function addLeafletStyle(id,href){if(document.getElementById(id))return;var l=document.createElement("link");l.id=id;l.rel="stylesheet";l.href=href;document.head.appendChild(l)}
function loadLeafletScript(id,src){return new Promise(function(resolve,reject){var old=document.getElementById(id);if(old){if(old.dataset.loaded==="1"){resolve();return}old.addEventListener("load",resolve,{once:true});old.addEventListener("error",reject,{once:true});return}var s=document.createElement("script");s.id=id;s.src=src;s.async=true;s.addEventListener("load",function(){s.dataset.loaded="1";resolve()},{once:true});s.addEventListener("error",function(){reject(new Error("Kartenmodul konnte nicht geladen werden."))},{once:true});document.head.appendChild(s)})}
function ensureLeaflet(){if(window.L&&L.Control&&L.Control.Draw)return Promise.resolve(true);if(leafletPromise)return leafletPromise;var st=el("mapViewStatus");if(st)st.textContent="Karte wird geladen …";addLeafletStyle("jgwLeafletCss","https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.css");addLeafletStyle("jgwLeafletDrawCss","https://cdn.jsdelivr.net/npm/leaflet-draw@1.0.4/dist/leaflet.draw.css");leafletPromise=loadLeafletScript("jgwLeafletJs","https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.js").then(function(){return loadLeafletScript("jgwLeafletDrawJs","https://cdn.jsdelivr.net/npm/leaflet-draw@1.0.4/dist/leaflet.draw.js")}).then(function(){return true}).catch(function(e){leafletPromise=null;throw e});return leafletPromise}
'''
idx = replace_once(
    idx,
    'function initMap(){if(state.mapReady)return;if(typeof L==="undefined"){globalError("Kartenbibliothek konnte nicht geladen werden. Bitte Internetverbindung prüfen.");return}var mv=',
    loader + 'async function initMap(){if(state.mapReady)return true;try{await ensureLeaflet()}catch(e){globalError("Kartenbibliothek konnte nicht geladen werden. Bitte Internetverbindung prüfen.");return false}var mv=',
    "async lazy initMap",
)
idx = replace_once(
    idx,
    'state.mapReady=true;setMapEditing(!state.settings.mapView);renderMap()}',
    'state.mapReady=true;setMapEditing(!state.settings.mapView||placementActive()||state.setCenterMode);renderMap();return true}',
    "initMap completion",
)
idx = replace_once(
    idx,
    'function toggleMapEditing(){if(!state.mapReady)initMap();if(!state.mapReady)return;if(state.mapEditMode){',
    'async function toggleMapEditing(){if(!state.mapReady)await initMap();if(!state.mapReady)return;if(state.mapEditMode){',
    "async map edit toggle",
)
idx = replace_once(
    idx,
    'if(name==="map"){setTimeout(function(){initMap();if(state.map)state.map.invalidateSize();',
    'if(name==="map"){setTimeout(async function(){await initMap();if(!state.mapReady)return;if(state.map)state.map.invalidateSize();',
    "lazy map view switch",
)
idx = replace_once(
    idx,
    'el("drawZoneBtn").addEventListener("click",function(){initMap();if(!state.mapReady)return;',
    'el("drawZoneBtn").addEventListener("click",async function(){if(!state.mapReady)await initMap();if(!state.mapReady)return;',
    "lazy zone drawing",
)

# The shell previously needed a MutationObserver just to rename this text.
idx = idx.replace('b.textContent=edit?(has?"Bearbeitung beenden":"Ausschnitt festlegen"):"Karte bearbeiten"',
                  'b.textContent=edit?(has?"Bearbeitung beenden":"Ausschnitt festlegen"):"Gartenausschnitt ändern"')

# High-frequency care actions do not need to rebuild every screen.
idx = replace_once(
    idx,
    'function renderAll(){applyAppearance();renderOnboardingGuide();renderHeader();renderAreaManager();renderToday();renderPlants();renderNatureTabs();renderHabitats();renderAnimals();renderCalendar();renderWeather();renderSync();if(state.mapReady)renderMap()}',
    'function renderAll(){applyAppearance();renderOnboardingGuide();renderHeader();renderAreaManager();renderToday();renderPlants();renderNatureTabs();renderHabitats();renderAnimals();renderCalendar();renderWeather();renderSync();if(state.mapReady)renderMap()}\nfunction renderCareViews(){renderToday();renderPlants();renderCalendar();renderSync();if(state.mapReady)renderMap()}\nfunction renderWeatherViews(){renderHeader();renderToday();renderPlants();renderWeather();if(state.mapReady)renderMap()}',
    "targeted render helpers",
)
idx = idx.replace('setTimeout(renderAll,540)', 'setTimeout(renderCareViews,540)')
idx = idx.replace('setTimeout(renderAll,420)', 'setTimeout(renderCareViews,420)')
idx = idx.replace('save();celebrateDone(label);renderAll();if(!el("plantDetailOverlay")',
                  'save();celebrateDone(label);renderCareViews();if(!el("plantDetailOverlay")')
idx = idx.replace('el("locationStatus").textContent="Standort geladen: "+loc.name+".";renderAll();if(state.mapReady&&!state.gardenCenter)',
                  'el("locationStatus").textContent="Standort geladen: "+loc.name+".";renderWeatherViews();if(state.mapReady&&!state.gardenCenter)')

# Sanity checks before writing.
for forbidden in (
    'cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.css">\n',
    '<script src="https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.js"></script>',
    'id="jgw-photo-storage-direct"',
    'window.JGWPhotoStorageDirect',
):
    if forbidden in idx:
        raise RuntimeError(f"index cleanup incomplete: {forbidden}")
if idx.count('jgw-photo-storage-v2.js') != 1:
    raise RuntimeError("V2 photo storage must be loaded exactly once")
if 'async function initMap()' not in idx or 'function ensureLeaflet()' not in idx:
    raise RuntimeError("lazy Leaflet loader missing")
write("index.html", idx)


# ---------------------------------------------------------------------------
# jgw-photo-storage-v2.js: remove compatibility shims and local double work
# ---------------------------------------------------------------------------
v2 = read("jgw-photo-storage-v2.js")
v2 = replace_once(
    v2,
    'try{var compact=await compressSource(it.photo,640,.62);if(cloud){var up=await uploadData(compact,sp.folder,it.id||uniqueId());it.photoRef=up.ref;it.photo=up.url}else{it.photo=await compressSource(it.photo,480,.54)}done++;',
    'try{var compact=await compressSource(it.photo,cloud?640:480,cloud?.62:.54);if(cloud){var up=await uploadData(compact,sp.folder,it.id||uniqueId());it.photoRef=up.ref;it.photo=up.url}else{it.photo=compact}done++;',
    "single local photo compression",
)
v2 = re.sub(
    r'\n/\* Compatibility for the malformed legacy inline wrapper that follows this file\. \*/\nwindow\.bindType=function\(\)\{\};\nwindow\.optimize=optimize;\nwindow\.refreshSigned=refreshSigned;\n',
    '\n',
    v2,
    count=1,
)
if 'window.bindType=' in v2 or 'window.optimize=optimize' in v2:
    raise RuntimeError("legacy V2 compatibility globals still present")
write("jgw-photo-storage-v2.js", v2)


# ---------------------------------------------------------------------------
# jgw-ux-shell.js / patch: remove observer workaround at the source
# ---------------------------------------------------------------------------
shell = read("jgw-ux-shell.js")
shell = shell.replace('if(th)th.textContent="Heute zu tun";if(tm)tm.textContent="Nur das, was heute wirklich relevant ist."',
                      'if(th)th.textContent="Heute wichtig";if(tm)tm.textContent="Nur das, was heute wirklich ansteht."')
shell = replace_once(
    shell,
    'if(hl){new MutationObserver(function(){setTimeout(organize,0)}).observe(hl,{childList:true,subtree:true});organize()}',
    'if(hl)organize()',
    "remove duplicate habitat observer",
)
shell = replace_once(
    shell,
    'if(el("drawZoneBtn"))el("drawZoneBtn").textContent="Standortzone anlegen";function mapText(){var b=el("mapEditToggle");if(b&&b.textContent.trim()==="Karte bearbeiten")b.textContent="Gartenausschnitt ändern"}mapText();if(el("mapEditToggle"))new MutationObserver(mapText).observe(el("mapEditToggle"),{childList:true,subtree:true,characterData:true});if(mapbar){',
    'if(el("drawZoneBtn"))el("drawZoneBtn").textContent="Standortzone anlegen";if(el("mapEditToggle")&&el("mapEditToggle").textContent.trim()==="Karte bearbeiten")el("mapEditToggle").textContent="Gartenausschnitt ändern";if(mapbar){',
    "remove map label observer",
)
write("jgw-ux-shell.js", shell)

patch = read("jgw-ux-patch.js")
old_start = 'function stabilizeHabitats(){var old=el("habitatList");if(!old||old.dataset.jgwStablePlanning==="1")return;var fresh=old.cloneNode(false);fresh.dataset.jgwStablePlanning="1";old.replaceWith(fresh);function organize()'
new_start = 'function stabilizeHabitats(){var list=el("habitatList");if(!list||list.dataset.jgwStablePlanning==="1")return;list.dataset.jgwStablePlanning="1";function organize()'
patch = replace_once(patch, old_start, new_start, "stop cloning habitat list")
patch = replace_once(
    patch,
    'var list=el("habitatList");new MutationObserver(function(){setTimeout(organize,0)}).observe(list,{childList:true,subtree:true});try{',
    'new MutationObserver(function(){setTimeout(organize,0)}).observe(list,{childList:true,subtree:true});try{',
    "reuse habitat list observer target",
)
write("jgw-ux-patch.js", patch)

print("Runtime cleanup applied successfully")
