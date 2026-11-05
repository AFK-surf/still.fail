import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync, constants } from "node:sqlite";
import { test } from "node:test";
import { installSessionUpJobs, sessionUpJobsReady, sessionUpJobsStep } from "../src/store/session-up-jobs.ts";
import { Store } from "../src/store/store.ts";

function dropIndex(store: Store) {
  const db = store.db;
  for (const row of db.prepare("SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'session_up_job_%'").all() as { name: string }[])
    db.exec(`DROP TRIGGER ${row.name}`);
  db.exec("DROP TABLE session_up_job_rows; DROP TABLE session_up_job_replaced; DROP TABLE session_up_job_scopes; DROP TABLE session_up_job_meta");
}

function check(store: Store) {
  const db = store.db;
  const expected = db.prepare(`SELECT session_key AS session, CAST(rowid AS TEXT) AS position FROM jobs
    WHERE state='running' OR (state='exited' AND port IS NOT NULL) ORDER BY session_key, rowid`).all();
  const actual = db.prepare("SELECT session, CAST(job_rowid AS TEXT) AS position FROM session_up_job_rows ORDER BY session, job_rowid").all();
  assert.deepEqual(actual, expected);
  for (const key of ["one", "two", "three", "absent"]) {
    assert.equal(store.sessionHasUpJob(key), expected.some((row) => row.session === key));
    const ids = db.prepare(`SELECT id FROM jobs WHERE session_key=? AND
      (state='running' OR (state='exited' AND port IS NOT NULL)) ORDER BY started_at DESC`).all(key).map((row) => row.id);
    assert.deepEqual(store.upJobIds(key), ids);
  }
}

for (const recursive of [false, true]) test(`session up jobs follow mixed replacements (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:"), reference = Store.open(":memory:");
  const db = store.db;
  try {
    for (const d of [db, reference.db]) d.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    dropIndex(reference);
    const statements = (d: typeof db) => ({
      put: d.prepare(`INSERT OR REPLACE INTO jobs(rowid,id,token,session_key,state,port,name,command,cwd,started_at,log)
        VALUES(?,?,?,?,?,?, '', '', '', ?, '')`),
      change: d.prepare("UPDATE OR REPLACE jobs SET rowid=?,id=?,token=?,session_key=?,state=?,port=?,started_at=? WHERE rowid=?"),
      drop: d.prepare("DELETE FROM jobs WHERE rowid=?"),
    });
    const actual = statements(db), before = statements(reference.db);
    const rows = (d: typeof db) => d.prepare("SELECT rowid,id,token,session_key,state,port,started_at FROM jobs ORDER BY rowid").all();
    let seed = 0x12345678;
    const next = (n: number) => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % n; };
    for (let i = 0; i < 400; i++) {
      const rowid = next(25) - 5, id = `j${next(13)}`, token = `t${next(11)}`, session = ["one", "two", "three"][next(3)]!;
      const state = ["running", "exited", "stopped"][next(3)]!, port = next(3) === 0 ? 9000 + next(10) : null;
      const method = i % 6 === 0 ? "drop" : i % 6 === 1 ? "change" : "put";
      const args = method === "drop" ? [rowid] : method === "change"
        ? [rowid, id, token, session, state, port, i, next(25) - 5] : [rowid, id, token, session, state, port, i];
      const run = (ops: ReturnType<typeof statements>) => {
        try { ops[method].run(...args); return null; }
        catch (error) { return (error as { errcode?: number }).errcode; }
      };
      assert.equal(run(actual), run(before), `conflict policy at operation ${i}`);
      assert.deepEqual(rows(db), rows(reference.db), `jobs at operation ${i}`);
      check(store);
    }
  } finally { store.close(); reference.close(); }
});

for (const recursive of [false, true]) for (const alias of ["rowid", "_rowid_", "oid"]) {
  test(`replacing an up job by ${alias} keeps both sessions exact (recursive triggers ${recursive})`, () => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
      db.exec(`INSERT INTO jobs(rowid,id,token,session_key,state,port,name,command,cwd,started_at,log)
        VALUES(1,'a','ta','one','running',NULL,'','','',1,''),
          (2,'b','tb','two','exited',9000,'','','',2,''),
          (3,'c','tc','one','stopped',NULL,'','','',3,'')`);
      db.exec(`UPDATE OR REPLACE jobs SET ${alias}=2,session_key='three' WHERE rowid=1`);
      check(store);
      db.exec(`INSERT OR REPLACE INTO jobs(${alias},id,token,session_key,state,name,command,cwd,started_at,log)
        VALUES(3,'d','td','two','running','','','',4,'')`);
      check(store);
      db.exec(`INSERT OR IGNORE INTO jobs(${alias},id,token,session_key,state,name,command,cwd,started_at,log)
        VALUES(4,'a','te','one','running','','','',5,'')`);
      check(store);
      db.exec("UPDATE jobs SET state='stopped' WHERE id='d'");
      check(store);
    } finally { store.close(); }
  });
}

test("old jobs are prepared within each session while jobs change", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    dropIndex(store);
    const put = db.prepare(`INSERT INTO jobs(id,token,session_key,state,port,name,command,cwd,started_at,log)
      VALUES(?,?,?, ?,?, '', '', '', ?, '')`);
    for (let i = 0; i < 9; i++) put.run(`old-${i}`, `old-${i}`, i < 6 ? "one" : "two", i % 2 ? "running" : "exited", i % 2 ? null : 8000, i);
    installSessionUpJobs(db);
    assert.equal(sessionUpJobsReady(db, "one"), false);
    assert.equal(store.sessionHasUpJob("one"), null);
    assert.deepEqual(sessionUpJobsStep(db, "one", 2), { done: false, visited: 2 });
    db.exec("UPDATE jobs SET rowid=-30,session_key='one' WHERE id='old-4'");
    db.exec("UPDATE jobs SET rowid=1000,session_key='two' WHERE id='old-1'");
    db.exec("DELETE FROM jobs WHERE id='old-5'");
    let steps = 0;
    while (!sessionUpJobsReady(db, "one")) {
      put.run(`new-${steps}`, `new-${steps}`, "other", "running", null, 100 + steps);
      put.run(`new-one-${steps}`, `new-one-${steps}`, "one", "running", null, 200 + steps);
      assert.ok(sessionUpJobsStep(db, "one", 2).visited <= 2);
      assert.ok(++steps < 10);
    }
    while (!sessionUpJobsReady(db, "two")) sessionUpJobsStep(db, "two", 2);
    while (!sessionUpJobsReady(db, "three")) sessionUpJobsStep(db, "three", 2);
    while (!sessionUpJobsReady(db, "absent")) sessionUpJobsStep(db, "absent", 2);
    check(store);
  } finally { store.close(); }
});

test("another connection's old writes stay exact during and after session preparation", () => {
  const dir = mkdtempSync(join(tmpdir(), "session-up-jobs-writers-")), path = join(dir, "station.db");
  const store = Store.open(path), db = store.db;
  const old = new DatabaseSync(path);
  try {
    dropIndex(store);
    db.exec(`INSERT INTO jobs(id,token,session_key,state,name,command,cwd,started_at,log)
      VALUES('a','a','one','running','','','',1,''),('b','b','one','stopped','','','',2,'')`);
    installSessionUpJobs(db);
    assert.deepEqual(sessionUpJobsStep(db, "one", 1), { done: false, visited: 1 });
    old.exec("UPDATE jobs SET state='running' WHERE id='b'; UPDATE jobs SET rowid=-30 WHERE id='a'");
    while (!sessionUpJobsReady(db, "one")) sessionUpJobsStep(db, "one", 1);
    assert.deepEqual(store.upJobIds("one"), ["b", "a"]);
    old.exec("DELETE FROM jobs WHERE id='b'");
    assert.deepEqual(store.upJobIds("one"), ["a"]);
  } finally { old.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a failed version marker leaves no partially installed job lookup", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    dropIndex(store);
    db.setAuthorizer((action, name) => action === constants.SQLITE_INSERT && name === "session_up_job_meta"
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    assert.throws(() => installSessionUpJobs(db));
    db.setAuthorizer(null);
    assert.equal(db.prepare("SELECT 1 FROM sqlite_master WHERE name='session_up_job_meta'").get(), undefined);
    installSessionUpJobs(db);
    assert.equal(sessionUpJobsReady(db, "one"), true);
  } finally { db.setAuthorizer(null); store.close(); }
});

test("a job staying up does not rewrite its session lookup", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.exec(`INSERT INTO jobs(id,token,session_key,state,name,command,cwd,started_at,log)
      VALUES('a','a','one','running','','','',1,'');
      CREATE TEMP TABLE up_job_writes (n INTEGER);
      CREATE TEMP TRIGGER up_row_added AFTER INSERT ON main.session_up_job_rows BEGIN INSERT INTO up_job_writes VALUES(1); END;
      CREATE TEMP TRIGGER up_row_removed AFTER DELETE ON main.session_up_job_rows BEGIN INSERT INTO up_job_writes VALUES(1); END;
      CREATE TEMP TRIGGER up_stage_added AFTER INSERT ON main.session_up_job_replaced BEGIN INSERT INTO up_job_writes VALUES(1); END;
      CREATE TEMP TRIGGER up_stage_removed AFTER DELETE ON main.session_up_job_replaced BEGIN INSERT INTO up_job_writes VALUES(1); END;
      UPDATE jobs SET state='exited',port=9000 WHERE id='a';
      UPDATE jobs SET port=9001 WHERE id='a';
      UPDATE jobs SET state='running',port=NULL WHERE id='a';`);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM up_job_writes").get()!.n, 0);
    assert.equal(store.sessionHasUpJob("one"), true);
  } finally { store.close(); }
});

test("a failed job batch rolls back its scope and rows", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    dropIndex(store);
    db.exec(`INSERT INTO jobs(id,token,session_key,state,name,command,cwd,started_at,log)
      VALUES('a','a','one','running','','','',1,''),('b','b','one','running','','','',2,'')`);
    installSessionUpJobs(db);
    db.exec("CREATE TRIGGER fail_up_job BEFORE INSERT ON session_up_job_rows BEGIN SELECT RAISE(ABORT,'failed batch'); END");
    assert.throws(() => sessionUpJobsStep(db, "one", 10), /failed batch/);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM session_up_job_rows").get()!.n, 0);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM session_up_job_scopes").get()!.n, 0);
    db.exec("DROP TRIGGER fail_up_job");
    assert.deepEqual(sessionUpJobsStep(db, "one", 10), { done: true, visited: 2 });
  } finally { store.close(); }
});

test("old job rowids beyond JavaScript's safe integers are prepared without loss", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    dropIndex(store);
    db.exec(`INSERT INTO jobs(rowid,id,token,session_key,state,name,command,cwd,started_at,log)
      VALUES(-9007199254740993,'a','a','one','running','','','',1,''),
        (9007199254740993,'b','b','one','running','','','',2,'')`);
    installSessionUpJobs(db);
    assert.deepEqual(sessionUpJobsStep(db, "one", 1), { done: false, visited: 1 });
    assert.deepEqual(sessionUpJobsStep(db, "one", 1), { done: false, visited: 1 });
    assert.deepEqual(sessionUpJobsStep(db, "one", 1), { done: true, visited: 0 });
    assert.deepEqual(store.upJobIds("one"), ["b", "a"]);
  } finally { store.close(); }
});

test("an incompatible up-job index is neither read nor built", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.exec("UPDATE session_up_job_meta SET version=2");
    assert.throws(() => store.sessionHasUpJob("one"), /session up jobs.*version/i);
    assert.throws(() => sessionUpJobsStep(db, "one"), /session up jobs.*version/i);
  } finally { store.close(); }
});

test("deleting a session removes its prepared scope and jobs", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    store.insertSession({ key: "one", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w",
      token: "session-token", createdAt: 1, lastActiveAt: 1 });
    dropIndex(store);
    db.exec("INSERT INTO jobs(id,token,session_key,state,name,command,cwd,started_at,log) VALUES('a','a','one','running','','','',1,'')");
    installSessionUpJobs(db);
    assert.deepEqual(sessionUpJobsStep(db, "one"), { done: true, visited: 1 });
    assert.ok(db.prepare("SELECT 1 FROM session_up_job_scopes WHERE session='one'").get());
    store.deleteSession("one");
    assert.equal(db.prepare("SELECT 1 FROM session_up_job_scopes WHERE session='one'").get(), undefined);
    assert.equal(db.prepare("SELECT 1 FROM session_up_job_rows WHERE session='one'").get(), undefined);
  } finally { store.close(); }
});
