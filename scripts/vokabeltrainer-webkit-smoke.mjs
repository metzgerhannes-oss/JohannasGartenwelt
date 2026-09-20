import { webkit, devices } from 'playwright';

const base=process.env.JGW_BASE||'http://127.0.0.1:4173';
const browser=await webkit.launch({headless:true});
const context=await browser.newContext(devices['iPhone 13']);
const page=await context.newPage();
page.setDefaultTimeout(10000);
page.setDefaultNavigationTimeout(15000);

const errors=[];
page.on('pageerror',err=>errors.push(String(err?.message||err)));
page.on('console',msg=>{if(msg.type()==='error')errors.push(msg.text())});

const assert=(condition,message)=>{if(!condition)throw new Error('Vokabeltrainer WebKit cache smoke failed: '+message)};

try{
  await page.goto(base+'/index.html',{waitUntil:'domcontentloaded'});
  await page.evaluate(async()=>{
    const cache=await caches.open('jgw-smoke-preserve');
    await cache.put(new Request(location.origin+'/__vocab_cache_sentinel__'),new Response('keep-me'));
  });

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

  const online=await page.evaluate(async()=>{
    const response=await fetch('./dict/wikidict/en-de/0_.json?v=1');
    return {ok:response.ok,text:await response.text()};
  });
  assert(online.ok&&online.text.includes('"0"'),'dictionary shard must load online');

  const cacheState=await page.evaluate(async()=>{
    const keys=await caches.keys();
    const foreign=await caches.open('jgw-smoke-preserve');
    const sentinel=await foreign.match(new Request(location.origin+'/__vocab_cache_sentinel__'));
    return {keys,sentinel:sentinel?await sentinel.text():''};
  });
  assert(cacheState.keys.includes('jgw-smoke-preserve'),'Vokabeltrainer activation must preserve foreign JGW cache');
  assert(cacheState.sentinel==='keep-me','foreign cache content must survive Vokabeltrainer activation');
  assert(cacheState.keys.some(x=>x==='vokabeltrainer-shell-v0.9.17'),'versioned shell cache must exist');
  assert(cacheState.keys.some(x=>x==='vokabeltrainer-resources-v1'),'version-independent resource cache must exist');

  await context.setOffline(true);
  const offline=await page.evaluate(async()=>{
    try{
      const response=await fetch('./dict/wikidict/en-de/0_.json?v=1');
      return {ok:response.ok,text:await response.text(),status:response.status};
    }catch(error){
      return {ok:false,text:String(error),status:0};
    }
  });
  assert(offline.ok&&offline.text.includes('"0"'),'dictionary shard must remain available offline from persistent cache');

  await context.setOffline(false);
  const resourceEntry=await page.evaluate(async()=>{
    const cache=await caches.open('vokabeltrainer-resources-v1');
    const match=await cache.match(new Request(new URL('./dict/wikidict/en-de/0_.json?v=1',location.href)));
    return !!match;
  });
  assert(resourceEntry,'dictionary shard must be stored in persistent resource cache');

  assert(errors.filter(x=>/ReferenceError|TypeError|SyntaxError|Content Security Policy/i.test(x)).length===0,'Vokabeltrainer page must have no fatal JS/CSP errors');

  await page.evaluate(()=>caches.delete('jgw-smoke-preserve'));
  console.log('Vokabeltrainer WebKit cache smoke: passed');
  console.log('✓ nested service worker controls Vokabeltrainer');
  console.log('✓ foreign JGW cache survives activation');
  console.log('✓ resource cache works offline');
}finally{
  await context.setOffline(false).catch(()=>{});
  await browser.close();
}
