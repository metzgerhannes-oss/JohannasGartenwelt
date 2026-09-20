'use strict';

const VERSION = '0.9.10';
const STORAGE_KEY = 'vokabeltrainer_v07';
const DB_NAME = 'vokabeltrainer-db';
const DB_STORE = 'app-state';
const DB_KEY = 'main';
const MIGRATION_MARKER = 'vokabeltrainer_v08_idb_migrated';
let persistenceMode = 'indexeddb';
let persistChain = Promise.resolve();
let persistRunning = false;
let persistRequested = false;
const MAX_BACKUP_BYTES = 25 * 1024 * 1024;
const MAX_CSV_BYTES = 15 * 1024 * 1024;
const MAX_PHOTO_BYTES = 20 * 1024 * 1024;
const SAFE_ID_RE = /^[A-Za-z0-9_-]{1,120}$/;
const dateKey = (d=new Date()) => `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
const today = () => dateKey(new Date());
const datePlusDays = days => { const d=new Date(); d.setHours(12,0,0,0); d.setDate(d.getDate()+days); return dateKey(d); };
const uid = (p='id') => `${p}_${Date.now().toString(36)}_${Math.random().toString(36).slice(2,8)}`;
const clamp = (n,min,max) => Math.max(min, Math.min(max,n));
const deepClone = obj => JSON.parse(JSON.stringify(obj));
const currentSchoolYear = () => {
  const d = new Date(); const y = d.getFullYear(); const start = d.getMonth() >= 7 ? y : y-1;
  return `${start}/${String(start+1).slice(-2)}`;
};

const defaultSkills = () => ({recognition:0,listening:0,retrieval:0,spelling:0,context:0});
const defaultGradeScale = () => ({n1:90,n2:80,n3:65,n4:50,n5:25});
const defaultGradeScales = () => ({english:defaultGradeScale(),latin:defaultGradeScale()});
const PROGRESS_FIELDS = new Set([
  'skills','level','repetitions','successes','independentSuccesses','assistedSuccesses','failures','intervalDays','dueDate',
  'lastReviewedAt','lastSuccessAt','lastActiveSuccessAt','activeSuccessDays','activePracticeDays','maxActiveGapDays','coldRecallDays',
  'coldRecallSuccesses','recentActiveResults','practiceDays','modesSeen','grammarSkills','grammarSuccessDays','errorProfile',
  'masteredAt','lastMasteredAt','confusionWith'
]);

function makeLearnerVocabulary(learnerId,vocabId,opts={}){
  return {
    id:opts.id||uid('w'),learnerId,vocabId,
    skills:{...defaultSkills(),...(opts.skills||{})},level:Number(opts.level)||0,repetitions:Number(opts.repetitions)||0,
    successes:Number(opts.successes)||0,independentSuccesses:Number(opts.independentSuccesses)||0,assistedSuccesses:Number(opts.assistedSuccesses)||0,failures:Number(opts.failures)||0,
    intervalDays:Number(opts.intervalDays)||0,dueDate:opts.dueDate||today(),lastReviewedAt:opts.lastReviewedAt||null,lastSuccessAt:opts.lastSuccessAt||null,lastActiveSuccessAt:opts.lastActiveSuccessAt||null,
    activeSuccessDays:Array.isArray(opts.activeSuccessDays)?opts.activeSuccessDays:[],activePracticeDays:Array.isArray(opts.activePracticeDays)?opts.activePracticeDays:[],maxActiveGapDays:Number(opts.maxActiveGapDays)||0,
    coldRecallDays:Array.isArray(opts.coldRecallDays)?opts.coldRecallDays:[],coldRecallSuccesses:Number(opts.coldRecallSuccesses)||0,recentActiveResults:Array.isArray(opts.recentActiveResults)?opts.recentActiveResults.slice(-8):[],
    practiceDays:Array.isArray(opts.practiceDays)?opts.practiceDays:[],modesSeen:Array.isArray(opts.modesSeen)?opts.modesSeen:[],
    grammarSkills:{genitive:0,gender:0,principalParts:0,form:0,...(opts.grammarSkills||{})},grammarSuccessDays:Array.isArray(opts.grammarSuccessDays)?opts.grammarSuccessDays:[],
    errorProfile:{meaning:0,retrieval:0,spelling:0,listening:0,context:0,grammar:0,...(opts.errorProfile||{})},
    masteredAt:opts.masteredAt||null,lastMasteredAt:opts.lastMasteredAt||null,confusionWith:Array.isArray(opts.confusionWith)?opts.confusionWith:[]
  };
}
function makeVocabulary(subject,term,translation,opts={}){
  const now=new Date().toISOString();
  return {
    id:opts.id||uid('v'),subject:subject==='latin'?'latin':'english',term:String(term||'').trim(),translation:String(translation||'').trim(),
    termVariants:Array.isArray(opts.termVariants)?[...new Set(opts.termVariants.filter(Boolean))]:[],
    translations:Array.isArray(opts.translations)?[...new Set(opts.translations.filter(Boolean))]:[],
    extra:opts.extra||'',examples:Array.isArray(opts.examples)?opts.examples.filter(Boolean):[],mnemonic:opts.mnemonic||'',chunks:Array.isArray(opts.chunks)?opts.chunks.filter(Boolean):[],
    sources:Array.isArray(opts.sources)?opts.sources:[],verifiedAt:opts.verifiedAt||null,createdAt:opts.createdAt||now,updatedAt:opts.updatedAt||now
  };
}
function makeSetVocabulary(setId,vocabId,opts={}){
  return {id:opts.id||uid('sv'),setId,vocabId,position:Number(opts.position)||0,termOverride:opts.termOverride||'',translationOverride:opts.translationOverride||'',extraOverride:opts.extraOverride||'',exampleOverride:opts.exampleOverride||'',source:opts.source||'',createdAt:opts.createdAt||new Date().toISOString()};
}
function defaultState(){
  const s={
    version: VERSION,
    activeLearnerId: 'learner_demo',activeSubject: 'english',
    learners:[{id:'learner_demo',name:'Mein Profil',xp:0,lrsMode:false,fontSize:17,letterSpacing:0,flashSpeed:1600,streakDays:[],milestones:{},fortressWins:{english:[],latin:[]},fortressWinsByYear:{},campaignLog:[],dailyPlans:{},testSeries:{english:null,latin:null},gradeScales:defaultGradeScales(),createdAt:new Date().toISOString()}],
    sets:[],vocabulary:[],setVocabulary:[],learnerVocabulary:[],grades:[],practiceTests:[],activity:[]
  };
  attachRuntimeWordApi(s);return s;
}

function lexicalKey(term,subject='english'){
  let x=String(term||'').normalize('NFKC').toLowerCase().replace(/[’‘`´]/g,"'").trim();
  if(subject==='english'){
    const contractions={"i'm":'i am',"you're":'you are',"he's":'he is',"she's":'she is',"it's":'it is',"we're":'we are',"they're":'they are',"can't":'cannot',"don't":'do not',"doesn't":'does not',"didn't":'did not',"won't":'will not'};
    x=contractions[x]||x;
    x=x.replace(/^to\s+([a-z][a-z' -]+)$/,'$1').replace(/\s*\(\s*to\s*\)\s*$/,'');
  }
  return x.normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/[.,;:!?()[\]{}"']/g,'').replace(/\s+/g,' ').trim();
}
function vocabularyMatch(subject,term,extra='',translation=''){
  if(!state)return null; const key=lexicalKey(term,subject);if(!key)return null;
  const candidates=(state.vocabulary||[]).filter(v=>v.subject===subject&&lexicalKey(v.term,subject)===key);
  if(!candidates.length)return null;if(candidates.length===1)return candidates[0];
  const tr=lexicalKey(translation,'english'), ex=lexicalKey(extra,subject);
  if(subject==='latin'&&ex){const exact=candidates.find(v=>lexicalKey(v.extra,subject)===ex);if(exact)return exact;}
  if(tr){const exact=candidates.find(v=>[v.translation,...(v.translations||[])].some(x=>lexicalKey(x,'english')===tr));if(exact)return exact;}
  return candidates[0];
}
function vocabularyUsage(vocabId){
  const links=(state?.setVocabulary||[]).filter(x=>x.vocabId===vocabId);const setIds=new Set(links.map(x=>x.setId));const learnerIds=new Set((state?.sets||[]).filter(s=>setIds.has(s.id)).map(s=>s.learnerId));
  return {links:links.length,sets:setIds.size,learners:learnerIds.size,setIds:[...setIds],learnerIds:[...learnerIds]};
}
function progressForVocabulary(vocabId,learnerId=state?.activeLearnerId){return (state?.learnerVocabulary||[]).find(x=>x.vocabId===vocabId&&x.learnerId===learnerId)||null;}
function ensureLearnerVocabulary(learnerId,vocabId,opts={}){
  let p=(state.learnerVocabulary||[]).find(x=>x.learnerId===learnerId&&x.vocabId===vocabId);if(p)return p;
  p=makeLearnerVocabulary(learnerId,vocabId,opts);state.learnerVocabulary.push(p);rebuildWordIndexes();return p;
}
function rebuildWordIndexes(s=state){
  if(!s)return null;const idx={vocab:new Map(),progress:new Map(),progressByCombo:new Map(),links:new Map(),sets:new Map(),learners:new Map()};
  (s.vocabulary||[]).forEach(x=>idx.vocab.set(x.id,x));(s.learnerVocabulary||[]).forEach(x=>{idx.progress.set(x.id,x);idx.progressByCombo.set(`${x.learnerId}\u0000${x.vocabId}`,x)});(s.setVocabulary||[]).forEach(x=>idx.links.set(x.id,x));(s.sets||[]).forEach(x=>idx.sets.set(x.id,x));(s.learners||[]).forEach(x=>idx.learners.set(x.id,x));
  Object.defineProperty(s,'_wordIndexes',{value:idx,writable:true,configurable:true,enumerable:false});return idx;
}
function wordViewForLink(link,s=state){
  if(!link||!s)return null;const idx=s._wordIndexes||rebuildWordIndexes(s),v=idx.vocab.get(link.vocabId),set=idx.sets.get(link.setId);if(!v||!set)return null;
  const p=idx.progressByCombo.get(`${set.learnerId}\u0000${v.id}`);if(!p)return null;
  const getValue=prop=>{
    if(prop==='id')return p.id;if(prop==='setId')return link.setId;if(prop==='setLinkId')return link.id;if(prop==='vocabId')return v.id;if(prop==='learnerId')return p.learnerId;if(prop==='subject')return v.subject;
    if(prop==='term')return link.termOverride||v.term;if(prop==='translation')return link.translationOverride||v.translation;if(prop==='extra')return link.extraOverride||v.extra||'';if(prop==='example')return link.exampleOverride||(v.examples||[])[0]||'';
    if(prop==='mnemonic')return v.mnemonic||'';if(prop==='chunks')return v.chunks||[];if(prop==='termVariants')return v.termVariants||[];if(prop==='translations')return v.translations||[];if(prop==='source')return link.source||'';
    if(prop==='toJSON')return ()=>{const o={};for(const k of ['id','setId','setLinkId','vocabId','learnerId','subject','term','translation','extra','example','mnemonic','chunks'])o[k]=getValue(k);Object.assign(o,p);return o;};
    if(prop in p)return p[prop];if(prop in link)return link[prop];if(prop in v)return v[prop];return undefined;
  };
  return new Proxy({}, {get:(_t,prop)=>getValue(prop),set:(_t,prop,value)=>{
    if(PROGRESS_FIELDS.has(prop)||prop in p){p[prop]=value;return true;}
    if(prop==='term'){link.termOverride=String(value||'');return true;}if(prop==='translation'){link.translationOverride=String(value||'');return true;}if(prop==='extra'){link.extraOverride=String(value||'');return true;}if(prop==='example'){link.exampleOverride=String(value||'');return true;}
    if(prop==='mnemonic'){v.mnemonic=String(value||'');return true;}if(prop==='chunks'){v.chunks=Array.isArray(value)?value:[];return true;}return false;
  },ownKeys:()=>[...new Set(['id','setId','setLinkId','vocabId','learnerId','subject','term','translation','extra','example','mnemonic','chunks',...Object.keys(p),...Object.keys(link),...Object.keys(v)])],getOwnPropertyDescriptor:()=>({enumerable:true,configurable:true})});
}
function attachRuntimeWordApi(s){
  rebuildWordIndexes(s);
  try{Object.defineProperty(s,'words',{configurable:true,enumerable:false,get(){return (s.setVocabulary||[]).map(link=>wordViewForLink(link,s)).filter(Boolean)}});}catch(_e){}
  return s;
}
function wordByLinkId(linkId){const link=(state?.setVocabulary||[]).find(x=>x.id===linkId);return link?wordViewForLink(link):null;}
function wordById(progressId,preferredSetId=''){
  const p=(state?.learnerVocabulary||[]).find(x=>x.id===progressId);if(!p)return null;
  const setsByLearner=new Set((state.sets||[]).filter(s=>s.learnerId===p.learnerId).map(s=>s.id));
  let link=(state.setVocabulary||[]).find(x=>x.vocabId===p.vocabId&&x.setId===preferredSetId&&setsByLearner.has(x.setId));
  if(!link)link=(state.setVocabulary||[]).find(x=>x.vocabId===p.vocabId&&setsByLearner.has(x.setId));return link?wordViewForLink(link):null;
}
function globalVocabulary(subject=state?.activeSubject){return (state?.vocabulary||[]).filter(v=>v.subject===subject);}
function addVocabularySource(v,source,setId=''){
  if(!v)return;v.sources=Array.isArray(v.sources)?v.sources:[];const item={kind:source||'manual',setId:setId||'',at:new Date().toISOString()};if(!v.sources.some(x=>x.kind===item.kind&&x.setId===item.setId))v.sources.push(item);v.updatedAt=new Date().toISOString();
}
function upsertVocabulary(subject,term,translation,opts={}){
  const cleanTerm=String(term||'').trim(),cleanTr=String(translation||'').trim();let v=vocabularyMatch(subject,cleanTerm,opts.extra||'',cleanTr),created=false,translationAdded=false;
  if(!v){v=makeVocabulary(subject,cleanTerm,cleanTr,{extra:opts.extra||'',examples:opts.example?[opts.example]:[],mnemonic:opts.mnemonic||'',chunks:opts.chunks||[],verifiedAt:opts.verified?new Date().toISOString():null});state.vocabulary.push(v);created=true;}
  else{
    if(cleanTerm&&cleanTerm!==v.term&&!(v.termVariants||[]).includes(cleanTerm))v.termVariants=[...(v.termVariants||[]),cleanTerm];
    if(cleanTr&&lexicalKey(cleanTr,'english')!==lexicalKey(v.translation,'english')&&!(v.translations||[]).some(x=>lexicalKey(x,'english')===lexicalKey(cleanTr,'english'))){v.translations=[...(v.translations||[]),cleanTr];translationAdded=true;}
    if(opts.extra&&!v.extra)v.extra=opts.extra;if(opts.example&&!(v.examples||[]).includes(opts.example))v.examples=[...(v.examples||[]),opts.example];if(opts.mnemonic&&!v.mnemonic)v.mnemonic=opts.mnemonic;if(opts.chunks?.length&&!v.chunks?.length)v.chunks=[...opts.chunks];if(opts.verified&&!v.verifiedAt)v.verifiedAt=new Date().toISOString();v.updatedAt=new Date().toISOString();
  }
  addVocabularySource(v,opts.source||'manual',opts.setId||'');rebuildWordIndexes();return {vocab:v,created,translationAdded};
}
function attachVocabularyToSet(setId,data={}){
  const set=(state.sets||[]).find(s=>s.id===setId);if(!set)throw new Error('Lernset nicht gefunden');
  const up=upsertVocabulary(set.subject,data.term,data.translation,{...data,setId,verified:data.verified!==false});const v=up.vocab;const p=ensureLearnerVocabulary(set.learnerId,v.id);
  let link=(state.setVocabulary||[]).find(x=>x.setId===setId&&x.vocabId===v.id),alreadyLinked=!!link;
  if(!link){const pos=Math.max(0,...(state.setVocabulary||[]).filter(x=>x.setId===setId).map(x=>Number(x.position)||0))+1;link=makeSetVocabulary(setId,v.id,{position:pos,source:data.source||'manual'});state.setVocabulary.push(link);}
  const term=String(data.term||'').trim(),tr=String(data.translation||'').trim(),extra=String(data.extra||'').trim(),example=String(data.example||'').trim();
  link.termOverride=term&&term!==v.term?term:'';link.translationOverride=tr&&tr!==v.translation?tr:'';link.extraOverride=extra&&extra!==(v.extra||'')?extra:'';link.exampleOverride=example&&example!==((v.examples||[])[0]||'')?example:'';if(data.source)link.source=data.source;
  rebuildWordIndexes();return {word:wordViewForLink(link),vocab:v,progress:p,newVocabulary:up.created,translationAdded:up.translationAdded,alreadyLinked,newLink:!alreadyLinked};
}
function removeSetVocabularyLink(linkId){state.setVocabulary=(state.setVocabulary||[]).filter(x=>x.id!==linkId);rebuildWordIndexes();}
function removeSetWithLinks(setId){state.setVocabulary=(state.setVocabulary||[]).filter(x=>x.setId!==setId);state.sets=(state.sets||[]).filter(x=>x.id!==setId);(state.vocabulary||[]).forEach(v=>{v.sources=(v.sources||[]).filter(src=>src.setId!==setId)});rebuildWordIndexes();}
function deleteGlobalVocabulary(vocabId){state.setVocabulary=(state.setVocabulary||[]).filter(x=>x.vocabId!==vocabId);state.learnerVocabulary=(state.learnerVocabulary||[]).filter(x=>x.vocabId!==vocabId);state.vocabulary=(state.vocabulary||[]).filter(x=>x.id!==vocabId);rebuildWordIndexes();}
function remapProgressReferences(oldId,newId){
  if(!oldId||!newId||oldId===newId)return;
  (state.learners||[]).forEach(l=>{for(const plan of Object.values(l.dailyPlans||{})){if(Array.isArray(plan.wordIds))plan.wordIds=[...new Set(plan.wordIds.map(id=>id===oldId?newId:id))];if(Array.isArray(plan.wordRefs))plan.wordRefs=plan.wordRefs.map(r=>({...r,wordId:r.wordId===oldId?newId:r.wordId}));}});
  (state.practiceTests||[]).forEach(t=>{(t.answers||[]).forEach(a=>{if(a.wordId===oldId)a.wordId=newId});if(Array.isArray(t.wordIds))t.wordIds=[...new Set(t.wordIds.map(id=>id===oldId?newId:id))]});
  (state.activity||[]).forEach(a=>{if(a.wordId===oldId)a.wordId=newId});(state.learnerVocabulary||[]).forEach(p=>{p.confusionWith=(p.confusionWith||[]).map(id=>id===oldId?newId:id)});
}
function mergeVocabularyEntries(targetId,sourceId){
  if(!targetId||!sourceId||targetId===sourceId)return (state.vocabulary||[]).find(v=>v.id===targetId)||null;
  const target=(state.vocabulary||[]).find(v=>v.id===targetId),source=(state.vocabulary||[]).find(v=>v.id===sourceId);if(!target||!source||target.subject!==source.subject)return target||null;
  target.termVariants=[...new Set([...(target.termVariants||[]),source.term,...(source.termVariants||[])].filter(x=>x&&x!==target.term))];target.translations=[...new Set([...(target.translations||[]),source.translation,...(source.translations||[])].filter(x=>x&&x!==target.translation))];
  if(!target.extra&&source.extra)target.extra=source.extra;target.examples=[...new Set([...(target.examples||[]),...(source.examples||[])])].slice(0,12);if(!target.mnemonic&&source.mnemonic)target.mnemonic=source.mnemonic;if(!target.chunks?.length&&source.chunks?.length)target.chunks=[...source.chunks];target.sources=[...target.sources||[],...source.sources||[]].filter((x,i,a)=>a.findIndex(y=>y.kind===x.kind&&y.setId===x.setId)===i).slice(-60);target.verifiedAt=target.verifiedAt||source.verifiedAt;target.updatedAt=new Date().toISOString();
  const links=[...(state.setVocabulary||[])];for(const link of links.filter(x=>x.vocabId===sourceId)){const duplicate=(state.setVocabulary||[]).find(x=>x.id!==link.id&&x.setId===link.setId&&x.vocabId===targetId);if(duplicate)state.setVocabulary=state.setVocabulary.filter(x=>x.id!==link.id);else link.vocabId=targetId;}
  const sourceProgress=(state.learnerVocabulary||[]).filter(p=>p.vocabId===sourceId);for(const p of sourceProgress){const existing=(state.learnerVocabulary||[]).find(x=>x.vocabId===targetId&&x.learnerId===p.learnerId);if(existing){if(typeof mergeProgress==='function')mergeProgress(existing,p);remapProgressReferences(p.id,existing.id);state.learnerVocabulary=state.learnerVocabulary.filter(x=>x.id!==p.id);}else p.vocabId=targetId;}
  state.vocabulary=state.vocabulary.filter(v=>v.id!==sourceId);rebuildWordIndexes();return target;
}



let state = null;
let session = null;
let installPrompt = null;
let scanImportState = {imageUrl:null, rows:[], titleHint:'', nativeOcr:false, ocrBusy:false, lastFile:null};
let libraryRenderLimit = 200;
let toastTimer = null;
const $ = s => document.querySelector(s);
const $$ = s => [...document.querySelectorAll(s)];