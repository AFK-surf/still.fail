import assert from "node:assert/strict";
import { on, once } from "node:events";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Worker } from "node:worker_threads";
import { backfillNextUsageSession, backfillUsageMinutes, installUsageMinutes, MINUTE_SAME_END, MINUTE_SAME_TIME, PENDING_MINUTE_SESSION } from "../src/store/usage-minutes.ts";

function oldDatabase(path = ":memory:") {
  const db = new DatabaseSync(path);
  db.exec(`CREATE TABLE sessions (key TEXT PRIMARY KEY, ws TEXT);
    CREATE TABLE usage (id TEXT PRIMARY KEY, at INTEGER NOT NULL, session TEXT NOT NULL, runtime TEXT NOT NULL, model TEXT,
      input INTEGER NOT NULL, cache_read INTEGER NOT NULL, cache_write INTEGER NOT NULL, cache_write_long INTEGER NOT NULL,
      output INTEGER NOT NULL, calls INTEGER NOT NULL);
    CREATE INDEX usage_session ON usage (session, at);
    INSERT INTO sessions VALUES ('a', 'workspace-a'), ('b', 'workspace-b');`);
  return db;
}

function add(db: DatabaseSync, id: string, session: string, at: number, input = 1, output = 0) {
  db.prepare("INSERT INTO usage VALUES (?, ?, ?, 'claude', 'm', ?, 0, 0, 0, ?, 1)").run(id, at, session, input, output);
}

function totals(db: DatabaseSync) {
  return db.prepare("SELECT session, minute, runtime, model, calls, tokens FROM usage_minute ORDER BY session, minute, runtime, model").all();
}

function expected(db: DatabaseSync) {
  return db.prepare(`SELECT session, CASE WHEN at >= 0 THEN at / 60000 ELSE -1 - ((-1 - at) / 60000) END AS minute,
    runtime, COALESCE(model, '') AS model, SUM(calls) AS calls, SUM(input + cache_read + cache_write + cache_write_long + output) AS tokens
    FROM usage GROUP BY session, minute, runtime, model ORDER BY session, minute, runtime, model`).all();
}

function quarterTotals(db: DatabaseSync) {
  return db.prepare("SELECT session, quarter, runtime, model, calls, tokens FROM usage_day_quarters ORDER BY session, quarter, runtime, model").all();
}

function expectedQuarters(db: DatabaseSync) {
  return db.prepare(`SELECT session, CASE WHEN at >= 0 THEN at / 900000 ELSE -1 - ((-1 - at) / 900000) END AS quarter,
    runtime, COALESCE(model, '') AS model, SUM(calls) AS calls, SUM(input + cache_read + cache_write + cache_write_long + output) AS tokens
    FROM usage GROUP BY session, quarter, runtime, model ORDER BY session, quarter, runtime, model`).all();
}

test("old usage is filled by session in bounded batches while writes stay correct", () => {
  const db = oldDatabase();
  try {
    db.exec("BEGIN");
    for (let n = 0; n < 12; n++) add(db, `a${n}`, "a", n * 60_000);
    for (let n = 0; n < 2_000; n++) add(db, `b${n}`, "b", 42);
    db.exec("COMMIT");
    installUsageMinutes(db);
    for (const sql of [MINUTE_SAME_TIME, MINUTE_SAME_END]) {
      const params = sql === MINUTE_SAME_TIME ? ["b", 42, 1, 3] : ["b", 42, 1, 2_000, 3];
      const plan = db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...params) as { detail: string }[];
      assert.match(plan.map((r) => r.detail).join(" | "), /usage_session \(session=\? AND at=\? AND rowid>\?/);
    }
    const first = backfillUsageMinutes(db, "a", 3);
    assert.equal(first.done, false);
    assert.equal(first.processed, 3);
    assert.equal((db.prepare(PENDING_MINUTE_SESSION).get("workspace-a") as { session: string }).session, "a");
    db.prepare("UPDATE sessions SET ws = 'workspace-c' WHERE key = 'a'").run();
    assert.equal(db.prepare(PENDING_MINUTE_SESSION).get("workspace-a"), undefined);
    assert.equal((db.prepare(PENDING_MINUTE_SESSION).get("workspace-c") as { session: string }).session, "a",
      "an unfinished session is checked in its new workspace");
    db.prepare("UPDATE sessions SET ws = 'workspace-a' WHERE key = 'a'").run();
    // A late call behind the cursor, one ahead of it, and an update/delete of old calls not filled yet.
    add(db, "late-before", "a", -1, 2);
    add(db, "late-middle", "a", 7 * 60_000 + 1, 3);
    db.prepare("UPDATE usage SET output = 7 WHERE id = 'a10'").run();
    db.prepare("DELETE FROM usage WHERE id = 'a11'").run();
    db.prepare("DELETE FROM usage WHERE id = 'a0'").run();
    add(db, "a0", "a", 1, 4);
    for (let batch = 0; ; batch++) {
      assert.ok(batch < 20, "the session's backfill makes progress");
      const step = backfillUsageMinutes(db, "a", 3);
      assert.ok(step.processed <= 3, "a batch examines at most three old calls");
      if (step.done) break;
    }
    assert.deepEqual(totals(db), expected(db).filter((r: any) => r.session === "a"));
    assert.deepEqual(quarterTotals(db), expectedQuarters(db).filter((r: any) => r.session === "a"));
    assert.equal(db.prepare(PENDING_MINUTE_SESSION).get("workspace-a"), undefined, "completion removes the session from the pending lookup");
    assert.equal((db.prepare("SELECT COUNT(*) AS n FROM usage_minute WHERE session = 'b'").get() as { n: number }).n, 0,
      "another workspace's growing history was not backfilled for this session");
    assert.equal((db.prepare("SELECT ws FROM usage_minute_scope WHERE session = 'a'").get() as { ws: string }).ws, "workspace-a");
    db.prepare("UPDATE sessions SET ws = 'workspace-c' WHERE key = 'a'").run();
    assert.equal((db.prepare("SELECT ws FROM usage_minute_scope WHERE session = 'a'").get() as { ws: string }).ws, "workspace-c");
    db.prepare("DELETE FROM sessions WHERE key = 'a'").run();
    assert.equal((db.prepare("SELECT ws FROM usage_minute_scope WHERE session = 'a'").get() as { ws: string | null }).ws, null);
    for (let batch = 0; ; batch++) {
      assert.ok(batch < 100, "background work reaches the other session");
      const step = backfillNextUsageSession(db, 32);
      assert.ok(step.processed <= 32);
      if (step.done) break;
    }
    assert.deepEqual(totals(db), expected(db));
    assert.deepEqual(quarterTotals(db), expectedQuarters(db));
    add(db, "after", "a", 60_001, 5, 1);
    db.prepare("UPDATE usage SET output = 9 WHERE id = 'after'").run();
    db.prepare("DELETE FROM usage WHERE id = 'a1'").run();
    assert.deepEqual(totals(db), expected(db), "old and new stations' writes keep the finished index current");
    assert.deepEqual(quarterTotals(db), expectedQuarters(db), "quarter summaries follow those writes too");
  } finally {
    db.close();
  }
});

test("a partial minute index resumes after the database is reopened", () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-minutes-"));
  const path = join(dir, "old.db");
  try {
    let db = oldDatabase(path);
    for (let n = 0; n < 8; n++) add(db, `a${n}`, "a", n * 60_000);
    installUsageMinutes(db);
    assert.equal(backfillUsageMinutes(db, "a", 2).processed, 2);
    db.close();
    db = new DatabaseSync(path);
    try {
      let done = false;
      for (let n = 0; n < 10 && !done; n++) done = backfillUsageMinutes(db, "a", 2).done;
      assert.ok(done);
      assert.deepEqual(totals(db), expected(db));
      assert.deepEqual(quarterTotals(db), expectedQuarters(db));
    } finally {
      db.close();
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("checking whether a workspace is ready skips all of its completed sessions", () => {
  const db = oldDatabase();
  try {
    installUsageMinutes(db);
    db.exec("BEGIN");
    const session = db.prepare("INSERT INTO sessions (key, ws) VALUES (?, 'workspace-a')");
    for (let n = 0; n < 2_000; n++) {
      const key = `session-${n}`;
      session.run(key);
      add(db, `call-${n}`, key, 1);
    }
    db.exec("COMMIT");
    assert.equal(db.prepare(PENDING_MINUTE_SESSION).get("workspace-a"), undefined);
    const plan = db.prepare(`EXPLAIN QUERY PLAN ${PENDING_MINUTE_SESSION}`).all("workspace-a") as { detail: string }[];
    assert.match(plan.map((r) => r.detail).join(" | "), /usage_minute_scope_ws \(ws=\? AND done=\?\)/,
      "the lookup must seek directly to unfinished sessions, not examine every completed session");
  } finally {
    db.close();
  }
});

test("minute backfill waits for a foreground writer, then catches up", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-minute-priority-"));
  const path = join(dir, "old.db");
  const db = oldDatabase(path);
  const priority = new Int32Array(new SharedArrayBuffer(8));
  let worker: Worker | null = null;
  try {
    db.exec("PRAGMA journal_mode = WAL");
    for (let n = 0; n < 100; n++) add(db, `a${n}`, "a", n * 60_000);
    installUsageMinutes(db);
    Atomics.store(priority, 0, 1);
    worker = new Worker(new URL("../src/usage/minute-worker.ts", import.meta.url), { workerData: { path, priority: priority.buffer } });
    const [notice] = await once(worker, "message") as [{ foreground?: boolean }];
    assert.equal(notice.foreground, true);
    assert.equal((db.prepare("SELECT COUNT(*) AS n FROM usage_minute").get() as { n: number }).n, 0);
    db.prepare("UPDATE sessions SET ws = 'workspace-c' WHERE key = 'a'").run();
    Atomics.store(priority, 0, 0);
    const [complete] = await once(worker, "message") as [{ complete?: boolean }];
    assert.equal(complete.complete, true);
    assert.deepEqual(totals(db), expected(db));
    assert.equal((db.prepare("SELECT ws FROM usage_minute_scope WHERE session = 'a'").get() as { ws: string }).ws, "workspace-c");
  } finally {
    if (worker !== null) await worker.terminate();
    db.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a workspace whose minutes are ready does not wait for foreground writes or another workspace's backfill", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-minute-ready-"));
  const path = join(dir, "old.db");
  const db = oldDatabase(path);
  const priority = new Int32Array(new SharedArrayBuffer(8));
  let worker: Worker | null = null;
  try {
    db.exec("PRAGMA journal_mode = WAL; CREATE INDEX sessions_ws ON sessions (key, ws)");
    add(db, "a1", "a", 1);
    for (let n = 0; n < 100; n++) add(db, `b${n}`, "b", n * 60_000);
    installUsageMinutes(db);
    assert.equal(backfillUsageMinutes(db, "a").done, true);
    const empty = db.prepare("INSERT INTO sessions VALUES (?, 'workspace-a')");
    for (let n = 0; n < 320; n++) empty.run(`empty-${n}`);
    Atomics.store(priority, 0, 1);
    worker = new Worker(new URL("../src/usage/minute-worker.ts", import.meta.url), { workerData: { path, priority: priority.buffer } });
    const messages = on(worker, "message");
    const next = async () => (await messages.next()).value![0] as { id?: number; foreground?: boolean; request?: number };
    const blocked = async (id: number) => {
      for (;;) {
        const message = await next();
        if (message.foreground && message.request === id) return;
        assert.equal(message.id, undefined, "a different request cannot finish yet");
      }
    };
    const busy = await next();
    assert.equal(busy.foreground, true);
    worker.postMessage({ id: 1, viewer: { workspace: "workspace-a", home: false } });
    const answer = await next();
    assert.equal(answer.id, 1, "a completed workspace needs no backfill write");
    assert.equal((db.prepare("SELECT COUNT(*) AS n FROM usage_minute WHERE session = 'b'").get() as { n: number }).n, 0);

    worker.postMessage({ id: 2, viewer: { workspace: "workspace-b", home: false } });
    await blocked(2);
    worker.postMessage({ id: 3, viewer: { workspace: "workspace-a", home: false } });
    await blocked(2);
    worker.postMessage({ id: 4, viewer: { workspace: "workspace-a", home: false } });
    const behind = await next();
    assert.equal(behind.id, 3, "a ready workspace passes a different workspace waiting for a write");
    await messages.return?.();
  } finally {
    if (worker !== null) await worker.terminate();
    db.close();
    rmSync(dir, { recursive: true, force: true });
  }
});
