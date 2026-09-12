from pathlib import Path
import re

path = Path('index.html')
s = path.read_text(encoding='utf-8')


def once(old, new, label):
    global s
    n = s.count(old)
    if n != 1:
        raise SystemExit(f'{label}: expected 1 occurrence, found {n}')
    s = s.replace(old, new, 1)


def between(start, end, new, label):
    global s
    a = s.find(start)
    if a < 0:
        raise SystemExit(f'{label}: start marker not found')
    b = s.find(end, a)
    if b < 0:
        raise SystemExit(f'{label}: end marker not found')
    s = s[:a] + new + s[b:]


# 1) Styling: four-item navigation, no global add/settings buttons,
#    and a clean "Mehr" launcher page.
css_marker = '/* /JGW AREA MASTER DATA */\n\n</style>'
css_patch = '''/* /JGW AREA MASTER DATA */

/* JGW SIMPLIFIED NAVIGATION */
#quickAddPlant,#settingsGear{display:none!important}
.dashboard-quick{display:none!important}
.more-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px;margin-top:14px}
.more-card{width:100%;min-height:92px;border:1px solid var(--line);border-radius:18px;background:linear-gradient(180deg,#fffdf9,#faf5ed);color:var(--forest-dark);padding:15px;text-align:left;display:grid;grid-template-columns:auto minmax(0,1fr);gap:12px;align-items:center;box-shadow:0 5px 14px rgba(80,100,72,.07)}
.more-card:active{transform:scale(.988)}
.more-icon{width:46px;height:46px;border-radius:14px;display:grid;place-items:center;background:#eef5e8;border:1px solid #dce7d5;font-size:23px}
.more-card b{display:block;font-size:15px;color:var(--forest-dark)}
.more-card small{display:block;color:var(--muted);font-size:11px;line-height:1.4;margin-top:3px}
@media(max-width:700px){.tabs{grid-template-columns:repeat(4,minmax(0,1fr))}.more-grid{grid-template-columns:1fr}.more-card{min-height:82px}}
/* /JGW SIMPLIFIED NAVIGATION */

</style>'''
once(css_marker, css_patch, 'simplified navigation CSS')

# 2) Replace the five primary tabs by the four agreed areas.
new_nav = '''  <nav class="tabs" aria-label="Hauptnavigation">
    <button class="tab active" data-view="today" type="button"><span class="navicon" aria-hidden="true"><svg viewBox="0 0 24 24"><path d="M3.5 11.2 12 4l8.5 7.2"/><path d="M5.5 10v9h13v-9"/><path d="M9.5 19v-5h5v5"/></svg></span><span>Garten</span></button>
    <button class="tab" data-view="plants" type="button"><span class="navicon" aria-hidden="true"><svg viewBox="0 0 24 24"><path d="M12 20V9"/><path d="M12 12C7.7 12 5 9.5 5 5.5c4.3 0 7 2.5 7 6.5Z"/><path d="M12 15c4.3 0 7-2.5 7-6.5-4.3 0-7 2.5-7 6.5Z"/></svg></span><span>Pflanzen</span></button>
    <button class="tab" data-view="calendar" type="button"><span class="navicon" aria-hidden="true"><svg viewBox="0 0 24 24"><path d="M5 5h14v14H5z"/><path d="M8 9h8M8 13h8M8 17h5"/></svg></span><span>Aufgaben</span></button>
    <button class="tab" data-view="more" type="button"><span class="navicon" aria-hidden="true"><svg viewBox="0 0 24 24"><circle cx="5" cy="12" r="1.5"/><circle cx="12" cy="12" r="1.5"/><circle cx="19" cy="12" r="1.5"/></svg></span><span>Mehr</span></button>
  </nav>'''
nav_pattern = r'  <nav class="tabs" aria-label="Hauptnavigation">.*?\n  </nav>'
s, n = re.subn(nav_pattern, new_nav, s, count=1, flags=re.S)
if n != 1:
    raise SystemExit(f'main navigation: expected 1 block, found {n}')

# 3) Plants is now the one obvious place for creating and managing plants.
once(
    '<div class="topline"><div><h2>Naturgarten</h2><div class="muted">Pflanzen, Lebensräume und Tierbeobachtungen – mit deinem Naturgarten-Score an einem Ort.</div></div></div>',
    '<div class="topline"><div><h2>Pflanzen</h2><div class="muted">Alle Pflanzen an einem Ort. Neue Pflanzen legst du hier direkt über „+ Pflanze hinzufügen“ an.</div></div></div>',
    'plants main heading')
once('<button class="btn" id="newPlantBtn" type="button">+ Pflanze</button>',
     '<button class="btn" id="newPlantBtn" type="button">+ Pflanze hinzufügen</button>',
     'plant add button label')
once('Noch keine Pflanzen angelegt. Mit dem <b>+</b> oben kannst du direkt starten.',
     'Noch keine Pflanzen angelegt. Unter <b>„Pflanzen“</b> kannst du die erste Pflanze hinzufügen.',
     'empty task plant hint')

# 4) Move the existing open-task card out of Garten and into Aufgaben.
task_block = '''  <div class="box dashboard-task-box">
    <div class="topline"><div><h3>Heute zu tun</h3><div class="muted">Das Wichtigste zuerst – erledigte Aufgaben verschwinden direkt.</div></div><span class="dashboard-task-count" id="taskCount"></span></div>
    <div id="tasks" class="tasklist"></div>
    <div class="dashboard-quick">
      <div class="dashboard-quick-title">Schnell hinzufügen</div>
      <div class="dashboard-actions" aria-label="Schnell hinzufügen">
        <button class="dashboard-action" id="addPlantToday" type="button"><span aria-hidden="true">🌿</span><b>Pflanze</b></button>
        <button class="dashboard-action" id="addHabitatToday" type="button"><span aria-hidden="true">🪵</span><b>Lebensraum</b></button>
        <button class="dashboard-action" id="addAnimalToday" type="button"><span aria-hidden="true">🦋</span><b>Tier</b></button>
      </div>
    </div>
  </div>
'''
once(task_block, '', 'remove task card from garden')
task_block_tasks = task_block.replace('<h3>Heute zu tun</h3>', '<h3>Offene Aufgaben</h3>')
once('<section class="view" id="view-calendar">\n  <div class="box">',
     '<section class="view" id="view-calendar">\n' + task_block_tasks + '  <div class="box">',
     'task card into tasks view')
once('<div class="topline"><div><h2>Pflegekalender</h2><div class="muted">Zuerst siehst du nur die nächsten relevanten Monate. Gießen bleibt in „Heute“.</div></div></div>',
     '<div class="topline"><div><h2>Pflegekalender</h2><div class="muted">Düngen und Schneiden im Jahresverlauf. Gieß- und Tagesaufgaben stehen direkt darüber.</div></div></div>',
     'task calendar wording')

# 5) Add the More hub while keeping the established map/weather/settings views intact.
more_view = '''<section class="view" id="view-more">
  <div class="box">
    <div class="topline"><div><h2>Mehr</h2><div class="muted">Karte, Wetter und selten benötigte Einstellungen sind hier gebündelt.</div></div></div>
    <div class="more-grid">
      <button class="more-card" id="moreMapBtn" type="button"><span class="more-icon" aria-hidden="true">🗺️</span><span><b>Gartenkarte</b><small>Pflanzen, Gartenbereiche und Standorte im Luftbild anzeigen.</small></span></button>
      <button class="more-card" id="moreWeatherBtn" type="button"><span class="more-icon" aria-hidden="true">🌦️</span><span><b>Wetter &amp; Regen</b><small>Regenhistorie, Wasserbilanz und 7-Tage-Ausblick öffnen.</small></span></button>
      <button class="more-card" id="moreSettingsBtn" type="button"><span class="more-icon" aria-hidden="true">⚙️</span><span><b>Einstellungen</b><small>Standort, Gartenbereiche, Pflanzenerkennung, Darstellung und Backup.</small></span></button>
      <button class="more-card" id="moreSyncBtn" type="button"><span class="more-icon" aria-hidden="true">☁️</span><span><b>Geräte &amp; Synchronisation</b><small>Garten-ID, Geräteverbindung und gemeinsamen Datenstand verwalten.</small></span></button>
    </div>
  </div>
</section>

'''
once('<div class="settings-overlay hidden" id="settingsOverlay" aria-hidden="true">',
     more_view + '<div class="settings-overlay hidden" id="settingsOverlay" aria-hidden="true">',
     'more view')

# 6) Internal map/weather views belong to More in the four-tab navigation.
new_switch = '''function switchView(name){closeSettings();document.querySelectorAll(".view").forEach(function(v){v.classList.toggle("active",v.id==="view-"+name)});var navName=(name==="map"||name==="weather")?"more":name;document.querySelectorAll(".tab").forEach(function(b){b.classList.toggle("active",b.dataset.view===navName)});if(name==="map"){setTimeout(function(){initMap();if(state.map)state.map.invalidateSize();var forced=!!(state.placePlantId||state.placePlantAddId||state.setCenterMode);if(!state.settings.mapView||forced)setMapEditing(true);else{applySavedMapView();setMapEditing(false)}renderMap()},40)}if(name==="calendar")renderCalendar();if(name==="plants")renderPlants()}'''
between('function switchView(name){', '\nfunction currentZoneForPlant', new_switch, 'switchView navigation parent')

# 7) Saving a plant returns to Plants and immediately shows the saved plant.
new_save_plant = '''function savePlant(placeAfter){try{var p=plantFromForm(),idx=state.plants.findIndex(function(x){return x.id===p.id}),wasExisting=idx>=0;if(wasExisting)state.plants[idx]=p;else state.plants.push(p);if(!save())return null;show("plantEditor",false);renderAll();if(placeAfter)beginPlacePlant(p.id);else{switchView("plants");setNatureTab("plants",false);setTimeout(function(){openPlantDetail(p.id);notice(wasExisting?"Pflanze gespeichert.":"Pflanze hinzugefügt.")},70)}return p}catch(e){globalError(e.message);return null}}'''
between('function savePlant(placeAfter){', '\nvar plantNameSearchTimer', new_save_plant, 'plant save return flow')

# 8) Main Plants button always means the plant collection, not the last nature sub-tab.
once('document.querySelectorAll(".tab").forEach(function(b){b.addEventListener("click",function(){switchView(b.dataset.view)})});',
     'document.querySelectorAll(".tab").forEach(function(b){b.addEventListener("click",function(){var v=b.dataset.view;switchView(v);if(v==="plants")setNatureTab("plants")})});',
     'main tab click behavior')

# More launchers.
more_bindings = '''el("moreMapBtn").addEventListener("click",function(){switchView("map")});
el("moreWeatherBtn").addEventListener("click",function(){switchView("weather")});
el("moreSettingsBtn").addEventListener("click",function(){openSettings()});
el("moreSyncBtn").addEventListener("click",function(){openSettings("settingsSync")});
'''
once('el("refreshWeather").addEventListener("click",function(){refreshWeather(true)});',
     more_bindings + 'el("refreshWeather").addEventListener("click",function(){refreshWeather(true)});',
     'more launcher bindings')

# Static sanity checks before writing.
nav = re.search(r'<nav class="tabs" aria-label="Hauptnavigation">(.*?)</nav>', s, re.S)
assert nav, 'navigation missing after patch'
assert nav.group(1).count('class="tab') == 4, 'navigation must contain exactly four tabs'
for label in ('Garten', 'Pflanzen', 'Aufgaben', 'Mehr'):
    assert f'<span>{label}</span>' in nav.group(1), label
assert 'data-view="map"' not in nav.group(1)
assert 'data-view="weather"' not in nav.group(1)
assert s.count('id="taskCount"') == 1
assert s.count('id="tasks"') == 1
assert '+ Pflanze hinzufügen' in s
assert 'id="view-more"' in s
assert 'id="moreMapBtn"' in s and 'id="moreWeatherBtn"' in s and 'id="moreSettingsBtn"' in s
assert 'openPlantDetail(p.id);notice(wasExisting?' in s
assert '#quickAddPlant,#settingsGear{display:none!important}' in s

path.write_text(s, encoding='utf-8')
print('simplified navigation patch applied')
