from pathlib import Path

root=Path('.')
lib=root/'jgw-library-v4.js'
s=lib.read_text(encoding='utf-8')

anchor='var kind="plants",own=false,filter="all",timer=null,seq=0;'
insert='''var kind="plants",own=false,filter="all",timer=null,seq=0,photoCache={};
async function libraryPhoto(x,isPlant){var key=(isPlant?"p:":"a:")+norm(x.scientific||x.name);if(!key)return null;if(Object.prototype.hasOwnProperty.call(photoCache,key))return photoCache[key];photoCache[key]=null;try{var term=x.scientific||x.name,u="https://api.inaturalist.org/v1/taxa/autocomplete?q="+encodeURIComponent(term)+"&locale=de&per_page=6"+(isPlant?"&taxon_id=47126":""),r=await fetch(u,{headers:{Accept:"application/json"}}),d=r.ok?await r.json():{results:[]},a=(d.results||[]).filter(function(t){return !isPlant||String(t.iconic_taxon_name||"").toLowerCase()==="plantae"}),exact=a.find(function(t){return norm(t.name)===norm(x.scientific)})||a.find(function(t){return t.default_photo})||a[0],p=exact&&exact.default_photo||{},out=(p.medium_url||p.large_url||p.square_url)?{photo:p.medium_url||p.large_url||p.square_url||"",attribution:p.attribution||"",taxonId:exact&&exact.id||null}:null;photoCache[key]=out;return out}catch(e){return null}}
async function hydrateLibraryPhotos(items,n){var cursor=0,workers=[];async function work(){while(cursor<items.length){var i=cursor++,x=items[i];if(x.photo)continue;var p=await libraryPhoto(x,kind==="plants");if(n!==seq)return;if(p&&p.photo){x.photo=p.photo;x.attribution=x.attribution||p.attribution;x.taxonId=x.taxonId||p.taxonId;var g=el("jgwLibraryGrid"),card=g&&g.querySelector('.jgw-library-card[data-i="'+i+'"]'),box=card&&card.querySelector(".jgw-library-photo");if(box)box.innerHTML='<img loading="lazy" src="'+esc(x.photo)+'" alt="'+esc(x.name)+'">'}}}}for(var w=0;w<Math.min(4,items.length);w++)workers.push(work());await Promise.all(workers)}'''
if s.count(anchor)!=1:
    raise RuntimeError(f'kind anchor count {s.count(anchor)}')
s=s.replace(anchor,insert,1)

old='async function remote(term){var n=++seq;if(term.length<3){cards((kind==="plants"?plants.filter(match):animals).slice());return}'
new='async function remote(term){var n=++seq;if(term.length<3){var base=(kind==="plants"?plants.filter(match):animals).slice();cards(base);hydrateLibraryPhotos(base,n);return}'
if s.count(old)!=1:
    raise RuntimeError(f'remote anchor count {s.count(old)}')
s=s.replace(old,new,1)

oldown='photo:p.photo||"",sourceId:p.id'
newown='photo:p.photo||((p.careMeta&&p.careMeta.refPhoto)||""),sourceId:p.id'
if s.count(oldown)!=1:
    raise RuntimeError(f'own photo anchor count {s.count(oldown)}')
s=s.replace(oldown,newown,1)

# Lazy-load all library images, including search results.
s=s.replace('<img src="'+"'+esc(x.photo)+'"+'" alt="'+"'+esc(x.name)+'"+'">','<img loading="lazy" src="'+"'+esc(x.photo)+'"+'" alt="'+"'+esc(x.name)+'"+'">')
lib.write_text(s,encoding='utf-8')

nav=root/'jgw-library-nav.js'
n=nav.read_text(encoding='utf-8')
old='tag("jgw-library-v4.js","20260914-1")'
new='tag("jgw-library-v4.js","20260914-2")'
if n.count(old)!=1:
    raise RuntimeError(f'nav version anchor count {n.count(old)}')
nav.write_text(n.replace(old,new,1),encoding='utf-8')

idx=root/'index.html'
i=idx.read_text(encoding='utf-8')
old='<script src="./jgw-library-nav.js?v=20260914-1"></script>'
new='<script src="./jgw-library-nav.js?v=20260914-2"></script>'
if i.count(old)!=1:
    raise RuntimeError(f'index cache anchor count {i.count(old)}')
idx.write_text(i.replace(old,new,1),encoding='utf-8')

print('Library reference photos enabled')
