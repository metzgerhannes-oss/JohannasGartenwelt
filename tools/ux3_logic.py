from pathlib import Path
import re
p=Path('index.html'); s=p.read_text(encoding='utf-8')

def line(prefix,new):
    global s
    a=s.splitlines(); h=[i for i,x in enumerate(a) if x.startswith(prefix)]
    if len(h)!=1: raise SystemExit(f'{prefix}: {len(h)} matches')
    a[h[0]:h[0]+1]=new.splitlines(); s='\n'.join(a)+('\n' if s.endswith('\n') else '')

def rep(old,new,label):
    global s
    if old not in s: raise SystemExit('missing '+label)
    s=s.replace(old,new,1)

if 'function friendlyGardenExplanation(' in s:
    print('Logic V3 already present'); raise SystemExit(0)

line('var state=','var state={days:30,plz:"",loc:null,gardenCenter:null,weather:null,plants:[],zones:[],settings:{plantnetKey:DEFAULT_PLANTNET_KEY,seasonMode:"auto",animations:true,mapView:null,onboardingDone:false},pendingZone:null,editingZoneId:null,map:null,zoneGroup:null,markerGroup:null,mapReady:false,mapEditMode:false,placePlantId:null,setCenterMode:false,photoData:"",photoFile:null,editPlantId:null};')
line('function load(){','function load(){try{var raw=localStorage.getItem(STORE);if(raw){var d=JSON.parse(raw);state.plz=d.plz||"";state.loc=d.loc||null;state.gardenCenter=d.gardenCenter||null;state.plants=Array.isArray(d.plants)?d.plants:[];state.zones=Array.isArray(d.zones)?d.zones:[];state.settings=Object.assign({plantnetKey:DEFAULT_PLANTNET_KEY,seasonMode:"auto",animations:true,mapView:null,onboardingDone:false},d.settings||{});if(!(state.settings.plantnetKey||"").trim())state.settings.plantnetKey=DEFAULT_PLANTNET_KEY;if(!["auto","spring","summer","autumn","winter"].includes(state.settings.seasonMode))state.settings.seasonMode="auto";if(state.settings.animations!==false)state.settings.animations=true;state.days=[7,14,30,60,90].includes(Number(d.days))?Number(d.days):30}else{var old=localStorage.getItem("giess_plz");if(old)state.plz=old}}catch(e){console.warn(e)}loadSync()}')

helpers='''var onboardingReady=false,appToastTimer=null;\nfunction renderOnboarding(){var box=el("firstRunGuide");if(!box)return;if(!onboardingReady||state.settings.onboardingDone){show("firstRunGuide",false);return}var a=!!state.plz,b=!!state.settings.mapView,c=state.plants.length>0;if(a&&b&&c){state.settings.onboardingDone=true;save();show("firstRunGuide",false);return}show("firstRunGuide",true);[["guideLocation",a,"1"],["guideMap",b,"2"],["guidePlant",c,"3"]].forEach(function(x){var n=el(x[0]);if(n)n.classList.toggle("done",x[1]);var m=n&&n.querySelector(".guide-mark");if(m)m.textContent=x[1]?"✓":x[2]})}\nfunction showAppToast(msg,type,duration){var t=el("appToast");if(!t)return;t.textContent=msg;t.className="app-toast"+(type==="error"?" error-toast":"");t.setAttribute("role",type==="error"?"alert":"status");clearTimeout(appToastTimer);requestAnimationFrame(function(){t.classList.add("show")});appToastTimer=setTimeout(function(){t.classList.remove("show")},duration||3200)}\nfunction friendlyGardenExplanation(idx,dryDays){var a=["Der Garten ist derzeit sehr gut mit Wasser versorgt.","Der Boden dürfte vielerorts noch gut feucht sein.","Regen und Verdunstung halten sich derzeit ungefähr die Waage.","Es wird trockener. Empfindliche und frisch gesetzte Pflanzen im Blick behalten.","Längere Trockenphase. Feuchtigkeitsliebende Pflanzen bitte prüfen.","Deutliche Trockenlage. Vor allem junge Pflanzen und Kübel auf Gießbedarf prüfen."];var x=a[idx]||"Die Gartenlage wurde aus dem Wetter der vergangenen Tage abgeleitet.";if(dryDays>=7)x+=" Seit "+dryDays+" Tagen gab es keinen nennenswerten Regen.";return x}\n'''
rep('function automaticSeason(){',helpers+'function automaticSeason(){','helpers')

line('function applyAppearance(){','function applyAppearance(){var key=currentSeason(),info=seasonInfo(key);document.body.dataset.season=key;var mark=el("seasonMark");if(mark){mark.textContent=info.icon;mark.title=info.label}var mt=document.querySelector(\'meta[name="theme-color"]\'),tc={spring:"#6f9467",summer:"#7f9a55",autumn:"#806b4c",winter:"#607873"};if(mt)mt.setAttribute("content",tc[key]||"#567a57");var sm=el("seasonMode");if(sm)sm.value=state.settings.seasonMode||"auto";var at=el("animationToggle");if(at)at.checked=state.settings.animations!==false;var st=el("seasonStatus");if(st)st.textContent=(state.settings.seasonMode||"auto")==="auto"?"Aktuell: "+info.label+" · Wechsel automatisch am 1. März, 1. Juni, 1. September und 1. Dezember.":"Manuell gewählt: "+info.label+"."}')

old='var explanation="14-Tage-Bilanz "+(balance>=0?"+":"")+de1(balance)+" mm · "+de1(rain14)+" mm Regen, "+de1(et14)+" mm Verdunstung.";return{name:levels[idx].name,cls:levels[idx].cls,balance:balance,dryDays:dryDays,nextRain:nextRain,frost:frost,explanation:explanation}'
rep(old,'var explanation=friendlyGardenExplanation(idx,dryDays);return{name:levels[idx].name,cls:levels[idx].cls,balance:balance,dryDays:dryDays,nextRain:nextRain,frost:frost,explanation:explanation}','weather explanation')

old='var zr=z?(" · Standort: "+lightLabel(z.light)+(z.rain!=="open"?", "+rainLabel(z.rain):"")):" · keine Standortzone";var er=est.days<999?(" · "+est.label):"";return{level:level,title:title,score:score,reason:"7 Tage: "+de1(rain)+" mm Regen, "+de1(et0)+" mm ET₀; nächste 2 Tage "+de1(fRain)+" mm Regen"+zr+er}'
new='var reason=level==="bad"?"Die vergangenen Tage waren für diese Pflanze voraussichtlich zu trocken.":level==="warn"?"Die Bodenfeuchte könnte knapp werden. Bitte einmal direkt an der Pflanze prüfen.":"Aktuell besteht voraussichtlich kein Gießbedarf.";if(fRain>=6)reason+=" In den nächsten zwei Tagen ist Regen angekündigt.";else if(level!=="ok")reason+=" Kurzfristig ist wenig Regen angekündigt.";if(est.days<=90)reason+=" Die Pflanze ist noch in der Anwachsphase.";if(z)reason+=" Standort: "+lightLabel(z.light)+(z.rain!=="open"?", "+rainLabel(z.rain):"")+".";return{level:level,title:title,score:score,reason:reason}'
rep(old,new,'task wording')

rep("return '<article class=\"plantcard\"><div class=\"plantphoto\">'","return '<article class=\"plantcard\" data-id=\"'+p.id+'\" tabindex=\"0\" title=\"Antippen für Details\"><div class=\"plantphoto\">'",'plant card tag')
old='</div></details><div class="plantactions"><button class="btn small editPlant" data-id="'+p.id+'" type="button">Bearbeiten</button><button class="btn secondary small placePlant" data-id="'+p.id+'" type="button">'+(p.lat?"Position ändern":"Auf Karte setzen")+'</button><button class="btn ghost small deletePlant" data-id="'+p.id+'" type="button">Löschen</button></div></div></article>'
new='</div></details><div class="plantactions"><button class="btn small editPlant" data-id="'+p.id+'" type="button">Bearbeiten</button><details class="card-menu"><summary class="btn ghost small" aria-label="Weitere Aktionen">•••</summary><div class="card-menu-pop"><button class="btn secondary small placePlant" data-id="'+p.id+'" type="button">'+(p.lat?"Position ändern":"Auf Karte setzen")+'</button><button class="btn ghost small deletePlant" data-id="'+p.id+'" type="button">Pflanze löschen</button></div></details></div></div></article>'
rep(old,new,'plant menu')
rep('}).join("");document.querySelectorAll(".editPlant")','}).join("");document.querySelectorAll(".plantcard").forEach(function(card){function tog(e){if(e&&e.target.closest("button,a,input,label,summary,.card-menu"))return;var d=card.querySelector(".plant-details");if(d)d.open=!d.open}card.addEventListener("click",tog);card.addEventListener("keydown",function(e){if(e.key==="Enter"||e.key===" "){e.preventDefault();tog(e)}})});document.querySelectorAll(".editPlant")','plant card click')

line('function saveMapViewport(){','function saveMapViewport(){if(!state.map)return;var c=state.map.getCenter();state.settings.mapView={lat:c.lat,lon:c.lng,zoom:state.map.getZoom()};state.gardenCenter={lat:c.lat,lon:c.lng};save();setMapEditing(false);renderOnboarding();if(state.plz)refreshWeather(false);notice("Gartenausschnitt gespeichert. Die Kartenmitte wird auch für das Wetter verwendet.")}')
rep('if(state.gardenCenter){L.circleMarker([state.gardenCenter.lat,state.gardenCenter.lon]','if(state.gardenCenter&&state.mapEditMode){L.circleMarker([state.gardenCenter.lat,state.gardenCenter.lon]','center marker')

line('function globalError(msg){','function globalError(msg){showAppToast(msg,"error",7000)}')
line('function notice(msg){','function notice(msg){showAppToast(msg,"notice",3200)}')
line('function renderAll(){','function renderAll(){applyAppearance();renderHeader();renderToday();renderPlants();renderCalendar();renderWeather();renderSync();renderOnboarding();if(state.mapReady)renderMap()}')

rep('el("plantSearch").addEventListener("input",renderPlants);','''el("plantSearch").addEventListener("input",renderPlants);\nel("guideDismissBtn").addEventListener("click",function(){state.settings.onboardingDone=true;save();renderOnboarding()});\nel("guideLocationBtn").addEventListener("click",function(){openSettings("settingsLocation")});\nel("guideMapBtn").addEventListener("click",function(){switchView("map");setTimeout(function(){setMapEditing(true)},100)});\nel("guidePlantBtn").addEventListener("click",function(){switchView("plants");setTimeout(function(){openPlantEditor(null)},60)});\nel("calendarMoreBtn").addEventListener("click",function(){var g=el("calendarGrid"),c=g.classList.toggle("calendar-collapsed");this.textContent=c?"Ganzes Pflegejahr anzeigen":"Nur nächste drei Monate"});''','events')
s=re.sub(r'^el\("openGardenCenter"\)\.addEventListener\([^\n]+\);\n?','',s,flags=re.M)
s=re.sub(r'^el\("setGardenCenterBtn"\)\.addEventListener\([^\n]+\);\n?','',s,flags=re.M)
rep('renderAll();syncBootstrap();if(state.plz)refreshWeather(false);','renderAll();syncBootstrap();if(state.plz)refreshWeather(false);setTimeout(function(){onboardingReady=true;renderOnboarding()},1700);','onboarding delay')

p.write_text(s,encoding='utf-8'); print('UX3 logic patched')
