import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { makeStore, seenBy } from "../src/read/store.ts";
import { JOBS_UP } from "../src/store/rows.ts";
import { Store } from "../src/store/store.ts";
import { installWorkspaceUpJobs, WORKSPACE_UP_JOBS, WORKSPACE_UP_OLD_ROWIDS, WORKSPACE_UP_SAME_PORT, workspaceUpJobsReady, workspaceUpJobsStep } from "../src/store/workspace-up-jobs.ts";

const session = (s: Store, key: string, ws: string | null, token = key) => s.insertSession({ key, connect: "ember",
  runtime: "claude", profile: "cc", workspace: "/w", token, ws, createdAt: 1, lastActiveAt: 1 });
const job = (s: Store, key: string, port: number | null = null, state = "running") => s.insertJob({ id: `job-${key}`,
  sessionKey: key, name: "job", command: "true", cwd: "/", port, token: `token-${key}`, state, pgid: null,
  exitCode: null, startedAt: 1, endedAt: null, restarts: 0, log: "/dev/null", watch: false });
const removeWorkspaceIndex = (s: Store) => {
  const triggers = s.db.prepare("SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'workspace_up_%'").all() as Array<{ name: string }>;
  for (const { name } of triggers) s.db.exec(`DROP TRIGGER ${name}`);
  s.db.exec("DROP TABLE workspace_up_session_replaced; DROP TABLE workspace_up_sessions; DROP TABLE workspace_up_meta");
};

function agrees(s: Store): void {
  const reader = makeStore(s.db, ".");
  for (const workspace of ["A", "B"]) for (const home of [false, true]) {
    const viewer = { sub: "a@x", email: "a@x", name: "A", role: "member", workspace, home, device: "dev" } as const;
    const raw = s.db.prepare(JOBS_UP).all() as Array<{ id: string; session_key: string }>;
    const oldSees = seenBy(reader, viewer, raw.map((r) => r.session_key));
    const expected = raw.filter((r) => oldSees(r.session_key)).map((r) => r.id).sort();
    const rows = s.db.prepare(`SELECT j.id,j.session_key FROM workspace_up_sessions p
      CROSS JOIN session_up_job_rows u ON u.session=p.session CROSS JOIN jobs j ON j.rowid=u.job_rowid
      WHERE (p.scope=0 AND p.ws=?1) OR (p.scope=1 AND p.ws='' AND ?2) OR (p.scope=2 AND p.ws='')`)
      .all(workspace, home ? 1 : 0) as Array<{ id: string; session_key: string }>;
    const sees = seenBy(reader, viewer, rows.map((r) => r.session_key));
    assert.deepEqual(rows.filter((r) => sees(r.session_key)).map((r) => r.id).sort(), expected);
  }
}

for (const recursive of [false, true]) test(`workspace up jobs follow session replacements (recursive triggers ${recursive})`, () => {
  const s = Store.open(":memory:");
  try {
    s.db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
    installWorkspaceUpJobs(s.db);
    assert.equal(workspaceUpJobsReady(s.db), true);
    assert.equal(s.db.prepare("SELECT 1 FROM sqlite_master WHERE type='trigger' AND name='workspace_up_copy_moved'").get(), undefined);
    session(s, "old", "B", "old-token"); session(s, "mine", "A", "mine-token");
    for (const key of ["old", "mine", "ghost"]) job(s, key);
    agrees(s);
    s.db.exec(`INSERT OR REPLACE INTO sessions(key,connect,scope,runtime,profile,workspace,token,created_at,last_active_at,ws)
      SELECT 'replacement',connect,scope,runtime,profile,workspace,token,created_at,last_active_at,'A'
      FROM sessions WHERE key='old'`);
    agrees(s);
    session(s, "ghost", "B", "ghost-token"); agrees(s);
    s.db.exec("UPDATE OR REPLACE sessions SET key='mine',ws='B' WHERE key='ghost'"); agrees(s);
    s.db.exec(`INSERT OR IGNORE INTO sessions(key,connect,scope,runtime,profile,workspace,token,created_at,last_active_at,ws)
      SELECT 'ignored',connect,scope,runtime,profile,workspace,token,created_at,last_active_at,'A' FROM sessions WHERE key='mine'`);
    s.db.exec("UPDATE sessions SET ws='A' WHERE key='mine'"); agrees(s);
    session(s, "fresh", "A", "fresh-token"); agrees(s);
    s.db.exec("BEGIN; DELETE FROM sessions WHERE key='mine'"); agrees(s);
    s.db.exec("ROLLBACK"); agrees(s);
    s.db.exec("DELETE FROM sessions WHERE key='mine'"); agrees(s);
    s.db.exec("UPDATE jobs SET state='exited',port=NULL WHERE id='job-old'"); agrees(s);
    s.db.exec("UPDATE jobs SET state='running' WHERE id='job-old'"); agrees(s);
    s.db.exec(`INSERT OR REPLACE INTO jobs(id,session_key,name,command,cwd,port,token,state,pgid,exit_code,started_at,ended_at,restarts,log,watch)
      SELECT 'replacement-job','fresh',name,command,cwd,port,token,state,pgid,exit_code,started_at,ended_at,restarts,log,watch
      FROM jobs WHERE id='job-old'`); agrees(s);
    session(s, "nested-a", "A"); session(s, "nested-b", "B"); job(s, "nested-a"); job(s, "nested-b");
    s.db.exec("UPDATE OR REPLACE sessions SET token='nested-b',runtime='codex' WHERE key='nested-a'"); agrees(s);
  } finally { s.close(); }
});

test("old up jobs are copied in bounded batches while jobs move between cursor ranges", () => {
  const s = Store.open(":memory:");
  try {
    removeWorkspaceIndex(s);
    for (let i = 0; i < 8; i++) { session(s, `s-${i}`, i % 2 ? "B" : "A"); job(s, `s-${i}`, 100 + i, i < 4 ? "running" : "exited"); }
    s.db.exec("DELETE FROM session_up_job_rows; UPDATE session_up_job_meta SET fresh=0");
    installWorkspaceUpJobs(s.db);
    assert.equal(workspaceUpJobsReady(s.db), false);
    assert.equal(workspaceUpJobsStep(s.db, 2).visited, 2);
    s.db.exec("UPDATE jobs SET port=NULL WHERE id='job-s-3'");
    while ((s.db.prepare("SELECT phase FROM workspace_up_meta").get() as { phase: number }).phase === 0) {
      assert.ok(workspaceUpJobsStep(s.db, 2).visited <= 2);
    }
    assert.equal(workspaceUpJobsStep(s.db, 2).visited, 2);
    s.db.exec("UPDATE jobs SET state='running',port=NULL WHERE id='job-s-7'");
    while (!workspaceUpJobsReady(s.db)) assert.ok(workspaceUpJobsStep(s.db, 2).visited <= 2);
    agrees(s);
  } finally { s.close(); }
});

test("old-job rowid batches seek past earlier jobs and stop before newer jobs", () => {
  for (const count of [40, 400, 4000]) {
    const db = new DatabaseSync(":memory:");
    let visited = 0;
    try {
      db.function("visit", (_rowid: unknown) => { visited++; return 1; });
      db.exec(`CREATE TABLE jobs(state TEXT,port INTEGER); CREATE INDEX jobs_state ON jobs(state);
        CREATE TABLE workspace_up_meta(id INTEGER PRIMARY KEY,last_rowid INTEGER,running_end INTEGER,
          guard_last INTEGER,guard_end INTEGER);
        INSERT INTO workspace_up_meta VALUES(1,${count - 2},${count},${count - 2},${count}); BEGIN`);
      const insert = db.prepare("INSERT INTO jobs(state,port) VALUES('exited',NULL)");
      for (let i = 0; i < count * 2; i++) insert.run();
      db.exec("COMMIT");
      const query = WORKSPACE_UP_OLD_ROWIDS("guard_last", "guard_end", false);
      const instrumented = query.replace("WHERE j.state=?", "WHERE j.state=? AND visit(j.rowid)");
      const plan = (sql: string) => db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all("exited", 2).map((r) => r.detail);
      assert.deepEqual(plan(instrumented), plan(query));
      assert.ok(plan(query).some((line) => String(line).includes("rowid>?") && String(line).includes("rowid<?")));
      assert.deepEqual(db.prepare(instrumented).all("exited", 2).map((r) => r.rowid), [count - 1, count]);
      assert.equal(visited, 2);
    } finally { db.close(); }
  }
});

test("unusual stored identities remain candidates for the existing workspace check", () => {
  const s = Store.open(":memory:");
  try {
    installWorkspaceUpJobs(s.db);
    for (const [key, ws] of [["normal", "A"], ["nul\0tail", "B"], ["workspace-nul", "A\0tail"],
      ["invalid-ws", "B"], ["invalid-key", "A"]] as const) { session(s, key, ws); job(s, key); }
    s.db.exec(`UPDATE sessions SET ws=CAST(x'80' AS TEXT) WHERE key='invalid-ws';
      UPDATE sessions SET key=CAST(x'62616480' AS TEXT) WHERE key='invalid-key';
      UPDATE jobs SET session_key=CAST(x'62616480' AS TEXT) WHERE id='job-invalid-key'`);
    agrees(s);
  } finally { s.close(); }
});

test("old-job copy retains SQLite cursor types and 64-bit rowids", () => {
  const s = Store.open(":memory:");
  try {
    removeWorkspaceIndex(s);
    for (let i = 0; i < 12; i++) job(s, `wide-${i}`, 100, i < 8 ? "running" : "exited");
    s.db.exec(`UPDATE jobs SET rowid=-5 WHERE id='job-wide-0';
      UPDATE jobs SET rowid=9007199254740993 WHERE id='job-wide-1';
      UPDATE jobs SET rowid=9223372036854775807 WHERE id='job-wide-2';
      UPDATE jobs SET port=CAST(x'80' AS TEXT) WHERE id='job-wide-3';
      UPDATE jobs SET port=CAST(x'ff' AS BLOB) WHERE id='job-wide-4';
      UPDATE jobs SET port=-9 WHERE id='job-wide-5';
      UPDATE jobs SET port=NULL WHERE id='job-wide-6';
      DELETE FROM session_up_job_rows; UPDATE session_up_job_meta SET fresh=0`);
    installWorkspaceUpJobs(s.db);
    while (!workspaceUpJobsReady(s.db)) assert.ok(workspaceUpJobsStep(s.db, 2).visited <= 2);
    const missing = s.db.prepare(`SELECT CAST(j.rowid AS TEXT) id FROM jobs j
      WHERE (j.state='running' OR (j.state='exited' AND j.port IS NOT NULL))
      AND NOT EXISTS (SELECT 1 FROM session_up_job_rows u WHERE u.session=j.session_key AND u.job_rowid=j.rowid)`).all();
    assert.deepEqual(missing, []);
    assert.equal((s.db.prepare("SELECT COUNT(*) AS n FROM workspace_up_sessions").get() as { n: number }).n, 12);
  } finally { s.close(); }
});

for (const alias of ["rowid", "_rowid_", "oid"]) test(`replacing a session by ${alias} keeps both jobs' visibility`, () => {
  const s = Store.open(":memory:");
  try {
    s.db.exec("PRAGMA recursive_triggers=OFF");
    installWorkspaceUpJobs(s.db);
    session(s, "first", "A"); session(s, "second", "B");
    job(s, "first"); job(s, "second"); agrees(s);
    s.db.exec(`UPDATE OR REPLACE sessions SET ${alias}=(SELECT ${alias} FROM sessions WHERE key='second') WHERE key='first'`);
    agrees(s);
  } finally { s.close(); }
});

test("an old-job batch seeks past earlier jobs on the same port", () => {
  for (const count of [40, 400, 4000]) {
    const db = new DatabaseSync(":memory:");
    let visited = 0;
    try {
      db.function("visit", (_rowid: unknown) => { visited++; return 1; });
      db.exec(`CREATE TABLE jobs(state TEXT,port INTEGER); CREATE INDEX jobs_up ON jobs(state,port);
        CREATE TABLE workspace_up_meta(id INTEGER PRIMARY KEY,last_port,last_rowid INTEGER);
        INSERT INTO workspace_up_meta VALUES(1,100,${count - 2}); BEGIN`);
      const insert = db.prepare("INSERT INTO jobs(state,port) VALUES('running',100)");
      for (let i = 0; i < count; i++) insert.run();
      db.exec("COMMIT");
      const instrumented = WORKSPACE_UP_SAME_PORT.replace("WHERE j.state=?", "WHERE j.state=? AND visit(j.rowid)");
      const plan = (sql: string) => db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all("running", 2).map((r) => r.detail);
      assert.deepEqual(plan(instrumented), plan(WORKSPACE_UP_SAME_PORT));
      assert.ok(plan(WORKSPACE_UP_SAME_PORT).some((line) => String(line).includes("rowid>?")));
      assert.deepEqual(db.prepare(instrumented).all("running", 2).map((r) => r.rowid), [count - 1, count]);
      assert.equal(visited, 2);
    } finally { db.close(); }
  }
});

test("new up jobs do not keep the old-job copy from finishing", () => {
  const s = Store.open(":memory:");
  try {
    removeWorkspaceIndex(s);
    job(s, "old-a", 10); job(s, "old-b", 10);
    s.db.exec("DELETE FROM session_up_job_rows; UPDATE session_up_job_meta SET fresh=0");
    installWorkspaceUpJobs(s.db);
    for (let i = 0; i < 12 && !workspaceUpJobsReady(s.db); i++) {
      workspaceUpJobsStep(s.db, 2);
      job(s, `new-${i}-a`, 1000 + 2 * i);
      job(s, `new-${i}-b`, 1001 + 2 * i);
    }
    assert.equal(workspaceUpJobsReady(s.db), true, "jobs written during preparation are followed by the triggers");
    agrees(s);
  } finally { s.close(); }
});

test("new services between the remaining old ports do not keep the copy from finishing", () => {
  const s = Store.open(":memory:");
  try {
    removeWorkspaceIndex(s);
    job(s, "old-low", 10, "exited"); job(s, "old-high", 100_000, "exited");
    s.db.exec("DELETE FROM session_up_job_rows; UPDATE session_up_job_meta SET fresh=0");
    installWorkspaceUpJobs(s.db);
    for (let i = 0; i < 24 && !workspaceUpJobsReady(s.db); i++) {
      workspaceUpJobsStep(s.db, 2);
      job(s, `between-${i}-a`, 100 + 2 * i, "exited");
      job(s, `between-${i}-b`, 101 + 2 * i, "exited");
    }
    assert.equal(workspaceUpJobsReady(s.db), true, "new services are followed by the triggers");
    agrees(s);
  } finally { s.close(); }
});

test("continuous services do not prevent copying through old inactive jobs", () => {
  const s = Store.open(":memory:");
  try {
    removeWorkspaceIndex(s);
    for (let i = 0; i < 32; i++) job(s, `inactive-${i}`, null, "exited");
    job(s, "old-low", 10, "exited"); job(s, "old-high", 1_000_000, "exited");
    s.db.exec("DELETE FROM session_up_job_rows; UPDATE session_up_job_meta SET fresh=0");
    installWorkspaceUpJobs(s.db);
    let steps = 0;
    while (!workspaceUpJobsReady(s.db) && steps < 200) {
      assert.ok(workspaceUpJobsStep(s.db, 2).visited <= 2);
      job(s, `added-${steps}-a`, 100 + 2 * steps, "exited");
      job(s, `added-${steps}-b`, 101 + 2 * steps, "exited");
      steps++;
    }
    assert.equal(workspaceUpJobsReady(s.db), true);
    agrees(s);
  } finally { s.close(); }
});

test("a prepared workspace lookup ignores other workspaces and idle sessions", () => {
  const s = Store.open(":memory:");
  let visited = 0, visitedSessions = 0;
  try {
    s.db.function("visit_workspace_job", (_rowid: unknown) => { visited++; return 1; });
    s.db.function("visit_workspace_session", (_session: unknown) => { visitedSessions++; return 1; });
    session(s, "mine", "A"); job(s, "mine");
    let added = 0;
    for (const total of [40, 400, 4000]) {
      s.db.exec("BEGIN");
      for (; added < total; added++) {
        const key = `other-${added}`; session(s, key, "B"); job(s, key);
        session(s, `idle-${added}`, "A");
      }
      s.db.exec("COMMIT");
      const instrumented = WORKSPACE_UP_JOBS
        .replace("scope=0 AND ws=?1", "scope=0 AND ws=?1 AND visit_workspace_session(session)")
        .replace("scope=1 AND ws='' AND ?2", "scope=1 AND ws='' AND ?2 AND visit_workspace_session(session)")
        .replace("scope=2 AND ws=''", "scope=2 AND ws='' AND visit_workspace_session(session)")
        .replace("ORDER BY j.started_at", "WHERE visit_workspace_job(j.rowid) ORDER BY j.started_at");
      const plan = (sql: string) => s.db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all("A", 0).map((r) => r.detail);
      assert.deepEqual(plan(instrumented), plan(WORKSPACE_UP_JOBS));
      visited = 0; visitedSessions = 0;
      const rows = s.db.prepare(instrumented).all("A", 0) as Array<{ id: string }>;
      assert.deepEqual(rows.map((r) => r.id), ["job-mine"]);
      assert.equal(visited, 1);
      assert.equal(visitedSessions, 1);
    }
  } finally { s.close(); }
});

test("backfill survives another connection changing jobs and replacing sessions between batches", () => {
  const dir = mkdtempSync(join(tmpdir(), "workspace-up-handover-"));
  const path = join(dir, "stillfail.db"), s = Store.open(path), writer = new DatabaseSync(path), backfill = new DatabaseSync(path);
  try {
    const changePort = writer.prepare("UPDATE jobs SET port=? WHERE id=?");
    removeWorkspaceIndex(s);
    session(s, "a", "A", "a-token"); session(s, "b", "B", "b-token"); session(s, "c", "A", "c-token");
    job(s, "a", 100); job(s, "b", 200, "exited"); job(s, "c", null, "exited");
    s.db.exec("DELETE FROM session_up_job_rows; UPDATE session_up_job_meta SET fresh=0");
    installWorkspaceUpJobs(s.db);
    assert.notEqual(s.db.prepare("SELECT 1 FROM sqlite_master WHERE type='trigger' AND name='workspace_up_copy_moved'").get(), undefined);
    assert.equal(workspaceUpJobsStep(backfill, 1).visited, 1);
    writer.exec(`PRAGMA recursive_triggers=OFF; BEGIN;
      UPDATE jobs SET state='exited',port=50 WHERE id='job-a';
      UPDATE jobs SET port=300 WHERE id='job-b';
      UPDATE jobs SET port=400 WHERE id='job-c';
      INSERT OR REPLACE INTO sessions(key,connect,scope,runtime,profile,workspace,token,created_at,last_active_at,ws)
        SELECT 'new-b',connect,scope,runtime,profile,workspace,token,created_at,last_active_at,'A' FROM sessions WHERE key='b';
      COMMIT`);
    let steps = 0;
    while (!workspaceUpJobsReady(s.db) && steps++ < 30) assert.ok(workspaceUpJobsStep(backfill, 1).visited <= 1);
    assert.equal(workspaceUpJobsReady(s.db), true);
    assert.equal(s.db.prepare("SELECT 1 FROM sqlite_master WHERE type='trigger' AND name='workspace_up_copy_moved'").get(), undefined);
    agrees(s);
    changePort.run(null, "job-a"); agrees(s);
    changePort.run(999, "job-a"); agrees(s);
  } finally { backfill.close(); writer.close(); s.close(); rmSync(dir, { recursive: true, force: true }); }
});
