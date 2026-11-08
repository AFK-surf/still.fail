// The MoonBit builders of an older store's edit and said lookups (station/mb, src/legacy) keep them up as said-worker.ts
// does (`legacyEdits`, `legacySaid`): for the same store, step by step, the same answers and the same tables, with an
// older writer changing messages and edits meanwhile; a store whose merged view must be switched first is left to the
// worker.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { MbProcess, mbReaderBinary } from "../src/read/mb-reader.ts";
import { legacyEditsMaintenanceStep, legacyMergedReadReady } from "../src/store/legacy-edits-build.ts";
import { hasLegacySaid, installLegacySaid, legacySaidScanReady, legacySaidStep } from "../src/store/legacy-said-build.ts";
import { repairMergedEditLookup } from "../src/store/schema.ts";
import { Store } from "../src/store/store.ts";

const binary = mbReaderBinary();

/// What said-worker.ts does for each kind's ask.
const worker = {
  "legacy-edits": (db: DatabaseSync) => {
    if (!legacyMergedReadReady(db)) {
      repairMergedEditLookup(db);
      if (!legacyMergedReadReady(db)) legacyEditsMaintenanceStep(db);
    }
    return legacyMergedReadReady(db);
  },
  "legacy-said": (db: DatabaseSync) => {
    if (hasLegacySaid(db) && !legacySaidScanReady(db)) legacySaidStep(db);
    return !hasLegacySaid(db) || legacySaidScanReady(db);
  },
};
type Kind = keyof typeof worker;

/// An older store: three chats of messages and edits of them, the native edit index gone and the lookups made (as the
/// store does when it opens such a store), nothing of them scanned yet.
function old() {
  const dir = mkdtempSync(join(tmpdir(), "mb-legacy-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path, join(dir, "archive")), db = store.db;
  db.exec("BEGIN");
  const threads = ["a", "b", "c"].map((key) => store.openThread("ember", "CHAT", key, null, null).id);
  const put = db.prepare(`INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at,ts) VALUES(?,?,?,?,?,?,?,?,?)`);
  for (const thread of threads) for (let n = 1; n <= 70; n++) {
    const edit = n % 3 === 0;
    put.run(thread, n, edit ? "edit" : "message", edit ? n - 1 : null, n % 2 ? "person" : "agent", `p${n % 4}`, `entry ${n}`, n, `ts-${n}`);
  }
  db.exec("COMMIT");
  db.exec("DROP INDEX entries_edits");
  repairMergedEditLookup(db);
  installLegacySaid(db);
  const writer = new DatabaseSync(path, { timeout: 5000 });
  return { dir, path, store, threads, writer, close: () => { writer.close(); store.close(); rmSync(dir, { recursive: true, force: true }); } };
}

/// What an older writer does meanwhile, the same on both.
function writes(f: ReturnType<typeof old>, step: number) {
  const w = f.writer, [a, b, c] = f.threads as [number, number, number];
  if (step === 1) {
    w.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at) VALUES(?,200,'edit',1,'agent','x','late edit',200)").run(a);
    w.prepare("UPDATE entries SET target = 4 WHERE thread = ? AND n = 3").run(a);
    w.prepare("UPDATE entries SET author = 'changed' WHERE thread = ? AND n = 5").run(b);
    w.prepare("DELETE FROM entries WHERE thread = ? AND n = 6").run(b);
    w.prepare("INSERT OR REPLACE INTO entries(thread,n,kind,target,author_kind,author,text,at,ts) VALUES(?,71,'message',NULL,'person','by-ts','replaced',71,'ts-7')").run(c);
  }
  if (step === 4) for (let n = 1; n <= 200; n++)
    w.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at) VALUES(?,?,'edit',?,'agent','x','again',?)").run(c, 300 + n, n % 70 + 1, 300 + n);
  if (step === 6) w.prepare("UPDATE entries SET target = NULL WHERE thread = ? AND n = 9").run(a);
}

const bare = (sql: string | null) => (sql ?? "").replace(/\s+/g, "");
function tables(db: DatabaseSync, prefix: string): string {
  const schema = (db.prepare("SELECT type, name, sql FROM sqlite_master WHERE name LIKE ? OR name = 'merged' ORDER BY type, name").all(`${prefix}%`) as { sql: string | null }[])
    .map((r) => ({ ...r, sql: bare(r.sql) }));
  const names = (db.prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE ? ORDER BY name").all(`${prefix}%`) as { name: string }[]).map((r) => r.name);
  return JSON.stringify([schema, names.map((name) => (db.prepare(`SELECT * FROM ${name}`).all() as object[]).map((r) => JSON.stringify(r)).sort())]);
}

for (const [kind, prefix] of [["legacy-edits", "legacy_edit"], ["legacy-said", "legacy_said"]] as [Kind, string][]) {
  test(`the MoonBit builder keeps ${kind} up as the worker does`, async () => {
    assert.notEqual(binary, null, "the MoonBit reader is built (station/mb/build.sh, or STILLFAIL_MB_READER)");
    const ts = old(), mb = old();
    const builder = new MbProcess(binary!, ["--builder", kind, "--db", mb.path]);
    try {
      let step = 0, done = false, dirty = 0;
      for (; step < 40 && !(done && step > 7); step++) {
        writes(ts, step); writes(mb, step);
        const answered = new Promise<{ done: boolean; error?: string; fallback?: boolean }>((resolve) => builder.once("message", resolve));
        builder.postMessage({ thread: 0, [kind === "legacy-edits" ? "legacyEdits" : "legacySaid"]: true });
        const ours = await answered;
        assert.equal(ours.error, undefined);
        assert.equal(ours.fallback, undefined);
        done = worker[kind](ts.store.db);
        assert.equal(ours.done, done, `step ${step}`);
        assert.equal(tables(mb.store.db, prefix), tables(ts.store.db, prefix), `step ${step}`);
        if (kind === "legacy-edits") dirty = Math.max(dirty, (mb.store.db.prepare("SELECT COUNT(*) AS n FROM legacy_edit_dirty").get() as { n: number }).n);
      }
      if (kind === "legacy-edits") assert.ok(dirty > 64, `changed keys folded back in batches (${dirty} at most)`);
      assert.ok(done && step >= 5, `${step} steps`);
      // what the lookups answer is what the messages say
      for (const f of [ts, mb]) assert.deepEqual(
        f.store.db.prepare("SELECT thread, n, text FROM merged ORDER BY thread, n").all(),
        ts.store.db.prepare("SELECT thread, n, text FROM merged ORDER BY thread, n").all());
    } finally {
      await builder.terminate();
      ts.close(); mb.close();
    }
  });
}

test("a store whose merged view must be switched first is left to the worker", async () => {
  assert.notEqual(binary, null);
  const dir = mkdtempSync(join(tmpdir(), "mb-legacy-repair-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path, join(dir, "archive"));
  const builder = new MbProcess(binary!, ["--builder", "legacy-edits", "--db", path]);
  try {
    // (the native edit index removed under a merged view that reads through it)
    store.db.exec("DROP INDEX entries_edits");
    const answered = new Promise<object>((resolve) => builder.once("message", resolve));
    builder.postMessage({ thread: 0, legacyEdits: true });
    assert.deepEqual(await answered, { fallback: true });
  } finally {
    await builder.terminate();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});
