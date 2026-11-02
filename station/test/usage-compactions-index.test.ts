import assert from "node:assert/strict";
import { once } from "node:events";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Worker } from "node:worker_threads";
import { backfillUsageCompactions, installUsageCompactions, usageCompactionsReady } from "../src/store/usage-compactions.ts";

function oldDatabase(path = ":memory:") {
  const db = new DatabaseSync(path);
  db.exec(`CREATE TABLE usage (id TEXT PRIMARY KEY, session TEXT NOT NULL, at INTEGER NOT NULL, profile TEXT, model TEXT, context INTEGER, subagent INTEGER NOT NULL);
    CREATE TABLE usage_compactions (at INTEGER NOT NULL, model TEXT NOT NULL, point INTEGER NOT NULL);`);
  return db;
}

function add(db: DatabaseSync, id: string, at: number, context: number | null, session = "a", subagent = 0) {
  db.prepare("INSERT INTO usage (id, session, at, profile, model, context, subagent) VALUES (?, ?, ?, 'cc', 'm', ?, ?)")
    .run(id, session, at, context, subagent);
}

function actual(db: DatabaseSync) {
  return db.prepare("SELECT id, at, model, point FROM usage_compaction_events ORDER BY id").all();
}

function expected(db: DatabaseSync) {
  return db.prepare(`SELECT id, at, model, before AS point FROM (
    SELECT id, at, model, context, profile, LAG(context) OVER w AS before, LAG(profile) OVER w AS was, LAG(model) OVER w AS previous_model
    FROM usage WHERE subagent = 0 WINDOW w AS (PARTITION BY session ORDER BY at, id))
    WHERE model IS NOT NULL AND before >= 50000 AND context * 2 < before AND profile IS was AND model IS previous_model ORDER BY id`).all();
}

test("old calls fill in bounded batches and converge with late writes and deletes", () => {
  const db = oldDatabase();
  try {
    db.exec("INSERT INTO usage (rowid, id, session, at, profile, model, context, subagent) VALUES (-2, 'negative', 'z', 1, 'cc', 'm', 120000, 0)");
    add(db, "a", 1_000, 120_000);
    add(db, "c", 3_000, 20_000);
    for (let n = 0; n < 12; n++) add(db, `sub${n}`, n * 100, null, "a", 1);
    installUsageCompactions(db);
    assert.equal(usageCompactionsReady(db), false);
    assert.deepEqual(backfillUsageCompactions(db, 2), { done: false, processed: 2 });
    add(db, "b", 2_000, 80_000);
    db.prepare("DELETE FROM usage WHERE id = 'a'").run();
    add(db, "a", 1_000, 120_000);
    for (let batch = 0; ; batch++) {
      assert.ok(batch < 20, "the cursor moves toward the old end");
      const result = backfillUsageCompactions(db, 2);
      assert.ok(result.processed <= 2);
      if (result.done) break;
    }
    assert.equal(usageCompactionsReady(db), true);
    assert.deepEqual(actual(db), expected(db));
    db.prepare("DELETE FROM usage WHERE id = 'b'").run();
    assert.deepEqual(actual(db), expected(db));
    add(db, "d", 4_000, 90_000);
    add(db, "e", 4_000, 10_000);
    assert.deepEqual(actual(db), expected(db));
    db.prepare("UPDATE usage SET at = 500, context = 140000 WHERE id = 'c'").run();
    assert.deepEqual(actual(db), expected(db), "a corrected call revises both of its neighborhoods");
    db.prepare("UPDATE usage SET session = 'z', subagent = 1 WHERE id = 'd'").run();
    assert.deepEqual(actual(db), expected(db), "a call changed to a subagent no longer separates main calls");
    add(db, "f", 5_000, 130_000);
    add(db, "g", 6_000, 10_000);
    db.prepare("UPDATE usage SET profile = 'other' WHERE id = 'f'").run();
    assert.deepEqual(actual(db), expected(db), "different profiles are not a compaction");
    db.prepare("UPDATE usage SET profile = 'cc', model = NULL WHERE id = 'f'").run();
    assert.deepEqual(actual(db), expected(db), "an unknown model still separates its neighboring calls");
    db.prepare("UPDATE usage SET model = 'm', context = NULL WHERE id = 'f'").run();
    assert.deepEqual(actual(db), expected(db), "an unknown context does not establish a compaction point");
  } finally {
    db.close();
  }
});

test("an unfinished disk index resumes in its worker after reopening", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-compactions-"));
  const path = join(dir, "stillfail.db");
  try {
    let db = oldDatabase(path);
    add(db, "c", 3_000, 20_000);
    add(db, "a", 1_000, 120_000);
    add(db, "b", 2_000, 80_000);
    installUsageCompactions(db);
    assert.equal(backfillUsageCompactions(db, 1).processed, 1);
    db.close();
    const worker = new Worker(new URL("../src/usage/compaction-worker.ts", import.meta.url), { workerData: { path } });
    const [code] = await once(worker, "exit");
    assert.equal(code, 0);
    db = new DatabaseSync(path);
    try {
      assert.equal(usageCompactionsReady(db), true);
      assert.deepEqual(actual(db), expected(db));
    } finally {
      db.close();
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("the worker resumes the same backfill when another connection releases its write lock", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-compactions-busy-"));
  const path = join(dir, "stillfail.db");
  const db = oldDatabase(path);
  let worker: Worker | null = null;
  try {
    db.exec("PRAGMA journal_mode = WAL");
    add(db, "a", 1, 120_000);
    add(db, "b", 2, 20_000);
    installUsageCompactions(db);
    db.exec("BEGIN IMMEDIATE");
    worker = new Worker(new URL("../src/usage/compaction-worker.ts", import.meta.url), { workerData: { path } });
    const [notice] = await once(worker, "message") as [{ waiting?: boolean }];
    assert.equal(notice.waiting, true);
    db.exec("COMMIT");
    const [code] = await once(worker, "exit");
    worker = null;
    assert.equal(code, 0);
    assert.equal(usageCompactionsReady(db), true);
    assert.deepEqual(actual(db), expected(db));
  } finally {
    if (worker !== null) await worker.terminate();
    try { db.exec("ROLLBACK"); } catch { /* already committed */ }
    db.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a waiting foreground writer gets the connection before another backfill batch", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-compactions-priority-"));
  const path = join(dir, "stillfail.db");
  const db = oldDatabase(path);
  const priority = new Int32Array(new SharedArrayBuffer(8));
  let worker: Worker | null = null;
  try {
    db.exec("PRAGMA journal_mode = WAL");
    db.exec("CREATE TABLE foreground (n INTEGER)");
    for (let n = 0; n < 100; n++) add(db, `call-${n}`, n, 100_000);
    installUsageCompactions(db);
    db.exec("BEGIN IMMEDIATE");
    worker = new Worker(new URL("../src/usage/compaction-worker.ts", import.meta.url), { workerData: { path, priority: priority.buffer } });
    const [busy] = await once(worker, "message") as [{ waiting?: boolean }];
    assert.equal(busy.waiting, true, "the worker has encountered the other connection's write lock");
    Atomics.store(priority, 0, 1); // A write is waiting on the station's connection.
    db.exec("COMMIT");
    const [yielded] = await once(worker, "message") as [{ foreground?: boolean }];
    assert.equal(yielded.foreground, true, "the next batch yields while the station is trying to write");
    assert.equal((db.prepare("SELECT COUNT(*) AS n FROM usage_main_calls").get() as { n: number }).n, 0);
    db.prepare("INSERT INTO foreground VALUES (1)").run();
    Atomics.store(priority, 0, 0);
    const [code] = await once(worker, "exit");
    worker = null;
    assert.equal(code, 0);
    assert.equal(usageCompactionsReady(db), true);
    assert.equal((db.prepare("SELECT COUNT(*) AS n FROM foreground").get() as { n: number }).n, 1);
  } finally {
    if (worker !== null) await worker.terminate();
    try { db.exec("ROLLBACK"); } catch { /* already committed */ }
    db.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("neighbors seek only main calls of the requested session", () => {
  const db = oldDatabase();
  try {
    installUsageCompactions(db);
    add(db, "first", 1, 120_000);
    add(db, "next", 3, 20_000);
    db.exec("BEGIN");
    for (let n = 0; n < 2_000; n++) {
      add(db, `sub${n}`, 2, null, "a", 1);
      add(db, `other${n}`, n, 1, "other");
    }
    db.exec("COMMIT");
    let examined = 0;
    db.function("examined", (_id) => { examined++; return 1; });
    const neighbor = `SELECT id FROM usage_main_calls WHERE session = ? AND (at, id) > (?, ?) AND examined(id)
      ORDER BY at, id LIMIT 1`;
    assert.equal((db.prepare(neighbor).get("a", 1, "first") as { id: string }).id, "next");
    assert.equal(examined, 1, "other sessions and subagent calls add no examined main calls");
    const plan = db.prepare(`EXPLAIN QUERY PLAN ${neighbor}`).all("a", 1, "first") as { detail: string }[];
    assert.match(plan.map((p) => p.detail).join(" | "), /SEARCH usage_main_calls USING PRIMARY KEY \(session=\? AND \(at,id\)>\(\?,\?\)\)/);
    assert.ok(!plan.some((p) => p.detail.includes("TEMP B-TREE")));
  } finally {
    db.close();
  }
});

test("reopening repairs an older compaction trigger without rebuilding the index", () => {
  const db = oldDatabase();
  try {
    installUsageCompactions(db);
    add(db, "a", 1, 120_000);
    db.exec("DROP TRIGGER usage_compactions_add; CREATE TRIGGER usage_compactions_add AFTER INSERT ON usage BEGIN SELECT 1; END;");
    installUsageCompactions(db);
    add(db, "b", 2, 20_000);
    assert.deepEqual(actual(db), expected(db));
    assert.equal(usageCompactionsReady(db), true);
  } finally {
    db.close();
  }
});
