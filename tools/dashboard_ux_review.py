from pathlib import Path
import re

p=Path('index.html')
s=p.read_text(encoding='utf-8')
if 'JGW DASHBOARD UX REVIEW' in s:
    print('already patched')
    raise SystemExit(0)

TODAY='''<section class="view active" id="view-today">
  <div class="box today-overview">
    <div class="topline"><div><h2>Heute im Garten</h2><div class="muted" id="todayDate"></div></div><div class="actions"><button class="btn ghost small" id="refreshWeather" type="button">↻ Aktualisieren</button></div></div>
    <div id="todayWeather" class="state-card">
      <div class="state-head">
        <div><div class="state-kicker">Gartenlage</div><div class="state-title" id="gardenState">Wetter wird geladen</div></div>
        <div class="state-badge" id="gardenStateBadge">–</div>
      </div>
      <div class="state-text" id="gardenStateText">Die Gartenlage wird aus Regen und Verdunstung der vergangenen Tage berechnet.</div>
      <div class="state-grid">
        <div class="state-item"><div class="state-label">Trockentage</div><div class="state-value" id="gardenDryDays">–</div></div>
        <div class="state-item"><div class="state-label">Nächster Regen</div><div class="state-value" id="gardenNextRain">–</div></div>
        <div class="state-item" id="gardenFrostBox"><div class="state-label">Frost</div><div class="state-value" id="gardenFrost">–</div></div>
      </div>
    </div>
  </div>
  <div class="box dashboard-task-box">
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
  <div class="box eco-compact-card" id="ecoDashboardCompact">
    <div class="eco-compact-head">
      <div><div class="label">Naturgarten</div><div class="eco-compact-score" id="ecoCompactScore">– <small>/ 100</small></div><div class="eco-compact-level" id="ecoCompactLevel">Noch keine Bewertung</div></div>
      <button class="btn ghost small" id="ecoCompactDetailsBtn" type="button">Details</button>
    </div>
    <div class="eco-compact-stats" id="ecoCompactStats"></div>
    <div class="eco-compact-recommend" id="ecoCompactRecommendation">Mit der ersten Pflanze oder einem Lebensraum startet die Bewertung.</div>
  </div>
</section>

<section class="view" id="view-map">'''
pat=r'<section class="view active" id="view-today">.*?</section>\s*\n\s*<section class="view" id="view-map">'
s,n=re.subn(pat,TODAY,s,count=1,flags=re.S)
assert n==1, 'today block not replaced'

NATURE_HEAD='''<section class="view" id="view-plants">
  <div class="box nature-head">
    <div class="topline"><div><h2>Naturgarten</h2><div class="muted">Pflanzen, Lebensräume und Tierbeobachtungen – mit deinem Naturgarten-Score an einem Ort.</div></div></div>
    <div class="nature-tabs" id="natureTabs" role="tablist" aria-label="Naturgarten-Sammlung">
      <button class="nature-tab active" data-nature="plants" type="button">🌿 Pflanzen <span class="nature-count" id="naturePlantCount">0</span></button>
      <button class="nature-tab" data-nature="habitats" type="button">🪵 Lebensräume <span class="nature-count" id="natureHabitatCount">0</span></button>
      <button class="nature-tab" data-nature="animals" type="button">🦋 Tiere <span class="nature-count" id="natureAnimalCount">0</span></button>
    </div>
  </div>
  <div class="box eco-dashboard-card eco-dashboard-detail" id="ecoDashboard">
    <div class="eco-head">
      <div><div class="label">Naturgarten-Score</div><div class="eco-score-wrap"><div class="eco-score" id="ecoGardenScore">– <small>/ 100</small></div></div><div class="eco-level" id="ecoGardenLevel">🌿 Noch keine Bewertung</div></div>
      <button class="btn ghost small" id="ecoSettingsBtn" type="button">Naturnahe Praxis</button>
    </div>
    <div class="eco-summary" id="ecoGardenSummary">Pflanzen, Lebensräume und naturnahe Pflege ergeben gemeinsam deinen Naturgarten-Score.</div>
    <div class="eco-stats" id="ecoGardenStats"></div>
    <div class="eco-animal-proof" id="ecoAnimalProof"></div>
    <div class="bloom-wrap"><div class="bloom-bars" id="ecoBloomBars"></div><div class="bloom-labels" id="ecoBloomLabels"></div></div>
    <div class="eco-recommend" id="ecoRecommendation">Pflanzen anlegen, um Blühlücken und Potenziale zu erkennen.</div>
  </div>
  <div class="nature-pane" id="naturePlantsPane">'''
pat2=r'<section class="view" id="view-plants">\s*<div class="box nature-head">.*?</div>\s*<div class="nature-pane" id="naturePlantsPane">'
s,n=re.subn(pat2,NATURE_HEAD,s,count=1,flags=re.S)
assert n==1, 'nature header not replaced'

s=s.replace('<h2>Meine Pflanzensammlung</h2><div class="muted">Deine Pflanzen als persönliche Gartenkarten – mit Pflege- und Insektenwert.</div>', '<h2>Pflanzen</h2><div class="muted">Deine Pflanzenkarten mit Pflege, Standort und Insektenwert.</div>',1)

CSS='''
/* JGW DASHBOARD UX REVIEW */
#view-today>.box{margin-top:10px}
.today-overview{box-shadow:0 7px 20px rgba(80,100,72,.08)}
.dashboard-task-box{box-shadow:0 6px 18px rgba(80,100,72,.07)}
.dashboard-task-count{display:inline-flex;align-items:center;justify-content:center;min-height:34px;padding:6px 10px;border-radius:999px;background:var(--ok);color:var(--forest-dark);font-size:12px;font-weight:800;white-space:nowrap}
.dashboard-quick{margin-top:14px;padding-top:12px;border-top:1px solid #eee4d8}
.dashboard-quick-title{font-size:12px;font-weight:800;color:var(--muted);margin-bottom:8px}
.dashboard-actions{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px}
.dashboard-action{min-height:58px;border:1px solid #e5d8ca;border-radius:14px;background:linear-gradient(180deg,#fffdf9,#faf5ed);color:var(--forest-dark);display:flex;align-items:center;justify-content:center;gap:7px;padding:9px 8px;box-shadow:none}
.dashboard-action span{font-size:20px}.dashboard-action b{font-size:12px}
.dashboard-action:active{transform:scale(.985)}
.eco-compact-card{background:linear-gradient(135deg,#f7f5e9,#eef5e8);box-shadow:0 6px 18px rgba(80,100,72,.07);overflow:hidden;position:relative}
.eco-compact-card:after{content:"";position:absolute;width:160px;height:160px;border-radius:50%;right:-70px;top:-85px;background:radial-gradient(circle,rgba(200,165,106,.14),transparent 70%);pointer-events:none}
.eco-compact-head{display:flex;align-items:flex-start;justify-content:space-between;gap:12px;position:relative;z-index:1}
.eco-compact-score{font-family:Georgia,"Times New Roman",serif;font-size:32px;font-weight:700;line-height:1;color:var(--forest-dark);margin-top:3px}.eco-compact-score small{font:600 13px -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:var(--muted)}
.eco-compact-level{margin-top:5px;font-size:12px;font-weight:800;color:var(--forest-dark)}
.eco-compact-stats{display:flex;gap:6px;flex-wrap:wrap;margin-top:11px;position:relative;z-index:1}.eco-compact-stat{font-size:11px;font-weight:750;background:rgba(255,253,249,.82);border:1px solid #e4dccd;border-radius:999px;padding:6px 9px;color:#62584d}
.eco-compact-recommend{margin-top:10px;font-size:12px;line-height:1.45;color:#5f5a3f;position:relative;z-index:1}
.eco-dashboard-detail{margin-top:10px;box-shadow:0 6px 18px rgba(80,100,72,.07)}
.nature-head{box-shadow:0 6px 18px rgba(80,100,72,.07)}
.collection-card,.nature-card{box-shadow:0 5px 14px rgba(80,100,72,.07)}
.collection-latin,.collection-area,.collection-status,.nature-card-sub,.nature-chip,.collection-chip,.eco-source,.reference-note,.bloom-labels span{font-size:max(11px,0.68rem)}
.detail-kv span{font-size:10.5px}
@media(max-width:700px){
  #view-today>.box{margin-top:8px}
  .dashboard-actions{gap:6px}.dashboard-action{min-height:56px;flex-direction:column;gap:3px;padding:7px 4px}.dashboard-action span{font-size:21px}.dashboard-action b{font-size:11px}
  .eco-compact-score{font-size:30px}.eco-dashboard-detail{margin-top:8px}
  .nature-head{padding-top:13px;padding-bottom:12px}.nature-head h2{margin-bottom:4px}
  .collection-latin,.collection-area,.collection-status,.nature-card-sub,.nature-chip,.collection-chip,.eco-source,.reference-note,.bloom-labels span{font-size:11px!important}
}
/* /JGW DASHBOARD UX REVIEW */
'''
s=s.replace('</style>',CSS+'\n</style>',1)

COMPACT='''function renderCompactEcoDashboard(){var g=gardenEcoScore(),dq=natureDataQuality(g),score=el("ecoCompactScore"),level=el("ecoCompactLevel"),stats=el("ecoCompactStats"),rec=el("ecoCompactRecommendation");if(!score)return;var any=state.plants.length||state.habitats.length,groups=animalGroups();if(!any){score.innerHTML='– <small>/ 100</small>';level.textContent="Noch keine Bewertung";stats.innerHTML='<span class="eco-compact-stat">0 Pflanzen</span><span class="eco-compact-stat">0 Lebensräume</span>';rec.textContent="Mit der ersten Pflanze oder einem Lebensraum startet die Bewertung.";return}score.innerHTML=g.total+' <small>/ 100</small>';level.textContent=gardenEcoLevel(g.total)+' · Datenbasis '+dq.label;stats.innerHTML='<span class="eco-compact-stat">🌿 '+g.uniqueCount+' Pflanzen</span><span class="eco-compact-stat">🪵 '+state.habitats.length+' Lebensräume</span><span class="eco-compact-stat">🐾 '+groups.length+' Tiergruppen</span>';rec.textContent=bloomGapRecommendation(g)}
'''
s=s.replace('function supportLabel(v){',COMPACT+'function supportLabel(v){',1)
s=s.replace('function renderToday(){renderEcoDashboard();', 'function renderToday(){renderEcoDashboard();renderCompactEcoDashboard();',1)
s=s.replace('state.ecology.practice[c.dataset.practice]=!!c.checked;save();renderEcoDashboard()', 'state.ecology.practice[c.dataset.practice]=!!c.checked;save();renderEcoDashboard();renderCompactEcoDashboard()',1)

old='''el("ecoSettingsBtn").addEventListener("click",function(){openSettings("settingsEcology")});
el("syncMini").addEventListener("click",function(){openSettings("settingsSync")});
el("quickAddPlant").addEventListener("click",function(){switchView("plants");setNatureTab("plants");setTimeout(function(){openPlantEditor(null)},50)});'''
new='''el("ecoSettingsBtn").addEventListener("click",function(){openSettings("settingsEcology")});
el("ecoCompactDetailsBtn").addEventListener("click",function(){switchView("plants");setTimeout(function(){var d=el("ecoDashboard");if(d)d.scrollIntoView({behavior:"smooth",block:"start"})},80)});
el("addPlantToday").addEventListener("click",function(){switchView("plants");setNatureTab("plants",false);setTimeout(function(){openPlantEditor(null)},60)});
el("addHabitatToday").addEventListener("click",function(){switchView("plants");setNatureTab("habitats",false);setTimeout(function(){openHabitatEditor(null)},60)});
el("addAnimalToday").addEventListener("click",function(){switchView("plants");setNatureTab("animals",false);setTimeout(function(){openAnimalEditor(null)},60)});
el("syncMini").addEventListener("click",function(){openSettings("settingsSync")});
el("quickAddPlant").addEventListener("click",function(){switchView("plants");setNatureTab("plants");setTimeout(function(){openPlantEditor(null)},50)});'''
assert old in s, 'event anchor missing'
s=s.replace(old,new,1)

# ensure detailed score appears only once and compact score exists once
assert s.count('id="ecoDashboard"')==1
assert s.count('id="ecoDashboardCompact"')==1
assert s.count('id="addPlantToday"')==1
assert s.count('id="addHabitatToday"')==1
assert s.count('id="addAnimalToday"')==1

p.write_text(s,encoding='utf-8')
print('patched',len(s))
