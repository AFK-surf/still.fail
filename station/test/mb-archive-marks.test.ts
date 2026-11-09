// The MoonBit builder of the archive marks (station/mb, src/marks) prepares them as `archiveMarksStep` does: the same
// old pins and kept chats, batch by batch, give the same answers and the same tables.
import assert from "node:assert/strict";
import { chmodSync, existsSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { ArchiveMarkBuilder } from "../src/read/archive-mark-builder.ts";
import { MbProcess, mbReaderBinary } from "../src/read/mb-reader.ts";
import { archiveMarksReady, archiveMarksStep, installArchiveMarkIndex } from "../src/store/archive-mark-index.ts";
import { Store } from "../src/store/store.ts";

const binary = mbReaderBinary();

/// A station's database whose marks are from before their index: 600 pins (some gone again, leaving gaps) and 300
/// kept chats, the index installed over them, nothing of them prepared.
function old() {
  const dir = mkdtempSync(join(tmpdir(), "mb-archive-marks-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path, join(dir, "archive")), db = store.db;
  for (const row of db.prepare("SELECT name FROM sqlite_master WHERE type='trigger' AND (name LIKE 'archive_pin_%' OR name LIKE 'archive_keep_%')").all() as { name: string }[]) db.exec(`DROP TRIGGER ${row.name}`);
  db.exec("DROP TABLE archive_pin_rows; DROP TABLE archive_keep_rows; DROP TABLE archive_pin_replaced; DROP TABLE archive_keep_replaced; DROP TABLE archive_mark_meta");
  const pin = db.prepare("INSERT INTO pins(viewer, session, at) VALUES (?, ?, ?)");
  for (let i = 0; i < 600; i++) pin.run(`person${i % 7}`, `session-${i % 211}`, i);
  db.exec("DELETE FROM pins WHERE rowid % 13 = 0");
  const keep = db.prepare("INSERT INTO kept_chats(viewer, thread) VALUES (?, ?)");
  for (let i = 0; i < 300; i++) keep.run(`person${i % 5}`, i * 3);
  installArchiveMarkIndex(db);
  return { dir, path, store, close: () => { store.close(); rmSync(dir, { recursive: true, force: true }); } };
}

/// What the preparation leaves: the lookups and the markers, as text.
function tables(store: Store): string {
  const all = (sql: string) => JSON.stringify(store.db.prepare(sql).all());
  return [
    all("SELECT session, position FROM archive_pin_rows ORDER BY session, position"),
    all("SELECT thread, position FROM archive_keep_rows ORDER BY thread, position"),
    all("SELECT kind, version, last_rowid, end_rowid, complete FROM archive_mark_meta ORDER BY kind"),
  ].join("\n");
}

test("the MoonBit builder prepares the archive marks batch by batch as archiveMarksStep does", async () => {
  assert.notEqual(binary, null, "the MoonBit reader is built (station/mb/build.sh, or STILLFAIL_MB_READER)");
  const ts = old(), mb = old();
  const builder = new MbProcess(binary!, ["--builder", "archive-marks", "--db", mb.path]);
  try {
    const steps: { ts: boolean; mb: boolean }[] = [];
    for (let i = 0; i < 20; i++) {
      const answered = new Promise<{ done: boolean; error?: string }>((resolve) => builder.once("message", resolve));
      builder.postMessage({ scope: "all" });
      const ours = await answered;
      assert.equal(ours.error, undefined);
      steps.push({ ts: archiveMarksStep(ts.store.db).done, mb: ours.done });
      if (ours.done) break;
    }
    // some batches of each kind, then done, the same each time
    assert.ok(steps.length >= 4, JSON.stringify(steps));
    assert.deepEqual(steps.map((s) => s.mb), steps.map((s) => s.ts));
    assert.equal(steps.at(-1)!.mb, true);
    assert.equal(tables(mb.store), tables(ts.store));
    assert.equal(archiveMarksReady(mb.store.db), true);
    // a pin made after: the triggers keep it, and the builder has nothing left to do
    mb.store.db.exec("INSERT INTO pins(viewer, session, at) VALUES ('late', 'session-late', 9)");
    assert.equal(mb.store.archiveMarks().pinned("session-late"), true);
    const again = new Promise<{ done: boolean }>((resolve) => builder.once("message", resolve));
    builder.postMessage({ scope: "all" });
    assert.deepEqual(await again, { done: true });
  } finally {
    await builder.terminate();
    ts.close(); mb.close();
  }
});

test("a batch asked while the station writes waits its turn, and what it was asked is still done", async () => {
  assert.notEqual(binary, null);
  const f = old();
  const priority = new SharedArrayBuffer(8), flags = new Int32Array(priority);
  // a foreground write announced (store/backfill.ts `foreground`): the builder may not take the permit meanwhile
  Atomics.add(flags, 0, 1);
  const builder = new ArchiveMarkBuilder(f.path, { priority }, undefined, binary);
  try {
    const ready = builder.readyIndex();
    let settled = false;
    void ready.then(() => { settled = true; }, () => { settled = true; });
    await new Promise((resolve) => setTimeout(resolve, 100));
    assert.equal(settled, false, "nothing prepared while the write is pending");
    assert.equal(f.store.db.prepare("SELECT COUNT(*) AS n FROM archive_pin_rows").get()!.n, 0);
    Atomics.sub(flags, 0, 1);
    await ready;
    assert.equal(archiveMarksReady(f.store.db), true);
    assert.equal(Atomics.load(flags, 1), 0, "the permit given back");
  } finally {
    await builder.close();
    f.close();
  }
});

test("a MoonBit builder that stopped is started again and finishes the request", { skip: process.platform === "win32" }, async () => {
  assert.notEqual(binary, null);
  const f = old(), program = join(f.dir, "builder.sh"), marker = join(f.dir, "exited");
  // the first process ends at once, as one the system stopped; the next is the builder
  writeFileSync(program, `#!/bin/sh\nif [ ! -e '${marker}' ]; then : > '${marker}'; exit 1; fi\nexec '${binary}' "$@"\n`);
  chmodSync(program, 0o755);
  const builder = new ArchiveMarkBuilder(f.path, {}, undefined, program);
  try {
    await builder.readyIndex();
    assert.ok(existsSync(marker), "the first one ended");
    assert.equal(archiveMarksReady(f.store.db), true);
  } finally {
    await builder.close();
    f.close();
  }
});
