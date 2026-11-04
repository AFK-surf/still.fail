import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { constants, DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Worker } from "node:worker_threads";
import * as reads from "../src/read/store.ts";
import { Store } from "../src/store/store.ts";
import { installCompactUsage, installUsageSummaryChanges } from "../src/store/usage-compact.ts";
import { installUsageSummaryBlocks, usageSummaryBlocksPending, usageSummaryBlocksStep } from "../src/store/usage-summary-blocks.ts";

test("a cold usage summary does bounded work as more minutes contribute to the same days", async () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a",
      ws: "A", createdAt: 0, lastActiveAt: 0 });
    installCompactUsage(store.db, () => 0);
    installUsageSummaryChanges(store.db);
    installUsageSummaryBlocks(store.db);
    store.db.exec("INSERT INTO usage_minute_scope (session, ws, done) VALUES ('a', 'A', 1)");
    const insert = store.db.prepare(`INSERT INTO usage_compact
      (session, minute, thread, person, profile, runtime, model, fast, records, calls, input, cache_read, cache_write,
       cache_write_long, output, scope, pending)
      VALUES ('a', ?, 0, 'p', 'cc', 'claude', 'm', 0, 1, 1, 2, 0, 0, 0, 3, 'WA', 0)`);
    for (let minute = 0; minute < 1_440; minute++) insert.run(minute);
    while (!usageSummaryBlocksStep(store.db).done) { /* Prepare the existing minute statistics in small transactions. */ }
    const reader = reads.makeStore(store.db, ".");
    const viewer = { workspace: "A", home: false };
    const from = 0n, to = 1_440n * 60_000n, offset = 17n;
    const expected = reads.usageGroups(reader, from, to, offset, viewer);
    assert.equal(expected.length, 2, "the interval crosses two local days");
    assert.equal(expected.reduce((total, row) => total + row.calls, 0), 1_440);
    const cold = await reads.usageGroupsBatched(reader, from, to, offset, viewer, async () => {});
    assert.ok(cold);
    assert.deepEqual(cold.groups, expected);
    assert.ok(cold.diagnostics.candidates <= 128 && cold.diagnostics.parts <= 128,
      `two displayed groups should not require visiting every minute: ${cold.diagnostics.candidates} candidates, ${cold.diagnostics.parts} parts`);
  } finally { store.close(); }
});

test("a partial-minute range uses grouped statistics for its complete minutes", async () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a",
      ws: "A", createdAt: 0, lastActiveAt: 0 });
    installCompactUsage(store.db, () => 0);
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const calls = Array.from({ length: 1_440 }, (_, n) => [{ id: `call-${n}`, at: (n - 720) * 60_000 + 100,
      model: "m", subagent: false, fast: false, input: 2, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0,
      output: 3, calls: 1, context: null, window: null }, owner] as const);
    store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", calls.map(([call, of]) => [call, of]));
    for (const [key, ws] of [["home", null], ["other", "B"]] as const) {
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key,
        ws, createdAt: 0, lastActiveAt: 0 });
      const at = [-60_001, -1, 0, 1, 59_999, 60_000];
      store.recordUsage(`/${key}`, { session: key, offset: 1, model: "m" }, "claude", at.map((time, n) => [{
        id: `${key}-${n}`, at: time, model: "m", subagent: false, fast: false, input: 7,
        cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 11, calls: 1, context: null, window: null,
      }, owner]));
    }
    installUsageSummaryBlocks(store.db);
    while (!usageSummaryBlocksStep(store.db).done) { /* Prepare the existing minute statistics. */ }
    const reader = reads.makeStore(store.db, "."), viewer = { workspace: "A", home: false };
    const from = -720n * 60_000n + 123n, to = 720n * 60_000n - 123n, offset = 17n;
    const expected = reads.usageGroups(reader, from, to, offset, viewer);
    assert.equal(expected.reduce((total, row) => total + row.calls, 0), 1_439);
    const actual = await reads.usageGroupsBatched(reader, from, to, offset, viewer, async () => {});
    assert.ok(actual, "partial bounds should not send the entire range to the old minute query");
    assert.deepEqual(actual.groups, expected);
    assert.ok(actual.diagnostics.candidates <= 128 && actual.diagnostics.parts <= 128,
      `the complete minutes should use groups: ${actual.diagnostics.candidates} candidates, ${actual.diagnostics.parts} parts`);
    const ranges = [[-60_001n, 60_001n], [-1n, 1n], [0n, 59_999n], [1n, 60_000n],
      [0n, 9_223_372_036_854_775_807n], [1n, 9_223_372_036_854_775_807n], [1n, 1n],
      [-86_399_999n, 86_400_001n]] as const;
    for (const [begin, end] of ranges) for (const tz of [-31n, 0n, 345n]) for (const who of [null, viewer, { workspace: "A", home: true }]) {
      const grouped = await reads.usageGroupsBatched(reader, begin, end, tz, who, async () => {});
      assert.ok(grouped);
      assert.deepEqual(grouped.groups, reads.usageGroups(reader, begin, end, tz, who), `${begin}..${end}, offset ${tz}, viewer ${JSON.stringify(who)}`);
    }
  } finally { store.close(); }
});

test("a busy partial minute yields while keeping the same read snapshot", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-summary-edge-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path);
  let db: DatabaseSync | null = null;
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a",
      ws: "A", createdAt: 0, lastActiveAt: 0 });
    installCompactUsage(store.db, () => 0);
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = (n: number, output = 3) => ({ id: `call-${n}`, at: 100 + n, model: "m", subagent: false, fast: false,
      input: 2, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output, calls: 1, context: null, window: null });
    store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", Array.from({ length: 200 }, (_, n) => [call(n), owner]));
    installUsageSummaryBlocks(store.db);
    while (!usageSummaryBlocksStep(store.db).done) { /* Prepare the existing minute statistics. */ }
    db = new DatabaseSync(path, { readOnly: true });
    const reader = reads.makeStore(db, dir), viewer = { workspace: "A", home: false };
    db.exec("BEGIN");
    try {
      const expected = reads.usageGroups(reader, 1n, 60_000n, 0n, viewer);
      let pauses = 0;
      const actual = await reads.usageGroupsBatched(reader, 1n, 60_000n, 0n, viewer, async () => {
        if (++pauses === 1) store.recordUsage("/a", { session: "a", offset: 2, model: "m" }, "claude", [[call(0, 9), owner]]);
      });
      assert.ok(actual);
      assert.ok(pauses > 1, "the calls at the edge give other work a turn");
      assert.deepEqual(actual.groups, expected, "all edge calls belong to the snapshot taken before the update");
      assert.equal(actual.groups.reduce((total, row) => total + row.calls, 0), 200);
    } finally { db.exec("COMMIT"); }
    assert.equal(reads.usageGroups(reader, 1n, 60_000n, 0n, viewer)[0]?.output, 606);
  } finally { db?.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a sparse usage range skips years with no usage", async () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a",
      ws: "A", createdAt: 0, lastActiveAt: 0 });
    installCompactUsage(db, () => 0);
    installUsageSummaryBlocks(db);
    db.exec("INSERT INTO usage_minute_scope (session, ws, done) VALUES ('a', 'A', 1)");
    const put = db.prepare(`INSERT INTO usage_compact
      (session, minute, thread, person, profile, runtime, model, fast, records, calls, input, cache_read, cache_write,
       cache_write_long, output, scope, pending) VALUES ('a', ?, 0, 'p', 'cc', 'claude', 'm', 0, 1, 1, 2, 0, 0, 0, 3, 'WA', 0)`);
    put.run(0);
    put.run(42_048_000);
    while (!usageSummaryBlocksStep(db).done) { /* Settle both buckets. */ }
    const viewer = { workspace: "A", home: false };
    const from = -2_208_988_800_000n, to = 4_102_444_800_000n;
    const expected = reads.usageGroups(reads.makeStore(db, "."), from, to, 17n, viewer);
    let seeks = 0;
    const observed = new Proxy(db, { get(target, key, receiver) {
      if (key !== "prepare") return Reflect.get(target, key, receiver);
      return (sql: string) => {
        const stmt = target.prepare(sql);
        if (!sql.includes("SELECT bucket FROM usage_summary_blocks") || !sql.includes("bucket >= ?1")) return stmt;
        return new Proxy(stmt, { get(statement, name) {
          const value = Reflect.get(statement, name, statement);
          if (name === "get") return (...args: Parameters<typeof stmt.get>) => { seeks++; return stmt.get(...args); };
          return typeof value === "function" ? value.bind(statement) : value;
        } });
      };
    } });
    const actual = await reads.usageGroupsBatched(reads.makeStore(observed, "."), from, to, 17n, viewer, async () => {});
    assert.ok(actual);
    assert.equal(actual.diagnostics.cache, "indexed");
    assert.deepEqual(actual.groups, expected);
    assert.ok(seeks > 0 && seeks <= 6, `two days of usage required ${seeks} indexed seeks`);
  } finally { store.close(); }
});

test("a summary remains bounded while many existing minutes are being updated", async () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a",
      ws: "A", createdAt: 0, lastActiveAt: 0 });
    installCompactUsage(db, () => 0);
    installUsageSummaryBlocks(db);
    db.exec("INSERT INTO usage_minute_scope (session, ws, done) VALUES ('a', 'A', 1)");
    const put = db.prepare(`INSERT INTO usage_compact
      (session, minute, thread, person, profile, runtime, model, fast, records, calls, input, cache_read, cache_write,
       cache_write_long, output, scope, pending) VALUES ('a', ?, 0, 'p', 'cc', 'claude', 'm', 0, 1, 1, 2, 0, 0, 0, 3, 'WA', 0)`);
    for (let minute = 0; minute < 1_440; minute++) put.run(minute);
    while (!usageSummaryBlocksStep(db).done) { /* Prepare the original statistics. */ }
    db.exec("UPDATE usage_compact SET output = 4 WHERE session = 'a' AND minute < 200");
    const reader = reads.makeStore(db, "."), viewer = { workspace: "A", home: false };
    const from = 0n, to = 1_440n * 60_000n;
    await assert.rejects(reads.usageGroupsBatched(reader, from, to, 0n, viewer, async () => {}),
      (error: unknown) => error instanceof Error && "status" in error && error.status === 503
        && error.message === "usage summary statistics are being prepared",
      "a reader waits for the worker rather than reading the whole day");
    while (!usageSummaryBlocksStep(db).done) { /* Let the worker settle the updated buckets. */ }
    const actual = await reads.usageGroupsBatched(reader, from, to, 0n, viewer, async () => {});
    assert.ok(actual);
    assert.deepEqual(actual.groups, reads.usageGroups(reader, from, to, 0n, viewer));
    assert.ok(actual.diagnostics.candidates <= 128 && actual.diagnostics.parts <= 128,
      `updating 200 minutes should not require reading the whole day: ${actual.diagnostics.candidates} candidates, ${actual.diagnostics.parts} parts`);
  } finally { store.close(); }
});

test("an unfinished summary is prepared without reading its old minutes on the requesting reader", async () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a",
      ws: "A", createdAt: 0, lastActiveAt: 0 });
    installCompactUsage(db, () => 0);
    db.exec("INSERT INTO usage_minute_scope (session, ws, done) VALUES ('a', 'A', 1)");
    const put = db.prepare(`INSERT INTO usage_compact
      (session, minute, thread, person, profile, runtime, model, fast, records, calls, input, cache_read, cache_write,
       cache_write_long, output, scope, pending) VALUES ('a', ?, 0, 'p', 'cc', 'claude', 'm', 0, 1, 1, 2, 0, 0, 0, 3, 'WA', 0)`);
    for (let minute = 0; minute < 1_440; minute++) put.run(minute);
    installUsageSummaryBlocks(db);
    const reader = reads.makeStore(db, "."), viewer = { workspace: "A", home: false };
    db.setAuthorizer((action, table) => action === constants.SQLITE_READ && table === "usage_compact" ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try {
      await assert.rejects(reads.usageGroupsBatched(reader, 0n, 1_440n * 60_000n, 0n, viewer, async () => {}),
        (error: unknown) => error instanceof Error && "status" in error && error.status === 503
          && error.message === "usage summary statistics are being prepared");
    } finally { db.setAuthorizer(null); }
    while (!usageSummaryBlocksStep(db).done) { /* Prepare the existing statistics in bounded transactions. */ }
    const actual = await reads.usageGroupsBatched(reader, 0n, 1_440n * 60_000n, 0n, viewer, async () => {});
    assert.ok(actual);
    assert.deepEqual(actual.groups, reads.usageGroups(reader, 0n, 1_440n * 60_000n, 0n, viewer));
    assert.ok(actual.diagnostics.candidates <= 128 && actual.diagnostics.parts <= 128);
  } finally { db.setAuthorizer(null); store.close(); }
});

test("a reader waits when grouped usage statistics have not yet been installed", async () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    const reader = reads.makeStore(db, "."), viewer = { workspace: "A", home: false };
    const ask = () => reads.usageGroupsBatched(reader, 0n, 60_000n, 0n, viewer, async () => {}, undefined, false);
    const pending = (error: unknown) => error instanceof Error && "status" in error && error.status === 503
      && error.message === "usage summary statistics are being prepared";
    await assert.rejects(ask(), pending, "before compact statistics exist the old call history is not scanned");
    installCompactUsage(db, () => 0);
    db.setAuthorizer((action, table) => action === constants.SQLITE_READ && table === "usage_compact" ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try { await assert.rejects(ask(), pending, "compact minutes are not scanned while their grouped index is missing"); }
    finally { db.setAuthorizer(null); }
  } finally { db.setAuthorizer(null); store.close(); }
});

test("preparing a workspace does not first convert another workspace's history", async () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    for (const [session, ws] of [["a", "B"], ["z", "A"]] as const) {
      store.insertSession({ key: session, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: session,
        ws, createdAt: 0, lastActiveAt: 0 });
    }
    installCompactUsage(db, () => 0);
    db.exec("INSERT INTO usage_minute_scope (session, ws, done) VALUES ('a', 'B', 1), ('z', 'A', 1)");
    const put = db.prepare(`INSERT INTO usage_compact
      (session, minute, thread, person, profile, runtime, model, fast, records, calls, input, cache_read, cache_write,
       cache_write_long, output, scope, pending) VALUES (?, ?, 0, 'p', 'cc', 'claude', 'm', 0, 1, 1, 2, 0, 0, 0, 3, ?, 0)`);
    for (let minute = 0; minute < 1_000; minute++) put.run("a", minute, "WB");
    for (let minute = 0; minute < 3; minute++) put.run("z", minute, "WA");
    installUsageSummaryBlocks(db);
    const reader = reads.makeStore(db, "."), viewer = { workspace: "A", home: false };
    const empty = await reads.usageGroupsBatched(reader, 0n, 0n, 0n, viewer, async () => {});
    assert.deepEqual(empty?.groups, [], "an empty interval does not wait for history to be prepared");
    const step = usageSummaryBlocksStep(db, 7, "WA");
    assert.deepEqual(step, { done: true, processed: 3 }, "the requested workspace has only three minutes to prepare");
    assert.equal((db.prepare("SELECT COUNT(*) AS n FROM usage_summary_blocks_shadow WHERE scope = 'WB'").get() as { n: number }).n, 0);
    assert.equal((db.prepare("SELECT done FROM usage_summary_blocks_progress WHERE id = 1").get() as { done: number }).done, 0,
      "the station can continue preparing other workspaces in the background");
    const result = await reads.usageGroupsBatched(reader, 0n, 3n * 60_000n, 0n, viewer, async () => {});
    assert.ok(result);
    assert.deepEqual(result.groups, reads.usageGroups(reader, 0n, 3n * 60_000n, 0n, viewer));
  } finally { store.close(); }
});

test("preparing a recent usage range does not first convert older minutes in the same workspace", async () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a",
      ws: "A", createdAt: 0, lastActiveAt: 0 });
    installCompactUsage(db, () => 0);
    db.exec("INSERT INTO usage_minute_scope (session, ws, done) VALUES ('a', 'A', 1)");
    const put = db.prepare(`INSERT INTO usage_compact
      (session, minute, thread, person, profile, runtime, model, fast, records, calls, input, cache_read, cache_write,
       cache_write_long, output, scope, pending) VALUES ('a', ?, 0, 'p', 'cc', 'claude', 'm', 0, 1, 1, 2, 0, 0, 0, 3, 'WA', 0)`);
    for (let minute = -1_000; minute < 0; minute++) put.run(minute);
    for (let minute = 0; minute < 3; minute++) put.run(minute);
    installUsageSummaryBlocks(db);
    const step = usageSummaryBlocksStep(db, 7, "WA", { from: 0n, to: 3n });
    assert.deepEqual(step, { done: true, processed: 3 }, "the requested interval contains only three minutes");
    assert.equal((db.prepare("SELECT COUNT(*) AS n FROM usage_summary_blocks_shadow WHERE minute < 0").get() as { n: number }).n, 0);
    const reader = reads.makeStore(db, "."), viewer = { workspace: "A", home: false };
    const result = await reads.usageGroupsBatched(reader, 0n, 3n * 60_000n, 0n, viewer, async () => {}, undefined, true);
    assert.ok(result);
    assert.deepEqual(result.groups, reads.usageGroups(reader, 0n, 3n * 60_000n, 0n, viewer));
  } finally { store.close(); }
});

for (const recursive of [false, true]) test(`a prepared range includes edits made during its batches (recursive triggers ${recursive})`, async () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a",
      ws: "A", createdAt: 0, lastActiveAt: 0 });
    installCompactUsage(db, () => 0);
    db.exec("INSERT INTO usage_minute_scope (session, ws, done) VALUES ('a', 'A', 1)");
    const put = db.prepare(`INSERT OR REPLACE INTO usage_compact
      (session, minute, thread, person, profile, runtime, model, fast, records, calls, input, cache_read, cache_write,
       cache_write_long, output, scope, pending) VALUES ('a', ?, 0, 'p', ?, 'claude', 'm', 0, 1, 1, 2, 0, 0, 0, ?, 'WA', 0)`);
    for (let minute = -100; minute < 0; minute++) put.run(minute, "cc", 3);
    for (let minute = 0; minute < 10; minute++) put.run(minute, "cc", 3);
    for (let n = 0; n < 20; n++) put.run(10, `p${n}`, 3);
    installUsageSummaryBlocks(db);
    const range: import("../src/store/usage-summary-blocks.ts").UsageSummaryRange = { from: 0n, to: 11n };
    let step = usageSummaryBlocksStep(db, 4, "WA", range);
    assert.equal(step.processed, 4);
    assert.ok(step.after);
    range.after = step.after;
    put.run(0, "cc", 9);
    put.run(9, "cc", 7);
    put.run(2, "added", 4);
    put.run(-1, "cc", 8);
    db.prepare("DELETE FROM usage_compact WHERE session = 'a' AND minute = 1").run();
    for (let n = 0; n < 40 && !step.done; n++) {
      step = usageSummaryBlocksStep(db, 4, "WA", range);
      if (step.after) range.after = step.after;
      if (step.converted) range.converted = true;
    }
    assert.equal(step.done, true);
    assert.equal(usageSummaryBlocksPending(db, "WA", { ...range, converted: true }), false);
    assert.equal((db.prepare("SELECT COUNT(*) AS n FROM usage_summary_blocks_shadow WHERE minute < 0").get() as { n: number }).n, 0,
      "changes outside the requested range do not hold it up");
    const reader = reads.makeStore(db, "."), viewer = { workspace: "A", home: false };
    const from = 0n, to = 11n * 60_000n;
    const result = await reads.usageGroupsBatched(reader, from, to, 17n, viewer, async () => {}, undefined, true);
    assert.ok(result);
    assert.deepEqual(result.groups, reads.usageGroups(reader, from, to, 17n, viewer));
    while (!usageSummaryBlocksStep(db, 7).done) { /* Finish the station-wide conversion too. */ }
    const full = await reads.usageGroupsBatched(reader, from, to, 17n, viewer, async () => {});
    assert.deepEqual(full?.groups, result.groups, "the later global conversion does not double count the range");
  } finally { store.close(); }
});

for (const recursive of [false, true]) test(`a requested workspace keeps concurrent changes during conversion (recursive triggers ${recursive})`, async () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    for (const [session, ws] of [["a", "B"], ["z", "A"]] as const) {
      store.insertSession({ key: session, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: session,
        ws, createdAt: 0, lastActiveAt: 0 });
    }
    installCompactUsage(db, () => 0);
    db.exec("INSERT INTO usage_minute_scope (session, ws, done) VALUES ('a', 'B', 1), ('z', 'A', 1)");
    const put = db.prepare(`INSERT OR REPLACE INTO usage_compact
      (session, minute, thread, person, profile, runtime, model, fast, records, calls, input, cache_read, cache_write,
       cache_write_long, output, scope, pending) VALUES (?, ?, 0, 'p', 'cc', 'claude', 'm', 0, 1, 1, 2, 0, 0, 0, ?, ?, 0)`);
    for (let minute = 0; minute < 100; minute++) put.run("a", minute, 3, "WB");
    for (let minute = 0; minute < 12; minute++) put.run("z", minute, 3, "WA");
    installUsageSummaryBlocks(db);
    assert.deepEqual(usageSummaryBlocksStep(db, 4, "WA"), { done: false, processed: 4 });
    put.run("z", 0, 9, "WA");
    put.run("z", 10, 7, "WA");
    put.run("z", -1, 4, "WA");
    put.run("z", 2, 5, "WB");
    db.prepare("DELETE FROM usage_compact WHERE session = 'z' AND minute = 1").run();
    for (let n = 0; n < 30 && usageSummaryBlocksPending(db, "WA"); n++) usageSummaryBlocksStep(db, 4, "WA");
    assert.equal(usageSummaryBlocksPending(db, "WA"), false);
    assert.equal((db.prepare("SELECT done FROM usage_summary_blocks_progress WHERE id = 1").get() as { done: number }).done, 0);
    const reader = reads.makeStore(db, "."), viewer = { workspace: "A", home: false };
    const from = -60_000n, to = 12n * 60_000n;
    const scoped = await reads.usageGroupsBatched(reader, from, to, 17n, viewer, async () => {});
    assert.ok(scoped);
    assert.deepEqual(scoped.groups, reads.usageGroups(reader, from, to, 17n, viewer));
    while (!usageSummaryBlocksStep(db, 4).done) { /* The station-wide scan can later pass the same rows. */ }
    for (const who of [null, viewer, { workspace: "B", home: false }]) {
      const finished = await reads.usageGroupsBatched(reader, from, to, 17n, who, async () => {});
      assert.ok(finished);
      assert.deepEqual(finished.groups, reads.usageGroups(reader, from, to, 17n, who));
    }
  } finally { store.close(); }
});

test("block summaries keep one snapshot while their buckets are updated and accounted", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-summary-snapshot-"));
  const path = join(dir, "stillfail.db");
  const writer = Store.open(path);
  let reader: DatabaseSync | null = null;
  try {
    writer.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a",
      ws: "A", createdAt: 0, lastActiveAt: 0 });
    installCompactUsage(writer.db, () => 0);
    installUsageSummaryBlocks(writer.db);
    writer.db.exec("INSERT INTO usage_minute_scope (session, ws, done) VALUES ('a', 'A', 1)");
    const put = writer.db.prepare(`INSERT INTO usage_compact
      (session, minute, thread, person, profile, runtime, model, fast, records, calls, input, cache_read, cache_write,
       cache_write_long, output, scope, pending) VALUES ('a', 0, 0, 'p', ?, 'claude', 'm', 0, 1, 1, 2, 0, 0, 0, 3, 'WA', 0)`);
    for (let n = 0; n < 100; n++) put.run(`p${n}`);
    while (!usageSummaryBlocksStep(writer.db).done) { /* Prepare the original statistics. */ }
    writer.db.prepare("UPDATE usage_compact SET output = 5 WHERE session = 'a' AND profile = 'p0'").run();
    reader = new DatabaseSync(path, { readOnly: true });
    const read = reads.makeStore(reader, dir), viewer = { workspace: "A", home: false };
    const from = 0n, to = 60n * 60_000n;
    const expected = reads.usageGroups(read, from, to, 0n, viewer);
    let pauses = 0;
    reader.exec("BEGIN");
    try {
      const answer = await reads.usageGroupsBatched(read, from, to, 0n, viewer, async () => {
        if (++pauses === 1) {
          writer.db.prepare("UPDATE usage_compact SET output = 9 WHERE session = 'a' AND profile = 'p0'").run();
          while (!usageSummaryBlocksStep(writer.db).done) { /* Account the newer value on the writer. */ }
        }
      });
      assert.ok(answer);
      assert.equal(answer.diagnostics.cache, "indexed");
      assert.ok(pauses > 0);
      assert.deepEqual(answer.groups, expected, "the overlay and grouped rows see the same snapshot");
    } finally { reader.exec("COMMIT"); }
    const fresh = await reads.usageGroupsBatched(read, from, to, 0n, viewer, async () => {});
    assert.ok(fresh);
    assert.notDeepEqual(fresh.groups, expected);
    assert.deepEqual(fresh.groups, reads.usageGroups(read, from, to, 0n, viewer));
  } finally { reader?.close(); writer.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("existing summaries are prepared in bounded transactions as their minutes change", async () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    for (const [session, ws] of [["a", "A"], ["b", "B"]] as const) {
      store.insertSession({ key: session, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: session,
        ws, createdAt: 0, lastActiveAt: 0 });
    }
    installCompactUsage(db, () => 0);
    db.exec("INSERT INTO usage_minute_scope (session, ws, done) VALUES ('a', 'A', 1), ('b', 'B', 1)");
    const put = (verb: string) => db.prepare(`${verb} INTO usage_compact
      (session, minute, thread, person, profile, runtime, model, fast, records, calls, input, cache_read, cache_write,
       cache_write_long, output, scope, pending) VALUES (?, ?, 0, 'p', 'cc', 'claude', 'm', 0, 1, 1, 2, 0, 0, 0, ?, ?, 0)`);
    const insert = put("INSERT"), replace = put("INSERT OR REPLACE");
    for (const session of ["a", "b"]) for (let minute = -80; minute < 80; minute++)
      insert.run(session, minute, 3, session === "a" ? "WA" : "WB");
    db.setAuthorizer((action, table) => action === constants.SQLITE_READ && table === "usage" ? constants.SQLITE_DENY : constants.SQLITE_OK);
    installUsageSummaryBlocks(db);
    const before = db.prepare("SELECT * FROM usage_summary_blocks_progress WHERE id = 1").get();
    db.exec(`CREATE TEMP TRIGGER fail_usage_blocks BEFORE INSERT ON main.usage_summary_blocks
      BEGIN SELECT RAISE(ABORT, 'injected block failure'); END`);
    assert.throws(() => usageSummaryBlocksStep(db, 7), /injected block failure/);
    db.exec("DROP TRIGGER fail_usage_blocks");
    assert.deepEqual(db.prepare("SELECT * FROM usage_summary_blocks_progress WHERE id = 1").get(), before,
      "a failed batch cannot advance its cursor");
    assert.equal(usageSummaryBlocksStep(db, 7).processed, 7);
    db.prepare("UPDATE usage_compact SET output = 9 WHERE session = 'a' AND minute = -80").run();
    db.prepare("UPDATE usage_compact SET output = 7 WHERE session = 'a' AND minute = 30").run();
    db.prepare("DELETE FROM usage_compact WHERE session = 'b' AND minute = -2").run();
    insert.run("a", -500, 4, "WA");
    replace.run("a", -79, 11, "WA");
    let finished = false;
    for (let n = 0; n < 200; n++) {
      const step = usageSummaryBlocksStep(db, 7);
      assert.ok(step.processed <= 7);
      if (step.done) { finished = true; break; }
    }
    assert.ok(finished);
    db.setAuthorizer(null);
    const reader = reads.makeStore(db, ".");
    for (const viewer of [null, { workspace: "A", home: false }, { workspace: "B", home: false }]) {
      for (const offset of [-330n, 0n, 17n]) {
        const from = -600n * 60_000n, to = 200n * 60_000n;
        const expected = reads.usageGroups(reader, from, to, offset, viewer);
        const actual = await reads.usageGroupsBatched(reader, from, to, offset, viewer, async () => {});
        assert.ok(actual);
        assert.equal(actual.diagnostics.cache, "indexed");
        assert.deepEqual(actual.groups, expected);
      }
    }
    db.prepare("UPDATE usage_compact SET output = 12 WHERE session = 'a' AND minute = -80").run();
    const viewer = { workspace: "A", home: false };
    const from = -600n * 60_000n, to = 200n * 60_000n;
    const dirty = await reads.usageGroupsBatched(reader, from, to, 17n, viewer, async () => {});
    assert.ok(dirty);
    assert.equal(dirty.diagnostics.cache, "indexed", "a small number of changing minutes can be overlaid on the blocks");
    assert.deepEqual(dirty.groups, reads.usageGroups(reader, from, to, 17n, viewer), "pending changes never produce a stale answer");
    while (!usageSummaryBlocksStep(db, 7).done) { /* Settle changes. */ }
    const clean = await reads.usageGroupsBatched(reader, from, to, 17n, viewer, async () => {});
    assert.ok(clean);
    assert.equal(clean.diagnostics.cache, "indexed");
    assert.deepEqual(clean.groups, dirty.groups);
    for (let n = 0; n < 100; n++) db.prepare("UPDATE usage_compact SET output = ? WHERE session = 'a' AND minute = -80").run(n);
    assert.equal((db.prepare("SELECT COUNT(*) AS n FROM usage_summary_blocks_dirty").get() as { n: number }).n, 1,
      "repeated changes to one minute leave one pending bucket");
    const grown = await reads.usageGroupsBatched(reader, from, to, 17n, viewer, async () => {});
    assert.ok(grown);
    assert.equal(grown.diagnostics.cache, "indexed");
    assert.deepEqual(grown.groups, reads.usageGroups(reader, from, to, 17n, viewer));
    replace.run("a", -79, 6, "WB");
    db.prepare("DELETE FROM usage_compact WHERE session = 'b' AND minute = 0").run();
    for (const who of [null, viewer, { workspace: "B", home: false }]) {
      const changed = await reads.usageGroupsBatched(reader, from, to, 17n, who, async () => {});
      assert.ok(changed);
      assert.equal(changed.diagnostics.cache, "indexed");
      assert.deepEqual(changed.groups, reads.usageGroups(reader, from, to, 17n, who),
        "a replaced scope and a deleted bucket are overlaid in the same snapshot");
    }
  } finally { db.setAuthorizer(null); store.close(); }
});

test("a stopped summary conversion resumes with changes made while it was stopped", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-summary-blocks-"));
  const path = join(dir, "stillfail.db");
  let store: Store | null = Store.open(path);
  let previous: DatabaseSync | null = null;
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a",
      ws: "A", createdAt: 0, lastActiveAt: 0 });
    installCompactUsage(store.db, () => 0);
    store.db.exec("INSERT INTO usage_minute_scope (session, ws, done) VALUES ('a', 'A', 1)");
    const insert = store.db.prepare(`INSERT INTO usage_compact
      (session, minute, thread, person, profile, runtime, model, fast, records, calls, input, cache_read, cache_write,
       cache_write_long, output, scope, pending) VALUES ('a', ?, 0, 'p', 'cc', 'claude', 'm', 0, 1, 1, 2, 0, 0, 0, 3, 'WA', 0)`);
    for (let minute = 0; minute < 100; minute++) insert.run(minute);
    installUsageSummaryBlocks(store.db);
    assert.equal(usageSummaryBlocksStep(store.db, 10).processed, 10);
    store.close();
    store = null;
    previous = new DatabaseSync(path);
    previous.prepare("UPDATE usage_compact SET output = 9 WHERE session = 'a' AND minute = 0").run();
    previous.prepare("DELETE FROM usage_compact WHERE session = 'a' AND minute = 20").run();
    previous.close();
    previous = null;
    store = Store.open(path);
    while (!usageSummaryBlocksStep(store.db, 10).done) { /* Continue from the durable cursor. */ }
    const reader = reads.makeStore(store.db, dir), viewer = { workspace: "A", home: false };
    const result = await reads.usageGroupsBatched(reader, 0n, 100n * 60_000n, 0n, viewer, async () => {});
    assert.ok(result);
    assert.equal(result.diagnostics.cache, "indexed");
    assert.deepEqual(result.groups, reads.usageGroups(reader, 0n, 100n * 60_000n, 0n, viewer));
  } finally { previous?.close(); store?.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("the background worker resumes and accounts requested workspaces independently", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-summary-worker-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path);
  let worker: Worker | null = null;
  try {
    for (const [session, ws] of [["a", "A"], ["b", "B"]] as const) {
      store.insertSession({ key: session, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: session,
        ws, createdAt: 0, lastActiveAt: 0 });
    }
    installCompactUsage(store.db, () => 0);
    store.db.exec("INSERT INTO usage_minute_scope (session, ws, done) VALUES ('a', 'A', 1), ('b', 'B', 1)");
    const insert = store.db.prepare(`INSERT INTO usage_compact
      (session, minute, thread, person, profile, runtime, model, fast, records, calls, input, cache_read, cache_write,
       cache_write_long, output, scope, pending) VALUES (?, ?, 0, 'p', 'cc', 'claude', 'm', 0, 1, 1, 2, 0, 0, 0, 3, ?, 0)`);
    for (const [session, scope] of [["a", "WA"], ["b", "WB"]] as const)
      for (let minute = 0; minute < 40; minute++) insert.run(session, minute, scope);
    installUsageSummaryBlocks(store.db);
    usageSummaryBlocksStep(store.db, 3);
    worker = new Worker(new URL("../src/usage/scope-worker.ts", import.meta.url), { workerData: { path, priority: store.backfillPriority } });
    const wake = (scope?: string) => new Promise<{ done: boolean; error?: string }>((resolve, reject) => {
      const fail = (error: Error) => { worker!.off("message", success); reject(error); };
      const success = (answer: { done: boolean; error?: string }) => { worker!.off("error", fail); resolve(answer); };
      worker!.once("message", success);
      worker!.once("error", fail);
      worker!.postMessage({ wake: true, ...(scope === undefined ? {} : { scope }) });
    });
    for (let n = 0; n < 20; n++) {
      const result = await wake();
      assert.equal(result.error, undefined);
      if (result.done) break;
    }
    assert.equal(usageSummaryBlocksPending(store.db), false);
    store.db.prepare("UPDATE usage_compact SET output = 9 WHERE session = 'a' AND minute = 0").run();
    store.db.prepare("UPDATE usage_compact SET output = 10 WHERE session = 'b' AND minute = 0").run();
    for (let n = 0; n < 20; n++) {
      const result = await wake("WA");
      assert.equal(result.error, undefined);
      if (result.done) break;
    }
    assert.equal(usageSummaryBlocksPending(store.db, "WA"), false);
    assert.equal(usageSummaryBlocksPending(store.db, "WB"), true, "reading one workspace does not settle another");
  } finally { if (worker !== null) await worker.terminate(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("block summaries agree with minute summaries through a reproducible mix of edits", async () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    for (const [session, ws] of [["a", "A"], ["b", "B"]] as const) {
      store.insertSession({ key: session, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: session,
        ws, createdAt: 0, lastActiveAt: 0 });
    }
    installCompactUsage(db, () => 0);
    installUsageSummaryChanges(db);
    installUsageSummaryBlocks(db);
    db.exec("INSERT INTO usage_minute_scope (session, ws, done) VALUES ('a', 'A', 1), ('b', 'B', 1)");
    const put = db.prepare(`INSERT OR REPLACE INTO usage_compact
      (session, minute, thread, person, profile, runtime, model, fast, records, calls, input, cache_read, cache_write,
       cache_write_long, output, scope, pending) VALUES (?, ?, 0, 'p', 'cc', 'claude', ?, 0, 1, ?, ?, 0, 0, 0, ?, ?, 0)`);
    const del = db.prepare("DELETE FROM usage_compact WHERE session = ? AND minute = ? AND model = ?");
    const reader = reads.makeStore(db, ".");
    let seed = 0x193ab47;
    const next = (max: number) => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % max; };
    for (let n = 0; n < 260; n++) {
      const session = next(2) ? "a" : "b", minute = next(301) - 150, model = next(2) ? "m" : "other";
      if (next(4) === 0) del.run(session, minute, model);
      else put.run(session, minute, model, next(3), next(4), next(5), session === "a" ? "WA" : "WB");
      if (n % 9 === 0) usageSummaryBlocksStep(db, 5);
      if (n % 37 === 0) {
        for (const viewer of [null, { workspace: "A", home: false }, { workspace: "B", home: false }]) {
          for (const offset of [-330n, 0n, 17n]) {
            const from = -200n * 60_000n, to = 200n * 60_000n;
            const answer = await reads.usageGroupsBatched(reader, from, to, offset, viewer, async () => {});
            assert.ok(answer);
            assert.deepEqual(answer.groups, reads.usageGroups(reader, from, to, offset, viewer), `step ${n}, offset ${offset}`);
          }
        }
      }
    }
    while (!usageSummaryBlocksStep(db, 5).done) { /* Settle the remaining changes. */ }
    const owner = { turn: null, thread: null, person: "p", profile: "cc" };
    const call = { id: "real", at: 8_000_000, model: "m", subagent: false, fast: false, input: 2,
      cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null };
    store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [[call, owner]]);
    store.recordUsage("/a", { session: "a", offset: 2, model: "m" }, "claude", [[{ ...call, output: 8 }, owner]]);
    const from = -200n * 60_000n, to = 200n * 60_000n, viewer = { workspace: "A", home: false };
    const answer = await reads.usageGroupsBatched(reader, from, to, 17n, viewer, async () => {});
    assert.ok(answer);
    assert.equal(answer.diagnostics.cache, "indexed");
    assert.deepEqual(answer.groups, reads.usageGroups(reader, from, to, 17n, viewer));
  } finally { store.close(); }
});
