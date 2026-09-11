from pathlib import Path

p=Path('index.html')
s=p.read_text(encoding='utf-8')


def replace_between(text,start_marker,end_marker,new_text):
    a=text.find(start_marker)
    if a<0: raise SystemExit('missing start '+start_marker)
    b=text.find(end_marker,a)
    if b<0: raise SystemExit('missing end '+end_marker)
    return text[:a]+new_text+'\n'+text[b:]

# Dashboard wording and animal proof area
s=s.replace('<div><div class="label">Insektenfreundlichkeit</div><div class="eco-score-wrap"><div class="eco-score" id="ecoGardenScore">– <small>/ 100</small></div></div><div class="eco-level" id="ecoGardenLevel">🐝 Noch keine Bewertung</div></div>',
'''<div><div class="label">Naturgarten-Score</div><div class="eco-score-wrap"><div class="eco-score" id="ecoGardenScore">– <small>/ 100</small></div></div><div class="eco-level" id="ecoGardenLevel">🌿 Noch keine Bewertung</div></div>''')
s=s.replace('<button class="btn ghost small" id="ecoSettingsBtn" type="button">Lebensraum</button>','<button class="btn ghost small" id="ecoSettingsBtn" type="button">Naturgarten</button>')
s=s.replace('Mit jeder eingetragenen Pflanze wird sichtbar, wie gut dein Garten Insekten über das Jahr unterstützt.','Pflanzen, Lebensräume und naturnahe Pflege ergeben gemeinsam deinen Naturgarten-Score.')
s=s.replace('<div class="eco-stats" id="ecoGardenStats"></div>','<div class="eco-stats" id="ecoGardenStats"></div>\n    <div class="eco-animal-proof" id="ecoAnimalProof"></div>')

# CSS additions
css='''
/* JGW NATURGARTEN SCORE */
.eco-animal-proof{margin-top:9px;padding:9px 11px;border:1px solid #ded7c6;border-radius:12px;background:rgba(250,247,238,.9);font-size:11px;line-height:1.45;color:#655d52;position:relative;z-index:1}
.eco-animal-proof b{color:var(--forest-dark)}
.eco-data-quality{font-weight:850}
.score-breakdown .score-part{min-width:0}
.score-breakdown .score-part small{display:block;line-height:1.2;margin-top:2px}
@media(max-width:760px){.score-breakdown{grid-template-columns:repeat(2,minmax(0,1fr))}.score-breakdown .score-part:last-child{grid-column:1/-1}.eco-animal-proof{font-size:10px}}
'''
marker='/* /JGW FINAL DESIGN */'
if '/* JGW NATURGARTEN SCORE */' not in s:
    s=s.replace(marker,css+'\n'+marker)

# Native status can evaluate preview plant lists as well as saved state.
s=replace_between(s,'function nativePlantStatus(){','function practiceScore()',
'''function nativePlantStatus(plantsOverride){var yes=0,no=0,unknown=0,src=plantsOverride||state.plants;src.forEach(function(p){if(p.ecoNative==="yes"){yes++;return}if(p.ecoNative==="no"){no++;return}var r=ecoProfileFor(p);if(r&&r.nat>=10)yes++;else if(r&&r.nat<=3)no++;else unknown++});var known=yes+no,ratio=known?yes/known:0,active=known>=5&&ratio>=.60;return{yes:yes,no:no,unknown:unknown,known:known,ratio:ratio,active:active}}''')

# Replace complete score model and its labels/recommendation.
score_code=r'''function gardenEcoScore(plantsOverride){
 var plants=(plantsOverride||state.plants||[]).map(normalizePlantData),unique={},families=new Set(),types=new Set(),supports=new Set();
 plants.forEach(function(p){var k=(p.scientific||p.name||p.id||"").trim().toLowerCase();if(!unique[k]||plantInsectValue(p).score>plantInsectValue(unique[k]).score)unique[k]=p;if(p.family)families.add(String(p.family).toLowerCase());if(p.type)types.add(p.type)});
 var ups=Object.keys(unique).map(function(k){return unique[k]}),plantFood=0,profiled=0,valuable=0;
 if(ups.length){
   var scores=[];ups.forEach(function(p){var e=plantInsectValue(p);scores.push(e.score);if(e.source==="Artprofil")profiled++;if(e.score>=70)valuable++;(e.supports||[]).forEach(function(x){if(x!=="bestäuber")supports.add(x)})});
   var avg=scores.reduce(function(a,b){return a+b},0)/scores.length;
   var qualityPts=avg/100*22,valuablePts=Math.min(4,valuable),functionPts=Math.min(4,supports.size*.8);
   plantFood=Math.min(30,Math.round(qualityPts+valuablePts+functionPts));
 }
 var counts=Array(12).fill(0);ups.forEach(function(p){plantInsectValue(p).bloomMonths.forEach(function(m){if(m>=1&&m<=12)counts[m-1]++})});
 var relevant=[1,2,3,4,5,6,7,8,9,10],season=0,continuous=true;relevant.forEach(function(i){if(counts[i]>=2)season+=1.2;else if(counts[i]===1)season+=.8;else continuous=false});if(continuous)season+=3;season=Math.min(15,Math.round(season));
 var habitat=Math.min(25,Math.round(habitatCollectionScore()*25/15));
 var practice=Math.min(15,Math.round(practiceScore()*15/10));
 var native=nativePlantStatus(plants),speciesPts=Math.min(5,Math.round(ups.length/2)),familyPts=Math.min(3,families.size),typePts=Math.min(2,types.size),nativePts=0;
 if(native.known)nativePts=Math.min(5,Math.round(native.ratio*5*Math.min(1,native.known/5)));
 var diversity=Math.min(15,speciesPts+familyPts+typePts+nativePts);
 var total=Math.max(0,Math.min(100,plantFood+season+habitat+practice+diversity));
 return{total:total,quality:plantFood,bloom:season,diversity:diversity,habitat:habitat,practice:practice,counts:counts,uniqueCount:ups.length,valuable:valuable,profiled:profiled,native:native,supportGroups:supports.size};
}
function natureDataQuality(g){
 var plantCoverage=Math.min(1,(g.uniqueCount||0)/10),habitatCoverage=Math.min(1,(state.habitats||[]).length/4),profileCoverage=g.uniqueCount?Math.min(1,(g.profiled||0)/g.uniqueCount):0,nativeCoverage=Math.min(1,(g.native&&g.native.known||0)/5);
 var pct=Math.round((plantCoverage*.45+habitatCoverage*.25+profileCoverage*.20+nativeCoverage*.10)*100),label=pct>=80?"sehr gut":pct>=60?"gut":pct>=35?"im Aufbau":"gering";
 return{percent:pct,label:label};
}
function gardenEcoLevel(score){return score>=85?"Vielfältiger Naturgarten":score>=70?"Sehr naturfreundlich":score>=50?"Naturfreundlich":score>=30?"Im Aufbau":"Erste Naturbausteine"}
function bloomGapRecommendation(g){
 var parts=[{k:"quality",v:g.quality/30},{k:"bloom",v:g.bloom/15},{k:"habitat",v:g.habitat/25},{k:"practice",v:g.practice/15},{k:"diversity",v:g.diversity/15}].sort(function(a,b){return a.v-b.v}),worst=parts[0].k;
 if(worst==="bloom"){
   var gaps=[];for(var m=2;m<=11;m++)if(!g.counts[m-1])gaps.push(m);
   if(gaps.length){if(gaps.some(function(m){return m<=4}))return"Was jetzt am meisten bringt: Frühblüher für "+gaps.filter(function(m){return m<=4}).map(function(m){return MONTHS[m-1]}).join(", ")+" ergänzen.";if(gaps.some(function(m){return m>=9}))return"Was jetzt am meisten bringt: Spätblüher für "+gaps.filter(function(m){return m>=9}).map(function(m){return MONTHS[m-1]}).join(", ")+" ergänzen.";return"Was jetzt am meisten bringt: eine Blühlücke in "+gaps.map(function(m){return MONTHS[m-1]}).join(", ")+" schließen."}
 }
 if(worst==="habitat"){
   var cats=new Set(state.habitats.filter(function(h){return h.status==="present"||h.status==="optimized"}).map(function(h){return habitatLibraryItem(h.type).category}));
   if(!cats.has("structure"))return"Was jetzt am meisten bringt: Nist- und Strukturraum ergänzen – z. B. offene Bodenstelle, Totholz oder Sandarium.";
   if(!cats.has("water"))return"Was jetzt am meisten bringt: eine sichere Wasserstelle ergänzen.";
   if(!cats.has("refuge"))return"Was jetzt am meisten bringt: einen ungestörten Rückzugs- und Überwinterungsbereich schaffen.";
   return"Was jetzt am meisten bringt: unterschiedliche Lebensraumtypen ergänzen statt denselben Typ mehrfach anzulegen.";
 }
 if(worst==="practice"){
   var p=state.ecology&&state.ecology.practice||DEFAULT_PRACTICE;
   if(!p.noPesticides)return"Was jetzt am meisten bringt: auf Insektizide verzichten.";
   if(!p.reducedNightLight)return"Was jetzt am meisten bringt: Außenlicht nachts reduzieren – besonders für Nachtfalter.";
   if(!p.leaveStemsInWinter)return"Was jetzt am meisten bringt: einen Teil der Staudenstängel über Winter stehen lassen.";
   if(!p.lessFrequentMowing)return"Was jetzt am meisten bringt: abschnittsweise und seltener mähen.";
   return"Naturnahe Pflege weiter ausbauen – Laub, Winterstrukturen und torffreies Gärtnern bieten noch Potenzial.";
 }
 if(worst==="diversity"){
   if(g.native.known>=5&&g.native.ratio<.6)return"Was jetzt am meisten bringt: bei neuen Pflanzungen stärker auf heimische bzw. regional passende Arten setzen.";
   return"Was jetzt am meisten bringt: Arten- und Strukturvielfalt erhöhen – neue Arten zählen stärker als viele Exemplare derselben Art.";
 }
 if(g.valuable<4)return"Was jetzt am meisten bringt: weitere ökologisch wertvolle Nahrungspflanzen mit offen zugänglichen Blüten ergänzen.";
 return"Der Garten ist bereits ausgewogen. Besonders wertvoll ist jetzt, die vorhandene Vielfalt dauerhaft zu erhalten und Tierbeobachtungen zu dokumentieren.";
}'''
s=replace_between(s,'function gardenEcoScore(plantsOverride){','function contributionText(p)',score_code)

# Dashboard renderer
render_code=r'''function renderEcoDashboard(){var g=gardenEcoScore(),dq=natureDataQuality(g),score=el("ecoGardenScore"),level=el("ecoGardenLevel"),summary=el("ecoGardenSummary"),stats=el("ecoGardenStats"),proof=el("ecoAnimalProof"),bars=el("ecoBloomBars"),labels=el("ecoBloomLabels"),rec=el("ecoRecommendation");if(!score)return;var any=state.plants.length||state.habitats.length;if(!any){score.innerHTML='– <small>/ 100</small>';level.textContent="🌿 Noch keine Bewertung";summary.textContent="Lege Pflanzen und Lebensräume an. Naturnahe Pflege ergänzt später den Naturgarten-Score.";stats.innerHTML='<span class="eco-stat">0 Pflanzen</span><span class="eco-stat">0 Lebensräume</span>';if(proof)proof.innerHTML='<b>🐾 Tierbeobachtungen</b> verändern den Score bewusst nicht – sie zeigen später, wer den Garten tatsächlich nutzt.';rec.textContent="Mit der ersten Pflanzen- oder Lebensraumkarte startet die Bewertung."}else{score.innerHTML=g.total+' <small>/ 100</small>';level.textContent="🌿 "+gardenEcoLevel(g.total)+" · Datenbasis "+dq.label;summary.textContent="Orientierungswert aus Pflanzen & Nahrung, Jahresversorgung, Lebensräumen, naturnaher Pflege sowie Vielfalt & Regionalität.";stats.innerHTML='<span class="eco-stat">'+g.uniqueCount+' Pflanzenarten/-einträge</span><span class="eco-stat">'+state.habitats.length+' Lebensräume</span><span class="eco-stat eco-data-quality">Datenbasis '+dq.percent+' %</span>';if(proof){var groups=animalGroups();proof.innerHTML=groups.length?'<b>🐾 '+groups.length+' Tierarten/-gruppen · '+state.animals.length+' Beobachtung'+(state.animals.length===1?'':'en')+'</b><br>Wirkungsnachweis aus deinem Garten – bewusst ohne zusätzliche Score-Punkte.':'<b>🐾 Noch keine Tierbeobachtungen</b><br>Sie verändern den Score nicht, zeigen später aber, welche Tiere deinen Garten tatsächlich nutzen.'}rec.textContent=bloomGapRecommendation(g)}var breakdown=el("ecoScoreBreakdown");if(!breakdown){breakdown=document.createElement("div");breakdown.id="ecoScoreBreakdown";breakdown.className="score-breakdown";rec.parentNode.insertBefore(breakdown,rec)}breakdown.innerHTML='<div class="score-part"><b>'+g.quality+'/30</b><small>Pflanzen & Nahrung</small></div><div class="score-part"><b>'+g.bloom+'/15</b><small>Jahresversorgung</small></div><div class="score-part"><b>'+g.habitat+'/25</b><small>Lebensräume</small></div><div class="score-part"><b>'+g.practice+'/15</b><small>Naturnahe Pflege</small></div><div class="score-part"><b>'+g.diversity+'/15</b><small>Vielfalt & Regionalität</small></div>';bars.innerHTML=g.counts.map(function(n){return'<span class="'+(n>=2?'good':n===1?'some':'')+'" title="'+n+' blühende '+(n===1?'Art':'Arten')+'"></span>'}).join("");labels.innerHTML=MONTHS.map(function(m){return'<span>'+m.slice(0,1)+'</span>'}).join("");renderPracticeSettings(g)}'''
s=replace_between(s,'function renderEcoDashboard(){','function supportLabel(v)',render_code)

# Settings values now reflect the main score weighting.
practice_code=r'''function renderPracticeSettings(g){g=g||gardenEcoScore();var n=nativePlantStatus(),box=el("nativePlantAutoStatus");document.querySelectorAll('[data-practice]').forEach(function(c){c.checked=!!(state.ecology&&state.ecology.practice&&state.ecology.practice[c.dataset.practice])});if(box){if(n.known>=5)box.innerHTML='<b>Heimische Pflanzen: '+(n.active?'automatisch erkannt ✓':'noch nicht überwiegend')+'</b><br>'+n.yes+' von '+n.known+' bewertbaren Pflanzen gelten als heimisch/regional ('+Math.round(n.ratio*100)+' %).'+(n.unknown?' '+n.unknown+' Pflanze'+(n.unknown===1?'':'n')+' noch ohne sichere Einordnung.':'');else box.innerHTML='<b>Heimische Pflanzen: noch zu wenig Daten</b><br>'+n.known+' Pflanze'+(n.known===1?'':'n')+' bewertbar. Ab 5 bewertbaren Pflanzen wird „überwiegend heimisch“ automatisch ab 60 % erkannt.'}var t=el("practiceScoreText");if(t)t.textContent="Naturgarten-Score: Naturnahe Pflege "+g.practice+" / 15 · Lebensräume "+g.habitat+" / 25 Punkten."}'''
s=replace_between(s,'function renderPracticeSettings(g){','function buildMonthChecks(containerId,name)',practice_code)

# Make generic "Wildbiene" a guaranteed useful library result even when no exact taxon exists.
apply_code=r'''function applyInatTaxon(t){var photo=t.default_photo||{},generic=!!t._jgwGeneric,name=t.preferred_common_name||t.matched_term||t.name||"";el("animalName").value=name;el("animalScientific").value=generic?"":(t.name||"");el("animalTaxonId").value=generic?"":(t.id||"");el("animalGroup").value=inatGroup(t);el("animalRefPhoto").value=generic?"":(photo.medium_url||photo.square_url||"");el("animalRefAttribution").value=generic?"":(photo.attribution||"");if(!state.animalPhotoData&&el("animalRefPhoto").value)el("animalPhotoPreview").innerHTML='<img src="'+el("animalRefPhoto").value+'" alt="Referenzbild">';el("animalReferenceNote").textContent=generic?"Als Tiergruppe gespeichert – keine exakte Artbestimmung.":(el("animalRefPhoto").value?"Referenzbild aus iNaturalist · "+(photo.attribution||"Lizenzangaben beim Quellbild"):"");el("animalTaxonAssist").textContent=generic?"Wildbiene als Gruppe übernommen. Eine genauere Art kannst du später ergänzen.":"Aus iNaturalist übernommen. Du kannst die Beobachtung jetzt speichern.";hideAnimalTaxonResults()}'''
s=replace_between(s,'function applyInatTaxon(t){','function renderAnimalTaxonResults(rs)',apply_code)

render_tax_code=r'''function renderAnimalTaxonResults(rs){var box=el("animalTaxonResults");if(!rs.length){hideAnimalTaxonResults();el("animalTaxonAssist").textContent="Kein passender Tiername gefunden – du kannst den Namen trotzdem frei eintragen.";return}box.innerHTML=rs.map(function(t,i){var photo=t.default_photo||{},name=t.preferred_common_name||t.matched_term||t.name||"",thumb=photo.square_url?'<img src="'+photo.square_url+'" alt="">':animalGroupIcon(inatGroup(t)),detail=t._jgwGeneric?'Gruppe · keine exakte Artbestimmung':((t.name||'')+' · '+animalGroupLabel(inatGroup(t)));return'<button class="tax-result" type="button" data-i="'+i+'"><span class="tax-thumb">'+thumb+'</span><span><b>'+esc(name)+'</b><small>'+esc(detail)+'</small></span></button>'}).join("");show("animalTaxonResults",true);box.querySelectorAll(".tax-result").forEach(function(b){b.addEventListener("click",function(){applyInatTaxon(rs[Number(b.dataset.i)])})})}'''
s=replace_between(s,'function renderAnimalTaxonResults(rs){','async function searchInaturalistTaxa(q)',render_tax_code)

search_code=r'''async function searchInaturalistTaxa(q){q=String(q||"").trim();if(q.length<3){hideAnimalTaxonResults();el("animalTaxonAssist").textContent="Ab 3 Zeichen durchsucht die Gartenwelt kostenlos iNaturalist.";return}var seq=++animalTaxonSeq,norm=q.toLowerCase().replace(/\s+/g," "),generic=(norm==="wildbiene"||norm==="wildbienen")?{_jgwGeneric:true,id:"",name:"",preferred_common_name:"Wildbiene",matched_term:"Wildbiene",iconic_taxon_name:"Insecta",ancestor_ids:[47201],default_photo:null}:null;el("animalTaxonAssist").textContent="iNaturalist wird durchsucht …";try{var url="https://api.inaturalist.org/v1/taxa/autocomplete?q="+encodeURIComponent(q)+"&taxon_id=1&locale=de&per_page=8",res=await fetch(url,{headers:{"Accept":"application/json"}});if(!res.ok)throw new Error("HTTP "+res.status);var data=await res.json();if(seq!==animalTaxonSeq)return;var rs=(data.results||[]).filter(function(t){return String(t.iconic_taxon_name||"").toLowerCase()!=="plantae"});if(generic)rs.unshift(generic);renderAnimalTaxonResults(rs.slice(0,8));if(rs.length)el("animalTaxonAssist").textContent=generic?"Wildbiene kann als Gruppe gespeichert werden; genauere iNaturalist-Treffer stehen darunter.":"Treffer antippen oder den Namen frei weiterschreiben."}catch(e){if(seq!==animalTaxonSeq)return;if(generic){renderAnimalTaxonResults([generic]);el("animalTaxonAssist").textContent="Wildbiene kann als Gruppe gespeichert werden. iNaturalist ist gerade nicht erreichbar.";return}hideAnimalTaxonResults();el("animalTaxonAssist").textContent="iNaturalist ist gerade nicht erreichbar – die Beobachtung kann trotzdem manuell gespeichert werden."}}'''
s=replace_between(s,'async function searchInaturalistTaxa(q){','function animalKey(a)',search_code)

# Data source transparency.
needle='<div class="muted" style="margin-top:8px"><b>Insektenwert:</b> ein nachvollziehbarer Orientierungswert aus internen Artprofilen bzw. Schätzregeln zu Nektar/Pollen, Wirtspflanzenfunktion, Herkunft, Blühzeit und Blütenzugang. Er ist kein wissenschaftliches Ranking und kann Sortenunterschiede nicht vollständig abbilden.</div>'
if needle in s and '<b>Naturgarten-Score:</b>' not in s:
    s=s.replace(needle,needle+'<div class="muted" style="margin-top:8px"><b>Naturgarten-Score:</b> Orientierungswert aus Pflanzen & Nahrung (30), Jahresversorgung (15), Lebensräumen (25), naturnaher Pflege (15) sowie Vielfalt & Regionalität (15). Tierbeobachtungen werden separat als Wirkungsnachweis gezeigt und geben keine Punkte.</div>')

p.write_text(s,encoding='utf-8')
print('updated index.html',len(s))
