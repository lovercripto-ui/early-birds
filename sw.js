'use strict';
const VERSION='early-birds-phone-v3-live-20261106';
const BASE=new URL('./',self.location.href);
const SHELL=['./','./index.html','./style.css','./app.js','./cloud.js','./config.js','./vendor/supabase-2.95.0.js','./logo.png','./fonts/noto-sans-sinhala-sinhala-400-normal.woff2','./fonts/noto-sans-sinhala-sinhala-700-normal.woff2','./icon.png','./icon-192.png','./icon-maskable.png','./apple-touch-icon.png','./manifest.webmanifest'].map(p=>new URL(p,BASE).href);
self.addEventListener('install',e=>e.waitUntil(caches.open(VERSION).then(c=>c.addAll(SHELL))));
self.addEventListener('activate',e=>e.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k.startsWith('early-birds-phone-')&&k!==VERSION).map(k=>caches.delete(k)))).then(()=>self.clients.claim())));
self.addEventListener('fetch',e=>{
 if(e.request.method!=='GET')return;
 const u=new URL(e.request.url);
 // Never intercept Auth, database, storage, private exports or Google requests.
 if(u.origin!==BASE.origin||!SHELL.includes(u.href))return;
 e.respondWith(fetch(e.request).then(r=>{if(r.ok){const copy=r.clone();caches.open(VERSION).then(c=>c.put(e.request,copy));}return r;}).catch(()=>caches.match(e.request).then(r=>r||(e.request.mode==='navigate'?caches.match(new URL('./index.html',BASE).href):Response.error()))));
});
