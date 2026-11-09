import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { constants, DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { usageRoutes } from "../src/api/routes/usage.ts";
import { hearLines, type Line } from "../src/ops/log.ts";
import { Readers } from "../src/read/pool.ts";
import * as reads from "../src/read/store.ts";
import { usage } from "../src/read/usage.ts";
import * as compact from "../src/store/usage-compact.ts";
import { retireUsageIndexes } from "../src/store/usage-retire.ts";
import { Store } from "../src/store/store.ts";
import { watchCompactMoves } from "../src/usage/module.ts";

test("a repeated usage summary rereads only minutes whose statistics changed", async () => {
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
    while (!compact.compactTotalsStep(writer.db, 64).done) { /* Settle existing pending buckets. */ }
    writer.db.setAuthorizer((action, table) => action === constants.SQLITE_READ &&
      ["usage", "usage_compact", "usage_minute_scope"].includes(table ?? "") ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try { compact.installUsageSummaryChanges(writer.db); }
    finally { writer.db.setAuthorizer(null); }
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
    assert.equal(first.diagnostics.cache, "miss");
    assert.deepEqual(first.groups, reads.usageGroups(store, 0n, 120n * 60_000n, 0n, viewer));
    const lines: Line[] = [];
    hearLines((line) => lines.push(line));
    try { usage(store, "en", 0n, 120n * 60_000n, 0n, false, viewer, false, { batched: { ...first, ms: 1_001 }, remoteRuns: false }); }
    finally { hearLines(null); }
    const slow = lines.find((line) => line.message === "a usage read's stages");
    assert.ok(slow);
    assert.equal(slow.fields.summarySelectedRestMs, first.diagnostics.selectedRestMs);
    assert.equal(slow.fields.summarySelectedCpuMs, first.diagnostics.selectedCpuMs);
    assert.equal(slow.fields.summaryCpuMs, first.diagnostics.cpuMs);
    const sql = (first.diagnostics as any).sql;
    for (const [name, field] of [["journal", "summarySqlJournalMs"], ["changes", "summarySqlChangesMs"], ["pending", "summarySqlPendingMs"],
      ["selected", "summarySqlSelectedMs"], ["owner", "summarySqlOwnerMs"], ["buckets", "summarySqlBucketsMs"], ["slowMs", "summarySqlSlowMs"]] as const) {
      assert.equal(typeof sql?.[name], "number");
      assert.equal(slow.fields[field], sql[name]);
    }
    assert.equal(slow.fields.summarySqlSlowOp, sql.slowOp);
    const values = new Set(["minute", "records", "calls", "input", "cache_read", "cache_write", "cache_write_long", "output"]);
    db.setAuthorizer((action, table, column) => action === constants.SQLITE_READ && table === "usage_compact" && values.has(column ?? "")
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try {
      const again = await read();
      assert.equal(again?.diagnostics.cache, "reused");
      assert.deepEqual(again?.groups, first.groups, "an unchanged summary does not read the minute buckets again");
    }
    finally { db.setAuthorizer(null); }
    writer.recordUsage("/a", { session: "a", offset: 2, model: "m" }, "claude", [[call("a-1", 60_000, 7), owner]]);
    const next = await read();
    assert.ok(next);
    assert.deepEqual(next.groups, reads.usageGroups(store, 0n, 120n * 60_000n, 0n, viewer));
    assert.equal(next.diagnostics.parts, 1, "only the changed session's minute is read again");
    assert.equal(next.diagnostics.candidates, 1, "a small pending set does not read the other minutes in the range");
    writer.recordUsage("/a", { session: "a", offset: 3, model: "m" }, "claude",
      Array.from({ length: 70 }, (_, n) => [call(`a-${n}`, n * 60_000, 2), owner] as [ReturnType<typeof call>, typeof owner]));
    db.setAuthorizer((action, table, column) => action === constants.SQLITE_READ && table === "usage_compact" && column === "output"
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try { await assert.rejects(read(), /prohibited/); }
    finally { db.setAuthorizer(null); }
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

test("slow usage diagnostics attribute database time to the step that took it", async () => {
  const writer = Store.open(":memory:");
  const descriptor = Object.getOwnPropertyDescriptor(performance, "now");
  let now = 0;
  try {
    writer.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "s", ws: "A", createdAt: 0, lastActiveAt: 0 });
    compact.installCompactUsage(writer.db, () => 0);
    retireUsageIndexes(writer.db);
    writer.recordUsage("/s", { session: "s", offset: 1, model: "m" }, "claude", [[
      { id: "call", at: 0, model: "m", subagent: false, fast: false, input: 1, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null },
      { turn: null, thread: null, person: "p", profile: "cc" },
    ]]);
    while (!compact.compactTotalsStep(writer.db, 64).done) {}
    compact.installUsageSummaryChanges(writer.db);
    writer.db.function("timing_bucket", (day) => { now += 7; return day; });
    const db = new Proxy(writer.db, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => target.prepare(sql.startsWith("SELECT strftime(")
          ? sql.replace("SELECT strftime(", "SELECT timing_bucket(strftime(").replace(" AS day, minute, session", ") AS day, minute, session") : sql);
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    Object.defineProperty(performance, "now", { value: () => now, configurable: true });
    const result = await reads.usageGroupsBatched(reads.makeStore(db, "/tmp"), 0n, 60_000n, 0n,
      { workspace: "A", home: false }, async () => {}, new reads.UsageSummaryCache());
    assert.ok(result);
    assert.equal(result.diagnostics.sql.buckets, 7);
    assert.deepEqual([result.diagnostics.sql.slowOp, result.diagnostics.sql.slowMs], ["buckets", 7]);
    assert.equal(result.groups.length, 1);
  } finally {
    if (descriptor === undefined) delete (performance as any).now;
    else Object.defineProperty(performance, "now", descriptor);
    writer.close();
  }
});

test("cached groups survive removed blocks until their last minute is removed", async () => {
  const writer = Store.open(":memory:");
  try {
    writer.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A", createdAt: 0, lastActiveAt: 0 });
    compact.installCompactUsage(writer.db, () => 0);
    retireUsageIndexes(writer.db);
    writer.db.exec("INSERT INTO usage_minute_scope (session, ws, done) VALUES ('a', 'A', 1)");
    const insert = writer.db.prepare(`INSERT INTO usage_compact
      (session, minute, thread, person, profile, runtime, model, fast, records, calls, input, cache_read, cache_write, cache_write_long, output, scope, pending)
      VALUES ('a', ?, 0, 'p', 'cc', 'claude', ?, 0, 1, 0, 0, 0, 0, 0, ?, 'WA', 0)`);
    insert.run(0, "m", 3);
    insert.run(1, "m", 7);
    insert.run(2, "m", 0);
    insert.run(2, "other", 4);
    compact.installUsageSummaryChanges(writer.db);
    const reader = reads.makeStore(writer.db, "."), cache = new reads.UsageSummaryCache(), viewer = { workspace: "A", home: false };
    const read = async () => {
      const actual = await reads.usageGroupsBatched(reader, 0n, 180_000n, 0n, viewer, async () => {}, cache);
      assert.ok(actual);
      assert.deepEqual(actual.groups, reads.usageGroups(reader, 0n, 180_000n, 0n, viewer));
      return actual.groups;
    };
    await read();
    writer.db.exec("DELETE FROM usage_compact WHERE session='a' AND minute=0 AND model='m'");
    assert.equal((await read()).find((group) => group.model === "m")?.output, 7);
    writer.db.exec("DELETE FROM usage_compact WHERE session='a' AND minute=1 AND model='m'");
    assert.equal((await read()).find((group) => group.model === "m")?.output, 0,
      "an existing all-zero group remains present");
    writer.db.exec("DELETE FROM usage_compact WHERE session='a' AND minute=2 AND model='m'");
    assert.equal((await read()).some((group) => group.model === "m"), false);
    insert.run(1, "m", 5);
    assert.equal((await read()).find((group) => group.model === "m")?.output, 5);
  } finally { writer.close(); }
});

test("an unbounded history settles its workspace's new statistics so its cache can reuse them", async (t) => {
  const dir = mkdtempSync(join(tmpdir(), "usage-unbounded-pending-"));
  const path = join(dir, "stillfail.db");
  const writer = Store.open(path);
  let db: DatabaseSync | null = null;
  let mover: ReturnType<typeof watchCompactMoves> | null = null;
  const lines: Line[] = [];
  hearLines((line) => lines.push(line));
  try {
    for (const key of ["A", "B"]) writer.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc",
      workspace: "/w", token: key, ws: key, createdAt: 0, lastActiveAt: 0 });
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = (id: string, at: number) => ({ id, at, model: "m", subagent: false, fast: false,
      input: 1, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null });
    writer.recordUsage("/A", { session: "A", offset: 0, model: "m" }, "claude", [[call("old", -60_000), owner]]);
    compact.installCompactUsage(writer.db, () => 0);
    retireUsageIndexes(writer.db);
    compact.installUsageSummaryChanges(writer.db);
    for (const key of ["A", "B"]) writer.recordUsage(`/${key}`, { session: key, offset: 1, model: "m" }, "claude",
      Array.from({ length: 128 }, (_, n) => [call(`${key}-${n}`, n * 60_000), owner] as [ReturnType<typeof call>, typeof owner]));
    db = new DatabaseSync(path, { readOnly: true });
    const reader = reads.makeStore(db, dir), cache = new reads.UsageSummaryCache(), viewer = { workspace: "A", home: false };
    const read = async () => {
      db!.exec("BEGIN");
      try { return await reads.usageGroupsBatched(reader, 0n, 128n * 60_000n, 0n, viewer, async () => {}, cache); }
      finally { db!.exec("COMMIT"); }
    };
    const first = await read();
    let ownerReads = 0;
    db.function("count_usage_owner", (ws) => { ownerReads++; return ws; });
    const prepare = db.prepare.bind(db);
    db.prepare = ((sql: string) => prepare(sql === "SELECT ws FROM usage_minute_scope WHERE session = ?"
      ? "SELECT count_usage_owner(ws) AS ws FROM usage_minute_scope WHERE session = ?" : sql)) as typeof db.prepare;
    let pending: Awaited<ReturnType<typeof read>>;
    try { pending = await read(); } finally { db.prepare = prepare; }
    assert.ok(first && pending);
    assert.equal(pending.diagnostics.parts, 128, "pending buckets have to be checked before they are settled");
    assert.equal(ownerReads, 1, "adjacent changed minutes of a session share one ownership check and read");
    usage(reader, "en", 0n, 128n * 60_000n, 0n, false, viewer, false, { batched: pending, remoteRuns: false });
    mover = watchCompactMoves(writer, Promise.resolve());
    const settled = new Promise<void>((resolve, reject) => {
      const abort = () => { unsubscribe(); reject(t.signal.reason); };
      const unsubscribe = writer.subscribe((change) => {
        if (change.type !== "usage" || !change.statisticsOnly || compact.compactTotal(writer.db, viewer) === null) return;
        unsubscribe();
        t.signal.removeEventListener("abort", abort);
        resolve();
      });
      t.signal.addEventListener("abort", abort, { once: true });
    });
    const route = usageRoutes({ read: () => Promise.resolve({ status: 200, headers: {}, body: Buffer.alloc(0) }) } as never,
      () => false, (scope) => mover!.read(scope))[1]!;
    await route.handle({ lang: "en", headers: {}, query: [["history", "1"]], viewer } as never, []);
    await settled;
    assert.deepEqual(compact.compactTotal(writer.db, viewer), { calls: 128, tokens: 256 },
      "a call from before compact statistics is not added to the new total");
    assert.equal((writer.db.prepare("SELECT COUNT(*) AS n FROM usage_compact WHERE scope = 'WB' AND pending = 1").get() as { n: number }).n, 128,
      "the other workspace is not settled by this request");
    const refreshed = await read(), reused = await read();
    assert.ok(refreshed && reused);
    assert.deepEqual(refreshed.groups, first.groups);
    assert.deepEqual(reused.groups, first.groups);
    assert.equal(reused.diagnostics.cache, "reused");
    assert.equal(reused.diagnostics.parts, 0);
    assert.equal(reused.diagnostics.candidates, 0);
    for (let n = 0; n < 2; n++) usage(reader, "en", 0n, 128n * 60_000n, 0n, false, viewer, false, { batched: reused, remoteRuns: false });
    assert.deepEqual(lines.filter((line) => line.message === "a usage read reused its summary")
      .map((line) => [line.fields.summaryParts, line.fields.summaryClean]), [[128, false], [0, true]],
      "the first clean reuse is recorded once even if an earlier reuse still read pending buckets");
  } finally {
    hearLines(null);
    if (mover !== null) await mover.close();
    db?.close();
    writer.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

for (const [scope, viewer] of [["all", null], ["workspace", { workspace: "A", home: false }],
  ["workspace and home", { workspace: "A", home: true }]] as const) test(`a cached summary does not enumerate pending minutes outside its range (${scope})`, async () => {
  const writer = Store.open(":memory:");
  try {
    for (const [key, ws] of [["a", "A"], ["h", null], ["other", "B"]] as const) {
      writer.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key, ws, createdAt: 0, lastActiveAt: 0 });
    }
    compact.installCompactUsage(writer.db, () => 0);
    retireUsageIndexes(writer.db);
    compact.installUsageSummaryChanges(writer.db);
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = (id: string, at: number, output = 1) => ({ id, at, model: "m", subagent: true, fast: false,
      input: 1, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output, calls: 1, context: null, window: null });
    writer.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [[call("within", 60_000), owner]]);
    for (const key of ["h", "other"]) writer.recordUsage(`/${key}`, { session: key, offset: 1, model: "m" }, "claude", [[call(`${key}-within`, 60_000), owner]]);
    while (!compact.compactTotalsStep(writer.db, 64).done) { /* Settle the initial bucket. */ }
    const store = reads.makeStore(writer.db, "."), cache = new reads.UsageSummaryCache();
    const from = 60_000n, to = 120_000n;
    const read = () => reads.usageGroupsBatched(store, from, to, 0n, viewer, async () => {}, cache);
    assert.ok(await read());
    const pending: [ReturnType<typeof call>, typeof owner][] = Array.from({ length: 200 }, (_, i) =>
      [call(`outside-${i}`, (i + 100) * 60_000), owner]);
    pending.push([call("within", 60_000, 7), owner]);
    writer.recordUsage("/a", { session: "a", offset: 2, model: "m" }, "claude", pending);
    for (const key of ["h", "other"]) writer.recordUsage(`/${key}`, { session: key, offset: 2, model: "m" }, "claude", [[call(`${key}-within`, 60_000, 7), owner]]);
    const result = await read();
    assert.ok(result);
    assert.deepEqual(result.groups, reads.usageGroups(store, from, to, 0n, viewer));
    assert.ok(result.diagnostics.candidates <= 70, `one minute is relevant; visited ${result.diagnostics.candidates} candidates`);
  } finally { writer.close(); }
});

test("a wide cached range checks the smaller pending set on one snapshot", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-pending-range-")), path = join(dir, "stillfail.db");
  const writer = Store.open(path);
  const db = new DatabaseSync(path, { readOnly: true });
  try {
    writer.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A", createdAt: 0, lastActiveAt: 0 });
    compact.installCompactUsage(writer.db, () => 0);
    retireUsageIndexes(writer.db);
    compact.installUsageSummaryChanges(writer.db);
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = (n: number, output = 1) => ({ id: `call-${n}`, at: n * 60_000, model: "m", subagent: true, fast: false,
      input: 1, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output, calls: 1, context: null, window: null });
    writer.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", Array.from({ length: 300 }, (_, n) => [call(n), owner]));
    while (!compact.compactTotalsStep(writer.db, 64).done) { /* Settle the initial buckets. */ }
    const store = reads.makeStore(db, dir), cache = new reads.UsageSummaryCache(), viewer = { workspace: "A", home: false };
    const from = 0n, to = 300n * 60_000n;
    const read = async (pause: (ms: number) => Promise<void> = async () => {}) => {
      db.exec("BEGIN");
      try { return await reads.usageGroupsBatched(store, from, to, 0n, viewer, pause, cache); }
      finally { db.exec("COMMIT"); }
    };
    assert.ok(await read());
    writer.recordUsage("/a", { session: "a", offset: 2, model: "m" }, "claude", Array.from({ length: 70 }, (_, n) => [call(n, 3), owner]));
    const before = reads.usageGroups(store, from, to, 0n, viewer);
    let wrote = false;
    const result = await read(async () => {
      if (wrote) return;
      wrote = true;
      writer.recordUsage("/a", { session: "a", offset: 3, model: "m" }, "claude", [[call(1, 9), owner]]);
    });
    assert.ok(wrote && result);
    assert.deepEqual(result.groups, before, "the pending index and range index share the earlier snapshot");
    assert.ok(result.diagnostics.candidates <= 77, `70 pending buckets in 300 minutes visited ${result.diagnostics.candidates} candidates`);
    assert.deepEqual((await read())?.groups, reads.usageGroups(store, from, to, 0n, viewer), "the next read sees the concurrent update");
  } finally { db.close(); writer.close(); rmSync(dir, { recursive: true, force: true }); }
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
    const values = new Set(["minute", "records", "calls", "input", "cache_read", "cache_write", "cache_write_long", "output"]);
    db.setAuthorizer((action, table, column) => action === constants.SQLITE_READ && table === "usage_compact" && values.has(column ?? "")
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try { assert.ok(await read(0)); } finally { db.setAuthorizer(null); }
    const append = writer.db.prepare("INSERT INTO usage_summary_changes (scope, session, minute) VALUES ('WB', 'b', 0)");
    writer.db.exec("BEGIN");
    for (let i = 0; i < 4_300; i++) append.run();
    writer.db.exec("COMMIT");
    const count = (writer.db.prepare("SELECT COUNT(*) AS n FROM usage_summary_changes").get() as { n: number }).n;
    assert.ok(count >= 4096 && count < 4160, "only the bounded recent change journal is retained");
    const fallback = await read(1);
    assert.ok(fallback);
    assert.equal(fallback.diagnostics.cache, "expired");
    assert.ok(fallback.diagnostics.candidates > 0, "a cache older than the journal is rebuilt");
    await same();
  } finally { db.close(); writer.close(); rmSync(dir, { recursive: true, force: true }); }
});

for (const recursive of [false, true]) test(`a pending bucket coalesces writes without losing a cached update (recursive triggers ${recursive})`, async () => {
  const writer = Store.open(":memory:");
  try {
    writer.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A", createdAt: 0, lastActiveAt: 0 });
    compact.installCompactUsage(writer.db, () => 0);
    retireUsageIndexes(writer.db);
    writer.db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    compact.installUsageSummaryChanges(writer.db);
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = { id: "one", at: 60_000, model: "m", subagent: true, fast: false, input: 1,
      cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null };
    writer.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [[call, owner]]);
    while (!compact.compactTotalsStep(writer.db, 64).done) { /* Settle the initial bucket. */ }
    const reader = reads.makeStore(writer.db, "."), cache = new reads.UsageSummaryCache();
    const viewer = { workspace: "A", home: false };
    const read = () => reads.usageGroupsBatched(reader, 0n, 120_000n, 0n, viewer, async () => {}, cache);
    const seq = () => (writer.db.prepare("SELECT COALESCE(MAX(seq), 0) AS n FROM usage_summary_changes").get() as { n: number }).n;
    const same = async () => {
      const result = await read();
      assert.ok(result);
      assert.deepEqual(result.groups, reads.usageGroups(reader, 0n, 120_000n, 0n, viewer));
      return result;
    };
    await same();
    const settledSeq = seq();
    writer.db.exec("UPDATE usage SET output = 3 WHERE id = 'one'");
    assert.equal(seq(), settledSeq, "a value change uses the pending index until it is accounted");
    await same();
    const pendingSeq = seq();
    writer.db.exec("UPDATE usage SET output = 7 WHERE id = 'one'");
    assert.equal(seq(), pendingSeq, "a second write while pending does not write the change journal again");
    assert.equal((await same()).groups[0]?.output, 7, "the pending index invalidates the hour even without a new journal entry");
    while (!compact.compactTotalsStep(writer.db, 64).done) { /* The final state is journaled as it is accounted. */ }
    assert.ok(seq() > pendingSeq);
    assert.equal((await same()).groups[0]?.output, 7);
    writer.db.exec("UPDATE usage SET output = 9 WHERE id = 'one'");
    await same();
    writer.db.exec("DELETE FROM usage WHERE id = 'one'");
    assert.deepEqual((await same()).groups, [], "a pending tombstone cannot retain a removed call");
    while (!compact.compactTotalsStep(writer.db, 64).done) { /* The tombstone is accounted and removed. */ }
    assert.deepEqual((await same()).groups, []);
    writer.recordUsage("/a", { session: "a", offset: 2, model: "m" }, "claude", [[{ ...call, id: "replacement" }, owner]]);
    while (!compact.compactTotalsStep(writer.db, 64).done) { /* Begin from a visible, accounted bucket. */ }
    assert.equal((await same()).groups[0]?.calls, 1);
    writer.db.exec("DELETE FROM usage WHERE id = 'replacement'");
    writer.db.exec(`INSERT OR REPLACE INTO usage_compact
      (session, minute, thread, person, profile, runtime, model, fast, records, calls, input, cache_read, cache_write, cache_write_long, output, scope)
      SELECT session, minute, thread, person, profile, runtime, model, fast, records, calls, input, cache_read, cache_write, cache_write_long, output, 'WB'
      FROM usage_compact WHERE session = 'a'`);
    assert.deepEqual((await same()).groups, [], "replacing a pending tombstone in another scope invalidates the old scope");
  } finally { writer.close(); }
});

test("a cached summary with the year's history says the same as a fresh read, in a reader too", async () => {
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
    assert.ok(expected.history);
    const cache = new reads.UsageSummaryCache();
    const compute = async () => {
      const summary = await reads.usageGroupsBatched(store, 0n, 120n * 60_000n, 0n, viewer, async () => {}, cache);
      assert.ok(summary);
      return usage(store, "en", 0n, 120n * 60_000n, 0n, false, viewer, true, { historyRange: range, batched: summary });
    };
    db.exec("BEGIN");
    try { assert.deepEqual(JSON.parse(JSON.stringify(await compute())), JSON.parse(JSON.stringify(expected))); }
    finally { db.exec("COMMIT"); }
    // Denying the bucket values proves the summary does not reread them.
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
    writer.recordUsage("/a", { session: "a", offset: 3, model: "m" }, "claude", [[{ ...calls[3]![0], output: 9 }, calls[3]![1]]]);
    while (!compact.compactTotalsStep(writer.db, 64).done) { /* Account the changed response. */ }
    const changed = usage(store, "en", 0n, 120n * 60_000n, 0n, false, viewer, true, { historyRange: range });
    db.exec("BEGIN");
    try { assert.deepEqual(JSON.parse(JSON.stringify(await compute())), JSON.parse(JSON.stringify(changed))); }
    finally { db.exec("COMMIT"); }
    assert.deepEqual(JSON.parse(await workers.read("usage", args, "en")), JSON.parse(JSON.stringify(changed)),
      "the actual reader refreshes both the detail and the chart after a write");
    for (const offset of [-61n, 330n]) {
      const interval = { from: -86_400_000n, to: 86_400_000n - offset * 60_000n };
      const expectedAtOffset = usage(store, "en", 0n, 120n * 60_000n, offset, false, viewer, true, { historyRange: interval });
      db.exec("BEGIN");
      try {
        const summary = await reads.usageGroupsBatched(store, 0n, 120n * 60_000n, offset, viewer, async () => {}, cache);
        assert.ok(summary);
        const actual = usage(store, "en", 0n, 120n * 60_000n, offset, false, viewer, true, { historyRange: interval, batched: summary });
        assert.deepEqual(JSON.parse(JSON.stringify(actual)), JSON.parse(JSON.stringify(expectedAtOffset)));
      } finally { db.exec("COMMIT"); }
    }
  } finally { workers?.close(); db?.close(); writer.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a large summary coarsens its cache without exceeding its limit or losing exact totals", async () => {
  const writer = Store.open(":memory:");
  try {
    writer.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A", createdAt: 0, lastActiveAt: 0 });
    compact.installCompactUsage(writer.db, () => 0);
    retireUsageIndexes(writer.db);
    writer.db.exec("INSERT INTO usage_minute_scope (session, ws, done) VALUES ('a', 'A', 1)");
    const bucket = writer.db.prepare(`INSERT INTO usage_compact
      (session, minute, thread, person, profile, runtime, model, fast, records, calls, input, cache_read, cache_write, cache_write_long, output, scope, pending)
      VALUES ('a', ?, 0, 'p', 'cc', 'claude', 'm', 0, 1, 1, 1, 0, 0, 0, 1, 'WA', 0)`);
    writer.db.exec("BEGIN");
    for (let minute = 0; minute < 8_192; minute++) bucket.run(minute);
    writer.db.exec("COMMIT");
    compact.installUsageSummaryChanges(writer.db);
    const reader = reads.makeStore(writer.db, "."), cache = new reads.UsageSummaryCache(), viewer = { workspace: "A", home: false };
    const to = 8_193n * 60_000n, offset = 17n;
    const read = () => reads.usageGroupsBatched(reader, 0n, to, offset, viewer, async () => {}, cache);
    const first = await read();
    assert.ok(first);
    assert.deepEqual(first.groups, reads.usageGroups(reader, 0n, to, offset, viewer));
    bucket.run(8_192);
    const grown = await read();
    assert.ok(grown);
    assert.deepEqual(grown.groups, reads.usageGroups(reader, 0n, to, offset, viewer),
      "a change that crosses the cache limit is still included when rebuilding at a coarser width");
    writer.db.prepare("UPDATE usage_compact SET output=7 WHERE session='a' AND minute=100").run();
    const changed = await read();
    assert.ok(changed);
    assert.equal(changed.diagnostics.cache, "reused");
    assert.equal(changed.diagnostics.parts, 5, "one changed minute refreshes its five-minute block after coarsening");
    assert.deepEqual(changed.groups, reads.usageGroups(reader, 0n, to, offset, viewer));
  } finally { writer.close(); }
});
