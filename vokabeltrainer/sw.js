'use strict';

const TARGET='/Vokabeltrainer/';

self.addEventListener('install',event=>event.waitUntil(self.skipWaiting()));
self.addEventListener('activate',event=>event.waitUntil(self.clients.claim()));

self.addEventListener('fetch',event=>{
  const request=event.request;
  if(request.method!=='GET'||request.mode!=='navigate')return;
  const url=new URL(request.url);
  if(url.origin!==self.location.origin)return;
  if(url.pathname.startsWith('/JohannasGartenwelt/vokabeltrainer/')){
    event.respondWith(Response.redirect(new URL(TARGET,self.location.origin).href,302));
  }
});
