import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Effect, Fiber } from "effect";
import { makeStore, usageByDay, usageGroups } from "../src/read/store.ts";
import { Store } from "../src/store/store.ts";
import { installUsageDetail } from "../src/store/usage-detail.ts";
import { dropUsageIndexStep, stopUsageIndexes, usageIndexBatchSql } from "../src/store/usage-retire.ts";
import { retireAfterPrevious } from "../src/usage/module.ts";

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
    assert.deepEqual(store.lastContexts("a", 5), []);
    assert.throws(() => usageGroups(makeStore(store.db, "."), 0n, 2_000_000_000_000n, 0n),
      (error: unknown) => (error as { status?: number }).status === 503 && /unavailable/.test((error as Error).message));
    assert.throws(() => usageByDay(makeStore(store.db, "."), 0n), /being indexed|unavailable/);
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
