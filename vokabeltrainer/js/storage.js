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
function storagePayload(s=state){const out={...s};delete out.words;return out;}

async function loadState(){
  try{
    const stored=await idbGet();
    if(stored)return migrate(stored);
    const raw=localStorage.getItem(STORAGE_KEY);
    if(raw){
      const migrated=migrate(JSON.parse(raw));
      await idbPut(storagePayload(migrated));
      localStorage.removeItem(STORAGE_KEY);localStorage.setItem(MIGRATION_MARKER,new Date().toISOString());return migrated;
    }
    const d=defaultState();await idbPut(storagePayload(d));return d;
  }catch(e){
    console.warn('IndexedDB nicht verfügbar, localStorage-Fallback aktiv.',e);persistenceMode='localstorage';
    try{const raw=localStorage.getItem(STORAGE_KEY);if(raw)return migrate(JSON.parse(raw))}catch(err){console.warn(err)}
    return defaultState();
  }
}
function pruneState(){
  if(state.activity?.length>3000)state.activity=state.activity.slice(-3000);
  state.learners?.forEach(l=>{if(l.campaignLog?.length>500)l.campaignLog=l.campaignLog.slice(-500);if(l.streakDays?.length>900)l.streakDays=l.streakDays.slice(-900)});
  state.vocabulary?.forEach(v=>{if(v.sources?.length>60)v.sources=v.sources.slice(-60);if(v.examples?.length>12)v.examples=v.examples.slice(0,12);if(v.termVariants?.length>20)v.termVariants=v.termVariants.slice(0,20);if(v.translations?.length>20)v.translations=v.translations.slice(0,20)});
}
async function persistState(){
  pruneState();state.version=VERSION;rebuildWordIndexes();const payload=storagePayload(state);
  if(persistenceMode==='indexeddb'){
    try{await idbPut(payload);return true}catch(e){console.error('IndexedDB-Speichern fehlgeschlagen',e);showPersistenceWarning('Speichern fehlgeschlagen. Bitte jetzt ein Backup erstellen.');return false}
  }
  try{localStorage.setItem(STORAGE_KEY,JSON.stringify(payload));return true}catch(e){console.error('localStorage-Speichern fehlgeschlagen',e);showPersistenceWarning('Lokaler Speicher ist voll. Bitte jetzt ein Backup erstellen.');return false}
}
function persistOnly(){
  persistRequested=true;if(persistRunning)return persistChain;persistRunning=true;
  persistChain=(async()=>{let ok=true;try{while(persistRequested){persistRequested=false;ok=(await persistState())&&ok;}return ok}catch(e){console.error(e);return false}finally{persistRunning=false;if(persistRequested)persistOnly();}})();return persistChain;
}
function showPersistenceWarning(text){const el=document.querySelector('#storageStatus');if(el){el.className='notice bad';el.textContent=text}}
const safeText=(value,max=1000)=>String(value??'').replace(/\u0000/g,'').slice(0,max);
const safeId=(value,prefix='id',used=null)=>{const raw=String(value||'');if(SAFE_ID_RE.test(raw)&&(!used||!used.has(raw))){used?.add(raw);return raw}let id=uid(prefix);while(used?.has(id))id=uid(prefix);used?.add(id);return id};
const safeNumber=(value,min,max,fallback=0)=>{const n=Number(value);return Number.isFinite(n)?clamp(n,min,max):fallback};
const unionLimited=(a,b,max=1000)=>[...new Set([...(Array.isArray(a)?a:[]),...(Array.isArray(b)?b:[])])].slice(-max);
const newerDate=(a,b)=>String(a||'')>=String(b||'')?a:b;
function mergeProgress(target,source){
  const ts={...defaultSkills(),...(target.skills||{})},ss={...defaultSkills(),...(source.skills||{})};for(const k of Object.keys(ts))ts[k]=Math.max(Number(ts[k])||0,Number(ss[k])||0);target.skills=ts;
  for(const k of ['level','repetitions','successes','independentSuccesses','assistedSuccesses','failures','intervalDays','maxActiveGapDays','coldRecallSuccesses'])target[k]=Math.max(Number(target[k])||0,Number(source[k])||0);
  for(const k of ['activeSuccessDays','activePracticeDays','coldRecallDays','practiceDays','modesSeen','grammarSuccessDays'])target[k]=unionLimited(target[k],source[k],1000);
  target.recentActiveResults=[...(target.recentActiveResults||[]),...(source.recentActiveResults||[])].sort((a,b)=>String(a?.at||a?.date||'').localeCompare(String(b?.at||b?.date||''))).slice(-8);
  const tg={genitive:0,gender:0,principalParts:0,form:0,...(target.grammarSkills||{})},sg={genitive:0,gender:0,principalParts:0,form:0,...(source.grammarSkills||{})};for(const k of Object.keys(tg))tg[k]=Math.max(Number(tg[k])||0,Number(sg[k])||0);target.grammarSkills=tg;
  const te={meaning:0,retrieval:0,spelling:0,listening:0,context:0,grammar:0,...(target.errorProfile||{})},se={meaning:0,retrieval:0,spelling:0,listening:0,context:0,grammar:0,...(source.errorProfile||{})};for(const k of Object.keys(te))te[k]=Math.max(Number(te[k])||0,Number(se[k])||0);target.errorProfile=te;
  const sourceNewer=String(source.lastReviewedAt||'')>String(target.lastReviewedAt||'');if(sourceNewer){target.dueDate=source.dueDate||target.dueDate;target.intervalDays=Math.max(target.intervalDays||0,source.intervalDays||0)}
  target.lastReviewedAt=newerDate(target.lastReviewedAt,source.lastReviewedAt)||null;target.lastSuccessAt=newerDate(target.lastSuccessAt,source.lastSuccessAt)||null;target.lastActiveSuccessAt=newerDate(target.lastActiveSuccessAt,source.lastActiveSuccessAt)||null;
  target.masteredAt=newerDate(target.masteredAt,source.masteredAt)||null;target.lastMasteredAt=newerDate(target.lastMasteredAt,source.lastMasteredAt)||null;target.confusionWith=unionLimited(target.confusionWith,source.confusionWith,20);return target;
}
function migrateLegacyWordShape(w,learnerId,vocabId,id){
  const oldSkills=w.skills||{};
  const migratedSkills=('recognition' in oldSkills||'retrieval' in oldSkills)?{...defaultSkills(),...oldSkills}:{recognition:Math.max(oldSkills.reading||0,oldSkills.meaning||0),listening:oldSkills.listening||0,retrieval:oldSkills.meaning||0,spelling:oldSkills.spelling||0,context:oldSkills.context||0};
  const base=makeLearnerVocabulary(learnerId,vocabId,{...w,id,skills:migratedSkills,errorProfile:{meaning:0,retrieval:0,spelling:0,listening:0,context:0,grammar:0,...(w.errorProfile||{})},practiceDays:w.practiceDays||[],modesSeen:w.modesSeen||[],chunks:undefined});
  base.independentSuccesses=Number.isFinite(w.independentSuccesses)?w.independentSuccesses:(w.successes||0);base.assistedSuccesses=w.assistedSuccesses||0;base.lastMasteredAt=w.lastMasteredAt||null;
  base.activeSuccessDays=Array.isArray(w.activeSuccessDays)?w.activeSuccessDays:[];base.activePracticeDays=Array.isArray(w.activePracticeDays)?w.activePracticeDays:[...base.activeSuccessDays];base.lastActiveSuccessAt=w.lastActiveSuccessAt||null;base.maxActiveGapDays=Number(w.maxActiveGapDays)||0;base.coldRecallDays=Array.isArray(w.coldRecallDays)?w.coldRecallDays:[];base.coldRecallSuccesses=Number(w.coldRecallSuccesses)||base.coldRecallDays.length;base.recentActiveResults=Array.isArray(w.recentActiveResults)?w.recentActiveResults.slice(-8):[];base.grammarSkills={genitive:0,gender:0,principalParts:0,form:0,...(w.grammarSkills||{})};base.grammarSuccessDays=Array.isArray(w.grammarSuccessDays)?w.grammarSuccessDays:[];
  if(!base.activeSuccessDays.length&&(base.skills.retrieval||0)>=2&&(base.skills.spelling||0)>=2&&(base.practiceDays||[]).length){const days=[...new Set(base.practiceDays)].sort().slice(-3);base.activeSuccessDays=days;let maxGap=0;for(let i=1;i<days.length;i++){const a=new Date(`${days[i-1]}T12:00:00`),b=new Date(`${days[i]}T12:00:00`);maxGap=Math.max(maxGap,Math.max(0,Math.round((b-a)/864e5)))}base.maxActiveGapDays=Math.max(base.maxActiveGapDays,maxGap);if(days.length)base.lastActiveSuccessAt=`${days[days.length-1]}T12:00:00`;}
  if(!base.coldRecallDays.length&&base.activeSuccessDays.length>=2&&(base.skills.retrieval||0)>=2){base.coldRecallDays=[...base.activeSuccessDays].sort().slice(-2);base.coldRecallSuccesses=Math.max(base.coldRecallSuccesses,base.coldRecallDays.length)}return base;
}
function migrateLegacyLibrary(s){
  const legacy=Array.isArray(s.words)?s.words:[];if(!legacy.length){s.vocabulary=s.vocabulary||[];s.setVocabulary=s.setVocabulary||[];s.learnerVocabulary=s.learnerVocabulary||[];delete s.words;return s;}
  s.vocabulary=[];s.setVocabulary=[];s.learnerVocabulary=[];
  const setById=new Map((s.sets||[]).map(x=>[String(x.id),x])),vocabBuckets=new Map(),progressByCombo=new Map(),oldWordMap=new Map(),setPos=new Map();
  for(const w of legacy){
    const set=setById.get(String(w.setId||''));if(!set||!w?.term||!w?.translation)continue;const subject=set.subject==='latin'?'latin':'english';const baseKey=lexicalKey(w.term,subject);if(!baseKey)continue;
    const bucketKey=`${subject}\u0000${baseKey}`;let candidates=vocabBuckets.get(bucketKey)||[];let v=null;
    if(subject==='latin'&&candidates.length){const ex=lexicalKey(w.extra||'',subject);v=candidates.find(x=>ex&&lexicalKey(x.extra||'',subject)===ex)||candidates.find(x=>!ex||!x.extra)||null;}else v=candidates[0]||null;
    if(!v){v=makeVocabulary(subject,w.term,w.translation,{extra:w.extra||'',examples:w.example?[w.example]:[],mnemonic:w.mnemonic||'',chunks:w.chunks||[],sources:[{kind:w.source||'migration',setId:set.id,at:new Date().toISOString()}],verifiedAt:new Date().toISOString()});s.vocabulary.push(v);candidates=[...candidates,v];vocabBuckets.set(bucketKey,candidates)}
    else{
      if(w.term!==v.term&&!v.termVariants.includes(w.term))v.termVariants.push(w.term);if(w.translation!==v.translation&&!v.translations.includes(w.translation))v.translations.push(w.translation);if(w.extra&&!v.extra)v.extra=w.extra;if(w.example&&!v.examples.includes(w.example))v.examples.push(w.example);if(w.mnemonic&&!v.mnemonic)v.mnemonic=w.mnemonic;if((w.chunks||[]).length&&!v.chunks.length)v.chunks=[...w.chunks];if(!v.sources.some(x=>x.setId===set.id))v.sources.push({kind:w.source||'migration',setId:set.id,at:new Date().toISOString()});
    }
    const combo=`${set.learnerId}\u0000${v.id}`;let p=progressByCombo.get(combo);const incoming=migrateLegacyWordShape(w,set.learnerId,v.id,p?uid('w'):w.id||uid('w'));
    if(!p){p=incoming;s.learnerVocabulary.push(p);progressByCombo.set(combo,p)}else mergeProgress(p,incoming);oldWordMap.set(String(w.id||''),p.id);
    const position=(setPos.get(set.id)||0)+1;setPos.set(set.id,position);s.setVocabulary.push(makeSetVocabulary(set.id,v.id,{position,termOverride:w.term!==v.term?w.term:'',translationOverride:w.translation!==v.translation?w.translation:'',extraOverride:(w.extra||'')!==(v.extra||'')?(w.extra||''):'',exampleOverride:(w.example||'')!==((v.examples||[])[0]||'')?(w.example||''):'',source:w.source||'migration'}));
  }
  const remapId=id=>oldWordMap.get(String(id||''))||String(id||'');
  (s.learners||[]).forEach(l=>{for(const plan of Object.values(l.dailyPlans||{})){if(Array.isArray(plan.wordIds))plan.wordIds=[...new Set(plan.wordIds.map(remapId))];if(Array.isArray(plan.wordRefs))plan.wordRefs=plan.wordRefs.map(r=>({...r,wordId:remapId(r.wordId)}));}});
  (s.practiceTests||[]).forEach(t=>{(t.answers||[]).forEach(a=>{if(a.wordId)a.wordId=remapId(a.wordId)});if(Array.isArray(t.wordIds))t.wordIds=[...new Set(t.wordIds.map(remapId))]});
  (s.activity||[]).forEach(a=>{if(a.wordId)a.wordId=remapId(a.wordId)});s.learnerVocabulary.forEach(p=>{p.confusionWith=(p.confusionWith||[]).map(remapId)});delete s.words;return s;
}
function hardenState(s){
  if(!s||typeof s!=='object')return defaultState();
  const learnersIn=Array.isArray(s.learners)?s.learners.slice(0,20):[];if(!learnersIn.length)return defaultState();
  const learnerUsed=new Set(),learnerMap=new Map();
  s.learners=learnersIn.map((raw,i)=>{const l=raw&&typeof raw==='object'?raw:{};const old=String(l.id||'');const id=safeId(old,'learner',learnerUsed);if(!learnerMap.has(old))learnerMap.set(old,id);return {...l,id,name:safeText(l.name||`Profil ${i+1}`,80),xp:Math.round(safeNumber(l.xp,0,100000000,0)),fontSize:safeNumber(l.fontSize,16,24,17),letterSpacing:safeNumber(l.letterSpacing,0,3,0),flashSpeed:Math.round(safeNumber(l.flashSpeed,800,4000,1600))}});
  const learnerIds=new Set(s.learners.map(l=>l.id)),firstLearner=s.learners[0].id,mapLearner=id=>learnerMap.get(String(id||''))||(learnerIds.has(String(id||''))?String(id):firstLearner);
  const setUsed=new Set(),setMap=new Map();
  s.sets=(Array.isArray(s.sets)?s.sets:[]).slice(0,10000).map(raw=>{const x=raw&&typeof raw==='object'?raw:{};const old=String(x.id||'');const id=safeId(old,'set',setUsed);if(!setMap.has(old))setMap.set(old,id);return {...x,id,learnerId:mapLearner(x.learnerId),subject:x.subject==='latin'?'latin':'english',title:safeText(x.title||'Lernset',200),schoolYear:safeText(x.schoolYear||currentSchoolYear(),24),testDate:safeText(x.testDate||'',10),testScopeMode:x.testScopeMode==='range'?'range':'set',testFrom:Math.max(1,Math.round(safeNumber(x.testFrom,1,100000,1))),testTo:Math.max(0,Math.round(safeNumber(x.testTo,0,100000,0))),testFormat:['target','source','mixed','dictation'].includes(x.testFormat)?x.testFormat:'target'};});
  const setIds=new Set(s.sets.map(x=>x.id));
  const vocabUsed=new Set(),vocabMap=new Map();
  s.vocabulary=(Array.isArray(s.vocabulary)?s.vocabulary:[]).slice(0,100000).map(raw=>{const v=raw&&typeof raw==='object'?raw:{};const old=String(v.id||'');const id=safeId(old,'v',vocabUsed);if(!vocabMap.has(old))vocabMap.set(old,id);return {...v,id,subject:v.subject==='latin'?'latin':'english',term:safeText(v.term,300).trim(),translation:safeText(v.translation,700).trim(),termVariants:(Array.isArray(v.termVariants)?v.termVariants:[]).slice(0,20).map(x=>safeText(x,300).trim()).filter(Boolean),translations:(Array.isArray(v.translations)?v.translations:[]).slice(0,20).map(x=>safeText(x,700).trim()).filter(Boolean),extra:safeText(v.extra,700),examples:(Array.isArray(v.examples)?v.examples:[]).slice(0,12).map(x=>safeText(x,2000)).filter(Boolean),mnemonic:safeText(v.mnemonic,1200),chunks:(Array.isArray(v.chunks)?v.chunks:[]).slice(0,30).map(x=>safeText(x,120)).filter(Boolean),sources:(Array.isArray(v.sources)?v.sources:[]).slice(-60).map(x=>({kind:safeText(x?.kind||'unknown',80),setId:safeText(setMap.get(String(x?.setId||''))||x?.setId||'',120),at:safeText(x?.at||'',40)})),verifiedAt:v.verifiedAt?safeText(v.verifiedAt,40):null,createdAt:safeText(v.createdAt||new Date().toISOString(),40),updatedAt:safeText(v.updatedAt||v.createdAt||new Date().toISOString(),40)};}).filter(v=>v.term&&v.translation);
  const vocabIds=new Set(s.vocabulary.map(v=>v.id));
  const progressUsed=new Set(),progressMap=new Map(),progressByCombo=new Map(),cleanProgress=[];
  for(const raw of (Array.isArray(s.learnerVocabulary)?s.learnerVocabulary:[]).slice(0,100000)){
    const p0=raw&&typeof raw==='object'?raw:{};const old=String(p0.id||'');const learnerId=mapLearner(p0.learnerId),vocabId=vocabMap.get(String(p0.vocabId||''))||String(p0.vocabId||'');if(!vocabIds.has(vocabId))continue;
    const id=safeId(old,'w',progressUsed);const p=makeLearnerVocabulary(learnerId,vocabId,{...p0,id});const combo=`${learnerId}\u0000${vocabId}`,existing=progressByCombo.get(combo);
    if(existing){mergeProgress(existing,p);progressMap.set(old,existing.id)}else{cleanProgress.push(p);progressByCombo.set(combo,p);progressMap.set(old,p.id)}
  }
  s.learnerVocabulary=cleanProgress;const progressIds=new Set(cleanProgress.map(x=>x.id));
  const rawSetVocabulary=(Array.isArray(s.setVocabulary)?s.setVocabulary:[]).slice(0,200000);
  const linkUsed=new Set(),seenLink=new Set(),setPositions=new Map();s.setVocabulary=[];
  for(const raw of rawSetVocabulary){
    const x=raw&&typeof raw==='object'?raw:{};const setId=setMap.get(String(x.setId||''))||String(x.setId||''),vocabId=vocabMap.get(String(x.vocabId||''))||String(x.vocabId||'');if(!setIds.has(setId)||!vocabIds.has(vocabId))continue;const set=s.sets.find(z=>z.id===setId),v=s.vocabulary.find(z=>z.id===vocabId);if(!set||!v||set.subject!==v.subject)continue;const combo=`${setId}\u0000${vocabId}`;if(seenLink.has(combo))continue;seenLink.add(combo);const id=safeId(x.id,'sv',linkUsed),next=(setPositions.get(setId)||0)+1,position=Math.max(next,Math.round(safeNumber(x.position,1,100000,next)));setPositions.set(setId,position);s.setVocabulary.push(makeSetVocabulary(setId,vocabId,{...x,id,position,termOverride:safeText(x.termOverride,300),translationOverride:safeText(x.translationOverride,700),extraOverride:safeText(x.extraOverride,700),exampleOverride:safeText(x.exampleOverride,2000),source:safeText(x.source,80)}));
    const progressCombo=`${set.learnerId}\u0000${vocabId}`;if(!progressByCombo.has(progressCombo)){const p=makeLearnerVocabulary(set.learnerId,vocabId);s.learnerVocabulary.push(p);progressByCombo.set(progressCombo,p);progressIds.add(p.id)}
  }
  s.learnerVocabulary.forEach(p=>{p.confusionWith=(p.confusionWith||[]).map(id=>progressMap.get(String(id))||String(id)).filter(id=>progressIds.has(id)).slice(0,20)});
  const remapProgress=id=>progressMap.get(String(id||''))||(progressIds.has(String(id||''))?String(id):String(id||''));
  s.learners.forEach(l=>{l.streakDays=l.streakDays||[];l.milestones=l.milestones||{};l.fortressWins=l.fortressWins||{english:[],latin:[]};l.fortressWinsByYear=l.fortressWinsByYear||{};l.campaignLog=l.campaignLog||[];l.dailyPlans=l.dailyPlans||{};l.testSeries=l.testSeries||{english:null,latin:null};l.gradeScales=l.gradeScales||defaultGradeScales();['english','latin'].forEach(subject=>{l.gradeScales[subject]={...defaultGradeScale(),...(l.gradeScales[subject]||{})};const cfg=l.testSeries[subject];if(cfg?.setId){const mapped=setMap.get(String(cfg.setId))||String(cfg.setId);if(setIds.has(mapped))cfg.setId=mapped;else l.testSeries[subject]=null;}const key=`${subject}:${currentSchoolYear()}`;if(!l.fortressWinsByYear[key]&&Array.isArray(l.fortressWins?.[subject])&&l.fortressWins[subject].length)l.fortressWinsByYear[key]=[...l.fortressWins[subject]]});for(const plan of Object.values(l.dailyPlans)){if(Array.isArray(plan.wordIds))plan.wordIds=[...new Set(plan.wordIds.map(remapProgress).filter(id=>progressIds.has(id)))];if(Array.isArray(plan.wordRefs))plan.wordRefs=plan.wordRefs.map(r=>({...r,wordId:remapProgress(r.wordId)})).filter(r=>progressIds.has(r.wordId));}});
  s.grades=(Array.isArray(s.grades)?s.grades:[]).slice(-5000).map(g=>({...g,id:safeId(g?.id,'g'),learnerId:mapLearner(g?.learnerId),date:safeText(g?.date,10),subject:g?.subject==='latin'?'latin':'english',grade:safeText(g?.grade,30),note:safeText(g?.note,1000),practiceTestId:g?.practiceTestId?safeText(g.practiceTestId,120):null}));
  s.practiceTests=(Array.isArray(s.practiceTests)?s.practiceTests:[]).slice(-3000).map(t=>({...t,id:safeId(t?.id,'pt'),learnerId:mapLearner(t?.learnerId),subject:t?.subject==='latin'?'latin':'english',scopeText:safeText(t?.scopeText,700),answers:(Array.isArray(t?.answers)?t.answers:[]).slice(0,1000).map(a=>({...a,wordId:remapProgress(a?.wordId),answer:safeText(a?.answer,1000),target:safeText(a?.target,1000),prompt:safeText(a?.prompt,1000)}))}));
  s.activity=(Array.isArray(s.activity)?s.activity:[]).slice(-3000).map(a=>({...a,id:safeId(a?.id,'a'),learnerId:mapLearner(a?.learnerId),type:safeText(a?.type,80),wordId:a?.wordId?remapProgress(a.wordId):a?.wordId}));
  s.activeLearnerId=mapLearner(s.activeLearnerId);s.activeSubject=s.activeSubject==='latin'?'latin':'english';s.version=VERSION;attachRuntimeWordApi(s);return s;
}
function inspectBackup(x){
  if(!x||typeof x!=='object')return 'Keine gültigen App-Daten gefunden.';if(!Array.isArray(x.learners)||x.learners.length<1)return 'Das Backup enthält kein Lernprofil.';if(!Array.isArray(x.sets))return 'Lernsets fehlen.';
  const legacy=Array.isArray(x.words),normalized=Array.isArray(x.vocabulary)&&Array.isArray(x.setVocabulary)&&Array.isArray(x.learnerVocabulary);if(!legacy&&!normalized)return 'Vokabeldaten fehlen.';
  if(x.learners.length>20)return 'Das Backup enthält ungewöhnlich viele Profile.';if(x.sets.length>10000)return 'Das Backup ist für diese App ungewöhnlich groß.';if(legacy&&x.words.length>100000)return 'Das Backup enthält ungewöhnlich viele Vokabeln.';if(normalized&&(x.vocabulary.length>100000||x.setVocabulary.length>200000||x.learnerVocabulary.length>100000))return 'Das Backup ist für diese App ungewöhnlich groß.';return '';
}
function migrate(s){
  if(!s||!Array.isArray(s.learners))return defaultState();s.version=VERSION;s.activeSubject=s.activeSubject||'english';s.grades=s.grades||[];s.practiceTests=s.practiceTests||[];s.activity=s.activity||[];
  s.learners.forEach(l=>{l.streakDays=l.streakDays||[];l.milestones=l.milestones||{};l.fortressWins=l.fortressWins||{english:[],latin:[]};l.fortressWinsByYear=l.fortressWinsByYear||{};l.campaignLog=l.campaignLog||[];l.dailyPlans=l.dailyPlans||{};l.testSeries=l.testSeries||{english:null,latin:null};l.fontSize=l.fontSize||17;l.letterSpacing=l.letterSpacing||0;l.flashSpeed=l.flashSpeed||1600;l.gradeScales=l.gradeScales||defaultGradeScales();['english','latin'].forEach(subject=>{l.gradeScales[subject]={...defaultGradeScale(),...(l.gradeScales[subject]||{})};const key=`${subject}:${currentSchoolYear()}`;if(!l.fortressWinsByYear[key]&&Array.isArray(l.fortressWins?.[subject])&&l.fortressWins[subject].length)l.fortressWinsByYear[key]=[...l.fortressWins[subject]]})});
  s.sets=(s.sets||[]).map(x=>({...x,schoolYear:x.schoolYear||currentSchoolYear(),testScopeMode:x.testScopeMode||'set',testFrom:Number(x.testFrom)||1,testTo:Number(x.testTo)||0,testFormat:x.testFormat||'target'}));
  migrateLegacyLibrary(s);
  s.practiceTests=(s.practiceTests||[]).map(t=>{const subject=t.subject||'english',owner=s.learners.find(l=>l.id===t.learnerId),scale={...defaultGradeScale(),...((owner?.gradeScales||defaultGradeScales())[subject]||{})};return {...t,gradeScaleSnapshot:t.gradeScaleSnapshot||scale,suggestedGrade:t.suggestedGrade||suggestGradeFromScale(t.percent,scale)}});
  return hardenState(s);
}
function save(){persistOnly();renderAll();}