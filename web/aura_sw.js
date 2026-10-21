'use strict';

// AuraSOS offline service worker.
// The version string and file list below are stamped in by tool/build_web.sh after the Flutter
// build, so the cache name changes whenever any shipped file changes.
const VERSION = '__AURA_VERSION__';
const CACHE = 'aurasync-' + VERSION;
const FILES = __AURA_FILES__;

self.addEventListener('install', (event) => {
  // A new version stays waiting until every open tab is closed, so a running session never
  // has files swapped underneath it.
  event.waitUntil(
    caches.open(CACHE).then((cache) => cache.addAll(FILES.map((f) => new Request(f, { cache: 'reload' }))))
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const names = await caches.keys();
      await Promise.all(
        names.filter((n) => n.startsWith('aurasync-') && n !== CACHE).map((n) => caches.delete(n))
      );
      await self.clients.claim();
    })()
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return; // nothing external is ever fetched

  event.respondWith(
    (async () => {
      const cache = await caches.open(CACHE);
      const hit = await cache.match(req, { ignoreSearch: true });
      if (hit) return hit;
      try {
        const res = await fetch(req);
        if (res && res.ok) cache.put(req, res.clone());
        return res;
      } catch (err) {
        // Offline and not precached: a page navigation still gets the app shell.
        if (req.mode === 'navigate') {
          const shell = await cache.match('index.html');
          if (shell) return shell;
        }
        throw err;
      }
    })()
  );
});
