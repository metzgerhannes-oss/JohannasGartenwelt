from pathlib import Path

p=Path('index.html')
s=p.read_text(encoding='utf-8')

s=s.replace('Name eintippen – ab 3 Zeichen sucht Pl@ntNet passende Arten.','Name eintippen – ab 3 Zeichen sucht die Gartenwelt passende Pflanzennamen.')
s=s.replace('plantNameSearchTimer=setTimeout(function(){searchPlantNetSpecies(q)},350)','plantNameSearchTimer=setTimeout(function(){searchPlantNames(q)},350)')
s=s.replace('if(this.value.trim().length>=3)searchPlantNetSpecies(this.value)','if(this.value.trim().length>=3)searchPlantNames(this.value)')

anchor='async function identifyPlant(){'
if anchor not in s:
    raise SystemExit('identifyPlant anchor missing')

insert=r'''function plantSearchFamily(t){var a=Array.isArray(t&&t.ancestors)?t.ancestors:[],f=a.find(function(x){return x&&x.rank==="family"});return f&&f.name?f.name:""}
function normalizeInatPlantTaxon(t){return{source:"iNaturalist",common:t.preferred_common_name||t.matched_term||t.name||"",sci:t.name||"",family:plantSearchFamily(t),raw:t}}
function normalizePlantNetTaxon(sp){var x=plantNetSpeciesLabel(sp);return{source:"Pl@ntNet",common:x.common||x.sci,sci:x.sci||"",family:x.family||"",raw:sp}}
function applyPlantSearchResult(x){if(!x||(!x.common&&!x.sci))return;el("plantName").value=x.common||x.sci;el("plantScientific").value=x.sci||"";if(x.family)el("plantFamily").value=x.family;var rule=applyCareRule(x.common,x.sci);if(rule){el("plantWater").value=rule.water;setCheckedMonths("fert",rule.fert);setCheckedMonths("cut",rule.cut);el("plantNameAssist").textContent="Aus "+x.source+" übernommen · Pflegeprofil wurde vorbelegt."}else el("plantNameAssist").textContent="Aus "+x.source+" übernommen · Pflegezeiten bei Bedarf unter Weitere Angaben ergänzen.";hidePlantNameResults();renderPlantEcoPreview()}
function renderPlantSearchResults(rs){var box=el("plantNameResults");if(!box)return;if(!rs.length){box.innerHTML="";show("plantNameResults",false);el("plantNameAssist").textContent="Kein passender Pflanzenname gefunden – der Name kann trotzdem frei eingetragen werden.";return}box.innerHTML=rs.map(function(x,i){var detail=(x.sci||"")+(x.family?" · "+x.family:"")+(x.source?" · "+x.source:"");return '<button class="plant-name-result" type="button" data-i="'+i+'" role="option"><b>'+esc(x.common||x.sci)+'</b><small>'+esc(detail)+'</small></button>'}).join("");show("plantNameResults",true);box.querySelectorAll(".plant-name-result").forEach(function(b){b.addEventListener("click",function(){applyPlantSearchResult(rs[Number(b.dataset.i)])})})}
async function searchPlantNames(query){var q=String(query||"").trim(),assist=el("plantNameAssist"),key=(state.settings.plantnetKey||"").trim();if(q.length<3){hidePlantNameResults();if(assist)assist.textContent="Name eintippen – ab 3 Zeichen sucht die Gartenwelt passende Pflanzennamen.";return}var seq=++plantNameSearchSeq;if(assist)assist.textContent="Pflanzennamen werden gesucht …";var jobs=[];jobs.push(fetch("https://api.inaturalist.org/v1/taxa/autocomplete?q="+encodeURIComponent(q)+"&taxon_id=47126&locale=de&per_page=10",{headers:{"Accept":"application/json"}}).then(async function(res){if(!res.ok)throw new Error("iNaturalist HTTP "+res.status);var data=await res.json();return(data.results||[]).filter(function(t){return String(t.iconic_taxon_name||"").toLowerCase()==="plantae"||String(t.rank||"").toLowerCase()==="kingdom"&&String(t.name||"").toLowerCase()==="plantae"}).map(normalizeInatPlantTaxon)}));if(key)jobs.push(fetch("https://my-api.plantnet.org/v2/species?lang=de&page=1&pageSize=10&prefix="+encodeURIComponent(q)+"&api-key="+encodeURIComponent(key)).then(async function(res){if(!res.ok)throw new Error("Pl@ntNet HTTP "+res.status);var data=await res.json();var arr=Array.isArray(data)?data:(Array.isArray(data.results)?data.results:[]);return arr.map(normalizePlantNetTaxon)}));try{var settled=await Promise.allSettled(jobs);if(seq!==plantNameSearchSeq)return;var merged=[],seen=new Set();settled.forEach(function(r){if(r.status!=="fulfilled")return;(r.value||[]).forEach(function(x){var k=String(x.sci||x.common||"").trim().toLowerCase();if(!k||seen.has(k))return;seen.add(k);merged.push(x)})});renderPlantSearchResults(merged.slice(0,10));if(merged.length&&assist)assist.textContent="Vorschlag antippen oder den Namen frei weiterschreiben. Suche über iNaturalist"+(key?" + Pl@ntNet":"")+".";else if(assist)assist.textContent="Kein passender Pflanzenname gefunden – freie Eingabe ist weiterhin möglich."}catch(e){if(seq!==plantNameSearchSeq)return;hidePlantNameResults();if(assist)assist.textContent="Pflanzensuche gerade nicht erreichbar – der Name kann trotzdem frei eingetragen werden."}}
'''

s=s.replace(anchor, insert+anchor, 1)

p.write_text(s,encoding='utf-8')
print('updated',len(s))
