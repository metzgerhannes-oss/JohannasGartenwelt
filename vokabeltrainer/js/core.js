'use strict';

const VERSION = '0.9.13';
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
const SUBJECT_META = Object.freeze({
  english:{id:'english',label:'Englisch',short:'EN',available:true},
  latin:{id:'latin',label:'Latein',short:'LA',available:true},
  french:{id:'french',label:'Französisch',short:'FR',available:false}
});
const availableSubjectIds=()=>Object.values(SUBJECT_META).filter(x=>x.available).map(x=>x.id);
const subjectLabel=id=>SUBJECT_META[id]?.label||id;
const subjectShort=id=>SUBJECT_META[id]?.short||String(id||'').slice(0,2).toUpperCase();
function normalizeLearnerSubjects(l,hints=[]){
  const allowed=new Set(availableSubjectIds());
  const fromProfile=Array.isArray(l?.activeSubjects)?l.activeSubjects:[];
  const out=[...new Set([...fromProfile,...hints].filter(x=>allowed.has(x)))];
  return out.length?out:['english'];
}
function learnerActiveSubjects(l=state?.learners?.find(x=>x.id===state?.activeLearnerId)){return normalizeLearnerSubjects(l)}
function isSubjectActive(subject,l=state?.learners?.find(x=>x.id===state?.activeLearnerId)){return learnerActiveSubjects(l).includes(subject)}
function ensureActiveSubject(){const l=state?.learners?.find(x=>x.id===state?.activeLearnerId)||state?.learners?.[0];const active=learnerActiveSubjects(l);if(!active.includes(state?.activeSubject))state.activeSubject=active[0]||'english';return state?.activeSubject;}

const PROGRESS_FIELDS = new Set([
  'skills','level','repetitions','successes','independentSuccesses','assistedSuccesses','failures','intervalDays','dueDate',
  'lastReviewedAt','lastSuccessAt','lastActiveSuccessAt','activeSuccessDays','activePracticeDays','maxActiveGapDays','coldRecallDays',
  'coldRecallSuccesses','recentActiveResults','practiceDays','modesSeen','grammarSkills','grammarSuccessDays','errorProfile',
  'masteredAt','lastMasteredAt','confusionWith'
]);


function makeLearnerVocabulary(learnerId,vocabId,senseIdOrOpts='',opts={}){
  if(senseIdOrOpts&&typeof senseIdOrOpts==='object'){opts=senseIdOrOpts;senseIdOrOpts=opts.senseId||''}
  const senseId=String(senseIdOrOpts||opts.senseId||'');
  return {
    id:opts.id||uid('w'),learnerId,vocabId,senseId,
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
function makeVocabularySense(translation,opts={}){
  const now=new Date().toISOString(),primary=String(translation||'').trim(),seen=new Set([meaningKey(primary)]),translations=[];
  for(const value of (Array.isArray(opts.translations)?opts.translations:[])){const clean=String(value||'').trim(),key=meaningKey(clean);if(clean&&key&&!seen.has(key)){seen.add(key);translations.push(clean)}}
  return {id:opts.id||uid('sense'),translation:primary,translations,examples:Array.isArray(opts.examples)?[...new Set(opts.examples.map(x=>String(x||'').trim()).filter(Boolean))].slice(0,12):[],partOfSpeech:String(opts.partOfSpeech||'').trim(),createdAt:opts.createdAt||now,updatedAt:opts.updatedAt||now};
}
function primarySense(v){return Array.isArray(v?.senses)&&v.senses.length?v.senses[0]:null}
function senseById(v,senseId){return Array.isArray(v?.senses)?v.senses.find(s=>s.id===senseId)||null:null}
function senseTranslationKeys(s){return [s?.translation,...(s?.translations||[])].map(meaningKey).filter(Boolean)}
function senseMatch(v,translation){const key=meaningKey(translation);if(!v||!key)return null;return (v.senses||[]).find(s=>senseTranslationKeys(s).includes(key))||null}
function ensureVocabularySense(v,translation,opts={}){
  const clean=String(translation||'').trim();if(!v||!clean)return {sense:null,created:false};
  let sense=opts.senseId?senseById(v,String(opts.senseId)):null,created=false;if(!sense)sense=senseMatch(v,clean);
  if(!sense){sense=makeVocabularySense(clean,{translations:opts.translations||[],examples:opts.example?[opts.example]:(opts.examples||[]),partOfSpeech:opts.partOfSpeech||''});v.senses=v.senses||[];v.senses.push(sense);created=true;}
  else{
    const aliases=Array.isArray(opts.translations)?opts.translations:[];for(const a of aliases){const x=String(a||'').trim(),key=meaningKey(x);if(x&&key!==meaningKey(sense.translation)&&!senseTranslationKeys(sense).includes(key))sense.translations.push(x)}
    if(opts.example&&!(sense.examples||[]).includes(opts.example))sense.examples=[...(sense.examples||[]),opts.example].slice(0,12);if(opts.partOfSpeech&&!sense.partOfSpeech)sense.partOfSpeech=String(opts.partOfSpeech).trim();sense.updatedAt=new Date().toISOString();
  }
  return {sense,created};
}
function attachVocabularySenseApi(v){
  if(!v||typeof v!=='object')return v;v.senses=Array.isArray(v.senses)?v.senses:[];
  for(const key of ['translation','translations','examples']){try{delete v[key]}catch(_e){}}
  const define=(key,get,set)=>{try{Object.defineProperty(v,key,{configurable:true,enumerable:false,get,set})}catch(_e){}};
  define('translation',()=>primarySense(v)?.translation||'',value=>{let s=primarySense(v);if(!s){s=makeVocabularySense(value);v.senses.push(s)}else{s.translation=String(value||'').trim();s.updatedAt=new Date().toISOString()}});
  define('translations',()=>primarySense(v)?.translations||[],value=>{let s=primarySense(v);if(!s){s=makeVocabularySense('');v.senses.push(s)}s.translations=Array.isArray(value)?[...new Set(value.filter(Boolean))]:[];s.updatedAt=new Date().toISOString()});
  define('examples',()=>primarySense(v)?.examples||[],value=>{let s=primarySense(v);if(!s){s=makeVocabularySense('');v.senses.push(s)}s.examples=Array.isArray(value)?[...new Set(value.filter(Boolean))].slice(0,12):[];s.updatedAt=new Date().toISOString()});
  return v;
}
function makeVocabulary(subject,term,translation,opts={}){
  const now=new Date().toISOString(),senses=Array.isArray(opts.senses)&&opts.senses.length?opts.senses.map(s=>makeVocabularySense(s.translation,{...s,id:s.id||uid('sense')})):[makeVocabularySense(translation,{translations:opts.translations||[],examples:opts.examples||[]})];
  const v={id:opts.id||uid('v'),subject:subject==='latin'?'latin':'english',term:String(term||'').trim(),termVariants:Array.isArray(opts.termVariants)?[...new Set(opts.termVariants.filter(Boolean))]:[],extra:opts.extra||'',mnemonic:opts.mnemonic||'',chunks:Array.isArray(opts.chunks)?opts.chunks.filter(Boolean):[],sources:Array.isArray(opts.sources)?opts.sources:[],verifiedAt:opts.verifiedAt||null,createdAt:opts.createdAt||now,updatedAt:opts.updatedAt||now,senses};
  return attachVocabularySenseApi(v);
}
function makeSetVocabulary(setId,vocabId,senseIdOrOpts='',opts={}){
  if(senseIdOrOpts&&typeof senseIdOrOpts==='object'){opts=senseIdOrOpts;senseIdOrOpts=opts.senseId||''}
  return {id:opts.id||uid('sv'),setId,vocabId,senseId:String(senseIdOrOpts||opts.senseId||''),position:Number(opts.position)||0,termOverride:opts.termOverride||'',translationOverride:opts.translationOverride||'',acceptedTermOverrides:Array.isArray(opts.acceptedTermOverrides)?opts.acceptedTermOverrides.filter(Boolean):[],acceptedTranslationOverrides:Array.isArray(opts.acceptedTranslationOverrides)?opts.acceptedTranslationOverrides.filter(Boolean):[],extraOverride:opts.extraOverride||'',exampleOverride:opts.exampleOverride||'',source:opts.source||'',createdAt:opts.createdAt||new Date().toISOString()};
}

function isbn13Checksum(digits12){let sum=0;for(let i=0;i<12;i++)sum+=Number(digits12[i])*(i%2?3:1);return String((10-(sum%10))%10)}
function normalizeIsbn(value){
  const raw=String(value||'').toUpperCase().replace(/ISBN(?:-1[03])?:?/g,'').replace(/[^0-9X]/g,'');
  if(raw.length===13&&/^97[89]\d{10}$/.test(raw)&&isbn13Checksum(raw.slice(0,12))===raw[12])return raw;
  if(raw.length===10&&/^\d{9}[\dX]$/.test(raw)){
    let sum=0;for(let i=0;i<10;i++)sum+=(10-i)*(raw[i]==='X'?10:Number(raw[i]));if(sum%11!==0)return '';
    const first='978'+raw.slice(0,9);return first+isbn13Checksum(first);
  }
  return '';
}
function formatIsbn(isbn){return normalizeIsbn(isbn)||String(isbn||'').replace(/[^0-9Xx]/g,'')}
function makeBook(isbn13,subject,opts={}){const now=new Date().toISOString();return {id:opts.id||uid('book'),isbn13:normalizeIsbn(isbn13),subject:SUBJECT_META[subject]?.available?subject:'english',title:String(opts.title||'').trim(),publisher:String(opts.publisher||'').trim(),edition:String(opts.edition||'').trim(),createdAt:opts.createdAt||now,updatedAt:opts.updatedAt||now}}
function bookById(id){return (state?.books||[]).find(x=>x.id===id)||null}
function bookByIsbn(isbn){const normalized=normalizeIsbn(isbn);return normalized?(state?.books||[]).find(x=>x.isbn13===normalized)||null:null}
function upsertBook(isbn,subject,opts={}){const isbn13=normalizeIsbn(isbn);if(!isbn13)throw new Error('Ungültige ISBN');let b=bookByIsbn(isbn13),created=false;if(!b){b=makeBook(isbn13,subject,opts);state.books.push(b);created=true}else{if(subject&&b.subject!==subject&&!bookUsage(b.id).vocabulary)b.subject=subject;if(opts.title)b.title=String(opts.title).trim();if(opts.publisher)b.publisher=String(opts.publisher).trim();if(opts.edition)b.edition=String(opts.edition).trim();b.updatedAt=new Date().toISOString()}return {book:b,created}}
function activeBookAssignment(learnerId=state?.activeLearnerId,subject=state?.activeSubject){return (state?.learnerBooks||[]).find(x=>x.learnerId===learnerId&&x.subject===subject&&x.active)||null}
function currentBook(learnerId=state?.activeLearnerId,subject=state?.activeSubject){const a=activeBookAssignment(learnerId,subject);return a?bookById(a.bookId):null}
function assignBookToLearner(learnerId,subject,bookId,opts={}){if(!bookById(bookId))throw new Error('Lehrwerk nicht gefunden');(state.learnerBooks||[]).forEach(x=>{if(x.learnerId===learnerId&&x.subject===subject)x.active=false});let a=(state.learnerBooks||[]).find(x=>x.learnerId===learnerId&&x.subject===subject&&x.bookId===bookId&&x.schoolYear===(opts.schoolYear||currentSchoolYear()));if(!a){a={id:uid('lb'),learnerId,subject,bookId,gradeLevel:String(opts.gradeLevel||''),schoolYear:opts.schoolYear||currentSchoolYear(),active:true,createdAt:new Date().toISOString()};state.learnerBooks.push(a)}else{a.active=true;a.gradeLevel=String(opts.gradeLevel||a.gradeLevel||'')}return a}
function unassignBook(learnerId,subject){(state.learnerBooks||[]).forEach(x=>{if(x.learnerId===learnerId&&x.subject===subject)x.active=false})}
function bookUsage(bookId){const rows=(state?.bookVocabulary||[]).filter(x=>x.bookId===bookId);return {sections:new Set(rows.map(x=>x.section||'Lernset')).size,vocabulary:new Set(rows.map(x=>x.vocabId)).size,rows:rows.length}}
function ensureBookVocabulary(bookId,vocabId,opts={}){
  if(!bookId||!vocabId)return null;const v=(state.vocabulary||[]).find(x=>x.id===vocabId);if(!v)return null;const sense=senseById(v,opts.senseId)||senseMatch(v,opts.translationOverride)||primarySense(v);if(!sense)return null;
  const section=String(opts.section||'Lernset').trim()||'Lernset';let row=(state.bookVocabulary||[]).find(x=>x.bookId===bookId&&x.senseId===sense.id&&x.section===section);
  if(!row){row={id:uid('bv'),bookId,vocabId,senseId:sense.id,section,position:Number(opts.position)||0,termOverride:opts.termOverride||'',translationOverride:opts.translationOverride||'',acceptedTermOverrides:Array.isArray(opts.acceptedTermOverrides)?opts.acceptedTermOverrides.filter(Boolean):[],acceptedTranslationOverrides:Array.isArray(opts.acceptedTranslationOverrides)?opts.acceptedTranslationOverrides.filter(Boolean):[],extraOverride:opts.extraOverride||'',exampleOverride:opts.exampleOverride||'',createdAt:new Date().toISOString()};state.bookVocabulary.push(row)}
  else{if(opts.position)row.position=Number(opts.position)||row.position;if(opts.termOverride)row.termOverride=opts.termOverride;if(opts.translationOverride)row.translationOverride=opts.translationOverride;if(opts.acceptedTermOverrides)row.acceptedTermOverrides=[...opts.acceptedTermOverrides];if(opts.acceptedTranslationOverrides)row.acceptedTranslationOverrides=[...opts.acceptedTranslationOverrides];if(opts.extraOverride)row.extraOverride=opts.extraOverride;if(opts.exampleOverride)row.exampleOverride=opts.exampleOverride}
  return row;
}
function knownBookSections(bookId){const rows=(state?.bookVocabulary||[]).filter(x=>x.bookId===bookId);const m=new Map();for(const r of rows){const key=r.section||'Lernset';if(!m.has(key))m.set(key,[]);m.get(key).push(r)}return [...m.entries()].map(([section,items])=>({section,items:items.sort((a,b)=>(a.position||0)-(b.position||0))})).sort((a,b)=>a.section.localeCompare(b.section,'de'))}
function associateExistingSetsToBook(learnerId,subject,bookId){const book=bookById(bookId);if(!book||book.subject!==subject)return {sets:0,links:0};let sets=0,links=0;for(const set of (state.sets||[]).filter(s=>s.learnerId===learnerId&&s.subject===subject&&!s.bookId)){set.bookId=bookId;set.bookSection=set.bookSection||set.title;sets++;for(const link of (state.setVocabulary||[]).filter(x=>x.setId===set.id)){ensureBookVocabulary(bookId,link.vocabId,{senseId:link.senseId,section:set.bookSection||set.title,position:link.position,termOverride:link.termOverride,translationOverride:link.translationOverride,acceptedTermOverrides:link.acceptedTermOverrides,acceptedTranslationOverrides:link.acceptedTranslationOverrides,extraOverride:link.extraOverride,exampleOverride:link.exampleOverride});links++}}return {sets,links}}
function cloneKnownBookToLearner(bookId,learnerId){const book=bookById(bookId),l=(state.learners||[]).find(x=>x.id===learnerId);if(!book||!l)return {sets:0,links:0};let sets=0,links=0;for(const group of knownBookSections(bookId)){let set=(state.sets||[]).find(s=>s.learnerId===learnerId&&s.bookId===bookId&&s.bookSection===group.section);if(!set){set={id:uid('set'),learnerId,subject:book.subject,title:group.section,schoolYear:currentSchoolYear(),bookId,bookSection:group.section,testDate:'',testScopeMode:'set',testFrom:1,testTo:0,testFormat:'target',from:'',to:''};state.sets.push(set);sets++}for(const r of group.items){const v=(state.vocabulary||[]).find(x=>x.id===r.vocabId),sense=v&&(senseById(v,r.senseId)||primarySense(v));if(!v||!sense)continue;if(!(state.setVocabulary||[]).some(x=>x.setId===set.id&&x.senseId===sense.id)){state.setVocabulary.push(makeSetVocabulary(set.id,v.id,sense.id,{position:r.position,termOverride:r.termOverride,translationOverride:r.translationOverride,acceptedTermOverrides:r.acceptedTermOverrides,acceptedTranslationOverrides:r.acceptedTranslationOverrides,extraOverride:r.extraOverride,exampleOverride:r.exampleOverride,source:'book-library'}));ensureLearnerVocabulary(learnerId,v.id,sense.id);links++}}}rebuildWordIndexes();return {sets,links}}

function defaultState(){
  const s={
    version: VERSION,senseModelVersion:1,
    activeLearnerId: 'learner_demo',activeSubject: 'english',
    learners:[{id:'learner_demo',name:'Mein Profil',gradeLevel:'',activeSubjects:['english'],xp:0,lrsMode:false,fontSize:17,letterSpacing:0,flashSpeed:1600,streakDays:[],milestones:{},fortressWins:{english:[],latin:[]},fortressWinsByYear:{},campaignLog:[],dailyPlans:{},testSeries:{english:null,latin:null},gradeScales:defaultGradeScales(),createdAt:new Date().toISOString()}],
    books:[],learnerBooks:[],bookVocabulary:[],sets:[],vocabulary:[],setVocabulary:[],learnerVocabulary:[],grades:[],practiceTests:[],activity:[]
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
function meaningKey(value){return String(value||'').normalize('NFKC').toLowerCase().replace(/[’‘`´]/g,"'").trim().replace(/[.,;:!?()[\]{}"']/g,'').replace(/\s+/g,' ').trim()}
function vocabularyMatch(subject,term,extra='',translation=''){
  if(!state)return null;const key=lexicalKey(term,subject);if(!key)return null;
  const candidates=(state.vocabulary||[]).filter(v=>v.subject===subject&&lexicalKey(v.term,subject)===key);if(!candidates.length)return null;if(candidates.length===1)return candidates[0];
  const ex=lexicalKey(extra,subject);if(subject==='latin'&&ex){const exact=candidates.find(v=>lexicalKey(v.extra,subject)===ex);if(exact)return exact;}
  return candidates[0];
}
function vocabularySenseMatch(subject,term,extra='',translation=''){const vocab=vocabularyMatch(subject,term,extra);return vocab?{vocab,sense:senseMatch(vocab,translation)}:{vocab:null,sense:null};}
function vocabularyUsage(vocabId,senseId=''){
  const links=(state?.setVocabulary||[]).filter(x=>x.vocabId===vocabId&&(!senseId||x.senseId===senseId));const setIds=new Set(links.map(x=>x.setId));const learnerIds=new Set((state?.sets||[]).filter(s=>setIds.has(s.id)).map(s=>s.learnerId));
  return {links:links.length,sets:setIds.size,learners:learnerIds.size,setIds:[...setIds],learnerIds:[...learnerIds]};
}
function progressForVocabulary(vocabId,learnerId=state?.activeLearnerId){const arr=(state?.learnerVocabulary||[]).filter(x=>x.vocabId===vocabId&&x.learnerId===learnerId);return arr.length===1?arr[0]:null}
function progressesForVocabulary(vocabId,learnerId=state?.activeLearnerId){return (state?.learnerVocabulary||[]).filter(x=>x.vocabId===vocabId&&x.learnerId===learnerId)}
function progressForSense(senseId,learnerId=state?.activeLearnerId){return (state?.learnerVocabulary||[]).find(x=>x.senseId===senseId&&x.learnerId===learnerId)||null}
function ensureLearnerVocabulary(learnerId,vocabId,senseIdOrOpts='',opts={}){
  if(senseIdOrOpts&&typeof senseIdOrOpts==='object'){opts=senseIdOrOpts;senseIdOrOpts=opts.senseId||''}
  const v=(state.vocabulary||[]).find(x=>x.id===vocabId),sense=senseById(v,String(senseIdOrOpts||''))||primarySense(v);if(!v||!sense)return null;
  let p=(state.learnerVocabulary||[]).find(x=>x.learnerId===learnerId&&x.senseId===sense.id);if(p)return p;
  p=makeLearnerVocabulary(learnerId,vocabId,sense.id,opts);state.learnerVocabulary.push(p);rebuildWordIndexes();return p;
}
function rebuildWordIndexes(s=state){
  if(!s)return null;const idx={vocab:new Map(),sense:new Map(),progress:new Map(),progressByCombo:new Map(),links:new Map(),sets:new Map(),learners:new Map()};
  (s.vocabulary||[]).forEach(x=>{attachVocabularySenseApi(x);idx.vocab.set(x.id,x);(x.senses||[]).forEach(se=>idx.sense.set(se.id,{sense:se,vocab:x}))});
  (s.learnerVocabulary||[]).forEach(x=>{idx.progress.set(x.id,x);idx.progressByCombo.set(`${x.learnerId}\u0000${x.senseId}`,x)});(s.setVocabulary||[]).forEach(x=>idx.links.set(x.id,x));(s.sets||[]).forEach(x=>idx.sets.set(x.id,x));(s.learners||[]).forEach(x=>idx.learners.set(x.id,x));
  Object.defineProperty(s,'_wordIndexes',{value:idx,writable:true,configurable:true,enumerable:false});return idx;
}
function wordViewForLink(link,s=state){
  if(!link||!s)return null;const idx=s._wordIndexes||rebuildWordIndexes(s),v=idx.vocab.get(link.vocabId),set=idx.sets.get(link.setId);if(!v||!set)return null;const sense=senseById(v,link.senseId)||primarySense(v);if(!sense)return null;
  const p=idx.progressByCombo.get(`${set.learnerId}\u0000${sense.id}`);if(!p)return null;
  const getValue=prop=>{
    if(prop==='id')return p.id;if(prop==='setId')return link.setId;if(prop==='setLinkId')return link.id;if(prop==='vocabId')return v.id;if(prop==='senseId')return sense.id;if(prop==='learnerId')return p.learnerId;if(prop==='subject')return v.subject;
    if(prop==='term')return link.termOverride||v.term;if(prop==='translation')return link.translationOverride||sense.translation;if(prop==='extra')return link.extraOverride||v.extra||'';if(prop==='example')return link.exampleOverride||(sense.examples||[])[0]||'';
    if(prop==='mnemonic')return v.mnemonic||'';if(prop==='chunks')return v.chunks||[];if(prop==='termVariants')return v.termVariants||[];if(prop==='translations')return sense.translations||[];
    if(prop==='acceptedTerms')return [...new Set([link.termOverride||v.term,...(v.termVariants||[]),...(link.acceptedTermOverrides||[])].filter(Boolean))];
    if(prop==='acceptedTranslations')return [...new Set([link.translationOverride||sense.translation,...(sense.translations||[]),...(link.acceptedTranslationOverrides||[])].filter(Boolean))];
    if(prop==='source')return link.source||'';
    if(prop==='toJSON')return ()=>{const o={};for(const k of ['id','setId','setLinkId','vocabId','senseId','learnerId','subject','term','translation','extra','example','mnemonic','chunks','acceptedTerms','acceptedTranslations'])o[k]=getValue(k);Object.assign(o,p);return o;};
    if(prop in p)return p[prop];if(prop in link)return link[prop];if(prop in sense)return sense[prop];if(prop in v)return v[prop];return undefined;
  };
  return new Proxy({}, {get:(_t,prop)=>getValue(prop),set:(_t,prop,value)=>{
    if(PROGRESS_FIELDS.has(prop)||prop in p){p[prop]=value;return true;}
    if(prop==='term'){link.termOverride=String(value||'');return true;}if(prop==='translation'){link.translationOverride=String(value||'');return true;}if(prop==='extra'){link.extraOverride=String(value||'');return true;}if(prop==='example'){link.exampleOverride=String(value||'');return true;}
    if(prop==='mnemonic'){v.mnemonic=String(value||'');return true;}if(prop==='chunks'){v.chunks=Array.isArray(value)?value:[];return true;}return false;
  },ownKeys:()=>[...new Set(['id','setId','setLinkId','vocabId','senseId','learnerId','subject','term','translation','extra','example','mnemonic','chunks','acceptedTerms','acceptedTranslations',...Object.keys(p),...Object.keys(link),...Object.keys(sense),...Object.keys(v)])],getOwnPropertyDescriptor:()=>({enumerable:true,configurable:true})});
}
function attachRuntimeWordApi(s){
  rebuildWordIndexes(s);
  try{Object.defineProperty(s,'words',{configurable:true,enumerable:false,get(){return (s.setVocabulary||[]).map(link=>wordViewForLink(link,s)).filter(Boolean)}});}catch(_e){}
  return s;
}
function wordByLinkId(linkId){const link=(state?.setVocabulary||[]).find(x=>x.id===linkId);return link?wordViewForLink(link):null;}
function wordById(progressId,preferredSetId=''){
  const p=(state?.learnerVocabulary||[]).find(x=>x.id===progressId);if(!p)return null;const setsByLearner=new Set((state.sets||[]).filter(s=>s.learnerId===p.learnerId).map(s=>s.id));
  let link=(state.setVocabulary||[]).find(x=>x.senseId===p.senseId&&x.setId===preferredSetId&&setsByLearner.has(x.setId));if(!link)link=(state.setVocabulary||[]).find(x=>x.senseId===p.senseId&&setsByLearner.has(x.setId));return link?wordViewForLink(link):null;
}
function globalVocabulary(subject=state?.activeSubject){return (state?.vocabulary||[]).filter(v=>v.subject===subject).map(attachVocabularySenseApi)}
function addVocabularySource(v,source,setId=''){
  if(!v)return;v.sources=Array.isArray(v.sources)?v.sources:[];const set=(state?.sets||[]).find(x=>x.id===setId),item={kind:source||'manual',setId:setId||'',bookId:set?.bookId||'',at:new Date().toISOString()};if(!v.sources.some(x=>x.kind===item.kind&&x.setId===item.setId&&x.bookId===item.bookId))v.sources.push(item);v.updatedAt=new Date().toISOString();
}
function upsertVocabulary(subject,term,translation,opts={}){
  const cleanTerm=String(term||'').trim(),cleanTr=String(translation||'').trim();let v=vocabularyMatch(subject,cleanTerm,opts.extra||''),created=false;
  if(!v){v=makeVocabulary(subject,cleanTerm,cleanTr,{extra:opts.extra||'',mnemonic:opts.mnemonic||'',chunks:opts.chunks||[],verifiedAt:opts.verified?new Date().toISOString():null});state.vocabulary.push(v);created=true;}
  else{attachVocabularySenseApi(v);if(cleanTerm&&cleanTerm!==v.term&&!(v.termVariants||[]).includes(cleanTerm))v.termVariants=[...(v.termVariants||[]),cleanTerm];if(opts.extra&&!v.extra)v.extra=opts.extra;if(opts.mnemonic&&!v.mnemonic)v.mnemonic=opts.mnemonic;if(opts.chunks?.length&&!v.chunks?.length)v.chunks=[...opts.chunks];if(opts.verified&&!v.verifiedAt)v.verifiedAt=new Date().toISOString();v.updatedAt=new Date().toISOString();}
  const aliases=Array.isArray(opts.senseAliases)?opts.senseAliases:(Array.isArray(opts.translations)?opts.translations:(!opts.senseId&&Array.isArray(opts.acceptedTranslations)?opts.acceptedTranslations:[]));
  const ensured=ensureVocabularySense(v,cleanTr,{senseId:opts.senseId||'',translations:aliases,example:opts.example||'',partOfSpeech:opts.partOfSpeech||''});const sense=ensured.sense;
  addVocabularySource(v,opts.source||'manual',opts.setId||'');rebuildWordIndexes();return {vocab:v,sense,created,senseCreated:ensured.created,translationAdded:ensured.created};
}
function attachVocabularyToSet(setId,data={}){
  const set=(state.sets||[]).find(s=>s.id===setId);if(!set)throw new Error('Lernset nicht gefunden');
  const canonicalTranslation=String(data.senseTranslation||data.translation||'').trim();
  const up=upsertVocabulary(set.subject,data.term,canonicalTranslation,{...data,setId,verified:data.verified!==false});const v=up.vocab,sense=up.sense;if(!sense)throw new Error('Bedeutung fehlt');const p=ensureLearnerVocabulary(set.learnerId,v.id,sense.id);
  let link=(state.setVocabulary||[]).find(x=>x.setId===setId&&x.senseId===sense.id),alreadyLinked=!!link;
  if(!link){const pos=Math.max(0,...(state.setVocabulary||[]).filter(x=>x.setId===setId).map(x=>Number(x.position)||0))+1;link=makeSetVocabulary(setId,v.id,sense.id,{position:pos,source:data.source||'manual'});state.setVocabulary.push(link);}
  const term=String(data.term||'').trim(),tr=String(data.translation||canonicalTranslation).trim(),extra=String(data.extra||'').trim(),example=String(data.example||'').trim();
  link.termOverride=term&&term!==v.term?term:'';link.translationOverride=tr&&tr!==sense.translation?tr:'';link.acceptedTermOverrides=Array.isArray(data.acceptedTerms)?[...new Set(data.acceptedTerms.filter(Boolean))]:link.acceptedTermOverrides||[];link.acceptedTranslationOverrides=Array.isArray(data.acceptedTranslations)?[...new Set(data.acceptedTranslations.filter(Boolean))]:link.acceptedTranslationOverrides||[];link.extraOverride=extra&&extra!==(v.extra||'')?extra:'';link.exampleOverride=example&&example!==((sense.examples||[])[0]||'')?example:'';if(data.source)link.source=data.source;
  if(set.bookId)ensureBookVocabulary(set.bookId,v.id,{senseId:sense.id,section:set.bookSection||set.title,position:link.position,termOverride:link.termOverride,translationOverride:link.translationOverride,acceptedTermOverrides:link.acceptedTermOverrides,acceptedTranslationOverrides:link.acceptedTranslationOverrides,extraOverride:link.extraOverride,exampleOverride:link.exampleOverride});
  rebuildWordIndexes();return {word:wordViewForLink(link),vocab:v,sense,progress:p,newVocabulary:up.created,newSense:up.senseCreated,translationAdded:up.senseCreated,alreadyLinked,newLink:!alreadyLinked};
}
function removeSetVocabularyLink(linkId){state.setVocabulary=(state.setVocabulary||[]).filter(x=>x.id!==linkId);rebuildWordIndexes();}
function removeSetWithLinks(setId){state.setVocabulary=(state.setVocabulary||[]).filter(x=>x.setId!==setId);state.sets=(state.sets||[]).filter(x=>x.id!==setId);(state.vocabulary||[]).forEach(v=>{v.sources=(v.sources||[]).filter(src=>src.setId!==setId)});rebuildWordIndexes();}
function deleteGlobalVocabulary(vocabId){state.setVocabulary=(state.setVocabulary||[]).filter(x=>x.vocabId!==vocabId);state.bookVocabulary=(state.bookVocabulary||[]).filter(x=>x.vocabId!==vocabId);state.learnerVocabulary=(state.learnerVocabulary||[]).filter(x=>x.vocabId!==vocabId);state.vocabulary=(state.vocabulary||[]).filter(x=>x.id!==vocabId);rebuildWordIndexes()}
function remapProgressReferences(oldId,newId){
  if(!oldId||!newId||oldId===newId)return;
  (state.learners||[]).forEach(l=>{for(const plan of Object.values(l.dailyPlans||{})){if(Array.isArray(plan.wordIds))plan.wordIds=[...new Set(plan.wordIds.map(id=>id===oldId?newId:id))];if(Array.isArray(plan.wordRefs))plan.wordRefs=plan.wordRefs.map(r=>({...r,wordId:r.wordId===oldId?newId:r.wordId}));}});
  (state.practiceTests||[]).forEach(t=>{(t.answers||[]).forEach(a=>{if(a.wordId===oldId)a.wordId=newId});if(Array.isArray(t.wordIds))t.wordIds=[...new Set(t.wordIds.map(id=>id===oldId?newId:id))]});
  (state.activity||[]).forEach(a=>{if(a.wordId===oldId)a.wordId=newId});(state.learnerVocabulary||[]).forEach(p=>{p.confusionWith=(p.confusionWith||[]).map(id=>id===oldId?newId:id)});
}
function mergeVocabularyEntries(targetId,sourceId){
  if(!targetId||!sourceId||targetId===sourceId)return (state.vocabulary||[]).find(v=>v.id===targetId)||null;
  const target=(state.vocabulary||[]).find(v=>v.id===targetId),source=(state.vocabulary||[]).find(v=>v.id===sourceId);if(!target||!source||target.subject!==source.subject)return target||null;attachVocabularySenseApi(target);attachVocabularySenseApi(source);
  target.termVariants=[...new Set([...(target.termVariants||[]),source.term,...(source.termVariants||[])].filter(x=>x&&x!==target.term))];if(!target.extra&&source.extra)target.extra=source.extra;if(!target.mnemonic&&source.mnemonic)target.mnemonic=source.mnemonic;if(!target.chunks?.length&&source.chunks?.length)target.chunks=[...source.chunks];target.sources=[...target.sources||[],...source.sources||[]].filter((x,i,a)=>a.findIndex(y=>y.kind===x.kind&&y.setId===x.setId)===i).slice(-60);target.verifiedAt=target.verifiedAt||source.verifiedAt;target.updatedAt=new Date().toISOString();
  const senseMap=new Map();for(const ss of (source.senses||[])){let ts=senseMatch(target,ss.translation);if(!ts){ts=makeVocabularySense(ss.translation,{translations:ss.translations||[],examples:ss.examples||[],partOfSpeech:ss.partOfSpeech||'',createdAt:ss.createdAt,updatedAt:ss.updatedAt});target.senses.push(ts)}else{ts.translations=[...new Set([...(ts.translations||[]),...(ss.translations||[])])].filter(x=>meaningKey(x)!==meaningKey(ts.translation));ts.examples=[...new Set([...(ts.examples||[]),...(ss.examples||[])])].slice(0,12);if(!ts.partOfSpeech&&ss.partOfSpeech)ts.partOfSpeech=ss.partOfSpeech}senseMap.set(ss.id,ts.id)}
  for(const link of [...(state.setVocabulary||[])].filter(x=>x.vocabId===sourceId)){const mappedSense=senseMap.get(link.senseId)||primarySense(target)?.id||'';const duplicate=(state.setVocabulary||[]).find(x=>x.id!==link.id&&x.setId===link.setId&&x.senseId===mappedSense);if(duplicate)state.setVocabulary=state.setVocabulary.filter(x=>x.id!==link.id);else{link.vocabId=targetId;link.senseId=mappedSense}}
  for(const row of [...(state.bookVocabulary||[])].filter(x=>x.vocabId===sourceId)){const mappedSense=senseMap.get(row.senseId)||primarySense(target)?.id||'';const duplicate=(state.bookVocabulary||[]).find(x=>x.id!==row.id&&x.bookId===row.bookId&&x.section===row.section&&x.senseId===mappedSense);if(duplicate)state.bookVocabulary=state.bookVocabulary.filter(x=>x.id!==row.id);else{row.vocabId=targetId;row.senseId=mappedSense}}
  const sourceProgress=(state.learnerVocabulary||[]).filter(p=>p.vocabId===sourceId);for(const p of sourceProgress){const mappedSense=senseMap.get(p.senseId)||primarySense(target)?.id||'';const existing=(state.learnerVocabulary||[]).find(x=>x.senseId===mappedSense&&x.learnerId===p.learnerId);if(existing){if(typeof mergeProgress==='function')mergeProgress(existing,p);remapProgressReferences(p.id,existing.id);state.learnerVocabulary=state.learnerVocabulary.filter(x=>x.id!==p.id)}else{p.vocabId=targetId;p.senseId=mappedSense}}
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