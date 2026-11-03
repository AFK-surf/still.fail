import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { backfillNextUsageDetail, backfillUsageDetail, detailQuery, installUsageDetail, removeReplacedStatements, usageDetailReady, usageDetailScopeBySession } from "../src/store/usage-detail.ts";

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

test("a time range reads each session's nearby detail buckets together", () => {
  const db = older();
  try {
    db.exec("UPDATE sessions SET ws = 'A' WHERE key = 'b'");
    installUsageDetail(db, 0);
    for (let i = 0; i < 6; i++) for (const session of ["a", "b"]) add(db, `${session}${i}`, session, i * 900_000);
    const visited: string[] = [];
    db.function("inspect_session", (session) => { visited.push(String(session)); return session; });
    const query = detailQuery(0n, 5_400_000n, 0n, { workspace: "A", home: false })!;
    const sql = query.sql.replaceAll("d.session = target.session", "d.session = inspect_session(target.session)");
    const rows = db.prepare(sql).all(...query.args) as { session: string; calls: number }[];
    assert.deepEqual(rows.map((r) => [r.session, r.calls]), [["a", 6], ["b", 6]]);
    assert.deepEqual(visited, [...visited].sort(), "the lookup does not alternate sessions at every time bucket");
  } finally { db.close(); }
});

test("a moved session's range is sought through its current workspace without rewriting buckets", () => {
  const db = older();
  try {
    installUsageDetail(db, 0);
    for (let i = 0; i < 80; i++) add(db, `a${i}`, "a", i * 60_000);
    add(db, "b", "b", 1);
    const query = detailQuery(0n, 90_000_000n, 0n, { workspace: "A", home: false })!;
    const plan = (db.prepare(`EXPLAIN QUERY PLAN ${query.sql}`).all(...query.args) as { detail: string }[]).map((r) => r.detail).join(" | ");
    assert.match(plan, /usage_detail_lookup.*scope=\? AND level=\? AND bucket>\? AND bucket<\?/);
    const before = db.prepare("SELECT COUNT(*) AS n FROM usage_detail_lookup WHERE session = 'a' AND scope = 'WA'").get() as { n: number };
    db.prepare("UPDATE sessions SET ws = 'B' WHERE key = 'a'").run();
    assert.equal((db.prepare("SELECT COUNT(*) AS n FROM usage_detail_lookup WHERE session = 'a' AND scope = 'WA'").get() as { n: number }).n, before.n,
      "the move did not rewrite the session's history on the foreground connection");
    assert.equal(usageDetailReady(db, { workspace: "A", home: false }), true);
    assert.equal(usageDetailReady(db, { workspace: "B", home: false }), true);
    assert.equal(usageDetailScopeBySession(db, { workspace: "C", home: false }), false);
    for (const [workspace, expectedCalls] of [["A", 0], ["B", 81]] as const) {
      const viewer = { workspace, home: false };
      const moved = detailQuery(0n, 90_000_000n, 0n, viewer, "legacy", usageDetailScopeBySession(db, viewer))!;
      const plan = (db.prepare(`EXPLAIN QUERY PLAN ${moved.sql}`).all(...moved.args) as { detail: string }[]).map((r) => r.detail).join(" | ");
      assert.match(plan, /usage_detail_scope_ws.*ws=\?/);
      assert.match(plan, /SEARCH l USING PRIMARY KEY \(session=\? AND level=\? AND bucket>\? AND bucket<\?\)/);
      const rows = db.prepare(moved.sql).all(...moved.args) as { calls: number }[];
      assert.equal(rows.reduce((n, row) => n + row.calls, 0), expectedCalls);
    }
    assert.equal((db.prepare("SELECT COUNT(*) AS n FROM usage_detail_lookup WHERE session = 'a' AND scope = 'WA'").get() as { n: number }).n, before.n);
  } finally { db.close(); }
});

test("replacing and updating a recorded call changes its contribution exactly once", () => {
  for (const recursive of ["OFF", "ON"]) {
    const db = older();
    try {
      db.exec(`PRAGMA recursive_triggers = ${recursive}`);
      installUsageDetail(db, 0);
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
    installUsageDetail(db, 0);
    for (const sql of removeReplacedStatements("?1")) {
      const plan = (db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all("one") as { detail: string }[]).map((r) => r.detail);
      assert.ok(plan.some((line) => line.includes("SEARCH usage_detail USING PRIMARY KEY (session=? AND level=? AND bucket=?")), plan.join(" | "));
      assert.ok(!plan.some((line) => line.startsWith("SCAN usage_detail")), plan.join(" | "));
    }
  } finally { db.close(); }
});

test("detail totals follow repeated moves, replacements and writes without a history worker", () => {
  const db = older();
  try {
    installUsageDetail(db, 0);
    for (let i = 0; i < 40; i++) add(db, `a${i}`, "a", i * 1000, i + 1);
    add(db, "b1", "b", 1, 2);
    const check = () => {
      for (const viewer of [null, { workspace: "A", home: false }, { workspace: "B", home: false },
        { workspace: "C", home: false }, { workspace: "C", home: true }]) {
        assert.equal(usageDetailReady(db, viewer), true);
        const query = detailQuery(-2000n, 100_000n, 0n, viewer, "legacy", usageDetailScopeBySession(db, viewer))!;
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
    };
    check();
    db.prepare("UPDATE sessions SET ws = 'B' WHERE key = 'a'").run();
    check();
    add(db, "late", "a", -1000, 6);
    db.prepare("DELETE FROM usage WHERE id = 'a5'").run();
    db.prepare("UPDATE sessions SET ws = 'C' WHERE key = 'a'").run();
    check();
    db.exec("INSERT OR REPLACE INTO sessions VALUES ('a', 'A', 'a')");
    check();
    db.exec("INSERT OR REPLACE INTO sessions VALUES ('c', 'C', 'b')");
    check();
    db.exec("UPDATE sessions SET key = 'renamed' WHERE key = 'a'");
    check();
  } finally { db.close(); }
});

test("a partially filled detail index resumes after reopening", () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-detail-resume-"));
  const path = join(dir, "old.db");
  let db = older(path);
  try {
    for (let i = 0; i < 12; i++) add(db, `a${i}`, "a", i * 1000);
    installUsageDetail(db, 0);
    assert.equal(backfillUsageDetail(db, "a", 3).processed, 3);
    db.close();
    db = new DatabaseSync(path);
    while (!backfillNextUsageDetail(db, 3).done) { /* resume the saved cursor */ }
    for (const [level, size] of [900_000, 60_000, 1_000, 1].entries()) {
      assert.deepEqual(actual(db, level), expected(db, size));
    }
  } finally { db.close(); rmSync(dir, { recursive: true, force: true }); }
});
