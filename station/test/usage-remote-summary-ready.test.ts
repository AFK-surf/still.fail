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
      assert.throws(() => readUsage(makeStore(store.db, "."), "en", 0n, 100n, 0n, false,
        { workspace: "workspace-a", home: false }), /remote.*(not ready|pending|being filled)/i,
      "an unready summary is detected before doing the rest of the read");
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

test("a usage read waits for the remote summary without holding a reader or blocking handover", async () => {
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
  const usage = readers.read("usage", args, "en");
  let state = "pending";
  void usage.then(() => { state = "resolved"; }, () => { state = "rejected"; });
  try {
    // The usage read was enqueued first. A checkpoint reaches the sole reader after it returned the pending signal.
    await readers.read("checkpoint", {}, "en");
    assert.equal(state, "pending");
    assert.equal((store.db.prepare("SELECT done FROM remote_run_progress WHERE id = 1").get() as { done: number }).done, 0,
      "the backfill does not start before the previous station is gone");
    handover();
    const result = JSON.parse(await usage);
    assert.deepEqual(result.remoteRuns, [{ at: 10, session: "remote:A:station:a" }]);
    assert.equal((store.db.prepare("SELECT done FROM remote_run_progress WHERE id = 1").get() as { done: number }).done, 1);
    const history = JSON.parse(await readers.read("usage", { ...args, history: true }, "en"));
    assert.equal(history.history.remoteRuns, 1);
  } finally {
    handover();
    readers.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("closing a reader rejects remote summary requests waiting for handover", async () => {
  const reader = new MinuteReader("unused", { previousGone: new Promise<void>(() => {}) });
  const waiting = reader.readyRemote();
  await reader.close();
  await assert.rejects(waiting, /station stopping/);
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

test("a failed remote summary reports the error to current and later readers", async () => {
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
    await assert.rejects(reader.readyRemote(), /no such table: remote_run_lookup/);
    await assert.rejects(reader.readyRemote(), /no such table: remote_run_lookup/);
  } finally {
    await reader.close();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});
