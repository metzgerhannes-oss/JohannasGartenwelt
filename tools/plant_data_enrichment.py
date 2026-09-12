from pathlib import Path
import re

p=Path('index.html')
s=p.read_text(encoding='utf-8')
orig=s

def one(old,new,label):
    global s
    n=s.count(old)
    if n!=1:
        raise SystemExit(f'{label}: expected 1 occurrence, got {n}')
    s=s.replace(old,new,1)

# 1) Specific care profiles for the two reported examples.
one(
' {keys:["pelargonium","geranie"],water:"normal",fert:[5,6,7,8,9],cut:[]}\n];',
' {keys:["pelargonium","geranie"],water:"normal",fert:[5,6,7,8,9],cut:[]},\n {keys:["buddleja davidii","sommerflieder","schmetterlingsflieder"],water:"normal",fert:[3,4,5],cut:[2,3]},\n {keys:["parrotia persica","eisenholzbaum","persischer eisenholzbaum"],water:"normal",fert:[3,4],cut:[2,3]}\n];',
'CARE_RULES tail')

# 2) Settings UI: optional Trefle token, while core enrichment remains key-free.
one(
'''        <div class="muted" style="margin-top:8px">Die App funktioniert auch ohne Pflanzenerkennung.</div>\n      </details>\n    </section>''',
'''        <div class="muted" style="margin-top:8px">Die App funktioniert auch ohne Pflanzenerkennung.</div>\n      </details>\n      <details style="margin-top:10px">\n        <summary>Zusätzliche Pflanzendaten (optional)</summary>\n        <div class="muted" style="margin-top:8px">iNaturalist, GBIF und die lokale Pflegelogik funktionieren ohne Schlüssel. Ein kostenloser Trefle-Token kann zusätzliche Angaben zu Blüte, Wasserbedarf und Verbreitung liefern.</div>\n        <div class="field" style="margin-top:9px"><label for="trefleKey">Trefle API-Token</label><input id="trefleKey" type="password" autocomplete="off" placeholder="optional"></div>\n        <div class="actions" style="margin-top:8px"><button class="btn secondary small" id="savePlantDataKey" type="button">Token speichern</button></div>\n        <div class="section-status" id="plantDataApiStatus" style="margin-top:8px">Zusatzquelle nicht eingerichtet – nicht erforderlich.</div>\n      </details>\n    </section>''',
'Trefle settings UI')

# 3) Plant editor enrichment status and manual refresh.
one(
'''          <div class="field"><label for="plantScientific">Botanischer Name</label><input id="plantScientific" placeholder="z. B. Hydrangea macrophylla"></div>\n          <div class="field"><label for="plantType">Pflanzung</label>''',
'''          <div class="field"><label for="plantScientific">Botanischer Name</label><input id="plantScientific" placeholder="z. B. Hydrangea macrophylla"></div>\n          <div class="field full"><div class="plant-data-status" id="plantDataStatus"><b>Automatische Pflanzendaten</b><br><span>Nach Auswahl oder Fotoerkennung ergänzt die Gartenwelt verfügbare Pflege- und Herkunftsdaten automatisch.</span></div><div class="actions" style="margin-top:8px"><button class="btn secondary small" id="refreshPlantDataBtn" type="button">Pflanzendaten neu laden</button></div></div>\n          <div class="field"><label for="plantType">Pflanzung</label>''',
'plant editor enrichment UI')

# 4) CSS for the source/status card.
css='''\n/* JGW PLANT DATA ENRICHMENT */\n.plant-data-status{padding:11px 12px;border:1px solid #d9e3cb;border-radius:14px;background:linear-gradient(135deg,#f5f7ed,#eef5e8);font-size:12px;line-height:1.45;color:#5c544a}\n.plant-data-status b{color:var(--forest-dark)}\n.plant-data-status.loading{background:#fff7e7;border-color:#ead7a9}\n.plant-data-status.good{background:#eef6eb;border-color:#cfe0c8}\n.plant-data-status.warn{background:#fff5df;border-color:#ead7a9}\n@media(max-width:560px){#refreshPlantDataBtn{width:100%}}\n/* /JGW PLANT DATA ENRICHMENT */\n'''
idx=s.find('</style>')
if idx<0: raise SystemExit('style close missing')
s=s[:idx]+css+s[idx:]

# 5) State defaults and transient enrichment metadata.
one(
'settings:{plantnetKey:DEFAULT_PLANTNET_KEY,seasonMode:"auto",animations:true,mapView:null,onboardingDismissed:false,plantView:"collection",plantSort:"name",natureTab:"plants"},pendingZone:',
'settings:{plantnetKey:DEFAULT_PLANTNET_KEY,trefleKey:"",seasonMode:"auto",animations:true,mapView:null,onboardingDismissed:false,plantView:"collection",plantSort:"name",natureTab:"plants"},plantDataMeta:null,pendingZone:',
'state defaults')

s=s.replace('Object.assign({plantnetKey:DEFAULT_PLANTNET_KEY,seasonMode:', 'Object.assign({plantnetKey:DEFAULT_PLANTNET_KEY,trefleKey:"",seasonMode:')
s=s.replace('settings:{plantnetKey:state.settings.plantnetKey||"",seasonMode:', 'settings:{plantnetKey:state.settings.plantnetKey||"",trefleKey:state.settings.trefleKey||"",seasonMode:')
# Import compatibility if backup contains the optional token.
one(
'if(data.settings&&Object.prototype.hasOwnProperty.call(data.settings,"plantnetKey"))state.settings.plantnetKey=data.settings.plantnetKey||"";save();',
'if(data.settings&&Object.prototype.hasOwnProperty.call(data.settings,"plantnetKey"))state.settings.plantnetKey=data.settings.plantnetKey||"";if(data.settings&&Object.prototype.hasOwnProperty.call(data.settings,"trefleKey"))state.settings.trefleKey=data.settings.trefleKey||"";save();',
'import token')

# 6) Form reset/open/save keep provenance.
one(
'state.photoData="";state.photoFile=null;state.editPlantId=null;el("photoPreview").textContent="Foto";',
'state.photoData="";state.photoFile=null;state.editPlantId=null;state.plantDataMeta=null;el("photoPreview").textContent="Foto";',
'reset metadata')
one(
'setCheckedMonths("fert",[]);setCheckedMonths("cut",[]);setCheckedMonths("bloom",[]);if(el("plantAdvanced"))el("plantAdvanced").open=false;renderPlantEcoPreview()}',
'setCheckedMonths("fert",[]);setCheckedMonths("cut",[]);setCheckedMonths("bloom",[]);if(el("plantAdvanced"))el("plantAdvanced").open=false;renderPlantDataStatus(null);renderPlantEcoPreview()}',
'reset status')
one(
'if(p){state.editPlantId=p.id;el("plantId").value=p.id;',
'if(p){state.editPlantId=p.id;state.plantDataMeta=p.careMeta||null;el("plantId").value=p.id;',
'open metadata')
one(
'setCheckedMonths("cut",p.cutMonths||[]);setCheckedMonths("bloom",p.bloomMonths||[])}renderPlantEcoPreview();',
'setCheckedMonths("cut",p.cutMonths||[]);setCheckedMonths("bloom",p.bloomMonths||[])}renderPlantDataStatus(state.plantDataMeta);renderPlantEcoPreview();',
'open status')
one(
'snoozed:old&&old.snoozed?old.snoozed:{},created:old?old.created:isoToday()})}',
'snoozed:old&&old.snoozed?old.snoozed:{},careMeta:state.plantDataMeta||(old?old.careMeta||null:null),created:old?old.created:isoToday()})}',
'save metadata')

# 7) Header reflects optional source.
one(
'function renderHeader(){el("headerLocation").textContent=state.loc?(state.loc.name+" · "+state.plz):(state.plz?"PLZ "+state.plz:"Noch kein Standort");el("plz").value=state.plz||"";el("plantnetKey").value=state.settings.plantnetKey||"";var ps=el("plantnetStatus");if(ps){var active=!!String(state.settings.plantnetKey||"").trim();ps.className="section-status "+(active?"ok":"");ps.textContent=active?"Pflanzenerkennung aktiv":"Nicht eingerichtet"}applyAppearance();renderSyncMini()}',
'function renderHeader(){el("headerLocation").textContent=state.loc?(state.loc.name+" · "+state.plz):(state.plz?"PLZ "+state.plz:"Noch kein Standort");el("plz").value=state.plz||"";el("plantnetKey").value=state.settings.plantnetKey||"";if(el("trefleKey"))el("trefleKey").value=state.settings.trefleKey||"";var ps=el("plantnetStatus");if(ps){var active=!!String(state.settings.plantnetKey||"").trim();ps.className="section-status "+(active?"ok":"");ps.textContent=active?"Pflanzenerkennung aktiv":"Nicht eingerichtet"}var ds=el("plantDataApiStatus");if(ds){var ta=!!String(state.settings.trefleKey||"").trim();ds.className="section-status "+(ta?"ok":"");ds.textContent=ta?"Trefle-Zusatzdaten aktiv":"Zusatzquelle nicht eingerichtet – iNaturalist, GBIF und Pflegelogik bleiben aktiv."}applyAppearance();renderSyncMini()}',
'renderHeader')

# 8) Enrichment engine inserted before current search-result application.
anchor='function applyPlantSearchResult(x){'
pos=s.find(anchor)
if pos<0: raise SystemExit('applyPlantSearchResult anchor missing')
engine=r'''var plantEnrichSeq=0,inatGermanyPlaceId=null;
var JGW_MONTH_MAP={jan:1,feb:2,mar:3,apr:4,may:5,jun:6,jul:7,aug:8,sep:9,oct:10,nov:11,dec:12,january:1,february:2,march:3,april:4,june:6,july:7,august:8,september:9,october:10,november:11,december:12};
function uniqueNums(a){return Array.from(new Set((a||[]).map(Number).filter(function(x){return x>=1&&x<=12}))).sort(function(a,b){return a-b})}
function trefleMonths(v){if(!v)return[];var a=Array.isArray(v)?v:String(v).split(/[|,; ]+/);return uniqueNums(a.map(function(x){var k=String(x||'').trim().toLowerCase();return JGW_MONTH_MAP[k]||Number(k)||0}))}
function renderPlantDataStatus(meta,text,mode){var box=el("plantDataStatus");if(!box)return;if(text){box.className="plant-data-status "+(mode||"");box.innerHTML='<b>Automatische Pflanzendaten</b><br><span>'+esc(text)+'</span>';return}if(meta&&Array.isArray(meta.sources)&&meta.sources.length){var f=(meta.fields||[]).join(', ');box.className="plant-data-status good";box.innerHTML='<b>Automatische Pflanzendaten</b><br><span>Quelle'+(meta.sources.length===1?'':'n')+': '+esc(meta.sources.join(' · '))+(f?' · ergänzt: '+esc(f):'')+'</span>';return}box.className="plant-data-status";box.innerHTML='<b>Automatische Pflanzendaten</b><br><span>Nach Auswahl oder Fotoerkennung ergänzt die Gartenwelt verfügbare Pflege- und Herkunftsdaten automatisch.</span>'}
function addPlantField(ctx,label){if(!ctx.fields.includes(label))ctx.fields.push(label)}
function addPlantSource(ctx,label){if(label&&!ctx.sources.includes(label))ctx.sources.push(label)}
function fieldMonths(name){return checkedMonths(name)}
function applyMonths(name,vals,force,ctx,label){vals=uniqueNums(vals);if(!vals.length)return false;if(force||!fieldMonths(name).length){setCheckedMonths(name,vals);addPlantField(ctx,label);return true}return false}
function applyNative(v,ctx,source){if(!v||v==="auto"||el("plantNative").value!=="auto")return false;el("plantNative").value=v;addPlantField(ctx,"Herkunft");addPlantSource(ctx,source);return true}
function applyFlowerAccess(v,ctx,source){if(!v||v==="auto"||el("plantFlowerAccess").value!=="auto")return false;el("plantFlowerAccess").value=v;addPlantField(ctx,"Blütenzugang");addPlantSource(ctx,source);return true}
function localNativeHint(name,sci){var p={name:name||"",scientific:sci||"",family:el("plantFamily").value||""},e=ecoProfileFor(p),q=((name||"")+" "+(sci||"")).toLowerCase();if(e&&e.nat>=10)return"yes";if(e&&e.nat<=3)return"no";if(q.indexOf("parrotia persica")>=0||q.indexOf("eisenholzbaum")>=0)return"no";return"auto"}
function applyLocalPlantKnowledge(base,force,ctx){var name=base.common||el("plantName").value.trim(),sci=base.sci||el("plantScientific").value.trim(),rule=applyCareRule(name,sci),eco=ecoProfileFor({name:name,scientific:sci,family:base.family||el("plantFamily").value||""});if(rule){el("plantWater").value=rule.water||el("plantWater").value;applyMonths("fert",rule.fert,force,ctx,"Düngemonate");applyMonths("cut",rule.cut,force,ctx,"Schnittmonate");addPlantField(ctx,"Wasserbedarf");addPlantSource(ctx,"lokales Pflegeprofil")}if(eco){applyMonths("bloom",eco.bloom,force,ctx,"Blühmonate");var n=localNativeHint(name,sci);applyNative(n,ctx,"Artprofil");if(eco.a>=8)applyFlowerAccess("open",ctx,"Artprofil");else if(eco.a>=5)applyFlowerAccess("partial",ctx,"Artprofil");addPlantSource(ctx,"Artprofil")}else{var hint=localNativeHint(name,sci);applyNative(hint,ctx,"Artprofil")}return{rule:rule,eco:eco}}
async function resolveInatPlant(base){if(base&&base.raw&&base.raw.id)return base.raw;var q=(base&&base.sci)||el("plantScientific").value.trim()||(base&&base.common)||el("plantName").value.trim();if(!q)return null;try{var r=await fetch("https://api.inaturalist.org/v1/taxa/autocomplete?q="+encodeURIComponent(q)+"&taxon_id=47126&locale=de&per_page=8",{headers:{Accept:"application/json"}});if(!r.ok)return null;var d=await r.json(),a=(d.results||[]).filter(function(t){return String(t.iconic_taxon_name||"").toLowerCase()==="plantae"});if(!a.length)return null;var sci=(base&&base.sci)||el("plantScientific").value.trim();return a.find(function(t){return sci&&String(t.name||"").toLowerCase()===sci.toLowerCase()})||a.find(function(t){return ["species","subspecies","variety","hybrid"].includes(String(t.rank||"").toLowerCase())})||a[0]}catch(e){return null}}
function bloomFromHistogram(d){var h=d&&d.results&&d.results.month_of_year||{},pairs=Object.keys(h).map(function(k){return[Number(k),Number(h[k])||0]}).filter(function(x){return x[0]>=1&&x[0]<=12}),total=pairs.reduce(function(a,x){return a+x[1]},0),mx=pairs.reduce(function(a,x){return Math.max(a,x[1])},0);if(total<4||!mx)return[];var min=total>=30?Math.max(2,Math.ceil(mx*.08)):1;return uniqueNums(pairs.filter(function(x){return x[1]>=min}).map(function(x){return x[0]}))}
async function inatBloomMonths(taxonId){if(!taxonId)return{months:[],source:""};var base="https://api.inaturalist.org/v1/observations/histogram?interval=month_of_year&term_id=12&term_value_id=13&quality_grade=research&taxon_id="+encodeURIComponent(taxonId);try{var r=await fetch(base+"&nelat=55.1&nelng=15.1&swlat=47.2&swlng=5.8"),d=r.ok?await r.json():null,m=bloomFromHistogram(d);if(m.length)return{months:m,source:"iNaturalist · Blühbeobachtungen Deutschland"};var r2=await fetch(base),d2=r2.ok?await r2.json():null,m2=bloomFromHistogram(d2);return{months:m2,source:m2.length?"iNaturalist · Blühbeobachtungen weltweit":""}}catch(e){return{months:[],source:""}}}
async function getInatGermanyPlace(){if(inatGermanyPlaceId!==null)return inatGermanyPlaceId||null;inatGermanyPlaceId=0;try{var r=await fetch("https://api.inaturalist.org/v1/places/autocomplete?q=Germany&per_page=20"),d=r.ok?await r.json():null,a=d&&d.results||[],p=a.find(function(x){var n=String(x.name||x.display_name||"").toLowerCase(),t=String(x.place_type_name||"").toLowerCase();return(n==="germany"||n.indexOf("germany")===0)&&(!t||t==="country")})||a.find(function(x){return String(x.name||"").toLowerCase()==="germany"});if(p)inatGermanyPlaceId=Number(p.id)||0}catch(e){}return inatGermanyPlaceId||null}
async function inatNativeGermany(taxonId){if(!taxonId)return"auto";try{var pid=await getInatGermanyPlace();if(!pid)return"auto";var r=await fetch("https://api.inaturalist.org/v1/taxa/"+encodeURIComponent(taxonId)+"?preferred_place_id="+pid),d=r.ok?await r.json():null,t=d&&d.results&&d.results[0];if(!t)return"auto";var a=Array.isArray(t.listed_taxa)?t.listed_taxa:[];for(var i=0;i<a.length;i++){var x=a[i],placeId=Number(x.place_id||(x.place&&x.place.id)||(x.list&&x.list.place_id)||0),m=String(x.establishment_means||"").toLowerCase();if(placeId===pid&&m){if(m==="native"||m==="endemic")return"yes";if(["introduced","naturalised","naturalized","managed","invasive"].includes(m))return"no"}}return"auto"}catch(e){return"auto"}}
async function gbifNativeGermany(sci){if(!sci)return{native:"auto",key:null};try{var r=await fetch("https://api.gbif.org/v1/species/match?kingdom=Plantae&name="+encodeURIComponent(sci)),m=r.ok?await r.json():null,key=m&&(m.usageKey||m.speciesKey||m.key);if(!key)return{native:"auto",key:null};var rd=await fetch("https://api.gbif.org/v1/species/"+key+"/distributions"),a=rd.ok?await rd.json():[];if(!Array.isArray(a))a=a&&a.results||[];for(var i=0;i<a.length;i++){var x=a[i],country=String(x.countryCode||x.country||x.locality||x.area||x.locationId||x.locationID||"").toLowerCase(),german=country==="de"||country==="deu"||country.indexOf("germany")>=0||country.indexOf("deutschland")>=0;if(!german)continue;var e=String(x.establishmentMeans||x.establishment_means||x.status||"").toLowerCase();if(e.indexOf("native")>=0||e.indexOf("endemic")>=0)return{native:"yes",key:key};if(e.indexOf("introduc")>=0||e.indexOf("natural")>=0||e.indexOf("invasive")>=0)return{native:"no",key:key}}return{native:"auto",key:key}}catch(e){return{native:"auto",key:null}}}
function trefleGermanStatus(data){var ds=data&&((data.distributions)||(data.distribution))||{},keys=[["native","yes"],["introduced","no"]];for(var i=0;i<keys.length;i++){var a=ds[keys[i][0]]||[];if(!Array.isArray(a))continue;for(var j=0;j<a.length;j++){var q=JSON.stringify(a[j]).toLowerCase();if(q.indexOf("germany")>=0||q.indexOf("deutschland")>=0||q.indexOf('"deu"')>=0||q.indexOf('"de"')>=0)return keys[i][1]}}return"auto"}
async function treflePlantData(sci){var token=String(state.settings.trefleKey||"").trim();if(!token||!sci)return null;try{var r=await fetch("https://trefle.io/api/v1/species/search?token="+encodeURIComponent(token)+"&q="+encodeURIComponent(sci)),d=r.ok?await r.json():null,a=d&&d.data||[];if(!a.length)return null;var x=a.find(function(v){return String(v.scientific_name||"").toLowerCase()===sci.toLowerCase()})||a[0],url=x.links&&x.links.self;if(!url)return null;if(url.charAt(0)==="/")url="https://trefle.io"+url;url+=(url.indexOf("?")>=0?"&":"?")+"token="+encodeURIComponent(token);var rd=await fetch(url),detail=rd.ok?await rd.json():null;return detail&&detail.data||null}catch(e){return null}}
function growthValue(data,key){var g=data&&data.growth||{},sp=data&&data.specifications||{};return g[key]!=null?g[key]:sp[key]}
function derivePlantCare(base,trefle,local,force,ctx){if(local&&local.rule)return;var name=(base.common||el("plantName").value||"").toLowerCase(),sci=(base.sci||el("plantScientific").value||"").toLowerCase(),family=(base.family||el("plantFamily").value||"").toLowerCase(),habit=String(growthValue(trefle,"growth_habit")||growthValue(trefle,"growth_form")||growthValue(trefle,"habit")||"").toLowerCase(),dur=Array.isArray(trefle&&trefle.duration)?trefle.duration.join(" ").toLowerCase():String(trefle&&trefle.duration||"").toLowerCase(),soil=Number(growthValue(trefle,"soil_humidity"));if(Number.isFinite(soil)&&soil>0){el("plantWater").value=soil>=7?"high":soil<=3?"low":"normal";addPlantField(ctx,"Wasserbedarf");addPlantSource(ctx,"Trefle")}var woodyFamilies=["hamamelidaceae","fagaceae","betulaceae","sapindaceae","magnoliaceae","pinaceae","cupressaceae","oleaceae","salicaceae"],woody=/tree|shrub|woody/.test(habit)||woodyFamilies.includes(family)||/baum|strauch|tree|shrub/.test(name),shrub=/shrub|subshrub/.test(habit)||/strauch|flieder|buddleja/.test(name+sci),perennial=/perennial/.test(dur+" "+habit)||["lamiaceae","asteraceae","geraniaceae","crassulaceae"].includes(family);if(!fieldMonths("fert").length){var fm=shrub?[3,4,5]:woody?[3,4]:perennial?[3,4,5]:[];if(fm.length){applyMonths("fert",fm,force,ctx,"Düngemonate");addPlantSource(ctx,"abgeleitete Pflegelogik")}}if(!fieldMonths("cut").length){var cm=shrub?[2,3]:perennial?[2,3]:[];if(cm.length){applyMonths("cut",cm,force,ctx,"Schnittmonate");addPlantSource(ctx,"abgeleitete Pflegelogik")}}}
async function enrichPlantForm(base,force){base=base||{common:el("plantName").value.trim(),sci:el("plantScientific").value.trim(),family:el("plantFamily").value.trim()};if(!base.common&&!base.sci){renderPlantDataStatus(null,"Bitte zuerst eine Pflanze auswählen oder einen botanischen Namen eingeben.","warn");return null}var seq=++plantEnrichSeq,ctx={sources:[],fields:[]};renderPlantDataStatus(null,"Pflege, Blüte und Herkunft werden abgeglichen …","loading");var local=applyLocalPlantKnowledge(base,!!force,ctx);var tax=await resolveInatPlant(base);if(seq!==plantEnrichSeq)return null;if(tax){if(!el("plantScientific").value&&tax.name){el("plantScientific").value=tax.name;addPlantField(ctx,"Botanischer Name")}var fam=plantSearchFamily(tax);if(fam&&!el("plantFamily").value){el("plantFamily").value=fam;addPlantField(ctx,"Familie")}addPlantSource(ctx,"iNaturalist");if(!fieldMonths("bloom").length){var bl=await inatBloomMonths(tax.id);if(seq!==plantEnrichSeq)return null;if(bl.months.length){applyMonths("bloom",bl.months,false,ctx,"Blühmonate");addPlantSource(ctx,bl.source)}}if(el("plantNative").value==="auto"){var iv=await inatNativeGermany(tax.id);if(seq!==plantEnrichSeq)return null;applyNative(iv,ctx,"iNaturalist · Deutschland")}}var sci=base.sci||el("plantScientific").value.trim();var gb=await gbifNativeGermany(sci);if(seq!==plantEnrichSeq)return null;if(gb&&gb.key)addPlantSource(ctx,"GBIF");if(el("plantNative").value==="auto"&&gb)applyNative(gb.native,ctx,"GBIF");var tr=await treflePlantData(sci);if(seq!==plantEnrichSeq)return null;if(tr){addPlantSource(ctx,"Trefle");var bm=trefleMonths(tr.growth&&tr.growth.bloom_months);if(!fieldMonths("bloom").length&&bm.length)applyMonths("bloom",bm,false,ctx,"Blühmonate");if(el("plantNative").value==="auto")applyNative(trefleGermanStatus(tr),ctx,"Trefle")}derivePlantCare(base,tr,local,!!force,ctx);state.plantDataMeta={sources:ctx.sources,fields:ctx.fields,enrichedAt:new Date().toISOString(),inatTaxonId:tax&&tax.id||null,gbifKey:gb&&gb.key||null};renderPlantDataStatus(state.plantDataMeta,ctx.fields.length?null:"Art abgeglichen. Fehlende Angaben bleiben bewusst auf „unbekannt“, wenn keine belastbare Quelle vorliegt.",ctx.fields.length?"good":"warn");renderPlantEcoPreview();return state.plantDataMeta}
'''
s=s[:pos]+engine+s[pos:]

# 9) Replace application functions so every selected/search-recognized plant is enriched.
s=re.sub(r'function applyPlantSearchResult\(x\)\{.*?\}\nfunction renderPlantSearchResults',
'''async function applyPlantSearchResult(x){if(!x||(!x.common&&!x.sci))return;el("plantName").value=x.common||x.sci;el("plantScientific").value=x.sci||"";if(x.family)el("plantFamily").value=x.family;hidePlantNameResults();if(el("plantNameAssist"))el("plantNameAssist").textContent="Aus "+x.source+" übernommen · Pflanzendaten werden ergänzt …";await enrichPlantForm(x,true);if(el("plantNameAssist"))el("plantNameAssist").textContent="Aus "+x.source+" übernommen · verfügbare Pflege- und Herkunftsdaten wurden ergänzt."}\nfunction renderPlantSearchResults''',s,count=1,flags=re.S)

s=re.sub(r'function applyPlantNetSpecies\(sp\)\{.*?\}\nfunction renderPlantNameResults',
'''async function applyPlantNetSpecies(sp){var x=plantNetSpeciesLabel(sp);if(!x.common&&!x.sci)return;el("plantName").value=x.common||x.sci;el("plantScientific").value=x.sci||"";el("plantFamily").value=x.family||"";hidePlantNameResults();if(el("plantNameAssist"))el("plantNameAssist").textContent="Aus Pl@ntNet übernommen · Pflanzendaten werden ergänzt …";await enrichPlantForm({common:x.common,sci:x.sci,family:x.family,source:"Pl@ntNet"},true)}\nfunction renderPlantNameResults''',s,count=1,flags=re.S)

# 10) Replace identifyPlant entirely to enrich after photo selection.
new_identify=r'''async function identifyPlant(){if(!state.photoFile){el("aiStatus").textContent="Bitte zuerst ein Foto auswählen.";return}var key=(state.settings.plantnetKey||"").trim();if(!key){openSettings("settingsPlantnet");notice("Für die KI-Erkennung zuerst die Pflanzenerkennung einrichten.");return}el("identifyBtn").disabled=true;el("aiStatus").textContent="Pflanze wird erkannt …";el("aiResults").innerHTML="";try{var fd=new FormData();fd.append("images",state.photoFile);var organ=el("plantOrgan").value;if(organ!=="auto")fd.append("organs",organ);var res=await fetch("https://my-api.plantnet.org/v2/identify/all?lang=de&include-related-images=false&api-key="+encodeURIComponent(key),{method:"POST",body:fd});if(!res.ok)throw new Error("PlantNet antwortet mit HTTP "+res.status);var data=await res.json();var rs=(data.results||[]).slice(0,5);if(!rs.length)throw new Error("Keine Pflanze erkannt");el("aiStatus").textContent="Vorschlag auswählen:";el("aiResults").innerHTML=rs.map(function(r,i){var sp=r.species||{},sci=sp.scientificNameWithoutAuthor||sp.scientificName||"",common=(sp.commonNames&&sp.commonNames[0])||sci,pc=Math.round((r.score||0)*100);return '<button class="airesult" type="button" data-i="'+i+'"><b>'+esc(common)+'</b><small>'+esc(sci)+' · '+pc+' %</small></button>'}).join("");document.querySelectorAll(".airesult").forEach(function(b){b.addEventListener("click",async function(){var r=rs[Number(b.dataset.i)],sp=r.species||{},sci=sp.scientificNameWithoutAuthor||sp.scientificName||"",common=(sp.commonNames&&sp.commonNames[0])||sci;el("plantName").value=common;el("plantScientific").value=sci;el("plantFamily").value=sp.family||"";hidePlantNameResults();if(el("plantNameAssist"))el("plantNameAssist").textContent="Aus der Fotoerkennung übernommen.";el("aiStatus").textContent="Übernommen. Pflege, Blüte und Herkunft werden ergänzt …";await enrichPlantForm({common:common,sci:sci,family:sp.family||"",source:"Pl@ntNet"},true);el("aiStatus").textContent="Übernommen. Verfügbare Pflege- und Herkunftsdaten wurden automatisch ergänzt."})})}catch(e){el("aiStatus").textContent="Erkennung fehlgeschlagen: "+e.message+". Bei einer lokal geöffneten Datei kann zusätzlich eine CORS-Freigabe bei PlantNet erforderlich sein."}finally{el("identifyBtn").disabled=false}}'''
s,n=re.subn(r'async function identifyPlant\(\)\{.*?\}\nfunction beginPlacePlant',new_identify+'\nfunction beginPlacePlant',s,count=1,flags=re.S)
if n!=1: raise SystemExit(f'identify replace {n}')

# 11) Provenance in detail view: add source line to Steckbrief grid.
one(
'''<div class="detail-kv"><span>Standort</span><b>'+esc(z?lightLabel(z.light):'nicht kartiert')+'</b></div></div></div><div class="detail-section"><h4>Pflegehistorie</h4>''',
'''<div class="detail-kv"><span>Standort</span><b>'+esc(z?lightLabel(z.light):'nicht kartiert')+'</b></div>'+(p.careMeta&&p.careMeta.sources&&p.careMeta.sources.length?'<div class="detail-kv" style="grid-column:1/-1"><span>Pflanzendaten</span><b>'+esc(p.careMeta.sources.join(' · '))+'</b></div>':'')+'</div></div><div class="detail-section"><h4>Pflegehistorie</h4>''',
'detail provenance')

# 12) Add listeners for refresh and optional Trefle token.
one(
'''el("saveApiKey").addEventListener("click",function(){state.settings.plantnetKey=el("plantnetKey").value.trim();save();renderHeader();notice("API-Schlüssel lokal gespeichert.")});''',
'''el("saveApiKey").addEventListener("click",function(){state.settings.plantnetKey=el("plantnetKey").value.trim();save();renderHeader();notice("API-Schlüssel lokal gespeichert.")});\nel("savePlantDataKey").addEventListener("click",function(){state.settings.trefleKey=el("trefleKey").value.trim();save();renderHeader();notice(state.settings.trefleKey?"Trefle-Token gespeichert. Zusätzliche Pflanzendaten sind aktiv.":"Trefle-Token entfernt. Die kostenlosen Standardquellen bleiben aktiv.")});\nel("refreshPlantDataBtn").addEventListener("click",function(){enrichPlantForm({common:el("plantName").value.trim(),sci:el("plantScientific").value.trim(),family:el("plantFamily").value.trim(),source:"manuell"},true)});''',
'listeners')

# Ensure the optional token is present in all default settings objects after broad replacements.
assert 'trefleKey:""' in s
for marker in ['async function enrichPlantForm','observations/histogram','api.gbif.org/v1/species/match','trefle.io/api/v1/species/search','id="plantDataStatus"','id="refreshPlantDataBtn"','id="trefleKey"','careMeta:state.plantDataMeta']:
    if marker not in s: raise SystemExit('missing '+marker)

p.write_text(s,encoding='utf-8')
print('patched',len(orig),'->',len(s))
