// Adi Music service worker: makes the app shell work offline.
// Audio never passes through here: local tracks are Blob URLs from IndexedDB, and
// the /up/* proxies and YouTube are network-only. Same-origin GETs only.
//
// Bump CACHE when SHELL changes shape (files added or removed). File *contents* do
// not need a bump: code is fetched network-first and the cache is refreshed.

const CACHE = 'adi-shell-v1';

const SHELL = [
  '/',
  '/app.html',
  '/manifest.webmanifest',
  '/favicon.ico',
  '/assets/app.css',
  '/assets/uno.config.js',
  '/assets/js/app.js',
  '/assets/js/config.js',
  '/assets/js/db.js',
  '/assets/js/lyrics.js',
  '/assets/js/palette.js',
  '/assets/js/pwa.js',
  '/assets/js/router.js',
  '/assets/js/sources.js',
  '/assets/js/tags.js',
  '/assets/js/theme.js',
  '/assets/js/util.js',
  '/assets/vendor/alpine.min.js',
  '/assets/vendor/alpine-anchor.min.js',
  '/assets/vendor/alpine-focus.min.js',
  '/assets/vendor/alpine-intersect.min.js',
  '/assets/vendor/alpine-persist.min.js',
  '/assets/vendor/unocss-preset-wind4.js',
  '/assets/vendor/unocss-reset.css',
  '/assets/vendor/unocss-runtime-core.js',
  '/components/collection',
  '/components/discovery',
  '/components/home',
  '/components/player',
  '/components/settings',
  '/components/tracks',
  '/fonts/MPLUSRounded1c-Bold.woff2',
  '/fonts/MPLUSRounded1c-Medium.woff2',
  '/fonts/MPLUSRounded1c-Regular.woff2',
  '/images/icon-192.png',
  '/images/icon-512.png',
  '/images/logo-64.png',
  '/images/player.png'
];

const PLAYER_ROUTE = /^\/(library(\/.*)?|discovery|settings|player)\/?$/;
const IMMUTABLE = /^\/(fonts|images|assets\/vendor)\//;
const NETWORK_TIMEOUT_MS = 4000;

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(CACHE)
      .then((cache) => cache.addAll(SHELL.map((url) => new Request(url, { cache: 'reload' }))))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => k.startsWith('adi-') && k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET' || req.headers.has('range')) return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin || url.pathname.startsWith('/up/')) return;

  if (req.mode === 'navigate') {
    const key = PLAYER_ROUTE.test(url.pathname) ? '/app.html' : url.pathname === '/' || url.pathname === '/index.html' ? '/' : null;
    if (key) event.respondWith(networkFirst(req, key));
    return;
  }
  event.respondWith(IMMUTABLE.test(url.pathname) ? cacheFirst(req) : networkFirst(req, req));
});

async function networkFirst(req, key) {
  const cache = await caches.open(CACHE);
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), NETWORK_TIMEOUT_MS);
  try {
    const res = await fetch(req, { signal: ctrl.signal });
    if (res.ok) cache.put(key, res.clone());
    return res;
  } catch (err) {
    const hit = await cache.match(key);
    if (hit) return hit;
    throw err;
  } finally {
    clearTimeout(timer);
  }
}

async function cacheFirst(req) {
  const cache = await caches.open(CACHE);
  const hit = await cache.match(req);
  if (hit) return hit;
  const res = await fetch(req);
  if (res.ok) cache.put(req, res.clone());
  return res;
}
