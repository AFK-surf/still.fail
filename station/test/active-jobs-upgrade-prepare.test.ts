import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { installOtherActiveJobs, installRemoteQueueIndex, REMOTE_QUEUE_JOBS } from "../src/store/active-jobs.ts";
import { activeJobUpgradeReady, activeJobUpgradeStep, activeRemoteJobsAvailable, REMOTE_QUEUE_PREPARED } from "../src/store/active-jobs-upgrade.ts";
import { installActiveWatches } from "../src/store/watch-jobs.ts";

const present = (db: DatabaseSync, type: string, name: string) =>
  db.prepare("SELECT 1 FROM sqlite_master WHERE type = ? AND name = ?").get(type, name) !== undefined;
const keys = (db: DatabaseSync, sql: string) => db.prepare(sql).all();
const schema = `CREATE TABLE jobs (id TEXT PRIMARY KEY, session_key TEXT NOT NULL, state TEXT NOT NULL,
  watch INTEGER NOT NULL, token TEXT NOT NULL UNIQUE, started_at INTEGER NOT NULL DEFAULT 1,
  queued INTEGER, screen INTEGER, small INTEGER);
  CREATE INDEX jobs_state ON jobs(state);`;

for (const recursive of [false, true]) test(`old active jobs are published only when their bounded preparation is complete (recursive triggers ${recursive})`, () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}; ${schema}`);
    const add = db.prepare("INSERT INTO jobs (id, session_key, state, watch, token) VALUES (?, ?, 'running', ?, ?)");
    const replace = db.prepare("INSERT OR REPLACE INTO jobs (rowid, id, session_key, state, watch, token) VALUES (?, ?, ?, ?, ?, ?)");
    const change = db.prepare("UPDATE OR REPLACE jobs SET session_key = ?, watch = ?, token = ? WHERE id = ?");
    for (let i = 0; i < 400; i++) add.run(`job-${i}`, `session-${i % 5}`, i % 3 === 0 ? 1 : 0, `token-${i}`);
    installActiveWatches(db);
    installOtherActiveJobs(db);
    installRemoteQueueIndex(db);
    assert.equal(present(db, "table", "active_watch_jobs"), false);
    assert.equal(present(db, "table", "active_other_jobs"), false);
    assert.equal(activeJobUpgradeReady(db), false);
    let batches = 0;
    while (!activeJobUpgradeReady(db)) {
      const result = activeJobUpgradeStep(db, 17);
      assert.ok(result.visited <= 17);
      batches++;
      if (batches === 1) {
        assert.equal(present(db, "table", "active_watch_jobs"), false, "old readers cannot see a partial watch table");
        assert.equal(present(db, "table", "active_other_jobs"), false);
        replace.run(12, "new-on-rowid", "new-session", "running", 1, "new-token");
        replace.run(5000, "new-on-token", "new-session", "running", 0, "token-35");
        change.run("moved", 1, "token-55", "job-200");
        db.prepare("INSERT OR IGNORE INTO jobs (id, session_key, state, watch, token) VALUES ('ignored', 's', 'running', 0, 'token-70')").run();
        db.prepare("DELETE FROM jobs WHERE id = 'job-100'").run();
      }
      assert.ok(batches < 100, "the initial boundary cannot grow with later writes");
    }
    const compare = () => {
      assert.deepEqual(keys(db, "SELECT job, session, token FROM active_watch_jobs ORDER BY job"),
        keys(db, "SELECT id AS job, session_key AS session, token FROM jobs WHERE state = 'running' AND watch <> 0 ORDER BY job"));
      assert.deepEqual(keys(db, "SELECT session, job FROM active_other_jobs ORDER BY session, job"),
        keys(db, "SELECT session_key AS session, id AS job FROM jobs WHERE state = 'running' AND watch = 0 ORDER BY session, job"));
    };
    compare();
    replace.run(14, "after-publication", "after", "running", 0, "after-token");
    change.run("after", 0, "token-72", "job-201");
    compare();
    assert.ok(present(db, "index", "active_watch_jobs_session"));
    assert.ok(present(db, "index", "active_other_remote_jobs"));
  } finally { db.close(); }
});

for (const recursive of [false, true]) test(`an older active table prepares remote queue keys in bounded batches (recursive triggers ${recursive})`, () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}; ${schema}`);
    installActiveWatches(db);
    installOtherActiveJobs(db);
    installRemoteQueueIndex(db);
    const add = db.prepare("INSERT INTO jobs (id, session_key, state, watch, token) VALUES (?, ?, 'running', ?, ?)");
    for (let i = 0; i < 400; i++) add.run(`${i % 30 === 0 ? "remote_" : "local-"}${i}`, `session-${i % 9}`, i % 5 === 0 ? 1 : 0, `token-${i}`);
    db.exec("DROP INDEX active_other_remote_jobs");
    installRemoteQueueIndex(db);
    assert.equal(present(db, "index", "active_other_remote_jobs"), false, "a large table is not indexed under one writer lock");
    let batches = 0;
    while (!activeJobUpgradeReady(db)) {
      const result = activeJobUpgradeStep(db, 19);
      assert.ok(result.visited <= 19);
      batches++;
      if (batches === 1) {
        assert.equal(activeRemoteJobsAvailable(db), false);
        db.prepare("UPDATE jobs SET watch = 0 WHERE id = 'remote_0'").run();
        db.prepare("DELETE FROM jobs WHERE id = 'remote_30'").run();
        add.run("remote_new", "session-0", 0, "token-new");
      }
      assert.ok(batches < 100);
    }
    assert.equal(activeRemoteJobsAvailable(db), true);
    const expected = () => keys(db, `SELECT id, session_key, started_at, queued, screen, small, rowid AS queue_rowid FROM jobs
      WHERE state = 'running' AND id >= 'remote_' AND id < 'remote\`' ORDER BY started_at DESC, rowid`);
    assert.deepEqual(keys(db, REMOTE_QUEUE_PREPARED), expected());
    add.run("remote_after", "session-new", 0, "token-after");
    db.prepare("UPDATE jobs SET watch = 1 WHERE id = 'remote_new'").run();
    assert.deepEqual(keys(db, REMOTE_QUEUE_PREPARED), expected());
    assert.throws(() => db.prepare(REMOTE_QUEUE_JOBS), /no such index/);
  } finally { db.close(); }
});

for (const recursive of [false, true]) test(`active job ownership agrees through interleaved replacements (recursive triggers ${recursive})`, () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}; ${schema}`);
    const insert = db.prepare("INSERT OR REPLACE INTO jobs (rowid, id, session_key, state, watch, token) VALUES (?, ?, ?, ?, ?, ?)");
    const ignored = db.prepare("INSERT OR IGNORE INTO jobs (rowid, id, session_key, state, watch, token) VALUES (?, ?, ?, ?, ?, ?)");
    const change = db.prepare("UPDATE OR REPLACE jobs SET rowid = ?, id = ?, session_key = ?, state = ?, watch = ?, token = ? WHERE rowid = ?");
    const drop = db.prepare("DELETE FROM jobs WHERE rowid = ?");
    for (let i = 0; i < 96; i++) insert.run(i + 1, `old-${i}`, `s${i % 3}`, "running", i % 2, `old-token-${i}`);
    let seed = 0x12345678;
    const next = (n: number) => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % n; };
    const mutate = () => {
      const row = next(120) - 5, id = `j${next(13)}`, session = `s${next(3)}`, state = ["running", "exited", "stopped"][next(3)]!;
      const watch = next(3) - 1, token = `t${next(11)}`;
      switch (next(4)) {
        case 0: drop.run(row); break;
        case 1: ignored.run(row, id, session, state, watch, token); break;
        case 2: change.run(row, id, session, state, watch, token, next(120) - 5); break;
        default: insert.run(row, id, session, state, watch, token);
      }
    };
    const compare = () => {
      assert.deepEqual(keys(db, "SELECT job, session, token FROM active_watch_jobs ORDER BY job"),
        keys(db, "SELECT id AS job, session_key AS session, token FROM jobs WHERE state = 'running' AND watch <> 0 ORDER BY job"));
      assert.deepEqual(keys(db, "SELECT session, job FROM active_other_jobs ORDER BY session, job"),
        keys(db, "SELECT session_key AS session, id AS job FROM jobs WHERE state = 'running' AND watch = 0 ORDER BY session, job"));
    };
    for (let i = 0; !activeJobUpgradeReady(db); i++) {
      assert.ok(i < 100);
      activeJobUpgradeStep(db, 7);
      mutate();
    }
    compare();
    for (let i = 0; i < 400; i++) { mutate(); compare(); }
  } finally { db.close(); }
});

test("vacuum and a failed batch do not lose jobs while the lookup is prepared", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(schema);
    const insert = db.prepare("INSERT INTO jobs (rowid, id, session_key, state, watch, token) VALUES (?, ?, 'mine', 'running', 1, ?)");
    insert.run(100, "a", "a"); insert.run(500, "b", "b"); insert.run(900, "c", "c");
    assert.deepEqual(activeJobUpgradeStep(db, 1), { done: false, visited: 1 });
    db.exec("VACUUM");
    db.exec("CREATE TRIGGER fail_active_job BEFORE INSERT ON active_job_watch_build WHEN NEW.job='b' BEGIN SELECT RAISE(ABORT, 'failed batch'); END");
    const before = keys(db, "SELECT cursor, end_rowid, complete FROM active_job_upgrade");
    assert.throws(() => activeJobUpgradeStep(db, 8), /failed batch/);
    assert.deepEqual(keys(db, "SELECT cursor, end_rowid, complete FROM active_job_upgrade"), before);
    db.exec("DROP TRIGGER fail_active_job");
    while (!activeJobUpgradeReady(db)) activeJobUpgradeStep(db, 1);
    assert.deepEqual(keys(db, "SELECT job, session, token FROM active_watch_jobs ORDER BY job"),
      keys(db, "SELECT id AS job, session_key AS session, token FROM jobs WHERE state='running' ORDER BY job"));
    db.exec("VACUUM");
    assert.deepEqual(keys(db, "SELECT job, session, token FROM active_watch_jobs ORDER BY job"),
      keys(db, "SELECT id AS job, session_key AS session, token FROM jobs WHERE state='running' ORDER BY job"));
  } finally { db.close(); }
});

test("an old writer can still insert a running job without an id during preparation", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(schema);
    const add = db.prepare("INSERT INTO jobs (id, session_key, state, watch, token) VALUES (?, 'mine', 'running', ?, ?)");
    for (let i = 0; i < 70; i++) add.run(`job-${i}`, i % 2, `token-${i}`);
    assert.equal(activeJobUpgradeStep(db, 10).done, false);
    assert.doesNotThrow(() => add.run(null, 1, "missing-id"));
    assert.throws(() => activeJobUpgradeStep(db, 128), /running job without an id/);
    assert.equal(activeJobUpgradeReady(db), false);
    assert.equal(present(db, "table", "active_watch_jobs"), false);
    db.exec("DELETE FROM jobs WHERE id IS NULL");
    while (!activeJobUpgradeReady(db)) activeJobUpgradeStep(db, 10);
    assert.throws(() => add.run(null, 1, "after"));
    assert.equal(db.prepare("SELECT 1 FROM jobs WHERE token='after'").get(), undefined);
  } finally { db.close(); }
});

test("a small old store with a missing job id stays readable until the job is gone", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(`${schema} INSERT INTO jobs (id, session_key, state, watch, token) VALUES (NULL, 'old', 'running', 0, 'missing');`);
    assert.doesNotThrow(() => { installActiveWatches(db); installOtherActiveJobs(db); installRemoteQueueIndex(db); });
    assert.equal(activeJobUpgradeReady(db), false);
    assert.equal(present(db, "table", "active_other_jobs"), false);
    assert.throws(() => activeJobUpgradeStep(db), /running job without an id/);
    db.exec("DELETE FROM jobs WHERE id IS NULL");
    while (!activeJobUpgradeReady(db)) activeJobUpgradeStep(db);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM active_other_jobs").get()!.n, 0);
  } finally { db.close(); }
});
