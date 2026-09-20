'use strict';

function openDb(){
  return new Promise((resolve,reject)=>{
    if(!('indexedDB' in window))return reject(new Error('IndexedDB nicht verfügbar'));
    const req=indexedDB.open(DB_NAME,1);
    req.onupgradeneeded=()=>{const db=req.result;if(!db.objectStoreNames.contains(DB_STORE))db.createObjectStore(DB_STORE)};
    req.onsuccess=()=>resolve(req.result); req.onerror=()=>reject(req.error||new Error('IndexedDB konnte nicht geöffnet werden'));
  });
}
async function idbGet(){const db=await openDb();return new Promise((resolve,reject)=>{const tx=db.transaction(DB_STORE,'readonly'),req=tx.objectStore(DB_STORE).get(DB_KEY);req.onsuccess=()=>resolve(req.result||null);req.onerror=()=>reject(req.error);tx.oncomplete=()=>db.close()})}
async function idbPut(value){const db=await openDb();return new Promise((resolve,reject)=>{const tx=db.transaction(DB_STORE,'readwrite');tx.objectStore(DB_STORE).put(value,DB_KEY);tx.oncomplete=()=>{db.close();resolve(true)};tx.onerror=()=>{db.close();reject(tx.error||new Error('IndexedDB-Schreibfehler'))};tx.onabort=()=>{db.close();reject(tx.error||new Error('IndexedDB abgebrochen'))}})}
async function idbClear(){const db=await openDb();return new Promise((resolve,reject)=>{const tx=db.transaction(DB_STORE,'readwrite');tx.objectStore(DB_STORE).delete(DB_KEY);tx.oncomplete=()=>{db.close();resolve(true)};tx.onerror=()=>{db.close();reject(tx.error)}})}

async function loadState(){
  try{
    const stored=await idbGet();
    if(stored)return migrate(stored);
    const raw=localStorage.getItem(STORAGE_KEY);
    if(raw){
      const migrated=migrate(JSON.parse(raw));
      await idbPut(migrated);
      localStorage.removeItem(STORAGE_KEY);
      localStorage.setItem(MIGRATION_MARKER,new Date().toISOString());
      return migrated;
    }
    const d=defaultState(); await idbPut(d); return d;
  }catch(e){
    console.warn('IndexedDB nicht verfügbar, localStorage-Fallback aktiv.',e); persistenceMode='localstorage';
    try{const raw=localStorage.getItem(STORAGE_KEY);if(raw)return migrate(JSON.parse(raw))}catch(err){console.warn(err)}
    return defaultState();
  }
}
function pruneState(){
  if(state.activity?.length>3000)state.activity=state.activity.slice(-3000);
  state.learners?.forEach(l=>{
    if(l.campaignLog?.length>500)l.campaignLog=l.campaignLog.slice(-500);
    if(l.streakDays?.length>900)l.streakDays=l.streakDays.slice(-900);
  });
}
async function persistState(){
  pruneState(); state.version=VERSION;
  if(persistenceMode==='indexeddb'){
    try{await idbPut(state);return true}catch(e){console.error('IndexedDB-Speichern fehlgeschlagen',e);showPersistenceWarning('Speichern fehlgeschlagen. Bitte jetzt ein Backup erstellen.');return false}
  }
  try{localStorage.setItem(STORAGE_KEY,JSON.stringify(state));return true}catch(e){console.error('localStorage-Speichern fehlgeschlagen',e);showPersistenceWarning('Lokaler Speicher ist voll. Bitte jetzt ein Backup erstellen.');return false}
}
function persistOnly(){
  persistRequested=true;
  if(persistRunning)return persistChain;
  persistRunning=true;
  persistChain=(async()=>{
    let ok=true;
    try{
      while(persistRequested){persistRequested=false;ok=(await persistState())&&ok;}
      return ok;
    }catch(e){console.error(e);return false}
    finally{persistRunning=false;if(persistRequested)persistOnly();}
  })();
  return persistChain;
}
function showPersistenceWarning(text){const el=document.querySelector('#storageStatus');if(el){el.className='notice bad';el.textContent=text}}
const safeText=(value,max=1000)=>String(value??'').replace(/\u0000/g,'').slice(0,max);
const safeId=(value,prefix='id',used=null)=>{const raw=String(value||'');if(SAFE_ID_RE.test(raw)&&(!used||!used.has(raw))){used?.add(raw);return raw}let id=uid(prefix);while(used?.has(id))id=uid(prefix);used?.add(id);return id};
const safeNumber=(value,min,max,fallback=0)=>{const n=Number(value);return Number.isFinite(n)?clamp(n,min,max):fallback};
function hardenState(s){
  if(!s||typeof s!=='object')return defaultState();
  const learnersIn=Array.isArray(s.learners)?s.learners.slice(0,20):[]; if(!learnersIn.length)return defaultState();
  const learnerUsed=new Set(),learnerMap=new Map();
  s.learners=learnersIn.map((raw,i)=>{const l=raw&&typeof raw==='object'?raw:{};const old=String(l.id||'');const id=safeId(old,'learner',learnerUsed);if(!learnerMap.has(old))learnerMap.set(old,id);l.id=id;l.name=safeText(l.name||`Profil ${i+1}`,80);l.xp=Math.round(safeNumber(l.xp,0,100000000,0));l.fontSize=safeNumber(l.fontSize,16,24,17);l.letterSpacing=safeNumber(l.letterSpacing,0,3,0);l.flashSpeed=Math.round(safeNumber(l.flashSpeed,800,4000,1600));return l});
  const learnerIds=new Set(s.learners.map(l=>l.id));const firstLearner=s.learners[0].id;const mapLearner=id=>learnerMap.get(String(id||''))|| (learnerIds.has(String(id||''))?String(id):firstLearner);
  const setUsed=new Set(),setMap=new Map();
  s.sets=(Array.isArray(s.sets)?s.sets:[]).slice(0,10000).map(raw=>{const x=raw&&typeof raw==='object'?raw:{};const old=String(x.id||'');const id=safeId(old,'set',setUsed);if(!setMap.has(old))setMap.set(old,id);return {...x,id,learnerId:mapLearner(x.learnerId),subject:x.subject==='latin'?'latin':'english',title:safeText(x.title||'Lernset',200),schoolYear:safeText(x.schoolYear||currentSchoolYear(),24),testDate:safeText(x.testDate||'',10),testScopeMode:x.testScopeMode==='range'?'range':'set',testFrom:Math.max(1,Math.round(safeNumber(x.testFrom,1,100000,1))),testTo:Math.max(0,Math.round(safeNumber(x.testTo,0,100000,0))),testFormat:['target','source','mixed','dictation'].includes(x.testFormat)?x.testFormat:'target'};});
  const setIds=new Set(s.sets.map(x=>x.id));const wordUsed=new Set();
  s.words=(Array.isArray(s.words)?s.words:[]).slice(0,100000).map(raw=>{const w=raw&&typeof raw==='object'?raw:{};const mappedSet=setMap.get(String(w.setId||''))||String(w.setId||'');if(!setIds.has(mappedSet))return null;const id=safeId(w.id,'w',wordUsed);return {...w,id,setId:mappedSet,term:safeText(w.term,300),translation:safeText(w.translation,700),extra:safeText(w.extra,700),example:safeText(w.example,2000),mnemonic:safeText(w.mnemonic,1200),image:'',chunks:(Array.isArray(w.chunks)?w.chunks:[]).slice(0,30).map(v=>safeText(v,120)).filter(Boolean),confusionWith:(Array.isArray(w.confusionWith)?w.confusionWith:[]).slice(0,10).map(v=>safeText(v,120))};}).filter(w=>w&&w.term&&w.translation);
  s.grades=(Array.isArray(s.grades)?s.grades:[]).slice(-5000).map(g=>({...g,id:safeId(g?.id,'g'),learnerId:mapLearner(g?.learnerId),date:safeText(g?.date,10),subject:g?.subject==='latin'?'latin':'english',grade:safeText(g?.grade,30),note:safeText(g?.note,1000),practiceTestId:g?.practiceTestId?safeText(g.practiceTestId,120):null}));
  s.practiceTests=(Array.isArray(s.practiceTests)?s.practiceTests:[]).slice(-5000).map(t=>({...t,id:safeId(t?.id,'pt'),learnerId:mapLearner(t?.learnerId),subject:t?.subject==='latin'?'latin':'english',scopeText:safeText(t?.scopeText,300),suggestedGrade:safeText(t?.suggestedGrade,30),correct:Math.max(0,Math.round(safeNumber(t?.correct,0,100000,0))),total:Math.max(0,Math.round(safeNumber(t?.total,0,100000,0))),percent:safeNumber(t?.percent,0,100,0)}));
  s.activity=(Array.isArray(s.activity)?s.activity:[]).slice(-3000).map(a=>({...a,id:safeId(a?.id,'a'),learnerId:mapLearner(a?.learnerId),type:safeText(a?.type,60),date:safeText(a?.date,40)}));
  s.learners.forEach(l=>{l.testSeries=l.testSeries||{english:null,latin:null};['english','latin'].forEach(subject=>{const cfg=l.testSeries[subject];if(cfg?.setId){const mapped=setMap.get(String(cfg.setId))||String(cfg.setId);if(setIds.has(mapped))cfg.setId=mapped;else l.testSeries[subject]=null;}})});
  s.activeLearnerId=mapLearner(s.activeLearnerId);s.activeSubject=s.activeSubject==='latin'?'latin':'english';return s;
}
function inspectBackup(x){
  if(!x||typeof x!=='object')return 'Keine gültigen App-Daten gefunden.';
  if(!Array.isArray(x.learners)||x.learners.length<1)return 'Das Backup enthält kein Lernprofil.';
  if(!Array.isArray(x.sets)||!Array.isArray(x.words))return 'Lernsets oder Vokabeln fehlen.';
  if(x.learners.length>20)return 'Das Backup enthält ungewöhnlich viele Profile.';
  if(x.sets.length>10000||x.words.length>100000)return 'Das Backup ist für diese App ungewöhnlich groß.';
  return '';
}
function migrate(s){
  if(!s || !Array.isArray(s.learners)) return defaultState();
  s.version=VERSION; s.activeSubject=s.activeSubject||'english'; s.grades=s.grades||[]; s.practiceTests=s.practiceTests||[]; s.activity=s.activity||[];
  s.learners.forEach(l=>{
    l.streakDays=l.streakDays||[]; l.milestones=l.milestones||{}; l.fortressWins=l.fortressWins||{english:[],latin:[]}; l.fortressWinsByYear=l.fortressWinsByYear||{}; l.campaignLog=l.campaignLog||[]; l.dailyPlans=l.dailyPlans||{}; l.testSeries=l.testSeries||{english:null,latin:null};
    l.fontSize=l.fontSize||17; l.letterSpacing=l.letterSpacing||0; l.flashSpeed=l.flashSpeed||1600; l.gradeScales=l.gradeScales||defaultGradeScales();
    ['english','latin'].forEach(subject=>{l.gradeScales[subject]={...defaultGradeScale(),...(l.gradeScales[subject]||{})};const key=`${subject}:${currentSchoolYear()}`;if(!l.fortressWinsByYear[key] && Array.isArray(l.fortressWins?.[subject]) && l.fortressWins[subject].length)l.fortressWinsByYear[key]=[...l.fortressWins[subject]]});
  });
  s.sets=(s.sets||[]).map(x=>({...x,schoolYear:x.schoolYear||currentSchoolYear(),testScopeMode:x.testScopeMode||'set',testFrom:Number(x.testFrom)||1,testTo:Number(x.testTo)||0,testFormat:x.testFormat||'target'}));
  s.words=(s.words||[]).map(w=>{
    const oldSkills=w.skills||{};
    const migratedSkills=('recognition' in oldSkills || 'retrieval' in oldSkills)
      ? {...defaultSkills(),...oldSkills}
      : {recognition:Math.max(oldSkills.reading||0,oldSkills.meaning||0),listening:oldSkills.listening||0,retrieval:oldSkills.meaning||0,spelling:oldSkills.spelling||0,context:oldSkills.context||0};
    const base={...makeWord(w.setId,w.term,w.translation,w),...w};
    base.skills=migratedSkills; base.errorProfile={meaning:0,retrieval:0,spelling:0,listening:0,context:0,...(w.errorProfile||{})}; base.practiceDays=w.practiceDays||[]; base.modesSeen=w.modesSeen||[]; base.chunks=w.chunks||[];
    base.independentSuccesses=Number.isFinite(w.independentSuccesses)?w.independentSuccesses:(w.successes||0); base.assistedSuccesses=w.assistedSuccesses||0; base.lastMasteredAt=w.lastMasteredAt||null;
    base.activeSuccessDays=Array.isArray(w.activeSuccessDays)?w.activeSuccessDays:[]; base.activePracticeDays=Array.isArray(w.activePracticeDays)?w.activePracticeDays:[...base.activeSuccessDays]; base.lastActiveSuccessAt=w.lastActiveSuccessAt||null; base.maxActiveGapDays=Number(w.maxActiveGapDays)||0; base.coldRecallDays=Array.isArray(w.coldRecallDays)?w.coldRecallDays:[]; base.coldRecallSuccesses=Number(w.coldRecallSuccesses)||base.coldRecallDays.length; base.recentActiveResults=Array.isArray(w.recentActiveResults)?w.recentActiveResults.slice(-8):[]; base.grammarSkills={genitive:0,gender:0,principalParts:0,form:0,...(w.grammarSkills||{})}; base.grammarSuccessDays=Array.isArray(w.grammarSuccessDays)?w.grammarSuccessDays:[];
    if(!base.activeSuccessDays.length && (base.skills.retrieval||0)>=2 && (base.skills.spelling||0)>=2 && (base.practiceDays||[]).length){
      const days=[...new Set(base.practiceDays)].sort().slice(-3);base.activeSuccessDays=days;let maxGap=0;for(let i=1;i<days.length;i++)maxGap=Math.max(maxGap,Math.max(0,dayNumber(days[i])-dayNumber(days[i-1])));base.maxActiveGapDays=Math.max(base.maxActiveGapDays,maxGap);if(days.length)base.lastActiveSuccessAt=`${days[days.length-1]}T12:00:00`;
    }
    if(!base.coldRecallDays.length && base.activeSuccessDays.length>=2 && (base.skills.retrieval||0)>=2){base.coldRecallDays=[...base.activeSuccessDays].sort().slice(-2);base.coldRecallSuccesses=Math.max(base.coldRecallSuccesses,base.coldRecallDays.length);}
    return base;
  });
  s.practiceTests=(s.practiceTests||[]).map(t=>{const subject=t.subject||'english';const owner=s.learners.find(l=>l.id===t.learnerId);const scale={...defaultGradeScale(),...((owner?.gradeScales||defaultGradeScales())[subject]||{})};return {...t,gradeScaleSnapshot:t.gradeScaleSnapshot||scale,suggestedGrade:t.suggestedGrade||suggestGradeFromScale(t.percent,scale)};});
  return hardenState(s);
}
function save(){persistOnly();renderAll();}