'use strict';

function learner(){ return state.learners.find(x=>x.id===state.activeLearnerId)||state.learners[0]; }
function gradeScaleFor(subject=state.activeSubject){const l=learner();l.gradeScales=l.gradeScales||defaultGradeScales();l.gradeScales[subject]={...defaultGradeScale(),...(l.gradeScales[subject]||{})};return l.gradeScales[subject];}
function suggestGradeFromScale(percent,scale){const s={...defaultGradeScale(),...(scale||{})};const p=Number(percent)||0;if(p>=s.n1)return '1';if(p>=s.n2)return '2';if(p>=s.n3)return '3';if(p>=s.n4)return '4';if(p>=s.n5)return '5';return '6';}
function gradeScaleText(scale=gradeScaleFor()){return `1 ab ${scale.n1}% · 2 ab ${scale.n2}% · 3 ab ${scale.n3}% · 4 ab ${scale.n4}% · 5 ab ${scale.n5}% · darunter 6`;}
function actualGradeForPractice(practiceId){return state.grades.find(g=>g.learnerId===state.activeLearnerId&&g.practiceTestId===practiceId)||null;}
function mySets(subject=state.activeSubject){ return state.sets.filter(s=>s.learnerId===state.activeLearnerId && s.subject===subject); }
function schoolYearSets(subject=state.activeSubject,schoolYear=currentSchoolYear()){ return mySets(subject).filter(s=>s.schoolYear===schoolYear); }
function myWords(subject=state.activeSubject){ const ids=new Set(mySets(subject).map(s=>s.id)); return state.words.filter(w=>ids.has(w.setId)); }
function schoolYearWords(subject=state.activeSubject,schoolYear=currentSchoolYear()){ const ids=new Set(schoolYearSets(subject,schoolYear).map(s=>s.id)); return state.words.filter(w=>ids.has(w.setId)); }
function setWords(setId){ return state.words.filter(w=>w.setId===setId); }
function fortressWins(subject=state.activeSubject,schoolYear=currentSchoolYear()){const l=learner(),key=`${subject}:${schoolYear}`;l.fortressWinsByYear=l.fortressWinsByYear||{};return l.fortressWinsByYear[key]||(l.fortressWinsByYear[key]=[]);}

function normalize(s){return String(s||'').trim().toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/[.,;:!?()[\]{}"']/g,'').replace(/\s+/g,' ')}
function answerMatches(answer, target){
  const a=normalize(answer), t=normalize(target); if(a===t) return true;
  return t.split(/\s*[/;,]\s*/).some(part=>a===normalize(part));
}
function levenshtein(a,b){a=normalize(a);b=normalize(b);const dp=Array.from({length:a.length+1},(_,i)=>[i]);for(let j=1;j<=b.length;j++)dp[0][j]=j;for(let i=1;i<=a.length;i++)for(let j=1;j<=b.length;j++)dp[i][j]=Math.min(dp[i-1][j]+1,dp[i][j-1]+1,dp[i-1][j-1]+(a[i-1]===b[j-1]?0:1));return dp[a.length][b.length]}
function detectConfusions(word, pool){
  const scored=pool.filter(x=>x.id!==word.id).map(x=>({w:x,d:levenshtein(word.term,x.term)})).filter(x=>x.d<=Math.max(2,Math.floor(word.term.length*.34))).sort((a,b)=>a.d-b.d).slice(0,2);
  return scored.map(x=>x.w);
}
function autoChunks(term){
  const t=String(term||'').trim(); if(t.length<7) return [t];
  const common=['tion','ing','ment','ness','ful','less','able','ous','pre','re','un','dis','con','sub','pro','per'];
  let out=[],rest=t;
  const pre=common.find(x=>rest.toLowerCase().startsWith(x)&&rest.length>x.length+3); if(pre){out.push(rest.slice(0,pre.length));rest=rest.slice(pre.length)}
  const suf=common.find(x=>rest.toLowerCase().endsWith(x)&&rest.length>x.length+3); if(suf){out.push(rest.slice(0,-suf.length));out.push(rest.slice(-suf.length));return out.filter(Boolean)}
  while(rest.length>4){out.push(rest.slice(0,Math.min(3,rest.length-3)));rest=rest.slice(Math.min(3,rest.length-3))} if(rest)out.push(rest);return out;
}

function masteryScore(w){
  const s={...defaultSkills(),...(w.skills||{})};
  const skillCore=(s.retrieval*.35)+(s.spelling*.30)+(s.context*.15)+(s.recognition*.10)+(s.listening*.10);
  const activeDays=Math.min(4,(w.activeSuccessDays||[]).length);
  const delayed=w.maxActiveGapDays>=7?4:w.maxActiveGapDays>=3?3:w.maxActiveGapDays>=1?2:0;
  return (skillCore*.68)+(activeDays*.20)+(delayed*.12);
}
function meetsMasteryCriteria(w){
  const s={...defaultSkills(),...(w.skills||{})};
  const activeDays=(w.activeSuccessDays||[]).length;
  const contextOk=(w.errorProfile?.context||0)<2 || s.context>=1;
  return s.retrieval>=2 && s.spelling>=2 && contextOk && activeDays>=3 && (w.maxActiveGapDays||0)>=3 && (w.coldRecallDays||[]).length>=2 && (w.independentSuccesses||0)>=5 && w.intervalDays>=7;
}
function isMastered(w){ return meetsMasteryCriteria(w); }
function refreshMastery(w){
  const mastered=meetsMasteryCriteria(w);
  if(mastered && !w.masteredAt)w.masteredAt=new Date().toISOString();
  if(!mastered && w.masteredAt){w.lastMasteredAt=w.masteredAt;w.masteredAt=null;}
  w.level=mastered?4:Math.min(3,Math.max(0,Math.floor(masteryScore(w))));
}
function subjectProgress(subject=state.activeSubject,schoolYear=currentSchoolYear()){
  const words=schoolYearWords(subject,schoolYear); const mastered=words.filter(isMastered).length; const stable=words.filter(w=>w.intervalDays>=7 && (w.independentSuccesses||0)>w.failures).length;
  return {schoolYear,total:words.length,mastered,stable,pct:words.length?Math.round(mastered/words.length*100):0};
}
function dueWords(subject=state.activeSubject,schoolYear=currentSchoolYear()){return schoolYearWords(subject,schoolYear).filter(w=>!w.dueDate||w.dueDate<=today()).sort((a,b)=>(a.dueDate||'').localeCompare(b.dueDate||''));}
function armyStrength(subject=state.activeSubject,schoolYear=currentSchoolYear()){
  const p=subjectProgress(subject,schoolYear); const words=schoolYearWords(subject,schoolYear);
  const avg=words.length?words.reduce((s,w)=>s+masteryScore(w),0)/(words.length*4):0;
  return Math.round(p.pct*10 + avg*100);
}
const fortresses=[{id:'outpost',name:'Vorposten',req:15},{id:'tower',name:'Wachturm',req:30},{id:'wall',name:'Grenzfestung',req:50},{id:'citadel',name:'Zitadelle',req:70},{id:'capital',name:'Hauptfestung',req:85},{id:'final',name:'Jahresfestung',req:100}];
function nextFortress(subject=state.activeSubject,schoolYear=currentSchoolYear()){const wins=fortressWins(subject,schoolYear);return fortresses.find(f=>!wins.includes(f.id))||null}
function rankFor(pct,subject){
  const latin=['Tiro','Miles','Contubernium','Centurie','Cohorte','Legion'];
  const english=['Rekruten','Trupp','Kompanie','Bataillon','Regiment','Armee'];
  const arr=subject==='latin'?latin:english; const i=Math.min(5,Math.floor(pct/20)); return arr[i];
}
function gearFor(pct){return ['I','II','III','IV','V','VI'][Math.min(5,Math.floor(pct/18))]}
function soldiersFor(pct){return clamp(2+Math.floor(pct/9),2,13)}

const streakActivityTypes=new Set(['adaptive','recognition','recall','spelling','listening','context','chunks','flash','shower']);
function recordActivity(type,meta={}){ const l=learner(); if(streakActivityTypes.has(type)&&!l.streakDays.includes(today())) l.streakDays.push(today()); state.activity.push({id:uid('a'),learnerId:l.id,date:new Date().toISOString(),type,...meta}); }
function streak(){
  const days=new Set(learner().streakDays); let n=0,d=new Date(); d.setHours(12,0,0,0); for(;;){const k=dateKey(d); if(days.has(k)){n++;d.setDate(d.getDate()-1)}else break} return n;
}

function seasonInfo(){const m=new Date().getMonth()+1; if([12,1,2].includes(m))return {class:'winter',festive:m===12}; if([3,4,5].includes(m))return {class:'spring'}; if([9,10,11].includes(m))return {class:'autumn'}; return {class:'summer'}}
function dayNumber(key){const [y,m,d]=String(key||'').split('-').map(Number);return y&&m&&d?Math.floor(Date.UTC(y,m-1,d)/864e5):NaN}
function daysUntil(key){const n=dayNumber(key),t=dayNumber(today());return Number.isFinite(n)&&Number.isFinite(t)?n-t:null}
function formatDateShort(key){const [y,m,d]=String(key||'').split('-').map(Number);if(!y||!m||!d)return '';return new Date(y,m-1,d).toLocaleDateString('de-DE',{day:'2-digit',month:'2-digit'})}
const WEEKDAYS=['Sonntag','Montag','Dienstag','Mittwoch','Donnerstag','Freitag','Samstag'];
const WEEKDAYS_SHORT=['So','Mo','Di','Mi','Do','Fr','Sa'];
function localDateFromKey(key){const [y,m,d]=String(key||'').split('-').map(Number);if(!y||!m||!d)return null;const out=new Date(y,m-1,d,12,0,0,0);return Number.isNaN(out.getTime())?null:out}
function nextWeeklyDate(weekday,fromKey=today()){const base=localDateFromKey(fromKey)||new Date();const wanted=clamp(Number(weekday)||0,0,6);const delta=(wanted-base.getDay()+7)%7;base.setDate(base.getDate()+delta);return dateKey(base)}
function activeSeries(subject=state.activeSubject){const cfg=learner()?.testSeries?.[subject];return cfg&&cfg.enabled?cfg:null}
function seriesScopePending(subject=state.activeSubject){const cfg=activeSeries(subject);if(!cfg)return null;const date=nextWeeklyDate(cfg.weekday);return cfg.scopeDate===date?null:{date,days:daysUntil(date),series:cfg}}
function normalizedRange(count,from,to){if(!count)return {from:1,to:0};let a=clamp(Math.max(1,Number(from)||1),1,count),b=clamp(Math.max(1,Number(to)||count),1,count);if(a>b)[a,b]=[b,a];return {from:a,to:b}}
function scopedWordsForSet(set,scopeMode='set',from=1,to=null){if(!set)return [];const words=setWords(set.id);if(scopeMode!=='range'||!words.length)return words;const r=normalizedRange(words.length,from,to);return words.slice(r.from-1,r.to)}
function scopeTextForSet(set,scopeMode='set',from=1,to=null){if(!set)return '';if(scopeMode!=='range')return set.title;const count=setWords(set.id).length;if(!count)return set.title;const r=normalizedRange(count,from,to);return `${set.title} · Vokabeln ${r.from}–${r.to}`}
function scopedWordsForSeries(cfg,subject=state.activeSubject){if(!cfg||!cfg.setId)return [];const set=state.sets.find(s=>s.id===cfg.setId&&s.learnerId===state.activeLearnerId&&s.subject===subject);return scopedWordsForSet(set,cfg.scopeMode,cfg.from,cfg.to)}
function seriesScopeText(cfg){if(!cfg)return '';const set=state.sets.find(s=>s.id===cfg.setId);return scopeTextForSet(set,cfg.scopeMode,cfg.from,cfg.to)}
function testReadinessScore(w){
  const s={...defaultSkills(),...(w.skills||{})};
  const activeCore=((s.retrieval||0)*.48+(s.spelling||0)*.38+(s.context||0)*.08+(s.recognition||0)*.03+(s.listening||0)*.03)/4;
  const activeDays=Math.min(1,(w.activeSuccessDays||[]).length/2); const delayed=Math.min(1,(w.maxActiveGapDays||0)/3);
  return Math.round((activeCore*.72+activeDays*.18+delayed*.10)*100);
}
function isTestReady(w){const s={...defaultSkills(),...(w.skills||{})};return isMastered(w)||(testReadinessScore(w)>=65&&(s.retrieval||0)>=2&&(s.spelling||0)>=2&&(w.activeSuccessDays||[]).length>=2&&(w.coldRecallDays||[]).length>=1&&(w.maxActiveGapDays||0)>=1)}
function testReadinessForContext(ctx){
  const words=ctx?.words||[]; if(!words.length)return {total:0,ready:0,pct:0,avg:0,weak:[]};
  const ready=words.filter(isTestReady).length; const avg=Math.round(words.reduce((sum,w)=>sum+testReadinessScore(w),0)/words.length);
  const weak=[...words].sort((a,b)=>testReadinessScore(a)-testReadinessScore(b)||masteryScore(a)-masteryScore(b));
  return {total:words.length,ready,pct:Math.round(ready/words.length*100),avg,weak};
}
function upcomingTestContext(subject=state.activeSubject){
  const explicit=mySets(subject).filter(s=>s.testDate&&daysUntil(s.testDate)>=0&&setWords(s.id).length).sort((a,b)=>a.testDate.localeCompare(b.testDate));
  let single=null;
  if(explicit.length){const date=explicit[0].testDate,sets=explicit.filter(s=>s.testDate===date),words=uniqueWords(sets.flatMap(set=>scopedWordsForSet(set,set.testScopeMode,set.testFrom,set.testTo)));single={date,days:daysUntil(date),sets,words,source:'single',testFormat:sets[0]?.testFormat||'target',scopeText:sets.map(set=>scopeTextForSet(set,set.testScopeMode,set.testFrom,set.testTo)).join(' + ')}}
  const cfg=activeSeries(subject); let recurring=null;
  if(cfg){const date=nextWeeklyDate(cfg.weekday),set=state.sets.find(s=>s.id===cfg.setId&&s.learnerId===state.activeLearnerId&&s.subject===subject),words=scopedWordsForSeries(cfg,subject);if(cfg.scopeDate===date&&set&&words.length)recurring={date,days:daysUntil(date),sets:[set],words,source:'series',series:cfg,testFormat:cfg.testFormat||'target',scopeText:seriesScopeText(cfg)}}
  if(single&&recurring&&single.date===recurring.date){const sets=uniqueById([...single.sets,...recurring.sets]);const words=uniqueWords([...single.words,...recurring.words]);return {date:single.date,days:single.days,sets,words,source:'mixed',series:cfg,testFormat:single.testFormat||recurring.testFormat||'target',scopeText:[single.scopeText,recurring.scopeText].filter(Boolean).join(' + ')}}
  if(!single)return recurring; if(!recurring)return single; return single.date<=recurring.date?single:recurring;
}
function uniqueById(list){const seen=new Set();return list.filter(x=>x&&!seen.has(x.id)&&seen.add(x.id))}
function testContextLabel(ctx,subject=state.activeSubject){if(!ctx)return '';const subjectName=subject==='latin'?'Latein':'Englisch';const when=ctx.days===0?'heute':ctx.days===1?'morgen':`in ${ctx.days} Tagen`;const recurrence=ctx.source==='series'||ctx.source==='mixed'?` · wöchentlich ${WEEKDAYS_SHORT[Number(ctx.series?.weekday)||0]}`:'';return `${subjectName}-Test ${when}${recurrence} · ${ctx.scopeText||ctx.sets.map(s=>s.title).join(' + ')}`}
function dailyPlanSignature(ctx,subject,sessionSize){
  const words=(ctx?ctx.words:schoolYearWords(subject)).map(w=>w.id).sort().join(',');
  return `${VERSION}:${ctx?`test:${ctx.source||'single'}:${ctx.date}:${ctx.sets.map(s=>s.id).sort().join(',')}`:`general:${currentSchoolYear()}`}:${sessionSize}:${words}`;
}
function uniqueWords(list){const seen=new Set();return list.filter(w=>w&&!seen.has(w.id)&&seen.add(w.id))}
function buildDailyPlan(subject=state.activeSubject){
  const l=learner(); l.dailyPlans=l.dailyPlans||{}; const sessionSize=l.lrsMode?6:10; const ctx=upcomingTestContext(subject); const key=`${today()}:${subject}`; const signature=dailyPlanSignature(ctx,subject,sessionSize);
  const existing=l.dailyPlans[key]; if(existing&&existing.signature===signature&&existing.wordIds.every(id=>state.words.some(w=>w.id===id)))return existing;
  const pool=ctx?ctx.words:schoolYearWords(subject); let selected=[],urgent=false,plannedNeed=0,phase='general',maintenanceCount=0;
  if(ctx&&pool.length){
    const due=pool.filter(w=>(w.repetitions||0)>0&&(!w.dueDate||w.dueDate<=today())).sort((a,b)=>testReadinessScore(a)-testReadinessScore(b));
    const unseen=pool.filter(w=>(w.repetitions||0)===0).sort((a,b)=>a.term.localeCompare(b.term));
    const seenWeak=pool.filter(w=>(w.repetitions||0)>0&&!isTestReady(w)).sort((a,b)=>testReadinessScore(a)-testReadinessScore(b)||masteryScore(a)-masteryScore(b));
    const allWeak=pool.filter(w=>!isTestReady(w)).sort((a,b)=>testReadinessScore(a)-testReadinessScore(b)||masteryScore(a)-masteryScore(b));
    const maxDaily=sessionSize*2;
    if(ctx.days>=4){
      phase='acquire';
      const newQuota=Math.min(unseen.length,Math.max(1,Math.ceil(unseen.length/Math.max(1,ctx.days-2))));
      const reviewQuota=Math.min(seenWeak.length,Math.max(1,Math.ceil(seenWeak.length/Math.max(2,ctx.days))));
      plannedNeed=Math.min(maxDaily,Math.max(due.length,newQuota+reviewQuota));
      selected=uniqueWords([...unseen.slice(0,newQuota),...due,...seenWeak,...allWeak]).slice(0,plannedNeed);
    }else if(ctx.days>=2){
      phase='consolidate';
      const newQuota=Math.min(unseen.length,Math.max(0,Math.ceil(unseen.length/Math.max(2,ctx.days+1))));
      plannedNeed=Math.min(maxDaily,Math.max(due.length,Math.ceil(allWeak.length/Math.max(1,ctx.days)),newQuota));
      selected=uniqueWords([...due,...seenWeak,...unseen.slice(0,newQuota),...allWeak]).slice(0,plannedNeed);
    }else{
      phase='rehearse';
      plannedNeed=Math.min(maxDaily,Math.max(due.length,Math.min(allWeak.length,maxDaily)));
      if(!plannedNeed&&pool.length)plannedNeed=Math.min(sessionSize,Math.min(3,pool.length));
      selected=uniqueWords([...due,...seenWeak,...allWeak.filter(w=>(w.repetitions||0)>0),...unseen,...allWeak]).slice(0,plannedNeed);
    }
    urgent=allWeak.length>maxDaily || (ctx.days<=1&&unseen.length>0);
    if(ctx.days>=2 && selected.length<maxDaily){
      const poolIds=new Set(pool.map(w=>w.id)); const maintenance=dueWords(subject).filter(w=>!poolIds.has(w.id)).slice(0,l.lrsMode?1:2);
      const before=selected.length; selected=uniqueWords([...selected,...maintenance]).slice(0,maxDaily); maintenanceCount=selected.length-before;
    }
  }else{
    const due=dueWords(subject),weak=schoolYearWords(subject).filter(w=>!isMastered(w)).sort((a,b)=>masteryScore(a)-masteryScore(b)); plannedNeed=due.length?Math.min(sessionSize,due.length):Math.min(learner().lrsMode?4:5,weak.length); selected=uniqueWords([...due,...weak]).slice(0,plannedNeed);
  }
  const plan={date:today(),subject,signature,source:ctx?(ctx.source||'test'):'general',testDate:ctx?.date||'',setIds:ctx?.sets.map(s=>s.id)||[],setTitle:ctx?.scopeText||ctx?.sets.map(s=>s.title).join(' + ')||'',wordIds:selected.map(w=>w.id),sessionSize,urgent,phase,maintenanceCount,createdAt:new Date().toISOString()};
  l.dailyPlans[key]=plan; Object.keys(l.dailyPlans).filter(k=>k<`${datePlusDays(-21)}:`).forEach(k=>delete l.dailyPlans[k]); persistOnly(); return plan;
}
function wordPracticedToday(w){return !!(w?.activePracticeDays||[]).includes(today())}
function dailyPlanStatus(plan=buildDailyPlan()){
  const words=plan.wordIds.map(id=>state.words.find(w=>w.id===id)).filter(Boolean),done=words.filter(wordPracticedToday),remaining=words.filter(w=>!wordPracticedToday(w));
  return {total:words.length,done:done.length,remaining:remaining.length,remainingIds:remaining.map(w=>w.id),units:remaining.length?Math.ceil(remaining.length/plan.sessionSize):0};
}
function startDailyTodo(){
  const pending=seriesScopePending(),ctx=upcomingTestContext(); if(pending&&(!ctx||pending.date<=ctx.date)){openTestDatePlanner();return}
  const plan=buildDailyPlan(),status=dailyPlanStatus(plan); if(!myWords().length){if(!mySets().length)openSetEditor();else openFirstWordsChooser();return} if(!status.remaining){toast('Tagesziel erledigt. Weitere Übungen sind optional.','good');return}
  startSession('adaptive',null,status.remainingIds.slice(0,plan.sessionSize),true);
}