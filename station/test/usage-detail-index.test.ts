import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { backfillNextUsageDetail, backfillUsageDetail, backfillUsageDetailMove, detailQuery, installUsageDetail, removeReplacedStatements, usageDetailReady } from "../src/store/usage-detail.ts";

function older(path = ":memory:") {
  const db = new DatabaseSync(path);
  db.exec(`CREATE TABLE sessions (key TEXT PRIMARY KEY, ws TEXT, token TEXT UNIQUE);
    CREATE TABLE usage (id TEXT PRIMARY KEY, at INTEGER NOT NULL, session TEXT NOT NULL, thread INTEGER, person TEXT,
      profile TEXT, runtime TEXT NOT NULL, model TEXT, fast INTEGER NOT NULL DEFAULT 0, calls INTEGER NOT NULL,
      input INTEGER NOT NULL, cache_read INTEGER NOT NULL, cache_write INTEGER NOT NULL, cache_write_long INTEGER NOT NULL, output INTEGER NOT NULL);
    CREATE INDEX usage_session ON usage (session, at);
    INSERT INTO sessions VALUES ('a', 'A', 'a'), ('b', 'B', 'b');`);
  return db;
}
function add(db: DatabaseSync, id: string, session: string, at: number, input = 1) {
  db.prepare("INSERT INTO usage VALUES (?, ?, ?, NULL, NULL, NULL, 'claude', 'm', 0, 1, ?, 0, 0, 0, 0)").run(id, at, session, input);
}
function actual(db: DatabaseSync, level: number) {
  return db.prepare(`SELECT session, bucket, SUM(records) AS records, SUM(calls) AS calls, SUM(input) AS input,
    SUM(output) AS output FROM usage_detail WHERE level = ? GROUP BY session, bucket ORDER BY session, bucket`).all(level);
}
function expected(db: DatabaseSync, size: number) {
  return db.prepare(`SELECT session, CASE WHEN at >= 0 THEN at / ${size} ELSE -1 - ((-1 - at) / ${size}) END AS bucket,
    COUNT(*) AS records, SUM(calls) AS calls, SUM(input) AS input, SUM(output) AS output
    FROM usage GROUP BY session, bucket ORDER BY session, bucket`).all();
}

test("detail statistics fill old calls in bounded resumable batches and follow concurrent writes", () => {
  const db = older();
  try {
    for (let i = 0; i < 20; i++) add(db, `a${i}`, "a", i * 1000);
    for (let i = 0; i < 120; i++) add(db, `b${i}`, "b", 1);
    installUsageDetail(db);
    assert.equal(backfillUsageDetail(db, "a", 3).processed, 3);
    add(db, "before", "a", -1, 2);
    add(db, "between", "a", 12_345, 3);
    db.prepare("UPDATE usage SET output = 9 WHERE id = 'a17'").run();
    db.prepare("DELETE FROM usage WHERE id = 'a18'").run();
    db.prepare("DELETE FROM usage WHERE id = 'a0'").run();
    add(db, "a0", "a", 1, 5);
    for (let n = 0; ; n++) {
      assert.ok(n < 60);
      const step = backfillNextUsageDetail(db, 3);
      assert.ok(step.processed <= 3);
      if (step.done) break;
    }
    for (const [level, size] of [900_000, 60_000, 1_000, 1].entries()) {
      assert.deepEqual(actual(db, level), expected(db, size));
    }
    db.prepare("UPDATE sessions SET ws = 'C' WHERE key = 'a'").run();
    assert.equal((db.prepare("SELECT ws FROM usage_detail_scope WHERE session = 'a'").get() as { ws: string }).ws, "C");
  } finally { db.close(); }
});

test("a range seeks the workspace and time, and moving a session updates lookups in bounded batches", () => {
  const db = older();
  try {
    installUsageDetail(db);
    for (let i = 0; i < 80; i++) add(db, `a${i}`, "a", i * 60_000);
    add(db, "b", "b", 1);
    const query = detailQuery(0n, 90_000_000n, 0n, { workspace: "A", home: false })!;
    const plan = (db.prepare(`EXPLAIN QUERY PLAN ${query.sql}`).all(...query.args) as { detail: string }[]).map((r) => r.detail).join(" | ");
    assert.match(plan, /usage_detail_lookup.*scope=\? AND level=\? AND bucket>\? AND bucket<\?/);
    const before = db.prepare("SELECT COUNT(*) AS n FROM usage_detail_lookup WHERE session = 'a' AND scope = 'WA'").get() as { n: number };
    db.prepare("UPDATE sessions SET ws = 'B' WHERE key = 'a'").run();
    assert.equal((db.prepare("SELECT COUNT(*) AS n FROM usage_detail_lookup WHERE session = 'a' AND scope = 'WA'").get() as { n: number }).n, before.n,
      "the move did not rewrite the session's history on the foreground connection");
    assert.equal(usageDetailReady(db, { workspace: "A", home: false }), false);
    assert.equal(usageDetailReady(db, { workspace: "B", home: false }), false);
    assert.equal(usageDetailReady(db, { workspace: "C", home: false }), true);
    for (let n = 0; ; n++) {
      assert.ok(n < 200);
      const step = backfillUsageDetailMove(db, 3);
      assert.ok(step.processed <= 3);
      if (step.done) break;
    }
    assert.equal(usageDetailReady(db, { workspace: "A", home: false }), true);
    assert.equal(usageDetailReady(db, { workspace: "B", home: false }), true);
    assert.equal((db.prepare("SELECT COUNT(*) AS n FROM usage_detail_lookup WHERE session = 'a' AND scope = 'WB'").get() as { n: number }).n, before.n);
  } finally { db.close(); }
});

test("replacing and updating a recorded call changes its contribution exactly once", () => {
  for (const recursive of ["OFF", "ON"]) {
    const db = older();
    try {
      db.exec(`PRAGMA recursive_triggers = ${recursive}`);
      installUsageDetail(db);
      add(db, "one", "a", 2, 3);
      add(db, "two", "a", 2, 4);
      db.prepare(`INSERT OR IGNORE INTO usage VALUES (?, ?, ?, NULL, NULL, NULL, 'claude', 'm', 0, 1, ?, 0, 0, 0, 0)`)
        .run("two", 20, "a", 99);
      db.prepare(`INSERT OR REPLACE INTO usage VALUES (?, ?, ?, NULL, NULL, NULL, 'claude', 'm', 0, 1, ?, 0, 0, 0, 0)`)
        .run("one", 3, "a", 5);
      db.prepare("UPDATE usage SET output = 7 WHERE id = 'two'").run();
      db.prepare("UPDATE usage SET output = 7 WHERE id = 'two'").run();
      for (const [level, size] of [900_000, 60_000, 1_000, 1].entries()) {
        assert.deepEqual(actual(db, level), expected(db, size), `recursive triggers ${recursive}`);
      }
    } finally { db.close(); }
  }
});

test("looking for a replaced call seeks its own buckets instead of scanning the statistics", () => {
  const db = older();
  try {
    installUsageDetail(db);
    for (const sql of removeReplacedStatements("?1")) {
      const plan = (db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all("one") as { detail: string }[]).map((r) => r.detail);
      assert.ok(plan.some((line) => line.includes("SEARCH usage_detail USING PRIMARY KEY (session=? AND level=? AND bucket=?")), plan.join(" | "));
      assert.ok(!plan.some((line) => line.startsWith("SCAN usage_detail")), plan.join(" | "));
    }
  } finally { db.close(); }
});

test("detail totals follow repeated moves, replacements and writes while a move is unfinished", () => {
  const db = older();
  try {
    installUsageDetail(db);
    for (let i = 0; i < 40; i++) add(db, `a${i}`, "a", i * 1000, i + 1);
    add(db, "b1", "b", 1, 2);
    db.prepare("UPDATE sessions SET ws = 'B' WHERE key = 'a'").run();
    assert.equal(backfillUsageDetailMove(db, 3, "a").processed, 3);
    add(db, "late", "a", -1000, 6);
    db.prepare("DELETE FROM usage WHERE id = 'a5'").run();
    db.prepare("UPDATE sessions SET ws = 'C' WHERE key = 'a'").run();
    assert.equal(usageDetailReady(db, { workspace: "A", home: false }), false);
    assert.equal(usageDetailReady(db, { workspace: "B", home: false }), false);
    assert.equal(usageDetailReady(db, { workspace: "C", home: false }), false);
    while (!backfillUsageDetailMove(db, 4).done) { /* bounded batches */ }
    db.exec("INSERT OR REPLACE INTO sessions VALUES ('a', 'A', 'a')");
    while (!backfillUsageDetailMove(db, 4).done) { /* the same session was replaced */ }
    db.exec("INSERT OR REPLACE INTO sessions VALUES ('c', 'C', 'b')");
    while (!backfillUsageDetailMove(db, 4).done) { /* another session's token was replaced */ }
    db.exec("UPDATE sessions SET key = 'renamed' WHERE key = 'a'");
    while (!backfillUsageDetailMove(db, 4).done) { /* the old session's usage is now owned by home */ }
    for (const viewer of [null, { workspace: "A", home: false }, { workspace: "B", home: false },
      { workspace: "C", home: false }, { workspace: "C", home: true }]) {
      assert.equal(usageDetailReady(db, viewer), true);
      const query = detailQuery(-2000n, 100_000n, 0n, viewer)!;
      const got = db.prepare(query.sql).all(...query.args) as { session: string; calls: number; input: number }[];
      const sums = new Map<string, [number, number]>();
      for (const row of got) {
        const prior = sums.get(row.session) ?? [0, 0];
        sums.set(row.session, [prior[0] + row.calls, prior[1] + row.input]);
      }
      const expected = db.prepare(`SELECT u.session, SUM(u.calls) AS calls, SUM(u.input) AS input FROM usage u
        LEFT JOIN sessions s ON s.key = u.session WHERE u.at >= -2000 AND u.at < 100000
        AND (?1 IS NULL OR s.ws = ?1 OR (?2 AND s.ws IS NULL)) GROUP BY u.session`)
        .all(viewer?.workspace ?? null, viewer?.home === false ? 0 : 1) as { session: string; calls: number; input: number }[];
      assert.deepEqual([...sums].sort(), expected.map((r) => [r.session, [r.calls, r.input]]).sort());
    }
  } finally { db.close(); }
});

test("a partially filled detail index resumes after reopening", () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-detail-resume-"));
  const path = join(dir, "old.db");
  let db = older(path);
  try {
    for (let i = 0; i < 12; i++) add(db, `a${i}`, "a", i * 1000);
    installUsageDetail(db);
    assert.equal(backfillUsageDetail(db, "a", 3).processed, 3);
    db.close();
    db = new DatabaseSync(path);
    while (!backfillNextUsageDetail(db, 3).done) { /* resume the saved cursor */ }
    for (const [level, size] of [900_000, 60_000, 1_000, 1].entries()) {
      assert.deepEqual(actual(db, level), expected(db, size));
    }
  } finally { db.close(); rmSync(dir, { recursive: true, force: true }); }
});
