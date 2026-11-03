import assert from "node:assert/strict";
import { once } from "node:events";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Worker } from "node:worker_threads";
import { makeStore, remoteRunCount, remoteRunsSince } from "../src/read/store.ts";
import { backfillRemoteRuns, DELETE_EXPIRED_REMOTE_RUNS, installRemoteRuns, REMOTE_RUNS_OF } from "../src/store/remote-runs.ts";
import { Store } from "../src/store/store.ts";

test("old remote tasks fill in bounded batches and survive concurrent old writes and a restart", () => {
  const dir = mkdtempSync(join(tmpdir(), "remote-runs-"));
  const path = join(dir, "stillfail.db");
  const before = new DatabaseSync(path);
  before.exec("CREATE TABLE remote_runs (job TEXT PRIMARY KEY, at INTEGER NOT NULL, session TEXT NOT NULL)");
  const old = before.prepare("INSERT INTO remote_runs VALUES (?, ?, ?)");
  for (let i = 0; i < 70; i++) old.run(`old-${i}`, i + 10, `remote:${i % 2 ? "B" : "A"}:station:chat`);
  before.close();
  let store = Store.open(path);
  try {
    assert.throws(() => remoteRunCount(makeStore(store.db, dir), { workspace: "A", home: false }), /remote task statistics are still being filled/);
    assert.deepEqual(backfillRemoteRuns(store.db, 5), { done: false, processed: 5 });
    const later = 91 * 24 * 60 * 60 * 1_000;
    store.noteRemoteRun("later", "remote:A:station:later", later);

    // An old station can insert and edit rows while this one is filling. Reuse a rowid inside the saved range after the
    // cleanup: this new, earlier-dated row must survive just as it would in the old table.
    store.db.prepare("DELETE FROM remote_runs WHERE job = ?").run("old-49");
    store.db.prepare("INSERT INTO remote_runs (rowid, job, at, session) VALUES (50, 'late', 2, 'remote:B:station:late')").run();
    store.db.prepare("UPDATE remote_runs SET session = 'remote:B:station:moved' WHERE job = 'old-10'").run();
    assert.throws(() => remoteRunsSince(makeStore(store.db, dir), 0n, { workspace: "B", home: false }), /remote task statistics are still being filled/);
    store.close();
    store = Store.open(path);

    let step: { done: boolean; processed: number };
    do {
      step = backfillRemoteRuns(store.db, 5);
      assert.ok(step.processed <= 5);
    } while (!step.done);
    const reader = makeStore(store.db, dir);
    assert.deepEqual(remoteRunsSince(reader, 0n), [
      { at: 2, session: "remote:B:station:late" },
      { at: later, session: "remote:A:station:later" },
    ]);
    assert.equal(remoteRunCount(reader, { workspace: "A", home: false }), 1);
    assert.equal(remoteRunCount(reader, { workspace: "B", home: false }), 1);
    assert.equal(remoteRunCount(reader, null), 2);
    assert.equal((store.db.prepare("SELECT COUNT(*) AS n FROM remote_runs").get() as { n: number }).n, 2);
  } finally {
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("remote task indexes follow writes, edits, deletes and the existing ninety-day cleanup", () => {
  const store = Store.open(":memory:");
  try {
    const db = store.db;
    const add = db.prepare("INSERT INTO remote_runs VALUES (?, ?, ?)");
    add.run("a", 10, "remote:A:station:a");
    add.run("b", 10, "remote:B:station:b");
    add.run("negative", -1, "remote:A:station:old");
    add.run("unusual", 20, "without-colons");
    db.prepare("UPDATE remote_runs SET session = 'remote:A:station:moved' WHERE job = 'b'").run();
    db.prepare("DELETE FROM remote_runs WHERE job = 'a'").run();
    const reader = makeStore(db, ".");
    assert.deepEqual(remoteRunsSince(reader, 0n, { workspace: "A", home: true }), [{ at: 10, session: "remote:A:station:moved" }]);
    assert.equal(remoteRunCount(reader, { workspace: "A", home: true }), 1);
    assert.equal(remoteRunCount(reader, { workspace: "B", home: false }), 0);
    assert.equal(remoteRunCount(reader, null), 2);
    assert.deepEqual(remoteRunsSince(reader, 0n, { workspace: "", home: false }), [{ at: 20, session: "without-colons" }]);
    db.prepare("INSERT OR REPLACE INTO remote_runs VALUES (?, ?, ?)").run("b", 30, "remote:B:station:replacement");
    assert.equal(remoteRunCount(reader, { workspace: "A", home: false }), 0);
    assert.equal(remoteRunCount(reader, { workspace: "B", home: false }), 1);
    assert.equal(remoteRunCount(reader, null), 2, "replacing a job does not leave its old indexed copy");

    const plan = (db.prepare(`EXPLAIN QUERY PLAN ${REMOTE_RUNS_OF}`).all("A", 0) as { detail: string }[]).map((r) => r.detail).join(" | ");
    assert.match(plan, /PRIMARY KEY \(ws=\? AND at>\?\)/);
    const expiry = (db.prepare(`EXPLAIN QUERY PLAN ${DELETE_EXPIRED_REMOTE_RUNS}`).all(1) as { detail: string }[]).map((r) => r.detail).join(" | ");
    assert.match(expiry, /remote_run_by_time USING PRIMARY KEY \(at<\?\)/);
    store.noteRemoteRun("later", "remote:A:station:later", 91 * 24 * 60 * 60 * 1_000);
    assert.equal(remoteRunCount(reader, null), 1);
    assert.deepEqual(remoteRunsSince(reader, 0n).map((r) => r.session), ["remote:A:station:later"]);
  } finally {
    store.close();
  }
});

test("a partial remote task index converges after old rows change and new rows arrive", () => {
  const db = new DatabaseSync(":memory:");
  db.exec("CREATE TABLE remote_runs (job TEXT PRIMARY KEY, at INTEGER NOT NULL, session TEXT NOT NULL)");
  const add = db.prepare("INSERT INTO remote_runs VALUES (?, ?, ?)");
  db.exec("INSERT INTO remote_runs (rowid, job, at, session) VALUES (-2, 'negative-rowid', 0, 'remote:A:station:first')");
  for (let i = 0; i < 10; i++) add.run(`old-${i}`, i % 2, `remote:${i % 2 ? "B" : "A"}:station:${i}`);
  try {
    // Install on the same connection an older station could continue to use.
    installRemoteRuns(db);
    backfillRemoteRuns(db, 2);
    db.prepare("UPDATE remote_runs SET session = 'remote:B:station:moved', at = 4 WHERE job = 'old-8'").run();
    db.prepare("DELETE FROM remote_runs WHERE job = 'old-6'").run();
    add.run("new", 0, "remote:A:station:new");
    while (!backfillRemoteRuns(db, 2).done) {}
    const reader = makeStore(db, ".");
    for (const ws of ["A", "B"]) {
      const expected = (db.prepare("SELECT at, session FROM remote_runs WHERE at >= 0 ORDER BY at, rowid").all() as { at: number; session: string }[])
        .filter((r) => r.session.split(":")[1] === ws).map((r) => ({ at: r.at, session: r.session }));
      assert.deepEqual(remoteRunsSince(reader, 0n, { workspace: ws, home: false }), expected);
      assert.equal(remoteRunCount(reader, { workspace: ws, home: false }), expected.length);
    }
  } finally { db.close(); }
});

test("the existing background reader finishes old remote tasks even when minutes are already ready", async () => {
  const dir = mkdtempSync(join(tmpdir(), "remote-runs-worker-"));
  const path = join(dir, "stillfail.db");
  const old = new DatabaseSync(path);
  old.exec(`CREATE TABLE remote_runs (job TEXT PRIMARY KEY, at INTEGER NOT NULL, session TEXT NOT NULL);
    INSERT INTO remote_runs VALUES ('a', 10, 'remote:A:station:a');`);
  old.close();
  const store = Store.open(path);
  const priority = new SharedArrayBuffer(8);
  Atomics.store(new Int32Array(priority), 0, 1);
  const worker = new Worker(new URL("../src/usage/minute-worker.ts", import.meta.url), { workerData: { path, priority } });
  try {
    const [waiting] = await once(worker, "message");
    assert.equal(waiting.foreground, true, "the background batch gives a waiting foreground writer priority");
    worker.postMessage({ id: 1, viewer: { workspace: "A", home: false } });
    const [ready] = await once(worker, "message");
    assert.equal(ready.id, 1, "a ready minute history can be read while remote tasks wait to be indexed");
    assert.equal((store.db.prepare("SELECT done FROM remote_run_progress WHERE id = 1").get() as { done: number }).done, 0);
    assert.throws(() => remoteRunCount(makeStore(store.db, dir), { workspace: "A", home: false }), /remote task statistics are still being filled/);
    Atomics.store(new Int32Array(priority), 0, 0);
    const [message] = await once(worker, "message");
    assert.deepEqual(message, { complete: true });
    assert.equal((store.db.prepare("SELECT done FROM remote_run_progress WHERE id = 1").get() as { done: number }).done, 1);
    assert.equal(remoteRunCount(makeStore(store.db, dir), { workspace: "A", home: false }), 1);
  } finally {
    await worker.terminate();
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});
