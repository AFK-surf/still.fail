import assert from "node:assert/strict";
import { test } from "node:test";
import { Hub } from "../src/sessions/hub.ts";
import { LAST_TURN_OF_SESSION, LIVE_SESSIONS, Store } from "../src/store/store.ts";

test("restart recovery does not inspect idle sessions to find waits", async () => {
  const results: { sessions: number; turns: number }[] = [];
  for (const idle of [40, 400]) {
    const store = Store.open(":memory:");
    const db = store.db;
    let sessions = 0, turns = 0, observing = false;
    db.function("recovery_session_seen", (_key) => { if (observing) sessions++; return 1; });
    db.function("recovery_turn_seen", (_key) => { if (observing) turns++; return 1; });
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql === LIVE_SESSIONS) return target.prepare(sql.replace("WHERE archived_at IS NULL", "WHERE recovery_session_seen(key) AND archived_at IS NULL"));
        if (sql === LAST_TURN_OF_SESSION) return target.prepare(sql.replace("WHERE s.key = ?", "WHERE recovery_turn_seen(s.key) AND s.key = ?"));
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    try {
      const addSession = db.prepare(`INSERT INTO sessions(key,connect,scope,runtime,profile,workspace,token,created_at,last_active_at)
        VALUES (?,'connected','thread','claude','default','.',?,0,0)`);
      const addTurn = db.prepare("INSERT INTO turns(id,session_key,kind,started_at,ended_at,outcome,declared) VALUES (?,?,'user',0,1,'completed',?)");
      for (const key of [...Array.from({ length: idle }, (_, i) => `idle-${i}`), "waiting"]) {
        addSession.run(key, `token-${key}`);
        addTurn.run(`turn-${key}`, key, key === "waiting" ? "waiting" : "all_done");
      }
      Object.defineProperty(store, "db", { value: observed });
      const resumed: string[] = [];
      const hub = Object.assign(Object.create(Hub.prototype), {
        adopted: new Set(), store,
        chatOf: () => ({}),
        actor: (r: { key: string }) => ({ takeWait: () => { resumed.push(r.key); }, takeRefill: () => {} }),
      });
      observing = true;
      await hub.recover();
      observing = false;
      assert.deepEqual(resumed, ["waiting"]);
      results.push({ sessions, turns });
    } finally { store.close(); }
  }
  for (const result of results) {
    assert.ok(result.sessions <= 1, `idle sessions were read: ${result.sessions}`);
    assert.ok(result.turns <= 1, `idle turns were read: ${result.turns}`);
  }
});
