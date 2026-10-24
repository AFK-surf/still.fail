// A thread as stations before 2026-10-25 archived it (store.ts `// ── archive`): its entries written out to its archive
// file, as the Rust station wrote them, and taken out of the database. A station reads what they left as it is until it
// brings it back.
import { archiveText, threadFile, writeCompressed } from "../src/store/archive.ts";
import type { Store } from "../src/store/store.ts";

export function fileAway(store: Store, thread: number): string {
  const path = threadFile(store.archiveDir(), thread);
  writeCompressed(path, archiveText(store.entriesAfter(thread, 0)));
  store.db.prepare("DELETE FROM entries WHERE thread = ?").run(thread);
  store.db.prepare("UPDATE threads SET archived_at = ? WHERE id = ?").run(store.now(), thread);
  return path;
}
