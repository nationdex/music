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
// Safari cannot always store a Blob in IndexedDB (private browsing, lockdown mode, older iOS), and
// the failure only shows up at write time. When a write fails, retry with each Blob turned into an
// ArrayBuffer; reads turn those back into Blobs, so callers never notice.
const BUFFERED = '__blobBuffer';

async function unblob(row) {
  const out = {};
  for (const [key, value] of Object.entries(row)) {
    out[key] = value instanceof Blob ? { [BUFFERED]: await value.arrayBuffer(), type: value.type } : value;
  }
  return out;
}

function reblob(row) {
  if (!row || typeof row !== 'object') return row;
  for (const [key, value] of Object.entries(row)) {
    if (value && typeof value === 'object' && BUFFERED in value) row[key] = new Blob([value[BUFFERED]], { type: value.type });
  }
  return row;
}

export const idbAll = async (store) => (await idbRun(store, 'readonly', (s) => s.getAll())).map(reblob);
export const idbGet = async (store, key) => reblob(await idbRun(store, 'readonly', (s) => s.get(key)));
export const idbPut = async (store, value) => {
  try {
    return await idbRun(store, 'readwrite', (s) => s.put(value));
  } catch (e) {
    if (!Object.values(value).some((v) => v instanceof Blob)) throw e;
    const plain = await unblob(value);
    return idbRun(store, 'readwrite', (s) => s.put(plain));
  }
};
export const idbDelete = (store, key) => idbRun(store, 'readwrite', (s) => s.delete(key));
export const idbClear = (store) => idbRun(store, 'readwrite', (s) => s.clear());
