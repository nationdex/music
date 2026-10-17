// ---------------------------------------------------------------- IndexedDB
// 'tracks' holds metadata (+ artwork blob); 'files' holds the audio blob.

let dbPromise = null;
function openDb() {
  if (!dbPromise) {
    dbPromise = new Promise((resolve, reject) => {
      if (!window.indexedDB) return reject(new Error('IndexedDB unavailable'));
      const req = indexedDB.open('adimusic', 1);
      req.onupgradeneeded = () => {
        req.result.createObjectStore('tracks', { keyPath: 'id' });
        req.result.createObjectStore('files', { keyPath: 'id' });
      };
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    });
  }
  return dbPromise;
}

async function idbRun(store, mode, fn) {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(store, mode);
    const req = fn(tx.objectStore(store));
    tx.oncomplete = () => resolve(req ? req.result : undefined);
    tx.onerror = () => reject(tx.error);
    tx.onabort = () => reject(tx.error);
  });
}
export const idbAll = (store) => idbRun(store, 'readonly', (s) => s.getAll());
export const idbGet = (store, key) => idbRun(store, 'readonly', (s) => s.get(key));
export const idbPut = (store, value) => idbRun(store, 'readwrite', (s) => s.put(value));
export const idbDelete = (store, key) => idbRun(store, 'readwrite', (s) => s.delete(key));
export const idbClear = (store) => idbRun(store, 'readwrite', (s) => s.clear());
