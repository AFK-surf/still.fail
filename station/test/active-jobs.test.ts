import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { OTHER_JOBS_AT_INSTALL, RUNNING_LIMIT, RUNNING_WAIT_JOBS, installOtherActiveJobs } from "../src/store/active-jobs.ts";
import { HAS_ACTIVE_WATCH, installActiveWatches } from "../src/store/watch-jobs.ts";

for (const recursive of [false, true]) test(`the running limit follows watches, ordinary jobs and older writers (recursive triggers ${recursive})`, () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"};
      CREATE TABLE jobs (id TEXT PRIMARY KEY, session_key TEXT NOT NULL, state TEXT NOT NULL, watch INTEGER NOT NULL, token TEXT NOT NULL UNIQUE);
      CREATE INDEX jobs_state ON jobs (state);
      CREATE TABLE thread_sessions (thread INTEGER NOT NULL, session TEXT NOT NULL, PRIMARY KEY (thread, session));
      INSERT INTO thread_sessions VALUES (1, 'a'), (2, 'b');`);
    const add = (id: string, session: string, state: string, watch: number, token = `token-${id}`) =>
      db.prepare("INSERT INTO jobs VALUES (?, ?, ?, ?, ?)").run(id, session, state, watch, token);
    for (let i = 0; i < 200; i++) add(`old-${i}`, "a", "exited", 0);
    add("a-watch", "a", "running", 1);
    add("a-job", "a", "running", 0);
    add("b-job", "b", "running", 0);
    installActiveWatches(db);
    const before = (db.prepare("SELECT total_changes() AS n").get() as { n: number }).n;
    installOtherActiveJobs(db);
    assert.equal((db.prepare("SELECT total_changes() AS n").get() as { n: number }).n - before, 2,
      "upgrade copies only currently running ordinary jobs");
    const plan = (db.prepare(`EXPLAIN QUERY PLAN ${OTHER_JOBS_AT_INSTALL}`).all() as { detail: string }[]).map((r) => r.detail).join(" | ");
    assert.match(plan, /jobs_state \(state=\?\)/);
    const limitPlan = (db.prepare(`EXPLAIN QUERY PLAN ${RUNNING_LIMIT}`).all("a", 19) as { detail: string }[]).map((r) => r.detail).join(" | ");
    assert.match(limitPlan, /active_watch_jobs_session \(session=\?\)/);
    assert.match(limitPlan, /active_other_jobs USING PRIMARY KEY \(session=\?\)/);
    const atLeast = (session: string, count: number) => db.prepare(RUNNING_LIMIT).get(session, count - 1) !== undefined;
    const watching = (thread: number) => db.prepare(HAS_ACTIVE_WATCH).get(thread) !== undefined;
    const assertActive = () => {
      const pairs = (sql: string) => (db.prepare(sql).all() as { session: string; job: string }[]).map((r) => [r.session, r.job]);
      assert.deepEqual(pairs(`SELECT session, job FROM (SELECT session, job FROM active_watch_jobs UNION ALL
        SELECT session, job FROM active_other_jobs) ORDER BY session, job`),
      pairs("SELECT session_key AS session, id AS job FROM jobs WHERE state = 'running' ORDER BY session, job"));
    };
    assert.equal(atLeast("a", 2), true);
    assert.equal(atLeast("a", 3), false);
    assert.equal(watching(1), true);
    assertActive();
    db.prepare("UPDATE jobs SET watch = 1 WHERE id = ?").run("a-job");
    assert.equal(atLeast("a", 2), true, "switching to watch does not count a job twice");
    db.prepare("UPDATE jobs SET watch = 0 WHERE id = ?").run("a-watch");
    assert.equal(atLeast("a", 2), true, "switching from watch keeps it counted");
    db.prepare("UPDATE jobs SET session_key = 'b' WHERE id = ?").run("a-job");
    assert.equal(watching(1), false);
    assert.equal(watching(2), true);
    assert.equal(atLeast("a", 2), false);
    assert.equal(atLeast("b", 2), true);
    db.prepare("INSERT OR IGNORE INTO jobs VALUES (?, ?, ?, ?, ?)").run("ignored", "a", "running", 0, "token-b-job");
    assert.equal(atLeast("b", 2), true);
    db.prepare("UPDATE OR IGNORE jobs SET token = ? WHERE id = ?").run("token-b-job", "a-watch");
    assertActive();
    db.prepare("UPDATE jobs SET state = 'running' WHERE id = ?").run("a-watch");
    assert.equal(atLeast("b", 2), true, "an ignored insert cannot remove a different job on a later update");
    db.prepare("INSERT OR IGNORE INTO jobs VALUES (?, ?, ?, ?, ?)").run("ignored", "a", "running", 0, "token-b-job");
    db.prepare("DELETE FROM jobs WHERE id = ?").run("a-watch");
    assert.equal(atLeast("b", 2), true, "an ignored insert cannot affect a later deletion");
    add("a-watch", "a", "running", 0);
    db.prepare("INSERT OR REPLACE INTO jobs VALUES (?, ?, ?, ?, ?)").run("replace", "a", "exited", 0, "token-b-job");
    assert.equal(atLeast("b", 2), false, "replacing on the unique token removes the displaced job");
    add("overwritten", "b", "running", 0);
    db.prepare("UPDATE OR REPLACE jobs SET token = ? WHERE id = ?").run("token-overwritten", "replace");
    assert.equal(atLeast("b", 2), false, "updating on the unique token removes the displaced job");
    assertActive();
    add("upserted", "b", "running", 0);
    db.prepare(`INSERT INTO jobs VALUES (?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET
      session_key = excluded.session_key, state = excluded.state, watch = excluded.watch, token = excluded.token`)
      .run("upserted", "a", "running", 0, "token-upserted");
    assert.equal(atLeast("a", 2), true, "an upsert moves the existing job once");
    assertActive();
    db.prepare("DELETE FROM jobs WHERE id = ?").run("upserted");
    add("by-id", "d", "running", 0);
    add("by-token", "d", "running", 0);
    db.prepare("INSERT OR REPLACE INTO jobs VALUES (?, ?, ?, ?, ?)").run("by-id", "d", "running", 0, "token-by-token");
    assertActive();
    db.prepare("DELETE FROM jobs WHERE id = ?").run("by-id");
    assertActive();
    for (let i = 0; i < 50; i++) add(`other-${i}`, "b", "running", 0);
    let inspected = 0;
    db.function("inspected_active_job", (_job) => { inspected++; return 1; });
    const measured = RUNNING_LIMIT.replaceAll("WHERE session = ?1", "WHERE session = ?1 AND inspected_active_job(job)");
    assert.ok(db.prepare(measured).get("b", 19));
    assert.equal(inspected, 20, "the limit reads only twenty jobs, even when more exist");
    inspected = 0;
    assert.equal(db.prepare(measured).get("a", 1), undefined);
    assert.equal(inspected, 1, "other sessions' active jobs and completed history are not inspected");
    installOtherActiveJobs(db);
    assert.equal(atLeast("b", 20), true);
  } finally { db.close(); }
});

test("stopping a wait finds only its running watches and commands", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(`CREATE TABLE jobs (id TEXT PRIMARY KEY, session_key TEXT NOT NULL, state TEXT NOT NULL,
      watch INTEGER NOT NULL, token TEXT NOT NULL UNIQUE, port INTEGER, started_at INTEGER NOT NULL);
      CREATE INDEX jobs_state ON jobs (state);`);
    const add = (id: string, session: string, state: string, watch: number, port: number | null, at: number) =>
      db.prepare("INSERT INTO jobs VALUES (?, ?, ?, ?, ?, ?, ?)").run(id, session, state, watch, id, port, at);
    for (let i = 0; i < 200; i++) add(`old-${i}`, "a", "exited", 0, null, i);
    add("watch", "a", "running", 1, null, 10);
    add("command", "a", "running", 0, null, 20);
    add("service", "a", "running", 0, 47123, 30);
    add("other", "b", "running", 1, null, 40);
    installActiveWatches(db);
    installOtherActiveJobs(db);
    const plan = (db.prepare(`EXPLAIN QUERY PLAN ${RUNNING_WAIT_JOBS}`).all("a") as { detail: string }[]).map((r) => r.detail).join(" | ");
    assert.match(plan, /active_watch_jobs_session \(session=\?\)/);
    assert.match(plan, /active_other_jobs USING PRIMARY KEY \(session=\?\)/);
    assert.match(plan, /SEARCH j USING INDEX \S+ \(id=\?\)/);
    let visited = 0;
    db.function("visited_job", (_id) => { visited++; return 1; });
    const measured = RUNNING_WAIT_JOBS.replace("j.id = active.job", "j.id = active.job AND visited_job(j.id)");
    const ids = () => (db.prepare(measured).all("a") as { id: string }[]).map((r) => r.id);
    assert.deepEqual(ids(), ["command", "watch"]);
    assert.equal(visited, 3, "the other session and completed jobs are not visited");
    db.prepare("UPDATE jobs SET state = 'stopped' WHERE id = ?").run("watch");
    visited = 0;
    assert.deepEqual(ids(), ["command"]);
    assert.equal(visited, 2);
  } finally { db.close(); }
});
