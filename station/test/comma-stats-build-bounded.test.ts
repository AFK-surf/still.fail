import assert from "node:assert/strict";
import { copyFileSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { CommaStats, statsRowsOf } from "../src/comma/stats.ts";

const empty = async () => ({ stations: [], unread: [] });
const quiet = () => () => {};

test("a Comma build preserves old statistics without parsing the entire history in one event-loop turn", async () => {
  const dir = mkdtempSync(join(tmpdir(), "comma-stats-build-")), path = join(dir, "stats.db");
  new CommaStats(path, empty, quiet).close();
  const writer = new DatabaseSync(path);
  try {
    const put = writer.prepare("INSERT INTO stats_index (key, source, kind, rev, json, removed) VALUES (?, 'stillfail', 'usage', ?, ?, 0)");
    writer.exec("BEGIN");
    for (let i = 0; i < 1024; i++) put.run(`old\0${i}`, i + 1, JSON.stringify({ day: "0000-01-01", marker: `old-${i}` }));
    writer.prepare("INSERT INTO meta (key, value) VALUES ('stats_index.rev', '1024')").run();
    writer.exec("COMMIT");
  } finally { writer.close(); }
  const stats = new CommaStats(path, empty, quiet);
  const parse = JSON.parse;
  let done = false, count = 0, max = 0;
  JSON.parse = ((...args: Parameters<typeof JSON.parse>) => {
    if (typeof args[0] === "string" && args[0].includes('"marker":"old-')) count++;
    return parse(...args);
  }) as typeof JSON.parse;
  const sample = () => {
    max = Math.max(max, count);
    count = 0;
    if (!done) setImmediate(sample);
  };
  setImmediate(sample);
  try {
    stats.build();
    await stats.settled();
    done = true;
    sample();
    assert.ok(max <= 256, `parsed ${max} old statistics before the event loop could run`);
    assert.equal(stats.stats.since(0, 2048).length, 1024, "days before the build's window stay");
  } finally {
    done = true;
    JSON.parse = parse;
    stats.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a prepared build has the same rows and revisions as the original reader, including an unread station", async () => {
  const dir = mkdtempSync(join(tmpdir(), "comma-stats-build-")), original = join(dir, "original.db"), prepared = join(dir, "prepared.db");
  const usage = (day: string, session: string, calls = 1) => ({ day, session, runtime: "claude", calls });
  const station = (rows: ReturnType<typeof usage>[], name?: string) => ({ ...(name === undefined ? {} : { station: name }), usage: { rows }, chats: [] });
  const seed = new CommaStats(original, empty, quiet);
  seed.apply([
    station([usage("1900-01-01", "old"), usage("9999-12-31", "keep"), usage("9999-12-31", "remove")]),
    station([usage("9999-12-31", "unread")], "away"),
  ], [], Date.UTC(1900, 0, 1));
  seed.close();
  const raw = new DatabaseSync(original);
  try {
    const rev = Number((raw.prepare("SELECT value FROM meta WHERE key = 'stats_index.rev'").get() as { value: string }).value);
    const put = raw.prepare("INSERT INTO stats_index (key, source, kind, rev, json) VALUES (?, 'stillfail', 'usage', ?, ?)");
    put.run("odd-array", rev + 1, '{"day":["9999-12-31"]}');
    put.run("odd-false", rev + 2, '{"day":false}');
    put.run("no-day", rev + 3, '{"thread":42}');
    raw.prepare("UPDATE meta SET value = ? WHERE key = 'stats_index.rev'").run(String(rev + 3));
  } finally { raw.close(); }
  copyFileSync(original, prepared);
  const answer = { stations: [station([usage("9999-12-31", "keep", 2)])], unread: ["away"] };
  let from = 0;
  const candidate = new CommaStats(prepared, async (start) => { from = start; return answer; }, quiet);
  const baseline = new CommaStats(original, empty, quiet);
  try {
    candidate.build();
    await candidate.settled();
    assert.ok(from > 0);
    assert.ok(baseline.apply(answer.stations, answer.unread, from).stats > 0);
    assert.deepEqual(candidate.stats.since(0, 1000), baseline.stats.since(0, 1000));
    assert.deepEqual(candidate.tasks.since(0, 1000), baseline.tasks.since(0, 1000));
    assert.equal(candidate.stats.rev(), baseline.stats.rev());
    assert.equal(candidate.tasks.rev(), baseline.tasks.rev());
  } finally { candidate.close(); baseline.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("closing during index preparation stops it and the next build resumes it", async () => {
  const dir = mkdtempSync(join(tmpdir(), "comma-stats-build-")), path = join(dir, "stats.db");
  new CommaStats(path, empty, quiet).close();
  const writer = new DatabaseSync(path);
  try {
    const put = writer.prepare("INSERT INTO stats_index (key, source, kind, rev, json) VALUES (?, 'stillfail', 'usage', ?, ?)");
    writer.exec("BEGIN");
    for (let i = 0; i < 512; i++) put.run(`old-${i}`, i + 1, '{"day":"1900-01-01"}');
    writer.exec("COMMIT");
  } finally { writer.close(); }
  const first = new CommaStats(path, empty, quiet);
  try {
    setImmediate(() => first.close());
    first.build();
    first.build();
    await first.settled();
    const inspection = new DatabaseSync(path);
    try {
      const state = inspection.prepare("SELECT cursor, done FROM comma_stats_age_progress WHERE id = 1").get() as { cursor: number; done: number };
      assert.ok(state.cursor > 0);
      assert.equal(state.done, 0);
    } finally { inspection.close(); }
    const resumed = new CommaStats(path, empty, quiet);
    try {
      resumed.build();
      await resumed.settled();
      assert.equal(resumed.stats.since(0, 1000).length, 512);
      const inspection = new DatabaseSync(path);
      try {
        assert.equal((inspection.prepare("SELECT done FROM comma_stats_age_progress WHERE id = 1").get() as { done: number }).done, 1);
      } finally { inspection.close(); }
    } finally { resumed.close(); }
  } finally { first.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("an older writer changing classified rows during preparation is included in the build", async () => {
  const dir = mkdtempSync(join(tmpdir(), "comma-stats-build-")), path = join(dir, "stats.db");
  new CommaStats(path, empty, quiet).close();
  const writer = new DatabaseSync(path);
  try {
    const put = writer.prepare("INSERT INTO stats_index (key, source, kind, rev, json) VALUES (?, 'stillfail', 'usage', ?, ?)");
    writer.exec("BEGIN");
    for (let i = 0; i < 256; i++) put.run(`old-${i}`, i + 1, '{"day":"1900-01-01"}');
    writer.prepare("INSERT INTO meta (key, value) VALUES ('stats_index.rev', '256')").run();
    writer.exec("COMMIT");
    const stats = new CommaStats(path, empty, quiet);
    try {
      // The first batch classifies these rows before this older connection changes them.
      setImmediate(() => {
        writer.exec("BEGIN");
        const update = writer.prepare("UPDATE stats_index SET json = ?, rev = ? WHERE key = ?");
        for (let i = 0; i < 64; i++) update.run('{"day":"9999-12-31"}', 257 + i, `old-${i}`);
        for (let i = 0; i < 80; i++) put.run(`new-${i}`, 321 + i, '{"day":"9999-12-31"}');
        writer.prepare("UPDATE meta SET value = '400' WHERE key = 'stats_index.rev'").run();
        writer.exec("COMMIT");
      });
      stats.build();
      await stats.settled();
      const rows = stats.stats.since(0, 1000);
      assert.equal(rows.filter((row) => row.removed).length, 144);
      assert.equal(rows.filter((row) => !row.removed).length, 192);
      assert.equal(stats.stats.rev(), 544);
    } finally { stats.close(); }
  } finally { writer.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a build retries a database held by an older writer and can stop while waiting", async () => {
  const dir = mkdtempSync(join(tmpdir(), "comma-stats-build-")), path = join(dir, "stats.db");
  new CommaStats(path, empty, quiet).close();
  const writer = new DatabaseSync(path);
  let stats: CommaStats | null = null;
  try {
    stats = new CommaStats(path, empty, quiet);
    writer.exec("BEGIN IMMEDIATE");
    stats.build();
    const waiting = stats.settled();
    await new Promise<void>((resolve) => setImmediate(resolve));
    stats.close();
    await waiting;
    stats = null;
    writer.exec("COMMIT");

    stats = new CommaStats(path, empty, quiet);
    writer.exec("BEGIN IMMEDIATE");
    stats.build();
    const resumed = stats.settled();
    await new Promise<void>((resolve) => setTimeout(resolve, 60));
    writer.exec("COMMIT");
    await resumed;
    const state = writer.prepare("SELECT done FROM comma_stats_age_progress WHERE id = 1").get() as { done: number };
    assert.equal(state.done, 1);
  } finally {
    if (writer.isTransaction) writer.exec("ROLLBACK");
    stats?.close();
    writer.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a malformed stored row still rolls back a build and can be replaced by a later one", async () => {
  const dir = mkdtempSync(join(tmpdir(), "comma-stats-build-")), path = join(dir, "stats.db");
  new CommaStats(path, empty, quiet).close();
  const usage = (session: string) => ({ day: "9999-12-31", session, runtime: "claude", calls: 1 });
  const station = (session: string) => ({ usage: { rows: [usage(session)] }, chats: [] });
  const key = [...statsRowsOf(station("repair"), "0000-01-01").keys()][0]!;
  const writer = new DatabaseSync(path);
  try {
    writer.prepare("INSERT INTO stats_index (key, source, kind, rev, json) VALUES (?, 'stillfail', 'usage', 1, 'not json')").run(key);
    writer.prepare("INSERT INTO meta (key, value) VALUES ('stats_index.rev', '1')").run();
  } finally { writer.close(); }
  let result = station("other");
  const stats = new CommaStats(path, async () => ({ stations: [result], unread: [] }), quiet);
  let notified = 0;
  const stop = stats.stats.listen(() => { notified++; });
  try {
    stats.build();
    await stats.settled();
    assert.equal(stats.stats.rev(), 1);
    assert.deepEqual(stats.stats.since(0, 10).map((row) => row.json), ["not json"]);
    assert.equal(notified, 0, "the failed transaction did not announce partial writes");
    result = station("repair");
    stats.build();
    await stats.settled();
    assert.equal(stats.stats.rev(), 2);
    assert.equal(JSON.parse(stats.stats.since(0, 10)[0]!.json).session, "repair");
    assert.equal(notified, 1);
  } finally { stop(); stats.close(); rmSync(dir, { recursive: true, force: true }); }
});
