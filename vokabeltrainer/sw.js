const CACHE='vokabeltrainer-v0.9.14-sense-final';
const ASSETS=['./','./index.html','./css/app.css?v=0.9.14','./js/core.js?v=0.9.14','./js/storage.js?v=0.9.14','./js/model.js?v=0.9.14','./js/learning.js?v=0.9.14','./js/translation.js?v=0.9.14','./js/io.js?v=0.9.14','./js/ui.js?v=0.9.14','./js/app.js?v=0.9.14','./manifest.webmanifest','./assets/icons/icon-180.png','./assets/icons/icon-192.png','./assets/icons/icon-512.png'];
self.addEventListener('install',event=>event.waitUntil((async()=>{
  const cache=await caches.open(CACHE);
  const requests=ASSETS.map(path=>new Request(new URL(path,self.location).href,{cache:'reload'}));
  await cache.addAll(requests);
  await self.skipWaiting();
})()));
self.addEventListener('activate',event=>event.waitUntil((async()=>{
  const keys=await caches.keys();
  await Promise.all(keys.filter(key=>key!==CACHE).map(key=>caches.delete(key)));
  await self.clients.claim();
})()));
self.addEventListener('fetch',event=>{
  const req=event.request;
  if(req.method!=='GET')return;
  const url=new URL(req.url);
  if(url.origin!==self.location.origin)return;
  event.respondWith((async()=>{
    if(req.mode==='navigate'){
      try{
        const response=await fetch(req,{cache:'no-cache'});
        if(response.ok){const cache=await caches.open(CACHE);cache.put(req,response.clone()).catch(()=>{});}
        return response;
      }catch(err){return (await caches.match(req))||(await caches.match(new URL('./index.html',self.location).href))||Response.error();}
    }
    const cached=await caches.match(req);
    if(cached)return cached;
    try{
      const response=await fetch(req);
      if(response.ok){const cache=await caches.open(CACHE);cache.put(req,response.clone()).catch(()=>{});}
      return response;
    }catch(err){return new Response('Offline',{status:503,statusText:'Offline'});}
  })());
});