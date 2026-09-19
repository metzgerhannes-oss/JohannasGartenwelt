(function(){
"use strict";
if(window.__jgwCareCalendarV1)return;window.__jgwCareCalendarV1=true;

var SYNC_KEY="johannas_gartenwelt_sync_v1";
var MONTHS_LONG=["Januar","Februar","März","April","Mai","Juni","Juli","August","September","Oktober","November","Dezember"];
var expanded=false,rendering=false,scheduled=false;

function el(id){return document.getElementById(id)}
function esc(s){return String(s==null?"":s).replace(/[&<>"']/g,function(c){return{"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"}[c]})}
function norm(v){return String(v||"").normalize("NFD").replace(/[\u0300-\u036f]/g,"").toLowerCase().replace(/[^a-z0-9]+/g," ").trim()}
function appState(){return window.JGWCore&&window.JGWCore.getState?window.JGWCore.getState():(window.state||{})}
function textOf(p){return norm((p.name||"")+" "+(p.scientific||"")+" "+(typeof p.family==="string"?p.family:""))}
function monthName(m){return MONTHS_LONG[Number(m)-1]||""}
function windowLabel(a,b){return a===b?monthName(a):monthName(a)+"–"+monthName(b)}
function uniqueMonths(x){return Array.from(new Set((Array.isArray(x)?x:[]).map(Number).filter(function(m){return m>=1&&m<=12}))).sort(function(a,b){return a-b})}
function ranges(x){var a=uniqueMonths(x),out=[];if(!a.length)return out;var start=a[0],prev=a[0];for(var i=1;i<a.length;i++){if(a[i]===prev+1){prev=a[i];continue}out.push({start:start,end:prev});start=prev=a[i]}out.push({start:start,end:prev});return out}
function isFruitTree(p){var s=norm(p.scientific),n=norm(p.name),exact=["malus domestica","pyrus communis","cydonia oblonga","prunus avium","prunus cerasus","prunus domestica","prunus armeniaca","prunus persica"];return exact.some(function(x){return s===x||s.indexOf(x+" ")===0})||/\b(apfel|birne|zwetschge|pflaume|susskirsche|sauerkirsche|quitte|aprikose|pfirsich)\b/.test(n)}
function isBerry(p){var s=norm(p.scientific),n=norm(p.name);return /^(ribes|rubus|vaccinium)\b/.test(s)||/\b(johannisbeere|stachelbeere|himbeere|brombeere|heidelbeere)\b/.test(n)}
function isHydrangea(p){return /\bhydrangea\b|\bhortensie\b/.test(textOf(p))}
function isRose(p){var s=norm(p.scientific),n=norm(p.name);return /^rosa\b/.test(s)||/\brose\b|\brosen\b/.test(n)}
function isGrass(p){var s=norm(p.scientific),n=norm(p.name);return /^(miscanthus|pennisetum|panicum|calamagrostis|cortaderia|imperata|leymus|molinia|stipa)\b/.test(s)||/\b(pampasgras|chinaschilf|federborstengras|rutenhirse|reitgras|blutgras|strandroggen)\b/.test(n)}
function isClimber(p){var s=norm(p.scientific),n=norm(p.name);return /^(clematis|wisteria|parthenocissus|akebia|campsis|vitis)\b/.test(s)||/\b(waldrebe|wisteria|blauregen|jungfernrebe|akebie|klettertrompete|wein)\b/.test(n)}
function isTender(p){var s=norm(p.scientific),n=norm(p.name),a=["ficus carica","eucalyptus gunnii","photinia fraseri","cortaderia selloana","salvia rosmarinus","poliomintha bustamanta","albizia"];return a.some(function(x){return s===x||s.indexOf(x+" ")===0})||/\b(feige|eukalyptus|glanzmispel|pampasgras|rosmarin|seidenbaum)\b/.test(n)}

function speciesCutOverride(p){
  var s=norm(p.scientific),n=norm(p.name);
  return /^abeliophyllum distichum\b/.test(s)||/^forsythia\b/.test(s)||/^syringa\b/.test(s)||/^philadelphus\b/.test(s)||/^viburnum bodnantense\b/.test(s)||/^chaenomeles speciosa\b/.test(s)||/^wisteria\b/.test(s)||/^clematis montana\b/.test(s)||/^buddleja davidii\b/.test(s)||/^caryopteris clandonensis\b/.test(s)||/^campsis\b/.test(s)||/^hydrangea macrophylla\b/.test(s)||/^hydrangea paniculata\b/.test(s)||/^hydrangea quercifolia\b/.test(s)||/^ficus carica\b/.test(s)||/^hibiscus syriacus\b/.test(s)||/\b(forsythie|flieder|pfeifenstrauch|bodnant schneeball|zierquitte)\b/.test(n);
}
function speciesCare(p){
  var s=norm(p.scientific),n=norm(p.name),out=[];
  function push(key,title,icon,start,end,note,source){out.push({kind:"species",title:title,group:title.split(/[:–-]/)[0].trim(),icon:icon,start:start,end:end,plants:[p],note:note,source:source,key:"species|"+key+"|"+start+"|"+end})}
  if(/^abeliophyllum distichum\b/.test(s))push("abeliophyllum","Schneeforsythie nach der Blüte schneiden","✂️",3,4,"Nach der Blüte auslichten bzw. abgeblühte Triebe auf kräftige jüngere Triebe zurücknehmen. Nicht vor der Blüte schneiden.","RHS · Pruning Group 5");
  if(/^forsythia\b/.test(s)||/\bforsythie\b/.test(n))push("forsythia","Forsythie nach der Blüte schneiden","✂️",4,4,"Direkt nach der Blüte schneiden; späterer Schnitt reduziert die Blüte des Folgejahres.","RHS · Forsythia Growing Guide");
  if(/^syringa\b/.test(s)||/\bflieder\b/.test(n))push("syringa","Flieder nach der Blüte auslichten","✂️",6,6,"Nur leicht schneiden und bei Bedarf ältere oder störende Triebe auslichten. Starker Winterschnitt kostet Blüten.","RHS · Lilac Growing Guide");
  if(/^philadelphus\b/.test(s)||/\bpfeifenstrauch\b/.test(n))push("philadelphus","Pfeifenstrauch nach der Blüte schneiden","✂️",6,7,"Nach der Blüte einige ältere Triebe auf junge Seitentriebe ableiten bzw. einzelne alte Triebe an der Basis entfernen.","RHS · Philadelphus Growing Guide");
  if(/^viburnum bodnantense\b/.test(s)||/\bbodnant schneeball\b/.test(n))push("viburnum-bodnantense","Bodnant-Schneeball nach der Blüte auslichten","✂️",3,4,"Nach Ende der Winterblüte bei Bedarf auslichten; ältere Triebe können an der Basis entfernt werden.","RHS · Viburnum Growing Guide");
  if(/^chaenomeles speciosa\b/.test(s)||/\bzierquitte\b/.test(n))push("chaenomeles","Zierquitte nach der Blüte schneiden","✂️",4,5,"Nach der Blüte auf kräftige Knospen oder jüngeres Grundholz zurücknehmen. Bei Fruchtnutzung nur maßvoll schneiden.","RHS · Chaenomeles");
  if(/^wisteria\b/.test(s)){
    push("wisteria-winter","Wisteria – Winterschnitt","✂️",1,2,"Die im Sommer gekürzten Seitentriebe auf zwei bis drei Knospen zurücknehmen.","RHS · Wisteria Pruning Guide");
    push("wisteria-summer","Wisteria – Sommerschnitt","✂️",7,8,"Lange diesjährige Seitentriebe auf etwa fünf bis sechs Blätter einkürzen.","RHS · Wisteria Pruning Guide");
  }
  if(/^clematis montana\b/.test(s)||/\bberg waldrebe\b/.test(n))push("clematis-montana","Berg-Waldrebe nach der Blüte auslichten","✂️",5,6,"Clematis montana gehört zur Schnittgruppe 1: nur bei Bedarf direkt nach der Blüte auslichten oder einkürzen.","RHS · Clematis Group One");
  if(/^buddleja davidii\b/.test(s)||/\bsommerflieder\b/.test(n))push("buddleja-davidii","Sommerflieder kräftig zurückschneiden","✂️",3,4,"Nach den stärksten Frösten auf ein niedriges dauerhaftes Gerüst zurückschneiden; die Blüten entstehen am neuen Austrieb.","RHS · Buddleja Growing Guide");
  if(/^caryopteris clandonensis\b/.test(s)||/\bbartblume\b/.test(n))push("caryopteris","Bartblume zurückschneiden","✂️",3,4,"Erst wenn starke Fröste weitgehend vorbei sind, die Triebe auf wenige Knospen am Grundgerüst zurücknehmen.","RHS · Caryopteris Growing Guide");
  if(/^campsis\b/.test(s)||/\bklettertrompete\b/.test(n))push("campsis","Klettertrompete schneiden","✂️",2,3,"Seitentriebe im Spätwinter auf zwei bis drei Knospen am dauerhaften Gerüst einkürzen.","RHS · Campsis Growing Guide");
  if(/^hydrangea macrophylla\b/.test(s)||/\bgartenhortensie\b/.test(n))push("hydrangea-macrophylla","Gartenhortensie leicht schneiden","✂️",4,4,"Alte Blütenstände erst im Frühjahr bis zum ersten oder zweiten kräftigen Knospenpaar entfernen; nicht stark zurückschneiden.","RHS · Shrubby Hydrangeas");
  if(/^hydrangea paniculata\b/.test(s)||/\brispen hortensie\b/.test(n))push("hydrangea-paniculata","Rispen-Hortensie zurückschneiden","✂️",3,3,"Vor dem Austrieb die Vorjahrestriebe auf ein kräftiges Knospenpaar zurücknehmen; stärkerer Schnitt fördert große Blütenstände.","RHS · Hydrangea Pruning Guide");
  if(/^hydrangea quercifolia\b/.test(s))push("hydrangea-quercifolia","Eichenblättrige Hortensie auslichten","✂️",4,4,"Nur minimal schneiden: totes, beschädigtes oder zu langes Holz entfernen.","RHS · Hydrangea Pruning Guide");
  if(/^ficus carica\b/.test(s)||/\bechte feige\b/.test(n)){
    push("fig-spring","Feige – Frühjahrsschnitt","✂️",4,4,"Nach der Gefahr längerer harter Fröste frostgeschädigte, schwache oder ungünstige Triebe entfernen; Triebe mit überwinterten Fruchtansätzen möglichst erhalten.","RHS · Fig Pruning Guide");
    push("fig-summer","Feige – neue Triebe entspitzen","✂️",6,7,"Kräftige neue Triebe im Frühsommer nach etwa fünf Blättern entspitzen, wenn die Pflanze stärker verzweigen soll.","RHS · Fig Pruning Guide");
  }
  if(/^hibiscus syriacus\b/.test(s)||/\bstraucheibisch\b/.test(n))push("hibiscus-syriacus","Straucheibisch schneiden","✂️",3,3,"Vor dem kräftigen Austrieb totes Holz entfernen und bei Bedarf letztjährige Triebe einkürzen; die Blüte entsteht am neuen Holz.","RHS · Pruning summer-flowering shrubs");
  return out;
}
function isHerbaceousSpringCut(p){
  var s=norm(p.scientific);
  return /^(actaea simplex|achillea filipendulina|brunnera macrophylla|chrysanthemum morifolium|hemerocallis|hosta|hylotelephium spectabile|knautia macedonica|lomelosia caucasica|mentha piperita|salvia nemorosa|sanguisorba officinalis)\b/.test(s);
}
function isTenderPerennialCut(p){
  var s=norm(p.scientific);
  return /^(oenothera lindheimeri|penstemon barbatus)\b/.test(s);
}
function isTallPerennial(p){
  var s=norm(p.scientific);
  return /^(actaea simplex|achillea filipendulina|knautia macedonica|sanguisorba officinalis)\b/.test(s);
}
function groupFor(p,kind){if(isFruitTree(p))return{key:"obstbaeume",label:kind==="fert"?"Obstgehölze":"Obstbäume"};if(isBerry(p))return{key:"beeren",label:"Beerenobst"};if(isRose(p))return{key:"rosen",label:"Rosen"};if(isHydrangea(p))return{key:"hortensien",label:"Hortensien"};if(isGrass(p))return{key:"ziergraeser",label:"Ziergräser"};if(isClimber(p))return{key:"kletterpflanzen",label:"Kletterpflanzen"};var name=String(p.name||p.scientific||"Pflanzen").trim();return{key:"plant-"+norm(p.scientific||p.name).replace(/\s+/g,"-"),label:name}}
function qtyLabel(p){var q=Math.max(1,Number(p.quantity||1)),s=String(p.name||p.scientific||"Pflanze");return s+(q>1?" ×"+q:"")+(p.area?" · "+p.area:"")}
function add(map,c){var old=map[c.key];if(old){var ids={};old.plants.forEach(function(p){ids[String(p.id||p.name||p.scientific)]=1});c.plants.forEach(function(p){var id=String(p.id||p.name||p.scientific);if(!ids[id]){ids[id]=1;old.plants.push(p)}});return}map[c.key]=c}

function tasks(){
  var s=appState(),plants=Array.isArray(s.plants)?s.plants:[],practice=s.ecology&&s.ecology.practice||{},map={};
  function addCare(p,kind,months){
    var g=groupFor(p,kind),action=kind==="fert"?"düngen":"schneiden",icon=kind==="fert"?"🌱":"✂️";
    ranges(months).forEach(function(r){
      add(map,{kind:kind,title:g.label+" "+action,group:g.label,icon:icon,start:r.start,end:r.end,plants:[p],
        note:kind==="fert"?"Düngung an Pflanzenzustand, Boden und Witterung anpassen; lieber bedarfsgerecht als schematisch.":"Nur bei geeigneter Witterung schneiden. Vor jedem Schnitt auf belegte Nester und Tiere prüfen.",
        source:kind==="cut"?"LWG Gartenakademie · BNatSchG §39":"LWG Gartenakademie · Pflanzenprofil",
        key:[kind,g.key,r.start,r.end].join("|")});
    });
  }
  plants.forEach(function(p){
    addCare(p,"fert",p.fertMonths);
    var special=speciesCare(p);
    if(!speciesCutOverride(p))addCare(p,"cut",p.cutMonths);
    special.forEach(function(x){add(map,x)});
    if(isHerbaceousSpringCut(p))add(map,{kind:"spring",title:"Stauden zurückschneiden / ausputzen",group:"Stauden",icon:"🌿",start:3,end:4,plants:[p],note:"Abgestorbene Stängel vor dem neuen Austrieb bodennah entfernen. Neue Triebe und überwinternde Tiere schonen.",source:"RHS · Perennials: Cutting Back",key:"spring|perennials|3|4"});
    if(isTenderPerennialCut(p))add(map,{kind:"spring",title:"Frostempfindlichere Stauden zurückschneiden",group:"Stauden",icon:"🌿",start:4,end:5,plants:[p],note:"Alte Stängel erst zurücknehmen, wenn stärkere Fröste weitgehend vorbei sind; der alte Austrieb schützt die Krone im Winter.",source:"RHS · Perennials: Cutting Back",key:"spring|tender-perennials|4|5"});
    if(isTallPerennial(p))add(map,{kind:"support",title:"Hohe Stauden stützen",group:"Stauden",icon:"🪴",start:5,end:5,plants:[p],note:"Stützen früh setzen, bevor die Triebe lang und kopflastig werden.",source:"RHS · Perennial Growing Guide",key:"support|tall-perennials|5|5"});
    if(isFruitTree(p))add(map,{kind:"fruit",title:"Obstbäume – Fruchtbehang prüfen",group:"Obstbäume",icon:"🍎",start:6,end:7,plants:[p],note:"Nach dem natürlichen Junifall prüfen, ob der Behang sehr dicht ist. Bei Überbehang kann Ausdünnen Fruchtgröße und Aststabilität verbessern.",source:"RHS · Fruit Thinning",key:"fruit|tree-thinning|6|7"});
    if(isGrass(p)&&!ranges(p.cutMonths).length){
      var g=groupFor(p,"cut");add(map,{kind:"spring",title:g.label+" zurückschneiden",group:g.label,icon:"🌾",start:3,end:3,plants:[p],note:"Vertrocknete Halme erst gegen Ende des Winters bzw. vor dem Neuaustrieb zurücknehmen.",source:"RHS · Gartenwelt-Pflegeregel",key:"spring-grass|"+g.key+"|3|3"});
    }
    if(norm(p.scientific).indexOf("cortaderia selloana")===0||norm(p.name).indexOf("pampasgras")>=0){
      add(map,{kind:"winter",title:"Pampasgras winterfest machen",group:"Pampasgras",icon:"❄️",start:11,end:11,plants:[p],note:"Blattschopf locker zusammenbinden und das Herz besonders vor Winternässe schützen.",source:"RHS · Gartenwelt-Pflegeregel",key:"winter|pampas|11|11"});
    }
    if(p.type==="pot"||p.type==="balcony"){
      add(map,{kind:"winter",title:"Kübelpflanzen winterfest machen",group:"Kübelpflanzen",icon:"🪴",start:10,end:10,plants:[p],note:"Gefäße gegen Durchfrieren schützen, empfindliche Arten rechtzeitig an einen passenden Überwinterungsplatz bringen.",source:"RHS · Gartenwelt-Winterhärtecheck",key:"winter|containers|10|10"});
    }else if(isTender(p)){
      add(map,{kind:"winter",title:"Empfindliche Pflanzen auf Winterschutz prüfen",group:"Empfindliche Pflanzen",icon:"❄️",start:10,end:10,plants:[p],note:"Standort, Sorte und aktuelle Wetterprognose beachten. Bei Bedarf Wurzelbereich schützen oder Pflanze einpacken.",source:"Gartenwelt-Winterhärteprofile · RHS",key:"winter|tender|10|10"});
    }
    if(isClimber(p)){
      add(map,{kind:"support",title:"Kletterpflanzen: Bindungen und Kletterhilfen prüfen",group:"Kletterpflanzen",icon:"🪢",start:3,end:3,plants:[p],note:"Lose, einschneidende oder beschädigte Bindungen ersetzen und Kletterhilfen vor dem starken Austrieb kontrollieren.",source:"Gartenwelt-Pflegeregel",key:"support|climbers|3|3"});
    }
    var recent=[p.plantedSince,p.transplanted].filter(Boolean).sort().slice(-1)[0];
    if(recent){var d=new Date(recent+"T12:00:00Z"),age=(Date.now()-d.getTime())/86400000;if(Number.isFinite(age)&&age>=0&&age<=400)add(map,{kind:"winter",title:"Jungpflanzen: Wurzelbereich vor Winter schützen",group:"Jungpflanzen",icon:"🍂",start:10,end:11,plants:[p],note:"Bei jungen bzw. frisch umgesetzten Pflanzen den Wurzelbereich vor starken Frösten schützen; Staunässe vermeiden.",source:"Gartenwelt-Anwachsphase · RHS",key:"winter|young|10|11"})}
  });
  if(practice.leaveStemsInWinter)add(map,{kind:"nature",title:"Überwinterte Staudenstängel behutsam zurücknehmen",group:"Naturgarten",icon:"🐝",start:3,end:4,plants:[],note:"Nicht alles auf einmal räumen. Markhaltige Stängel und überwinternde Insekten möglichst schonend behandeln.",source:"LWG Gartenakademie · Naturgarten-Praxis",key:"nature|stems|3|4"});
  if(practice.leavesPartlyRemain)add(map,{kind:"nature",title:"Laub als Winterschutz teilweise liegen lassen",group:"Naturgarten",icon:"🍂",start:10,end:11,plants:[],note:"Laub in geeigneten Beet- und Rückzugsbereichen belassen; Rasen und empfindliche immergrüne Polster frei halten.",source:"Naturgarten-Praxis",key:"nature|leaves|10|11"});
  return Object.keys(map).map(function(k){return map[k]}).sort(function(a,b){return a.start-b.start||a.title.localeCompare(b.title,"de")});
}

function nextMonths(n){var d=new Date(),a=[];d=new Date(d.getFullYear(),d.getMonth(),1);for(var i=0;i<n;i++){var x=new Date(d.getFullYear(),d.getMonth()+i,1);a.push({m:x.getMonth()+1,y:x.getFullYear()})}return a}
function taskForMonth(all,m){return all.filter(function(t){return t.start===m})}
function taskHtml(t){var affected=t.plants.length?t.plants.map(qtyLabel).sort(function(a,b){return a.localeCompare(b,"de")}):[];return '<details class="jgw-care-item"><summary><span class="jgw-care-icon">'+t.icon+'</span><span><b>'+esc(t.title)+'</b><small>'+esc(windowLabel(t.start,t.end))+(affected.length?" · "+affected.length+" Pflanz"+(affected.length===1?"e":"en"):"")+'</small></span></summary><div class="jgw-care-detail">'+(affected.length?'<div><strong>Betrifft:</strong> '+esc(affected.join(" · "))+'</div>':'')+'<div>'+esc(t.note)+'</div><div class="jgw-care-source">'+esc(t.source)+'</div></div></details>'}
function renderCalendar(){
  var grid=el("calendarGrid"),toggle=el("calendarToggle");if(!grid||rendering)return;rendering=true;
  try{var all=tasks(),months=nextMonths(expanded?12:3);grid.dataset.jgwCareRendering="1";grid.innerHTML=months.map(function(mm,idx){var items=taskForMonth(all,mm.m),label=new Date(mm.y,mm.m-1,1).toLocaleDateString("de-DE",{month:"long",year:"numeric"});return '<div class="calmonth"><div class="topline"><h3>'+(idx===0?"Jetzt · ":"")+esc(label)+'</h3></div>'+(items.length?items.map(taskHtml).join(""):'<div class="muted">Keine saisonale Aufgabe startet in diesem Monat.</div>')+'</div>'}).join("");if(toggle)toggle.textContent=expanded?"Nur die nächsten 3 Monate":"Ganzes Pflegejahr anzeigen";bindExports();ensureAutoCalendar();setTimeout(function(){delete grid.dataset.jgwCareRendering},0)}finally{rendering=false}
}
function schedule(){if(scheduled)return;scheduled=true;requestAnimationFrame(function(){scheduled=false;renderCalendar()})}

function icsEsc(s){return String(s==null?"":s).replace(/\\/g,"\\\\").replace(/\r?\n/g,"\\n").replace(/,/g,"\\,").replace(/;/g,"\\;")}
function icsDate(y,m,d){return String(y)+String(m).padStart(2,"0")+String(d).padStart(2,"0")}
function icsStamp(){return new Date().toISOString().replace(/[-:]/g,"").replace(/\.\d{3}Z$/,"Z")}
function downloadIcs(filterMonths,filename,name){
  var all=tasks(),events=[];filterMonths.forEach(function(mm){all.filter(function(t){return t.start===mm.m}).forEach(function(t){var affected=t.plants.length?t.plants.map(qtyLabel).join("; "):"gesamter Garten",uid=("jgw-manual-"+mm.y+"-"+t.key).replace(/[^a-z0-9@|.-]+/gi,"-");events.push(["BEGIN:VEVENT","UID:"+icsEsc(uid+"@johannas-gartenwelt"),"DTSTAMP:"+icsStamp(),"DTSTART;VALUE=DATE:"+icsDate(mm.y,t.start,1),"DTEND;VALUE=DATE:"+icsDate(mm.y,t.start,2),"SUMMARY:"+icsEsc(t.icon+" "+t.title),"DESCRIPTION:"+icsEsc("Zeitfenster: "+windowLabel(t.start,t.end)+"\nBetrifft: "+affected+"\n\n"+t.note+"\n\n"+t.source),"CATEGORIES:Gartenpflege","TRANSP:TRANSPARENT","STATUS:CONFIRMED","END:VEVENT"].join("\r\n"))})});
  if(!events.length){alert("Für diesen Zeitraum sind keine Pflegeaufgaben hinterlegt.");return}
  var lines=["BEGIN:VCALENDAR","VERSION:2.0","PRODID:-//Johannas Gartenwelt//Pflegekalender//DE","CALSCALE:GREGORIAN","METHOD:PUBLISH","X-WR-CALNAME:"+icsEsc(name||"Johanna´s Gartenwelt – Pflege")].concat(events,["END:VCALENDAR",""]),blob=new Blob(["\ufeff"+lines.join("\r\n")],{type:"text/calendar;charset=utf-8"}),a=document.createElement("a");a.href=URL.createObjectURL(blob);a.download=filename||"Johannas_Gartenwelt_Pflege.ics";document.body.appendChild(a);a.click();setTimeout(function(){URL.revokeObjectURL(a.href);a.remove()},500)
}
function seasonMonths(key){var d={spring:[3,4,5],summer:[6,7,8],autumn:[9,10,11],winter:[12,1,2]}[key]||[],now=new Date(),y=now.getFullYear(),m=now.getMonth()+1,base=y;if(key==="winter"){base=m<=2?y-1:y}else if(d.length&&m>d[d.length-1])base=y+1;return d.map(function(mm){return{m:mm,y:key==="winter"&&mm<12?base+1:base}})}
function bindExports(){
  document.querySelectorAll(".seasonExport").forEach(function(btn){if(btn.dataset.jgwGrouped==="1")return;var clone=btn.cloneNode(true);clone.dataset.jgwGrouped="1";btn.parentNode.replaceChild(clone,btn);clone.addEventListener("click",function(){var k=clone.dataset.season,months=seasonMonths(k),label=clone.textContent.replace(/\.ics$/,"");downloadIcs(months,"Johannas_Gartenwelt_"+label.replace(/[^a-zA-Z0-9äöüÄÖÜß_-]+/g,"_")+".ics","Johanna´s Gartenwelt – "+label)})});
  var yr=el("exportCareYear");if(yr&&yr.dataset.jgwGrouped!=="1"){var c=yr.cloneNode(true);c.dataset.jgwGrouped="1";yr.parentNode.replaceChild(c,yr);c.addEventListener("click",function(){downloadIcs(nextMonths(12),"Johannas_Gartenwelt_Pflege_naechste_12_Monate.ics","Johanna´s Gartenwelt – Pflegejahr")})}
}
function readSync(){try{return JSON.parse(localStorage.getItem(SYNC_KEY)||"{}")}catch(e){return{}}}
function configured(c){return /^https:\/\/[^/]+\.supabase\.co$/i.test(String(c.url||"").replace(/\/+$/,""))&&String(c.key||"").length>10&&String(c.gardenId||"").length>=6&&String(c.pin||"").length>=6}
async function sha256Hex(s){var b=await crypto.subtle.digest("SHA-256",new TextEncoder().encode(s));return Array.from(new Uint8Array(b)).map(function(x){return x.toString(16).padStart(2,"0")}).join("")}
async function rpc(c,fn,args){var r=await fetch(String(c.url).replace(/\/+$/,"")+"/rest/v1/rpc/"+fn,{method:"POST",headers:{"apikey":c.key,"Content-Type":"application/json"},body:JSON.stringify(args||{})}),txt=await r.text(),d=null;try{d=txt?JSON.parse(txt):null}catch(e){d=txt}if(!r.ok)throw new Error(d&&d.message?d.message:"HTTP "+r.status);if(Array.isArray(d)&&d.length===1)d=d[0];return d}
async function feedUrl(rotate){var c=readSync();if(!configured(c))throw new Error("Geräte-Synchronisierung ist noch nicht vollständig eingerichtet.");var secret=await sha256Hex(String(c.gardenId).trim().toLowerCase()+"|"+String(c.pin)),fn=rotate?"jgw_rotate_calendar_token":"jgw_get_calendar_token",d=await rpc(c,fn,{p_garden_id:String(c.gardenId).trim().toLowerCase(),p_secret_hash:secret});if(!d||d.ok!==true||!d.calendar_token)throw new Error("Kalenderzugang konnte nicht erzeugt werden.");return String(c.url).replace(/\/+$/,"")+"/functions/v1/jgw-calendar?token="+encodeURIComponent(d.calendar_token)}
function ensureAutoCalendar(){
  var tools=document.querySelector(".calendar-tools");if(!tools)return;var box=document.querySelector(".jgw-auto-calendar");if(!box){box=document.createElement("div");box.className="jgw-auto-calendar";var summary=tools.querySelector("summary");if(summary&&summary.nextSibling)tools.insertBefore(box,summary.nextSibling);else tools.appendChild(box)}var c=readSync();
  if(!configured(c)){box.innerHTML='<div class="label">Automatischer Kalender</div><div class="muted" style="margin-top:5px">Für einen automatisch aktualisierten Pflegekalender zuerst die Geräte-Synchronisierung unter Einstellungen verbinden.</div>';return}
  box.innerHTML='<div class="label">Automatischer Kalender</div><div class="muted" style="margin-top:5px">Einmal abonnieren. Änderungen an Pflanzen und Pflegefenstern werden danach automatisch beim Kalender-Abruf übernommen – wie beim Abfallkalender.</div><div class="actions" style="margin-top:9px"><button class="btn small jgw-subscribe-care" type="button">Pflegekalender abonnieren</button><button class="btn secondary small jgw-copy-care" type="button">Kalender-Link kopieren</button></div><details class="jgw-calendar-security"><summary>Kalenderzugang</summary><div class="muted" style="margin-top:6px">Der Kalender-Link enthält einen eigenen langen Zugriffsschlüssel, aber weder Garten-PIN noch API-Schlüssel. Wer den Link kennt, kann die gruppierten Pflegetermine sehen.</div><button class="btn ghost small jgw-reset-care" style="margin-top:8px" type="button">Kalender-Link zurücksetzen</button></details>';
  var sub=box.querySelector(".jgw-subscribe-care"),copy=box.querySelector(".jgw-copy-care"),reset=box.querySelector(".jgw-reset-care");
  sub.addEventListener("click",async function(){sub.disabled=true;sub.textContent="Kalender wird vorbereitet …";try{var u=await feedUrl(false);location.href=u.replace(/^https:/i,"webcal:")}catch(e){alert(e.message||String(e))}finally{sub.disabled=false;sub.textContent="Pflegekalender abonnieren"}});
  copy.addEventListener("click",async function(){copy.disabled=true;try{var u=await feedUrl(false);await navigator.clipboard.writeText(u);copy.textContent="Link kopiert ✓";setTimeout(function(){copy.textContent="Kalender-Link kopieren"},1800)}catch(e){alert(e.message||String(e))}finally{copy.disabled=false}});
  reset.addEventListener("click",async function(){if(!confirm("Der bisherige Kalender-Link funktioniert danach nicht mehr. Neuen Link erzeugen?"))return;reset.disabled=true;try{var u=await feedUrl(true);if(navigator.clipboard)await navigator.clipboard.writeText(u);alert("Neuer Kalender-Link erzeugt. Der alte Link ist ungültig. Der neue Link wurde kopiert.")}catch(e){alert(e.message||String(e))}finally{reset.disabled=false}})
}
function installStyle(){if(el("jgw-care-calendar-style"))return;var s=document.createElement("style");s.id="jgw-care-calendar-style";s.textContent=".jgw-care-item{border-top:1px solid #efe6db;padding:8px 0}.jgw-care-item:first-of-type{border-top:0}.jgw-care-item summary{display:grid;grid-template-columns:30px minmax(0,1fr);gap:8px;align-items:center;list-style:none;cursor:pointer}.jgw-care-item summary::-webkit-details-marker{display:none}.jgw-care-icon{width:30px;height:30px;border-radius:9px;display:grid;place-items:center;background:#f5eee6}.jgw-care-item b{display:block;font-size:13px;color:var(--forest-dark)}.jgw-care-item small{display:block;margin-top:2px;color:var(--muted);font-size:10px}.jgw-care-detail{padding:8px 0 2px 38px;font-size:11px;line-height:1.45;color:var(--muted)}.jgw-care-detail>div+div{margin-top:5px}.jgw-care-source{font-size:9.5px!important;opacity:.86}.jgw-auto-calendar{padding:12px 0 14px;border-bottom:1px solid #eee3d8;margin-bottom:11px}.jgw-calendar-security{margin-top:10px}.jgw-calendar-security summary{font-size:11px}";document.head.appendChild(s)}
function start(){installStyle();var grid=el("calendarGrid"),toggle=el("calendarToggle");if(toggle)toggle.addEventListener("click",function(){expanded=!expanded;setTimeout(schedule,0)},true);if(grid)new MutationObserver(function(){if(grid.dataset.jgwCareRendering==="1"||rendering)return;schedule()}).observe(grid,{childList:true,subtree:true});document.querySelectorAll('.tab[data-view="calendar"]').forEach(function(b){b.addEventListener("click",function(){setTimeout(schedule,40)})});schedule()}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",start,{once:true});else start();
window.addEventListener("load",schedule,{once:true});
window.JGWCareCalendar={tasks:tasks,render:renderCalendar,feedUrl:feedUrl,hasSpeciesCutOverride:speciesCutOverride,cutTasksForPlant:function(p){return speciesCare(p)}};if(window.JGWCore&&JGWCore.renderCareViews)setTimeout(function(){JGWCore.renderCareViews()},0);
})();