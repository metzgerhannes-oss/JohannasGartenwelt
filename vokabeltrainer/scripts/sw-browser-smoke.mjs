import { chromium, devices } from 'playwright';

const base=process.env.JGW_BASE||'http://127.0.0.1:4173';
const hardStop=setTimeout(()=>{console.error('FATAL_VOKABELTRAINER_SW_BROWSER_TIMEOUT');process.exit(1)},45000);
const browser=await chromium.launch({headless:true});
const context=await browser.newContext(devices['Desktop Chrome']);
const page=await context.newPage();
page.setDefaultTimeout(10000);
page.setDefaultNavigationTimeout(15000);

const errors=[];
page.on('pageerror',err=>errors.push(String(err?.message||err)));
page.on('console',msg=>{if(msg.type()==='error')errors.push(msg.text())});
const assert=(condition,message)=>{if(!condition)throw new Error('Vokabeltrainer SW browser smoke failed: '+message)};
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
  console.log('SW_BROWSER checkpoint: seed foreign cache');
  await page.goto(base+'/vokabeltrainer/manifest.webmanifest',{waitUntil:'commit'});
  const foreignCacheName='jgw-shell-v5';
  await page.evaluate(async cacheName=>{
    const cache=await caches.open(cacheName);
    await cache.put(new Request(location.origin+'/__vocab_cache_sentinel__'),new Response('keep-me'));
  },foreignCacheName);

  console.log('SW_BROWSER checkpoint: register vocab service worker');
  const workerPromise=context.waitForEvent('serviceworker',{timeout:12000});
  await page.goto(base+'/vokabeltrainer/index.html',{waitUntil:'domcontentloaded'});
  const worker=await workerPromise;
  assert(worker.url().includes('/vokabeltrainer/sw.js'),'Vokabeltrainer service worker must register');

  await page.evaluate(async()=>{
    const registration=await navigator.serviceWorker.getRegistration('./');
    if(registration?.active?.state==='activated'&&navigator.serviceWorker.controller?.scriptURL?.includes('/vokabeltrainer/sw.js'))return;
    await new Promise((resolve,reject)=>{
      const timer=setTimeout(()=>reject(new Error('controllerchange timeout')),10000);
      navigator.serviceWorker.addEventListener('controllerchange',()=>{
        clearTimeout(timer);resolve();
      },{once:true});
    });
  });
  let controller=await page.evaluate(()=>navigator.serviceWorker.controller?.scriptURL||'');
  if(!controller.includes('/vokabeltrainer/sw.js')){
    await page.reload({waitUntil:'domcontentloaded'});
    controller=await page.evaluate(()=>navigator.serviceWorker.controller?.scriptURL||'');
  }
  assert(controller.includes('/vokabeltrainer/sw.js'),'nested Vokabeltrainer service worker must control its page');

  console.log('SW_BROWSER checkpoint: cache dictionary');
  const online=await fetchWithTimeout('./dict/wikidict/en-de/0_.json?v=1');
  assert(online.ok&&online.text.includes('"0"'),'dictionary shard must load online');

  const cacheState=await page.evaluate(async foreignName=>{
    const keys=await caches.keys();
    const foreign=await caches.open(foreignName);
    const sentinel=await foreign.match(new Request(location.origin+'/__vocab_cache_sentinel__'));
    return {keys,sentinel:sentinel?await sentinel.text():''};
  },foreignCacheName);
  assert(cacheState.keys.includes(foreignCacheName),'Vokabeltrainer activation must preserve Gartenwelt cache');
  assert(cacheState.sentinel==='keep-me','Gartenwelt cache content must survive activation');
  assert(cacheState.keys.includes('vokabeltrainer-shell-v0.9.17'),'versioned shell cache must exist');
  assert(cacheState.keys.includes('vokabeltrainer-resources-v1'),'version-independent resource cache must exist');

  console.log('SW_BROWSER checkpoint: offline resource');
  await context.setOffline(true);
  const offline=await fetchWithTimeout('./dict/wikidict/en-de/0_.json?v=1');
  assert(offline.ok&&offline.text.includes('"0"'),'dictionary shard must remain available offline');
  await context.setOffline(false);

  const resourceEntry=await page.evaluate(async()=>{
    const cache=await caches.open('vokabeltrainer-resources-v1');
    return !!(await cache.match(new Request(new URL('./dict/wikidict/en-de/0_.json?v=1',location.href))));
  });
  assert(resourceEntry,'dictionary shard must be stored in persistent resource cache');
  assert(errors.filter(x=>/ReferenceError|TypeError|SyntaxError|Content Security Policy/i.test(x)).length===0,'page must have no fatal JS/CSP errors');

  console.log('Vokabeltrainer service-worker browser smoke: passed');
  console.log('✓ foreign Gartenwelt cache survives activation');
  console.log('✓ persistent resource cache works offline');
}finally{
  await context.setOffline(false).catch(()=>{});
  await browser.close().catch(()=>{});
  clearTimeout(hardStop);
}
