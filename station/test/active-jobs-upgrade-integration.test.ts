import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { buildWorkspaceActivity } from "../src/sessions/workspace-activity-builder.ts";
import { makeStore, watching } from "../src/read/store.ts";
import { activeJobUpgradeReady, activeJobUpgradeStep, activeRemoteJobsAvailable, REMOTE_QUEUE_PREPARED } from "../src/store/active-jobs-upgrade.ts";
import { Store } from "../src/store/store.ts";

function legacy() {
  const data = mkdtempSync(join(tmpdir(), "active-jobs-upgrade-"));
  const path = join(data, "stillfail.db");
  Store.open(path).close();
  const old = new DatabaseSync(path);
  old.exec(`DROP TRIGGER active_watch_job_add; DROP TRIGGER active_watch_job_change; DROP TRIGGER active_watch_job_drop;
    DROP TRIGGER active_other_job_before_add; DROP TRIGGER active_other_job_add; DROP TRIGGER active_other_job_before_change;
    DROP TRIGGER active_other_job_change; DROP TRIGGER active_other_job_drop;
    DROP TABLE active_watch_jobs; DROP TABLE active_other_jobs; DROP TABLE active_other_replaced;
    INSERT INTO thread_sessions (thread, session, connect, joined_at) VALUES (1, 'mine', 'test', 1);`);
  const insert = old.prepare(`INSERT INTO jobs (id, session_key, name, command, cwd, port, token, state, started_at, log, watch, queued)
    VALUES (?, ?, ?, 'true', '/', ?, ?, ?, ?, '/dev/null', ?, ?)`);
  old.exec("BEGIN");
  for (let i = 0; i < 120; i++) insert.run(`other-${i}`, "other", `other-${i}`, null, `token-${i}`, "running", i, 0, 0);
  insert.run("watch", "mine", "watch", null, "watch-token", "running", 200, 1, 0);
  insert.run("command", "mine", "command", null, "command-token", "running", 201, 0, 0);
  insert.run("remote_queue", "mine", "remote", null, "remote-token", "running", 202, 0, 1);
  insert.run("service", "mine", "service", 5432, "service-token", "running", 203, 0, 0);
  insert.run("restart", "mine", "restart", 5433, "restart-token", "exited", 204, 0, 0);
  old.exec("COMMIT");
  return { data, path, old, insert };
}

function answers(store: Store, db: DatabaseSync, data: string) {
  const watchingMine = db.prepare("SELECT 1 FROM jobs WHERE session_key = 'mine' AND state = 'running' AND watch <> 0 LIMIT 1").get() !== undefined;
  assert.equal(store.hasSessionActiveWatch("mine"), watchingMine);
  assert.equal(store.hasActiveWatch(1), watchingMine);
  assert.equal(watching(makeStore(store.db, data), ["mine"]).has("mine"), watchingMine);
  const count = (db.prepare("SELECT COUNT(*) AS n FROM jobs WHERE session_key = 'mine' AND state = 'running'").get() as { n: number }).n;
  assert.equal(store.runningJobsAtLeast("mine", count), true);
  assert.equal(store.runningJobsAtLeast("mine", count + 1), false);
  const ids = (sql: string) => (db.prepare(sql).all() as { id: string }[]).map((r) => r.id);
  assert.deepEqual(store.runningWaitJobIds("mine"), ids(`SELECT id FROM jobs WHERE session_key = 'mine' AND state = 'running'
    AND (watch <> 0 OR port IS NULL) ORDER BY started_at DESC`));
  assert.deepEqual(store.upJobIds("mine", true), ids(`SELECT id FROM jobs WHERE session_key = 'mine'
    AND (state = 'running' OR (state = 'exited' AND port IS NOT NULL)) ORDER BY started_at DESC`));
  const awake = (db.prepare("SELECT session_key, started_at FROM jobs WHERE state = 'running' AND (watch <> 0 OR port IS NULL)").all() as
    { session_key: string; started_at: number }[]).map((r) => `${r.session_key}:${r.started_at}`).sort();
  assert.deepEqual(store.awakeJobs().map((r) => `${r.sessionKey}:${r.startedAt}`).sort(), awake);
  const queue = ids("SELECT id FROM jobs WHERE id >= 'remote_' AND id < 'remote`' AND state = 'running' ORDER BY started_at DESC, rowid");
  assert.deepEqual(store.remoteQueueJobs().map((r) => r.id), queue);
}

test("old readers and the station answer throughout bounded preparation and an old connection's writes", () => {
  const { data, path, old, insert } = legacy();
  const store = Store.open(path);
  try {
    assert.equal(activeJobUpgradeReady(store.db), false);
    answers(store, old, data);
    assert.equal(activeJobUpgradeStep(store.db, 17).done, false);
    old.prepare("UPDATE jobs SET watch = 0 WHERE id = 'watch'").run();
    insert.run("remote_late", "mine", "late", null, "late-token", "running", 205, 1, 1);
    answers(store, old, data);
    while (!activeJobUpgradeReady(store.db)) activeJobUpgradeStep(store.db, 17);
    answers(store, old, data);
    old.prepare("UPDATE jobs SET watch = 0 WHERE id = 'remote_late'").run();
    answers(store, old, data);
  } finally { store.close(); old.close(); rmSync(data, { recursive: true, force: true }); }
});

test("jobs at the same start time keep their stopping order across publication", () => {
  const { data, path, old, insert } = legacy();
  insert.run("a-command", "mine", "command", null, "tie-command", "running", 500, 0, 0);
  insert.run("z-watch", "mine", "watch", null, "tie-watch-z", "running", 500, 1, 0);
  insert.run("b-watch", "mine", "watch", null, "tie-watch-b", "running", 500, 1, 0);
  insert.run("a-service", "mine", "service", 5000, "tie-service", "running", 500, 0, 0);
  insert.run("z-restart", "mine", "restart", 9000, "tie-restart-z", "exited", 500, 0, 0);
  insert.run("b-restart", "mine", "restart", 2000, "tie-restart-b", "exited", 500, 0, 0);
  const store = Store.open(path);
  try {
    const before = { waits: store.runningWaitJobIds("mine"), up: store.upJobIds("mine", true) };
    while (!activeJobUpgradeReady(store.db)) activeJobUpgradeStep(store.db, 17);
    assert.deepEqual(store.runningWaitJobIds("mine"), before.waits);
    assert.deepEqual(store.upJobIds("mine", true), before.up);
  } finally { store.close(); old.close(); rmSync(data, { recursive: true, force: true }); }
});

test("an interrupted old-store upgrade resumes without exposing its partial lookup", () => {
  const { data, path, old, insert } = legacy();
  let store = Store.open(path);
  try {
    assert.equal(activeJobUpgradeStep(store.db, 17).done, false);
    store.close();
    insert.run("remote_while_down", "mine", "down", null, "down-token", "running", 250, 1, 1);
    store = Store.open(path);
    assert.equal(activeJobUpgradeReady(store.db), false);
    assert.equal(store.db.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name='active_watch_jobs'").get(), undefined);
    answers(store, old, data);
    while (!activeJobUpgradeReady(store.db)) activeJobUpgradeStep(store.db, 17);
    answers(store, old, data);
  } finally { store.close(); old.close(); rmSync(data, { recursive: true, force: true }); }
});

test("preparing old active jobs waits for handover without holding up their answers", async () => {
  const { data, path, old } = legacy();
  const store = Store.open(path);
  const previous = Promise.withResolvers<void>();
  const builder = buildWorkspaceActivity(store, previous.promise);
  try {
    let completed = false;
    void builder.activeJobsReady.then(() => { completed = true; });
    await Promise.resolve();
    assert.equal(completed, false);
    assert.equal(activeJobUpgradeReady(store.db), false);
    answers(store, old, data);
    previous.resolve();
    assert.equal(await builder.activeJobsReady, true);
    assert.equal(activeJobUpgradeReady(store.db), true);
    answers(store, old, data);
  } finally { await builder.close(); store.close(); old.close(); rmSync(data, { recursive: true, force: true }); }
});

test("closing while the previous station is still up settles preparation", async () => {
  const { data, path, old } = legacy();
  const store = Store.open(path);
  const previous = Promise.withResolvers<void>();
  const builder = buildWorkspaceActivity(store, previous.promise);
  try {
    await builder.close();
    assert.equal(await builder.activeJobsReady, false);
    answers(store, old, data);
  } finally { previous.resolve(); store.close(); old.close(); rmSync(data, { recursive: true, force: true }); }
});

test("a prepared remote queue seeks only remote keys and stays prepared after reopening", () => {
  const reads: number[] = [];
  for (const count of [100, 400]) {
    const data = mkdtempSync(join(tmpdir(), "active-remote-upgrade-"));
    const path = join(data, "stillfail.db");
    let store = Store.open(path);
    try {
      const db = store.db;
      db.exec("BEGIN");
      const insert = db.prepare(`INSERT INTO jobs (id, session_key, name, command, cwd, token, state, started_at, log, watch)
        VALUES (?, 's', ?, 'true', '/', ?, 'running', ?, '/dev/null', 0)`);
      for (let i = 0; i < count; i++) insert.run(`local-${i}`, "local", `token-${i}`, i);
      insert.run("remote_one", "remote", "remote-token", count + 1);
      db.exec("COMMIT; DROP INDEX active_other_remote_jobs");
      assert.deepEqual(store.remoteQueueJobs().map((r) => r.id), ["remote_one"]);
      while (!activeJobUpgradeReady(db)) activeJobUpgradeStep(db, 17);
      assert.equal(activeRemoteJobsAvailable(db), true);
      let seen = 0;
      db.function("remote_candidate_seen", () => { seen++; return 1; });
      const observed = new Proxy(db, { get(target, property) {
        if (property === "prepare") return (sql: string) => target.prepare(sql === REMOTE_QUEUE_PREPARED
          ? sql.replace("ON j.id = a.job", "ON j.id = a.job AND remote_candidate_seen()") : sql);
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      } });
      Object.defineProperty(store, "db", { value: observed });
      assert.deepEqual(store.remoteQueueJobs().map((r) => r.id), ["remote_one"]);
      reads.push(seen);
      db.exec("DELETE FROM jobs WHERE id LIKE 'local-%'");
      store.close();
      store = Store.open(path);
      assert.equal(activeRemoteJobsAvailable(store.db), true);
      assert.equal(store.db.prepare("SELECT 1 FROM sqlite_master WHERE type='index' AND name='active_other_remote_jobs'").get(), undefined);
      assert.deepEqual(store.remoteQueueJobs().map((r) => r.id), ["remote_one"]);
    } finally { store.close(); rmSync(data, { recursive: true, force: true }); }
  }
  assert.deepEqual(reads, [1, 1]);
});
