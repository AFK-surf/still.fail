import assert from "node:assert/strict";
import { test } from "node:test";
import { working } from "../src/ops/awake.ts";
import { RECOVER_AWAKE_WAITS } from "../src/store/recover-waits.ts";
import { LAST_TURN_OF_SESSION, LIVE_SESSIONS, Store } from "../src/store/store.ts";

test("the periodic awake check does not inspect idle sessions to find a waiting turn", () => {
  const results: { sessions: number; turns: number; candidates: number }[] = [];
  for (const idle of [40, 400]) {
    const store = Store.open(":memory:");
    const db = store.db;
    let sessions = 0, turns = 0, candidates = 0, observing = false;
    db.function("awake_session_seen", (_key) => { if (observing) sessions++; return 1; });
    db.function("awake_turn_seen", (_key) => { if (observing) turns++; return 1; });
    db.function("awake_candidate_seen", (_key) => { if (observing) candidates++; return 1; });
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql === LIVE_SESSIONS) return target.prepare(sql.replace("WHERE archived_at IS NULL", "WHERE awake_session_seen(key) AND archived_at IS NULL"));
        if (sql === LAST_TURN_OF_SESSION) return target.prepare(sql.replace("WHERE s.key = ?", "WHERE awake_turn_seen(s.key) AND s.key = ?"));
        if (sql === RECOVER_AWAKE_WAITS) return target.prepare(sql.replace("WHERE s.archived_at IS NULL", "WHERE awake_candidate_seen(w.session) AND s.archived_at IS NULL"));
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    try {
      const session = db.prepare(`INSERT INTO sessions(key,connect,scope,runtime,profile,workspace,token,created_at,last_active_at)
        VALUES (?,'connected','thread','claude','default','.',?,0,0)`);
      const turn = db.prepare("INSERT INTO turns(id,session_key,kind,started_at,ended_at,outcome,declared,wait_seconds) VALUES (?,?,'user',0,1,'completed',?,600)");
      for (const key of [...Array.from({ length: idle }, (_, i) => `idle-${i}`), "waiting"]) {
        session.run(key, `token-${key}`);
        turn.run(`turn-${key}`, key, key === "waiting" ? "waiting" : "all_done");
      }
      Object.defineProperty(store, "db", { value: observed });
      observing = true;
      assert.equal(working(store, 100_000), true);
      observing = false;
      results.push({ sessions, turns, candidates });
    } finally { store.close(); }
  }
  assert.deepEqual(results, [{ sessions: 0, turns: 0, candidates: 1 }, { sessions: 0, turns: 0, candidates: 1 }]);
});

test("awake waits keep their expiry, latest-turn and old-store behavior", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    store.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "s", createdAt: 1, lastActiveAt: 1 });
    db.prepare("INSERT INTO turns(id,session_key,kind,started_at,ended_at,outcome,declared,wait_seconds) VALUES ('wait','s','user',0,100,'completed','waiting',NULL)").run();
    assert.equal(working(store, 60_099), true);
    assert.equal(working(store, 60_100), false, "the original deadline is exclusive");
    db.prepare("UPDATE turns SET outcome='failed',detail='other: interrupted' WHERE id='wait'").run();
    assert.equal(working(store, 101), true, "awake also follows a recorded wait from an unsuccessful turn");
    db.prepare("UPDATE turns SET ended_at=NULL WHERE id='wait'").run();
    assert.equal(working(store, 101), false, "an unended turn is not a recorded wait");
    db.prepare("UPDATE turns SET ended_at=100 WHERE id='wait'").run();
    db.prepare("INSERT INTO turns(id,session_key,kind,started_at,ended_at,outcome,declared) VALUES ('done','s','user',1,100,'completed','all_done')").run();
    assert.equal(working(store, 101), false, "a wait in history no longer keeps the station awake");
    db.prepare("DELETE FROM turns WHERE id='done'").run();
    db.exec("DELETE FROM session_recover_waits; UPDATE session_recover_wait_meta SET cursor=NULL,complete=0 WHERE id=1");
    assert.equal(working(store, 101), true, "the old scan remains available until preparation finishes");
  } finally { store.close(); }
});

test("a running job still checks a waiting last turn of its archived session", () => {
  const store = Store.open(":memory:");
  try {
    const db = store.db;
    store.insertSession({ key: "archived", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "archived", createdAt: 1, lastActiveAt: 1 });
    db.prepare("INSERT INTO turns(id,session_key,kind,started_at,ended_at,outcome,declared,wait_seconds) VALUES ('wait','archived','user',0,1,'completed','waiting',20000)").run();
    db.prepare("UPDATE sessions SET archived_at=1 WHERE key='archived'").run();
    store.insertJob({ id: "job", sessionKey: "archived", name: "work", command: "true", cwd: "/", port: null, token: "job", state: "running", pgid: null, exitCode: null, startedAt: 0, endedAt: null, restarts: 0, log: "/dev/null", watch: false });
    assert.equal(working(store, 10_000_000), true, "the long wait counts even when the job is too old to count alone");
    db.prepare("UPDATE turns SET wait_seconds=1 WHERE id='wait'").run();
    assert.equal(working(store, 10_000_000), false);
  } finally { store.close(); }
});
