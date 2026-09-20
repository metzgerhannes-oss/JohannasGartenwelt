'use strict';

const VERSION = '0.9.5';
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
const defaultState = () => ({
  version: VERSION,
  activeLearnerId: 'learner_demo',
  activeSubject: 'english',
  learners: [{
    id:'learner_demo', name:'Mein Profil', xp:0, lrsMode:false, fontSize:17, letterSpacing:0,
    flashSpeed:1600, streakDays:[], milestones:{}, fortressWins:{english:[],latin:[]}, fortressWinsByYear:{},
    campaignLog:[], dailyPlans:{}, testSeries:{english:null,latin:null}, gradeScales:defaultGradeScales(), createdAt:new Date().toISOString()
  }],
  sets:[],
  words:[],
  grades:[], practiceTests:[], activity:[]
});

function makeWord(setId, term, translation, opts={}) {
  return {
    id:uid('w'), setId, term, translation, extra:opts.extra||'', example:opts.example||'', mnemonic:opts.mnemonic||'', image:opts.image||'',
    chunks:opts.chunks||[], confusionWith:[], skills:defaultSkills(), level:0, repetitions:0, successes:0, independentSuccesses:0, assistedSuccesses:0, failures:0,
    intervalDays:0, dueDate:today(), lastReviewedAt:null, lastSuccessAt:null, lastActiveSuccessAt:null, activeSuccessDays:[], activePracticeDays:[], maxActiveGapDays:0, coldRecallDays:[], coldRecallSuccesses:0, recentActiveResults:[], practiceDays:[], modesSeen:[], grammarSkills:{genitive:0,gender:0,principalParts:0,form:0}, grammarSuccessDays:[], errorProfile:{meaning:0,retrieval:0,spelling:0,listening:0,context:0,grammar:0}, masteredAt:null, lastMasteredAt:null
  };
}


let state = null;
let session = null;
let installPrompt = null;
let scanImportState = {imageUrl:null, rows:[], titleHint:'', nativeOcr:false, ocrBusy:false, lastFile:null};
let libraryRenderLimit = 200;
let toastTimer = null;
const $ = s => document.querySelector(s);
const $$ = s => [...document.querySelectorAll(s)];