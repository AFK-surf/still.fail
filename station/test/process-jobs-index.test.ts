import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { pathToFileURL } from "node:url";
import { watchedJobs } from "../src/jobs/memory.ts";
import { ProcessJobsBuilder } from "../src/jobs/process-jobs-builder.ts";
import { installProcessJobs, processJobs, processJobsReady, processJobsStep } from "../src/store/process-jobs.ts";
import { Store } from "../src/store/store.ts";

const addSql = `INSERT OR REPLACE INTO jobs(rowid,id,token,session_key,state,pgid,name,command,cwd,port,started_at,log)
  VALUES(?,?,?,?,?,?,?,'','',?,?, '')`;
function oldAnswer(db: DatabaseSync) {
  return (db.prepare(`SELECT id,session_key,name,port,pgid FROM jobs WHERE state='running' AND pgid IS NOT NULL
    ORDER BY started_at DESC,port,rowid`).all() as { id: string; session_key: string; name: string; port: number | null; pgid: number }[])
    .map((j) => ({ id: j.id, sessionKey: j.session_key, name: j.name, port: j.port, pgid: j.pgid }));
}
function finish(db: DatabaseSync, limit = 3) {
  let steps = 0;
  while (!processJobsReady(db)) {
    assert.ok(processJobsStep(db, limit).visited <= limit);
    assert.ok(++steps < 100);
  }
}

for (const recursive of [false, true]) test(`process job keys follow old writes and replacements (recursive triggers ${recursive})`, () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    const put = db.prepare(addSql);
    put.run(1, "a", "ta", "one", "running", 101, "first", null, 10);
    put.run(2, "b", "tb", "two", "running", 202, "second", 8000, 10);
    put.run(3, "c", "tc", "other", "running", null, "queued", null, 1);
    installProcessJobs(db);
    assert.equal(processJobs(db), null);
    finish(db, 1);
    assert.deepEqual(processJobs(db), oldAnswer(db));
    let seed = 0x12345678;
    const next = (n: number) => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % n; };
    const change = db.prepare(`UPDATE OR REPLACE jobs SET rowid=?,id=?,token=?,session_key=?,state=?,pgid=?,name=?,port=?,started_at=? WHERE rowid=?`);
    const drop = db.prepare("DELETE FROM jobs WHERE rowid=?");
    for (let i = 0; i < 400; i++) {
      const row = next(25) - 5, id = `j${next(13)}`, token = `t${next(11)}`, session = `s${next(3)}`;
      const state = ["running", "exited", "stopped"][next(3)]!, pgid = next(3) === 0 ? null : 100 + next(30);
      const args = [row, id, token, session, state, pgid, `name-${i}`, next(3) === 0 ? 8000 : null, i];
      if (i % 6 === 0) drop.run(row);
      else if (i % 6 === 1) change.run(...args, next(25) - 5);
      else put.run(...args);
      assert.deepEqual(processJobs(db), oldAnswer(db), `operation ${i}`);
    }
    db.exec(`INSERT OR IGNORE INTO jobs(rowid,id,token,session_key,state,pgid,name,command,cwd,started_at,log)
      VALUES (99,'a','unused','other','running',999,'','','',0,'')`);
    assert.deepEqual(processJobs(db), oldAnswer(db));
    db.exec("UPDATE jobs SET name='renamed' WHERE id='a'");
    assert.deepEqual(processJobs(db), oldAnswer(db));
  } finally { store.close(); }
});

for (const recursive of [false, true]) for (const alias of ["rowid", "_rowid_", "oid"]) {
  test(`an ignored write and a replacement by ${alias} preserve process ownership (recursive triggers ${recursive})`, () => {
    const store = Store.open(":memory:"), db = store.db;
    try {
      db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
      db.prepare(addSql).run(1, "a", "ta", "one", "running", 1, "a", null, 1);
      installProcessJobs(db); finish(db);
      db.exec(`INSERT OR IGNORE INTO jobs(${alias},id,token,session_key,state,pgid,name,command,cwd,started_at,log)
        VALUES(2,'a','unused','other','running',2,'ignored','','',2,'')`);
      assert.deepEqual(processJobs(db), oldAnswer(db));
      db.exec("UPDATE jobs SET name='renamed' WHERE id='a'");
      assert.deepEqual(processJobs(db), oldAnswer(db));
      db.exec(`INSERT OR REPLACE INTO jobs(${alias},id,token,session_key,state,pgid,name,command,cwd,started_at,log)
        VALUES(1,'b','tb','two','running',2,'replacement','','',2,'')`);
      assert.deepEqual(processJobs(db), oldAnswer(db));
      assert.deepEqual(processJobs(db)?.map((j) => j.id), ["b"]);
    } finally { store.close(); }
  });
}

for (const recursive of [false, true]) test(`old running jobs are prepared while another connection writes (recursive triggers ${recursive})`, () => {
  const dir = mkdtempSync(join(tmpdir(), "process-job-old-")), path = join(dir, "stillfail.db");
  const store = Store.open(path), db = store.db, old = new DatabaseSync(path);
  try {
    old.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    for (let i = 1; i <= 8; i++) db.prepare(addSql).run(i, `old-${i}`, `old-${i}`, "one", "running", i % 2 ? i : null, "old", null, i);
    installProcessJobs(db);
    assert.deepEqual(processJobsStep(db, 2), { done: false, visited: 2 });
    old.exec("UPDATE jobs SET rowid=-10 WHERE id='old-7'; UPDATE jobs SET pgid=200 WHERE id='old-8'; DELETE FROM jobs WHERE id='old-1'");
    old.prepare(addSql).run(1000, "new", "new", "two", "running", 1000, "new", null, 10);
    finish(db, 2);
    assert.deepEqual(processJobs(db), oldAnswer(db));
    old.exec("UPDATE jobs SET state='exited' WHERE id='old-3'");
    assert.deepEqual(processJobs(db), oldAnswer(db));
  } finally { old.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("old job rowids beyond JavaScript's safe integers are not lost", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.exec(`INSERT INTO jobs(rowid,id,token,session_key,state,pgid,name,command,cwd,started_at,log)
      VALUES(CAST('9223372036854775806' AS INTEGER),'large','large','one','running',2,'large','','',2,''),
        (CAST('-9223372036854775807' AS INTEGER),'small','small','one','running',1,'small','','',1,'')`);
    installProcessJobs(db); finish(db, 1);
    assert.deepEqual(processJobs(db), oldAnswer(db));
  } finally { store.close(); }
});

test("the readiness check and process groups use the same snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "process-job-snapshot-")), path = join(dir, "stillfail.db");
  const store = Store.open(path), db = store.db, old = new DatabaseSync(path);
  try {
    db.prepare(addSql).run(1, "first", "first", "one", "running", 1, "first", null, 1);
    installProcessJobs(db); finish(db);
    let changed = false;
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const prepared = target.prepare(sql);
        if (!sql.startsWith("SELECT version, complete FROM process_job_meta")) return prepared;
        return new Proxy(prepared, { get(stmt, part) {
          if (part === "get") return (...args: Parameters<typeof prepared.get>) => {
            const result = stmt.get(...args);
            if (!changed) {
              changed = true;
              old.exec("UPDATE jobs SET pgid=NULL WHERE id='first'");
              old.prepare(addSql).run(2, "later", "later", "two", "running", 2, "later", null, 2);
            }
            return result;
          };
          const value = Reflect.get(stmt, part, stmt);
          return typeof value === "function" ? value.bind(stmt) : value;
        } });
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    assert.deepEqual(processJobs(observed)?.map((j) => j.id), ["first"]);
    assert.deepEqual(processJobs(db)?.map((j) => j.id), ["later"]);
  } finally { old.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("vacuum during and after preparation keeps the process groups exact", () => {
  const dir = mkdtempSync(join(tmpdir(), "process-job-vacuum-")), path = join(dir, "stillfail.db");
  const store = Store.open(path), db = store.db;
  try {
    const put = db.prepare(addSql);
    put.run(101, "a", "a", "one", "running", 1, "a", null, 1);
    put.run(500, "b", "b", "one", "running", 2, "b", null, 2);
    put.run(900, "c", "c", "one", "running", 3, "c", null, 3);
    installProcessJobs(db);
    assert.deepEqual(processJobsStep(db, 1), { done: false, visited: 1 });
    const before = (db.prepare("PRAGMA schema_version").get() as { schema_version: number }).schema_version;
    db.exec("VACUUM");
    assert.notEqual((db.prepare("PRAGMA schema_version").get() as { schema_version: number }).schema_version, before);
    finish(db, 1);
    assert.deepEqual(processJobs(db), oldAnswer(db));
    db.exec("VACUUM");
    assert.deepEqual(processJobs(db), oldAnswer(db));
  } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("failed process job batches roll back rows and cursor together", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const put = db.prepare(addSql);
    put.run(1, "a", "a", "one", "running", 1, "a", null, 1);
    put.run(2, "b", "b", "one", "running", 2, "b", null, 2);
    installProcessJobs(db);
    db.exec("CREATE TRIGGER fail_process_job BEFORE INSERT ON process_job_rows WHEN NEW.job='b' BEGIN SELECT RAISE(ABORT,'failed batch'); END");
    assert.throws(() => processJobsStep(db, 4), /failed batch/);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM process_job_rows").get()!.n, 0);
    assert.equal(db.prepare("SELECT cursor FROM process_job_meta WHERE id=1").get()!.cursor, null);
    db.exec("DROP TRIGGER fail_process_job");
    finish(db);
    assert.deepEqual(processJobs(db), oldAnswer(db));
  } finally { store.close(); }
});

test("a running job's unrelated updates do not rewrite its lookup key", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    db.prepare(addSql).run(1, "a", "a", "one", "running", 1, "a", null, 1);
    installProcessJobs(db); finish(db);
    db.exec(`CREATE TEMP TABLE process_job_writes (n INTEGER);
      CREATE TEMP TRIGGER process_job_added AFTER INSERT ON main.process_job_rows BEGIN INSERT INTO process_job_writes VALUES(1); END;
      CREATE TEMP TRIGGER process_job_removed AFTER DELETE ON main.process_job_rows BEGIN INSERT INTO process_job_writes VALUES(1); END;
      UPDATE jobs SET name='new',pgid=2 WHERE id='a'`);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM process_job_writes").get()!.n, 0);
    assert.deepEqual(processJobs(db), oldAnswer(db));
  } finally { store.close(); }
});

test("unknown versions and old null ids leave the immediate old answer available", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(`CREATE TABLE jobs (id TEXT PRIMARY KEY, token TEXT UNIQUE, session_key TEXT, state TEXT, pgid INTEGER,
      name TEXT, port INTEGER, started_at INTEGER); CREATE INDEX jobs_state ON jobs(state);
      INSERT INTO jobs VALUES(NULL,'null','one','running',1,'old',NULL,1)`);
    installProcessJobs(db); finish(db);
    assert.equal(processJobs(db), null);
    db.exec("DELETE FROM jobs WHERE id IS NULL");
    assert.deepEqual(processJobs(db), []);
    db.exec("UPDATE process_job_meta SET version=99");
    assert.throws(() => processJobs(db), /incompatible/);
  } finally { db.close(); }
});

test("a memory check answers during handover and prepares groups afterwards", async () => {
  const dir = mkdtempSync(join(tmpdir(), "process-job-handover-")), path = join(dir, "stillfail.db");
  const store = Store.open(path), db = store.db;
  let handover!: () => void;
  const previous = new Promise<void>((resolve) => { handover = resolve; });
  const builder = new ProcessJobsBuilder(store, previous);
  try {
    const put = db.prepare(addSql);
    for (let i = 1; i <= 40; i++) put.run(i, `j${i}`, `j${i}`, "one", "running", i === 1 ? 101 : null, "job", null, i);
    assert.deepEqual(watchedJobs(store, builder).map((j) => j.id), ["j1"]);
    assert.equal(db.prepare("SELECT 1 FROM sqlite_master WHERE name='process_job_meta'").get(), undefined);
    handover();
    await builder.settled();
    assert.equal(processJobsReady(db), true);
    assert.deepEqual(watchedJobs(store, builder).map((j) => j.id), ["j1"]);
  } finally { handover(); await builder.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("small queues do not install an extra lookup, and closing cancels handover", async () => {
  const store = Store.open(":memory:"), db = store.db;
  const previous = Promise.withResolvers<void>(), builder = new ProcessJobsBuilder(store, previous.promise);
  try {
    const put = db.prepare(addSql);
    put.run(1, "one", "one", "one", "running", 1, "job", null, 1);
    assert.equal(watchedJobs(store, builder).length, 1);
    await builder.settled();
    assert.equal(db.prepare("SELECT 1 FROM sqlite_master WHERE name='process_job_meta'").get(), undefined);
    for (let i = 2; i <= 40; i++) put.run(i, `j${i}`, `j${i}`, "one", "running", null, "job", null, i);
    assert.equal(watchedJobs(store, builder).length, 1);
    await builder.close();
    previous.resolve();
    assert.equal(db.prepare("SELECT 1 FROM sqlite_master WHERE name='process_job_meta'").get(), undefined);
  } finally { previous.resolve(); await builder.close(); store.close(); }
});

test("a later memory check retries a stopped process job worker", async () => {
  const dir = mkdtempSync(join(tmpdir(), "process-job-retry-")), store = Store.open(join(dir, "stillfail.db"));
  const worker = join(dir, "worker.mjs");
  writeFileSync(worker, "process.exit(1);\n");
  const builder = new ProcessJobsBuilder(store, Promise.resolve(), pathToFileURL(worker));
  try {
    const put = store.db.prepare(addSql);
    for (let i = 1; i <= 40; i++) put.run(i, `j${i}`, `j${i}`, "one", "running", i === 1 ? 101 : null, "job", null, i);
    assert.equal(watchedJobs(store, builder).length, 1);
    await builder.settled();
    assert.equal(store.db.prepare("SELECT 1 FROM sqlite_master WHERE name='process_job_meta'").get(), undefined);
    const actual = new URL("../src/sessions/workspace-activity-worker.ts", import.meta.url).href;
    writeFileSync(worker, `import ${JSON.stringify(actual)};\n`);
    assert.equal(watchedJobs(store, builder).length, 1);
    await builder.settled();
    assert.equal(processJobsReady(store.db), true);
    assert.equal(watchedJobs(store, builder).length, 1);
  } finally { await builder.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});
