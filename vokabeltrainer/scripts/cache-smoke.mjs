import fs from 'node:fs';
import vm from 'node:vm';

const source=fs.readFileSync('vokabeltrainer/sw.js','utf8');
const listeners={};
const store=new Map();
const keyOf=input=>typeof input==='string'?input:input.url;

class MockCache{
  constructor(){this.entries=new Map()}
  async match(request){const hit=this.entries.get(keyOf(request));return hit?hit.clone():undefined}
  async put(request,response){this.entries.set(keyOf(request),response.clone())}
  async keys(){return [...this.entries.keys()].map(url=>new Request(url))}
  async addAll(){return undefined}
}
const cachesMock={
  async open(name){if(!store.has(name))store.set(name,new MockCache());return store.get(name)},
  async keys(){return [...store.keys()]},
  async delete(name){return store.delete(name)},
  async match(request){for(const cache of store.values()){const hit=await cache.match(request);if(hit)return hit}return undefined}
};

let networkCalls=0;
let networkMode='throw';
const context=vm.createContext({
  console,URL,Request,Response,Promise,Map,Set,
  caches:cachesMock,
  fetch:async request=>{
    networkCalls++;
    if(networkMode==='throw')throw new Error('offline');
    return new Response(networkMode,{status:200});
  },
  self:{
    location:new URL('https://example.test/JohannasGartenwelt/vokabeltrainer/sw.js'),
    addEventListener:(type,handler)=>{listeners[type]=handler},
    skipWaiting:async()=>{},
    clients:{claim:async()=>{}}
  }
});
vm.runInContext(source,context,{filename:'vokabeltrainer/sw.js'});

const assert=(condition,message)=>{if(!condition)throw new Error('Cache smoke failed: '+message)};

const legacyName='vokabeltrainer-v0.9.16-subject-system-hardened';
const jgwName='jgw-shell-v5';
const unrelatedName='other-app-cache';
const legacy=await cachesMock.open(legacyName);
await legacy.put(new Request('https://example.test/JohannasGartenwelt/vokabeltrainer/ocr/lang/eng.traineddata'),new Response('OCR-V1'));
await legacy.put(new Request('https://example.test/JohannasGartenwelt/vokabeltrainer/dict/wikidict/en-de/aa.json?v=1'),new Response('DICT-V1'));
await legacy.put(new Request('https://example.test/JohannasGartenwelt/vokabeltrainer/js/core.js?v=0.9.16'),new Response('OLD-SHELL'));
await cachesMock.open(jgwName);
await cachesMock.open(unrelatedName);

let activation;
listeners.activate({waitUntil:p=>{activation=p}});
await activation;

const keys=await cachesMock.keys();
assert(keys.includes(jgwName),'activation must preserve the Gartenwelt cache');
assert(keys.includes(unrelatedName),'activation must preserve unrelated origin caches');
assert(!keys.includes(legacyName),'legacy Vokabeltrainer cache should be removed after migration');
const resourceName=keys.find(x=>x.startsWith('vokabeltrainer-resources-'));
assert(resourceName==='vokabeltrainer-resources-v1','resource cache revision must be independent from app version');
const resources=await cachesMock.open(resourceName);
assert((await (await resources.match(new Request('https://example.test/JohannasGartenwelt/vokabeltrainer/ocr/lang/eng.traineddata'))).text())==='OCR-V1','cached OCR data must migrate across app versions');
assert((await (await resources.match(new Request('https://example.test/JohannasGartenwelt/vokabeltrainer/dict/wikidict/en-de/aa.json?v=1'))).text())==='DICT-V1','cached dictionary shard must migrate across app versions');

let responsePromise;
networkCalls=0;networkMode='throw';
listeners.fetch({request:new Request('https://example.test/JohannasGartenwelt/vokabeltrainer/ocr/lang/eng.traineddata'),respondWith:p=>{responsePromise=p}});
let response=await responsePromise;
assert(await response.text()==='OCR-V1','persistent resource must work offline from cache');
assert(networkCalls===0,'cached persistent resource must not hit network');

networkCalls=0;networkMode='DICT-NEW';
const newShard='https://example.test/JohannasGartenwelt/vokabeltrainer/dict/wikidict/de-en/ab.json?v=1';
listeners.fetch({request:new Request(newShard),respondWith:p=>{responsePromise=p}});
response=await responsePromise;
assert(await response.text()==='DICT-NEW','new dictionary resource should load from network');
assert(networkCalls===1,'new dictionary resource should fetch exactly once');

networkMode='throw';
listeners.fetch({request:new Request(newShard),respondWith:p=>{responsePromise=p}});
response=await responsePromise;
assert(await response.text()==='DICT-NEW','newly fetched dictionary resource must survive offline reuse');
assert(networkCalls===1,'second dictionary request must come from persistent cache');

assert(!source.includes("keys.filter(key=>key!==CACHE)"),'service worker must never delete every other origin cache');
assert(source.includes("url.pathname.startsWith(\`\${base}ocr/\`)"),'OCR path must be classified as persistent');
assert(source.includes("url.pathname.startsWith(\`\${base}dict/wikidict/\`)"),'Wikidict path must be classified as persistent');

console.log('Vokabeltrainer cache smoke: passed');
console.log('✓ foreign origin caches are preserved');
console.log('✓ legacy OCR and dictionary data migrate');
console.log('✓ OCR and dictionary resources are cache-first across app versions');
