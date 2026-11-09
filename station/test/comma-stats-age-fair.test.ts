import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { CommaStats } from "../src/comma/stats.ts";
import { installStatsAge, statsAgeCandidates, statsAgeReady, statsAgeStep } from "../src/comma/stats-age.ts";

for (const changes of [1, 64, 65, 512]) test(`a build can finish while an older connection changes ${changes} rows between event-loop turns`, async () => {
  const dir = mkdtempSync(join(tmpdir(), "comma-stats-fair-")), path = join(dir, "stats.db");
  const stats = new CommaStats(path, async () => ({ stations: [], unread: [] }), () => () => {});
  const writer = new DatabaseSync(path);
  let writing = true;
  try {
    const insert = writer.prepare("INSERT INTO stats_index (key, source, kind, rev, json) VALUES (?, 'stillfail', 'usage', ?, ?)");
    for (let i = 1; i <= changes; i++) insert.run(`old-${i}`, i, JSON.stringify({ day: i === 1 ? "9999-12-31" : "1900-01-01" }));
    insert.run("recent", changes + 1, '{"day":"9999-12-31"}');
    writer.prepare("INSERT INTO meta (key, value) VALUES ('stats_index.rev', ?)").run(String(changes + 1));
    const update = writer.prepare("UPDATE stats_index SET json = ? WHERE key = ?");
    let writes = 0, finished = false;
    const write = () => {
      if (!writing || writes >= 20) return;
      writes++;
      writer.exec("BEGIN");
      for (let i = 1; i <= changes; i++) update.run(JSON.stringify({ day: i === 1 ? "9999-12-31" : "1900-01-01", write: writes }), `old-${i}`);
      writer.exec("COMMIT");
      setImmediate(write);
    };
    setImmediate(write);
    stats.build();
    const settled = stats.settled().then(() => { finished = true; });
    while (writes < 20) await new Promise<void>((resolve) => setImmediate(resolve));
    const finishedWhileWriting = finished;
    writing = false;
    await settled;
    assert.ok(finishedWhileWriting, "the build waited for all old-writer activity to stop");
    const rows = stats.stats.since(0, changes + 10);
    assert.equal(rows.find((row) => row.key === "recent")?.removed, true);
    assert.equal(rows.find((row) => row.key === "old-1")?.removed, true);
    assert.equal(rows.filter((row) => row.key.startsWith("old-") && !row.removed).length, changes - 1);
  } finally {
    writing = false;
    writer.close();
    stats.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a single large burst from an older writer is classified in batches before the build", async () => {
  const dir = mkdtempSync(join(tmpdir(), "comma-stats-burst-")), path = join(dir, "stats.db");
  const stats = new CommaStats(path, async () => ({ stations: [], unread: [] }), () => () => {});
  const writer = new DatabaseSync(path);
  const parse = JSON.parse;
  let done = false, count = 0, max = 0;
  try {
    const put = writer.prepare("INSERT INTO stats_index (key, source, kind, rev, json) VALUES (?, 'stillfail', 'usage', ?, ?)");
    writer.exec("BEGIN");
    for (let i = 0; i < 1024; i++) put.run(`old-${i}`, i + 1, JSON.stringify({ day: "1900-01-01", marker: `old-${i}` }));
    writer.exec("COMMIT");
    JSON.parse = ((...args: Parameters<typeof JSON.parse>) => {
      if (typeof args[0] === "string" && args[0].includes('"marker":"old-')) count++;
      return parse(...args);
    }) as typeof JSON.parse;
    const sample = () => { max = Math.max(max, count); count = 0; if (!done) setImmediate(sample); };
    setImmediate(sample);
    setImmediate(() => {
      writer.exec("BEGIN");
      writer.exec("UPDATE stats_index SET json = json_set(json, '$.burst', 1)");
      writer.exec("COMMIT");
    });
    stats.build();
    await stats.settled();
    done = true;
    sample();
    assert.ok(max <= 256, `parsed ${max} old statistics before yielding after a single burst`);
    assert.equal(stats.stats.since(0, 1100).length, 1024);
  } finally {
    done = true;
    JSON.parse = parse;
    writer.close();
    stats.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

// Model the documented possibility that a schema-rebuilding VACUUM renumbers a table without an INTEGER PRIMARY KEY.
// The SQLite used here normally keeps rowids for this indexed table, so disable the row-change triggers temporarily.
const renumber = (db: DatabaseSync) => {
  const triggers = db.prepare("SELECT name, sql FROM sqlite_schema WHERE type = 'trigger' AND tbl_name = 'stats_index'").all() as { name: string; sql: string }[];
  for (const trigger of triggers) db.exec(`DROP TRIGGER "${trigger.name.replaceAll('"', '""')}"`);
  db.exec("UPDATE stats_index SET rowid = -rowid; UPDATE stats_index SET rowid = -rowid / 10");
  for (const trigger of triggers) db.exec(trigger.sql);
};

for (const transition of ["vacuum", "rowid renumbering"] as const) for (const during of [true, false]) test(`${transition} ${during ? "during" : "after"} preparation keeps recent statistics as candidates`, () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(`CREATE TABLE stats_index (key TEXT PRIMARY KEY, source TEXT NOT NULL, kind TEXT NOT NULL,
      rev INTEGER NOT NULL, json TEXT NOT NULL, removed INTEGER NOT NULL DEFAULT 0)`);
    const put = db.prepare("INSERT INTO stats_index (rowid, key, source, kind, rev, json) VALUES (?, ?, 'stillfail', 'usage', ?, ?)");
    db.exec("BEGIN");
    for (let i = 1; i <= 256; i++) put.run(i * 10, `old-${i}`, i, '{"day":"1900-01-01"}');
    put.run(2570, "recent", 257, '{"day":"9999-12-31"}');
    db.exec("COMMIT");
    installStatsAge(db);
    if (during) assert.equal(statsAgeStep(db, 256).done, false);
    else while (!statsAgeStep(db).done) { /* finish the old index */ }
    const before = db.prepare("SELECT rowid AS id FROM stats_index WHERE key = 'recent'").get() as { id: number };
    if (transition === "vacuum") db.exec("VACUUM");
    else renumber(db);
    const after = db.prepare("SELECT rowid AS id FROM stats_index WHERE key = 'recent'").get() as { id: number };
    const staleReady = statsAgeReady(db, 0);
    db.prepare("UPDATE stats_index SET json = ? WHERE key = 'old-1'").run('{"day":"9999-12-30"}');
    let done = false;
    for (let i = 0; i < 20 && !done; i++) {
      const step = statsAgeStep(db);
      assert.ok(step.visited <= 64);
      done = step.done;
    }
    assert.equal(done, true);
    const recent = statsAgeCandidates(db, "2026-11-01")
      .filter((row) => JSON.parse(row.json).day >= "2026-11-01")
      .map((row) => Buffer.from(row.key).toString());
    assert.deepEqual(recent, ["old-1", "recent"], `rowid of the recent row changed ${before.id} → ${after.id}`);
    assert.equal(staleReady, false, "the old classification cannot be used after the schema cookie changes");
  } finally { db.close(); }
});

test("old writers and a second schema change are followed while a renumbered index is rebuilt", () => {
  const dir = mkdtempSync(join(tmpdir(), "comma-stats-rebuild-")), path = join(dir, "stats.db");
  const db = new DatabaseSync(path), writer = new DatabaseSync(path);
  try {
    db.exec(`CREATE TABLE stats_index (key TEXT PRIMARY KEY, source TEXT NOT NULL, kind TEXT NOT NULL,
      rev INTEGER NOT NULL, json TEXT NOT NULL, removed INTEGER NOT NULL DEFAULT 0)`);
    const put = writer.prepare("INSERT INTO stats_index (rowid, key, source, kind, rev, json) VALUES (?, ?, 'stillfail', 'usage', ?, ?)");
    for (let i = 1; i <= 256; i++) put.run(i * 10, `old-${i}`, i, '{"day":"1900-01-01"}');
    put.run(2570, "recent", 257, '{"day":"9999-12-31"}');
    installStatsAge(db);
    while (!statsAgeStep(db).done) { /* initial preparation */ }
    renumber(writer);
    assert.equal(statsAgeStep(db).done, false);
    writer.prepare("UPDATE stats_index SET json = ? WHERE key = 'old-1'").run('{"day":"9999-12-30"}');
    writer.prepare("DELETE FROM stats_index WHERE key = 'old-2'").run();
    writer.prepare("INSERT OR REPLACE INTO stats_index (key, source, kind, rev, json) VALUES ('old-3', 'stillfail', 'usage', 258, ?)")
      .run('{"day":"9999-12-29"}');
    writer.exec("BEGIN");
    writer.prepare("UPDATE stats_index SET json = ? WHERE key = 'old-4'").run('{"day":"9999-12-28"}');
    writer.exec("ROLLBACK");
    writer.exec("VACUUM");
    let done = false;
    for (let i = 0; i < 20 && !done; i++) {
      const step = statsAgeStep(db);
      assert.ok(step.visited <= 64);
      done = step.done;
    }
    assert.equal(done, true);
    const recent = statsAgeCandidates(db, "2026-11-01")
      .filter((row) => JSON.parse(row.json).day >= "2026-11-01")
      .map((row) => Buffer.from(row.key).toString());
    assert.deepEqual(recent, ["old-1", "recent", "old-3"]);
    assert.equal((db.prepare(`SELECT COUNT(*) AS n FROM comma_stats_age
      WHERE generation < (SELECT generation FROM comma_stats_age_progress WHERE id = 1)`).get() as { n: number }).n, 0);
  } finally { writer.close(); db.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a later build removes a recent statistic after its prepared database is vacuumed", async () => {
  const dir = mkdtempSync(join(tmpdir(), "comma-stats-vacuum-")), path = join(dir, "stats.db");
  let unread = ["away"];
  const stats = new CommaStats(path, async () => ({ stations: [], unread }), () => () => {});
  const writer = new DatabaseSync(path);
  try {
    const put = writer.prepare("INSERT INTO stats_index (rowid, key, source, kind, rev, json) VALUES (?, ?, 'stillfail', 'usage', ?, ?)");
    writer.exec("BEGIN");
    for (let i = 1; i <= 256; i++) put.run(i * 10, `old-${i}`, i, '{"day":"1900-01-01","station":"away"}');
    put.run(2570, "recent", 257, '{"day":"9999-12-31","station":"away"}');
    writer.prepare("INSERT INTO meta (key, value) VALUES ('stats_index.rev', '257')").run();
    writer.exec("COMMIT");
    stats.build();
    await stats.settled();
    assert.equal(stats.stats.since(0, 300).find((row) => row.key === "recent")?.removed, false);
    writer.exec("VACUUM");
    unread = [];
    stats.build();
    await stats.settled();
    const rows = stats.stats.since(0, 300);
    assert.equal(rows.find((row) => row.key === "recent")?.removed, true);
    assert.equal(rows.filter((row) => row.key.startsWith("old-") && !row.removed).length, 256);
  } finally { writer.close(); stats.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a vacuumed copy does not trust the source database's prepared rowids", () => {
  const dir = mkdtempSync(join(tmpdir(), "comma-stats-vacuum-copy-")), path = join(dir, "copy.db");
  const db = new DatabaseSync(":memory:");
  let copy: DatabaseSync | null = null;
  try {
    db.exec(`CREATE TABLE stats_index (key TEXT PRIMARY KEY, source TEXT NOT NULL, kind TEXT NOT NULL,
      rev INTEGER NOT NULL, json TEXT NOT NULL, removed INTEGER NOT NULL DEFAULT 0)`);
    const put = db.prepare("INSERT INTO stats_index (rowid, key, source, kind, rev, json) VALUES (?, ?, 'stillfail', 'usage', ?, ?)");
    for (let i = 1; i <= 256; i++) put.run(i * 10, `old-${i}`, i, '{"day":"1900-01-01"}');
    put.run(2570, "recent", 257, '{"day":"9999-12-31"}');
    installStatsAge(db);
    while (!statsAgeStep(db).done) { /* prepare the source */ }
    db.prepare("VACUUM INTO ?").run(path);
    copy = new DatabaseSync(path);
    const sourceId = (db.prepare("SELECT rowid AS id FROM stats_index WHERE key = 'recent'").get() as { id: number }).id;
    const copyId = (copy.prepare("SELECT rowid AS id FROM stats_index WHERE key = 'recent'").get() as { id: number }).id;
    if (sourceId !== copyId) assert.equal(statsAgeReady(copy, 0), false);
    let done = false;
    for (let i = 0; i < 20 && !done; i++) done = statsAgeStep(copy).done;
    assert.equal(done, true);
    const recent = statsAgeCandidates(copy, "2026-11-01")
      .filter((row) => JSON.parse(row.json).day >= "2026-11-01")
      .map((row) => Buffer.from(row.key).toString());
    assert.deepEqual(recent, ["recent"]);
  } finally { copy?.close(); db.close(); rmSync(dir, { recursive: true, force: true }); }
});
