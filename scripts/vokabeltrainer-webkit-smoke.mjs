import { webkit, devices } from 'playwright';

const base=process.env.JGW_BASE||'http://127.0.0.1:4173';
const hardStop=setTimeout(()=>{console.error('FATAL_VOKABELTRAINER_WEBKIT_TIMEOUT');process.exit(1)},60000);
const browser=await webkit.launch({headless:true});
const context=await browser.newContext(devices['iPhone 13']);
const page=await context.newPage();
page.setDefaultTimeout(10000);
page.setDefaultNavigationTimeout(15000);

const errors=[];
page.on('pageerror',err=>errors.push(String(err?.message||err)));
page.on('console',msg=>{if(msg.type()==='error')errors.push(msg.text())});

const assert=(condition,message)=>{if(!condition)throw new Error('Vokabeltrainer WebKit cache smoke failed: '+message)};
const fetchWithTimeout=async relative=>page.evaluate(async url=>{
  const controller=new AbortController();
  const timer=setTimeout(()=>controller.abort(),7000);
  try{
    const response=await fetch(url,{signal:controller.signal});
    return {ok:response.ok,text:await response.text(),status:response.status};
  }catch(error){
    return {ok:false,text:String(error),status:0};
  }finally{
    clearTimeout(timer);
  }
},relative);

try{
  await page.goto(base+'/index.html',{waitUntil:'domcontentloaded'});
  await page.waitForFunction(async()=>{
    const registration=await navigator.serviceWorker.getRegistration('./');
    return !!registration?.active?.scriptURL?.endsWith('/sw.js');
  },null,{timeout:12000});
  let rootController=await page.evaluate(()=>navigator.serviceWorker.controller?.scriptURL||'');
  if(!rootController.endsWith('/sw.js')||rootController.includes('/vokabeltrainer/')){
    await page.reload({waitUntil:'domcontentloaded'});
    await page.waitForFunction(()=>!!navigator.serviceWorker.controller?.scriptURL?.endsWith('/sw.js')&&!navigator.serviceWorker.controller.scriptURL.includes('/vokabeltrainer/'),null,{timeout:12000});
  }

  const rootCacheName=await page.evaluate(async()=>{
    const keys=await caches.keys();
    return keys.find(key=>key.startsWith('jgw-shell-'))||'';
  });
  assert(!!rootCacheName,'Gartenwelt shell cache must exist before Vokabeltrainer activation');
  await page.evaluate(async cacheName=>{
    const cache=await caches.open(cacheName);
    await cache.put(new Request(location.origin+'/__vocab_cache_sentinel__'),new Response('keep-me'));
  },rootCacheName);

  await page.goto(base+'/vokabeltrainer/index.html',{waitUntil:'domcontentloaded'});
  await page.waitForFunction(async()=>{
    const registration=await navigator.serviceWorker.getRegistration('./');
    return !!registration?.active?.scriptURL?.includes('/vokabeltrainer/sw.js');
  },null,{timeout:12000});

  let controller=await page.evaluate(()=>navigator.serviceWorker.controller?.scriptURL||'');
  if(!controller.includes('/vokabeltrainer/sw.js')){
    await page.reload({waitUntil:'domcontentloaded'});
    await page.waitForFunction(()=>navigator.serviceWorker.controller?.scriptURL?.includes('/vokabeltrainer/sw.js'),null,{timeout:12000});
    controller=await page.evaluate(()=>navigator.serviceWorker.controller?.scriptURL||'');
  }
  assert(controller.includes('/vokabeltrainer/sw.js'),'nested Vokabeltrainer service worker must control its page');

  const online=await fetchWithTimeout('./dict/wikidict/en-de/0_.json?v=1');
  assert(online.ok&&online.text.includes('"0"'),'dictionary shard must load online');

  const cacheState=await page.evaluate(async rootName=>{
    const keys=await caches.keys();
    const foreign=await caches.open(rootName);
    const sentinel=await foreign.match(new Request(location.origin+'/__vocab_cache_sentinel__'));
    return {keys,sentinel:sentinel?await sentinel.text():''};
  },rootCacheName);
  assert(cacheState.keys.includes(rootCacheName),'Vokabeltrainer activation must preserve the Gartenwelt shell cache');
  assert(cacheState.sentinel==='keep-me','Gartenwelt cache content must survive Vokabeltrainer activation');
  assert(cacheState.keys.includes('vokabeltrainer-shell-v0.9.17'),'versioned shell cache must exist');
  assert(cacheState.keys.includes('vokabeltrainer-resources-v1'),'version-independent resource cache must exist');

  await context.setOffline(true);
  const offline=await fetchWithTimeout('./dict/wikidict/en-de/0_.json?v=1');
  assert(offline.ok&&offline.text.includes('"0"'),'dictionary shard must remain available offline from persistent cache');

  await context.setOffline(false);
  const resourceEntry=await page.evaluate(async()=>{
    const cache=await caches.open('vokabeltrainer-resources-v1');
    const match=await cache.match(new Request(new URL('./dict/wikidict/en-de/0_.json?v=1',location.href)));
    return !!match;
  });
  assert(resourceEntry,'dictionary shard must be stored in persistent resource cache');

  assert(errors.filter(x=>/ReferenceError|TypeError|SyntaxError|Content Security Policy/i.test(x)).length===0,'Vokabeltrainer page must have no fatal JS/CSP errors');

  console.log('Vokabeltrainer WebKit cache smoke: passed');
  console.log('✓ nested service worker controls Vokabeltrainer');
  console.log('✓ Gartenwelt shell cache survives Vokabeltrainer activation');
  console.log('✓ resource cache works offline');
}finally{
  clearTimeout(hardStop);
  await context.setOffline(false).catch(()=>{});
  await browser.close();
}
