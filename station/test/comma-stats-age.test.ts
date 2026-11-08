import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { installStatsAge, STATS_AGE_CANDIDATES, statsAgeCandidates, statsAgeReady, statsAgeStep } from "../src/comma/stats-age.ts";

const schema = `CREATE TABLE stats_index (key TEXT PRIMARY KEY, source TEXT NOT NULL, kind TEXT NOT NULL,
  rev INTEGER NOT NULL, json TEXT NOT NULL, removed INTEGER NOT NULL DEFAULT 0);`;
const finish = (db: DatabaseSync) => {
  let steps = 0;
  while (!statsAgeStep(db, 3).done) assert.ok(++steps < 1000);
};
const byKey = (key: Uint8Array) => Buffer.from(key).toString("utf8");
const relevant = (json: string, from: string) => {
  try { const row = JSON.parse(json); return row.day !== undefined && row.day >= from ? "drop" : "keep"; }
  catch { return "error"; }
};
const dropped = (db: DatabaseSync) => statsAgeCandidates(db, "2026-11-01")
  .filter((row) => relevant(row.json, "2026-11-01") !== "keep").map((row) => byKey(row.key));

test("the age index only omits rows the original predicate cannot drop or fail on", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(schema);
    const insert = db.prepare("INSERT INTO stats_index (key, source, kind, rev, json, removed) VALUES (?, 'stillfail', 'usage', ?, ?, ?)");
    const old = Array.from({ length: 300 }, (_, i) => JSON.stringify({ day: `2026-10-${String(i % 31 + 1).padStart(2, "0")}`, session: String(i) }));
    const cases = [
      "{}", "null", "not JSON", "42", '"word"',
      '{"day":"2026-11-01"}', '{"day":"2026-11-01\\u0000tail"}', '{"day":"2026-11-0"}',
      '{"day":"2026-10-01","day":"2026-12-01"}', '{"day\\u0000ignored":"2026-12-01","day":"2026-01-01"}',
      '{"day":"\\ud800"}', '{"day":"2026-11-0\\udc00"}', '{"day":["2026-12-01"]}',
      '{"day":{"toString":0}}', '{"day":null}', '{"day":false}',
    ];
    let random = 137;
    const units = [0, 1, 32, 43, 44, 45, 46, 47, 48, 49, 53, 57, 58, 127, 0xd800, 0xdc00, 0xffff];
    const prefixes = ["", "2026-11-0", "+010000-0", "-000001-0", "9999-12-3"];
    for (let i = 0; i < 300; i++) {
      random = (random * 1664525 + 1013904223) >>> 0;
      const prefix = prefixes[random % prefixes.length]!;
      random = (random * 1664525 + 1013904223) >>> 0;
      cases.push(JSON.stringify({ day: prefix + String.fromCharCode(units[random % units.length]!) }));
    }
    for (const [i, json] of [...old, ...cases].entries()) insert.run(`k\0${i}`, i + 1, json, 0);
    db.prepare("INSERT INTO stats_index (rowid, key, source, kind, rev, json) VALUES (?, ?, 'stillfail', 'usage', 1000, ?)")
      .run(9223372036854775000n, "huge-rowid", '{"day":"2026-12-01"}');
    installStatsAge(db);
    finish(db);
    assert.equal(statsAgeReady(db, 0), true);
    const all = db.prepare("SELECT CAST(key AS BLOB) AS key, json FROM stats_index WHERE removed = 0 ORDER BY rowid").all() as { key: Uint8Array; json: string }[];
    for (const from of ["-000001-01", "0000-01-01", "2026-11-01", "9999-12-31", "+010000-01"]) {
      const expected = all.filter((row) => relevant(row.json, from) !== "keep").map((row) => [byKey(row.key), relevant(row.json, from)]);
      const actual = statsAgeCandidates(db, from).filter((row) => relevant(row.json, from) !== "keep").map((row) => [byKey(row.key), relevant(row.json, from)]);
      assert.deepEqual(actual, expected, from);
    }
    const selected = statsAgeCandidates(db, "2026-11-01");
    const oldKeys = new Set(old.map((_, i) => `k\0${i}`));
    assert.ok(selected.every((row) => !oldKeys.has(byKey(row.key))), "old rows need not be read on each build");
    const plan = db.prepare(`EXPLAIN QUERY PLAN ${STATS_AGE_CANDIDATES}`).all("0032003000320036") as { detail: string }[];
    assert.ok(plan.some((r) => r.detail.includes("comma_stats_age_day")));
    assert.ok(!plan.some((r) => /SCAN s\b/.test(r.detail)), JSON.stringify(plan));
  } finally { db.close(); }
});

test("a bounded rebuild follows old writers across its cursor and cleans replacement orphans", () => {
  const dir = mkdtempSync(join(tmpdir(), "comma-stats-age-")), path = join(dir, "stats.db");
  const db = new DatabaseSync(path), older = new DatabaseSync(path);
  try {
    db.exec(schema);
    const put = older.prepare("INSERT INTO stats_index (key, source, kind, rev, json) VALUES (?, 'stillfail', 'usage', 1, ?)");
    for (let i = 0; i < 10; i++) put.run(`old-${i}`, '{"day":"2026-01-01"}');
    installStatsAge(db);
    assert.equal(statsAgeStep(db, 3).visited, 3);
    assert.equal(statsAgeReady(db), false);
    older.prepare("UPDATE stats_index SET json = ? WHERE key = ?").run('{"day":"2026-12-01"}', "old-0");
    older.prepare("DELETE FROM stats_index WHERE key = ?").run("old-1");
    older.prepare("INSERT OR REPLACE INTO stats_index (key, source, kind, rev, json) VALUES (?, 'stillfail', 'usage', 2, ?)")
      .run("old-2", '{"day":"2026-12-01"}');
    older.prepare("INSERT INTO stats_index (key, source, kind, rev, json) VALUES (?, 'stillfail', 'usage', 1, ?) ON CONFLICT(key) DO NOTHING")
      .run("old-3", '{"day":"2026-01-01"}');
    older.exec("BEGIN");
    older.prepare("UPDATE stats_index SET json = ? WHERE key = ?").run('{"day":"2026-12-01"}', "old-4");
    older.exec("ROLLBACK");
    finish(db);
    assert.deepEqual(dropped(db), ["old-0", "old-2"]);
    assert.equal((db.prepare("SELECT COUNT(*) AS n FROM comma_stats_age a LEFT JOIN stats_index s ON s.rowid = a.id WHERE s.rowid IS NULL").get() as { n: number }).n, 0);
    older.prepare("UPDATE stats_index SET _rowid_ = 999, json = ? WHERE key = ?").run('{"day":"2026-12-01"}', "old-5");
    assert.equal(statsAgeReady(db, 0), false);
    finish(db);
    assert.deepEqual(dropped(db), ["old-0", "old-2", "old-5"]);
    older.prepare("UPDATE OR IGNORE stats_index SET key = ? WHERE key = ?").run("old-3", "old-0");
    assert.equal((db.prepare("SELECT COUNT(*) AS n FROM comma_stats_age a JOIN stats_index s ON s.rowid = a.id WHERE s.key = 'old-0'").get() as { n: number }).n, 1);
    finish(db);
    assert.deepEqual(dropped(db), ["old-0", "old-2", "old-5"]);
    // With recursive triggers off, replacing a conflicting row during UPDATE does not fire its DELETE trigger.
    older.prepare("UPDATE OR REPLACE stats_index SET key = ? WHERE key = ?").run("old-4", "old-6");
    finish(db);
    assert.deepEqual(dropped(db), ["old-0", "old-2", "old-5"]);
    assert.equal((db.prepare("SELECT COUNT(*) AS n FROM comma_stats_age a LEFT JOIN stats_index s ON s.rowid = a.id WHERE s.rowid IS NULL").get() as { n: number }).n, 0);
    older.exec("PRAGMA recursive_triggers = ON");
    older.prepare("UPDATE OR REPLACE stats_index SET key = ? WHERE key = ?").run("old-7", "old-8");
    older.prepare("INSERT OR REPLACE INTO stats_index (key, source, kind, rev, json) VALUES (?, 'stillfail', 'usage', 3, ?)")
      .run("old-9", '{"day":"2026-12-01"}');
    finish(db);
    assert.deepEqual(dropped(db), ["old-0", "old-2", "old-5", "old-9"]);
    assert.equal((db.prepare("SELECT COUNT(*) AS n FROM comma_stats_age a LEFT JOIN stats_index s ON s.rowid = a.id WHERE s.rowid IS NULL").get() as { n: number }).n, 0);
  } finally { older.close(); db.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("one rebuild batch cannot collect a large set of oversized old rows", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(schema);
    const put = db.prepare("INSERT INTO stats_index (key, source, kind, rev, json) VALUES (?, 'stillfail', 'usage', 1, ?)");
    const body = JSON.stringify({ day: "2026-01-01", data: "x".repeat(128 * 1024) });
    for (let i = 0; i < 16; i++) put.run(`big-${i}`, body);
    put.run("no-day-big", JSON.stringify({ data: "x".repeat(128 * 1024) }));
    put.run("recent-big", JSON.stringify({ day: "2026-12-01", data: "x".repeat(128 * 1024) }));
    installStatsAge(db);
    const step = statsAgeStep(db, 64);
    assert.ok(step.visited <= 3, `read ${step.visited} large rows in one batch`);
    assert.equal(step.done, false);
    finish(db);
    assert.deepEqual(statsAgeCandidates(db, "2026-11-01").map((row) => byKey(row.key)), ["recent-big"]);
  } finally { db.close(); }
});

test("removed rows need no body read until an older writer restores one", () => {
  const db = new DatabaseSync(":memory:");
  const parse = JSON.parse;
  try {
    db.exec(schema);
    db.prepare("INSERT INTO stats_index (key, source, kind, rev, json, removed) VALUES ('gone', 'stillfail', 'usage', 1, ?, 1)")
      .run("invalid tombstone " + "x".repeat(256 * 1024));
    installStatsAge(db);
    let parsed = 0;
    JSON.parse = ((...args: Parameters<typeof JSON.parse>) => { parsed++; return parse(...args); }) as typeof JSON.parse;
    finish(db);
    assert.equal(parsed, 0);
    assert.deepEqual(statsAgeCandidates(db, "2026-11-01"), []);
    db.prepare("UPDATE stats_index SET removed = 0 WHERE key = 'gone'").run();
    assert.deepEqual(statsAgeCandidates(db, "2026-11-01").map((row) => byKey(row.key)), ["gone"]);
    finish(db);
    assert.equal(parsed, 1);
    assert.deepEqual(statsAgeCandidates(db, "2026-11-01").map((row) => byKey(row.key)), ["gone"]);
  } finally { JSON.parse = parse; db.close(); }
});
