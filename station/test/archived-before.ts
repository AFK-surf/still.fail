// A thread as stations before 2026-10-25 archived it (the Rust station's way): its entries written out to its archive
// file as serde wrote EntryRow, and taken out of the database, which is at version 12 then. Opened again, the store
// brings it back (store.ts `#upgradeFrom12`).
import { entryJson, threadFile, writeCompressed } from "../src/store/archive.ts";
import type { Store } from "../src/store/store.ts";

export function fileAway(store: Store, thread: number): string {
  const path = threadFile(store.archiveDir(), thread);
  writeCompressed(path, store.entriesAfter(thread, 0).map((e) => `${JSON.stringify(entryJson(e))}\n`).join(""));
  store.db.prepare("DELETE FROM entries WHERE thread = ?").run(thread);
  store.db.prepare("UPDATE threads SET archived_at = ? WHERE id = ?").run(store.now(), thread);
  store.db.exec("PRAGMA user_version = 12");
  return path;
}
