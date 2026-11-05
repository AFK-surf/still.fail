import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { installRecoverWaits, recoverWaitsReady, recoverWaitsStep, RECOVER_BACKFILL_FIRST, RECOVER_BACKFILL_NEXT, RECOVER_WAITS } from "../src/store/recover-waits.ts";

function fixture() {
  const db = new DatabaseSync(":memory:");
  db.exec(`CREATE TABLE sessions (key TEXT PRIMARY KEY, token TEXT NOT NULL UNIQUE, running INTEGER NOT NULL DEFAULT 0,
      archived_at INTEGER, last_active_at INTEGER NOT NULL);
    CREATE TABLE turns (id TEXT PRIMARY KEY, session_key TEXT NOT NULL, started_at INTEGER NOT NULL, ended_at INTEGER,
      outcome TEXT, detail TEXT, declared TEXT, wait_for TEXT);
    CREATE INDEX turns_by_session ON turns (session_key, started_at);`);
  const addSession = db.prepare("INSERT INTO sessions(key,token,last_active_at) VALUES (?,?,?)");
  const addTurn = db.prepare("INSERT INTO turns(id,session_key,started_at,ended_at,outcome,detail,declared) VALUES (?,?,?,?,?,?,?)");
  const session = (key: string, at = 0, token = key) => addSession.run(key, token, at);
  const turn = (id: string, key: string, at: number, declared: string | null, outcome = "completed", detail: string | null = null, ended: number | null = 1) =>
    addTurn.run(id, key, at, ended, outcome, detail, declared);
  const actual = () => (db.prepare("SELECT session FROM session_recover_waits ORDER BY session").all() as {session:string}[]).map((r) => r.session);
  const query = () => (db.prepare(RECOVER_WAITS).all() as {key:string}[]).map((r) => r.key);
  return { db, session, turn, actual, query };
}

test("old sessions are prepared in bounded resumable batches while both sides of the cursor change", () => {
  const { db, session, turn, actual } = fixture();
  try {
    for (const key of ["a", "b", "c", "d", "e"]) { session(key); turn(`t-${key}`, key, 1, "waiting"); }
    installRecoverWaits(db);
    assert.equal(recoverWaitsReady(db), false);
    assert.deepEqual(actual(), []);
    assert.deepEqual(recoverWaitsStep(db, 2), { done: false, visited: 2 });
    db.prepare("UPDATE turns SET declared='all_done' WHERE id='t-a'").run();
    db.prepare("UPDATE sessions SET archived_at=1 WHERE key='c'").run();
    db.prepare("UPDATE sessions SET running=1 WHERE key='d'").run();
    session("aa"); turn("t-aa", "aa", 1, "waiting");
    installRecoverWaits(db);
    while (!recoverWaitsReady(db)) assert.ok(recoverWaitsStep(db, 2).visited <= 2);
    assert.deepEqual(actual(), ["aa", "b", "e"]);
    assert.deepEqual(recoverWaitsStep(db, 2), { done: true, visited: 0 });
  } finally { db.close(); }
});

test("only each live idle session's latest ended wait or allowance failure is recovered, in activity order", () => {
  const { db, session, turn, actual, query } = fixture();
  try {
    installRecoverWaits(db);
    assert.equal(recoverWaitsReady(db), true);
    session("a", 5); session("b", 10); session("c", 10); session("archived", 20);
    turn("a-old", "a", 1, "waiting");
    turn("a-new", "a", 2, "all_done");
    turn("b-old", "b", 2, "all_done");
    turn("b-new", "b", 2, "waiting"); // The later row wins a tied timestamp.
    turn("c", "c", 1, null, "failed", "rate_limit:tomorrow");
    turn("archived", "archived", 1, "waiting");
    db.prepare("UPDATE sessions SET archived_at=1 WHERE key='archived'").run();
    assert.deepEqual(actual(), ["b", "c"]);
    assert.deepEqual(query(), ["c", "b"]);
    db.prepare("UPDATE turns SET ended_at=NULL WHERE id='b-new'").run();
    assert.deepEqual(actual(), ["c"]);
    db.prepare("DELETE FROM turns WHERE id='a-new'").run();
    db.prepare("UPDATE sessions SET running=1 WHERE key='c'").run();
    assert.deepEqual(actual(), ["a"]);
    db.prepare("UPDATE sessions SET archived_at=NULL WHERE key='archived'").run();
    assert.deepEqual(query(), ["archived", "a"]);
    const count = () => (db.prepare("SELECT total_changes() AS n").get() as {n:number}).n;
    const before = count();
    db.prepare("UPDATE turns SET wait_for='some work' WHERE id='a-old'").run();
    assert.equal(count() - before, 1, "unrelated turn fields do not rewrite the lookup");
  } finally { db.close(); }
});

for (const recursive of [false, true]) test(`replacement and ignored writes keep recovery current (recursive triggers ${recursive})`, () => {
  const { db, session, turn, actual } = fixture();
  try {
    db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
    installRecoverWaits(db);
    session("a"); session("b"); session("c");
    turn("a-wait", "a", 1, "waiting");
    turn("b-wait", "b", 1, "waiting");
    db.prepare("INSERT OR IGNORE INTO turns VALUES ('a-wait','c',2,1,'completed',NULL,'all_done',NULL)").run();
    assert.deepEqual(actual(), ["a", "b"]);
    db.prepare("INSERT OR REPLACE INTO turns VALUES ('a-wait','c',2,1,'completed',NULL,'all_done',NULL)").run();
    assert.deepEqual(actual(), ["b"]);
    turn("a-next", "a", 2, "waiting");
    db.prepare("UPDATE OR REPLACE turns SET id='b-wait' WHERE id='a-next'").run();
    assert.deepEqual(actual(), ["a"]);
    db.prepare("INSERT OR REPLACE INTO sessions(key,token,last_active_at) VALUES ('c','a',0)").run();
    assert.deepEqual(actual(), []);
    session("a", 0, "a-again"); // Old turns still exist, and must become recoverable if the session comes back.
    assert.deepEqual(actual(), ["a"]);
  } finally { db.close(); }
});

test("a failed batch rolls its entries and cursor back together", () => {
  const { db, session, turn, actual } = fixture();
  try {
    session("a"); session("b"); turn("a", "a", 1, "waiting"); turn("b", "b", 1, "waiting");
    installRecoverWaits(db);
    db.exec("CREATE TRIGGER fail_wait BEFORE INSERT ON session_recover_waits WHEN NEW.session='b' BEGIN SELECT RAISE(ABORT,'test failure'); END");
    assert.throws(() => recoverWaitsStep(db, 2), /test failure/);
    assert.deepEqual(actual(), []);
    const state = db.prepare("SELECT cursor,complete FROM session_recover_wait_meta WHERE id=1").get() as {cursor:string|null;complete:number};
    assert.deepEqual([state.cursor, state.complete], [null, 0]);
    db.exec("DROP TRIGGER fail_wait");
    while (!recoverWaitsReady(db)) recoverWaitsStep(db, 2);
    assert.deepEqual(actual(), ["a", "b"]);
  } finally { db.close(); }
});

test("recovery and backfill use the waiting lookup and bounded session seeks", () => {
  const { db } = fixture();
  try {
    installRecoverWaits(db);
    const plan = (sql: string, args: unknown[]) => (db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...(args as never[])) as {detail:string}[]).map((r) => r.detail);
    const steps = plan(RECOVER_WAITS, []);
    assert.ok(steps.some((s) => s.startsWith("SCAN w")), steps.join(" | "));
    assert.ok(steps.some((s) => s.startsWith("SEARCH s USING") && s.includes("key=?")), steps.join(" | "));
    assert.ok(steps.some((s) => s.includes("turns_by_session") && s.includes("session_key=?")), steps.join(" | "));
    assert.ok(steps.every((s) => !s.startsWith("SCAN s") && !s.startsWith("SCAN t")), steps.join(" | "));
    assert.match(RECOVER_BACKFILL_FIRST, /LIMIT \?$/);
    assert.match(RECOVER_BACKFILL_NEXT, /LIMIT \?$/);
    assert.ok(plan(RECOVER_BACKFILL_NEXT, ["a", 64]).some((s) => s.startsWith("SEARCH sessions USING COVERING INDEX")));
  } finally { db.close(); }
});
