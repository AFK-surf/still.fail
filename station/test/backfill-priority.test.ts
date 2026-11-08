import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { syncBuiltinESMExports } from "node:module";
import { test } from "node:test";
import workerThreads from "node:worker_threads";
import { Store } from "../src/store/store.ts";
import { giveBackfill, releaseStoppedBackfill, takeBackfill } from "../src/store/backfill.ts";
import { MinuteReader } from "../src/usage/minute-reader.ts";
import { previousExited } from "../src/ops/previous.ts";

test("the station marks its writes as pending until they finish, including failures", () => {
  const store = Store.open(":memory:");
  try {
    const buffer = (store as any).backfillPriority;
    assert.ok(buffer instanceof SharedArrayBuffer);
    const priority = new Int32Array(buffer);
    store.db.exec("CREATE TABLE foreground_probe (value INTEGER)");
    store.db.function("priority_seen", () => Atomics.load(priority, 0));
    store.db.prepare("INSERT INTO foreground_probe VALUES (priority_seen())").run();
    store.db.exec("INSERT INTO foreground_probe VALUES (priority_seen())");
    assert.deepEqual(store.db.prepare("SELECT value FROM foreground_probe").all().map((r: any) => r.value), [1, 1]);
    assert.equal(Atomics.load(priority, 0), 0);
    store.db.exec("CREATE UNIQUE INDEX foreground_once ON foreground_probe (value) WHERE value = 2");
    store.db.prepare("INSERT INTO foreground_probe VALUES (2)").run();
    assert.throws(() => store.db.prepare("INSERT INTO foreground_probe VALUES (2)").run());
    assert.equal(Atomics.load(priority, 0), 0);
  } finally { store.close(); }
});

test("a read-only coverage check does not wait for the previous process", async () => {
  const original = workerThreads.Worker;
  const workers: FakeWorker[] = [];
  class FakeWorker extends EventEmitter {
    posts: any[] = [];
    constructor() { super(); workers.push(this); }
    unref() { return this; }
    postMessage(message: any) { this.posts.push(message); }
    terminate() { return Promise.resolve(0); }
  }
  let finish!: () => void;
  const previousGone = new Promise<void>((resolve) => { finish = resolve; });
  (workerThreads as any).Worker = FakeWorker;
  syncBuiltinESMExports();
  const reader = new (MinuteReader as any)("unused", { previousGone }, null);
  try {
    const ready = reader.ready(null);
    await Promise.resolve();
    assert.equal(workers.length, 1, "the read-only worker can start before handover ends");
    assert.equal(workers[0]!.posts.length, 1, "a page requested during handover is sent once");
    workers[0]!.emit("message", { id: workers[0]!.posts[0].id });
    await ready;
    finish();

    let finishOther!: () => void;
    const otherHandover = new Promise<void>((resolve) => { finishOther = resolve; });
    const stopping = new (MinuteReader as any)("unused", { previousGone: otherHandover }, null);
    const waiting = assert.rejects(stopping.ready(null), /station stopping/);
    await stopping.close();
    await waiting;
    finishOther();
    await Promise.resolve();
    assert.equal(workers.length, 2, "a stopped station does not start another worker when handover later ends");
  } finally {
    await reader.close();
    (workerThreads as any).Worker = original;
    syncBuiltinESMExports();
  }
});

test("only the stopped worker's backfill permit is released", () => {
  const priority = new Int32Array(new SharedArrayBuffer(8));
  assert.equal(takeBackfill(priority, 1), true);
  assert.equal(takeBackfill(priority, 2), false);
  releaseStoppedBackfill(priority.buffer as SharedArrayBuffer, 2);
  assert.equal(takeBackfill(priority, 2), false);
  releaseStoppedBackfill(priority.buffer as SharedArrayBuffer, 1);
  assert.equal(takeBackfill(priority, 2), true);
  giveBackfill(priority, 2);
  Atomics.store(priority, 0, 1);
  assert.equal(takeBackfill(priority, 1), false, "a queued foreground write takes priority");
});

test("backfills wait for the old process even after session takeover times out", async () => {
  let alive = true;
  let wake!: () => void;
  const exited = previousExited({ pid: 123, gone: Promise.resolve() }, () => alive, () => new Promise<void>((resolve) => { wake = resolve; }));
  await Promise.resolve();
  assert.equal(typeof wake, "function", "the old process is still checked after takeover is allowed");
  alive = false;
  wake();
  await exited;
});
