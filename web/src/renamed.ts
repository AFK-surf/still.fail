// What a browser kept under the names from before the rename (localStorage and sessionStorage keys `ember.*`) is
// copied to the new names (`stillfail.*`) once, before anything reads them: the settings, the drafts' places, the
// accounts from before the core. The old keys stay as they were (a tab of an older build may still read them); a key
// the new name already has is not overwritten. index.html does the same inline before its first paint.
const FORMER = "ember.";
const PREFIX = "stillfail.";
const DONE = "stillfail.renamed";

export function carryOver(storage: Storage): void {
  try {
    if (storage.getItem(DONE)) return;
    const keys: string[] = [];
    for (let i = 0; i < storage.length; i++) {
      const key = storage.key(i);
      if (key?.startsWith(FORMER)) keys.push(key);
    }
    for (const key of keys) {
      const renamed = PREFIX + key.slice(FORMER.length);
      const value = storage.getItem(key);
      if (value !== null && storage.getItem(renamed) === null) storage.setItem(renamed, value);
    }
    storage.setItem(DONE, "1");
  } catch { /* no storage (private mode, a sandbox): nothing to carry */ }
}

for (const name of ["localStorage", "sessionStorage"] as const) {
  try { carryOver(window[name]); } catch { /* not allowed here */ }
}
