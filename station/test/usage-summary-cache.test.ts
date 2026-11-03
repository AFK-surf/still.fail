import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { constants, DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Readers } from "../src/read/pool.ts";
import * as reads from "../src/read/store.ts";
import { usage } from "../src/read/usage.ts";
import * as compact from "../src/store/usage-compact.ts";
import { retireUsageIndexes } from "../src/store/usage-retire.ts";
import { Store } from "../src/store/store.ts";

test("a repeated usage summary rereads only hours whose statistics changed", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-summary-cache-"));
  const path = join(dir, "stillfail.db");
  const writer = Store.open(path);
  let db: DatabaseSync | null = null;
  try {
    for (const [key, ws] of [["a", "A"], ["b", "A"], ["other", "B"]] as const) {
      writer.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key, ws, createdAt: 0, lastActiveAt: 0 });
    }
    compact.installCompactUsage(writer.db, () => 0);
    retireUsageIndexes(writer.db);
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = (id: string, at: number, output = 1) => ({ id, at, model: "m", subagent: false, fast: false,
      input: 1, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output, calls: 1, context: null, window: null });
    for (const key of ["a", "b", "other"]) {
      const calls = Array.from({ length: 120 }, (_, n) => [call(`${key}-${n}`, n * 60_000), owner] as [ReturnType<typeof call>, typeof owner]);
      writer.recordUsage(`/${key}`, { session: key, offset: 1, model: "m" }, "claude", calls);
    }
    compact.installUsageSummaryChanges(writer.db);
    db = new DatabaseSync(path, { readOnly: true });
    const store = reads.makeStore(db, dir);
    const cache = new reads.UsageSummaryCache();
    const viewer = { workspace: "A", home: false };
    const read = async () => {
      db!.exec("BEGIN");
      try { return await reads.usageGroupsBatched(store, 0n, 120n * 60_000n, 0n, viewer, async () => {}, cache); }
      finally { db!.exec("COMMIT"); }
    };
    const first = await read();
    assert.ok(first);
    assert.deepEqual(first.groups, reads.usageGroups(store, 0n, 120n * 60_000n, 0n, viewer));
    db.setAuthorizer((action, table) => action === constants.SQLITE_READ && table === "usage_compact" ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try { assert.deepEqual((await read())?.groups, first.groups, "an unchanged summary does not read the minute buckets again"); }
    finally { db.setAuthorizer(null); }
    writer.recordUsage("/a", { session: "a", offset: 2, model: "m" }, "claude", [[call("a-1", 60_000, 7), owner]]);
    const next = await read();
    assert.ok(next);
    assert.deepEqual(next.groups, reads.usageGroups(store, 0n, 120n * 60_000n, 0n, viewer));
    assert.equal(next.diagnostics.parts, 60, "only the changed session's hour is read again");
    writer.recordUsage("/a", { session: "a", offset: 3, model: "m" }, "claude",
      [[call("a-0", 0, 2), owner], [call("a-90", 90 * 60_000, 3), owner]]);
    const beforeConcurrentWrite = reads.usageGroups(store, 0n, 120n * 60_000n, 0n, viewer);
    let paused = false;
    db.exec("BEGIN");
    try {
      const during = await reads.usageGroupsBatched(store, 0n, 120n * 60_000n, 0n, viewer, async () => {
        if (!paused) {
          paused = true;
          writer.recordUsage("/a", { session: "a", offset: 4, model: "m" }, "claude", [[call("a-0", 0, 99), owner]]);
        }
      }, cache);
      assert.ok(paused && during);
      assert.deepEqual(during.groups, beforeConcurrentWrite, "refreshed hours belong to the same snapshot");
    } finally { db.exec("COMMIT"); }
    const afterConcurrentWrite = await read();
    assert.ok(afterConcurrentWrite);
    assert.deepEqual(afterConcurrentWrite.groups, reads.usageGroups(store, 0n, 120n * 60_000n, 0n, viewer),
      "the following read sees the write that happened while the first snapshot was open");
  } finally {
    db?.close();
    writer.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

for (const recursive of [false, true]) test(`cached usage follows older writers, edits, removals, ownership and journal overflow (recursive triggers ${recursive})`, async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-cache-changes-"));
  const path = join(dir, "stillfail.db");
  const writer = Store.open(path);
  const db = new DatabaseSync(path, { readOnly: true });
  try {
    for (const [key, ws] of [["a", "A"], ["b", "B"], ["h", null]] as const) {
      writer.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key, ws, createdAt: 0, lastActiveAt: 0 });
    }
    compact.installCompactUsage(writer.db, () => 0);
    retireUsageIndexes(writer.db);
    writer.db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    compact.installUsageSummaryChanges(writer.db);
    assert.equal((writer.db.prepare("SELECT COUNT(*) AS n FROM usage_summary_changes").get() as { n: number }).n, 0, "installation reads and writes no old minutes");
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = (id: string, at: number) => ({ id, at, model: "m", subagent: true, fast: false,
      input: 1, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null });
    for (const key of ["a", "b", "h"]) writer.recordUsage(`/${key}`, { session: key, offset: 1, model: "m" }, "claude",
      [-61, -1, 0, 1, 61].map((n) => [call(`${key}-${n}`, n * 60_000), owner]));
    const store = reads.makeStore(db, dir);
    const from = -120n * 60_000n, to = 120n * 60_000n, tz = 330n;
    const viewers = [{ workspace: "A", home: false }, { workspace: "B", home: false }, { workspace: "A", home: true }, null];
    const caches = viewers.map(() => new reads.UsageSummaryCache());
    const read = async (i: number) => {
      db.exec("BEGIN");
      try { return await reads.usageGroupsBatched(store, from, to, tz, viewers[i]!, async () => {}, caches[i]); }
      finally { db.exec("COMMIT"); }
    };
    const same = async () => {
      for (let i = 0; i < viewers.length; i++) {
        const actual = await read(i);
        assert.ok(actual);
        assert.deepEqual(actual.groups, reads.usageGroups(store, from, to, tz, viewers[i]!));
      }
    };
    await same();
    const oldWrite = writer.db.prepare(`INSERT INTO usage (id, at, session, turn, thread, person, profile, runtime, model, subagent, fast,
      input, cache_read, cache_write, cache_write_long, output, calls, context, context_window)
      VALUES ('legacy', 60000, 'a', NULL, NULL, 'p', 'cc', 'claude', 'm', 1, 0, 3, 0, 0, 0, ?, 1, NULL, NULL)
      ON CONFLICT (id) DO UPDATE SET output = MAX(output, excluded.output)`);
    oldWrite.run(1);
    await same();
    oldWrite.run(9);
    await same();
    writer.db.exec("UPDATE usage SET at = -1800000, model = 'other', person = 'new' WHERE id = 'a-61'");
    await same();
    writer.db.exec("DELETE FROM usage WHERE id = 'a--1'");
    await same();
    // REPLACE may suppress DELETE triggers, even for a writer from before this change.
    writer.db.exec("INSERT OR REPLACE INTO usage_minute_scope (session, ws, done) VALUES ('a', 'B', 1)");
    await same();
    writer.db.exec("INSERT OR REPLACE INTO usage_minute_scope (session, ws, done) VALUES ('a', 'A', 1)");
    await same();
    const copy = `INSERT OR REPLACE INTO usage_compact
      (session, minute, thread, person, profile, runtime, model, fast, records, calls, input, cache_read, cache_write, cache_write_long, output, scope)
      SELECT session, minute, thread, person, profile, runtime, model, fast, records, calls, input, cache_read, cache_write, cache_write_long, output, ?
      FROM usage_compact WHERE session = 'a' AND minute = 0`;
    writer.db.prepare(copy).run("WB");
    await same();
    writer.db.prepare(copy).run("WA");
    await same();
    writer.db.exec("UPDATE sessions SET ws = 'B' WHERE key = 'a'");
    while (!compact.moveCompactStep(writer.db, 2).done) { /* The move is bounded. */ }
    await same();
    writer.db.exec("BEGIN");
    writer.db.exec("UPDATE usage SET output = output + 100 WHERE id = 'a-0'");
    writer.db.exec("ROLLBACK");
    await same();

    // An unrelated workspace does not cause a bucket lookup in A while the journal still covers the cache.
    writer.db.exec("UPDATE usage SET output = output + 1 WHERE id = 'b-0'");
    db.setAuthorizer((action, table) => action === constants.SQLITE_READ && table === "usage_compact" ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try { assert.ok(await read(0)); } finally { db.setAuthorizer(null); }
    const append = writer.db.prepare("INSERT INTO usage_summary_changes (scope, session, minute) VALUES ('WB', 'b', 0)");
    writer.db.exec("BEGIN");
    for (let i = 0; i < 4_300; i++) append.run();
    writer.db.exec("COMMIT");
    const count = (writer.db.prepare("SELECT COUNT(*) AS n FROM usage_summary_changes").get() as { n: number }).n;
    assert.ok(count >= 4096 && count < 4160, "only the bounded recent change journal is retained");
    const fallback = await read(1);
    assert.ok(fallback);
    assert.ok(fallback.diagnostics.candidates > 0, "a cache older than the journal is rebuilt");
    await same();
  } finally { db.close(); writer.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a cached summary and partial history reuse minutes together and a reader returns the same result", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-cache-history-"));
  const path = join(dir, "stillfail.db");
  const writer = Store.open(path);
  let db: DatabaseSync | null = null;
  let workers: Readers | null = null;
  try {
    writer.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A", createdAt: 0, lastActiveAt: 0 });
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = { id: "old", at: -60_000, model: "m", subagent: false, fast: false, input: 2, cacheRead: 0,
      cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null };
    writer.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [[call, owner]]);
    writer.db.exec("CREATE TABLE usage_retired_detail (id INTEGER PRIMARY KEY); INSERT INTO usage_retired_detail VALUES (1)");
    compact.installCompactUsage(writer.db, () => 0);
    retireUsageIndexes(writer.db);
    compact.installUsageSummaryChanges(writer.db);
    const calls = Array.from({ length: 100 }, (_, i) => [{ ...call, id: `new-${i}`, at: i * 60_000,
      model: i % 2 ? "other" : "m", fast: i % 3 === 0, input: i + 1 }, { ...owner, person: i % 2 ? "other" : "p" }] as [typeof call, typeof owner]);
    writer.recordUsage("/a", { session: "a", offset: 2, model: "m" }, "claude", calls);
    while (!compact.compactTotalsStep(writer.db, 64).done) { /* A bounded total becomes ready. */ }
    db = new DatabaseSync(path, { readOnly: true });
    const store = reads.makeStore(db, dir);
    const viewer = { workspace: "A", home: false }, range = { from: 0n, to: 86_400_000n };
    const expected = usage(store, "en", 0n, 120n * 60_000n, 0n, false, viewer, true, { historyRange: range });
    assert.ok(expected.partialHistory);
    const cache = new reads.UsageSummaryCache();
    const compute = async () => {
      const summary = await reads.usageGroupsBatched(store, 0n, 120n * 60_000n, 0n, viewer, async () => {}, cache);
      const history = await reads.usageGroupsBatched(store, range.from, range.to, 0n, viewer, async () => {}, cache, "history");
      assert.ok(summary && history);
      return usage(store, "en", 0n, 120n * 60_000n, 0n, false, viewer, true,
        { historyRange: range, batched: summary, batchedHistory: { range, result: history } });
    };
    db.exec("BEGIN");
    try { assert.deepEqual(JSON.parse(JSON.stringify(await compute())), JSON.parse(JSON.stringify(expected))); }
    finally { db.exec("COMMIT"); }
    // Total readiness reads only the pending index; denying the bucket values proves neither page component rereads them.
    const values = new Set(["minute", "records", "calls", "input", "cache_read", "cache_write", "cache_write_long", "output"]);
    db.setAuthorizer((action, table, column) => action === constants.SQLITE_READ && table === "usage_compact" && values.has(column ?? "")
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    db.exec("BEGIN");
    try { assert.deepEqual(JSON.parse(JSON.stringify(await compute())), JSON.parse(JSON.stringify(expected))); }
    finally { db.exec("COMMIT"); db.setAuthorizer(null); }
    workers = new Readers(dir, 1);
    const args = { from: "0", to: String(120 * 60_000), tz: "0", lang: "en", reading: false, viewer, history: true,
      historyRange: { from: "0", to: String(86_400_000) } };
    const wanted = JSON.parse(JSON.stringify(expected));
    assert.deepEqual(JSON.parse(await workers.read("usage", args, "en")), wanted);
    assert.deepEqual(JSON.parse(await workers.read("usage", args, "en")), wanted);
  } finally { workers?.close(); db?.close(); writer.close(); rmSync(dir, { recursive: true, force: true }); }
});
