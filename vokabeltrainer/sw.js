'use strict';

const APP_VERSION='0.9.17';
const RESOURCE_REVISION='1';
const SHELL_CACHE=`vokabeltrainer-shell-v${APP_VERSION}`;
const RESOURCE_CACHE=`vokabeltrainer-resources-v${RESOURCE_REVISION}`;
const SHELL_CACHE_PREFIX='vokabeltrainer-shell-';
const RESOURCE_CACHE_PREFIX='vokabeltrainer-resources-';
const LEGACY_CACHE_PREFIX='vokabeltrainer-v';

const ASSETS=[
  './','./index.html','./css/app.css?v=0.9.17','./js/core.js?v=0.9.17','./js/storage.js?v=0.9.17',
  './js/model.js?v=0.9.17','./js/learning.js?v=0.9.17','./js/translation.js?v=0.9.17',
  './js/io.js?v=0.9.17','./js/ui.js?v=0.9.17','./js/app.js?v=0.9.17','./manifest.webmanifest',
  './assets/icons/icon-180.png','./assets/icons/icon-192.png','./assets/icons/icon-512.png'
];

function appBasePath(){
  return new URL('./',self.location.href).pathname;
}

function isPersistentResource(url){
  if(url.origin!==self.location.origin)return false;
  const base=appBasePath();
  return url.pathname.startsWith(`${base}ocr/`)||url.pathname.startsWith(`${base}dict/wikidict/`);
}

function isOwnedObsoleteCache(key){
  if(key===SHELL_CACHE||key===RESOURCE_CACHE)return false;
  return key.startsWith(SHELL_CACHE_PREFIX)||key.startsWith(RESOURCE_CACHE_PREFIX)||key.startsWith(LEGACY_CACHE_PREFIX);
}

async function migrateLegacyResources(){
  const names=await caches.keys();
  const legacy=names.filter(key=>key.startsWith(LEGACY_CACHE_PREFIX)&&key!==SHELL_CACHE&&key!==RESOURCE_CACHE);
  if(!legacy.length)return;
  const target=await caches.open(RESOURCE_CACHE);
  for(const name of legacy){
    const source=await caches.open(name);
    const requests=await source.keys();
    for(const request of requests){
      let url;try{url=new URL(request.url)}catch(_e){continue}
      if(!isPersistentResource(url))continue;
      if(await target.match(request))continue;
      const response=await source.match(request);
      if(response)await target.put(request,response.clone()).catch(()=>{});
    }
  }
}

self.addEventListener('install',event=>event.waitUntil((async()=>{
  const cache=await caches.open(SHELL_CACHE);
  const requests=ASSETS.map(path=>new Request(new URL(path,self.location).href,{cache:'reload'}));
  await cache.addAll(requests);
  await self.skipWaiting();
})()));

self.addEventListener('activate',event=>event.waitUntil((async()=>{
  await migrateLegacyResources();
  const keys=await caches.keys();
  await Promise.all(keys.filter(isOwnedObsoleteCache).map(key=>caches.delete(key)));
  await self.clients.claim();
})()));

async function persistentResourceResponse(request){
  const cache=await caches.open(RESOURCE_CACHE);
  const cached=await cache.match(request);
  if(cached)return cached;
  try{
    const response=await fetch(request,{cache:'reload'});
    if(response&&response.status===200)await cache.put(request,response.clone()).catch(()=>{});
    return response;
  }catch(err){
    return new Response('Offline',{status:503,statusText:'Offline'});
  }
}

async function navigationResponse(request){
  const shell=await caches.open(SHELL_CACHE);
  try{
    const response=await fetch(request,{cache:'no-cache'});
    if(response&&response.ok)await shell.put(request,response.clone()).catch(()=>{});
    return response;
  }catch(err){
    return (await shell.match(request))||(await shell.match(new URL('./index.html',self.location).href))||Response.error();
  }
}

async function shellResponse(request){
  const shell=await caches.open(SHELL_CACHE);
  const cached=await shell.match(request);
  if(cached)return cached;
  try{
    const response=await fetch(request);
    if(response&&response.status===200)await shell.put(request,response.clone()).catch(()=>{});
    return response;
  }catch(err){
    return new Response('Offline',{status:503,statusText:'Offline'});
  }
}

self.addEventListener('fetch',event=>{
  const request=event.request;
  if(request.method!=='GET')return;
  const url=new URL(request.url);
  if(url.origin!==self.location.origin)return;
  if(isPersistentResource(url)){
    event.respondWith(persistentResourceResponse(request));
    return;
  }
  if(request.mode==='navigate'){
    event.respondWith(navigationResponse(request));
    return;
  }
  event.respondWith(shellResponse(request));
});
