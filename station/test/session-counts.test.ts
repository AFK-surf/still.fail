import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { DatabaseSync } from "node:sqlite";
import { overview } from "../src/api/overview.ts";
import { buildSessionCounts } from "../src/sessions/session-count-builder.ts";
import { installSessionCounts, sessionCountsReady, sessionCountsStep, SESSION_COUNT_TOTAL } from "../src/store/session-counts.ts";
import { Store } from "../src/store/store.ts";

function withoutCounts(db: DatabaseSync) {
  for (const row of db.prepare("SELECT name FROM sqlite_master WHERE type='trigger' AND name LIKE 'session_count_%'").all() as { name: string }[]) {
    db.exec(`DROP TRIGGER ${row.name}`);
  }
  db.exec("DROP TABLE session_count_seen; DROP TABLE session_count_replaced; DROP TABLE session_count_groups; DROP TABLE session_count_totals; DROP TABLE session_count_meta");
}

function fixture(store = Store.open(":memory:")) {
  const db = store.db;
  const add = (key: string, connect: string, ws: string | null, token = key) => store.insertSession({
    key, connect, runtime: "claude", profile: "cc", workspace: "/w", token, createdAt: 1, lastActiveAt: 1, ws,
  });
  const exact = () => {
    const original = db.prepare("SELECT connect, ws, COUNT(*) AS n FROM sessions GROUP BY connect, ws ORDER BY connect, ws").all();
    assert.deepEqual(store.sessionCounts(), original.map((row) => ({ connect: row.connect, ws: row.ws, n: row.n })));
  };
  return { store, db, add, exact };
}

for (const recursive of [false, true]) test(`session totals follow old writers and replacements (recursive triggers ${recursive})`, () => {
  const { store, db, add, exact } = fixture();
  try {
    db.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    add("a", "x", null); add("b", "x", ""); add("c", "y", "mine"); exact();
    db.exec("UPDATE sessions SET ws='mine', connect='y' WHERE key='a'"); exact();
    db.exec("UPDATE sessions SET last_active_at=9 WHERE key='b'"); exact();
    db.exec("DELETE FROM sessions WHERE key='c'"); exact();
    add("token-owner", "x", "mine", "shared-token");
    db.exec("INSERT OR IGNORE INTO sessions (key,connect,scope,runtime,profile,workspace,token,created_at,last_active_at,ws) VALUES ('ignored','y','thread','claude','cc','/w','shared-token',1,1,NULL)"); exact();
    db.exec("INSERT OR REPLACE INTO sessions (key,connect,scope,runtime,profile,workspace,token,created_at,last_active_at,ws) VALUES ('replacement','y','thread','claude','cc','/w','shared-token',1,1,NULL)"); exact();
    add("rowid-owner", "x", "mine");
    const id = db.prepare("SELECT rowid AS id FROM sessions WHERE key='rowid-owner'").get()!.id;
    db.prepare("INSERT OR REPLACE INTO sessions (rowid,key,connect,scope,runtime,profile,workspace,token,created_at,last_active_at,ws) VALUES (?,'rowid-new','y','thread','claude','cc','/w','rowid-new',1,1,'other')").run(id); exact();
    add("target", "x", "mine");
    const target = db.prepare("SELECT rowid AS id FROM sessions WHERE key='target'").get()!.id;
    db.prepare("UPDATE OR REPLACE sessions SET rowid=?, connect='x', ws='mine' WHERE key='rowid-new'").run(target); exact();
    db.exec("UPDATE OR REPLACE sessions SET token='shared-token' WHERE key='rowid-new'"); exact();
    db.exec("UPDATE OR REPLACE sessions SET key='b' WHERE key='rowid-new'"); exact();
  } finally { store.close(); }
});

test("an old store is counted in bounded steps as sessions change", () => {
  const { store, db, add, exact } = fixture();
  try {
    withoutCounts(db);
    for (let i = 0; i < 8; i++) add(`old-${i}`, i % 2 ? "x" : "y", i % 3 ? "mine" : null);
    installSessionCounts(db);
    assert.equal(sessionCountsReady(db), false);
    assert.throws(() => store.sessionCounts(), /not ready/);
    assert.deepEqual(sessionCountsStep(db, 2), { done: false, visited: 2 });
    db.exec("UPDATE sessions SET rowid=2000, ws='other' WHERE key='old-3'");
    db.exec("UPDATE sessions SET rowid=-2, connect='x' WHERE key='old-4'");
    db.exec("DELETE FROM sessions WHERE key='old-5'");
    add("new", "x", "mine");
    let steps = 0;
    while (!sessionCountsReady(db)) {
      assert.ok(sessionCountsStep(db, 2).visited <= 2);
      assert.ok(++steps < 10);
    }
    exact();
    assert.deepEqual(sessionCountsStep(db, 2), { done: true, visited: 0 });
  } finally { store.close(); }
});

test("a failed session count batch rolls back its counts and cursor", () => {
  const { store, db, add, exact } = fixture();
  try {
    withoutCounts(db);
    add("one", "x", "mine"); add("two", "x", "mine");
    installSessionCounts(db);
    db.exec("CREATE TRIGGER fail_second_count BEFORE INSERT ON session_count_seen WHEN NEW.session='two' BEGIN SELECT RAISE(ABORT, 'stopped'); END");
    assert.throws(() => sessionCountsStep(db, 8), /stopped/);
    assert.equal(db.prepare("SELECT count(*) AS n FROM session_count_seen").get()!.n, 0);
    assert.equal(db.prepare("SELECT last_rowid FROM session_count_meta").get()!.last_rowid, null);
    db.exec("DROP TRIGGER fail_second_count");
    assert.deepEqual(sessionCountsStep(db, 8), { done: true, visited: 2 });
    exact();
  } finally { store.close(); }
});

test("an incompatible session count index is neither read nor built", () => {
  const { store, db, add } = fixture();
  try {
    add("one", "x", "mine");
    db.exec("UPDATE session_count_meta SET version=2");
    assert.throws(() => store.overviewSessionCounts({ workspace: "mine" }, ["x"]), /session count.*version/i);
    assert.throws(() => sessionCountsStep(db), /session count.*version/i);
    assert.throws(() => installSessionCounts(db), /session count.*version/i);
  } finally { store.close(); }
});

test("new sessions do not keep an old count scan open", () => {
  const { store, db, add, exact } = fixture();
  try {
    withoutCounts(db);
    for (let i = 0; i < 8; i++) add(`old-${i}`, "x", "mine");
    installSessionCounts(db);
    let steps = 0;
    while (!sessionCountsReady(db)) {
      sessionCountsStep(db, 2);
      for (let i = 0; i < 20; i++) add(`new-${steps}-${i}`, "other", "elsewhere");
      assert.ok(++steps <= 5, "new rowids cannot extend the old scan");
    }
    exact();
  } finally { store.close(); }
});

test("old session rowids beyond JavaScript's safe integer range do not prevent counting", () => {
  const { store, db, exact } = fixture();
  try {
    withoutCounts(db);
    const put = db.prepare("INSERT INTO sessions (rowid,key,connect,scope,runtime,profile,workspace,token,created_at,last_active_at,ws) VALUES (?,?,'x','thread','claude','cc','/w',?,1,1,'mine')");
    put.run(-9007199254740993n, "negative", "negative");
    put.run(9007199254740993n, "positive", "positive");
    installSessionCounts(db);
    assert.deepEqual(sessionCountsStep(db, 1), { done: false, visited: 1 });
    assert.deepEqual(sessionCountsStep(db, 1), { done: false, visited: 1 });
    assert.deepEqual(sessionCountsStep(db, 1), { done: true, visited: 0 });
    exact();
  } finally { store.close(); }
});

test("the count builder waits for handover and resumes after reopening", async () => {
  const dir = mkdtempSync(join(tmpdir(), "session-counts-"));
  const path = join(dir, "station.db");
  let store = Store.open(path);
  let builder: ReturnType<typeof buildSessionCounts> | null = null;
  try {
    withoutCounts(store.db);
    const { add } = fixture(store);
    for (let i = 0; i < 130; i++) add(`old-${i}`, "x", "mine");
    installSessionCounts(store.db);
    assert.deepEqual(sessionCountsStep(store.db, 1), { done: false, visited: 1 });
    store.close();
    store = Store.open(path);
    const previous = Promise.withResolvers<void>();
    builder = buildSessionCounts(store, previous.promise);
    let settled = false;
    void builder.ready.then(() => { settled = true; });
    await Promise.resolve();
    assert.equal(settled, false);
    previous.resolve();
    assert.equal(await builder.ready, true);
    assert.deepEqual(store.sessionCounts(), [{ connect: "x", ws: "mine", n: 130 }]);
  } finally { await builder?.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("closing the count builder releases an overview waiting for handover", async () => {
  const { store, db, add } = fixture();
  try {
    withoutCounts(db);
    add("one", "x", "mine");
    installSessionCounts(db);
    const previous = Promise.withResolvers<void>();
    const builder = buildSessionCounts(store, previous.promise);
    await builder.close();
    assert.equal(await builder.ready, false);
    previous.resolve();
  } finally { store.close(); }
});

test("an old overview waits for complete counts after handover", async () => {
  const { store, db, add } = fixture();
  let builder: ReturnType<typeof buildSessionCounts> | null = null;
  try {
    withoutCounts(db);
    add("old", "x", "mine");
    installSessionCounts(db);
    const previous = Promise.withResolvers<void>();
    builder = buildSessionCounts(store, previous.promise);
    const hub: any = { processes: () => [], config: () => ({ dataDir: "/" }), waitForSessionCounts: () => builder!.ready };
    const viewer = { sub: "s", email: "p@example.test", name: "P", role: "member" as const,
      workspace: "mine", device: "d", home: false };
    let settled = false;
    const answer = overview({ store, hub, cloud: { state: null } as any,
      config: () => ({ connects: [{ id: "x", workspace: "mine" }] }) }, viewer, "en");
    void answer.then(() => { settled = true; });
    await Promise.resolve();
    assert.equal(settled, false);
    previous.resolve();
    const result: any = await answer;
    assert.equal(result.counts.sessions, 1);
    assert.equal(result.connects[0].sessions, 1);
  } finally { await builder?.close(); store.close(); }
});

test("an overview's workspace and connection totals use one snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "session-count-snapshot-"));
  const path = join(dir, "station.db");
  const { store, db, add } = fixture(Store.open(path));
  const writer = new DatabaseSync(path);
  try {
    add("one", "x", "mine");
    let changed = false;
    Object.defineProperty(store, "db", { configurable: true, value: new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => {
          const statement = target.prepare(sql);
          if (sql !== SESSION_COUNT_TOTAL) return statement;
          return new Proxy(statement, { get(s, p) {
            if (p === "get") return (...args: any[]) => {
              const row = (s.get as any)(...args);
              if (!changed) { changed = true; writer.exec("UPDATE sessions SET connect='y' WHERE key='one'"); }
              return row;
            };
            const value = Reflect.get(s, p, s);
            return typeof value === "function" ? value.bind(s) : value;
          } });
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    }) });
    const viewer = { workspace: "mine", home: false };
    const before = store.overviewSessionCounts(viewer, ["x", "y"])!;
    assert.equal(before.total, 1);
    assert.deepEqual([...before.byConnect], [["x", 1], ["y", 0]]);
    const after = store.overviewSessionCounts(viewer, ["x", "y"])!;
    assert.equal(after.total, 1);
    assert.deepEqual([...after.byConnect], [["x", 0], ["y", 1]]);
  } finally { writer.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});
