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
  const rows=parseCsv(text);if(!rows.length){toast('CSV enthält keine Daten.','warn');return}
  const keys=new Set(Object.keys(rows[0]||{}));if(!keys.has('term')||!keys.has('translation')){toast('CSV benötigt die Spalten „term“ und „translation“.','bad');return}
  let linked=0,existingGlobal=0,newGlobal=0,duplicates=0,skipped=0;
  const setIndex=new Map(mySets().map(s=>[`${s.subject}\u0000${s.schoolYear}\u0000${s.title}`,s]));
  rows.forEach(r=>{
    const subj=(r.subject||state.activeSubject).toLowerCase().startsWith('la')?'latin':'english';if(subj!==state.activeSubject){skipped++;return}
    const term=safeText(r.term,300).trim(),translation=safeText(r.translation,700).trim();if(!term||!translation){skipped++;return}
    const importYear=safeText(r.schoolyear||currentSchoolYear(),24),title=safeText(r.set||'Import',200)||'Import',setKey=`${subj}\u0000${importYear}\u0000${title}`;let set=setIndex.get(setKey);
    if(!set){set={id:uid('set'),learnerId:learner().id,subject:subj,title,schoolYear:importYear,testDate:'',testScopeMode:'set',testFrom:1,testTo:0,testFormat:'target',from:'',to:''};state.sets.push(set);setIndex.set(setKey,set);rebuildWordIndexes();}
    const result=attachVocabularyToSet(set.id,{term,translation,extra:safeText(r.extra,700),example:safeText(r.example,2000),mnemonic:safeText(r.mnemonic,1200),chunks:safeText(r.chunks,3000).split('|').slice(0,30).map(x=>safeText(x.trim(),120)).filter(Boolean),source:'csv-import',verified:true});
    if(result.alreadyLinked){duplicates++;return}linked++;if(result.newVocabulary)newGlobal++;else existingGlobal++;
  });
  save();toast(`${linked} Zuordnung${linked===1?'':'en'} importiert · ${newGlobal} neue globale Vokabel${newGlobal===1?'':'n'}${existingGlobal?` · ${existingGlobal} aus Bibliothek`:''}${duplicates?` · ${duplicates} bereits im Lernset`:''}${skipped?` · ${skipped} ausgelassen`:''}.`,linked?'good':'warn');
}


function cleanImportText(text){
  return String(text||'')
    .replace(/\r/g,'')
    .replace(/[\u00A0\u202F]/g,' ')
    .replace(/[•·▪◦]/g,' ')
    .split('\n')
    .map(x=>x.replace(/[ \f\v]{3,}/g,'  ').replace(/ *\t */g,'\t').trim())
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
function makeImportRow(term,translation,extra='',example='',confidence='check',origin='ocr'){
  const tx=splitTermExtra(term,state.activeSubject);
  return {term:tx.term,translation:String(translation||'').trim(),extra:String(extra||tx.extra||'').trim(),example:String(example||'').trim(),include:true,confidence,origin};
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
function scanOcrProgress(progress=0,label=''){
  const wrap=$('#scanOcrWrap'),bar=$('#scanOcrProgress'),txt=$('#scanOcrLabel');
  if(!wrap||!bar||!txt)return;
  wrap.classList.remove('hidden');
  bar.value=clamp(Number(progress)||0,0,1); txt.textContent=label||'OCR wird vorbereitet …';
}
function scanReviewHtml(){
  if(!scanImportState.rows.length)return '<p class="notice subtle">Noch keine Vokabelpaare erkannt. Foto aufnehmen oder Text einfügen und analysieren.</p>';
  const badge=r=>{
    if(r.libraryMatchStatus==='existing')return '<span class="pill scan-existing">bereits vorhanden</span>';
    if(r.libraryMatchStatus==='new-meaning')return '<span class="pill scan-existing">vorhanden · neue Bedeutung</span>';
    if(r.confidence==='good')return '<span class="pill scan-good">erkannt</span>';
    if(r.confidence==='auto'){
      const source={memory:'aus globaler Bibliothek',school:'automatisch ergänzt',wikidict:'Wörterbuch',repair:'OCR korrigiert'}[r.origin]||'automatisch ergänzt';
      return `<span class="pill scan-auto" title="${esc(source)}">ergänzt · prüfen</span>`;
    }
    return '<span class="pill scan-check">prüfen</span>';
  };
  return scanImportState.rows.map((r,i)=>`<article class="scan-row ${r.confidence==='auto'?'scan-row-auto':''}"><div class="row spread align-center"><label class="scan-include"><input type="checkbox" id="scanUse_${i}" ${r.include?'checked':''}> übernehmen</label>${badge(r)}<button type="button" class="ghost" data-scan-remove="${i}">×</button></div><div class="scan-grid"><label>${state.activeSubject==='latin'?'Latein':'Englisch'}<input id="scanTerm_${i}" value="${esc(r.term)}"></label><label>Deutsch<input id="scanTrans_${i}" value="${esc(r.translation)}"></label><label>Zusatzform<input id="scanExtra_${i}" value="${esc(r.extra)}"></label><label>Beispielsatz / Phrase<input id="scanExample_${i}" value="${esc(r.example)}"></label></div>${r.libraryMatchStatus==='existing'?'<div class="microcopy scan-source">Globale Bibliothek: bereits vorhanden. Beim Import wird nur die Zuordnung zum Lernset angelegt.</div>':r.libraryMatchStatus==='new-meaning'?'<div class="microcopy scan-source">Globale Bibliothek: Wort bereits vorhanden. Diese Bedeutung wird als Variante ergänzt.</div>':r.confidence==='auto'?`<div class="microcopy scan-source">${r.origin==='repair'?'OCR-Erkennung anhand der deutschen Bedeutung korrigiert':'Automatisch ergänzt'+(r.origin==='memory'?' aus der globalen Bibliothek':r.origin==='wikidict'?' aus lokalem Wörterbuch':'')}. Bitte kurz prüfen.</div>`:''}</article>`).join('');
}
function renderScanReview(){
  const el=$('#scanReview'); if(!el)return; el.innerHTML=scanReviewHtml();
  $$('[data-scan-remove]').forEach(b=>b.onclick=()=>{scanImportState.rows.splice(Number(b.dataset.scanRemove),1);renderScanReview();scanStatus(`${scanImportState.rows.length} Zeilen zur Kontrolle.`)});
  const btn=$('#scanImportSave'); if(btn)btn.textContent=`Importieren (${scanImportState.rows.length})`;
}
async function analyzeScanText(text,source='Text'){
  const raw=String(text||'').trim();
  if(!raw){
    scanImportState.rows=[];renderScanReview();
    if(scanImportState.ocrBusy) scanStatus('OCR läuft noch. Bitte kurz warten, bis die Erkennung abgeschlossen ist.','subtle');
    else scanStatus('Kein Text erkannt. Foto möglichst gerade, nah und gut beleuchtet aufnehmen.','warn');
    return;
  }
  const parsed=parseVocabularyText(raw,state.activeSubject);
  scanImportState.rows=parsed.rows; scanImportState.titleHint=parsed.titleHint;
  await enrichHybridRows(scanImportState.rows);
  if(parsed.titleHint && ($('#scanNewTitle')?.value==='Foto-Import'||!$('#scanNewTitle')?.value.trim()))$('#scanNewTitle').value=parsed.titleHint;
  renderScanReview();
  const auto=scanImportState.rows.filter(r=>r.confidence==='auto').length;
  const open=scanImportState.rows.filter(r=>!(r.term&&r.translation)).length;
  const message=parsed.rows.length?`${source}: ${parsed.rows.length} Zeilen erkannt${auto?` · ${auto} automatisch ergänzt`:''}${open?` · ${open} noch offen`:''}. Bitte kurz prüfen.`:`${source}: Text erkannt, aber noch keine sicheren Vokabelpaare. Text unten prüfen oder Zeilen manuell ergänzen.`;
  scanStatus(message,parsed.rows.length?'good':'warn');
}
function medianNumber(values){
  const a=values.filter(Number.isFinite).sort((x,y)=>x-y); if(!a.length)return 0;
  const m=Math.floor(a.length/2); return a.length%2?a[m]:(a[m-1]+a[m])/2;
}
function cleanOcrCell(text){
  return String(text||'')
    .replace(/[|¦]+/g,' ')
    .replace(/\s+/g,' ')
    .replace(/^[-–—_=;:,\s]+|[-–—_=;:,\s]+$/g,'')
    .trim();
}
function parseTesseractWords(tsv){
  const raw=String(tsv||'').trim(); if(!raw)return [];
  const rows=raw.split(/\r?\n/); if(rows.length<2)return [];
  const out=[];
  for(const row of rows.slice(1)){
    const c=row.split('\t'); if(c.length<12||Number(c[0])!==5)continue;
    const text=c.slice(11).join('\t').trim(); if(!text)continue;
    const conf=Number(c[10]); if(Number.isFinite(conf)&&conf<18)continue;
    out.push({text,left:Number(c[6])||0,top:Number(c[7])||0,width:Number(c[8])||0,height:Number(c[9])||0,conf:Number.isFinite(conf)?conf:0});
  }
  return out;
}
function groupOcrColumnLines(words,tolerance){
  const groups=[];
  for(const word of [...words].sort((a,b)=>(a.top+a.height/2)-(b.top+b.height/2)||a.left-b.left)){
    const yc=word.top+word.height/2;
    const g=groups.at(-1);
    if(g&&Math.abs(yc-g.yc)<=tolerance){
      g.words.push(word); g.yc=g.words.reduce((sum,w)=>sum+w.top+w.height/2,0)/g.words.length;
    }else groups.push({yc,words:[word]});
  }
  return groups.map(g=>{
    g.words.sort((a,b)=>a.left-b.left);
    return {...g,text:cleanOcrCell(g.words.map(w=>w.text).join(' ')),minX:Math.min(...g.words.map(w=>w.left)),maxX:Math.max(...g.words.map(w=>w.left+w.width))};
  }).filter(g=>g.text);
}
function ocrUiNoise(text){
  return /^(?:übersicht|finden|verwandte(?:s)?|herunterladen|download|suche|search|menü|menu|teilen|share|zurück|weiter|start|home|bookmark|lesezeichen)$/i.test(cleanOcrCell(text));
}
function safeOcrPair(term,translation,subject){
  let a=cleanOcrCell(term),b=cleanOcrCell(translation);
  if(subject==='english'){
    a=a.replace(/^l[’']m\b/i,"I'm").replace(/^I['’]m\s*\(=\s*am\)$/i,"I'm (= I am)");
    if(/^like$/i.test(a)&&/^ich mag[.!]?$/i.test(b))a='I like';
    b=b.replace(/\(beij\/in\)/i,'(bei/in)').replace(/\bPI\./g,'Pl.');
  }
  return makeImportRow(a,b,'','','good');
}
function tesseractTsvToVocabulary(tsv,subject=state.activeSubject){
  const words=parseTesseractWords(tsv); if(!words.length)return {rows:[],text:''};
  const heights=words.map(w=>w.height).filter(h=>h>2); const medianH=Math.max(12,medianNumber(heights)||20);
  const canon=x=>normalize(x).replace(/[^a-zäöüß]/g,'');
  const deutsch=words.filter(w=>canon(w.text)==='deutsch').sort((a,b)=>a.top-b.top)[0];
  const pageWidth=Math.max(...words.map(w=>w.left+w.width));
  const divider=deutsch?Math.max(pageWidth*.36,deutsch.left-Math.max(30,deutsch.width*.30)):pageWidth*.46;
  const dataStart=deutsch?deutsch.top+deutsch.height+Math.max(22,medianH*.8):Math.max(0,Math.min(...words.map(w=>w.top))+medianH*3);
  const noiseToken=w=>(w.height<Math.max(5,medianH*.22)&&!/^\.{2,}$/.test(w.text))||/^[|¦Il1—–_\-]+$/.test(w.text);
  const data=words.filter(w=>w.top>=dataStart&&!noiseToken(w));
  const tolerance=Math.max(13,medianH*.72);
  let left=groupOcrColumnLines(data.filter(w=>w.left<divider),tolerance);
  let right=groupOcrColumnLines(data.filter(w=>w.left>=divider),tolerance);
  left=left.filter(g=>g.minX<divider*.58&&!ocrUiNoise(g.text));
  right=right.filter(g=>g.minX<divider+Math.max(180,(pageWidth-divider)*.38)&&!ocrUiNoise(g.text));

  const records=[]; const usedRight=new Set(); let consecutiveMissing=0;
  const firstY=left[0]?.yc??0;
  const gapStop=Math.max(90,medianH*3.1);
  let parsedLastY=firstY;

  for(let i=0;i<left.length;i++){
    const l=left[i]; if(ocrUiNoise(l.text))break;
    if(i>4 && l.yc-left[i-1].yc>gapStop)break;
    const prev=i?(left[i-1].yc+l.yc)/2:l.yc-medianH*1.7;
    const next=i+1<left.length?(l.yc+left[i+1].yc)/2:l.yc+medianH*1.9;
    const matches=right.map((r,idx)=>({r,idx})).filter(x=>x.r.yc>=prev&&x.r.yc<next&&!ocrUiNoise(x.r.text));
    if(!matches.length){
      parsedLastY=l.yc;
      consecutiveMissing++;
      const term=cleanOcrCell(l.text);
      if(term)records.push({y:l.yc,row:makeImportRow(term,'','','','check','ocr')});
      if(consecutiveMissing>=3&&i>8)break;
      continue;
    }
    consecutiveMissing=0;
    parsedLastY=l.yc;
    matches.forEach(x=>usedRight.add(x.idx));
    const translation=cleanOcrCell(matches.map(x=>x.r.text).join(' '));
    const term=cleanOcrCell(l.text);
    if(!term||!translation||ocrUiNoise(term)||ocrUiNoise(translation))continue;
    if(subject==='english'&&germanScore(term)>2&&foreignScore(term,subject)===0&&records.length>3)break;
    records.push({y:l.yc,row:safeOcrPair(term,translation,subject)});
    if(records.length>=250)break;
  }

  // Preserve German-only rows that OCR saw on the right but lost on the left.
  right.forEach((r,idx)=>{
    if(usedRight.has(idx)||r.yc<firstY-medianH||r.yc>parsedLastY+medianH*1.25||ocrUiNoise(r.text))return;
    const translation=cleanOcrCell(r.text); if(!translation)return;
    const nearLeft=left.some(l=>Math.abs(l.yc-r.yc)<=tolerance*.65);
    if(!nearLeft)records.push({y:r.yc,row:makeImportRow('',translation,'','','check','ocr')});
  });

  records.sort((a,b)=>a.y-b.y);
  const rows=records.map(x=>x.row).slice(0,250);
  const text=rows.map(r=>`${r.term||''}\t${r.translation||''}`).join('\n');
  return {rows,text};
}
function tesseractTsvToText(tsv){
  const parsed=tesseractTsvToVocabulary(tsv,state.activeSubject);
  if(parsed.text)return parsed.text;
  const words=parseTesseractWords(tsv); if(!words.length)return '';
  const tolerance=Math.max(13,(medianNumber(words.map(w=>w.height).filter(h=>h>2))||20)*.72);
  return groupOcrColumnLines(words,tolerance).map(g=>g.text).join('\n');
}
async function prepareOcrImage(file){
  if(!('createImageBitmap' in window))return file;
  try{
    const bitmap=await createImageBitmap(file); const longest=Math.max(bitmap.width,bitmap.height); const scale=longest>2600?2600/longest:Math.min(1.5,2200/longest);
    const width=Math.max(1,Math.round(bitmap.width*scale)),height=Math.max(1,Math.round(bitmap.height*scale));
    const canvas=document.createElement('canvas');canvas.width=width;canvas.height=height;const ctx=canvas.getContext('2d',{willReadFrequently:true});
    ctx.drawImage(bitmap,0,0,width,height);bitmap.close?.();
    const img=ctx.getImageData(0,0,width,height),d=img.data;
    for(let i=0;i<d.length;i+=4){const lum=.299*d[i]+.587*d[i+1]+.114*d[i+2];const v=clamp((lum-128)*1.28+128,0,255);d[i]=d[i+1]=d[i+2]=v;}
    ctx.putImageData(img,0,0);
    return await new Promise(resolve=>canvas.toBlob(blob=>resolve(blob||file),'image/jpeg',.92));
  }catch(e){console.warn('OCR preprocessing',e);return file;}
}
let tesseractLoadPromise=null;
function loadTesseract(){
  if(window.Tesseract?.createWorker)return Promise.resolve(window.Tesseract);
  if(tesseractLoadPromise)return tesseractLoadPromise;
  tesseractLoadPromise=new Promise((resolve,reject)=>{
    const script=document.createElement('script');
    script.src='ocr/tesseract/tesseract.min.js';
    script.async=true; script.crossOrigin='anonymous';
    script.onload=()=>window.Tesseract?.createWorker?resolve(window.Tesseract):reject(new Error('OCR-Bibliothek konnte nicht initialisiert werden.'));
    script.onerror=()=>reject(new Error('OCR-Bibliothek konnte nicht geladen werden. Internetverbindung prüfen.'));
    document.head.appendChild(script);
  });
  return tesseractLoadPromise;
}
function humanOcrStatus(m){
  const p=Number(m?.progress)||0,status=String(m?.status||'');
  const labels={
    'loading tesseract core':'OCR-Engine wird geladen …','initializing tesseract':'OCR wird gestartet …','loading language traineddata':'Sprachmodell wird geladen …',
    'initializing api':'Sprachmodell wird vorbereitet …','recognizing text':'Text wird erkannt …'
  };
  return {progress:p,label:labels[status]||'OCR arbeitet …'};
}
async function runTesseractOcr(file){
  if(scanImportState.ocrBusy||!file)return;
  scanImportState.ocrBusy=true;
  const retry=$('#scanOcrRetry'),analyze=$('#scanAnalyzeBtn');
  if(retry)retry.disabled=true; if(analyze)analyze.disabled=true;
  let watchdog=null;
  try{
    scanStatus('OCR wird auf diesem iPhone gestartet …');scanOcrProgress(.02,'OCR wird vorbereitet …');
    const T=await loadTesseract();
    const prepared=await prepareOcrImage(file);
    const ocrBase=new URL('ocr/',window.location.href);
    const langs=state.activeSubject==='latin'?['lat','deu']:['eng','deu'];
    const createPromise=T.createWorker(langs,T.OEM?.LSTM_ONLY??1,{
      workerPath:new URL('tesseract/worker.min.js',ocrBase).href,
      corePath:new URL('core/tesseract-core-lstm.wasm.js',ocrBase).href,
      langPath:new URL('lang',ocrBase).href.replace(/\/$/,''),
      workerBlobURL:false,
      gzip:false,
      logger:m=>{const x=humanOcrStatus(m);scanOcrProgress(x.progress,x.label)},
      errorHandler:e=>console.warn('OCR worker',e)
    });
    const timeoutPromise=new Promise((_,reject)=>{watchdog=setTimeout(()=>reject(new Error('OCR-Start-Timeout')),45000)});
    const worker=await Promise.race([createPromise,timeoutPromise]);
    if(watchdog){clearTimeout(watchdog);watchdog=null;}
    try{
      await worker.setParameters({preserve_interword_spaces:'1',user_defined_dpi:'300',tessedit_pageseg_mode:String(T.PSM?.SINGLE_COLUMN??4)});
      scanOcrProgress(.18,'Text wird erkannt …');
      const result=await worker.recognize(prepared,{rotateAuto:true},{text:true,tsv:true});
      const table=tesseractTsvToVocabulary(result?.data?.tsv,state.activeSubject);
      const plainText=String(result?.data?.text||'').trim();
      const text=(table.text||tesseractTsvToText(result?.data?.tsv)||plainText).trim();
      if(!text)throw new Error('OCR lieferte keinen Text');
      $('#scanRawText').value=text; scanImportState.nativeOcr=true; scanOcrProgress(1,'OCR abgeschlossen');
      if(table.rows.length){
        scanImportState.rows=table.rows;
        await enrichHybridRows(scanImportState.rows);
        renderScanReview();
        const good=scanImportState.rows.filter(r=>r.confidence==='good'&&r.term&&r.translation).length;
        const auto=scanImportState.rows.filter(r=>r.confidence==='auto'&&r.term&&r.translation).length;
        const open=scanImportState.rows.filter(r=>!(r.term&&r.translation)).length;
        scanStatus(`OCR: ${good} Originalpaare erkannt${auto?` · ${auto} automatisch ergänzt`:''}${open?` · ${open} noch offen`:''}.`,'good');
      }else await analyzeScanText(text,'OCR');
    }finally{await worker.terminate().catch(()=>{});}
  }catch(e){
    if(watchdog){clearTimeout(watchdog);watchdog=null;}
    console.warn('Tesseract OCR',e); scanOcrProgress(0,'OCR konnte nicht abgeschlossen werden');
    const timeout=String(e?.message||e).includes('Timeout');
    scanStatus(timeout?'OCR-Engine startet auf diesem iPhone nicht innerhalb von 45 Sekunden. Bitte Seite neu laden und noch einmal versuchen.':'OCR-Fehler: Die Erkennung konnte auf diesem Gerät nicht abgeschlossen werden. Bitte erneut starten.','warn');
  }finally{
    scanImportState.ocrBusy=false;
    if(retry)retry.disabled=false; if(analyze)analyze.disabled=false;
  }
}

function openScanImport(){
  scanImportState.rows=[]; scanImportState.titleHint=''; scanImportState.nativeOcr=false;scanImportState.ocrBusy=false;scanImportState.lastFile=null;
  if(scanImportState.imageUrl){URL.revokeObjectURL(scanImportState.imageUrl);scanImportState.imageUrl=null;}
  const sets=mySets();
  modal(`<div class="eyebrow">Fotoimport mit OCR</div><h2>Vokabelseite fotografieren</h2><p>Foto aufnehmen oder auswählen. Erkannte Originalpaare bleiben erhalten; fehlende Englisch-/Deutsch-Seiten ergänzt die App soweit möglich automatisch. Automatische Ergänzungen sind immer als „prüfen“ markiert. Das Foto bleibt auf diesem Gerät.</p><div class="scan-layout"><div><div id="scanImageBox" class="scan-image-box"><span>Noch kein Foto</span></div><button type="button" id="scanPhotoBtn" class="primary top-space">📷 Foto aufnehmen / auswählen</button><p class="microcopy">Tipp: Seite gerade, nah und ohne Schatten fotografieren. Die kostenlose OCR-Engine und Sprachmodelle werden vom Vokabeltrainer selbst geladen und anschließend lokal zwischengespeichert.</p></div><div><label>OCR-Text<textarea id="scanRawText" rows="10" placeholder="Der erkannte Text erscheint hier …"></textarea></label><div id="scanOcrWrap" class="ocr-progress hidden"><progress id="scanOcrProgress" max="1" value="0"></progress><span id="scanOcrLabel">OCR wird vorbereitet …</span></div><div class="row gap wrap"><button type="button" id="scanAnalyzeBtn" class="secondary">Text neu analysieren</button><button type="button" id="scanOcrRetry" class="ghost">OCR erneut starten</button><button type="button" id="scanAddRowBtn" class="ghost">+ leere Zeile</button></div><div id="scanStatus" class="notice subtle">Foto auswählen – OCR startet automatisch.</div></div></div><hr><div class="scan-target"><label>Ziel-Lernset<select id="scanSetSelect">${sets.map(s=>`<option value="${s.id}">${esc(s.title)} · ${esc(s.schoolYear)}</option>`).join('')}<option value="__new__" ${sets.length?'':'selected'}>+ Neues Lernset</option></select></label><label id="scanNewTitleWrap" class="${sets.length?'hidden':''}">Titel für neues Lernset<input id="scanNewTitle" value="Foto-Import"></label><label id="scanNewYearWrap" class="${sets.length?'hidden':''}">Schuljahr<input id="scanNewYear" value="${esc(currentSchoolYear())}"></label></div><h3>Kontrolle vor dem Import</h3><div id="scanReview"></div><div class="modal-actions"><button value="cancel" class="ghost">Abbrechen</button><button type="button" id="scanImportSave" class="primary">Importieren (0)</button></div>`);
  renderScanReview();
  const toggleNew=()=>{const show=$('#scanSetSelect').value==='__new__';$('#scanNewTitleWrap').classList.toggle('hidden',!show);$('#scanNewYearWrap').classList.toggle('hidden',!show)};
  $('#scanSetSelect').onchange=toggleNew;
  $('#scanPhotoBtn').onclick=()=>$('#photoInput').click();
  $('#scanAnalyzeBtn').onclick=()=>void analyzeScanText($('#scanRawText').value,'Textanalyse');
  $('#scanOcrRetry').onclick=()=>scanImportState.lastFile?runTesseractOcr(scanImportState.lastFile):scanStatus('Bitte zuerst ein Foto auswählen.','warn');
  $('#scanAddRowBtn').onclick=()=>{scanImportState.rows.push(makeImportRow('','','','','check'));renderScanReview()};
  $('#scanImportSave').onclick=importScannedRows;
}
async function handleScanPhoto(file){
  if(!file || !file.type.startsWith('image/'))return;
  if(file.size>MAX_PHOTO_BYTES){scanStatus('Das Foto ist größer als 20 MB. Bitte ein kleineres Bild verwenden.','warn');return;}
  scanImportState.lastFile=file;
  if(scanImportState.imageUrl)URL.revokeObjectURL(scanImportState.imageUrl);
  scanImportState.imageUrl=URL.createObjectURL(file);
  const box=$('#scanImageBox'); if(box)box.innerHTML=`<img src="${scanImportState.imageUrl}" alt="Ausgewählte Vokabelseite">`;
  $('#scanRawText').value=''; scanImportState.rows=[];renderScanReview();
  await runTesseractOcr(file);
}
function importScannedRows(){
  const rows=scanImportState.rows.map((r,i)=>({include:$(`#scanUse_${i}`)?.checked!==false,term:$(`#scanTerm_${i}`)?.value.trim()||'',translation:$(`#scanTrans_${i}`)?.value.trim()||'',extra:$(`#scanExtra_${i}`)?.value.trim()||'',example:$(`#scanExample_${i}`)?.value.trim()||'',confidence:r.confidence||'check'})).filter(r=>r.include&&r.term&&r.translation);
  if(!rows.length){scanStatus('Es gibt noch keine vollständige Vokabelzeile zum Importieren.','warn');return;}
  let setId=$('#scanSetSelect').value;
  if(setId==='__new__'){const title=$('#scanNewTitle').value.trim()||scanImportState.titleHint||'Foto-Import',schoolYear=$('#scanNewYear').value.trim()||currentSchoolYear();const set={id:uid('set'),learnerId:learner().id,subject:state.activeSubject,title,schoolYear,testDate:'',testScopeMode:'set',testFrom:1,testTo:0,testFormat:'target',from:'',to:''};state.sets.push(set);setId=set.id;rebuildWordIndexes();}
  let linked=0,alreadyLinked=0,newGlobal=0,fromLibrary=0,newMeanings=0;
  rows.forEach(r=>{const result=attachVocabularyToSet(setId,{term:r.term,translation:r.translation,extra:r.extra,example:r.example,chunks:autoChunks(r.term),source:'photo-text-import',verified:true});if(result.alreadyLinked){alreadyLinked++;return}linked++;if(result.newVocabulary)newGlobal++;else fromLibrary++;if(result.translationAdded)newMeanings++;});
  closeModal();if(scanImportState.imageUrl){URL.revokeObjectURL(scanImportState.imageUrl);scanImportState.imageUrl=null;}save();
  toast(`${linked} Zuordnung${linked===1?'':'en'} gespeichert · ${newGlobal} neue globale Vokabel${newGlobal===1?'':'n'}${fromLibrary?` · ${fromLibrary} aus Bibliothek`:''}${newMeanings?` · ${newMeanings} neue Bedeutungsvariante${newMeanings===1?'':'n'}`:''}${alreadyLinked?` · ${alreadyLinked} bereits im Lernset`:''}.`,'good');
}

function backup(){const payload={...deepClone(state),backupMeta:{appVersion:VERSION,exportedAt:new Date().toISOString()}};download(`vokabeltrainer_backup_${today()}.json`,JSON.stringify(payload,null,2),'application/json')}
function backupSummary(x){return {profiles:Array.isArray(x?.learners)?x.learners.length:0,sets:Array.isArray(x?.sets)?x.sets.length:0,words:Array.isArray(x?.vocabulary)?x.vocabulary.length:(Array.isArray(x?.words)?x.words.length:0),links:Array.isArray(x?.setVocabulary)?x.setVocabulary.length:(Array.isArray(x?.words)?x.words.length:0),grades:Array.isArray(x?.grades)?x.grades.length:0}}
function restore(text){
  try{
    const x=JSON.parse(text),issue=inspectBackup(x); if(issue)throw new Error(issue); const b=backupSummary(x),current=backupSummary(state);
    modal(`<div class="eyebrow">Backup einspielen</div><h2>Aktuelle Daten ersetzen?</h2><p>Das Backup enthält <strong>${b.profiles} Profil${b.profiles===1?'':'e'}, ${b.sets} Lernsets und ${b.words} globale Vokabeln</strong>.</p><div class="notice warn">Aktuell auf diesem Gerät: ${current.profiles} Profil${current.profiles===1?'':'e'}, ${current.sets} Lernsets, ${current.words} globale Vokabeln. Diese Daten werden ersetzt.</div><p class="microcopy">Empfehlung: Vorher ein aktuelles Backup herunterladen.</p><div class="modal-actions wrap"><button value="cancel" class="ghost">Abbrechen</button><button type="button" id="backupBeforeRestore" class="secondary">Vorher sichern</button><button type="button" id="confirmRestore" class="primary">Backup einspielen</button></div>`);
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