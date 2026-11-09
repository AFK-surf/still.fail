import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { LATEST_NAMING_ORIGIN, LATEST_NAMING_ORIGIN_POSSIBLE, LATEST_NAMING_ORIGIN_PREPARED, latestNamingOrigins, makeStore } from "../src/read/store.ts";
import { CcIndexPreparation, ccSessionReady } from "../src/store/cc-thread-index.ts";
import { Store, newMessage } from "../src/store/store.ts";

const session = (s: Store, key: string) => s.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key,
  createdAt: 1, lastActiveAt: 1, createdBy: "ann@x" });

const prepare = (s: Store, key: string) => {
  const work = new CcIndexPreparation();
  let steps = 0;
  while (!ccSessionReady(s.db, key)) { work.step(s.db, key, 64); assert.ok(++steps < 20_000); }
};

const ownChats = (s: Store, key: string, count = 9) => {
  const thread = s.db.prepare("INSERT INTO threads (surface,channel,thread_ts,created_at) VALUES ('ember','C',?,1)");
  const member = s.db.prepare("INSERT INTO thread_sessions (thread,session,connect,joined_at) VALUES (?,?,'ember',1)");
  s.db.exec("BEGIN IMMEDIATE");
  for (let i = 0; i < count; i++) member.run(thread.run(`${key}-own-${i}`).lastInsertRowid, key);
  s.db.exec("COMMIT");
};

const origin = (s: Store, key: string, name: string, at: number) => {
  const thread = s.openThread("slack:one", "C", name, null, "ann@x");
  s.joinThread(thread.id, key, "one");
  s.insertMessage({ ...newMessage(thread.id, name, "person", "ann@x", name), at });
  return thread.id;
};

for (const own of [40, 400, 4000]) for (const external of [0, 1])
  test(`a prepared latest origin ignores ${own} unrelated Station chats with ${external} external origins`, () => {
    const s = Store.open(":memory:");
    try {
      session(s, "member");
      const thread = s.db.prepare("INSERT INTO threads (surface,channel,thread_ts,created_at) VALUES ('ember','C',?,1)");
      const member = s.db.prepare("INSERT INTO thread_sessions (thread,session,connect,joined_at) VALUES (?,'member','ember',1)");
      s.db.exec("BEGIN IMMEDIATE");
      for (let i=0; i<own; i++) member.run(thread.run(`own-${i}`).lastInsertRowid);
      s.db.exec("COMMIT");
      const origin = external ? s.openThread("slack:one", "C", "origin", null, "ann@x") : null;
      if (origin) {
        s.joinThread(origin.id, "member", "one");
        s.insertMessage({ ...newMessage(origin.id, "origin", "person", "ann@x", "hello"), at: 2 });
      }
      prepare(s, "member");
      let oldVisits = 0, possibleVisits = 0;
      s.db.function("visit_old_latest_origin", (value) => { oldVisits++; return value; });
      s.db.function("visit_possible_latest_origin", (value) => { possibleVisits++; return value; });
      const observed = new Proxy(s.db, { get(target, property) {
        if (property === "prepare") return (sql: string) => {
          if (sql === LATEST_NAMING_ORIGIN_POSSIBLE) {
            const traced = sql.replace("WHERE session=c.session LIMIT",
              "WHERE session=c.session AND visit_possible_latest_origin(rowid)=rowid LIMIT");
            assert.notEqual(traced, sql);
            const statement = target.prepare(traced);
            return new Proxy(statement, { get(stmt, method) {
              if (method === "all") return (...args: any[]) => {
                const plan = (text: string) => target.prepare(`EXPLAIN QUERY PLAN ${text}`).all(...args).map((r) => r.detail);
                assert.deepEqual(plan(traced), plan(sql));
                return stmt.all(...args);
              };
              const value = Reflect.get(stmt, method, stmt);
              return typeof value === "function" ? value.bind(stmt) : value;
            } });
          }
          if (sql !== LATEST_NAMING_ORIGIN) return target.prepare(sql);
          const traced = sql.replace("m.session = requested.value AND t.surface",
            "m.session = requested.value AND visit_old_latest_origin(m.thread) = m.thread AND t.surface");
          assert.notEqual(traced, sql);
          const statement = target.prepare(traced);
          return new Proxy(statement, { get(stmt, method) {
            if (method === "all") return (...args: any[]) => {
              const plan = (text: string) => target.prepare(`EXPLAIN QUERY PLAN ${text}`).all(...args).map((r) => r.detail);
              assert.deepEqual(plan(traced), plan(sql));
              return stmt.all(...args);
            };
            const value = Reflect.get(stmt, method, stmt);
            return typeof value === "function" ? value.bind(stmt) : value;
          } });
        };
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      } });
      const changes = s.db.prepare("SELECT total_changes() AS n").get()!.n;
      assert.deepEqual(latestNamingOrigins(makeStore(observed, "."), ["member"]), origin ? [origin.id] : []);
      assert.equal(oldVisits, 0, "the prepared answer must not inspect unrelated source memberships");
      assert.equal(possibleVisits, 9, "classifying the prepared member must stop after nine memberships");
      assert.equal(s.db.prepare("SELECT total_changes() AS n").get()!.n, changes, "the read must not write or prepare an index");
    } finally { s.close(); }
  });

for (const count of [8, 9]) test(`latest origin keeps message order with ${count} prepared external candidates`, () => {
  const s = Store.open(":memory:");
  try {
    session(s, "member"); ownChats(s, "member");
    for (let i = 0; i < count - 1; i++) origin(s, "member", `old-${i}`, i + 1);
    const latest = origin(s, "member", "latest", 100);
    // Copy order uses last entries, including this edit. Naming order must still use message time.
    s.editMessage("slack:one", "C", "old-0", "old-0", "edited");
    prepare(s, "member");
    let candidates = 0, fallback = 0;
    s.db.function("visit_small_latest_origin", (value) => { candidates++; return value; });
    const observed = new Proxy(s.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql === LATEST_NAMING_ORIGIN) {
          const statement = target.prepare(sql);
          return new Proxy(statement, { get(stmt, method) {
            if (method === "all") return (...args: any[]) => { fallback++; return stmt.all(...args); };
            const value = Reflect.get(stmt, method, stmt);
            return typeof value === "function" ? value.bind(stmt) : value;
          } });
        }
        if (sql !== LATEST_NAMING_ORIGIN_PREPARED) return target.prepare(sql);
        const traced = sql.replace("surface != 'ember' LIMIT", "surface != 'ember' AND visit_small_latest_origin(thread) = thread LIMIT");
        assert.notEqual(traced, sql);
        const statement = target.prepare(traced);
        return new Proxy(statement, { get(stmt, method) {
          if (method === "get") return (...args: any[]) => {
            const plan = (text: string) => target.prepare(`EXPLAIN QUERY PLAN ${text}`).all(...args).map((r) => r.detail);
            assert.deepEqual(plan(traced), plan(sql));
            return stmt.get(...args);
          };
          const value = Reflect.get(stmt, method, stmt);
          return typeof value === "function" ? value.bind(stmt) : value;
        } });
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    assert.deepEqual(latestNamingOrigins(makeStore(observed, "."), ["member"]), [latest]);
    assert.equal(candidates, count);
    assert.equal(fallback, count === 9 ? 1 : 0);
  } finally { s.close(); }
});

for (const count of [8, 9]) test(`a large unselected thread id is safe with ${count} external candidates`, () => {
  const s = Store.open(":memory:");
  try {
    session(s, "member"); ownChats(s, "member");
    for (let i = 0; i < count - 2; i++) origin(s, "member", `old-${i}`, i + 1);
    const latest = origin(s, "member", "latest", 100);
    // Keep the id inside SQLite: exposing an unselected 64-bit value to Node's number conversion would throw.
    s.db.exec(`INSERT INTO threads(id,surface,channel,thread_ts,created_at)
      VALUES(9007199254740993,'slack:one','C','large-id',1);
      INSERT INTO thread_sessions(thread,session,connect,joined_at)
      VALUES(9007199254740993,'member','one',1);`);
    prepare(s, "member");
    assert.deepEqual(latestNamingOrigins(makeStore(s.db, "."), ["member"]), [latest]);
  } finally { s.close(); }
});

test("prepared, missing and unprepared members retain their requested order and duplicates", () => {
  const s = Store.open(":memory:");
  try {
    for (const key of ["prepared", "unprepared", "helper"]) session(s, key);
    ownChats(s, "prepared");
    const first = origin(s, "prepared", "first", 10);
    const second = origin(s, "unprepared", "second", 20);
    const shared = origin(s, "missing", "shared", 30);
    s.joinThread(shared, "helper", "one");
    origin(s, "missing-only", "missing-only", 40);
    prepare(s, "prepared"); prepare(s, "missing"); prepare(s, "missing-only");
    assert.deepEqual(latestNamingOrigins(makeStore(s.db, "."), ["prepared", "missing", "prepared", "missing-only", "unprepared"]),
      [first, shared, first, second]);
  } finally { s.close(); }
});

test("a changed source with a dirty prepared index uses the current origin", () => {
  const s = Store.open(":memory:");
  try {
    session(s, "member"); ownChats(s, "member");
    const first = origin(s, "member", "first", 10); prepare(s, "member");
    assert.deepEqual(latestNamingOrigins(makeStore(s.db, "."), ["member"]), [first]);
    const second = origin(s, "member", "second", 20);
    assert.equal(ccSessionReady(s.db, "member"), false);
    assert.deepEqual(latestNamingOrigins(makeStore(s.db, "."), ["member"]), [second]);
  } finally { s.close(); }
});

for (const dropped of ["TABLE cc_index_meta", "INDEX thread_sessions_session"]) test(`latest origin works without ${dropped}`, () => {
  const s = Store.open(":memory:");
  try {
    session(s, "member");
    const expected = origin(s, "member", "origin", 10);
    s.db.exec(`DROP ${dropped}`);
    assert.deepEqual(latestNamingOrigins(makeStore(s.db, "."), ["member"]), [expected]);
  } finally { s.close(); }
});

test("a nullable legacy surface remains an external origin", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(`CREATE TABLE sessions(key TEXT PRIMARY KEY);
      CREATE TABLE threads(id INTEGER PRIMARY KEY,surface TEXT,created_at INTEGER);
      CREATE TABLE thread_sessions(thread INTEGER,session TEXT,PRIMARY KEY(thread,session));
      CREATE TABLE thread_state(thread INTEGER PRIMARY KEY,said_n INTEGER);
      CREATE TABLE entries(thread INTEGER,n INTEGER,kind TEXT,at INTEGER,PRIMARY KEY(thread,n));
      INSERT INTO sessions VALUES('member'); INSERT INTO threads VALUES(1,NULL,1);
      INSERT INTO thread_sessions VALUES(1,'member');`);
    assert.deepEqual(latestNamingOrigins({ db } as ReturnType<typeof makeStore>, ["member"]), [1]);
  } finally { db.close(); }
});

for (const key of ["会话🔑", "member\0suffix"]) test(`a prepared latest origin retains the stored session identity ${JSON.stringify(key)}`, () => {
  const s = Store.open(":memory:");
  try {
    session(s, key); ownChats(s, key);
    const expected = origin(s, key, "origin", 10); prepare(s, key);
    assert.deepEqual(latestNamingOrigins(makeStore(s.db, "."), [key]), [expected]);
  } finally { s.close(); }
});

test("the prepared and fallback latest origins use one snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "job-latest-prepared-"));
  const path = join(dir, "stillfail.db"), s = Store.open(path), writer = new DatabaseSync(path);
  try {
    session(s, "member"); ownChats(s, "member");
    const expected = origin(s, "member", "origin", 10); prepare(s, "member");
    let changed = false;
    const observed = new Proxy(s.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const statement = target.prepare(sql);
        if (sql !== LATEST_NAMING_ORIGIN_POSSIBLE) return statement;
        return new Proxy(statement, { get(stmt, method) {
          if (method === "all") return (...args: any[]) => {
            const rows = stmt.all(...args);
            if (!changed && rows.length > 0) { writer.prepare("DELETE FROM sessions WHERE key=?").run("member"); changed = true; }
            return rows;
          };
          const value = Reflect.get(stmt, method, stmt);
          return typeof value === "function" ? value.bind(stmt) : value;
        } });
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const reader = makeStore(observed, dir);
    assert.deepEqual(latestNamingOrigins(reader, ["member", "member"]), [expected, expected]);
    assert.equal(changed, true);
    assert.deepEqual(latestNamingOrigins(reader, ["member"]), []);
  } finally { writer.close(); s.close(); rmSync(dir, { recursive: true, force: true }); }
});
