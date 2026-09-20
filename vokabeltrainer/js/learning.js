'use strict';

function recentActiveAccuracy(w){const arr=(w.recentActiveResults||[]).slice(-6);return arr.length?arr.filter(Boolean).length/arr.length:null}
function latinMeta(w){
  const extra=String(w.extra||'').trim(), term=String(w.term||'').trim();
  const out={kind:'other',genitive:'',gender:'',principalParts:'',other:''};
  const gender=(extra.match(/(?:^|[,;\s])([mfn])\.?\s*$/i)||[])[1]; if(gender)out.gender=gender.toLowerCase();
  const parts=extra.split(',').map(x=>x.trim()).filter(Boolean);
  if(gender && parts.length){out.kind='noun';out.genitive=parts[0].replace(/\s+[mfn]\.?$/i,'').trim();return out;}
  if(/(?:o|or|io|eo)\b/i.test(parts[0]||'') || parts.length>=3 || /\b(?:sum|fui|esse|fero|tuli|latum)\b/i.test(extra)){out.kind='verb';out.principalParts=extra;return out;}
  if(extra){out.kind='form';out.other=extra;}
  return out;
}
function latinGrammarEligible(w){if(state.activeSubject!=='latin')return false;const m=latinMeta(w);return !!(m.genitive||m.gender||m.principalParts||m.other)}
function grammarKeys(w){const m=latinMeta(w);if(m.kind==='noun')return [m.genitive?'genitive':null,m.gender?'gender':null].filter(Boolean);if(m.kind==='verb')return ['principalParts'];return m.other?['form']:[]}
function grammarReady(w){const keys=grammarKeys(w),skills=w.grammarSkills||{};return !!keys.length&&keys.every(k=>(skills[k]||0)>=2)&&(w.grammarSuccessDays||[]).length>=2}
function grammarTarget(w){
  const m=latinMeta(w), skills=w.grammarSkills||{genitive:0,gender:0,principalParts:0,form:0};
  if(m.kind==='noun')return (m.genitive && skills.genitive<=skills.gender)?{key:'genitive',label:'Genitiv',prompt:`${w.term} – Genitiv?`,target:m.genitive,rule:'Substantive immer als Nominativ + Genitiv + Genus zusammen lernen.'}:{key:'gender',label:'Genus',prompt:`${w.term}, ${m.genitive||'…'} – Genus?`,target:m.gender,rule:'Das Genus gehört fest zur Vokabel. Antworte m, f oder n.'};
  if(m.kind==='verb')return {key:'principalParts',label:'Stammformen',prompt:`${w.term} – Stamm-/Grundformen?`,target:m.principalParts,rule:'Stammformen produktiv abrufen; sie helfen, gebeugte Verbformen später wiederzuerkennen.'};
  return {key:'form',label:'Zusatzform',prompt:`${w.term} – ergänzende Form?`,target:m.other,rule:'Form und Grundbedeutung zusammen verknüpfen; danach im Beispielsatz wiedererkennen.'};
}
function chooseAdaptiveMode(w){
  const s={...defaultSkills(),...(w.skills||{})},lrs=!!learner().lrsMode,modes=new Set(w.modesSeen||[]),acc=recentActiveAccuracy(w);
  if(acc!==null&&acc<.7){if(lrs&&s.listening<2)return 'listening';if(s.recognition<2)return 'recognition';if(!modes.has('chunks'))return 'chunks';}
  const testCtx=session?.isDaily?upcomingTestContext():null,fmt=testCtx?.testFormat||'target';
  if(testCtx&&testCtx.days<=1&&(w.repetitions||0)>0){if(fmt==='source')return 'reverseRecall';if(fmt==='dictation')return 'spelling';if(fmt==='mixed')return session.index%2?'reverseRecall':'recall';}
  if(lrs){
    if(s.listening<1)return 'listening';
    if(s.spelling<1&&!modes.has('chunks'))return 'chunks';
    if(s.retrieval<2)return 'recall';
    if(s.spelling<2)return 'spelling';
    if(w.example&&(w.errorProfile?.context||0)>0&&s.context<1)return 'context';
    if(s.retrieval<3)return 'recall';
    if(s.spelling<3)return 'spelling';
    return w.example&&(w.errorProfile?.context||0)>0&&s.context<2?'context':(s.retrieval<=s.spelling?'recall':'spelling');
  }
  if(s.recognition<1)return 'recognition';
  if(s.retrieval<2)return 'recall';
  if(s.spelling<2)return 'spelling';
  if(s.listening<1)return 'listening';
  if(w.example&&s.context<1)return 'context';
  if(s.retrieval<3)return 'recall';
  if(s.spelling<3)return 'spelling';
  return w.example&&(w.errorProfile?.context||0)>0&&s.context<2?'context':(s.retrieval<=s.spelling?'recall':'spelling');
}
function buildQueue(mode,setId=null,wordIds=null){
  const chosen=Array.isArray(wordIds)?wordIds.map(id=>state.words.find(w=>w.id===id)).filter(Boolean):null; const pool=chosen||(setId?setWords(setId):schoolYearWords()); if(chosen)return pool; if(mode==='shower'||mode==='flash') return pool.filter(Boolean);
  if(mode==='latinGrammar'){const all=pool.filter(latinGrammarEligible),need=all.filter(w=>!grammarReady(w)),src=need.length?need:all;return src.sort((a,b)=>(a.grammarSuccessDays||[]).length-(b.grammarSuccessDays||[]).length||Math.min(...grammarKeys(a).map(k=>(a.grammarSkills||{})[k]||0))-Math.min(...grammarKeys(b).map(k=>(b.grammarSkills||{})[k]||0))).slice(0,learner().lrsMode?6:10);}
  if(mode==='handwriting'){const src=[...pool].filter(Boolean).sort((a,b)=>((b.errorProfile?.spelling||0)-(a.errorProfile?.spelling||0))||((a.skills?.spelling||0)-(b.skills?.spelling||0))||masteryScore(a)-masteryScore(b));return src.slice(0,learner().lrsMode?4:6);}
  let q=pool.filter(w=>!isMastered(w)); if(!q.length)q=pool; const due=q.filter(w=>!w.dueDate||w.dueDate<=today()); const src=due.length?due:q;
  return src.sort((a,b)=>masteryScore(a)-masteryScore(b)).slice(0,learner().lrsMode?6:10);
}
function openPracticeTestChooser(){
  const ctx=upcomingTestContext(); if(!ctx||!ctx.words.length){toast('Lege zuerst einen Testplan mit Vokabelumfang fest.','warn');return}
  const r=testReadinessForContext(ctx); const shortCount=Math.min(10,ctx.words.length);
  modal(`<div class="eyebrow">Prüfungssimulation</div><h2>Testcheck starten</h2><p>${esc(testContextLabel(ctx))}</p><div class="notice subtle"><strong>${r.pct}% testbereit</strong><br>${r.ready} von ${r.total} Wörtern erfüllen aktuell die Testbereitschaft.</div><p>Die Simulation verändert weder Lernstufen noch Wiederholungsintervalle und vergibt keine XP.</p><div class="modal-actions wrap"><button value="cancel" class="ghost">Abbrechen</button><button type="button" id="practiceShortBtn" class="secondary">Kurzcheck (${shortCount})</button><button type="button" id="practiceFullBtn" class="primary">Kompletter Test (${ctx.words.length})</button></div>`);
  $('#practiceShortBtn').onclick=()=>{closeModal();startPracticeTest(false)}; $('#practiceFullBtn').onclick=()=>{closeModal();startPracticeTest(true)};
}
function startPracticeTest(full=false){
  const ctx=upcomingTestContext(); if(!ctx||!ctx.words.length){toast('Kein Testumfang festgelegt.','warn');return}
  const pool=full?[...ctx.words]:testReadinessForContext(ctx).weak.slice(0,Math.min(10,ctx.words.length));
  session={mode:'practiceTest',setId:null,queue:pool.map(w=>w.id),index:0,correct:0,answered:0,currentSubmode:'practiceTest',locked:false,retryCounts:{},followupCounts:{},hintUsed:false,isDaily:false,testAnswers:[],practiceContext:{date:ctx.date,scopeText:ctx.scopeText||ctx.sets.map(s=>s.title).join(' + '),source:ctx.source,testFormat:ctx.testFormat||'target'},practiceFull:full};
  showView('learnView'); $('#modePill').textContent=full?'Prüfung · komplett':'Prüfung · Kurzcheck'; renderStudy();
}
function practiceDirection(w){const f=session?.practiceContext?.testFormat||'target';if(f==='source')return {prompt:w.term,target:w.translation,label:'Deutsch'};if(f==='dictation')return {prompt:'🔊 Diktat',target:w.term,label:state.activeSubject==='latin'?'Latein':'Englisch',audio:true};if(f==='mixed'){const flip=(session.index%2)===1;return flip?{prompt:w.term,target:w.translation,label:'Deutsch'}:{prompt:w.translation,target:w.term,label:state.activeSubject==='latin'?'Latein':'Englisch'};}return {prompt:w.translation,target:w.term,label:state.activeSubject==='latin'?'Latein':'Englisch'};}
function renderPracticeTest(w){
  const d=practiceDirection(w);$('#studyArea').innerHTML=`<div class="study-card"><div class="eyebrow">Prüfungssimulation</div><div class="study-prompt">${esc(d.prompt)}</div><div class="study-sub">Schreibe die passende Antwort auf ${esc(d.label)}. Keine Hinweise, Auswertung erst am Ende.</div>${d.audio?'<button id="practiceSpeakBtn" class="secondary">🔊 Anhören</button>':''}<input id="answerField" class="answer-input" autocomplete="off" autocapitalize="none" spellcheck="false"><div class="top-space"><button id="answerBtn" class="primary">Antwort speichern</button></div></div>`;
  if(d.audio){$('#practiceSpeakBtn').onclick=()=>speak(w.term);setTimeout(()=>speak(w.term),150)}
  const submit=()=>{if(session.locked)return;session.locked=true;const answer=$('#answerField').value.trim();const ok=answerMatches(answer,d.target);session.testAnswers.push({wordId:w.id,answer,correct:ok,target:d.target,prompt:d.prompt});session.answered++;if(ok)session.correct++;session.index++;renderStudy()};
  $('#answerBtn').onclick=submit; $('#answerField').onkeydown=e=>{if(e.key==='Enter')submit()}; setTimeout(()=>$('#answerField')?.focus(),40);
}
function finishPracticeTest(){
  const answers=session?.testAnswers||[],total=answers.length,correct=answers.filter(a=>a.correct).length,pct=total?Math.round(correct/total*100):0,wrong=answers.filter(a=>!a.correct);
  const scale={...gradeScaleFor(state.activeSubject)},suggestedGrade=suggestGradeFromScale(pct,scale);
  const result={id:uid('pt'),learnerId:learner().id,subject:state.activeSubject,date:today(),testDate:session?.practiceContext?.date||'',scopeText:session?.practiceContext?.scopeText||'',full:!!session?.practiceFull,total,correct,percent:pct,suggestedGrade,gradeScaleSnapshot:scale,answers};
  state.practiceTests.push(result); persistOnly();
  $('#studyArea').innerHTML=`<div class="study-card"><div class="eyebrow">Testcheck beendet</div><div class="study-prompt">${pct}%</div><p><strong>${correct} von ${total}</strong> richtig.</p><div class="notice subtle"><strong>Notenvorschlag: ${esc(suggestedGrade)}</strong><br><small>${esc(gradeScaleText(scale))}</small><br><small>Nur Orientierung – der tatsächliche Notenschlüssel der Lehrkraft kann abweichen.</small></div>${wrong.length?`<div class="practice-errors"><h3>Noch unsicher</h3>${wrong.map(a=>`<div><span>${esc(a.prompt)}</span><span>${esc(a.answer||'–')} → <strong>${esc(a.target)}</strong></span></div>`).join('')}</div>`:'<div class="notice good">Alle Antworten waren richtig.</div>'}<div class="row gap center-actions wrap top-space">${wrong.length?'<button id="practiceWrongBtn" class="secondary">Unsichere Wörter üben</button>':''}<button id="practiceScaleBtn" class="ghost">Notenschlüssel</button><button id="doneBtn" class="primary">Zur Übersicht</button></div><p class="microcopy">Dieser Testcheck verändert den Lernstand nicht. Ergebnis und damaliger Notenschlüssel werden gespeichert.</p></div>`;
  $('#sessionPill').textContent='Fertig'; $('#practiceWrongBtn')?.addEventListener('click',()=>{const ids=wrong.map(a=>a.wordId);session=null;startSession('adaptive',null,ids,false)}); $('#practiceScaleBtn').onclick=()=>openGradeScaleSettings(state.activeSubject); $('#doneBtn').onclick=()=>{session=null;showView('dashboardView');renderAll()};
}

function startSession(mode='adaptive',setId=null,wordIds=null,isDaily=false){
  const queue=buildQueue(mode,setId,wordIds); if(!queue.length){toast('Noch keine Vokabeln vorhanden.','warn');return}
  session={mode,setId,queue:queue.map(w=>w.id),index:0,correct:0,answered:0,currentSubmode:null,locked:false,retryCounts:{},followupCounts:{},hintUsed:false,isDaily,scaffoldedWords:{},activeAttemptedWords:{},grammarIntroShown:false}; showView('learnView'); $('#modePill').textContent=modeLabel(mode); renderStudy();
}
function modeLabel(m){return ({adaptive:'Adaptiv',flash:'Wortblitz',shower:'Vokabeldusche',chunks:'Wortbausteine',handwriting:'Handschrift',recognition:'Erkennen',recall:'Abrufen',reverseRecall:'Bedeutung abrufen',spelling:'Schreiben',listening:'Hören',context:'Kontext',latinGrammar:'Latein Formen',practiceTest:'Prüfung'})[m]||m}
function currentWord(){return state.words.find(w=>w.id===session.queue[session.index])}
function renderStudy(){
  if(!session||session.index>=session.queue.length){finishSession();return}
  const w=currentWord(); if(!w){session.index++;renderStudy();return}
  $('#sessionPill').textContent=`${session.index+1} / ${session.queue.length}`;
  session.locked=false; session.hintUsed=false;
  if(session.mode==='practiceTest') return renderPracticeTest(w);
  if(session.mode==='latinGrammar') return renderLatinGrammar(w);
  if(session.mode==='shower') return renderShower(w);
  if(session.mode==='flash') return renderFlash(w);
  if(session.mode==='chunks') return renderChunks(w);
  if(session.mode==='handwriting') return renderHandwriting(w);
  const sub=session.mode==='adaptive'?chooseAdaptiveMode(w):session.mode; session.currentSubmode=sub; $('#modePill').textContent=session.mode==='adaptive'?`Adaptiv · ${modeLabel(sub)}`:modeLabel(sub);
  if(sub==='recognition')renderRecognition(w); else if(sub==='listening')renderListening(w); else if(sub==='chunks')renderChunks(w); else if(sub==='reverseRecall')renderReverseRecall(w); else if(sub==='spelling')renderSpelling(w); else if(sub==='context')renderContext(w); else renderRecall(w);
}
function cardExtras(w){
  const conf=detectConfusions(w,myWords()); const c=conf.length?`<div class="confusion-box"><strong>Verwechslungsalarm</strong><br>${conf.map(x=>`<span class="pill">${esc(x.term)} = ${esc(x.translation)}</span>`).join(' ')}</div>`:'';
  const s={...defaultSkills(),...(w.skills||{})}; return `${c}<div class="skill-strip" title="Erkennen · Hören · Abruf · Schreiben · Kontext">${['recognition','listening','retrieval','spelling','context'].map(k=>`<span class="${s[k]>=3?'on':''}"></span>`).join('')}</div>`;
}
function renderLatinGrammar(w){
  const g=grammarTarget(w); session.currentSubmode='latinGrammar';
  $('#modePill').textContent=`Latein · ${g.label}`;
  $('#studyArea').innerHTML=`<div class="study-card"><div class="eyebrow">Latein Formen · ${esc(g.label)}</div><div class="notice subtle"><strong>Mini-Regel</strong><br>${esc(g.rule)}</div><div class="study-prompt compact-prompt">${esc(g.prompt)}</div><div class="study-sub">Aus dem Gedächtnis antworten. Danach bekommst du sofort die richtige Form und die Vokabel im Zusammenhang.</div><input id="answerField" class="answer-input" autocomplete="off" autocapitalize="none" spellcheck="false"><div class="row gap center-actions top-space"><button id="answerBtn" class="primary">Prüfen</button><button id="grammarHintBtn" class="ghost">Regelhilfe</button></div></div>`;
  const submit=()=>gradeGrammar(w,g,$('#answerField').value); $('#answerBtn').onclick=submit; $('#answerField').onkeydown=e=>{if(e.key==='Enter')submit()}; $('#grammarHintBtn').onclick=()=>{session.hintUsed=true;$('#grammarHintBtn').textContent=g.target.slice(0,Math.max(1,Math.ceil(g.target.length*.25)))+'…'}; setTimeout(()=>$('#answerField')?.focus(),40);
}
function grammarMatches(answer,target,key){
  if(key==='gender'){const a=normalize(answer).replace(/\./g,''),t=normalize(target).replace(/\./g,'');const aliases={maskulin:'m',masculine:'m',feminin:'f',feminine:'f',neutrum:'n',neuter:'n'};return (aliases[a]||a)===(aliases[t]||t)}
  if(key==='principalParts'){const norm=x=>normalize(x).replace(/\s+/g,' ');const a=norm(answer),t=norm(target);if(a===t)return true;const ap=a.split(/[,;]\s*/).filter(Boolean),tp=t.split(/[,;]\s*/).filter(Boolean);return tp.length>1&&ap.length===tp.length&&ap.every((x,i)=>x===tp[i]);}
  return answerMatches(answer,target);
}
function gradeGrammar(w,g,answer){if(session.locked)return;session.locked=true;const ok=grammarMatches(answer,g.target,g.key),assisted=!!session.hintUsed;$('#studyArea .study-card').insertAdjacentHTML('beforeend',`<div class="feedback notice ${ok?'good':'bad'}"><strong>${ok?(assisted?'Richtig mit Hilfe.':'Richtig.'):'Noch nicht richtig.'}</strong><br>${ok?'':`Deine Antwort: ${esc(answer||'–')}<br>`}Richtig: <strong>${esc(g.target)}</strong>${w.example?`<br><small>Im Kontext: ${esc(w.example)}</small>`:''}</div>`);recordGrammarResult(w,g.key,ok,assisted);setTimeout(()=>nextStudy(ok,w),ok?850:2300)}
function recordGrammarResult(w,key,ok,assisted){w.grammarSkills=w.grammarSkills||{genitive:0,gender:0,principalParts:0,form:0};w.grammarSuccessDays=w.grammarSuccessDays||[];if(ok){w.grammarSkills[key]=clamp((w.grammarSkills[key]||0)+(assisted?.5:1),0,4);if(!assisted)w.grammarSuccessDays=[...new Set([...w.grammarSuccessDays,today()])];session.correct++;learner().xp+=assisted?1:2}else{w.grammarSkills[key]=clamp((w.grammarSkills[key]||0)-1,0,4);w.errorProfile.grammar=(w.errorProfile.grammar||0)+1}w.repetitions++;w.lastReviewedAt=new Date().toISOString();w.practiceDays=[...new Set([...(w.practiceDays||[]),today()])];session.answered++;recordActivity('latinGrammar',{wordId:w.id,key,correct:ok,assisted});persistOnly()}
function renderRecognition(w){
  const pool=schoolYearWords().filter(x=>x.id!==w.id); const opts=uniqueOptions(w.translation,shuffle(pool).map(x=>x.translation));
  $('#studyArea').innerHTML=`<div class="study-card"><div class="eyebrow">Erkennen</div><div class="study-prompt">${esc(w.term)}</div><div class="study-sub">Welche Bedeutung passt?</div><div class="answer-grid">${opts.map(o=>`<button class="answer-option" data-answer="${esc(o)}">${esc(o)}</button>`).join('')}</div>${cardExtras(w)}</div>`;
  $$('[data-answer]').forEach(b=>b.onclick=()=>gradeChoice(b,w,b.dataset.answer,w.translation,'recognition'));
}
function renderRecall(w){
  $('#studyArea').innerHTML=`<div class="study-card"><div class="eyebrow">Aktiver Abruf</div><div class="study-prompt">${esc(w.translation)}</div><div class="study-sub">Schreibe die Vokabel aus dem Gedächtnis.</div><input id="answerField" class="answer-input" autocomplete="off" autocapitalize="none"><div class="row gap center-actions top-space"><button id="answerBtn" class="primary">Prüfen</button><button id="hintBtn" class="ghost">Hinweis</button></div>${cardExtras(w)}</div>`;
  $('#answerBtn').onclick=()=>gradeText(w,$('#answerField').value,w.term,'retrieval','retrieval'); $('#answerField').onkeydown=e=>{if(e.key==='Enter')$('#answerBtn').click()}; $('#hintBtn').onclick=()=>{session.hintUsed=true;$('#hintBtn').textContent=`${w.term.slice(0,Math.max(1,Math.ceil(w.term.length*.3)))}…`}; setTimeout(()=>$('#answerField').focus(),40);
}
function renderReverseRecall(w){
  $('#studyArea').innerHTML=`<div class="study-card"><div class="eyebrow">Aktiver Abruf · Bedeutung</div><div class="study-prompt">${esc(w.term)}</div><div class="study-sub">Schreibe die deutsche Bedeutung aus dem Gedächtnis.</div><input id="answerField" class="answer-input" autocomplete="off"><div class="row gap center-actions top-space"><button id="answerBtn" class="primary">Prüfen</button><button id="hintBtn" class="ghost">Hinweis</button></div>${cardExtras(w)}</div>`;
  $('#answerBtn').onclick=()=>gradeText(w,$('#answerField').value,w.translation,'retrieval','retrieval');$('#answerField').onkeydown=e=>{if(e.key==='Enter')$('#answerBtn').click()};$('#hintBtn').onclick=()=>{session.hintUsed=true;$('#hintBtn').textContent=`${w.translation.slice(0,Math.max(1,Math.ceil(w.translation.length*.3)))}…`};setTimeout(()=>$('#answerField')?.focus(),40);
}
function renderSpelling(w){
  $('#studyArea').innerHTML=`<div class="study-card"><div class="eyebrow">Schreiben</div><button id="speakBtn" class="secondary">🔊 Anhören</button><div class="study-prompt">${esc(w.translation)}</div><div class="study-sub">Hören → erinnern → vollständig schreiben.</div><input id="answerField" class="answer-input" autocomplete="off" autocapitalize="none"><div class="top-space"><button id="answerBtn" class="primary">Prüfen</button></div>${wordLearningCard(w,true)}${cardExtras(w)}</div>`;
  $('#speakBtn').onclick=()=>speak(w.term); $('#answerBtn').onclick=()=>gradeText(w,$('#answerField').value,w.term,'spelling','spelling'); $('#answerField').onkeydown=e=>{if(e.key==='Enter')$('#answerBtn').click()}; setTimeout(()=>speak(w.term),120);
}

function renderHandwriting(w){
  session.currentSubmode='handwriting';
  session.handwritingPhase=session.handwritingPhase||'trace';
  const trace=session.handwritingPhase==='trace';
  $('#modePill').textContent='Handschrift';
  $('#studyArea').innerHTML=`<div class="study-card handwriting-card"><div class="eyebrow">Handschrift · ${trace?'Einprägen':'Aus dem Gedächtnis'}</div><div class="study-prompt compact-prompt">${esc(trace?w.term:w.translation)}</div><div class="study-sub">${trace?'Sprich die Buchstaben leise mit und fahre das Wort mit dem Finger nach.':'Das Wort ist abgedeckt. Schreibe es jetzt aus dem Gedächtnis.'}</div><div class="handwriting-wrap ${trace?'trace-phase':''}"><canvas id="handwritingCanvas" class="handwriting-canvas" aria-label="Handschrift-Schreibfeld"></canvas>${trace?`<div class="trace-word" aria-hidden="true">${esc(w.term)}</div>`:''}</div><div class="row gap center-actions wrap top-space"><button id="undoStrokeBtn" class="ghost">↶ Rückgängig</button><button id="clearHandwritingBtn" class="ghost">Leeren</button><button id="speakHandwritingBtn" class="secondary">🔊 Anhören</button>${trace?'<button id="memoryWriteBtn" class="primary">Abdecken & schreiben</button>':'<button id="compareHandwritingBtn" class="primary">Lösung vergleichen</button>'}</div><p class="study-sub handwriting-note">Ohne Zeitdruck. Handschrift unterstützt die Einprägung; Mastery wird erst durch einen anschließend geprüften Abruf bestimmt.</p></div>`;
  const canvas=$('#handwritingCanvas'),ctx=setupHandwritingCanvas(canvas),strokes=[];
  let current=null,drawing=false;
  const redraw=()=>{ctx.clearRect(0,0,canvas.width,canvas.height);ctx.lineCap='round';ctx.lineJoin='round';ctx.strokeStyle='#172033';ctx.lineWidth=Math.max(4,canvas.width/120);for(const stroke of strokes){if(stroke.length<2)continue;ctx.beginPath();ctx.moveTo(stroke[0].x,stroke[0].y);for(const pt of stroke.slice(1))ctx.lineTo(pt.x,pt.y);ctx.stroke()}};
  const point=e=>{const r=canvas.getBoundingClientRect();return {x:(e.clientX-r.left)*canvas.width/r.width,y:(e.clientY-r.top)*canvas.height/r.height}};
  canvas.onpointerdown=e=>{drawing=true;current=[point(e)];strokes.push(current);canvas.setPointerCapture?.(e.pointerId);e.preventDefault()};
  canvas.onpointermove=e=>{if(!drawing)return;current.push(point(e));redraw();e.preventDefault()};
  const stop=e=>{drawing=false;current=null;try{canvas.releasePointerCapture?.(e.pointerId)}catch{}};
  canvas.onpointerup=stop;canvas.onpointercancel=stop;canvas.onpointerleave=e=>{if(e.buttons===0)stop(e)};
  $('#undoStrokeBtn').onclick=()=>{strokes.pop();redraw()};
  $('#clearHandwritingBtn').onclick=()=>{strokes.length=0;redraw()};
  $('#speakHandwritingBtn').onclick=()=>speak(w.term);
  if(trace){
    $('#memoryWriteBtn').onclick=()=>{session.handwritingPhase='memory';renderHandwriting(w)};
  }else{
    $('#compareHandwritingBtn').onclick=()=>showHandwritingCompare(w,strokes.length>0);
  }
}
function setupHandwritingCanvas(canvas){
  const ratio=Math.max(1,window.devicePixelRatio||1),rect=canvas.getBoundingClientRect(),w=Math.max(280,Math.round(rect.width)),h=Math.max(220,Math.round(rect.height));
  canvas.width=Math.round(w*ratio);canvas.height=Math.round(h*ratio);
  return canvas.getContext('2d');
}
function showHandwritingCompare(w,hasInk){
  if(!hasInk){toast('Schreibe das Wort zuerst einmal aus dem Gedächtnis.','warn');return}
  const card=$('#studyArea .study-card');card.insertAdjacentHTML('beforeend',`<div class="feedback notice subtle handwriting-compare"><strong>Lösung: ${esc(w.term)}</strong><br><small>Vergleiche Buchstabenfolge und Endung mit deiner Handschrift.</small><div class="row gap center-actions wrap top-space"><button id="handwritingAgainBtn" class="secondary">Nochmal</button><button id="handwritingMatchesBtn" class="primary">Passt</button></div></div>`);
  $('#compareHandwritingBtn').disabled=true;
  $('#handwritingAgainBtn').onclick=()=>{recordHandwriting(w,false);session.handwritingPhase='trace';nextStudy(false,w)};
  $('#handwritingMatchesBtn').onclick=()=>{recordHandwriting(w,true);session.handwritingPhase='trace';nextStudy(true,w)};
}
function recordHandwriting(w,matched){
  w.modesSeen=[...new Set([...(w.modesSeen||[]),'handwriting'])];
  recordActivity('handwriting',{wordId:w.id,selfChecked:!!matched});
  session.answered++;if(matched)session.correct++;
  persistOnly();
}
function renderListening(w){
  const pool=schoolYearWords().filter(x=>x.id!==w.id); const opts=uniqueOptions(w.term,shuffle(pool).map(x=>x.term));
  $('#studyArea').innerHTML=`<div class="study-card"><div class="eyebrow">Hören</div><button id="speakBtn" class="secondary">🔊 Wort anhören</button><div class="study-sub top-space-lg">Welches Wort hast du gehört?</div><div class="answer-grid">${opts.map(o=>`<button class="answer-option" data-answer="${esc(o)}">${esc(o)}</button>`).join('')}</div>${cardExtras(w)}</div>`;
  $('#speakBtn').onclick=()=>speak(w.term); $$('[data-answer]').forEach(b=>b.onclick=()=>gradeChoice(b,w,b.dataset.answer,w.term,'listening')); setTimeout(()=>speak(w.term),200);
}
function renderContext(w){
  const ex=w.example||`${w.term} — ${w.translation}`; const rx=new RegExp(w.term.replace(/[.*+?^${}()|[\]\\]/g,'\\$&'),'i'); const cloze=ex.replace(rx,'________');
  $('#studyArea').innerHTML=`<div class="study-card"><div class="eyebrow">Kontext</div><div class="study-prompt compact-prompt">${esc(cloze)}</div><div class="study-sub">Setze die passende Vokabel ein.</div><input id="answerField" class="answer-input" autocomplete="off" autocapitalize="none"><div class="top-space"><button id="answerBtn" class="primary">Prüfen</button></div>${cardExtras(w)}</div>`;
  $('#answerBtn').onclick=()=>gradeText(w,$('#answerField').value,w.term,'context','context'); $('#answerField').onkeydown=e=>{if(e.key==='Enter')$('#answerBtn').click()};
}
function wordLearningCard(w,compact=false){return `<div class="learning-card"><div><small>Wort</small><strong>${esc(w.term)}</strong>${w.extra?` · ${esc(w.extra)}`:''}</div><div><small>Bedeutung</small>${esc(w.translation)}</div>${w.example?`<div><small>Kontext</small>${esc(w.example)}</div>`:''}${w.mnemonic?`<div><small>Wortkniff / Eselsbrücke</small>${esc(w.mnemonic)}</div>`:''}${!compact?`<div><small>Bausteine</small>${esc((w.chunks?.length?w.chunks:autoChunks(w.term)).join(' · '))}</div>`:''}</div>`}
function renderChunks(w){
  const chunks=(w.chunks?.length?w.chunks:autoChunks(w.term)).filter(Boolean); const shuffled=shuffle(chunks.map((x,i)=>({x,i,key:uid('c')}))); session.chunkBuilt=[];
  $('#studyArea').innerHTML=`<div class="study-card"><div class="eyebrow">Multisensorisches Schreiben</div><button id="speakBtn" class="secondary">🔊 Anhören</button><div class="study-prompt compact-prompt">${esc(w.translation)}</div><div class="study-sub">Baue das Wort aus seinen Laut-/Wortbausteinen.</div><div id="assembled" class="assembled">&nbsp;</div><div class="word-chunks">${shuffled.map(c=>`<button class="chunk" data-chunk="${esc(c.x)}">${esc(c.x)}</button>`).join('')}</div><div class="row gap center-actions"><button id="chunkReset" class="ghost">Neu</button><button id="chunkCheck" class="primary">Prüfen</button></div>${cardExtras(w)}</div>`;
  $('#speakBtn').onclick=()=>speak(w.term); $$('[data-chunk]').forEach(b=>b.onclick=()=>{if(b.classList.contains('used'))return;b.classList.add('used');session.chunkBuilt.push(b.dataset.chunk);$('#assembled').textContent=session.chunkBuilt.join('')}); $('#chunkReset').onclick=()=>{session.chunkBuilt=[];$$('[data-chunk]').forEach(b=>b.classList.remove('used'));$('#assembled').innerHTML='&nbsp;'}; $('#chunkCheck').onclick=()=>{session.hintUsed=true;session.scaffoldedWords[w.id]=true;gradeText(w,session.chunkBuilt.join(''),w.term,'spelling','spelling')}; setTimeout(()=>speak(w.term),150);
}
function renderFlash(w){
  const speed=learner().lrsMode?Math.max(learner().flashSpeed,2000):learner().flashSpeed; $('#studyArea').innerHTML=`<div class="study-card"><div class="eyebrow">Wortblitz · Genauigkeit vor Tempo</div><button id="speakBtn" class="secondary">🔊 zuerst anhören</button><div id="flashWord" class="flash-word">…</div><div id="flashAnswer" class="hidden"><div class="study-sub">Welche Bedeutung hat das Wort?</div><div class="answer-grid" id="flashOptions"></div></div></div>`; $('#speakBtn').onclick=()=>speak(w.term); speak(w.term);
  setTimeout(()=>{$('#flashWord').textContent=w.term;setTimeout(()=>{$('#flashWord').textContent='';const pool=schoolYearWords().filter(x=>x.id!==w.id);const opts=uniqueOptions(w.translation,shuffle(pool).map(x=>x.translation));$('#flashOptions').innerHTML=opts.map(o=>`<button class="answer-option" data-answer="${esc(o)}">${esc(o)}</button>`).join('');$('#flashAnswer').classList.remove('hidden');$$('#flashOptions [data-answer]').forEach(b=>b.onclick=()=>gradeChoice(b,w,b.dataset.answer,w.translation,'reading',true));},speed)},500);
}
function renderShower(w){
  const all=session.queue.map(id=>state.words.find(x=>x.id===id)).filter(Boolean); $('#studyArea').innerHTML=`<div class="study-card"><div class="eyebrow">Vokabeldusche</div><h2>Anhören und mitlesen</h2><div class="learning-card">${all.map((x,i)=>`<div class="row spread align-center"><span><strong>${esc(x.term)}</strong><br><small>${esc(x.translation)}</small></span><button class="ghost" data-shower="${i}">🔊</button></div>`).join('')}</div><div class="row gap center-actions wrap"><button id="playActiveBtn" class="primary">Aktiv: Bedeutung → Denkpause → Wort</button><button id="playAllBtn" class="secondary">Passiv nacheinander</button><button id="finishShowerBtn" class="ghost">Fertig</button></div><p class="study-sub">Aktiv: Erst Bedeutung hören und im Kopf erinnern; nach kurzer Denkpause folgt die Lösung. Beide Varianten verändern Mastery und Wiederholungsabstände nicht.</p></div>`;
  $$('[data-shower]').forEach(b=>b.onclick=()=>speak(all[+b.dataset.shower].term)); $('#playAllBtn').onclick=()=>speakSequence(all.map(x=>x.term)); $('#playActiveBtn').onclick=()=>speakActiveShower(all); $('#finishShowerBtn').onclick=()=>{recordActivity('shower',{count:all.length});session.index=session.queue.length;renderStudy()};
}
function speechLang(foreign=true){return foreign?(state.activeSubject==='latin'?'la':'en-GB'):'de-DE'}
function makeUtterance(text,foreign=true,rate=null){const u=new SpeechSynthesisUtterance(text);u.lang=speechLang(foreign);u.rate=rate??(learner().lrsMode?.75:.9);return u}
function speak(text){if(!('speechSynthesis'in window))return; speechSynthesis.cancel();speechSynthesis.speak(makeUtterance(text,true))}
function speakSequence(items){if(!('speechSynthesis'in window))return;speechSynthesis.cancel();let i=0;const next=()=>{if(i>=items.length)return;const u=makeUtterance(items[i++],true,learner().lrsMode?.72:.88);u.onend=()=>setTimeout(next,350);speechSynthesis.speak(u)};next()}
function speakActiveShower(words){if(!('speechSynthesis'in window))return;speechSynthesis.cancel();let i=0;const next=()=>{if(i>=words.length)return;const w=words[i++],prompt=makeUtterance(w.translation,false,.85);prompt.onend=()=>setTimeout(()=>{const answer=makeUtterance(w.term,true,learner().lrsMode?.72:.86);answer.onend=()=>setTimeout(next,550);speechSynthesis.speak(answer)},learner().lrsMode?2800:2200);speechSynthesis.speak(prompt)};next()}
function shuffle(a){const x=[...a];for(let i=x.length-1;i>0;i--){const j=Math.floor(Math.random()*(i+1));[x[i],x[j]]=[x[j],x[i]]}return x}
function uniqueOptions(correct,candidates,max=4){const seen=new Set([normalize(correct)]),out=[correct];for(const c of candidates){const k=normalize(c);if(!k||seen.has(k))continue;seen.add(k);out.push(c);if(out.length>=max)break}return shuffle(out)}

function closestTargetForm(answer,target){const parts=String(target||'').split(/\s*[/;]\s*/).filter(Boolean);if(!parts.length)return String(target||'');return parts.sort((a,b)=>levenshtein(answer,a)-levenshtein(answer,b))[0]}
function diffMarkup(value,other){const a=String(value||''),b=String(other||'');let start=0;while(start<a.length&&start<b.length&&a[start].toLowerCase()===b[start].toLowerCase())start++;let ae=a.length-1,be=b.length-1;while(ae>=start&&be>=start&&a[ae].toLowerCase()===b[be].toLowerCase()){ae--;be--}const pre=esc(a.slice(0,start)),mid=esc(a.slice(start,ae+1)),suf=esc(a.slice(ae+1));return `${pre}${mid?`<mark>${mid}</mark>`:'<mark>∅</mark>'}${suf}`}
function errorFeedbackHtml(answer,target){const t=closestTargetForm(answer,target),d=levenshtein(answer,t),near=d>0&&d<=2&&d<=Math.max(1,Math.ceil(normalize(t).length*.25));return `<div class="spelling-feedback"><strong>${near?'Fast richtig – bleibt als Fehler markiert.':'Noch nicht richtig.'}</strong><div><small>Deine Eingabe</small>${diffMarkup(answer,t)}</div><div><small>Richtig</small>${diffMarkup(t,answer)}</div></div>`}
function gradeChoice(btn,w,answer,target,skill,nonEvaluative=false){if(session.locked)return;session.locked=true;const ok=answerMatches(answer,target);btn.classList.add(ok?'correct':'wrong'); if(!ok){$$('[data-answer]').find(b=>answerMatches(b.dataset.answer,target))?.classList.add('correct')} setTimeout(()=>{if(['recognition','listening'].includes(skill))session.scaffoldedWords[w.id]=true;if(nonEvaluative){recordNonEvaluative(w,'flash',ok,skill)}else recordResult(w,ok,skill,ok?null:skill);nextStudy(ok,w)},650)}
function gradeText(w,answer,target,errorType,skill){if(session.locked)return;session.locked=true;const ok=answerMatches(answer,target); const detail=ok?(session.hintUsed?'Richtig mit Hinweis.':'Richtig.'):' '; $('#studyArea .study-card').insertAdjacentHTML('beforeend',`<div class="feedback notice ${ok?'good':'bad'}">${ok?`<strong>${detail}</strong>`:errorFeedbackHtml(answer,target)}${!ok?wordLearningCard(w):''}</div>`); recordResult(w,ok,skill,ok?null:errorType); setTimeout(()=>nextStudy(ok,w),ok?700:2400)}
function recordNonEvaluative(w,mode,ok,skill){w.modesSeen=[...new Set([...(w.modesSeen||[]),mode])];recordActivity(mode,{wordId:w.id,correct:ok});session.answered++;if(ok)session.correct++}
function isActiveSkill(skill){return ['retrieval','spelling','context'].includes(skill)}
function skillCredits(skill){if(skill==='retrieval'&&session?.currentSubmode==='reverseRecall')return ['retrieval'];if(skill==='retrieval')return ['retrieval','spelling'];if(skill==='spelling')return ['spelling','listening'];if(skill==='context')return ['context','retrieval','spelling'];return [skill]}
function recordResult(w,ok,skill,errorType){
  w.repetitions++; w.lastReviewedAt=new Date().toISOString(); w.practiceDays=[...new Set([...(w.practiceDays||[]),today()])]; w.modesSeen=[...new Set([...(w.modesSeen||[]),session.currentSubmode||session.mode])];
  const assisted=!!(ok&&session.hintUsed),active=isActiveSkill(skill),now=new Date().toISOString(),firstActiveToday=active&&!(w.activePracticeDays||[]).includes(today()),cold=active&&!assisted&&skill!=='spelling'&&firstActiveToday&&!session.scaffoldedWords?.[w.id];
  if(active){session.activeAttemptedWords[w.id]=true;if(!assisted)w.activePracticeDays=[...new Set([...(w.activePracticeDays||[]),today()])];w.recentActiveResults=[...(w.recentActiveResults||[]),!!ok].slice(-8)}
  if(ok){
    w.successes++; w.lastSuccessAt=now; skillCredits(skill).forEach((k,i)=>{const gain=(assisted?.5:1)*(i===0?1:.55);w.skills[k]=clamp((w.skills[k]||0)+gain,0,4)});
    if(active&&assisted){w.assistedSuccesses=(w.assistedSuccesses||0)+1;w.intervalDays=Math.min(Math.max(w.intervalDays||0,1),1);w.dueDate=datePlusDays(1);learner().xp+=1;}
    else if(active){
      const previousDay=w.lastActiveSuccessAt?dateKey(new Date(w.lastActiveSuccessAt)):null,gap=previousDay?Math.max(0,dayNumber(today())-dayNumber(previousDay)):0;
      w.independentSuccesses=(w.independentSuccesses||0)+1;w.activeSuccessDays=[...new Set([...(w.activeSuccessDays||[]),today()])];w.maxActiveGapDays=Math.max(Number(w.maxActiveGapDays)||0,gap);w.lastActiveSuccessAt=now;
      if(cold){w.coldRecallDays=[...new Set([...(w.coldRecallDays||[]),today()])];w.coldRecallSuccesses=(w.coldRecallSuccesses||0)+1;}
      const seq=[0,1,3,7,14,30,60],acc=recentActiveAccuracy(w);let idx=Math.max(1,(w.independentSuccesses||0)-w.failures);if(cold&&acc!==null&&acc>=.85)idx+=1;if(acc!==null&&acc<.65)idx=Math.min(idx,1);w.intervalDays=seq[Math.min(seq.length-1,idx)];w.dueDate=datePlusDays(w.intervalDays);learner().xp+=3;
    }else{learner().xp+=1;session.scaffoldedWords[w.id]=true;}
    session.correct++;
  } else {
    w.failures++;skillCredits(skill).forEach((k,i)=>{w.skills[k]=clamp((w.skills[k]||0)-(i===0?1:.35),0,4)});if(errorType)w.errorProfile[errorType]=(w.errorProfile[errorType]||0)+1;
    if(active){w.intervalDays=0;w.dueDate=today();}
  }
  session.answered++;refreshMastery(w);recordActivity(session.currentSubmode||session.mode,{wordId:w.id,correct:ok,errorType,assisted,active,cold});persistOnly();
}
function scheduleRetry(targetSession,wordId){const n=targetSession.retryCounts[wordId]||0;if(n>=1)return false;targetSession.retryCounts[wordId]=n+1;const pos=Math.min(targetSession.index+3,targetSession.queue.length);targetSession.queue.splice(pos,0,wordId);return true;}
function scheduleScaffoldFollowup(targetSession,wordId){targetSession.followupCounts=targetSession.followupCounts||{};const n=targetSession.followupCounts[wordId]||0;if(n>=2)return false;targetSession.followupCounts[wordId]=n+1;const pos=Math.min(targetSession.index+3,targetSession.queue.length);targetSession.queue.splice(pos,0,wordId);return true;}
function nextStudy(ok,w){
  if(!ok && w && !['flash','shower'].includes(session.mode))scheduleRetry(session,w.id);
  if(ok&&w&&session.mode==='adaptive'&&['recognition','listening','chunks'].includes(session.currentSubmode))scheduleScaffoldFollowup(session,w.id);
  session.index++;renderStudy();
}
function finishSession(){
  if(session?.mode==='practiceTest')return finishPracticeTest();
  const c=session?.correct||0,a=session?.answered||0,isDaily=!!session?.isDaily,plan=isDaily?buildDailyPlan():null,status=plan?dailyPlanStatus(plan):null; const more=status?.remaining>0;
  $('#studyArea').innerHTML=`<div class="study-card"><div class="eyebrow">Einheit beendet</div><div class="study-prompt">${a?Math.round(c/a*100):'✓'}${a?'%':''}</div><p>${a?`${c} von ${a} Aufgaben richtig.`:'Training abgeschlossen.'}</p>${isDaily?`<p class="notice ${more?'subtle':'good'}">${more?`Noch ${status.remaining} Vokabel${status.remaining===1?'':'n'} im Tagesziel.`:'Tagesziel für heute geschafft.'}</p>`:''}<div class="row gap center-actions wrap">${more?'<button id="continueDailyBtn" class="primary">Nächste kurze Einheit</button>':''}<button id="doneBtn" class="${more?'secondary':'primary'}">Zur Übersicht</button></div></div>`;
  $('#sessionPill').textContent='Fertig'; $('#continueDailyBtn')?.addEventListener('click',()=>{session=null;startDailyTodo()}); $('#doneBtn').onclick=()=>{session=null;showView('homeView');renderAll()}; persistOnly();
}
