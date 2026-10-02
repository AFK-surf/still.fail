/** Runs in an empty renderer before the app starts. The old origin is the rollback copy; never clear it here. */
export interface OriginSnapshot {
  local: [string, string][];
  databases: { name: string; version: number; stores: { name: string; rows: [IDBValidKey, number[]][] }[] }[];
}

// These functions must be self-contained: main executes their source in isolated, preload-free renderers.
export async function exportOriginStorage(): Promise<OriginSnapshot> {
  const request = <T>(r: IDBRequest<T>) => new Promise<T>((resolve, reject) => {
    r.onsuccess = () => resolve(r.result);
    r.onerror = () => reject(r.error);
  });
  const snapshot: OriginSnapshot = { local: [], databases: [] };
  for (let i = 0; i < localStorage.length; i++) {
    const key = localStorage.key(i)!;
    snapshot.local.push([key, localStorage.getItem(key)!]);
  }
  const known = await indexedDB.databases();
  for (const name of ["ember-core", "stillfail-core"]) {
    if (!known.some((db) => db.name === name)) continue;
    const db = await request(indexedDB.open(name));
    try {
      const stores: OriginSnapshot["databases"][number]["stores"] = [];
      for (const name of Array.from(db.objectStoreNames)) {
        const store = db.transaction(name).objectStore(name);
        // The core owns two out-of-line-key stores containing byte arrays. Fail rather than silently discard a future schema.
        if (!["values", "records"].includes(name) || store.keyPath !== null || store.autoIncrement || store.indexNames.length) {
          throw new Error(`Unsupported core store: ${name}`);
        }
        const [keys, values] = await Promise.all([request(store.getAllKeys()), request(store.getAll())]);
        stores.push({ name, rows: keys.map((key, i) => {
          const value = values[i];
          if (!(value instanceof Uint8Array)) throw new Error(`Unsupported core value: ${name}`);
          return [key, Array.from(value)];
        }) });
      }
      snapshot.databases.push({ name, version: db.version, stores });
    } finally { db.close(); }
  }
  return snapshot;
}

export async function importOriginStorage(snapshot: OriginSnapshot): Promise<void> {
  const marker = "stillfail.origin-migration.v1";
  if (localStorage.getItem(marker)) return;
  for (const source of snapshot.databases) {
    const db = await new Promise<IDBDatabase>((resolve, reject) => {
      const r = indexedDB.open(source.name, source.version);
      r.onupgradeneeded = () => {
        for (const store of source.stores) if (!r.result.objectStoreNames.contains(store.name)) r.result.createObjectStore(store.name);
      };
      r.onsuccess = () => resolve(r.result);
      r.onerror = () => reject(r.error);
      r.onblocked = () => reject(new Error("Origin migration blocked by an open database"));
    });
    try {
      if (source.stores.length) await new Promise<void>((resolve, reject) => {
        const tx = db.transaction(source.stores.map((s) => s.name), "readwrite");
        tx.oncomplete = () => resolve();
        tx.onabort = () => reject(tx.error ?? new Error("Origin migration aborted"));
        tx.onerror = () => reject(tx.error);
        for (const sourceStore of source.stores) {
          const store = tx.objectStore(sourceStore.name);
          for (const [key, bytes] of sourceStore.rows) {
            // An interrupted import is safe to retry; a newer value always wins.
            const get = store.get(key);
            get.onsuccess = () => { if (get.result === undefined) store.put(new Uint8Array(bytes), key); };
          }
        }
      });
    } finally { db.close(); }
  }
  for (const [key, value] of snapshot.local) {
    if (key !== marker && localStorage.getItem(key) === null) localStorage.setItem(key, value);
  }
  // Only after every database committed and every setting was copied. No app runs at this origin before this finishes.
  localStorage.setItem(marker, "1");
}
