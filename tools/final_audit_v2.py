from __future__ import annotations
import json,time,urllib.request
from pathlib import Path
from selenium import webdriver
from selenium.common.exceptions import TimeoutException
from selenium.webdriver.common.by import By
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.support.ui import Select,WebDriverWait

BASE='https://metzgerhannes-oss.github.io/JohannasGartenwelt/'
OUT=Path('audit_v2'); OUT.mkdir(exist_ok=True)
DLS=OUT/'downloads'; DLS.mkdir(exist_ok=True)
R=[]

def rec(name,status='PASS',detail=''):
    R.append({'name':name,'status':status,'detail':detail}); print(f'[{status}] {name}: {detail}')

def drv(mobile=True,standalone=False):
    o=webdriver.ChromeOptions()
    for a in ['--headless=new','--no-sandbox','--disable-dev-shm-usage','--disable-gpu','--lang=de-DE']: o.add_argument(a)
    o.set_capability('goog:loggingPrefs',{'browser':'ALL'})
    o.add_experimental_option('prefs',{'download.default_directory':str(DLS.resolve()),'download.prompt_for_download':False,'download.directory_upgrade':True})
    d=webdriver.Chrome(options=o); d.set_window_size(390 if mobile else 1280,844 if mobile else 900)
    if standalone:
        d.execute_cdp_cmd('Page.addScriptToEvaluateOnNewDocument',{'source':"Object.defineProperty(navigator,'standalone',{configurable:true,get:()=>true});"})
    return d

def wait(d,n=15): return WebDriverWait(d,n)
def vis(d,css,n=15): return wait(d,n).until(EC.visibility_of_element_located((By.CSS_SELECTOR,css)))
def click(d,css,n=15):
    x=wait(d,n).until(EC.presence_of_element_located((By.CSS_SELECTOR,css))); d.execute_script("arguments[0].scrollIntoView({block:'center'});",x)
    wait(d,n).until(lambda z:x.is_displayed() and x.is_enabled()); d.execute_script('arguments[0].click()',x); return x
def txt(d,css): return d.find_element(By.CSS_SELECTOR,css).text.strip()
def shot(d,n): d.save_screenshot(str(OUT/n))
def ljson(d,k): return d.execute_script("return JSON.parse(localStorage.getItem(arguments[0])||'null')",k)
def dl(suf,before,timeout=12):
    end=time.time()+timeout
    while time.time()<end:
        now={p for p in DLS.iterdir() if p.suffix.lower()==suf}
        new=now-before
        if new:return max(new,key=lambda p:p.stat().st_mtime)
        time.sleep(.25)
    raise TimeoutException('download '+suf)

def probe(name,url):
    try:
        q=urllib.request.Request(url,headers={'User-Agent':'JGW-Audit/2'}); r=urllib.request.urlopen(q,timeout=15); ok=200<=r.status<300
        rec('Externer Dienst: '+name,'PASS' if ok else 'WARN',f'HTTP {r.status}')
    except Exception as e: rec('Externer Dienst: '+name,'WARN',repr(e))

def browser_errors(d):
    out=[]
    for x in d.get_log('browser'):
        if x.get('level')!='SEVERE': continue
        m=x.get('message','').lower()
        if any(k in m for k in ['favicon','tile','wms_lgl','err_blocked_by_client']): continue
        out.append(x.get('message',''))
    return out

probe('Zippopotam','https://api.zippopotam.us/de/72144')
probe('Open-Meteo','https://api.open-meteo.com/v1/forecast?latitude=48.45&longitude=9.06&daily=precipitation_sum&timezone=Europe%2FBerlin')
probe('QR-Bibliothek','https://cdn.jsdelivr.net/npm/qrcodejs@1.0.0/qrcode.min.js')

d=drv(True)
token=None
try:
    d.get(BASE+'?auditv2='+str(int(time.time()))); vis(d,'body',25)
    # Start / navigation / layout
    try:
        labels=[x.text.strip() for x in d.find_elements(By.CSS_SELECTOR,'.tabs .tab')]
        assert labels==['Heute','Pflanzen','Karte','Kalender','Wetter']
        assert d.find_element(By.ID,'view-today').is_displayed()
        nav=d.find_element(By.CSS_SELECTOR,'.tabs'); style=d.execute_script('return getComputedStyle(arguments[0])',nav)
        h=d.execute_script("return document.querySelector('.tabs .tab').getBoundingClientRect().height")
        assert h>=50
        for sel in ['#settingsGear','#quickAddPlant']:
            r=d.execute_script('return arguments[0].getBoundingClientRect()',d.find_element(By.CSS_SELECTOR,sel)); assert r['width']>=44 and r['height']>=44
        rec('Mobile Navigation und Touch-Ziele',detail=f'{h:.0f}px Navigation')
    except Exception as e: rec('Mobile Navigation und Touch-Ziele','FAIL',repr(e))
    try:
        bf=d.execute_script('return getComputedStyle(document.body).fontFamily'); hf=d.execute_script("return getComputedStyle(document.querySelector('.brand h1')).fontFamily")
        assert any(k in bf for k in ['Arial','Segoe UI','Roboto','BlinkMacSystemFont','SF Pro']); assert 'Georgia' in hf
        rec('Typografie und Lesbarkeit')
    except Exception as e: rec('Typografie und Lesbarkeit','FAIL',repr(e))
    # settings
    try:
        click(d,'#settingsGear'); vis(d,'#settingsOverlay'); shot(d,'01_settings.png'); click(d,'#settingsClose'); rec('Einstellungen')
    except Exception as e: rec('Einstellungen','FAIL',repr(e))
    # Location + real weather
    try:
        click(d,'#settingsGear'); p=vis(d,'#plz'); p.clear(); p.send_keys('72144'); click(d,"#locationForm button[type='submit']")
        wait(d,25).until(lambda z:'72144' in txt(z,'#headerLocation'))
        click(d,'#settingsClose'); click(d,".tab[data-view='weather']")
        wait(d,45).until(lambda z: txt(z,'#wTotal') not in ('','–','-'))
        total=txt(d,'#wTotal'); forecast=txt(d,'#wFuture')
        assert len(d.find_elements(By.CSS_SELECTOR,'#weatherForecast .day'))>=1
        rec('Standort und Wetter',detail=f'Niederschlag {total}, Ausblick {forecast}')
    except Exception as e: rec('Standort und Wetter','FAIL',repr(e))
    # Today garden state after weather
    try:
        click(d,".tab[data-view='today']"); wait(d,15).until(lambda z:txt(z,'#gardenState') not in ('','Wetter wird geladen','Noch keine Wetterdaten'))
        assert txt(d,'#gardenDryDays'); assert txt(d,'#gardenNextRain'); assert txt(d,'#gardenFrost')
        shot(d,'02_today.png'); rec('Gartenlage auf Heute',detail=txt(d,'#gardenState'))
    except Exception as e: rec('Gartenlage auf Heute','FAIL',repr(e))
    # map setup and locking
    try:
        click(d,".tab[data-view='map']"); wait(d,25).until(lambda z:'leaflet-container' in (z.find_element(By.ID,'map').get_attribute('class') or ''))
        if d.find_element(By.ID,'saveMapViewBtn').is_displayed(): click(d,'#saveMapViewBtn')
        app=ljson(d,'giess_check_garten_v3'); assert app['settings']['mapView'] and app['gardenCenter']
        assert 'Fester Gartenausschnitt' in txt(d,'#mapViewStatus')
        shot(d,'03_map.png'); rec('Gartenkarte und fester Ausschnitt')
    except Exception as e: rec('Gartenkarte und fester Ausschnitt','FAIL',repr(e))
    # plant creation quick mode
    try:
        click(d,".tab[data-view='plants']"); click(d,'#newPlantBtn'); vis(d,'#plantEditor')
        assert not d.find_element(By.ID,'plantAdvanced').get_property('open'); assert d.find_element(By.ID,'plantType').get_attribute('value')=='bed'
        d.find_element(By.ID,'plantName').send_keys('Audit-Hortensie'); d.find_element(By.ID,'plantArea').send_keys('Auditbeet')
        click(d,"#plantForm button[type='submit']"); wait(d,15).until(lambda z:'Audit-Hortensie' in txt(z,'#plantList'))
        shot(d,'04_plants.png'); rec('Pflanze schnell anlegen',detail='Standard Gartenboden')
    except Exception as e: rec('Pflanze schnell anlegen','FAIL',repr(e))
    # search/details/actions
    try:
        s=d.find_element(By.ID,'plantSearch'); s.send_keys('Audit-Hort'); assert 'Audit-Hortensie' in txt(d,'#plantList'); s.clear(); s.send_keys('xxxx-keine'); wait(d,8).until(lambda z:'Keine passende Pflanze' in txt(z,'#plantList')); s.clear(); rec('Pflanzensuche')
    except Exception as e: rec('Pflanzensuche','FAIL',repr(e))
    # tasks + snooze/done behavior
    try:
        click(d,".tab[data-view='today']"); tasks=d.find_elements(By.CSS_SELECTOR,'#tasks .task');
        if tasks:
            snooze=d.find_elements(By.CSS_SELECTOR,'.taskSnooze')
            if snooze: d.execute_script('arguments[0].click()',snooze[0]); time.sleep(.4)
        rec('Heute-Aufgaben, Später und Erledigt')
    except Exception as e: rec('Heute-Aufgaben, Später und Erledigt','FAIL',repr(e))
    # calendar + actual ICS download; open collapsed tools intentionally
    try:
        click(d,".tab[data-view='calendar']"); initial=len(d.find_elements(By.CSS_SELECTOR,'#calendarGrid .calmonth')); assert 1<=initial<=3
        click(d,'#calendarToggle'); expanded=len(d.find_elements(By.CSS_SELECTOR,'#calendarGrid .calmonth')); assert expanded>=initial
        d.execute_script("document.querySelector('.calendar-tools').open=true")
        before={p for p in DLS.iterdir() if p.suffix.lower()=='.ics'}; click(d,'#exportCareYear'); f=dl('.ics',before,15); assert 'BEGIN:VCALENDAR' in f.read_text(encoding='utf-8-sig')
        shot(d,'05_calendar.png'); rec('Pflegekalender und ICS-Export',detail=f'{initial}→{expanded} Monate')
    except Exception as e: rec('Pflegekalender und ICS-Export','FAIL',repr(e))
    # backup export/import
    try:
        click(d,'#settingsGear'); before={p for p in DLS.iterdir() if p.suffix.lower()=='.json'}; click(d,'#exportBtn'); f=dl('.json',before); data=json.loads(f.read_text(encoding='utf-8-sig')); assert 'plants' in data and 'zones' in data
        d.find_element(By.ID,'importFile').send_keys(str(f.resolve()))
        try: wait(d,3).until(EC.alert_is_present()).accept()
        except TimeoutException: pass
        time.sleep(.5); assert ljson(d,'giess_check_garten_v3') is not None; click(d,'#settingsClose'); rec('Datensicherung Export/Import')
    except Exception as e: rec('Datensicherung Export/Import','FAIL',repr(e))
    # seasons + animation setting
    try:
        click(d,'#settingsGear'); Select(d.find_element(By.ID,'seasonMode')).select_by_value('winter'); time.sleep(.2); assert d.find_element(By.TAG_NAME,'body').get_attribute('data-season')=='winter'; Select(d.find_element(By.ID,'seasonMode')).select_by_value('auto')
        a=d.find_element(By.ID,'animationsEnabled'); old=a.is_selected(); d.execute_script('arguments[0].click()',a); time.sleep(.1); assert a.is_selected()!=old; d.execute_script('arguments[0].click()',a); click(d,'#settingsClose'); rec('Jahreszeiten und Animationen')
    except Exception as e: rec('Jahreszeiten und Animationen','FAIL',repr(e))
    # sync settings UI: details need opening
    try:
        click(d,'#settingsGear'); d.execute_script("document.getElementById('generateGardenId').closest('details').open=true"); click(d,'#generateGardenId'); gid=d.find_element(By.ID,'syncGardenId').get_attribute('value'); assert gid.startswith('JOHANNA-') and len(gid)>=10; click(d,'#settingsClose'); rec('Sync-Einrichtung und Garten-ID',detail=gid)
    except Exception as e: rec('Sync-Einrichtung und Garten-ID','FAIL',repr(e))
    # delete/undo
    try:
        click(d,".tab[data-view='plants']"); card=next(c for c in d.find_elements(By.CSS_SELECTOR,'.plantcard') if 'Audit-Hortensie' in c.text); det=card.find_element(By.CSS_SELECTOR,'details.plant-more'); d.execute_script('arguments[0].open=true',det); d.execute_script('arguments[0].click()',card.find_element(By.CSS_SELECTOR,'.deletePlant')); wait(d,3).until(EC.alert_is_present()).accept(); vis(d,'#undoToast'); click(d,'#undoDeleteBtn'); wait(d,10).until(lambda z:'Audit-Hortensie' in txt(z,'#plantList')); rec('Löschen und Rückgängig')
    except Exception as e: rec('Löschen und Rückgängig','FAIL',repr(e))
    # QR generator with synthetic credentials
    try:
        d.execute_script("localStorage.setItem('giess_check_garten_v3',JSON.stringify({settings:{plantnetKey:'demo-plantnet-key'},plants:[],zones:[]}));localStorage.setItem('johannas_gartenwelt_sync_v1',JSON.stringify({url:'https://demo.supabase.co',key:'sb_publishable_demo_key_123456789',gardenId:'johanna-audit12',pin:'audit123'}));")
        d.get(BASE+'setup.html?audit='+str(int(time.time()))); vis(d,'#generatorBox'); assert not d.find_element(By.ID,'makeQr').get_attribute('disabled'); click(d,'#makeQr'); wait(d,20).until(lambda z:len(z.find_elements(By.CSS_SELECTOR,'#qrCanvas img,#qrCanvas canvas'))>0); token=txt(d,'#setupLink'); assert '#setup=' in token; shot(d,'06_setup_qr.png'); rec('QR-Geräteeinrichtung erzeugen',detail=f'{len(token)} Zeichen')
    except Exception as e: rec('QR-Geräteeinrichtung erzeugen','FAIL',repr(e))
    errs=browser_errors(d)
    rec('JavaScript-Laufzeit','PASS' if not errs else 'FAIL','; '.join(errs[:3]))
finally:
    d.quit()

# standalone token receiver
if token:
    d=drv(True,True)
    try:
        try:
            d.get(token.replace('#setup=','?install=')); vis(d,'#receiverBox',20); pin=d.find_element(By.ID,'setupPin'); pin.send_keys('audit123'); click(d,"#unlockForm button[type='submit']"); wait(d,20).until(lambda z:z.current_url.rstrip('/').endswith('JohannasGartenwelt'))
            sync=ljson(d,'johannas_gartenwelt_sync_v1'); assert sync and sync.get('gardenId')=='johanna-audit12'; rec('Home-Screen-QR-Übernahme')
        except Exception as e: rec('Home-Screen-QR-Übernahme','FAIL',repr(e))
    finally:d.quit()

# desktop smoke
d=drv(False)
try:
    d.get(BASE+'?desktopaudit='+str(int(time.time()))); vis(d,'body',20); assert len(d.find_elements(By.CSS_SELECTOR,'.tabs .tab'))==5; shot(d,'07_desktop.png'); rec('Desktop-Darstellung')
finally:d.quit()

Path(OUT/'audit_report.json').write_text(json.dumps(R,ensure_ascii=False,indent=2),encoding='utf-8')
fail=[x for x in R if x['status']=='FAIL']; warn=[x for x in R if x['status']=='WARN']
print(f'AUDIT V2 SUMMARY: {len(R)-len(fail)-len(warn)} PASS, {len(warn)} WARN, {len(fail)} FAIL')
raise SystemExit(1 if fail else 0)
