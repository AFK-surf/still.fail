import assert from "node:assert/strict";
import { test } from "node:test";
import { RECOVER_AWAKE_WAITS } from "../src/store/recover-waits.ts";
import { AWAKE_WAIT_STATUS } from "../src/store/awake-waits.ts";
import { Store } from "../src/store/store.ts";

for (const current of [false, true]) test(`the awake check does not inspect expired waits (${current ? "one current wait" : "no current wait"})`, () => {
  const candidates: number[] = [];
  for (const expired of [40, 400]) {
    const store = Store.open(":memory:");
    const db = store.db;
    let seen = 0;
    db.function("expired_wait_seen", () => { seen++; return 1; });
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => target.prepare(sql === RECOVER_AWAKE_WAITS
        ? sql.replace("WHERE s.archived_at IS NULL", "WHERE expired_wait_seen() AND s.archived_at IS NULL")
        : sql === AWAKE_WAIT_STATUS ? sql.replace("WHERE deadline > ?", "WHERE deadline > ? AND expired_wait_seen()") : sql);
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    try {
      const session = db.prepare(`INSERT INTO sessions(key,connect,scope,runtime,profile,workspace,token,created_at,last_active_at)
        VALUES (?,'connected','thread','claude','default','.',?,0,0)`);
      const turn = db.prepare("INSERT INTO turns(id,session_key,kind,started_at,ended_at,outcome,declared,wait_seconds) VALUES (?,?,'user',0,1,'completed','waiting',?)");
      for (let i = 0; i < expired; i++) {
        const key = `expired-${i}`;
        session.run(key, `token-${key}`);
        turn.run(`turn-${key}`, key, 1);
      }
      if (current) { session.run("current", "token-current"); turn.run("turn-current", "current", 600); }
      Object.defineProperty(store, "db", { value: observed });
      assert.equal(store.awakeWait(100_000, 60_000), current);
      candidates.push(seen);
    } finally { store.close(); }
  }
  assert.deepEqual(candidates, current ? [1, 1] : [0, 0]);
});

test("unusual old wait values keep the original JavaScript deadline rule", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    store.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "s", createdAt: 1, lastActiveAt: 1 });
    db.prepare("INSERT INTO turns(id,session_key,kind,started_at,ended_at,outcome,declared,wait_seconds) VALUES ('t','s','user',0,100,'completed','waiting',0.5)").run();
    assert.equal(store.awakeWait(60_599, 60_000), true);
    assert.equal(store.awakeWait(60_600, 60_000), false);
    db.prepare("UPDATE turns SET wait_seconds='not a number' WHERE id='t'").run();
    assert.equal(store.awakeWait(101, 60_000), false);
    db.prepare("UPDATE turns SET wait_seconds=1 WHERE id='t'").run();
    assert.equal(store.awakeWait(61_099, 60_000), true);
    assert.equal(store.awakeWait(61_100, 60_000), false);
  } finally { store.close(); }
});

test("the deadline decision uses one snapshot while the previous station changes a wait", async () => {
  const { DatabaseSync } = await import("node:sqlite");
  const { mkdtempSync, rmSync } = await import("node:fs");
  const { tmpdir } = await import("node:os");
  const { join } = await import("node:path");
  const dir = mkdtempSync(join(tmpdir(), "awake-deadline-snapshot-"));
  const path = join(dir, "station.db");
  const store = Store.open(path);
  const old = new DatabaseSync(path);
  const db = store.db;
  try {
    store.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "s", createdAt: 1, lastActiveAt: 1 });
    db.prepare("INSERT INTO turns(id,session_key,kind,started_at,ended_at,outcome,declared,wait_seconds) VALUES ('t','s','user',0,100,'completed','waiting',1)").run();
    let changed = false;
    db.function("change_wait_during_read", () => {
      if (!changed) { changed = true; old.prepare("UPDATE turns SET wait_seconds=0.5 WHERE id='t'").run(); }
      return 0;
    });
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => target.prepare(sql === AWAKE_WAIT_STATUS
        ? sql.replace(/ AS uncertain,\s*EXISTS/, " AS uncertain, change_wait_during_read() AS changed, EXISTS") : sql);
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    Object.defineProperty(store, "db", { value: observed });
    assert.equal(store.awakeWait(60_599, 60_000), true);
    assert.equal(changed, true);
    assert.equal(store.awakeWait(60_600, 60_000), false);
  } finally { old.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});
