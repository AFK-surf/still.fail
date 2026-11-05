import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Jobs } from "../src/jobs/jobs.ts";
import { REMOTE_QUEUE_JOBS, installRemoteQueueIndex } from "../src/store/active-jobs.ts";
import { JOBS_RUNNING, Store, type JobRow } from "../src/store/store.ts";

const queueFields = (j: JobRow) => ({
  id: j.id, sessionKey: j.sessionKey, startedAt: j.startedAt,
  ...(j.queued === true ? { queued: true } : {}), ...(j.screen === true ? { screen: true } : {}),
  ...(j.small === true ? { small: true } : {}),
});

test("a remote task's queue position does not read unrelated running jobs", async () => {
  const reads: { all: number; queue: number }[] = [];
  for (const unrelated of [40, 400]) {
    const data = mkdtempSync(join(tmpdir(), "queue-bounded-"));
    const store = Store.open(":memory:");
    const db = store.db;
    let seen = 0, candidates = 0;
    db.function("queue_job_seen", () => { seen++; return 1; });
    db.function("queue_candidate_seen", () => { candidates++; return 1; });
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => target.prepare(sql === JOBS_RUNNING
        ? sql.replace("WHERE state = 'running'", "WHERE state = 'running' AND queue_job_seen()")
        : sql === REMOTE_QUEUE_JOBS ? sql.replaceAll("ON j.id = w.job", "ON j.id = w.job AND queue_candidate_seen()")
          .replaceAll("ON j.id = a.job", "ON j.id = a.job AND queue_candidate_seen()") : sql);
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const jobs = new Jobs({ store, data, notify: () => {}, link: () => null });
    try {
      const add = (id: string, watch: boolean, queued = false) => store.insertJob({ id, sessionKey: id, name: id,
        command: "true", cwd: "/", port: null, token: id, state: "running", pgid: null, exitCode: null,
        startedAt: queued ? 20 : 10, endedAt: null, restarts: 0, log: "/dev/null", watch, queued });
      for (let i = 0; i < unrelated; i++) add(`local-${i}`, i % 2 === 0);
      add("remote_running", true);
      add("remote_waiting", false, true);
      Object.defineProperty(store, "db", { value: observed });
      assert.equal(jobs.queueOf("remote_waiting")?.place, 1);
      reads.push({ all: seen, queue: candidates });
    } finally {
      await jobs.shutdown();
      store.close();
      rmSync(data, { recursive: true, force: true });
    }
  }
  assert.deepEqual(reads, [{ all: 0, queue: 2 }, { all: 0, queue: 2 }]);
});

for (const recursive of [false, true]) test(`remote queue lookup follows old writes and preserves order (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:");
  try {
    const db = store.db;
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}; DROP INDEX active_other_remote_jobs`);
    const add = (id: string, watch: boolean, state = "running", at = 1, token = id) => store.insertJob({ id, sessionKey: id,
      name: id, command: "true", cwd: "/", port: null, token, state, pgid: null, exitCode: null, startedAt: at,
      endedAt: null, restarts: 0, log: "/dev/null", watch });
    for (const id of ["remote_z", "local", "remote_", "remote_雪", "remote_a", "remote`outside", "remote-"]) add(id, id === "remote_a");
    add("remote_old", false, "exited");
    const oldWrite = db.prepare("UPDATE jobs SET state = ?, watch = ?, session_key = ? WHERE id = ?");
    const oldReplace = db.prepare(`INSERT OR REPLACE INTO jobs
      (id, session_key, name, command, cwd, token, state, started_at, log, watch) VALUES (?, ?, ?, 'true', '/', ?, ?, ?, '/dev/null', ?)`);
    installRemoteQueueIndex(db);
    const compare = () => assert.deepEqual(store.remoteQueueJobs(), store.jobsRunning().filter((job) => job.id.startsWith("remote_")).map(queueFields));
    compare();
    oldWrite.run("running", 1, "moved", "remote_old");
    oldWrite.run("running", 0, "another", "remote_a");
    compare();
    oldReplace.run("remote_replacement", "session", "replacement", "remote_z", "running", 1, 0);
    compare();
    db.prepare("INSERT OR IGNORE INTO jobs (id, session_key, name, command, cwd, token, state, started_at, log, watch) VALUES (?, ?, ?, 'true', '/', ?, 'running', 1, '/dev/null', 0)")
      .run("remote_ignored", "session", "ignored", "remote_z");
    compare();
    db.prepare("UPDATE jobs SET id = 'local-moved' WHERE id = 'remote_a'").run();
    db.prepare("UPDATE jobs SET id = 'remote_from_local' WHERE id = 'local'").run();
    db.prepare("DELETE FROM jobs WHERE id = 'remote_old'").run();
    compare();
    const plan = (db.prepare(`EXPLAIN QUERY PLAN ${REMOTE_QUEUE_JOBS}`).all() as { detail: string }[]).map((r) => r.detail).join(" | ");
    assert.match(plan, /SEARCH w USING PRIMARY KEY \(job>\? AND job<\?\)/);
    assert.match(plan, /SEARCH a USING COVERING INDEX active_other_remote_jobs \(job>\? AND job<\?\)/);
    assert.match(plan, /SEARCH j USING INDEX \S+ \(id=\?\)/);
  } finally { store.close(); }
});

for (const recursive of [false, true]) test(`remote queue lookup agrees with changing jobs (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:");
  try {
    const db = store.db;
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    const insert = db.prepare(`INSERT OR REPLACE INTO jobs
      (id, session_key, name, command, cwd, token, state, started_at, log, watch, queued, screen, small)
      VALUES (?, ?, ?, 'true', '/', ?, ?, ?, '/dev/null', ?, ?, ?, ?)`);
    const update = db.prepare("UPDATE OR REPLACE jobs SET token=?, state=?, watch=?, started_at=?, session_key=?, queued=?, screen=?, small=? WHERE id=?");
    const del = db.prepare("DELETE FROM jobs WHERE id=?");
    const ids = ["remote_", "remote_a", "remote_b", "remote_雪", "remote`other", "local_a", "local_b"];
    let seed = 0x3571;
    const rand = (n: number) => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % n; };
    const check = () => assert.deepEqual(store.remoteQueueJobs(), store.jobsRunning().filter((job) => job.id.startsWith("remote_")).map(queueFields));
    for (let i = 0; i < 400; i++) {
      const id = ids[rand(ids.length)]!, token = `token-${rand(5)}`, state = rand(3) ? "running" : "exited";
      const watch = rand(3) - 1, at = rand(3), session = `s${rand(4)}`, queued = rand(3), screen = rand(3), small = rand(3);
      const rollback = i % 17 === 0;
      if (rollback) db.exec("BEGIN");
      switch (rand(3)) {
        case 0: insert.run(id, session, id, token, state, at, watch, queued, screen, small); break;
        case 1: update.run(token, state, watch, at, session, queued, screen, small, id); break;
        default: del.run(id);
      }
      check();
      if (rollback) { db.exec("ROLLBACK"); check(); }
    }
  } finally { store.close(); }
});

test("a previous connection's prepared writes maintain the new remote queue index", () => {
  const data = mkdtempSync(join(tmpdir(), "queue-old-writer-"));
  const store = Store.open(join(data, "store.db"));
  const old = new DatabaseSync(join(data, "store.db"));
  try {
    store.db.exec("DROP INDEX active_other_remote_jobs");
    const insert = old.prepare(`INSERT INTO jobs (id, session_key, name, command, cwd, token, state, started_at, log, watch)
      VALUES (?, 's', ?, 'true', '/', ?, 'running', 1, '/dev/null', ?)`);
    const change = old.prepare("UPDATE jobs SET state=?, watch=? WHERE id=?");
    installRemoteQueueIndex(store.db);
    insert.run("remote_old", "old", "old", 0);
    insert.run("local_old", "local", "local", 0);
    assert.deepEqual(store.remoteQueueJobs().map((j) => j.id), ["remote_old"]);
    change.run("running", 1, "remote_old");
    assert.deepEqual(store.remoteQueueJobs().map((j) => j.id), ["remote_old"]);
    change.run("exited", 1, "remote_old");
    assert.deepEqual(store.remoteQueueJobs(), []);
  } finally { old.close(); store.close(); rmSync(data, { recursive: true, force: true }); }
});
