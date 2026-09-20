"use strict";

const SHELL_CACHE = "jgw-shell-v4";
const RUNTIME_CACHE = "jgw-runtime-v2";

const OPTIONAL_CDN = [
  "https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.css",
  "https://cdn.jsdelivr.net/npm/leaflet@1.9.4/dist/leaflet.js",
  "https://cdn.jsdelivr.net/npm/leaflet-draw@1.0.4/dist/leaflet.draw.css",
  "https://cdn.jsdelivr.net/npm/leaflet-draw@1.0.4/dist/leaflet.draw.js"
];

const SHELL = [
  "./",
  "./index.html",
  "./manifest.webmanifest",
  "./app-icon-180.png",
  "./app-icon.svg",
  "./jgw-app.css",
  "./jgw-runtime-styles.css",
  "./jgw-app.js",
  "./jgw-sw-register.js",
  "./jgw-ux-shell.js",
  "./jgw-library-v4.js",
  "./jgw-ux-patch.js",
  "./jgw-photo-storage-v2.js",
  "./jgw-ui-cleanup-20260914.js",
  "./jgw-mobile-fix-v5.js",
  "./jgw-hardiness-data-v1.js",
  "./jgw-hardiness-v2.js",
  "./jgw-hardiness-labels-v1.js",
  "./garten-tipps.js",
  "./jgw-care-calendar-v1.js",
  "./jgw-task-bulk-v3.js"
];

self.addEventListener("install", event => {
  event.waitUntil(
    Promise.all([
      caches.open(SHELL_CACHE).then(cache => cache.addAll(SHELL)),
      caches.open(RUNTIME_CACHE).then(async cache => {
        await Promise.allSettled(OPTIONAL_CDN.map(async url => {
          try {
            const response = await fetch(url, { mode: "no-cors", cache: "no-cache" });
            if (response) await cache.put(url, response.clone());
          } catch (_) {}
        }));
      })
    ]).then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(
        keys
          .filter(key => key.startsWith("jgw-") && ![SHELL_CACHE, RUNTIME_CACHE].includes(key))
          .map(key => caches.delete(key))
      ))
      .then(() => self.clients.claim())
  );
});

function sensitiveRequest(url) {
  return url.pathname.endsWith("/setup.html")
    || url.searchParams.has("install")
    || url.searchParams.has("setup")
    || url.searchParams.has("token");
}

async function networkFirst(request, fallbackUrl) {
  const cache = await caches.open(SHELL_CACHE);
  try {
    const response = await fetch(request, { cache: "no-cache" });
    if (response && response.ok) {
      await cache.put(request, response.clone());
      if (fallbackUrl) await cache.put(fallbackUrl, response.clone());
    }
    return response;
  } catch (error) {
    return (await cache.match(request, { ignoreSearch: true }))
      || (fallbackUrl ? await cache.match(fallbackUrl, { ignoreSearch: true }) : null)
      || Promise.reject(error);
  }
}

async function runtimeStaleWhileRevalidate(request) {
  const cache = await caches.open(RUNTIME_CACHE);
  const cached = await cache.match(request, { ignoreSearch: false });
  const network = fetch(request).then(response => {
    if (response && (response.ok || response.type === "opaque")) {
      cache.put(request, response.clone()).catch(() => {});
    }
    return response;
  }).catch(() => null);
  return cached || await network || Response.error();
}

self.addEventListener("fetch", event => {
  const request = event.request;
  if (request.method !== "GET") return;

  const url = new URL(request.url);

  if (sensitiveRequest(url)) {
    event.respondWith(fetch(request, { cache: "no-store" }));
    return;
  }

  if (url.origin === self.location.origin) {
    if (request.mode === "navigate") {
      event.respondWith(networkFirst(request, "./index.html"));
      return;
    }

    if (["script", "style", "image", "manifest", "font"].includes(request.destination)) {
      event.respondWith(networkFirst(request));
      return;
    }

    return;
  }

  if (url.hostname === "cdn.jsdelivr.net"
      && ["script", "style", "font"].includes(request.destination)) {
    event.respondWith(runtimeStaleWhileRevalidate(request));
  }
});
