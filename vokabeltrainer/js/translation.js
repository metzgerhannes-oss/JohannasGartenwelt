'use strict';

/*
  Hybrid translation helper for OCR import.
  Priority:
  1) exact pairs already recognized in the current scan
  2) learner's existing vocabulary (personal translation memory)
  3) compact school vocabulary bundled with the app
  4) on-demand CC0 Wikidict shards hosted with the app
  Never overwrites an already complete OCR pair.
*/

const HYBRID_SCHOOL_DE_EN = {
  'willkommen':'welcome','willkommen bei':'welcome to','willkommen in':'welcome to',
  'hallo':'Hello.','hi':'Hi.','ich bin':'I am','ich heiße':'My name is',
  'der':'the','die':'the','das':'the','der die das':'the',
  'fledermaus':'bat','nett dich kennen zu lernen':'Nice to meet you.',
  'nett dich kennenzulernen':'Nice to meet you.','wie heißt du':'What’s your name?',
  'ich mag':'I like','englisch':'English','hallo grüß dich':'Hello there.',
  'musik':'music','und du':'And you?','sport':'sport','tier':'animal',
  'freund':'friend','freundin':'friend','schule':'school','lehrer':'teacher',
  'lehrerin':'teacher','klasse':'class','buch':'book','heft':'exercise book',
  'stift':'pen','bleistift':'pencil','radiergummi':'rubber','lineal':'ruler',
  'tasche':'bag','schultasche':'school bag','haus':'house','zimmer':'room',
  'familie':'family','mutter':'mother','vater':'father','bruder':'brother',
  'schwester':'sister','hund':'dog','katze':'cat','pferd':'horse','maus':'mouse',
  'vogel':'bird','fisch':'fish','essen':'food','wasser':'water','milch':'milk',
  'brot':'bread','apfel':'apple','banane':'banana','tag':'day','morgen':'morning',
  'abend':'evening','heute':'today','morgen früh':'tomorrow morning',
  'montag':'Monday','dienstag':'Tuesday','mittwoch':'Wednesday','donnerstag':'Thursday',
  'freitag':'Friday','samstag':'Saturday','sonntag':'Sunday',
  'rot':'red','blau':'blue','grün':'green','gelb':'yellow','schwarz':'black','weiß':'white',
  'groß':'big','klein':'small','gut':'good','schlecht':'bad','neu':'new','alt':'old',
  'ja':'yes','nein':'no','bitte':'please','danke':'thank you','danke schön':'thank you',
  'wer':'who','was':'what','wo':'where','wann':'when','warum':'why','wie':'how',
  'mein':'my','meine':'my','dein':'your','deine':'your','unser':'our','unsere':'our',
  'ich':'I','du':'you','er':'he','sie':'she','wir':'we','ihr':'you','sie plural':'they',
  'sein':'be','haben':'have','gehen':'go','kommen':'come','machen':'do','spielen':'play',
  'lernen':'learn','lesen':'read','schreiben':'write','sprechen':'speak','sehen':'see',
  'hören':'hear','mögen':'like','lieben':'love','wohnen':'live','heißen':'be called'
};
const HYBRID_SCHOOL_EN_DE = Object.fromEntries(
  Object.entries(HYBRID_SCHOOL_DE_EN).map(([de,en])=>[hybridNormalize(en),de])
);

const hybridShardCache = new Map();

function hybridNormalize(value){
  return String(value||'')
    .normalize('NFKC')
    .toLowerCase()
    .replace(/[’‘`´]/g,"'")
    .replace(/[(){}\[\]]/g,' ')
    .replace(/[.,!?;:]+/g,' ')
    .replace(/ä/g,'ae').replace(/ö/g,'oe').replace(/ü/g,'ue').replace(/ß/g,'ss')
    .replace(/\s+/g,' ')
    .trim();
}
function hybridShardKey(value){
  const key=hybridNormalize(value).replace(/[^a-z0-9]/g,'');
  if(!key)return '__';
  const first=key[0], second=key[1]||'_';
  let bucket='_';
  if(/[a-d]/.test(second))bucket='a';
  else if(/[e-h]/.test(second))bucket='e';
  else if(/[i-l]/.test(second))bucket='i';
  else if(/[m-p]/.test(second))bucket='m';
  else if(/[q-t]/.test(second))bucket='q';
  else if(/[u-x]/.test(second))bucket='u';
  else if(/[y-z0-9]/.test(second))bucket='y';
  return `${first}${bucket}`;
}
function hybridExistingWords(){
  const learnerId=state?.activeLearnerId, subject=state?.activeSubject;
  const setIds=new Set((state?.sets||[]).filter(s=>s.learnerId===learnerId&&s.subject===subject).map(s=>s.id));
  return (state?.words||[]).filter(w=>setIds.has(w.setId));
}
function hybridMemoryLookup(value,direction,scanRows=[]){
  const q=hybridNormalize(value); if(!q)return '';
  const candidates=[];
  for(const r of (scanRows||[])){
    if(!r?.term||!r?.translation)continue;
    if(direction==='de-en' && hybridNormalize(r.translation)===q)candidates.push(r.term);
    if(direction==='en-de' && hybridNormalize(r.term)===q)candidates.push(r.translation);
  }
  for(const w of hybridExistingWords()){
    if(direction==='de-en' && hybridNormalize(w.translation)===q)candidates.push(w.term);
    if(direction==='en-de' && hybridNormalize(w.term)===q)candidates.push(w.translation);
  }
  return candidates.find(Boolean)||'';
}
function hybridCoreLookup(value,direction){
  const q=hybridNormalize(value); if(!q)return '';
  if(direction==='de-en')return HYBRID_SCHOOL_DE_EN[q]||'';
  return HYBRID_SCHOOL_EN_DE[q]||'';
}
async function loadHybridShard(direction,value){
  const shard=hybridShardKey(value), cacheKey=`${direction}:${shard}`;
  if(hybridShardCache.has(cacheKey))return hybridShardCache.get(cacheKey);
  const promise=(async()=>{
    try{
      const url=`dict/wikidict/${direction}/${shard}.json?v=1`;
      const response=await fetch(url,{cache:'force-cache'});
      if(!response.ok)return {};
      const data=await response.json();
      return data&&typeof data==='object'?data:{};
    }catch(_e){return {};}
  })();
  hybridShardCache.set(cacheKey,promise);
  return promise;
}
async function hybridDictionaryLookup(value,direction){
  const q=hybridNormalize(value); if(!q||q.length<2)return '';
  // Wikidict is most useful for words/concepts, not long free-form sentences.
  if(q.split(' ').length>6||q.length>70)return '';
  const shard=await loadHybridShard(direction,value);
  const found=shard[q];
  if(Array.isArray(found))return String(found[0]||'').trim();
  return typeof found==='string'?found.trim():'';
}
async function hybridTranslate(value,direction,scanRows=[]){
  const memory=hybridMemoryLookup(value,direction,scanRows);
  if(memory)return {text:memory,source:'memory'};
  const core=hybridCoreLookup(value,direction);
  if(core)return {text:core,source:'school'};
  if(state?.activeSubject!=='english')return {text:'',source:''};
  const dict=await hybridDictionaryLookup(value,direction);
  if(dict)return {text:dict,source:'wikidict'};
  return {text:'',source:''};
}
const HYBRID_SUSPICIOUS_GERMAN_LEFT = new Set([
  'der','die','das','ein','eine','einer','einen','einem','eines','und','oder','ich','du','er','sie','wir','ihr',
  'mit','fuer','von','aus','bei','im','in','am','an','auf','zu','zum','zur','ist','sind','bin','bist'
]);

async function repairSuspiciousCompletePair(row){
  if(state?.activeSubject!=='english'||!row?.term||!row?.translation)return false;
  const termKey=hybridNormalize(row.term);
  if(!HYBRID_SUSPICIOUS_GERMAN_LEFT.has(termKey))return false;
  // Do not trust the current scan row as translation memory here: it may be the OCR error we are repairing.
  let candidate=hybridCoreLookup(row.translation,'de-en');
  let source=candidate?'school':'';
  if(!candidate){
    const dict=await hybridDictionaryLookup(row.translation,'de-en');
    if(dict){candidate=dict;source='wikidict';}
  }
  if(!candidate||hybridNormalize(candidate)===termKey)return false;
  row.term=candidate;
  row.confidence='auto';
  row.origin='repair';
  row.repairedFrom=termKey;
  return true;
}

async function enrichHybridRows(rows){
  if(!Array.isArray(rows)||!rows.length)return rows||[];
  // Existing complete rows act as translation memory for the same scan, unless the left side is an obvious OCR spillover.
  for(const row of rows){
    if(row.term&&row.translation){
      if(await repairSuspiciousCompletePair(row))continue;
      row.origin=row.origin||'ocr';
      row.confidence=row.confidence==='check'?'check':'good';
      continue;
    }
    if(state?.activeSubject==='english'){
      if(!row.term&&row.translation){
        const hit=await hybridTranslate(row.translation,'de-en',rows);
        if(hit.text){
          row.term=hit.text; row.confidence='auto'; row.origin=hit.source;
        }
      }else if(row.term&&!row.translation){
        const hit=await hybridTranslate(row.term,'en-de',rows);
        if(hit.text){
          row.translation=hit.text; row.confidence='auto'; row.origin=hit.source;
        }
      }
    }else{
      // For Latin, only reuse known learner/scan pairs. Do not invent Latin words from German.
      if(!row.term&&row.translation){
        const hit=hybridMemoryLookup(row.translation,'de-en',rows);
        if(hit){row.term=hit;row.confidence='auto';row.origin='memory';}
      }else if(row.term&&!row.translation){
        const hit=hybridMemoryLookup(row.term,'en-de',rows);
        if(hit){row.translation=hit;row.confidence='auto';row.origin='memory';}
      }
    }
    if(!(row.term&&row.translation)){
      row.confidence='check'; row.origin=row.origin||'open';
    }
  }
  return rows;
}