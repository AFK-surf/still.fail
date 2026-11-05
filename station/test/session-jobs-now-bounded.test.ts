import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { jobsNow, LATEST_JOBS, makeStore, PREPARED_UP_JOBS_OF, UP_JOBS_OF } from "../src/read/store.ts";
import { sessionUpJobsReady, sessionUpJobsStep } from "../src/store/session-up-jobs.ts";
import { Store } from "../src/store/store.ts";

test("a session's current jobs do not inspect other sessions' running or restarting jobs", () => {
  const reads: { running: number; restarting: number; candidates: number }[] = [];
  for (const unrelated of [40, 400]) {
    const store = Store.open(":memory:"), db = store.db;
    let running = 0, restarting = 0, candidates = 0;
    db.function("other_running_seen", (id) => { if (String(id).startsWith("other-")) running++; return 1; });
    db.function("other_restarting_seen", (id) => { if (String(id).startsWith("other-")) restarting++; return 1; });
    db.function("up_candidate_seen", () => { candidates++; return 1; });
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => target.prepare(sql === UP_JOBS_OF
        ? sql.replace("state = 'running' AND session_key", "state = 'running' AND other_running_seen(id) AND session_key")
          .replace("port IS NOT NULL AND session_key", "port IS NOT NULL AND other_restarting_seen(id) AND session_key")
        : sql === PREPARED_UP_JOBS_OF ? sql.replace("ON j.rowid = i.job_rowid", "ON j.rowid = i.job_rowid AND up_candidate_seen()") : sql);
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    try {
      const insert = db.prepare(`INSERT INTO jobs(id,token,session_key,state,port,name,command,cwd,started_at,log)
        VALUES(?,?,?,?,?,'','','',?,'')`);
      insert.run("kept-running", "kept-running", "mine", "running", null, 0);
      insert.run("kept-service", "kept-service", "mine", "exited", 3000, 1);
      for (let i = 0; i < 60; i++) insert.run(`old-${i}`, `old-${i}`, "mine", "exited", null, 10 + i);
      for (let i = 0; i < unrelated; i++) {
        insert.run(`other-running-${i}`, `other-running-${i}`, "other", "running", null, i);
        insert.run(`other-service-${i}`, `other-service-${i}`, "other", "exited", 3001 + i, i);
      }
      const jobs = jobsNow(makeStore(observed, "."), "mine");
      assert.equal(jobs.length, 52);
      assert.ok(jobs.some((job) => job.id === "kept-running"));
      assert.ok(jobs.some((job) => job.id === "kept-service"));
      const plan = (db.prepare(`EXPLAIN QUERY PLAN ${PREPARED_UP_JOBS_OF}`).all("mine") as { detail: string }[]).map((r) => r.detail).join(" | ");
      assert.match(plan, /SEARCH i USING PRIMARY KEY \(session=\?\)/);
      assert.match(plan, /SEARCH j USING INTEGER PRIMARY KEY \(rowid=\?\)/);
      reads.push({ running, restarting, candidates });
    } finally { store.close(); }
  }
  assert.deepEqual(reads, [{ running: 0, restarting: 0, candidates: 2 }, { running: 0, restarting: 0, candidates: 2 }]);
});

test("vacuum keeps current jobs attached to the correct session", () => {
  const dir = mkdtempSync(join(tmpdir(), "session-up-vacuum-"));
  const store = Store.open(join(dir, "stillfail.db")), db = store.db;
  try {
    db.exec(`INSERT INTO jobs(rowid,id,token,session_key,state,name,command,cwd,started_at,log)
      VALUES (1,'gap','gap','gap','exited','','','',1,''),
        (100,'mine','mine','mine','running','','','',2,''),
        (200,'other','other','other','running','','','',3,'');
      DELETE FROM jobs WHERE id='gap'`);
    assert.deepEqual(store.upJobIds("mine"), ["mine"]);
    db.exec("VACUUM");
    assert.deepEqual(store.upJobIds("mine"), ["mine"]);
    assert.deepEqual(jobsNow(makeStore(db, "."), "mine").map((j) => j.id), ["mine"]);
  } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("prepared current jobs keep the old ordering and an old store falls back until ready", () => {
  const store = Store.open(":memory:"), db = store.db;
  try {
    const insert = db.prepare(`INSERT INTO jobs(id,token,session_key,state,port,name,command,cwd,started_at,log)
      VALUES(?,?,'mine',?,?,'','','',?,'')`);
    for (const [id, state, port] of [["service-b", "exited", 9], ["run-b", "running", 9], ["run-null", "running", null],
      ["service-a", "exited", 2], ["run-a", "running", 2], ["run-null-2", "running", null]] as const)
      insert.run(id, id, state, port, 1);
    for (let i = 0; i < 60; i++) insert.run(`ended-${i}`, `ended-${i}`, "exited", null, i + 10);
    const old = new Map<string, any>();
    for (const row of [...db.prepare(LATEST_JOBS).all("mine", 50), ...db.prepare(UP_JOBS_OF).all("mine")]) old.set(String(row.id), row);
    const expected = [...old.values()].sort((a, b) => b.started_at - a.started_at).map((row) => row.id);
    assert.deepEqual(jobsNow(makeStore(db, "."), "mine").map((j) => j.id), expected);
    db.exec("UPDATE session_up_job_meta SET fresh = 0");
    const read = makeStore(db, ".");
    assert.equal(sessionUpJobsReady(db, "mine"), false);
    assert.deepEqual(jobsNow(read, "mine").map((j) => j.id), expected);
    assert.equal(read.prepareUpJobs, "mine");
    while (!sessionUpJobsReady(db, "mine")) sessionUpJobsStep(db, "mine", 10);
    read.prepareUpJobs = null;
    assert.deepEqual(jobsNow(read, "mine").map((j) => j.id), expected);
    assert.equal(read.prepareUpJobs, null);
    db.exec("DROP TABLE session_up_job_meta");
    assert.deepEqual(jobsNow(read, "mine").map((j) => j.id), expected);
    assert.equal(read.prepareUpJobs, null);
  } finally { store.close(); }
});

test("an old session whose jobs all fit in the recent page needs no up-job lookup or preparation", () => {
  for (const count of [0, 1, 50]) {
    const store = Store.open(":memory:"), db = store.db;
    try {
      db.exec("UPDATE session_up_job_meta SET fresh=0");
      const insert = db.prepare(`INSERT INTO jobs(id,token,session_key,state,name,command,cwd,started_at,log)
        VALUES(?,?,?,'running','','','',?,'')`);
      for (let i = 0; i < count; i++) insert.run(`mine-${i}`, `mine-${i}`, "mine", i);
      for (let i = 0; i < 40; i++) insert.run(`other-${i}`, `other-${i}`, "other", i);
      let upReads = 0;
      const observed = new Proxy(db, { get(target, property) {
        if (property === "prepare") return (sql: string) => {
          if (sql === UP_JOBS_OF || sql === PREPARED_UP_JOBS_OF || sql.startsWith("SELECT version, fresh FROM session_up_job_meta")) upReads++;
          return target.prepare(sql);
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      } });
      const read = makeStore(observed, ".");
      assert.equal(jobsNow(read, "mine").length, count);
      assert.equal(upReads, 0, `${count} jobs fit in the recent page`);
      assert.equal(read.prepareUpJobs, null);
    } finally { store.close(); }
  }
});
