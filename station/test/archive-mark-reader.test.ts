import assert from "node:assert/strict";
import { existsSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { pathToFileURL } from "node:url";
import { ArchiveMarkBuilder } from "../src/read/archive-mark-builder.ts";
import { Readers } from "../src/read/pool.ts";
import { archiveMarksReady, installArchiveMarkIndex } from "../src/store/archive-mark-index.ts";
import { Store } from "../src/store/store.ts";

function fixture() {
  const dir = mkdtempSync(join(tmpdir(), "archive-mark-reader-"));
  const store = Store.open(join(dir, "stillfail.db")), db = store.db;
  for (const row of db.prepare("SELECT name FROM sqlite_master WHERE type='trigger' AND (name LIKE 'archive_pin_%' OR name LIKE 'archive_keep_%')").all() as { name: string }[]) db.exec(`DROP TRIGGER ${row.name}`);
  db.exec("DROP TABLE archive_pin_rows; DROP TABLE archive_keep_rows; DROP TABLE archive_pin_replaced; DROP TABLE archive_keep_replaced; DROP TABLE archive_mark_meta");
  db.exec("INSERT INTO pins(viewer,session,at) VALUES('person','s',1); INSERT INTO kept_chats(viewer,thread) VALUES('person',7)");
  installArchiveMarkIndex(db);
  return { dir, store, close: () => { store.close(); rmSync(dir, { recursive: true, force: true }); } };
}

test("archive mark requests wait for handover, share preparation, and allow one to cancel", async () => {
  const f = fixture(), previous = Promise.withResolvers<void>(), cancel = new AbortController();
  const readers = new Readers(f.dir, 1, undefined, 1, { previousGone: previous.promise });
  try {
    const abandoned = readers.prepareArchiveMarks(cancel.signal);
    const kept = readers.prepareArchiveMarks();
    assert.equal(archiveMarksReady(f.store.db), false);
    cancel.abort();
    await assert.rejects(abandoned, /read cancelled/);
    previous.resolve();
    await kept;
    assert.equal(archiveMarksReady(f.store.db), true);
    assert.equal(f.store.archiveMarks().pinned("s"), true);
    assert.equal(f.store.archiveMarks().kept(7), true);
  } finally { cancel.abort(); previous.resolve(); readers.close(); f.close(); }
});

test("an abandoned archive check does not start preparing marks after handover", async () => {
  const f = fixture(), previous = Promise.withResolvers<void>(), cancel = new AbortController();
  const readers = new Readers(f.dir, 1, undefined, 1, { previousGone: previous.promise });
  try {
    const pending = readers.prepareArchiveMarks(cancel.signal);
    cancel.abort();
    await assert.rejects(pending, /read cancelled/);
    previous.resolve();
    await Promise.resolve();
    assert.equal(archiveMarksReady(f.store.db), false);
    assert.equal(f.store.db.prepare("SELECT COUNT(*) AS n FROM archive_pin_rows").get()!.n, 0);
  } finally { cancel.abort(); previous.resolve(); readers.close(); f.close(); }
});

test("a stopped archive mark worker resumes its pending request", async () => {
  const f = fixture(), file = join(f.dir, "worker.mjs"), marker = join(f.dir, "exited");
  try {
    const real = new URL("../src/read/archive-mark-worker.ts", import.meta.url).href;
    writeFileSync(file, `import { existsSync, writeFileSync } from 'node:fs';\nif (!existsSync(${JSON.stringify(marker)})) { writeFileSync(${JSON.stringify(marker)}, '1'); process.exit(1); }\nawait import(${JSON.stringify(real)});\n`);
    const builder = new ArchiveMarkBuilder(join(f.dir, "stillfail.db"), {}, pathToFileURL(file));
    try {
      await builder.readyIndex();
      assert.ok(existsSync(marker));
      assert.equal(archiveMarksReady(f.store.db), true);
    } finally { await builder.close(); }
  } finally { f.close(); }
});
