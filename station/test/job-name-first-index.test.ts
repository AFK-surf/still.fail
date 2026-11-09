import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { JOB_NAME_FIRST_ROW, JOB_NAME_FIRST_SCAN, jobNameFirstStep } from "../src/store/job-name-first.ts";
import { Store } from "../src/store/store.ts";

function fixture(s: Store, count: number): number {
  s.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a",
    createdAt: 1, lastActiveAt: 1, createdBy: "ann@x" });
  s.insertJob({ id: "job-a", sessionKey: "a", name: "job", command: "true", cwd: "/", port: null, token: "job-a",
    state: "running", pgid: null, exitCode: null, startedAt: 1, endedAt: null, restarts: 0, log: "/dev/null", watch: false });
  const t = s.openThreadOf("ember", "CHAT", "shared", "Shared", "ann@x", "a");
  const insert = s.db.prepare("INSERT INTO thread_sessions(thread,session,connect,joined_at) VALUES (?,?,'ember',?)");
  insert.run(t.id, "a", 0);
  for (let i = 0; i < count; i++) insert.run(t.id, `peer-${String(i).padStart(5, "0")}`, i + 1);
  return t.id;
}

function prepare(db: DatabaseSync, thread: number, limit = 64, owner = "a"): { batches: number; visited: number } {
  let batches = 0, visited = 0, done = false;
  while (!done) {
    const step = jobNameFirstStep(db, owner, thread, limit);
    assert.ok(step.visited <= limit); visited += step.visited; batches++; done = step.done;
    assert.ok(batches < 2000);
  }
  return { batches, visited };
}

for (const count of [40, 400, 4000]) test(`first job member prepares ${count} peers in bounded seeks`, () => {
  const s = Store.open(":memory:");
  try {
    const thread = fixture(s, count);
    const result = prepare(s.db, thread);
    assert.equal(result.visited, count + 1);
    assert.equal((s.db.prepare(JOB_NAME_FIRST_ROW).get("a", thread) as any).session, "a");
    const plan = s.db.prepare(`EXPLAIN QUERY PLAN ${JOB_NAME_FIRST_SCAN(false)}`).all(thread, "a", 64) as any[];
    assert.ok(plan.some((row) => /thread=\? AND session>\? AND session<\?/.test(row.detail)), JSON.stringify(plan));
  } finally { s.close(); }
});

test("an old writer's additions, removals and replacements keep a ready first member current", () => {
  const s = Store.open(":memory:");
  try {
    const thread = fixture(s, 40), db = s.db;
    prepare(db, thread);
    const first = () => (db.prepare(JOB_NAME_FIRST_ROW).get("a", thread) as any)?.session;
    db.prepare("INSERT INTO thread_sessions(thread,session,connect,joined_at) VALUES (?,'later','ember',999)").run(thread);
    assert.equal(first(), "a");
    db.prepare("INSERT INTO thread_sessions(thread,session,connect,joined_at) VALUES (?,'earlier','ember',-1)").run(thread);
    assert.equal(first(), "earlier");
    db.prepare("DELETE FROM thread_sessions WHERE thread=? AND session='earlier'").run(thread);
    assert.equal(first(), undefined);
    prepare(db, thread);
    assert.equal(first(), "a");
    db.prepare("INSERT OR REPLACE INTO thread_sessions(thread,session,connect,joined_at) VALUES (?,'a','ember',9999)").run(thread);
    assert.equal(first(), undefined);
    prepare(db, thread);
    assert.equal(first(), "peer-00000");
  } finally { s.close(); }
});

test("later additions do not keep an initial fixed-end preparation open", () => {
  const s = Store.open(":memory:");
  try {
    const thread = fixture(s, 100), db = s.db;
    let done = false, iteration = 0;
    while (!done && iteration < 30) {
      db.prepare("INSERT INTO thread_sessions(thread,session,connect,joined_at) VALUES (?,?,'ember',?)")
        .run(thread, `zz-${String(iteration).padStart(3, "0")}`, -1 - iteration);
      done = jobNameFirstStep(db, "a", thread, 7).done;
      iteration++;
    }
    assert.ok(done && iteration < 30);
    assert.equal((db.prepare(JOB_NAME_FIRST_ROW).get("a", thread) as any).session, `zz-${String(iteration - 1).padStart(3, "0")}`);
  } finally { s.close(); }
});

test("a final up job removes its one tracked chat, and an abandoned request cannot recreate it", () => {
  const s = Store.open(":memory:");
  try {
    const thread = fixture(s, 1), db = s.db;
    s.insertJob({ id: "service", sessionKey: "a", name: "service", command: "true", cwd: "/", port: 123, token: "service",
      state: "running", pgid: null, exitCode: null, startedAt: 1, endedAt: null, restarts: 0, log: "/dev/null", watch: false });
    prepare(db, thread);
    db.prepare("UPDATE jobs SET state='exited' WHERE id='job-a'").run();
    assert.ok(db.prepare(JOB_NAME_FIRST_ROW).get("a", thread));
    db.prepare("UPDATE jobs SET state='exited' WHERE id='service'").run();
    assert.ok(db.prepare(JOB_NAME_FIRST_ROW).get("a", thread));
    db.prepare("UPDATE jobs SET port=NULL WHERE id='service'").run();
    assert.equal(db.prepare("SELECT 1 FROM job_name_first WHERE owner='a'").get(), undefined);
    assert.deepEqual(jobNameFirstStep(db, "a", thread), { done: true, visited: 0 });
    assert.equal(db.prepare("SELECT 1 FROM job_name_first WHERE owner='a'").get(), undefined);
  } finally { s.close(); }
});

test("a job ending during preparation removes its partial summary", () => {
  const s = Store.open(":memory:");
  try {
    const thread = fixture(s, 100), db = s.db;
    assert.deepEqual(jobNameFirstStep(db, "a", thread, 7), { done: false, visited: 7 });
    db.prepare("UPDATE jobs SET state='exited' WHERE id='job-a'").run();
    assert.equal(db.prepare("SELECT 1 FROM job_name_first WHERE owner='a'").get(), undefined);
    assert.deepEqual(jobNameFirstStep(db, "a", thread, 7), { done: true, visited: 0 });
    db.prepare("UPDATE jobs SET state='running' WHERE id='job-a'").run();
    prepare(db, thread, 7);
    assert.equal((db.prepare(JOB_NAME_FIRST_ROW).get("a", thread) as any).session, "a");
  } finally { s.close(); }
});

test("a replacement displacing the first members of two tracked chats invalidates both", () => {
  const s = Store.open(":memory:");
  try {
    const first = fixture(s, 70), db = s.db;
    s.insertSession({ key: "b", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "b",
      createdAt: 1, lastActiveAt: 1, createdBy: "ann@x" });
    s.insertJob({ id: "job-b", sessionKey: "b", name: "job", command: "true", cwd: "/", port: null, token: "job-b",
      state: "running", pgid: null, exitCode: null, startedAt: 1, endedAt: null, restarts: 0, log: "/dev/null", watch: false });
    const second = s.openThreadOf("ember", "CHAT", "other", "Other", "ann@x", "b").id;
    db.prepare("INSERT INTO thread_sessions(thread,session,connect,joined_at) VALUES (?,'b','ember',0)").run(second);
    prepare(db, first); prepare(db, second, 64, "b");
    const rowid = (db.prepare("SELECT best FROM job_name_first WHERE owner='a'").get() as any).best;
    db.exec("PRAGMA recursive_triggers=OFF");
    db.prepare("INSERT OR REPLACE INTO thread_sessions(rowid,thread,session,connect,joined_at) VALUES (?,?,'b','ember',-1)")
      .run(rowid, second);
    assert.equal(db.prepare(JOB_NAME_FIRST_ROW).get("a", first), undefined);
    assert.equal(db.prepare(JOB_NAME_FIRST_ROW).get("b", second), undefined);
    prepare(db, first); prepare(db, second, 64, "b");
    assert.equal((db.prepare(JOB_NAME_FIRST_ROW).get("a", first) as any).session, "peer-00000");
    assert.equal((db.prepare(JOB_NAME_FIRST_ROW).get("b", second) as any).session, "b");
  } finally { s.close(); }
});

test("bounded preparation keeps unusual stored keys and large rowids in SQLite", () => {
  const s = Store.open(":memory:");
  try {
    const thread = fixture(s, 130), db = s.db;
    db.prepare("INSERT INTO thread_sessions(rowid,thread,session,connect,joined_at) VALUES (9007199254741001,?,CAST(X'610078' AS TEXT),'ember',-3)").run(thread);
    db.prepare("INSERT INTO thread_sessions(thread,session,connect,joined_at) VALUES (?,CAST(X'61ff' AS TEXT),'ember',-2)").run(thread);
    db.prepare("INSERT INTO thread_sessions(thread,session,connect,joined_at) VALUES (?,X'62ff','ember',-1)").run(thread);
    const result = prepare(db, thread, 7);
    assert.equal(result.visited, 134);
    const actual = db.prepare("SELECT best FROM job_name_first WHERE owner='a'"); actual.setReadBigInts(true);
    const expected = db.prepare("SELECT rowid FROM thread_sessions WHERE thread=? ORDER BY joined_at,rowid LIMIT 1"); expected.setReadBigInts(true);
    assert.equal((actual.get() as any).best, (expected.get(thread) as any).rowid);
  } finally { s.close(); }
});

test("the first member and its readiness remain in a reader's snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "job-name-first-")), file = join(dir, "stillfail.db");
  const s = Store.open(file), writer = new DatabaseSync(file), reader = new DatabaseSync(file);
  try {
    const thread = fixture(s, 40); prepare(s.db, thread);
    reader.exec("BEGIN");
    try {
      assert.equal((reader.prepare(JOB_NAME_FIRST_ROW).get("a", thread) as any).session, "a");
      writer.prepare("INSERT INTO thread_sessions(thread,session,connect,joined_at) VALUES (?,'earlier','ember',-1)").run(thread);
      assert.equal((reader.prepare(JOB_NAME_FIRST_ROW).get("a", thread) as any).session, "a");
    } finally { reader.exec("COMMIT"); }
    assert.equal((reader.prepare(JOB_NAME_FIRST_ROW).get("a", thread) as any).session, "earlier");
  } finally { reader.close(); writer.close(); s.close(); rmSync(dir, { recursive: true, force: true }); }
});
