from pathlib import Path
import re
import json
import math
import struct
import zlib

path = Path('index.html')
s = path.read_text(encoding='utf-8')

assert '/* JGW UX V3 */' not in s, 'UX V3 already applied'

def sub_once(pattern, repl, text=None, flags=0, label='pattern'):
    global s
    src = s if text is None else text
    out, n = re.subn(pattern, repl, src, count=1, flags=flags)
    assert n == 1, f'{label}: expected exactly one match, got {n}'
    if text is None:
        s = out
    return out

# PWA/head metadata.
assert '<meta name="theme-color" content="#8faa7e">' in s
s = s.replace('<meta name="theme-color" content="#8faa7e">', '<meta id="themeColor" name="theme-color" content="#8faa7e">', 1)
assert '<title>Johanna´s Gartenwelt</title>' in s
s = s.replace(
    '<title>Johanna´s Gartenwelt</title>',
    '<title>Johanna´s Gartenwelt</title>\n<link rel="manifest" href="./manifest.webmanifest">\n<link rel="icon" href="./app-icon.svg" type="image/svg+xml">\n<link rel="apple-touch-icon" href="./app-icon-180.png">',
    1,
)

# Focused UX styles: bottom navigation, compact forms/cards, toast, first-run guide.
css = r'''
/* JGW UX V3 */
#globalNotice.toast-message{position:fixed;left:50%;bottom:24px;transform:translateX(-50%);z-index:8400;width:auto;max-width:calc(100vw - 28px);margin:0;padding:10px 15px;border-radius:999px;background:#4e443a;color:white;border:0;box-shadow:0 12px 30px rgba(40,35,31,.23);font-size:13px;line-height:1.35}
.setup-guide{background:linear-gradient(135deg,rgba(255,253,249,.98),rgba(242,248,239,.98));border:1px solid var(--line);border-radius:22px;padding:17px;margin-top:16px;box-shadow:var(--shadow)}
.setup-guide-head{display:flex;align-items:flex-start;justify-content:space-between;gap:12px}.setup-guide h2{margin:0;color:var(--forest-dark);font-size:21px}.setup-guide-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:9px;margin-top:12px}.setup-step{border:1px solid var(--line);border-radius:15px;padding:12px;background:rgba(255,255,255,.7)}.setup-step.done{background:var(--ok);opacity:.82}.setup-step b{display:block;color:var(--forest-dark);margin-bottom:4px}.setup-step small{display:block;color:var(--muted);line-height:1.35;margin-bottom:9px}.setup-step .step-state{font-size:10px;text-transform:uppercase;letter-spacing:.06em;font-weight:800;color:var(--muted)}
.plant-quick-note{margin:7px 0 11px;padding:9px 11px;border-radius:12px;background:var(--ok);color:var(--forest-dark);font-size:12px;line-height:1.4}.plant-advanced{margin-top:13px;border:1px solid var(--line);border-radius:14px;padding:11px 12px;background:rgba(255,255,255,.58)}.plant-advanced>summary{font-size:13px}.plantcard-main{display:block;width:100%;padding:0;border:0;background:transparent;text-align:left;color:inherit;cursor:pointer}.plantcard-main:focus-visible{outline:3px solid rgba(86,122,87,.26);outline-offset:-3px}.plant-more{margin:0 13px 13px;border-top:1px solid #f0e7dd;padding-top:8px}.plant-more>summary{list-style:none;width:38px;height:34px;margin-left:auto;border:1px solid var(--line);border-radius:999px;display:grid;place-items:center;background:#fffdf9;font-size:17px}.plant-more>summary::-webkit-details-marker{display:none}.plant-more-actions{display:flex;gap:7px;flex-wrap:wrap;justify-content:flex-end;margin-top:8px}
.calendar-tools{margin-top:14px;border-top:1px solid var(--line);padding-top:10px}.calendar-tools>summary{font-size:13px}.calendar-now{margin-top:14px}.calendar-now .calmonth:first-child{border-color:rgba(86,122,87,.35);box-shadow:0 7px 18px rgba(86,122,87,.09)}
@media(max-width:700px){
  body{padding-bottom:calc(76px + env(safe-area-inset-bottom))}
  .wrap{padding-bottom:12px}
  .head{padding-bottom:14px}
  .tabs{position:fixed;left:0;right:0;bottom:0;z-index:4000;margin:0;padding:6px 6px calc(6px + env(safe-area-inset-bottom));display:grid;grid-template-columns:repeat(5,1fr);gap:3px;background:rgba(255,253,249,.94);backdrop-filter:blur(14px);border-top:1px solid var(--line);box-shadow:0 -8px 26px rgba(54,49,44,.10);overflow:visible}
  .tab{min-width:0;border:0;background:transparent;box-shadow:none;border-radius:13px;padding:6px 2px 5px;display:grid;place-items:center;gap:1px;font-size:10.5px;line-height:1.1;font-weight:700;color:var(--muted)}
  .tab.active{background:var(--ok);color:var(--forest-dark)}
  .navicon{font-size:17px;line-height:1.05;font-weight:400}
  #globalNotice.toast-message,.undo-toast{bottom:calc(82px + env(safe-area-inset-bottom))}
  .setup-guide-grid{grid-template-columns:1fr}.setup-step{display:grid;grid-template-columns:1fr auto;column-gap:9px}.setup-step small{grid-column:1/-1}.setup-step .step-state{align-self:center}
  .plant-quick-note{margin-top:4px}.plant-advanced{padding:10px}.calendar{grid-template-columns:1fr}
  .brand h1{font-size:22px;white-space:nowrap}.brandtools{gap:5px}.gearbtn,.quickbtn{width:38px;height:38px}.syncmini{height:38px;min-width:38px;padding:0 7px}.seasonmark{display:none}
}
@media(max-width:380px){.syncmini{display:none}.brand h1{font-size:20px}.head{padding-left:12px;padding-right:12px}}
'''
assert '</style>' in s
s = s.replace('</style>', css + '\n</style>', 1)

# App-like navigation with compact icons.
sub_once(
    r'<nav class="tabs" aria-label="Bereiche">.*?</nav>',
    '''<nav class="tabs" aria-label="Hauptnavigation">\n    <button class="tab active" data-view="today" type="button"><span class="navicon" aria-hidden="true">⌂</span><span>Heute</span></button>\n    <button class="tab" data-view="plants" type="button"><span class="navicon" aria-hidden="true">🌿</span><span>Pflanzen</span></button>\n    <button class="tab" data-view="map" type="button"><span class="navicon" aria-hidden="true">⌖</span><span>Karte</span></button>\n    <button class="tab" data-view="calendar" type="button"><span class="navicon" aria-hidden="true">▦</span><span>Kalender</span></button>\n    <button class="tab" data-view="weather" type="button"><span class="navicon" aria-hidden="true">☁</span><span>Wetter</span></button>\n  </nav>''',
    flags=re.S,
    label='main navigation',
)

# Normal confirmations become non-disruptive bottom toasts.
assert '<div id="globalNotice" class="box notice hidden"></div>' in s
s = s.replace('<div id="globalNotice" class="box notice hidden"></div>', '<div id="globalNotice" class="toast-message hidden" role="status" aria-live="polite"></div>', 1)

# First-run checklist, non-blocking and automatically hidden when complete.
anchor = '<section class="view active" id="view-today">'
assert anchor in s
setup_guide = '''<section class="setup-guide hidden" id="setupGuide" aria-label="Ersteinrichtung">\n  <div class="setup-guide-head"><div><h2>In drei Schritten startklar</h2><div class="muted">Nur beim ersten Einrichten. Bereits erledigte Schritte verschwinden automatisch.</div></div><button class="btn ghost small" id="setupDismiss" type="button">Ausblenden</button></div>\n  <div class="setup-guide-grid">\n    <div class="setup-step" id="setupStepLocation"><div><b>1 · Standort</b><small>PLZ für Wetter und Gießempfehlungen hinterlegen.</small></div><span class="step-state" id="setupLocationState">offen</span><button class="btn secondary small" id="setupLocationBtn" type="button">Standort</button></div>\n    <div class="setup-step" id="setupStepMap"><div><b>2 · Gartenkarte</b><small>Einmal den passenden Luftbildausschnitt festlegen.</small></div><span class="step-state" id="setupMapState">offen</span><button class="btn secondary small" id="setupMapBtn" type="button">Ausschnitt</button></div>\n    <div class="setup-step" id="setupStepPlant"><div><b>3 · Erste Pflanze</b><small>Foto, Name und Gartenbereich reichen für den Start.</small></div><span class="step-state" id="setupPlantState">offen</span><button class="btn secondary small" id="setupPlantBtn" type="button">Pflanze</button></div>\n  </div>\n</section>\n\n'''
s = s.replace(anchor, setup_guide + anchor, 1)

# Map: one stored viewport, whose centre is automatically the weather position.
s = s.replace('Gartenausschnitt einmal festlegen:</b> Karte verschieben und zoomen, bis dein Garten gut sichtbar ist. Danach „Ausschnitt speichern“ wählen.', 'Gartenausschnitt einmal festlegen:</b> Karte verschieben und zoomen, bis dein Garten gut sichtbar ist. Beim Speichern wird die Kartenmitte automatisch als Wetterposition verwendet.', 1)
s = s.replace('        <button class="btn ghost" id="setGardenCenterBtn" type="button">Gartenmitte setzen</button>\n', '', 1)
s = s.replace('Für Wetter und Gießempfehlungen genügt die Postleitzahl. Die genaue Gartenmitte kann bei Bedarf auf der Karte gesetzt werden.', 'Für Wetter und Gießempfehlungen genügt die Postleitzahl. Die genaue Wetterposition ergibt sich automatisch aus dem gespeicherten Gartenausschnitt.', 1)
s = s.replace('<button class="btn ghost small" id="openGardenCenter" type="button">Gartenmitte auf Karte</button>', '', 1)

# Plant editor: daily path is photo + name + area; everything else is optional.
plant_form = '''<form id="plantForm">\n      <input type="hidden" id="plantId">\n      <div class="plant-quick-note"><b>Schnell anlegen:</b> Foto, Pflanzenname und Gartenbereich reichen. Alle weiteren Angaben sind optional.</div>\n      <div class="formgrid">\n        <div class="field full">\n          <label for="plantPhoto">Foto</label>\n          <div style="display:flex;gap:12px;align-items:flex-start;flex-wrap:wrap"><div class="photo-preview" id="photoPreview">Foto</div><div style="flex:1;min-width:220px"><input id="plantPhoto" type="file" accept="image/*" capture="environment"><div class="actions" style="margin-top:8px"><button type="button" class="btn secondary small" id="identifyBtn">Mit KI erkennen</button></div><div class="muted" id="aiStatus" style="margin-top:7px">Foto aufnehmen und auf Wunsch automatisch erkennen lassen.</div><div id="aiResults" class="airesults"></div></div></div>\n        </div>\n        <div class="field"><label for="plantName">Pflanzenname *</label><input id="plantName" required placeholder="z. B. Hortensie"></div>\n        <div class="field"><label for="plantArea">Gartenbereich</label><input id="plantArea" placeholder="z. B. Vorgarten"></div>\n      </div>\n      <details class="plant-advanced" id="plantAdvanced">\n        <summary>Weitere Angaben</summary>\n        <div class="formgrid" style="margin-top:11px">\n          <div class="field"><label for="plantScientific">Botanischer Name</label><input id="plantScientific" placeholder="z. B. Hydrangea macrophylla"></div>\n          <div class="field"><label for="plantType">Pflanzung</label><select id="plantType"><option value="bed" selected>Direkt im Gartenboden (Standard)</option><option value="pot">Kübel / Topf</option><option value="raised">Hochbeet</option><option value="balcony">Balkonkasten</option><option value="other">Sonstige Pflanzung</option></select></div>\n          <div class="field"><label for="plantWater">Wasserbedarf</label><select id="plantWater"><option value="low">Niedrig</option><option value="normal" selected>Normal</option><option value="high">Hoch</option></select></div>\n          <div class="field"><label for="plantSize">Pflanzengröße</label><select id="plantSize"><option value="small">Klein</option><option value="medium" selected>Mittel</option><option value="large">Groß</option></select></div>\n          <div class="field"><label for="plantBirthYear">Pflanz-/Anzuchtjahr (ca.)</label><input id="plantBirthYear" type="number" inputmode="numeric" min="1900" max="2100" placeholder="z. B. 2024"></div>\n          <div class="field"><label for="plantSince">Am aktuellen Standort seit</label><input id="plantSince" type="date"><div class="muted">Optional – wichtig für die Anwachsphase.</div></div>\n          <div class="field"><label for="plantTransplanted">Zuletzt umgepflanzt / umgetopft</label><input id="plantTransplanted" type="date"><div class="muted">Leer lassen, wenn unbekannt oder nie.</div></div>\n          <div class="field"><label for="plantOrgan">Foto zeigt</label><select id="plantOrgan"><option value="auto">Automatisch</option><option value="leaf">Blatt</option><option value="flower">Blüte</option><option value="fruit">Frucht</option><option value="bark">Rinde</option><option value="habit">Gesamtpflanze</option></select></div>\n          <div class="field full"><label>Düngemonate</label><div class="monthrow" id="fertMonths"></div></div>\n          <div class="field full"><label>Schnittmonate</label><div class="monthrow" id="cutMonths"></div></div>\n          <div class="field full"><label for="plantNotes">Notizen</label><textarea id="plantNotes" placeholder="Besonderheiten, Sorte, Pflanzjahr …"></textarea></div>\n        </div>\n      </details>\n      <div class="actions" style="margin-top:14px"><button class="btn" type="submit">Speichern</button><button class="btn secondary" id="saveAndPlaceBtn" type="button">Speichern & auf Karte setzen</button></div>\n    </form>'''
sub_once(r'<form id="plantForm">.*?</form>', plant_form, flags=re.S, label='plant form')

# Calendar: show current + next two months, exports tucked away.
calendar_section = '''<section class="view" id="view-calendar">\n  <div class="box">\n    <div class="topline"><div><h2>Pflegekalender</h2><div class="muted">Zuerst siehst du nur die nächsten relevanten Monate. Gießen bleibt in „Heute“.</div></div></div>\n    <div class="calendar calendar-now" id="calendarGrid"></div>\n    <div class="actions" style="margin-top:12px"><button class="btn secondary small" id="calendarToggle" type="button">Ganzes Pflegejahr anzeigen</button></div>\n    <details class="calendar-tools">\n      <summary>Kalender exportieren</summary>\n      <div style="margin-top:11px"><div class="label">Saison als Kalenderdatei</div><div class="actions" id="seasonExports" style="margin-top:8px"></div></div>\n      <div style="margin-top:11px"><button class="btn secondary small" id="exportCareYear" type="button">Nächste 12 Monate als .ics</button></div>\n    </details>\n  </div>\n</section>'''
sub_once(r'<section class="view" id="view-calendar">.*?</section>', calendar_section, flags=re.S, label='calendar section')

# Add onboarding preference to local-only UI settings.
assert 'settings:{plantnetKey:DEFAULT_PLANTNET_KEY,seasonMode:"auto",animations:true,mapView:null}' in s
s = s.replace('settings:{plantnetKey:DEFAULT_PLANTNET_KEY,seasonMode:"auto",animations:true,mapView:null}', 'settings:{plantnetKey:DEFAULT_PLANTNET_KEY,seasonMode:"auto",animations:true,mapView:null,onboardingDismissed:false}', 1)
assert 'Object.assign({plantnetKey:DEFAULT_PLANTNET_KEY,seasonMode:"auto",animations:true,mapView:null},d.settings||{})' in s
s = s.replace('Object.assign({plantnetKey:DEFAULT_PLANTNET_KEY,seasonMode:"auto",animations:true,mapView:null},d.settings||{})', 'Object.assign({plantnetKey:DEFAULT_PLANTNET_KEY,seasonMode:"auto",animations:true,mapView:null,onboardingDismissed:false},d.settings||{})', 1)

# Seasonal browser chrome follows the chosen/current season.
new_apply = '''function applyAppearance(){var key=currentSeason(),info=seasonInfo(key);document.body.dataset.season=key;var mark=el("seasonMark");if(mark){mark.textContent=info.icon;mark.title=info.label}var sm=el("seasonMode");if(sm)sm.value=state.settings.seasonMode||"auto";var at=el("animationToggle");if(at)at.checked=state.settings.animations!==false;var st=el("seasonStatus");if(st)st.textContent=(state.settings.seasonMode||"auto")==="auto"?"Aktuell: "+info.label+" · Wechsel automatisch am 1. März, 1. Juni, 1. September und 1. Dezember.":"Manuell gewählt: "+info.label+".";var tc=el("themeColor"),colors={spring:"#567f5a",summer:"#4f7a4e",autumn:"#68734e",winter:"#607873"};if(tc)tc.setAttribute("content",colors[key]||"#567a57")}\n'''
sub_once(r'function applyAppearance\(\)\{.*?\}\n(?=function renderSyncMini)', new_apply, flags=re.S, label='appearance function')

# Plain-language garden status on Today.
new_summary = '''function gardenWeatherSummary(){if(!state.weather)return null;var rows=weatherRows(),t=isoToday(),past=rows.filter(function(x){return x.date<t}).slice(-30),r14=past.slice(-14),fc=rows.filter(function(x){return x.date>=t}).slice(0,7);var rain14=r14.reduce(function(s,x){return s+x.rain},0),et14=r14.reduce(function(s,x){return s+x.et0},0),balance=rain14-et14,dryDays=0;for(var i=past.length-1;i>=0;i--){if(past[i].rain>=2)break;dryDays++}var levels=[{name:"Nass",cls:"state-wet",text:"Der Garten hat reichlich Wasser bekommen. Gießen ist meist nicht nötig."},{name:"Feucht",cls:"state-moist",text:"Der Boden dürfte derzeit gut mit Feuchtigkeit versorgt sein."},{name:"Ausgeglichen",cls:"state-balanced",text:"Regen und Trockenheit halten sich derzeit ungefähr die Waage."},{name:"Eher trocken",cls:"state-dryish",text:"Es wird trockener. Empfindliche Pflanzen am besten im Blick behalten."},{name:"Trocken",cls:"state-dry",text:"Die Trockenphase macht sich bemerkbar. Durstige Pflanzen sollten geprüft werden."},{name:"Sehr trocken",cls:"state-verydry",text:"Der Garten ist deutlich ausgetrocknet. Pflanzen mit hohem Wasserbedarf besonders prüfen."}],idx;if(balance>=20||rain14>=45)idx=0;else if(balance>=5||rain14>=30)idx=1;else if(balance>-8)idx=2;else if(balance>-22)idx=3;else if(balance>-38)idx=4;else idx=5;if(dryDays>=10&&idx<3)idx=3;if(dryDays>=18&&idx<4)idx=4;var nextRain=null;for(var j=0;j<fc.length;j++){if(fc[j].rain>=2){nextRain=fc[j];break}}var frost=null;for(var k=0;k<Math.min(4,fc.length);k++){if(fc[k].min<=0){frost=fc[k];break}}return{name:levels[idx].name,cls:levels[idx].cls,balance:balance,dryDays:dryDays,nextRain:nextRain,frost:frost,explanation:levels[idx].text}}\n'''
sub_once(r'function gardenWeatherSummary\(\)\{.*?\}\n(?=function mapInteraction)', new_summary, flags=re.S, label='garden summary')

# Map save also defines weather position; no second "garden centre" concept required.
new_save_map = '''function saveMapViewport(){if(!state.map)return;var c=state.map.getCenter();state.settings.mapView={lat:c.lat,lon:c.lng,zoom:state.map.getZoom()};state.gardenCenter={lat:c.lat,lon:c.lng};save();setMapEditing(false);renderOnboardingGuide();notice("Gartenausschnitt gespeichert. Die Kartenmitte wird auch für das Wetter verwendet.");if(state.plz)refreshWeather(false)}\n'''
sub_once(r'function saveMapViewport\(\)\{.*?\}\n(?=function toggleMapEditing)', new_save_map, flags=re.S, label='save map viewport')

# Simpler task explanations; detailed measurements remain in Weather.
new_water = '''function waterAssessment(p){if(!state.weather)return{level:"warn",title:"Wetter fehlt",reason:"Wetterdaten laden, um eine Gießempfehlung zu erhalten.",score:0};var all=weatherRows(),t=isoToday(),past=all.filter(function(x){return x.date<t}).slice(-7),future=all.filter(function(x){return x.date>=t}).slice(0,2);var rain=past.reduce(function(s,x){return s+x.rain},0),et0=past.reduce(function(s,x){return s+x.et0},0),fRain=future.reduce(function(s,x){return s+x.rain},0);var z=currentZoneForPlant(p);var light={fullsun:1.30,sunny:1.15,partial:.90,shade:.72};var rainF={open:1,partial:.72,protected:.42};var soil={normal:1,dry:1.18,moist:.82};var water={low:.72,normal:1,high:1.28};var type={bed:1,raised:1.20,pot:1.55,balcony:1.70,other:1.10};var size={small:.82,medium:1,large:1.28};var lf=z?light[z.light]||1:1,rf=z?rainF[z.rain]||1:1,sf=z?soil[z.soil]||1:1;var est=establishmentInfo(p),af=ageFactor(p),sz=size[p.size]||1;var score=(et0*(water[p.water]||1)*(type[p.type]||1)*lf*sf*est.factor*af*sz)-(rain*rf);var since=999;if(p.lastWatered){since=Math.max(0,Math.round((dateObj(t)-dateObj(p.lastWatered))/86400000));if(since===0)score-=12;else if(since===1)score-=8;else if(since===2)score-=4}if(fRain>=12)score-=7;else if(fRain>=6)score-=3;var isContainer=p.type==="pot"||p.type==="balcony"||p.type==="raised";var level="ok",title="Heute voraussichtlich nicht gießen";if(score>10||(isContainer&&since>=4&&rain<5)){level="bad";title="Gießen empfohlen"}else if(score>5||(isContainer&&since>=2&&rain<3)){level="warn";title="Feuchtigkeit prüfen"}if(est.days<=90&&level==="ok"&&rain<8){level="warn";title="Anwachsphase: Feuchtigkeit prüfen"}if(fRain>=12&&level==="bad"&&est.days>30){level="warn";title="Regen abwarten / Feuchtigkeit prüfen"}var reason;if(fRain>=12){reason="Bald ist kräftiger Regen angekündigt. Vorher nur gießen, wenn die Erde wirklich trocken ist."}else if(level==="bad"){reason="Die letzten Tage und der Standort sprechen für trockene Erde. Heute kurz prüfen und bei Bedarf gründlich gießen."}else if(level==="warn"){reason=est.days<=90?"Die Pflanze ist noch in der Anwachsphase. Die Erde sollte gleichmäßig leicht feucht bleiben.":"Die Erde könnte trockener werden. Eine kurze Fingerprobe reicht zur Kontrolle."}else{reason="Die vorhandene Feuchtigkeit reicht voraussichtlich aus."}if(z&&z.rain==="protected")reason+=" Der Standort liegt zusätzlich im Regenschatten.";return{level:level,title:title,score:score,reason:reason}}\n'''
sub_once(r'function waterAssessment\(p\)\{.*?\}\n(?=function lightLabel)', new_water, flags=re.S, label='water assessment')

# Plant cards: tap main card to edit; secondary/destructive actions live behind a quiet menu.
new_render_plants = '''function renderPlants(){var list=el("plantList"),q=String(el("plantSearch")?el("plantSearch").value:"").trim().toLowerCase();if(!state.plants.length){list.innerHTML='<div class="box empty" style="grid-column:1/-1">Noch keine Pflanzen gespeichert.</div>';return}var plants=state.plants.filter(function(p){return !q||String(p.name||"").toLowerCase().includes(q)||String(p.scientific||"").toLowerCase().includes(q)||String(p.area||"").toLowerCase().includes(q)});if(!plants.length){list.innerHTML='<div class="box empty" style="grid-column:1/-1">Keine passende Pflanze gefunden.</div>';return}list.innerHTML=plants.map(function(p){var wa=waterAssessment(p),z=currentZoneForPlant(p),photo=p.photo?'<img src="'+p.photo+'" alt="'+esc(p.name)+'">':'🌿',area=p.area?esc(p.area):(z?esc(lightLabel(z.light)):"Standort noch nicht benannt");return '<article class="plantcard"><button class="plantcard-main plantOpen" data-id="'+p.id+'" type="button" aria-label="'+esc(p.name)+' öffnen"><div class="plantphoto">'+photo+'</div><div class="plantbody"><div class="plantname"><span class="statusdot '+wa.level+'"></span>'+esc(p.name)+'</div><div class="plant-summary">'+area+' · <b>'+esc(wa.title)+'</b></div></div></button><details class="plant-more"><summary aria-label="Weitere Aktionen">•••</summary><div class="plant-more-actions"><button class="btn secondary small editPlant" data-id="'+p.id+'" type="button">Bearbeiten</button><button class="btn secondary small placePlant" data-id="'+p.id+'" type="button">'+(p.lat?"Position ändern":"Auf Karte setzen")+'</button><button class="btn ghost small deletePlant" data-id="'+p.id+'" type="button">Löschen</button></div></details></article>'}).join("");document.querySelectorAll(".plantOpen,.editPlant").forEach(function(b){b.addEventListener("click",function(){openPlantEditor(b.dataset.id)})});document.querySelectorAll(".placePlant").forEach(function(b){b.addEventListener("click",function(){beginPlacePlant(b.dataset.id)})});document.querySelectorAll(".deletePlant").forEach(function(b){b.addEventListener("click",function(){deletePlantWithUndo(b.dataset.id)})})}\n'''
sub_once(r'function renderPlants\(\)\{.*?\}\n(?=function buildMonthChecks)', new_render_plants, flags=re.S, label='render plants')

# Advanced plant data stays closed for new plants, opens automatically when editing an existing one.
s = s.replace('setCheckedMonths("fert",[]);setCheckedMonths("cut",[])}\nfunction openPlantEditor', 'setCheckedMonths("fert",[]);setCheckedMonths("cut",[]);if(el("plantAdvanced"))el("plantAdvanced").open=false}\nfunction openPlantEditor', 1)
s = s.replace('el("plantEditorTitle").textContent=p?"Pflanze bearbeiten":"Pflanze hinzufügen";if(p){', 'el("plantEditorTitle").textContent=p?"Pflanze bearbeiten":"Pflanze hinzufügen";if(el("plantAdvanced"))el("plantAdvanced").open=!!p;if(p){', 1)

# Calendar is initially just three months; detailed export remains available.
new_calendar = '''var calendarExpanded=false;\nfunction renderCalendar(){var months=nextTwelveMonths(),shown=calendarExpanded?months:months.slice(0,3),seasonKeys=["spring","summer","autumn","winter"];el("seasonExports").innerHTML=seasonKeys.map(function(k){var sw=seasonWindow(k);return '<button class="btn secondary small seasonExport" data-season="'+k+'" type="button">'+esc(sw.label)+'.ics</button>'}).join("");document.querySelectorAll(".seasonExport").forEach(function(b){b.addEventListener("click",function(){var sw=seasonWindow(b.dataset.season);downloadCareICS(sw.months,"Johannas_Gartenwelt_"+sw.label.replace(/[^a-zA-Z0-9äöüÄÖÜß_-]+/g,"_")+".ics","Johanna´s Gartenwelt – "+sw.label)})});el("calendarGrid").innerHTML=shown.map(function(mm,idx){var d=new Date(mm.y,mm.m-1,1),label=d.toLocaleDateString("de-DE",{month:"long",year:"numeric"}),items=careItemsForMonth(mm.m);return '<div class="calmonth"><div class="topline"><h3>'+(idx===0?'Jetzt · ':'')+esc(label)+'</h3></div>'+(items.length?items.map(function(x){return '<div class="calitem"><b>'+(x.kind==="fert"?'🌱':'✂️')+' '+esc(x.plant.name)+'</b>'+(x.kind==="fert"?'Düngen':'Schnitt prüfen')+'</div>'}).join(""):'<div class="muted">Keine saisonalen Pflegeaufgaben hinterlegt.</div>')+'</div>'}).join("");var bt=el("calendarToggle");if(bt)bt.textContent=calendarExpanded?"Nur die nächsten 3 Monate":"Ganzes Pflegejahr anzeigen"}\n'''
sub_once(r'function renderCalendar\(\)\{.*?\}\n(?=function ago)', new_calendar, flags=re.S, label='render calendar')

# Keep the centre marker only in edit mode.
s = s.replace('if(state.gardenCenter){L.circleMarker([state.gardenCenter.lat,state.gardenCenter.lon]', 'if(state.gardenCenter&&state.mapEditMode){L.circleMarker([state.gardenCenter.lat,state.gardenCenter.lon]', 1)

# Toast timer and first-run render helper.
sub_once(r'function notice\(msg\)\{.*?\}\n(?=function requestJSON)', 'var noticeTimer=null;\nfunction notice(msg){var n=el("globalNotice");if(!n)return;clearTimeout(noticeTimer);n.textContent=msg;show("globalNotice",true);noticeTimer=setTimeout(function(){show("globalNotice",false)},3000)}\n', flags=re.S, label='notice function')

onboarding_fn = '''function renderOnboardingGuide(){var g=el("setupGuide");if(!g)return;var waitingForCloud=syncState.enabled&&syncConfigured()&&!state.plz&&!state.plants.length,locDone=!!state.plz,mapDone=!!(state.settings&&state.settings.mapView),plantDone=state.plants.length>0,complete=locDone&&mapDone&&plantDone,hidden=!!state.settings.onboardingDismissed||complete||waitingForCloud;show("setupGuide",!hidden);if(hidden)return;[["setupStepLocation","setupLocationState",locDone],["setupStepMap","setupMapState",mapDone],["setupStepPlant","setupPlantState",plantDone]].forEach(function(x){var box=el(x[0]),st=el(x[1]);if(box)box.classList.toggle("done",x[2]);if(st)st.textContent=x[2]?"erledigt":"offen"});var mb=el("setupMapBtn");if(mb)mb.disabled=!locDone}\n'''
assert 'function renderAll(){' in s
s = s.replace('function renderAll(){renderHeader();', onboarding_fn + 'function renderAll(){renderOnboardingGuide();renderHeader();', 1)

# Remove obsolete garden-centre controls/listeners and add new simple actions.
s = s.replace('el("openGardenCenter").addEventListener("click",function(){closeSettings();switchView("map");setTimeout(function(){setMapEditing(true);el("setGardenCenterBtn").click()},100)});\n', '', 1)
s = s.replace('el("setGardenCenterBtn").addEventListener("click",function(){initMap();if(!state.mapReady)return;setMapEditing(true);state.placePlantId=null;state.setCenterMode=true;el("mapModeHint").textContent="Auf die Mitte deines Gartens tippen. Diese Position wird gespeichert und für Wetterdaten verwendet.";show("mapModeHint",true)});\n', '', 1)
listener_anchor = 'el("plantSearch").addEventListener("input",renderPlants);\n'
assert listener_anchor in s
s = s.replace(listener_anchor, listener_anchor + '''el("calendarToggle").addEventListener("click",function(){calendarExpanded=!calendarExpanded;renderCalendar()});\nel("setupLocationBtn").addEventListener("click",function(){openSettings("settingsLocation")});\nel("setupMapBtn").addEventListener("click",function(){switchView("map");setTimeout(function(){setMapEditing(true)},100)});\nel("setupPlantBtn").addEventListener("click",function(){switchView("plants");setTimeout(function(){openPlantEditor(null)},60)});\nel("setupDismiss").addEventListener("click",function(){state.settings.onboardingDismissed=true;save();renderOnboardingGuide()});\n''', 1)

# Write final HTML.
path.write_text(s, encoding='utf-8')

# Manifest.
manifest = {
    'name': 'Johanna´s Gartenwelt',
    'short_name': 'Gartenwelt',
    'start_url': './',
    'scope': './',
    'display': 'standalone',
    'background_color': '#fbf6ef',
    'theme_color': '#567a57',
    'description': 'Persönlicher Gartenplan mit Pflanzenpflege, Wetter und Gießempfehlungen.',
    'icons': [
        {'src': './app-icon-180.png', 'sizes': '180x180', 'type': 'image/png'},
        {'src': './app-icon.svg', 'sizes': 'any', 'type': 'image/svg+xml', 'purpose': 'any maskable'}
    ]
}
Path('manifest.webmanifest').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

# Scalable icon.
svg = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
<rect width="512" height="512" rx="112" fill="#4f7653"/>
<circle cx="256" cy="256" r="174" fill="#fff9ee"/>
<path d="M256 365c-5-82-2-145 0-205" fill="none" stroke="#4f7653" stroke-width="26" stroke-linecap="round"/>
<path d="M252 252c-73-12-111-54-111-111 67-2 112 39 111 111Z" fill="#91ad67"/>
<path d="M261 304c76-8 116-47 122-103-66-8-115 29-122 103Z" fill="#8faa7e"/>
<circle cx="257" cy="150" r="35" fill="#dda8b2"/>
<circle cx="224" cy="168" r="27" fill="#efd0d6"/>
<circle cx="290" cy="168" r="27" fill="#efd0d6"/>
</svg>'''
Path('app-icon.svg').write_text(svg + '\n', encoding='utf-8')

# 180x180 PNG for iOS Home Screen, generated without external libraries.
w = h = 180
bg = (79, 118, 83, 255)
cream = (255, 249, 238, 255)
green1 = (145, 173, 103, 255)
green2 = (143, 170, 126, 255)
pink = (221, 168, 178, 255)
pink2 = (239, 208, 214, 255)
pixels = bytearray()
for y in range(h):
    pixels.append(0)  # PNG filter byte
    for x in range(w):
        c = bg
        if (x-90)**2 + (y-90)**2 <= 61**2:
            c = cream
        # stem
        if 86 <= x <= 94 and 60 <= y <= 132:
            c = bg
        # left leaf / right leaf as rotated-ish ellipses
        if ((x-70)/29)**2 + ((y-85)/17)**2 <= 1 and x <= 93:
            c = green1
        if ((x-111)/30)**2 + ((y-103)/17)**2 <= 1 and x >= 87:
            c = green2
        # blossom cluster
        if (x-90)**2 + (y-52)**2 <= 13**2:
            c = pink
        if (x-78)**2 + (y-59)**2 <= 10**2 or (x-102)**2 + (y-59)**2 <= 10**2:
            c = pink2
        pixels.extend(c)

def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
png = b'\x89PNG\r\n\x1a\n'
png += chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
png += chunk(b'IDAT', zlib.compress(bytes(pixels), 9))
png += chunk(b'IEND', b'')
Path('app-icon-180.png').write_bytes(png)

# Sanity checks for expected UX outcome.
final = path.read_text(encoding='utf-8')
checks = [
    'class="navicon"', 'id="plantAdvanced"', 'id="calendarToggle"',
    'id="setupGuide"', 'manifest.webmanifest', 'apple-touch-icon',
    'function renderOnboardingGuide()', 'Die Erde könnte trockener werden',
    'Die Kartenmitte wird auch für das Wetter verwendet.'
]
for item in checks:
    assert item in final, f'missing expected result: {item}'
assert 'id="setGardenCenterBtn"' not in final
assert 'id="openGardenCenter"' not in final
