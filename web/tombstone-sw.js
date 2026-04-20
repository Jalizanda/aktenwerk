// Tombstone-Service-Worker.
// Ersetzt alte, kaputte Flutter-Service-Worker: installiert sich, löscht
// sämtliche Caches, übernimmt alle offenen Tabs und reicht alle
// Fetch-Requests direkt ans Netz weiter. Ergebnis: kein SW mehr, keine
// Cache-Hänger mehr.

self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    try {
      const keys = await caches.keys();
      await Promise.all(keys.map((k) => caches.delete(k)));
    } catch (e) {}
    await self.clients.claim();
    // Alle offenen Tabs neu laden, damit sie garantiert ohne SW weiterlaufen.
    try {
      const clients = await self.clients.matchAll({ type: 'window' });
      for (const c of clients) {
        try {
          c.postMessage({ type: 'AKTENWERK_RELOAD' });
          await c.navigate(c.url);
        } catch (e) {}
      }
    } catch (e) {}
    // Letzter Schritt: selbst abmelden, dann bleibt nichts zurück.
    try { await self.registration.unregister(); } catch (e) {}
  })());
});

// Alle Fetches unverändert ans Netz durchreichen.
self.addEventListener('fetch', (event) => {
  // Kein event.respondWith — Browser nimmt seinen Standard-Fetch.
});
