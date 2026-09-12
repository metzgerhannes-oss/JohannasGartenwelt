from pathlib import Path
import re

path = Path('index.html')
s = path.read_text(encoding='utf-8')


def replace_once(old, new, label):
    global s
    n = s.count(old)
    if n != 1:
        raise SystemExit(f'{label}: expected 1 occurrence, found {n}')
    s = s.replace(old, new, 1)


def regex_once(pattern, replacement, label, flags=re.S):
    global s
    s2, n = re.subn(pattern, replacement, s, count=1, flags=flags)
    if n != 1:
        raise SystemExit(f'{label}: expected 1 match, found {n}')
    s = s2


# 1) Trefle token must no longer be entered or stored in the browser.
regex_once(
    r'''      <details style="margin-top:10px">\n        <summary>Zusätzliche Pflanzendaten \(optional\)</summary>\n        <div class="muted" style="margin-top:8px">iNaturalist, GBIF und die lokale Pflegelogik funktionieren ohne Schlüssel\. Ein kostenloser Trefle-Token kann zusätzliche Angaben zu Blüte, Wasserbedarf und Verbreitung liefern\.</div>\n        <div class="field" style="margin-top:9px"><label for="trefleKey">Trefle API-Token</label><input id="trefleKey" type="password" autocomplete="off" placeholder="optional"></div>\n        <div class="actions" style="margin-top:8px"><button class="btn secondary small" id="savePlantDataKey" type="button">Token speichern</button></div>\n        <div class="section-status" id="plantDataApiStatus" style="margin-top:8px">Zusatzquelle nicht eingerichtet – nicht erforderlich\.</div>\n      </details>''',
    '''      <details style="margin-top:10px">
        <summary>Zusätzliche Pflanzendaten</summary>
        <div class="muted" style="margin-top:8px">Trefle wird geschützt über Supabase abgefragt. Der API-Token liegt ausschließlich als Supabase-Secret und wird weder im Browser noch in einem Backup gespeichert.</div>
        <div class="section-status" id="plantDataApiStatus" style="margin-top:8px">Trefle-Status wird geprüft.</div>
      </details>''',
    'replace Trefle settings UI'
)

# Remove the obsolete browser-side key from all settings defaults.
s = s.replace('plantnetKey:DEFAULT_PLANTNET_KEY,trefleKey:"",', 'plantnetKey:DEFAULT_PLANTNET_KEY,')

# 2) Route all Trefle calls through the protected Supabase Edge Function.
regex_once(
    r'''async function treflePlantData\(sci\)\{.*?\}\nfunction growthValue''',
    '''async function treflePlantData(sci){
 sci=String(sci||"").trim();
 if(!sci||!syncConfigured())return null;
 try{
  var secretHash=await syncSecretHash(),url=normalizeSyncUrl(syncState.url)+"/functions/v1/trefle-enrich";
  var r=await fetch(url,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({scientific_name:sci,garden_id:String(syncState.gardenId||"").trim().toLowerCase(),secret_hash:secretHash})});
  var d=null;try{d=await r.json()}catch(_e){}
  if(!r.ok||!d||d.ok!==true||!d.found)return null;
  return d.data||null
 }catch(e){console.warn("Trefle proxy",e);return null}
}
function growthValue''',
    'replace direct Trefle request'
)

# 3) Settings status now reflects whether the secure proxy can authenticate the garden.
replace_once(
    'if(el("trefleKey"))el("trefleKey").value=state.settings.trefleKey||"";',
    '',
    'remove Trefle input rendering'
)
replace_once(
    'var ds=el("plantDataApiStatus");if(ds){var ta=!!String(state.settings.trefleKey||"").trim();ds.className="section-status "+(ta?"ok":"");ds.textContent=ta?"Trefle-Zusatzdaten aktiv":"Zusatzquelle nicht eingerichtet – iNaturalist, GBIF und Pflegelogik bleiben aktiv."}',
    'var ds=el("plantDataApiStatus");if(ds){var ta=syncConfigured();ds.className="section-status "+(ta?"ok":"warn");ds.textContent=ta?"Trefle-Zusatzdaten geschützt über Supabase aktiv":"Trefle benötigt die eingerichtete Geräte-Synchronisierung. iNaturalist, GBIF und Pflegelogik bleiben unabhängig davon aktiv."}',
    'replace Trefle status rendering'
)

# 4) Do not export/import the old Trefle token anymore.
s = s.replace('trefleKey:state.settings.trefleKey||"",', '')
replace_once(
    'if(data.settings&&Object.prototype.hasOwnProperty.call(data.settings,"trefleKey"))state.settings.trefleKey=data.settings.trefleKey||"";',
    'delete state.settings.trefleKey;',
    'strip Trefle token from imported backups'
)

# Migrate any token that may still be present in localStorage from an older app version.
replace_once(
    'load();migrateAreaMasterData();',
    'load();if(state.settings&&Object.prototype.hasOwnProperty.call(state.settings,"trefleKey")){delete state.settings.trefleKey;save()}migrateAreaMasterData();',
    'local Trefle token migration'
)

# Remove the obsolete save-token handler.
regex_once(
    r'''\nel\("savePlantDataKey"\)\.addEventListener\("click",function\(\)\{state\.settings\.trefleKey=el\("trefleKey"\)\.value\.trim\(\);save\(\);renderHeader\(\);notice\(state\.settings\.trefleKey\?"Trefle-Token gespeichert\. Zusätzliche Pflanzendaten sind aktiv\.":"Trefle-Token entfernt\. Die kostenlosen Standardquellen bleiben aktiv\."\)\}\);''',
    '',
    'remove Trefle token event handler'
)

# Safety assertions: direct browser-side credential use is gone. A single reference is
# intentionally retained only to delete a legacy localStorage value during migration.
for forbidden in ('id="trefleKey"', 'savePlantDataKey', 'token="+encodeURIComponent(token)', 'https://trefle.io/api/v1/species/search'):
    if forbidden in s:
        raise SystemExit(f'forbidden browser-side Trefle credential/reference remains: {forbidden}')
if s.count('state.settings.trefleKey') > 1:
    raise SystemExit('unexpected Trefle token references remain outside the one-time deletion migration')

required = [
    '/functions/v1/trefle-enrich',
    'scientific_name:sci',
    'garden_id:String(syncState.gardenId||"")',
    'secret_hash:secretHash',
    'delete state.settings.trefleKey',
    'Trefle-Zusatzdaten geschützt über Supabase aktiv',
]
for item in required:
    if item not in s:
        raise SystemExit(f'missing required secure proxy feature: {item}')

path.write_text(s, encoding='utf-8')
print('secure Trefle proxy client patch applied')
