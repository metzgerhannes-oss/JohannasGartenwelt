import fs from 'node:fs';
import vm from 'node:vm';

const context=vm.createContext({
  console,Date,Math,JSON,Set,Map,WeakMap,WeakSet,Number,String,Boolean,Array,Object,RegExp,Error,TypeError,Promise,URL,
  setTimeout:()=>0,clearTimeout:()=>{},confirm:()=>true,
  document:{querySelector:()=>null,querySelectorAll:()=>[]},
  window:{},navigator:{},localStorage:{getItem:()=>null,setItem:()=>{},removeItem:()=>{}}
});
for(const file of ['vokabeltrainer/js/core.js','vokabeltrainer/js/storage.js','vokabeltrainer/js/model.js','vokabeltrainer/js/learning.js']){
  vm.runInContext(fs.readFileSync(file,'utf8'),context,{filename:file});
}
const result=vm.runInContext(`
(()=>{
  const passed=[];const assert=(v,n)=>{if(!v)throw new Error('Subject smoke failed: '+n);passed.push(n)};
  assert(knownSubjectIds().join(',')==='english,latin,french','all subjects come from metadata');
  assert(availableSubjectIds().join(',')==='english,latin','French remains gated until OCR resource exists');
  assert(subjectFromExternal('FR')==='french'&&subjectFromExternal('Französisch')==='french','external subject aliases resolve');
  assert(subjectSpeechLang('french')==='fr-FR','French speech locale configured');
  assert(subjectOcrLang('french')==='fra','French OCR code configured');
  assert(subjectHasCapability('latin','latinGrammar')&&!subjectHasCapability('french','latinGrammar'),'capabilities are metadata driven');
  assert(Object.keys(defaultGradeScales()).includes('french')&&Object.keys(defaultTestSeries()).includes('french'),'per-subject state is generated');
  const v=makeVocabulary('french','bonjour','hallo');assert(v.subject==='french','French vocabulary is not collapsed to English');
  const b=makeBook('9780140449136','french',{title:'Test'});assert(b.subject==='french','French books are not collapsed to English');
  const raw=defaultState();raw.vocabulary=[v];raw.sets=[{id:'sf',learnerId:'learner_demo',subject:'french',title:'Unité 1',schoolYear:currentSchoolYear(),bookId:'',bookSection:'',testDate:'',testScopeMode:'set',testFrom:1,testTo:0,testFormat:'target'}];raw.activeSubject='english';const hardened=hardenState(raw);assert(hardened.vocabulary[0].subject==='french'&&hardened.sets[0].subject==='french','state hardening preserves configured inactive subjects');
  SUBJECT_META.french.available=true;state=defaultState();state.learners[0].activeSubjects=['french'];state.activeSubject='french';ensureActiveSubject();assert(state.activeSubject==='french','enabling metadata is sufficient for profile activation');
  assert(rankFor(100,'french')==='Armee','campaign metadata works without French branch');
  return passed;
})()
`,context,{filename:'subject-smoke'});

const sourceFiles=['vokabeltrainer/js/core.js','vokabeltrainer/js/storage.js','vokabeltrainer/js/model.js','vokabeltrainer/js/learning.js','vokabeltrainer/js/translation.js','vokabeltrainer/js/io.js','vokabeltrainer/js/ui.js'];
const all=sourceFiles.map(f=>fs.readFileSync(f,'utf8')).join('\n');
for(const forbidden of ["subject==='latin'?'latin':'english'","['english','latin'].includes(x.subject)","profileSubEnglish","profileSubLatin"]){
  if(all.includes(forbidden))throw new Error('Subject smoke failed: hardcoded subject pattern remains: '+forbidden);
}
if(!fs.readFileSync('vokabeltrainer/js/io.js','utf8').includes('subjectOcrLang(state.activeSubject)'))throw new Error('Subject smoke failed: OCR language is not metadata driven');
if(!fs.readFileSync('vokabeltrainer/js/ui.js','utf8').includes('data-profile-subject'))throw new Error('Subject smoke failed: profile subjects are not metadata driven');
if(!fs.readFileSync('vokabeltrainer/js/translation.js','utf8').includes("subjectHasCapability(state?.activeSubject,'hybridDictionary')"))throw new Error('Subject smoke failed: translation capability is not metadata driven');

console.log('Vokabeltrainer subject smoke: '+result.length+' runtime checks passed');
for(const name of result)console.log('✓ '+name);
