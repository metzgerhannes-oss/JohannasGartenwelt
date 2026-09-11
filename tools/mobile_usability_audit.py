import json, subprocess, time, sys
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.chrome.options import Options

WIDTHS=[320,375,390,430]
HEIGHTS={320:740,375:812,390:844,430:932}

server=subprocess.Popen(['python','-m','http.server','8000','--bind','127.0.0.1'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
time.sleep(1)
opt=Options(); opt.add_argument('--headless=new'); opt.add_argument('--no-sandbox'); opt.add_argument('--disable-dev-shm-usage'); opt.add_argument('--disable-gpu')
d=webdriver.Chrome(options=opt)

JS_AUDIT=r'''
const label = arguments[0];
const vw = document.documentElement.clientWidth;
const vh = window.innerHeight;
const interactive = Array.from(document.querySelectorAll('button,input:not([type="hidden"]),select,textarea,summary,a[href],[role="button"],[role="tab"]'))
  .filter(e=>{const s=getComputedStyle(e),r=e.getBoundingClientRect();return s.display!=='none'&&s.visibility!=='hidden'&&r.width>0&&r.height>0;});
const tiny=[];
for(const e of interactive){
  const r=e.getBoundingClientRect(); const t=(e.getAttribute('type')||'').toLowerCase();
  if(t==='checkbox'||t==='radio') continue;
  const cls=e.className&&String(e.className).slice(0,100)||'';
  if(r.height<40 || r.width<32) tiny.push({tag:e.tagName,id:e.id||'',cls,text:(e.innerText||e.value||e.getAttribute('aria-label')||'').trim().slice(0,55),w:Math.round(r.width),h:Math.round(r.height)});
}
const horizontal=[];
for(const e of Array.from(document.querySelectorAll('body *'))){
  const s=getComputedStyle(e),r=e.getBoundingClientRect(); if(s.display==='none'||s.visibility==='hidden'||r.width===0||r.height===0) continue;
  if(r.left < -2 || r.right > vw+2){
    const ox=s.overflowX;
    if(!['auto','scroll'].includes(ox) && !e.closest('.leaflet-container')) horizontal.push({tag:e.tagName,id:e.id||'',cls:String(e.className||'').slice(0,80),left:Math.round(r.left),right:Math.round(r.right),vw});
  }
}
const clipped=[];
for(const e of Array.from(document.querySelectorAll('button,.btn,.tab,.nature-tab,.field input,.field select,.field textarea,.plant-sort,.library-search,.plant-search'))){
 const s=getComputedStyle(e),r=e.getBoundingClientRect(); if(s.display==='none'||s.visibility==='hidden'||r.width===0||r.height===0) continue;
 if(e.scrollWidth > e.clientWidth+3 && !['auto','scroll'].includes(s.overflowX)) clipped.push({tag:e.tagName,id:e.id||'',cls:String(e.className||'').slice(0,70),text:(e.innerText||e.value||e.placeholder||'').slice(0,55),cw:e.clientWidth,sw:e.scrollWidth});
}
const nav=document.querySelector('.tabs');
let navInfo=null;
if(nav){const r=nav.getBoundingClientRect(); navInfo={top:Math.round(r.top),bottom:Math.round(r.bottom),vh:Math.round(vh),position:getComputedStyle(nav).position};}
return {label,vw,docScrollWidth:document.documentElement.scrollWidth,tiny,horizontal:horizontal.slice(0,25),clipped:clipped.slice(0,25),navInfo};
'''

def click(css):
    els=d.find_elements(By.CSS_SELECTOR,css)
    if not els: return False
    try:
        d.execute_script('arguments[0].click()',els[0]); time.sleep(.12); return True
    except Exception: return False

def audit(label):
    data=d.execute_script(JS_AUDIT,label)
    print('AUDIT',json.dumps(data,ensure_ascii=False))
    return data

all_data=[]
try:
  for w in WIDTHS:
    d.set_window_size(w,HEIGHTS[w])
    d.get('http://127.0.0.1:8000/index.html'); time.sleep(.5)
    print(f'=== WIDTH {w} ===')
    all_data.append(audit(f'{w}:heute'))
    for view in ['plants','map','calendar','weather']:
      click(f'.tab[data-view="{view}"]'); all_data.append(audit(f'{w}:{view}'))
    # Naturgarten-Unterbereiche und Editoransichten
    click('.tab[data-view="plants"]')
    click('.nature-tab[data-nature="plants"]'); click('#newPlantBtn'); all_data.append(audit(f'{w}:plant-editor')); click('#closePlantEditor')
    click('.nature-tab[data-nature="habitats"]'); all_data.append(audit(f'{w}:habitats')); click('#newHabitatBtn'); all_data.append(audit(f'{w}:habitat-editor')); click('#closeHabitatEditor')
    click('.nature-tab[data-nature="animals"]'); all_data.append(audit(f'{w}:animals')); click('#newAnimalBtn'); all_data.append(audit(f'{w}:animal-editor')); click('#closeAnimalEditor')
    # Einstellungen komplett öffnen, Details aufklappen
    d.execute_script("window.scrollTo(0,0)")
    if click('.gearbtn'):
      all_data.append(audit(f'{w}:settings-top'))
      for det in d.find_elements(By.CSS_SELECTOR,'.settings-sheet details'):
        try: d.execute_script('arguments[0].open=true',det)
        except Exception: pass
      time.sleep(.1); all_data.append(audit(f'{w}:settings-all'))
      click('.settings-close')
    # Browserleiste simulieren: Navigation muss oberhalb liegen
    d.execute_script("document.documentElement.style.setProperty('--jgw-browser-bottom','64px')")
    time.sleep(.1); all_data.append(audit(f'{w}:browserbar64'))

  print('=== SUMMARY ===')
  labels=[]; tiny={}; horiz={}; clipped={}
  for x in all_data:
    if x['docScrollWidth']>x['vw']+2: labels.append(x['label'])
    for t in x['tiny']:
      k=(t['id'] or t['cls'] or t['tag'])+'|'+t['text']; tiny.setdefault(k,t)
    for h in x['horizontal']:
      k=(h['id'] or h['cls'] or h['tag']); horiz.setdefault(k,h)
    for c in x['clipped']:
      k=(c['id'] or c['cls'] or c['tag'])+'|'+c['text']; clipped.setdefault(k,c)
  print('PAGE_HORIZONTAL_OVERFLOW',labels)
  print('UNIQUE_SMALL_TARGETS',json.dumps(list(tiny.values()),ensure_ascii=False))
  print('UNIQUE_HORIZONTAL_ELEMENTS',json.dumps(list(horiz.values()),ensure_ascii=False))
  print('UNIQUE_CLIPPED_CONTROLS',json.dumps(list(clipped.values()),ensure_ascii=False))
finally:
  d.quit(); server.terminate(); server.wait(timeout=5)
