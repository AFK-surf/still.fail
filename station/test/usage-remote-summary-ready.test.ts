import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { constants, DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Readers } from "../src/read/pool.ts";
import { outflowUsage } from "../src/read/outflow.ts";
import { makeStore, remoteRunCount, remoteRunsSince } from "../src/read/store.ts";
import { usage as readUsage } from "../src/read/usage.ts";
import { Store } from "../src/store/store.ts";
import { MinuteReader } from "../src/usage/minute-reader.ts";

test("an unfinished remote-task summary does not read task records or report a partial count as complete", () => {
  const store = Store.open(":memory:");
  try {
    store.db.prepare("INSERT INTO remote_runs (job, at, session) VALUES ('old', 10, 'remote:workspace-a:station:chat')").run();
    store.db.prepare("UPDATE remote_run_progress SET done = 0 WHERE id = 1").run();
    store.db.setAuthorizer((action, table) => action === constants.SQLITE_READ && (table === "remote_runs" || table === "usage")
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try {
      assert.throws(() => remoteRunCount(makeStore(store.db, "."), { workspace: "workspace-a", home: false }),
        /remote.*(not ready|pending|being filled)/i);
      assert.throws(() => remoteRunsSince(makeStore(store.db, "."), 0n, { workspace: "workspace-a", home: false }),
        /remote.*(not ready|pending|being filled)/i);
      const result = readUsage(makeStore(store.db, "."), "en", 0n, 100n, 0n, false,
        { workspace: "workspace-a", home: false }, true);
      assert.equal(result.remoteRuns, undefined, "an incomplete task count is not returned as zero");
      assert.equal(result.history, undefined, "the history is omitted while its task count is unavailable");
      assert.deepEqual(result.rows, [], "independent complete usage details remain readable");
    } finally {
      store.db.setAuthorizer(null);
    }
  } finally {
    store.close();
  }
});

test("exporting usage does not wait for or read remote-task statistics it does not return", () => {
  const store = Store.open(":memory:");
  try {
    store.db.exec("UPDATE remote_run_progress SET done = 0 WHERE id = 1");
    store.db.setAuthorizer((action, table) => action === constants.SQLITE_READ &&
      (table === "remote_run_progress" || table === "remote_run_lookup" || table === "remote_runs")
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try {
      const result = outflowUsage(makeStore(store.db, "."), "en", 0, 100, 0, { workspace: "A", home: false });
      assert.deepEqual(result.rows, []);
    } finally {
      store.db.setAuthorizer(null);
    }
  } finally { store.close(); }
});

test("an incomplete remote summary is omitted without holding a reader or rebuilding history", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-remote-ready-"));
  const path = join(dir, "stillfail.db");
  const old = new DatabaseSync(path);
  old.exec(`CREATE TABLE remote_runs (job TEXT PRIMARY KEY, at INTEGER NOT NULL, session TEXT NOT NULL);
    INSERT INTO remote_runs VALUES ('a', 10, 'remote:A:station:a'), ('b', 20, 'remote:B:station:b');`);
  old.close();
  const store = Store.open(path);
  let handover!: () => void;
  const previousGone = new Promise<void>((resolve) => { handover = resolve; });
  const readers = new Readers(dir, 1, undefined, 1, { previousGone });
  const args = { lang: "en", from: 0, to: 100, tz: 0, reading: false, viewer: { workspace: "A", home: false } };
  const before = store.db.prepare("SELECT * FROM remote_run_progress WHERE id = 1").get();
  const usage = readers.read("usage", { ...args, history: true }, "en");
  try {
    await readers.read("checkpoint", {}, "en");
    const result = JSON.parse(await usage);
    assert.equal(result.remoteRuns, undefined);
    assert.equal(result.history, undefined);
    assert.deepEqual(result.rows, []);
    handover();
    assert.deepEqual(store.db.prepare("SELECT * FROM remote_run_progress WHERE id = 1").get(), before);
  } finally {
    handover();
    readers.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("closing a reader rejects remote summary requests waiting for handover", async () => {
  const reader = new MinuteReader("unused", { previousGone: new Promise<void>(() => {}) });
  const waiting = assert.rejects(reader.readyRemote(), /station stopping/);
  await reader.close();
  await waiting;
});

test("ready remote task statistics do not wait for unrelated minute summaries", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-remote-independent-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path);
  store.db.exec("UPDATE usage_minute_all SET done = 0 WHERE id = 1");
  const priority = new SharedArrayBuffer(8);
  Atomics.store(new Int32Array(priority), 0, 1); // The other index cannot take a write permit.
  const reader = new MinuteReader(path, { priority });
  try {
    await reader.readyRemote();
    assert.equal((store.db.prepare("SELECT done FROM usage_minute_all WHERE id = 1").get() as { done: number }).done, 0);
  } finally {
    await reader.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("an incomplete remote summary does not try to fill a missing lookup", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-remote-error-"));
  const path = join(dir, "stillfail.db");
  const old = new DatabaseSync(path);
  old.exec(`CREATE TABLE remote_runs (job TEXT PRIMARY KEY, at INTEGER NOT NULL, session TEXT NOT NULL);
    INSERT INTO remote_runs VALUES ('a', 10, 'remote:A:station:a');`);
  old.close();
  const store = Store.open(path);
  store.db.exec("DROP TABLE remote_run_lookup");
  const reader = new MinuteReader(path);
  try {
    await assert.rejects(reader.readyRemote(), /remote.*unavailable/);
    await assert.rejects(reader.readyRemote(), /remote.*unavailable/);
  } finally {
    await reader.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});
