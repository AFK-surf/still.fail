import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { AWAKE_BACKFILL_NEXT, AWAKE_WAIT_STATUS, awakeWaitsReady, awakeWaitsStep } from "../src/store/awake-waits.ts";
import { installRecoverWaits, recoverWaitsReady, recoverWaitsStep } from "../src/store/recover-waits.ts";

function fixture(path = ":memory:") {
  const db = new DatabaseSync(path);
  db.exec(`CREATE TABLE sessions (key TEXT PRIMARY KEY, token TEXT NOT NULL UNIQUE, running INTEGER NOT NULL DEFAULT 0,
      archived_at INTEGER, last_active_at INTEGER NOT NULL);
    CREATE TABLE turns (id TEXT PRIMARY KEY, session_key TEXT NOT NULL, started_at INTEGER NOT NULL, ended_at INTEGER,
      outcome TEXT, detail TEXT, declared TEXT, wait_seconds INTEGER);
    CREATE INDEX turns_by_session ON turns (session_key, started_at);`);
  const addSession = db.prepare("INSERT INTO sessions(key,token,last_active_at) VALUES (?,?,0)");
  const addTurn = db.prepare("INSERT INTO turns(id,session_key,started_at,ended_at,outcome,declared,wait_seconds) VALUES (?,?,?,?,'completed','waiting',?)");
  const session = (key: string) => addSession.run(key, key);
  const turn = (id: string, key: string, start = 1, end = 10, seconds: number | null = 1) => addTurn.run(id, key, start, end, seconds);
  const actual = () => db.prepare("SELECT session,deadline FROM session_awake_deadlines ORDER BY session").all();
  const expected = () => db.prepare(`SELECT s.key AS session, t.ended_at + COALESCE(t.wait_seconds, 0) * 1000 AS deadline
    FROM sessions s CROSS JOIN turns t ON t.rowid = (SELECT rowid FROM turns INDEXED BY turns_by_session
      WHERE session_key=s.key ORDER BY started_at DESC,rowid DESC LIMIT 1)
    WHERE s.archived_at IS NULL AND s.running != 1 AND t.ended_at IS NOT NULL AND t.declared='waiting' ORDER BY s.key`).all();
  return { db, session, turn, actual, expected };
}

test("an old recovery lookup is prepared in bounded resumable batches while waits change", () => {
  const { db, session, turn, actual, expected } = fixture();
  try {
    for (const key of ["a", "b", "c", "d"]) { session(key); turn(`turn-${key}`, key); }
    installRecoverWaits(db);
    while (!recoverWaitsReady(db)) recoverWaitsStep(db, 2);
    assert.equal(awakeWaitsReady(db), false);
    assert.deepEqual(awakeWaitsStep(db, 2), { done: false, visited: 2 });
    db.prepare("UPDATE turns SET wait_seconds=8 WHERE id='turn-a'").run();
    db.prepare("UPDATE sessions SET archived_at=1 WHERE key='c'").run();
    db.prepare("UPDATE turns SET declared='all_done' WHERE id='turn-d'").run();
    session("aa"); turn("turn-aa", "aa", 1, 10, 7);
    installRecoverWaits(db);
    while (!awakeWaitsReady(db)) assert.ok(awakeWaitsStep(db, 2).visited <= 2);
    assert.deepEqual(actual(), expected());
    assert.deepEqual(awakeWaitsStep(db, 2), { done: true, visited: 0 });
  } finally { db.close(); }
});

test("a failed expiry batch rolls its entries and cursor back together", () => {
  const { db, session, turn, actual, expected } = fixture();
  try {
    session("a"); session("b"); turn("a", "a"); turn("b", "b");
    installRecoverWaits(db);
    while (!recoverWaitsReady(db)) recoverWaitsStep(db, 2);
    db.exec("UPDATE session_recover_waits SET awake_deadline=NULL");
    db.exec("CREATE TRIGGER fail_expiry BEFORE INSERT ON session_awake_deadlines WHEN NEW.session='b' BEGIN SELECT RAISE(ABORT,'test failure'); END");
    assert.throws(() => awakeWaitsStep(db, 2), /test failure/);
    assert.deepEqual(actual(), []);
    const state = db.prepare("SELECT cursor,complete FROM session_awake_wait_meta WHERE id=1").get() as {cursor:string|null;complete:number};
    assert.deepEqual([state.cursor, state.complete], [null, 0]);
    db.exec("DROP TRIGGER fail_expiry");
    while (!awakeWaitsReady(db)) awakeWaitsStep(db, 2);
    assert.deepEqual(actual(), expected());
  } finally { db.close(); }
});

test("an existing recovery lookup is upgraded while the previous station keeps writing", async () => {
  const { mkdtempSync, rmSync } = await import("node:fs");
  const { tmpdir } = await import("node:os");
  const { join } = await import("node:path");
  const dir = mkdtempSync(join(tmpdir(), "awake-previous-writer-"));
  const path = join(dir, "station.db");
  const { db, session, turn, actual, expected } = fixture(path);
  const old = new DatabaseSync(path);
  try {
    session("a"); session("b"); session("c"); turn("a", "a"); turn("b", "b"); turn("c", "c");
    db.exec(`CREATE TABLE session_recover_waits (session TEXT PRIMARY KEY) WITHOUT ROWID;
      CREATE TABLE session_recover_turn_stage (session TEXT PRIMARY KEY) WITHOUT ROWID;
      CREATE TABLE session_recover_session_stage (session TEXT PRIMARY KEY) WITHOUT ROWID;
      CREATE TABLE session_recover_wait_meta (id INTEGER PRIMARY KEY, cursor TEXT, complete INTEGER NOT NULL);
      INSERT INTO session_recover_wait_meta VALUES (1, NULL, 1);
      INSERT INTO session_recover_waits VALUES ('a'), ('b');`);
    const oldWrite = old.prepare("UPDATE turns SET wait_seconds=? WHERE id=?");
    const oldArchive = old.prepare("UPDATE sessions SET archived_at=? WHERE key=?");
    const oldBackfill = old.prepare("INSERT INTO session_recover_waits(session) VALUES (?)");
    installRecoverWaits(db);
    assert.equal(awakeWaitsReady(db), false);
    assert.deepEqual(awakeWaitsStep(db, 1), { done: false, visited: 1 });
    oldWrite.run(15, "a");
    oldArchive.run(1, "b");
    oldBackfill.run("c");
    while (!awakeWaitsReady(db)) awakeWaitsStep(db, 1);
    assert.deepEqual(actual(), expected());
    oldArchive.run(null, "b");
    oldWrite.run(20, "b");
    assert.deepEqual(actual(), expected());
  } finally { old.close(); db.close(); rmSync(dir, { recursive: true, force: true }); }
});

for (const recursive of [false, true]) test(`expiry follows replacement and ignored writes (recursive triggers ${recursive})`, () => {
  const { db, session, turn, actual, expected } = fixture();
  try {
    db.exec(`PRAGMA recursive_triggers=${recursive ? "ON" : "OFF"}`);
    installRecoverWaits(db);
    session("a"); session("b"); session("c");
    turn("a-old", "a", 0, 10, 1); turn("x", "a", 1, 10, 50); turn("y", "b", 1, 10, 200);
    const check = () => assert.deepEqual(actual(), expected());
    check();
    db.prepare("INSERT OR IGNORE INTO turns VALUES ('x','b',2,10,'completed',NULL,'waiting',5)").run(); check();
    db.prepare("INSERT OR REPLACE INTO turns VALUES ('x','b',2,10,'completed',NULL,'waiting',5)").run(); check();
    db.prepare("UPDATE OR REPLACE turns SET id='x' WHERE id='a-old'").run(); check();
    db.prepare("INSERT OR REPLACE INTO sessions(key,token,last_active_at) VALUES ('c','a',0)").run(); check();
    db.prepare("INSERT INTO sessions(key,token,last_active_at) VALUES ('a','a-again',0)").run(); check();
  } finally { db.close(); }
});

test("expiry agrees with the latest turn across changing sessions and turns", () => {
  for (const seed of [1, 9, 73]) {
    const { db, session, actual, expected } = fixture();
    try {
      installRecoverWaits(db);
      for (let i = 0; i < 12; i++) session(`s${i}`);
      let state = seed;
      const random = (n: number) => { state = (Math.imul(state, 1664525) + 1013904223) >>> 0; return Math.floor(state / 0x100000000 * n); };
      const put = db.prepare("INSERT OR REPLACE INTO turns VALUES (?,?,?,?,?,?,?,?)");
      const change = db.prepare("UPDATE turns SET session_key=?,started_at=?,ended_at=?,outcome=?,detail=?,declared=?,wait_seconds=? WHERE id=?");
      for (let i = 0; i < 250; i++) {
        const id = `t${random(28)}`, key = `s${random(12)}`;
        const values = [key, random(5), random(4) === 0 ? null : random(200), random(2) === 0 ? "failed" : "completed",
          [null, "rate_limit:tomorrow", "other"][random(3)], [null, "waiting", "all_done"][random(3)], random(4) === 0 ? null : random(300)] as const;
        switch (random(6)) {
          case 0: put.run(id, ...values); break;
          case 1: change.run(...values, id); break;
          case 2: db.prepare("DELETE FROM turns WHERE id=?").run(id); break;
          case 3: db.prepare("UPDATE sessions SET archived_at=? WHERE key=?").run(random(2) ? 1 : null, key); break;
          case 4: db.prepare("UPDATE sessions SET running=? WHERE key=?").run(random(2), key); break;
          case 5: db.prepare("UPDATE turns SET wait_seconds=? WHERE id=?").run(random(300), id); break;
        }
        assert.deepEqual(actual(), expected(), `seed ${seed}, mutation ${i}`);
        const now = random(400_000);
        const state = db.prepare(AWAKE_WAIT_STATUS).get(now - 60_000) as { uncertain: number; awake: number };
        const original = (expected() as {deadline: number}[]).some(({ deadline }) => now < deadline + 60_000);
        assert.equal(state.uncertain, 0);
        assert.equal(state.awake === 1, original, `seed ${seed}, mutation ${i}, now ${now}`);
      }
    } finally { db.close(); }
  }
});

test("awake queries seek by deadline and backfill seeks by recovery session", () => {
  const { db } = fixture();
  try {
    installRecoverWaits(db);
    const plan = (sql: string, ...args: unknown[]) => (db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...(args as never[])) as {detail:string}[]).map((r) => r.detail).join(" | ");
    const status = plan(AWAKE_WAIT_STATUS, 100);
    assert.match(status, /SEARCH session_awake_deadlines USING PRIMARY KEY.*deadline>\?/);
    assert.match(status, /SEARCH session_awake_deadlines USING PRIMARY KEY.*deadline=\?/);
    assert.match(plan(AWAKE_BACKFILL_NEXT, "a", 64), /SEARCH session_recover_waits USING PRIMARY KEY.*session>\?/);
  } finally { db.close(); }
});
