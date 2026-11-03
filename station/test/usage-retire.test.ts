import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { constants, DatabaseSync } from "node:sqlite";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Effect, Fiber } from "effect";
import { makeStore, usageByDay, usageGroups } from "../src/read/store.ts";
import { Store } from "../src/store/store.ts";
import { installUsageDetail } from "../src/store/usage-detail.ts";
import { dropUsageIndexStep, stopUsageIndexes, usageIndexBatchSql } from "../src/store/usage-retire.ts";
import { retireAfterPrevious } from "../src/usage/module.ts";

test("installing compact statistics tells a waiting page even with no calls", async () => {
  const store = Store.open(":memory:");
  const told: unknown[] = [];
  const stop = store.subscribe((change) => { if (change.type === "usage") told.push(change); });
  try {
    await Effect.runPromise(retireAfterPrevious(store, Promise.resolve()));
    assert.deepEqual(told, [{ type: "usage", sessions: [], statisticsOnly: true }]);
  } finally { stop(); store.close(); }
});

const call = (id: string, input: number) => [{ id, at: 1_700_000_000_000, model: "m", subagent: false, fast: false,
  input, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: 100, window: 1000 },
  { turn: null, person: null, thread: null, profile: "cc" }] as const;
const table = (store: Store, name: string) => store.db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?").get(name);
const write = (store: Store, id: string, input: number) => store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [call(id, input)] as never);
const session = (store: Store) => store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", ws: "A", createdAt: 1, lastActiveAt: 1 });

test("retirement waits for handover, removes the large indexes and keeps recording calls", async () => {
  const store = Store.open(":memory:");
  try {
    session(store);
    write(store, "old", 2);
    let handover!: () => void;
    const fiber = Effect.runFork(retireAfterPrevious(store, new Promise<void>((resolve) => { handover = resolve; })));
    assert.ok(table(store, "usage_detail"));
    write(store, "during", 3);
    handover();
    await Effect.runPromise(Fiber.join(fiber));
    for (const name of ["usage_detail", "usage_detail_lookup", "usage_main_calls"]) assert.equal(table(store, name), undefined, name);
    const triggers = store.db.prepare("SELECT name, sql FROM sqlite_master WHERE type = 'trigger'").all() as { name: string; sql: string }[];
    assert.deepEqual(triggers.filter((t) => /\busage_detail(?:_|\b)|\busage_main_calls\b/.test(t.sql)).map((t) => t.name), []);
    write(store, "new", 4);
    assert.equal((store.db.prepare("SELECT COUNT(*) AS n FROM usage").get() as { n: number }).n, 3);
    assert.deepEqual(store.usageOfSession("a").map((r) => [r.calls, r.input, r.output]), [[3, 9, 3]]);
    assert.equal(store.lastContexts("a", 5).length, 1);
    assert.deepEqual(usageGroups(makeStore(store.db, "."), 0n, 9_223_372_036_854_775_807n, 0n).map((r) => [r.calls, r.input]), [[1, 4]]);
    assert.deepEqual(usageByDay(makeStore(store.db, "."), 0n).map((r) => [r.calls, r.tokens]), [[3, 12]]);
  } finally { store.close(); }
});

test("retirement also removes the separate live index of an incomplete old database", async () => {
  const store = Store.open(":memory:");
  try {
    session(store);
    write(store, "old", 2);
    store.db.exec("UPDATE usage_detail_all SET done = 0 WHERE id = 1");
    installUsageDetail(store.db, 1_700_000_000_001);
    assert.ok(table(store, "usage_detail_live"));
    await Effect.runPromise(retireAfterPrevious(store, Promise.resolve()));
    assert.equal(table(store, "usage_detail_live"), undefined);
    write(store, "new", 4);
    assert.deepEqual(store.usageOfSession("a").map((r) => [r.calls, r.input]), [[2, 6]]);
  } finally { store.close(); }
});

test("the old indexes stop being written even when their cleanup worker cannot start", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-retire-missing-worker-"));
  const store = Store.open(join(dir, "station.db"));
  try {
    session(store);
    write(store, "before", 2);
    const count = () => (store.db.prepare("SELECT COALESCE(SUM(calls), 0) AS n FROM usage_detail").get() as { n: number }).n;
    const before = count();
    let handover!: () => void;
    const fiber = Effect.runFork(retireAfterPrevious(store, new Promise<void>((resolve) => { handover = resolve; }),
      new URL("./no-such-usage-worker.ts", import.meta.url)));
    write(store, "during", 3);
    assert.ok(count() > before, "the previous station can use the indexes until handover");
    const atHandover = count();
    handover();
    await Effect.runPromise(Fiber.join(fiber));
    assert.ok(table(store, "usage_retired_detail"));
    assert.ok(table(store, "usage_compact"), "new statistics start even when cleanup cannot start");
    assert.ok(table(store, "usage_detail"), "the failed worker did not delete the old rows");
    write(store, "after", 4);
    assert.equal(count(), atHandover, "new calls no longer write the old detail");
    assert.deepEqual(store.usageOfSession("a").map((r) => [r.calls, r.input]), [[3, 9]]);
    assert.deepEqual(usageByDay(makeStore(store.db, dir), 0n).map((r) => [r.calls, r.tokens]), [[3, 12]],
      "the previous complete daily totals and the new call are both kept");
  } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("stopping index writers yields to another database writer and retries", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-retire-busy-"));
  const path = join(dir, "station.db");
  const store = Store.open(path);
  const blocker = new DatabaseSync(path);
  try {
    session(store);
    write(store, "before", 2);
    const timeout = (store.db.prepare("PRAGMA busy_timeout").get() as { timeout: number }).timeout;
    let attempts = 0;
    store.db.setAuthorizer((action, operation) => {
      if (action === constants.SQLITE_TRANSACTION && operation === "BEGIN") attempts++;
      return constants.SQLITE_OK;
    });
    blocker.exec("BEGIN IMMEDIATE");
    const fiber = Effect.runFork(retireAfterPrevious(store, Promise.resolve(), new URL("./no-such-usage-worker.ts", import.meta.url)));
    await new Promise<void>((resolve) => setImmediate(resolve));
    assert.ok(attempts > 0, "the stop tried while the other connection held the lock");
    assert.equal(table(store, "usage_retired_detail"), undefined);
    assert.equal((store.db.prepare("PRAGMA busy_timeout").get() as { timeout: number }).timeout, timeout);
    blocker.exec("COMMIT");
    await Effect.runPromise(Fiber.join(fiber));
    assert.ok(table(store, "usage_retired_detail"), "stopping is retried after the lock is released");
    write(store, "after", 3);
    assert.deepEqual(store.usageOfSession("a").map((r) => [r.calls, r.input]), [[2, 5]]);
  } finally { blocker.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a failed compact installation still stops the old index writers", async () => {
  const store = Store.open(":memory:");
  try {
    session(store);
    write(store, "before", 2);
    store.db.setAuthorizer((action, name) =>
      action === constants.SQLITE_CREATE_TABLE && name === "usage_compact" ? constants.SQLITE_DENY : constants.SQLITE_OK);
    await Effect.runPromise(retireAfterPrevious(store, Promise.resolve()));
    store.db.setAuthorizer(null);
    assert.ok(table(store, "usage_retired_detail"));
    assert.equal(table(store, "usage_compact"), undefined);
    assert.equal(table(store, "usage_detail"), undefined, "in-memory cleanup still removes the old index");
    write(store, "after", 3);
    assert.equal((store.db.prepare("SELECT COUNT(*) AS n FROM usage").get() as { n: number }).n, 2);
    assert.deepEqual(store.usageOfSession("a").map((r) => [r.calls, r.input]), [[2, 5]]);
  } finally { store.db.setAuthorizer(null); store.close(); }
});

test("retirement deletes at most one primary-key batch before releasing its write lock", () => {
  const store = Store.open(":memory:");
  try {
    session(store);
    for (let i = 0; i < 100; i++) {
      const [value, owner] = call(`call-${i}`, 1);
      store.recordUsage("/a", { session: "a", offset: i, model: "m" }, "claude",
        [[{ ...value, at: value.at + i * 60_000 }, owner]] as never);
    }
    stopUsageIndexes(store.db);
    const count = () => (store.db.prepare("SELECT COUNT(*) AS n FROM usage_detail").get() as { n: number }).n;
    const before = count();
    assert.ok(before > 256);
    const plan = store.db.prepare(`EXPLAIN QUERY PLAN ${usageIndexBatchSql(store.db, "usage_detail")}`).all(256) as { detail: string }[];
    assert.ok(plan.some((row) => /SEARCH usage_detail USING PRIMARY KEY/.test(row.detail)), JSON.stringify(plan));
    assert.equal(dropUsageIndexStep(store.db), false);
    assert.equal(before - count(), 256);
    assert.ok(table(store, "usage_detail"), "the table remains until its rows are deleted");
    while (table(store, "usage_detail")) dropUsageIndexStep(store.db);
    assert.equal(table(store, "usage_detail"), undefined);
    write(store, "after", 3);
    assert.equal((store.db.prepare("SELECT COUNT(*) AS n FROM usage").get() as { n: number }).n, 101);
  } finally { store.close(); }
});

test("an interrupted retirement resumes in the worker and reopening does not restore the indexes", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-retire-"));
  const path = join(dir, "station.db");
  let store = Store.open(path);
  try {
    session(store);
    write(store, "old", 2);
    stopUsageIndexes(store.db);
    assert.ok(table(store, "usage_detail"));
    write(store, "after-stop", 4);
    store.close();
    store = Store.open(path);
    await Effect.runPromise(retireAfterPrevious(store, Promise.resolve()));
    for (const name of ["usage_detail", "usage_detail_lookup", "usage_main_calls"]) assert.equal(table(store, name), undefined, name);
    store.close();
    store = Store.open(path);
    write(store, "after-reopen", 5);
    assert.equal(table(store, "usage_detail"), undefined);
    assert.equal(table(store, "usage_main_calls"), undefined);
    assert.deepEqual(store.usageOfSession("a").map((r) => [r.calls, r.input]), [[3, 11]]);
  } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
});
