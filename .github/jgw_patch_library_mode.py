from pathlib import Path

p = Path('jgw-library-nav.js')
s = p.read_text(encoding='utf-8')

# 1) Make the collection pills in "Mein Garten" real navigation controls.
marker = '  var addView=document.createElement("section");'
nav_block = '''  function openGardenCollection(kind){
    kind=["plants","habitats","animals"].includes(kind)?kind:"plants";
    if(typeof window.setNatureTab==="function"){
      window.setNatureTab(kind);
    }else{
      var panes={plants:"naturePlantsPane",habitats:"natureHabitatsPane",animals:"natureAnimalsPane"};
      Object.keys(panes).forEach(function(k){var pane=el(panes[k]);if(pane)pane.classList.toggle("hidden",k!==kind)});
      qa(".nature-tab").forEach(function(b){var active=b.dataset.nature===kind;b.classList.toggle("active",active);b.setAttribute("aria-selected",String(active))});
      if(kind==="habitats"&&typeof window.renderHabitats==="function")window.renderHabitats();
      if(kind==="animals"&&typeof window.renderAnimals==="function")window.renderAnimals();
    }
    var target=el(kind==="plants"?"naturePlantsPane":kind==="habitats"?"natureHabitatsPane":"natureAnimalsPane");
    if(target)setTimeout(function(){target.scrollIntoView({behavior:"smooth",block:"start"})},40);
  }
  if(nTabs){
    qa(".nature-tab",nTabs).forEach(function(b){
      b.setAttribute("aria-selected",String(b.classList.contains("active")));
      b.addEventListener("click",function(){openGardenCollection(b.dataset.nature)});
    });
  }

'''
if 'function openGardenCollection(kind)' not in s:
    if marker not in s:
        raise SystemExit('nav insertion marker missing')
    s = s.replace(marker, nav_block + marker, 1)

# 2) Add styling for the Mein-Garten library switch.
css_marker = '    .jgw-library-search-wrap{margin-top:14px;display:grid;grid-template-columns:minmax(0,1fr) auto;gap:8px}\n'
css_add = '''    .jgw-library-scope{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-top:14px;padding:11px 13px;border:1px solid #e1d6c9;border-radius:16px;background:linear-gradient(180deg,#fffdf9,#f8f3eb)}
    .jgw-library-scope-copy b{display:block;color:var(--forest-dark);font-size:14px}.jgw-library-scope-copy small{display:block;color:var(--muted);font-size:10px;margin-top:2px;line-height:1.35}
    .jgw-scope-switch{position:relative;width:52px;height:30px;flex:0 0 auto;border:0;border-radius:999px;background:#d9d2c8;padding:0;transition:background .16s ease}
    .jgw-scope-switch:after{content:"";position:absolute;width:24px;height:24px;left:3px;top:3px;border-radius:50%;background:#fff;box-shadow:0 2px 7px rgba(0,0,0,.18);transition:transform .16s ease}
    .jgw-scope-switch[aria-checked="true"]{background:linear-gradient(135deg,var(--forest),var(--sage))}.jgw-scope-switch[aria-checked="true"]:after{transform:translateX(22px)}
    .jgw-library-own .jgw-library-photo .jgw-source{background:rgba(63,95,67,.84)}
'''
if '.jgw-library-scope{' not in s:
    if css_marker not in s:
        raise SystemExit('css insertion marker missing')
    s = s.replace(css_marker, css_add + css_marker, 1)

# 3) Add the scope switch to the library header.
old_html = '''      </div>
      <div class="jgw-library-search-wrap"><input class="jgw-library-search" id="jgwLibrarySearch" type="search" autocomplete="off" placeholder="Pflanze suchen …"><button class="btn secondary" id="jgwLibraryClear" type="button">Entdecken</button></div>
      <div class="jgw-library-note" id="jgwLibraryHint">Beliebte Pflanzen zum Durchstöbern. Ab drei Buchstaben kannst du nach weiteren Pflanzen suchen.</div>
'''
new_html = '''      </div>
      <div class="jgw-library-scope">
        <span class="jgw-library-scope-copy"><b>Mein Garten</b><small id="jgwLibraryScopeText">Nur Pflanzen und Tiere aus deinem eigenen Garten anzeigen.</small></span>
        <button class="jgw-scope-switch" id="jgwLibraryScope" type="button" role="switch" aria-checked="true" aria-label="Mein Garten anzeigen"></button>
      </div>
      <div class="jgw-library-search-wrap"><input class="jgw-library-search" id="jgwLibrarySearch" type="search" autocomplete="off" placeholder="Im eigenen Garten suchen …"><button class="btn secondary" id="jgwLibraryClear" type="button">Alle anzeigen</button></div>
      <div class="jgw-library-note" id="jgwLibraryHint">Deine eigenen Pflanzen werden angezeigt.</div>
'''
if 'id="jgwLibraryScope"' not in s:
    if old_html not in s:
        raise SystemExit('library html marker missing')
    s = s.replace(old_html, new_html, 1)

# 4) Add personal-library rendering helpers.
state_marker = '  var libraryKind="plants",libraryTimer=null,librarySeq=0,seedCache={plants:null,animals:null};\n'
state_repl = '  var libraryKind="plants",libraryOwn=true,libraryTimer=null,librarySeq=0,seedCache={plants:null,animals:null};\n'
if state_marker in s:
    s = s.replace(state_marker, state_repl, 1)
elif 'libraryOwn=true' not in s:
    raise SystemExit('library state marker missing')

render_marker = '  async function hydrateSeeds(kind){\n'
helpers = '''  function ownPlantPhoto(p){var m=p&&p.careMeta||{};return p&&p.photo||m.refPhoto||""}
  function ownAnimalKey(a){return a&&a.taxonId?"inat:"+a.taxonId:"name:"+String(a&& (a.scientific||a.name)||"").trim().toLowerCase()}
  function ownAnimalGroups(){var g={};((window.state&&window.state.animals)||[]).forEach(function(a){var k=ownAnimalKey(a);if(!g[k])g[k]={key:k,items:[]};g[k].items.push(a)});return Object.keys(g).map(function(k){var x=g[k];x.items.sort(function(a,b){return String(b.date||"").localeCompare(String(a.date||""))});x.latest=x.items[0];return x}).sort(function(a,b){return String(b.latest&&b.latest.date||"").localeCompare(String(a.latest&&a.latest.date||""))})}
  function renderOwnLibrary(){
    var grid=el("jgwLibraryGrid");if(!grid)return;
    var term=String(el("jgwLibrarySearch")&&el("jgwLibrarySearch").value||"").trim().toLowerCase();
    grid.classList.add("jgw-library-own");
    if(libraryKind==="plants"){
      var items=((window.state&&window.state.plants)||[]).filter(function(p){return !term||String(p.name||"").toLowerCase().includes(term)||String(p.scientific||"").toLowerCase().includes(term)||String(p.area||"").toLowerCase().includes(term)});
      if(!items.length){grid.innerHTML='<div class="jgw-library-empty">'+(term?'Keine eigene Pflanze passt zur Suche.':'Noch keine Pflanzen im eigenen Garten gespeichert.')+'</div>';return}
      grid.innerHTML=items.map(function(p,i){var photo=ownPlantPhoto(p),qty=Math.max(1,Number(p.quantity||1));return '<button class="jgw-library-card jgw-own-plant" type="button" data-i="'+i+'"><div class="jgw-library-photo">'+(photo?'<img src="'+esc(photo)+'" alt="'+esc(p.name||"Pflanze")+'">':'<span>🌿</span>')+'<span class="jgw-source">Mein Garten</span></div><div class="jgw-library-body"><div class="jgw-library-name">'+esc(p.name||"Pflanze")+'</div><div class="jgw-library-latin">'+esc(p.scientific||p.area||"")+'</div><div class="jgw-library-meta"><span class="jgw-library-chip">'+qty+'× im Garten</span>'+(p.area?'<span class="jgw-library-chip">'+esc(p.area)+'</span>':'')+'</div></div></button>'}).join("");
      qa(".jgw-own-plant",grid).forEach(function(b){b.addEventListener("click",function(){var p=items[Number(b.dataset.i)];if(p&&typeof window.openPlantDetail==="function")window.openPlantDetail(p.id)})});
    }else{
      var groups=ownAnimalGroups().filter(function(g){var a=g.latest||{};return !term||String(a.name||"").toLowerCase().includes(term)||String(a.scientific||"").toLowerCase().includes(term)||animalGroupLabel(a.group).toLowerCase().includes(term)});
      if(!groups.length){grid.innerHTML='<div class="jgw-library-empty">'+(term?'Kein eigenes Tier passt zur Suche.':'Noch keine Tierbeobachtungen im eigenen Garten gespeichert.')+'</div>';return}
      grid.innerHTML=groups.map(function(g,i){var a=g.latest||{},photo=a.photo||a.refPhoto||"",count=g.items.length;return '<button class="jgw-library-card jgw-own-animal" type="button" data-i="'+i+'"><div class="jgw-library-photo">'+(photo?'<img src="'+esc(photo)+'" alt="'+esc(a.name||"Tier")+'">':'<span>'+animalGroupIcon(a.group)+'</span>')+'<span class="jgw-source">Mein Garten</span></div><div class="jgw-library-body"><div class="jgw-library-name">'+esc(a.name||"Tier")+'</div><div class="jgw-library-latin">'+esc(a.scientific||animalGroupLabel(a.group))+'</div><div class="jgw-library-meta"><span class="jgw-library-chip">'+count+'× beobachtet</span><span class="jgw-library-chip">'+esc(animalGroupLabel(a.group))+'</span></div></div></button>'}).join("");
      qa(".jgw-own-animal",grid).forEach(function(b){b.addEventListener("click",function(){var g=groups[Number(b.dataset.i)];if(g&&typeof window.openAnimalDetail==="function")window.openAnimalDetail(g.key)})});
    }
  }

'''
if 'function renderOwnLibrary()' not in s:
    if render_marker not in s:
        raise SystemExit('render helper marker missing')
    s = s.replace(render_marker, helpers + render_marker, 1)

# 5) Update renderLibrary and controls.
old_render = '''  function renderLibrary(){
    var plant=libraryKind==="plants";el("jgwLibraryPlants").classList.toggle("active",plant);el("jgwLibraryAnimals").classList.toggle("active",!plant);el("jgwLibraryPlants").setAttribute("aria-selected",String(plant));el("jgwLibraryAnimals").setAttribute("aria-selected",String(!plant));el("jgwLibrarySearch").placeholder=plant?"Pflanze suchen …":"Tier suchen …";el("jgwLibraryHint").textContent=plant?"Pflanzen zum Durchstöbern. Ab drei Buchstaben kannst du nach weiteren Arten suchen.":"Tiere zum Durchstöbern. Ab drei Buchstaben kannst du nach weiteren Arten suchen.";var term=el("jgwLibrarySearch").value.trim();if(term.length>=3)searchLibrary(term);else hydrateSeeds(libraryKind)
  }
'''
new_render = '''  function renderLibrary(){
    var plant=libraryKind==="plants",scope=el("jgwLibraryScope");
    el("jgwLibraryPlants").classList.toggle("active",plant);el("jgwLibraryAnimals").classList.toggle("active",!plant);el("jgwLibraryPlants").setAttribute("aria-selected",String(plant));el("jgwLibraryAnimals").setAttribute("aria-selected",String(!plant));
    if(scope)scope.setAttribute("aria-checked",String(libraryOwn));
    if(el("jgwLibraryScopeText"))el("jgwLibraryScopeText").textContent=libraryOwn?"Nur Pflanzen und Tiere aus deinem eigenen Garten anzeigen.":"Stöbermodus: weitere Pflanzen und Tiere entdecken.";
    if(libraryOwn){
      el("jgwLibrarySearch").placeholder=plant?"In meinen Pflanzen suchen …":"In meinen Tieren suchen …";
      el("jgwLibraryClear").textContent="Alle anzeigen";
      var count=plant?((window.state&&window.state.plants)||[]).length:ownAnimalGroups().length;
      el("jgwLibraryHint").textContent=plant?count+" eigene Pflanzeneinträge in deiner Bibliothek.":count+" beobachtete Tierart"+(count===1?"":"en")+" in deiner Bibliothek.";
      renderOwnLibrary();
      return;
    }
    el("jgwLibraryGrid").classList.remove("jgw-library-own");
    el("jgwLibrarySearch").placeholder=plant?"Pflanze suchen …":"Tier suchen …";el("jgwLibraryClear").textContent="Entdecken";el("jgwLibraryHint").textContent=plant?"Pflanzen zum Durchstöbern. Ab drei Buchstaben kannst du nach weiteren Arten suchen.":"Tiere zum Durchstöbern. Ab drei Buchstaben kannst du nach weiteren Arten suchen.";var term=el("jgwLibrarySearch").value.trim();if(term.length>=3)searchLibrary(term);else hydrateSeeds(libraryKind)
  }
'''
if old_render in s:
    s = s.replace(old_render, new_render, 1)
elif 'var plant=libraryKind==="plants",scope=el("jgwLibraryScope")' not in s:
    raise SystemExit('renderLibrary marker missing')

old_controls = '''  el("jgwLibraryPlants").addEventListener("click",function(){libraryKind="plants";el("jgwLibrarySearch").value="";renderLibrary()});
  el("jgwLibraryAnimals").addEventListener("click",function(){libraryKind="animals";el("jgwLibrarySearch").value="";renderLibrary()});
  el("jgwLibrarySearch").addEventListener("input",function(){clearTimeout(libraryTimer);var v=this.value;libraryTimer=setTimeout(function(){searchLibrary(v)},350)});
  el("jgwLibraryClear").addEventListener("click",function(){el("jgwLibrarySearch").value="";renderLibrary()});
'''
new_controls = '''  el("jgwLibraryPlants").addEventListener("click",function(){libraryKind="plants";el("jgwLibrarySearch").value="";renderLibrary()});
  el("jgwLibraryAnimals").addEventListener("click",function(){libraryKind="animals";el("jgwLibrarySearch").value="";renderLibrary()});
  el("jgwLibraryScope").addEventListener("click",function(){libraryOwn=!libraryOwn;el("jgwLibrarySearch").value="";renderLibrary()});
  el("jgwLibrarySearch").addEventListener("input",function(){clearTimeout(libraryTimer);var v=this.value;libraryTimer=setTimeout(function(){if(libraryOwn)renderOwnLibrary();else searchLibrary(v)},250)});
  el("jgwLibraryClear").addEventListener("click",function(){el("jgwLibrarySearch").value="";renderLibrary()});
'''
if old_controls in s:
    s = s.replace(old_controls, new_controls, 1)
elif 'el("jgwLibraryScope").addEventListener' not in s:
    raise SystemExit('library controls marker missing')

p.write_text(s, encoding='utf-8')
