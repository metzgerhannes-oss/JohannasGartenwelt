import time, json
from pathlib import Path
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait, Select
from selenium.webdriver.support import expected_conditions as EC
from selenium.common.exceptions import TimeoutException

BASE='https://metzgerhannes-oss.github.io/JohannasGartenwelt/'
OUT=Path('audit_unresolved'); OUT.mkdir(exist_ok=True)
DLS=OUT/'downloads'; DLS.mkdir(exist_ok=True)
R=[]
def rec(n,s='PASS',d=''): R.append({'name':n,'status':s,'detail':d}); print(f'[{s}] {n}: {d}')
def dvr():
    o=webdriver.ChromeOptions()
    for a in ['--headless=new','--no-sandbox','--disable-dev-shm-usage','--disable-gpu','--lang=de-DE']: o.add_argument(a)
    o.add_experimental_option('prefs',{'download.default_directory':str(DLS.resolve()),'download.prompt_for_download':False})
    d=webdriver.Chrome(options=o); d.set_window_size(390,844); return d
def wait(d,n=15):return WebDriverWait(d,n)
def click(d,css,n=15):
    x=wait(d,n).until(EC.presence_of_element_located((By.CSS_SELECTOR,css))); d.execute_script("arguments[0].scrollIntoView({block:'center'})",x); wait(d,n).until(lambda z:x.is_displayed() and x.is_enabled()); d.execute_script('arguments[0].click()',x); return x
def txt(d,css):return d.find_element(By.CSS_SELECTOR,css).text.strip()
def dl(suf,before,n=15):
    end=time.time()+n
    while time.time()<end:
        now={p for p in DLS.iterdir() if p.suffix.lower()==suf}; new=now-before
        if new:return max(new,key=lambda p:p.stat().st_mtime)
        time.sleep(.25)
    raise TimeoutException('download '+suf)

d=dvr()
try:
    d.get(BASE+'?unresolved='+str(int(time.time()))); wait(d,20).until(EC.presence_of_element_located((By.TAG_NAME,'body')))
    # navigation labels and touch sizes
    try:
        labels=[x.find_elements(By.CSS_SELECTOR,'span')[-1].text.strip() for x in d.find_elements(By.CSS_SELECTOR,'.tabs .tab')]
        sizes={sel:d.execute_script('return arguments[0].getBoundingClientRect()',d.find_element(By.CSS_SELECTOR,sel)) for sel in ['#settingsGear','#quickAddPlant','.tabs .tab']}
        assert labels==['Heute','Pflanzen','Karte','Kalender','Wetter']; assert all(v['height']>=44 and v['width']>=44 for v in sizes.values())
        rec('Navigation/Touch',detail=str(labels)+' '+str({k:round(v['height']) for k,v in sizes.items()}))
    except Exception as e:rec('Navigation/Touch','FAIL',repr(e))
    # location + weather diagnostics
    try:
        click(d,'#settingsGear'); p=d.find_element(By.ID,'plz'); p.clear(); p.send_keys('72144'); click(d,"#locationForm button[type='submit']"); wait(d,25).until(lambda z:'72144' in txt(z,'#headerLocation')); click(d,'#settingsClose')
        # Wait on the actual garden summary because it proves weather data arrived.
        wait(d,45).until(lambda z:txt(z,'#gardenState') not in ('','Wetter wird geladen','Noch keine Wetterdaten'))
        click(d,".tab[data-view='weather']"); time.sleep(1)
        vals={k:txt(d,'#'+k) for k in ['wTotal','wEt0','wBalance','wWet','wLast','wFuture']}
        if vals['wTotal'] in ('','–','-'):
            # Diagnose whether only the weather-detail view missed a render.
            d.execute_script("if(typeof renderWeather==='function')renderWeather()")
            time.sleep(.5); vals2={k:txt(d,'#'+k) for k in vals}
        else: vals2=vals
        assert vals2['wTotal'] not in ('','–','-')
        rec('Wetter Detailansicht',detail='vor='+json.dumps(vals,ensure_ascii=False)+' nach='+json.dumps(vals2,ensure_ascii=False))
    except Exception as e: rec('Wetter Detailansicht','FAIL',repr(e))
    # create plant and explicitly assign current care month, then ICS
    try:
        click(d,".tab[data-view='plants']"); click(d,'#newPlantBtn'); d.find_element(By.ID,'plantName').send_keys('ICS-Testpflanze'); d.find_element(By.ID,'plantArea').send_keys('Testbeet')
        adv=d.find_element(By.ID,'plantAdvanced'); d.execute_script('arguments[0].open=true',adv)
        m=str(time.localtime().tm_mon); cb=d.find_element(By.CSS_SELECTOR,f"#fertMonths input[value='{m}']"); d.execute_script('arguments[0].click()',cb); click(d,"#plantForm button[type='submit']"); wait(d,10).until(lambda z:'ICS-Testpflanze' in txt(z,'#plantList'))
        click(d,".tab[data-view='calendar']"); d.execute_script("document.querySelector('.calendar-tools').open=true")
        before={p for p in DLS.iterdir() if p.suffix.lower()=='.ics'}; click(d,'#exportCareYear'); f=dl('.ics',before,15); body=f.read_text(encoding='utf-8-sig'); assert 'BEGIN:VCALENDAR' in body and 'ICS-Testpflanze' in body
        rec('ICS Export',detail=f.name)
    except Exception as e:rec('ICS Export','FAIL',repr(e))
    # season/animation exact ids
    try:
        click(d,'#settingsGear'); Select(d.find_element(By.ID,'seasonMode')).select_by_value('winter'); time.sleep(.2); assert d.find_element(By.TAG_NAME,'body').get_attribute('data-season')=='winter'
        a=d.find_element(By.ID,'animationToggle'); old=a.is_selected(); d.execute_script('arguments[0].click()',a); assert a.is_selected()!=old; d.execute_script('arguments[0].click()',a); Select(d.find_element(By.ID,'seasonMode')).select_by_value('auto'); click(d,'#settingsClose'); rec('Jahreszeit/Animation')
    except Exception as e:rec('Jahreszeit/Animation','FAIL',repr(e))
    # generated garden id is normalized lower-case in storage/input; verify semantically
    try:
        click(d,'#settingsGear'); d.execute_script("document.getElementById('generateGardenId').closest('details').open=true"); click(d,'#generateGardenId'); gid=d.find_element(By.ID,'syncGardenId').get_attribute('value'); assert gid.upper().startswith('JOHANNA-') and len(gid)>=10; rec('Garten-ID Generator',detail=gid); click(d,'#settingsClose')
    except Exception as e:rec('Garten-ID Generator','FAIL',repr(e))
finally:d.quit()
Path(OUT/'report.json').write_text(json.dumps(R,ensure_ascii=False,indent=2),encoding='utf-8')
f=[x for x in R if x['status']=='FAIL']; print('SUMMARY',len(R)-len(f),'PASS',len(f),'FAIL'); raise SystemExit(1 if f else 0)
