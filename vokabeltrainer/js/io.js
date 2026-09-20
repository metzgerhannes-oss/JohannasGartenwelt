'use strict';

function exportCsv(){
  const header=['set','subject','schoolYear','term','translation','extra','example','mnemonic','chunks']; const rows=[header.join(';')]; mySets().forEach(s=>setWords(s.id).forEach(w=>rows.push([s.title,s.subject,s.schoolYear,w.term,w.translation,w.extra,w.example,w.mnemonic,(w.chunks||[]).join('|')].map(csvCell).join(';'))));download(`vokabeln_${state.activeSubject}_${today()}.csv`,rows.join('\n'),'text/csv;charset=utf-8')
}
function csvCell(v){const s=String(v??'');return /[;"\n]/.test(s)?`"${s.replace(/"/g,'""')}"`:s}
function detectCsvSeparator(text){
  let semi=0,comma=0,q=false;for(let i=0;i<text.length;i++){const c=text[i];if(c==='"'){if(q&&text[i+1]==='"'){i++;continue}q=!q;continue}if(!q&&(c==='\n'||c==='\r'))break;if(!q&&c===';')semi++;if(!q&&c===',')comma++;}return semi>=comma?';':',';
}
function parseCsv(text){
  const src=String(text||'').replace(/^\uFEFF/,'');if(!src.trim())return[];const sep=detectCsvSeparator(src),rows=[];let row=[],field='',q=false;
  const pushField=()=>{row.push(field);field=''};const pushRow=()=>{pushField();if(row.some(v=>String(v).trim()!==''))rows.push(row);row=[]};
  for(let i=0;i<src.length;i++){
    const c=src[i];
    if(c==='"'){if(q&&src[i+1]==='"'){field+='"';i++;}else q=!q;continue;}
    if(c===sep&&!q){pushField();continue;}
    if((c==='\n'||c==='\r')&&!q){if(c==='\r'&&src[i+1]==='\n')i++;pushRow();continue;}
    field+=c;
  }
  if(field.length||row.length)pushRow();if(rows.length<2)return[];
  const header=rows.shift().map(x=>String(x||'').trim().toLowerCase());
  return rows.slice(0,20000).map(values=>{const o={};header.forEach((k,i)=>{if(k)o[k]=values[i]??''});return o});
}
function importCsv(text){
  const rows=parseCsv(text); if(!rows.length){toast('CSV enthält keine Daten.','warn');return}
  const keys=new Set(Object.keys(rows[0]||{})); if(!keys.has('term')||!keys.has('translation')){toast('CSV benötigt die Spalten „term“ und „translation“.','bad');return}
  let count=0,duplicates=0,skipped=0;
  const setIndex=new Map(mySets().map(s=>[`${s.subject}\u0000${s.schoolYear}\u0000${s.title}`,s]));
  const dupeIndex=new Map();
  for(const set of mySets()){const keys=new Set();for(const w of setWords(set.id))keys.add(`${normalize(w.term)}\u0000${normalize(w.translation)}`);dupeIndex.set(set.id,keys)}
  rows.forEach(r=>{
    const subj=(r.subject||state.activeSubject).toLowerCase().startsWith('la')?'latin':'english'; if(subj!==state.activeSubject){skipped++;return}
    const term=safeText(r.term,300).trim(),translation=safeText(r.translation,700).trim();if(!term||!translation){skipped++;return}
    const importYear=safeText(r.schoolyear||currentSchoolYear(),24),title=safeText(r.set||'Import',200)||'Import',setKey=`${subj}\u0000${importYear}\u0000${title}`;let set=setIndex.get(setKey);
    if(!set){set={id:uid('set'),learnerId:learner().id,subject:subj,title,schoolYear:importYear,testDate:'',testScopeMode:'set',testFrom:1,testTo:0,testFormat:'target',from:'',to:''};state.sets.push(set);setIndex.set(setKey,set);dupeIndex.set(set.id,new Set())}
    const dupeKey=`${normalize(term)}\u0000${normalize(translation)}`,seen=dupeIndex.get(set.id);if(seen.has(dupeKey)){duplicates++;return}seen.add(dupeKey);
    state.words.push(makeWord(set.id,term,translation,{extra:safeText(r.extra,700),example:safeText(r.example,2000),mnemonic:safeText(r.mnemonic,1200),chunks:safeText(r.chunks,3000).split('|').slice(0,30).map(x=>safeText(x.trim(),120)).filter(Boolean)}));count++
  });
  save(); toast(`${count} Vokabeln importiert${duplicates?` · ${duplicates} Dubletten übersprungen`:''}${skipped?` · ${skipped} Zeilen ausgelassen`:''}.`,count?'good':'warn')
}


function cleanImportText(text){
  return String(text||'')
    .replace(/\r/g,'')
    .replace(/[\u00A0\u202F]/g,' ')
    .replace(/[•·▪◦]/g,' ')
    .split('\n')
    .map(x=>x.replace(/[ \f\v]+/g,' ').replace(/ *\t */g,'\t').trim())
    .filter(Boolean);
}
function importTitleHint(lines){
  const candidates=lines.filter(line=>/^(?:camden\s*town\b|unit\s*\d+\b|theme\s*\d+\b|part\s*[a-z0-9]+\s*$|word\s*bank\b|wordbank\b|vocabulary\b|vokabeln\b)/i.test(line));
  const best=candidates.find(x=>x.length<=70)||candidates[0]||'';
  return best.replace(/^[–—\-:|\s]+|[–—\-:|\s]+$/g,'').slice(0,80);
}
function germanScore(text){
  const t=` ${normalize(text)} `; let score=0;
  if(/[äöüß]/i.test(text))score+=3;
  [' der ',' die ',' das ',' ein ',' eine ',' einen ',' einem ',' einer ',' sich ',' jemand ',' jemanden ',' etwas ',' bzw ',' oder ',' zu '].forEach(x=>{if(t.includes(x))score+=1});
  if(/\b(jdn|jdm|etw)\.?\b/i.test(text))score+=2;
  return score;
}
function foreignScore(text,subject){
  const t=` ${normalize(text)} `; let score=0;
  if(subject==='english'){
    [' the ',' to ',' a ',' an ',' is ',' are ',' was ',' were ',' have ',' has ',' with ',' from ',' for ',' of ',' in ',' on ',' at '].forEach(x=>{if(t.includes(x))score+=1});
    if(/\b(to\s+)?[a-z][a-z'-]{2,}\b/i.test(text))score+=1;
  }else{
    if(/\b(us|um|ae|is|ibus|orum|arum|ere|ire|are|ri)\b/i.test(text))score+=1;
    if(/\b[fmna]\.?\b/i.test(text))score+=1;
  }
  return score;
}
function splitImportColumns(line){
  const splitters=[/\t+/,/\s+\|\s+/,/\s+[–—]\s+/,/\s+-\s+/,/\s*=\s*/,/\s{2,}/];
  for(const rx of splitters){
    const parts=line.split(rx).map(x=>x.trim()).filter(Boolean);
    if(parts.length>=2)return parts;
  }
  return [line];
}
function looksLikeExample(text,term,subject){
  const t=String(text||'').trim(); if(!t)return false;
  const words=t.split(/\s+/).length;
  if(/[.!?]$/.test(t)&&words>=3)return true;
  if(term && normalize(t).includes(normalize(term)) && words>=3)return true;
  if(subject==='english' && /\b(the|a|an|to|is|are|was|were|my|your|we|they|he|she)\b/i.test(t) && words>=3)return true;
  return subject==='latin' && words>=3 && !/[=:|]/.test(t);
}
function splitTermExtra(term,subject){
  let value=String(term||'').trim(), extra='';
  if(subject==='latin'){
    const m=value.match(/^([^,;]+)[,;]\s*(.+)$/);
    if(m && m[1].trim().split(/\s+/).length<=3){value=m[1].trim();extra=m[2].trim();}
  }else{
    const m=value.match(/^(.+?)\s*\(([^)]+)\)\s*$/);
    if(m){value=m[1].trim();extra=m[2].trim();}
  }
  return {term:value,extra};
}
function makeImportRow(term,translation,extra='',example='',confidence='check'){
  const tx=splitTermExtra(term,state.activeSubject);
  return {term:tx.term,translation:String(translation||'').trim(),extra:String(extra||tx.extra||'').trim(),example:String(example||'').trim(),include:true,confidence};
}
function parseVocabularyText(text,subject=state.activeSubject){
  const lines=cleanImportText(text); const titleHint=importTitleHint(lines); const rows=[]; const unresolved=[];
  const headingRx=/^(?:camden\s*town\b|unit\s*\d+\b|theme\s*\d+\b|part\s*[a-z0-9]+\s*$|word\s*bank\b|wordbank\b|vocabulary\b|vokabeln\b)/i;
  for(const line of lines){
    if(line.length<2 || /^\d{1,3}$/.test(line) || headingRx.test(line))continue;
    const parts=splitImportColumns(line);
    if(parts.length>=2){
      let left=parts[0],right=parts[1];
      if(germanScore(left)>germanScore(right)+1 && foreignScore(right,subject)>=foreignScore(left,subject)){[left,right]=[right,left];}
      let extra='',example='';
      for(const tail of parts.slice(2)){
        if(!example && looksLikeExample(tail,left,subject))example=tail;
        else if(!extra)extra=tail;
        else example=[example,tail].filter(Boolean).join(' · ');
      }
      rows.push(makeImportRow(left,right,extra,example,'good'));
    }else unresolved.push(line);
  }
  for(let i=0;i<unresolved.length-1;){
    let a=unresolved[i],b=unresolved[i+1];
    const ga=germanScore(a),gb=germanScore(b),fa=foreignScore(a,subject),fb=foreignScore(b,subject);
    if(ga>gb+1 || fb>fa+1){[a,b]=[b,a];}
    rows.push(makeImportRow(a,b,'','','check')); i+=2;
  }
  return {titleHint,rows};
}
function scanStatus(text,type='subtle'){
  const el=$('#scanStatus'); if(!el)return; el.className=`notice ${type}`; el.textContent=text;
}
function scanReviewHtml(){
  if(!scanImportState.rows.length)return '<p class="notice subtle">Noch keine Vokabelpaare erkannt. Text übernehmen und „Text analysieren“ wählen.</p>';
  return scanImportState.rows.map((r,i)=>`<article class="scan-row"><div class="row spread align-center"><label class="scan-include"><input type="checkbox" id="scanUse_${i}" ${r.include?'checked':''}> übernehmen</label><span class="pill ${r.confidence==='good'?'scan-good':''}">${r.confidence==='good'?'erkannt':'prüfen'}</span><button type="button" class="ghost" data-scan-remove="${i}">×</button></div><div class="scan-grid"><label>${state.activeSubject==='latin'?'Latein':'Englisch'}<input id="scanTerm_${i}" value="${esc(r.term)}"></label><label>Deutsch<input id="scanTrans_${i}" value="${esc(r.translation)}"></label><label>Zusatzform<input id="scanExtra_${i}" value="${esc(r.extra)}"></label><label>Beispielsatz / Phrase<input id="scanExample_${i}" value="${esc(r.example)}"></label></div></article>`).join('');
}
function renderScanReview(){
  const el=$('#scanReview'); if(!el)return; el.innerHTML=scanReviewHtml();
  $$('[data-scan-remove]').forEach(b=>b.onclick=()=>{scanImportState.rows.splice(Number(b.dataset.scanRemove),1);renderScanReview();scanStatus(`${scanImportState.rows.length} Zeilen zur Kontrolle.`)});
  const btn=$('#scanImportSave'); if(btn)btn.textContent=`Importieren (${scanImportState.rows.length})`;
}
function openScanImport(){
  scanImportState.rows=[]; scanImportState.titleHint=''; scanImportState.nativeOcr=false;
  if(scanImportState.imageUrl){URL.revokeObjectURL(scanImportState.imageUrl);scanImportState.imageUrl=null;}
  const sets=mySets();
  modal(`<div class="eyebrow">Foto-/Textimport</div><h2>Vokabelseite übernehmen</h2><p>Für eigene Schulbuchseiten: Foto lokal aufnehmen, Text mit iOS Live Text / „Text scannen“ übernehmen und vor dem Speichern kontrollieren. Das Foto wird nicht hochgeladen und nicht gespeichert.</p><div class="scan-layout"><div><div id="scanImageBox" class="scan-image-box"><span>Noch kein Foto</span></div><button type="button" id="scanPhotoBtn" class="secondary top-space">Foto aufnehmen / auswählen</button><p class="microcopy">Wenn der Browser native Texterkennung anbietet, versucht die App sie lokal. Auf dem iPhone: in das Textfeld tippen und „Text scannen“ verwenden oder Live Text aus Fotos kopieren.</p></div><div><label>Erkannter / kopierter Text<textarea id="scanRawText" rows="10" placeholder="Hier den erkannten Text einfügen …"></textarea></label><div class="row gap wrap"><button type="button" id="scanAnalyzeBtn" class="primary">Text analysieren</button><button type="button" id="scanAddRowBtn" class="ghost">+ leere Zeile</button></div><div id="scanStatus" class="notice subtle">Noch keine Analyse.</div></div></div><hr><div class="scan-target"><label>Ziel-Lernset<select id="scanSetSelect">${sets.map(s=>`<option value="${s.id}">${esc(s.title)} · ${esc(s.schoolYear)}</option>`).join('')}<option value="__new__" ${sets.length?'':'selected'}>+ Neues Lernset</option></select></label><label id="scanNewTitleWrap" class="${sets.length?'hidden':''}">Titel für neues Lernset<input id="scanNewTitle" value="Foto-Import"></label><label id="scanNewYearWrap" class="${sets.length?'hidden':''}">Schuljahr<input id="scanNewYear" value="${esc(currentSchoolYear())}"></label></div><h3>Kontrolle vor dem Import</h3><div id="scanReview"></div><div class="modal-actions"><button value="cancel" class="ghost">Abbrechen</button><button type="button" id="scanImportSave" class="primary">Importieren (0)</button></div>`);
  renderScanReview();
  const toggleNew=()=>{const show=$('#scanSetSelect').value==='__new__';$('#scanNewTitleWrap').classList.toggle('hidden',!show);$('#scanNewYearWrap').classList.toggle('hidden',!show)};
  $('#scanSetSelect').onchange=toggleNew;
  $('#scanPhotoBtn').onclick=()=>$('#photoInput').click();
  $('#scanAnalyzeBtn').onclick=()=>{const parsed=parseVocabularyText($('#scanRawText').value,state.activeSubject);scanImportState.rows=parsed.rows;scanImportState.titleHint=parsed.titleHint;if(parsed.titleHint && ($('#scanNewTitle').value==='Foto-Import'||!$('#scanNewTitle').value.trim()))$('#scanNewTitle').value=parsed.titleHint;renderScanReview();const message=parsed.rows.length?`${parsed.rows.length} mögliche Vokabelpaare erkannt. Bitte jede Zeile kurz prüfen.`:'Keine sicheren Paare erkannt. Text ggf. zeilenweise als Fremdsprache – Deutsch einfügen.';scanStatus(message,parsed.rows.length?'good':'warn')};
  $('#scanAddRowBtn').onclick=()=>{scanImportState.rows.push(makeImportRow('','','','','check'));renderScanReview()};
  $('#scanImportSave').onclick=importScannedRows;
}
async function handleScanPhoto(file){
  if(!file || !file.type.startsWith('image/'))return;
  if(file.size>MAX_PHOTO_BYTES){scanStatus('Das Foto ist größer als 20 MB. Bitte ein kleineres Bild verwenden.','warn');return;}
  if(scanImportState.imageUrl)URL.revokeObjectURL(scanImportState.imageUrl);
  scanImportState.imageUrl=URL.createObjectURL(file);
  const box=$('#scanImageBox'); if(box)box.innerHTML=`<img src="${scanImportState.imageUrl}" alt="Ausgewählte Vokabelseite">`;
  scanStatus('Foto lokal geladen. Keine Übertragung an einen Server.');
  if('TextDetector' in window && 'createImageBitmap' in window){
    try{
      scanStatus('Foto lokal geladen. Native Texterkennung läuft …');
      const bitmap=await createImageBitmap(file); const detector=new window.TextDetector(); const found=await detector.detect(bitmap); bitmap.close?.();
      const text=found.map(x=>x.rawValue||x.text||'').filter(Boolean).join('\n');
      if(text.trim()){scanImportState.nativeOcr=true;$('#scanRawText').value=text;scanStatus('Text lokal erkannt. Jetzt „Text analysieren“ wählen.','good');}
      else scanStatus('Foto geladen. Wenn iOS „Text scannen“ anbietet, den Text damit in das Feld übernehmen – alternativ Live Text aus Fotos kopieren.','subtle');
    }catch(e){scanStatus('Foto geladen. Wenn iOS „Text scannen“ anbietet, den Text damit in das Feld übernehmen – alternativ Live Text aus Fotos kopieren.','subtle');}
  }else scanStatus('Foto geladen. Wenn iOS „Text scannen“ anbietet, den Text damit in das Feld übernehmen – alternativ Live Text aus Fotos kopieren.','subtle');
}
function importScannedRows(){
  const rows=scanImportState.rows.map((r,i)=>({
    include:$(`#scanUse_${i}`)?.checked!==false,
    term:$(`#scanTerm_${i}`)?.value.trim()||'', translation:$(`#scanTrans_${i}`)?.value.trim()||'',
    extra:$(`#scanExtra_${i}`)?.value.trim()||'', example:$(`#scanExample_${i}`)?.value.trim()||''
  })).filter(r=>r.include&&r.term&&r.translation);
  if(!rows.length){scanStatus('Es gibt noch keine vollständige Vokabelzeile zum Importieren.','warn');return;}
  let setId=$('#scanSetSelect').value;
  if(setId==='__new__'){
    const title=$('#scanNewTitle').value.trim()||scanImportState.titleHint||'Foto-Import'; const schoolYear=$('#scanNewYear').value.trim()||currentSchoolYear();
    const set={id:uid('set'),learnerId:learner().id,subject:state.activeSubject,title,schoolYear,testDate:'',testScopeMode:'set',testFrom:1,testTo:0,testFormat:'target',from:'',to:''};state.sets.push(set);setId=set.id;
  }
  const existing=setWords(setId); let added=0,duplicates=0;
  rows.forEach(r=>{
    const dupe=existing.some(w=>normalize(w.term)===normalize(r.term)&&normalize(w.translation)===normalize(r.translation));
    if(dupe){duplicates++;return;}
    const w=makeWord(setId,r.term,r.translation,{extra:r.extra,example:r.example,chunks:autoChunks(r.term)}); w.source='photo-text-import'; state.words.push(w);existing.push(w);added++;
  });
  closeModal(); if(scanImportState.imageUrl){URL.revokeObjectURL(scanImportState.imageUrl);scanImportState.imageUrl=null;} save();
  toast(`${added} Vokabeln importiert${duplicates?` · ${duplicates} Dublette${duplicates===1?'':'n'} übersprungen`:''}.`,'good');
}

function backup(){const payload={...deepClone(state),backupMeta:{appVersion:VERSION,exportedAt:new Date().toISOString()}};download(`vokabeltrainer_backup_${today()}.json`,JSON.stringify(payload,null,2),'application/json')}
function backupSummary(x){return {profiles:Array.isArray(x.learners)?x.learners.length:0,sets:Array.isArray(x.sets)?x.sets.length:0,words:Array.isArray(x.words)?x.words.length:0,grades:Array.isArray(x.grades)?x.grades.length:0}}
function restore(text){
  try{
    const x=JSON.parse(text),issue=inspectBackup(x); if(issue)throw new Error(issue); const b=backupSummary(x),current=backupSummary(state);
    modal(`<div class="eyebrow">Backup einspielen</div><h2>Aktuelle Daten ersetzen?</h2><p>Das Backup enthält <strong>${b.profiles} Profil${b.profiles===1?'':'e'}, ${b.sets} Lernsets und ${b.words} Vokabeln</strong>.</p><div class="notice warn">Aktuell auf diesem Gerät: ${current.profiles} Profil${current.profiles===1?'':'e'}, ${current.sets} Lernsets, ${current.words} Vokabeln. Diese Daten werden ersetzt.</div><p class="microcopy">Empfehlung: Vorher ein aktuelles Backup herunterladen.</p><div class="modal-actions wrap"><button value="cancel" class="ghost">Abbrechen</button><button type="button" id="backupBeforeRestore" class="secondary">Vorher sichern</button><button type="button" id="confirmRestore" class="primary">Backup einspielen</button></div>`);
    $('#backupBeforeRestore').onclick=backup;
    $('#confirmRestore').onclick=async()=>{const btn=$('#confirmRestore');btn.disabled=true;btn.textContent='Wird gespeichert …';const previous=state;state=migrate(x);const ok=await persistState();let verified=ok;if(ok&&persistenceMode==='indexeddb'){try{const check=await idbGet();verified=!!check&&backupSummary(check).words===backupSummary(state).words&&backupSummary(check).sets===backupSummary(state).sets}catch(e){verified=false}}if(!verified){state=previous;await persistState();btn.disabled=false;btn.textContent='Backup einspielen';toast('Backup konnte nicht sicher gespeichert werden. Aktuelle Daten wurden beibehalten.','bad');return}closeModal();renderAll();toast('Backup vollständig geprüft und eingespielt.','good')};
  }catch(e){console.warn(e);toast(e?.message||'Backup ist ungültig oder konnte nicht gelesen werden.','bad')}
}
async function resetAppData(){
  modal(`<div class="eyebrow">Gefahrenbereich</div><h2>Alle App-Daten löschen</h2><p>Profile, Vokabeln, Lernfortschritt und Noten werden auf diesem Gerät gelöscht. Ein vorhandenes Backup kann später wieder eingespielt werden.</p><label>Zur Bestätigung <strong>LÖSCHEN</strong> eingeben<input id="resetConfirm" autocomplete="off"></label><div class="modal-actions"><button value="cancel" class="ghost">Abbrechen</button><button type="button" id="confirmReset" class="danger-btn" disabled>Alles löschen</button></div>`);
  const input=$('#resetConfirm'),btn=$('#confirmReset'); input.oninput=()=>btn.disabled=input.value.trim().toUpperCase()!=='LÖSCHEN';
  btn.onclick=async()=>{await persistChain.catch(()=>{});try{if(persistenceMode==='indexeddb')await idbClear();else localStorage.removeItem(STORAGE_KEY)}catch(e){console.warn(e)}state=defaultState();await persistState();closeModal();showView('homeView');renderAll();toast('App-Daten wurden zurückgesetzt.','good')};
}
function stateBytes(){try{return new Blob([JSON.stringify(state)]).size}catch(e){return 0}}
function fmtBytes(n){if(n<1024)return `${n} B`;if(n<1024*1024)return `${(n/1024).toFixed(1)} KB`;return `${(n/1024/1024).toFixed(2)} MB`}
async function renderStorageStatus(){
  const el=$('#storageStatus'); if(!el)return; const own=stateBytes(); let extra='';
  if(navigator.storage?.estimate){try{const est=await navigator.storage.estimate();if(est.usage&&est.quota)extra=` · Browser gesamt ${fmtBytes(est.usage)} von ${fmtBytes(est.quota)}`}catch(e){}}
  el.className='notice subtle';el.textContent=`Speicherung: ${persistenceMode==='indexeddb'?'IndexedDB':'localStorage-Fallback'} · App-Daten ca. ${fmtBytes(own)}${extra}`;
}
function download(name,text,type){const blob=new Blob([text],{type});const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(a.href),1000)}