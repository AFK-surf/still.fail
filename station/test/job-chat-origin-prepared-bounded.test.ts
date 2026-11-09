import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { HAS_NAMING_ORIGIN, HAS_NAMING_ORIGIN_POSSIBLE, HAS_NAMING_ORIGIN_PREPARED, makeStore, namingOriginProbe } from "../src/read/store.ts";
import { CcIndexPreparation, ccSessionReady } from "../src/store/cc-thread-index.ts";
import { Store } from "../src/store/store.ts";

const preparedLookup = HAS_NAMING_ORIGIN_PREPARED;
const possibleLookup = HAS_NAMING_ORIGIN_POSSIBLE;

const addSession = (s: Store, key: string) => s.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key,
  createdAt: 1, lastActiveAt: 1, createdBy: "ann@x" });

const prepare = (s: Store, key: string) => {
  const work = new CcIndexPreparation();
  let steps = 0;
  while (!ccSessionReady(s.db, key)) {
    work.step(s.db, key, 64);
    assert.ok(++steps < 20_000);
  }
};

const addOwnChats = (s: Store, key: string, count = 9) => {
  const thread = s.db.prepare("INSERT INTO threads (surface,channel,thread_ts,created_at) VALUES ('ember','C',?,1)");
  const member = s.db.prepare("INSERT INTO thread_sessions (thread,session,connect,joined_at) VALUES (?,?,'ember',1)");
  s.db.exec("BEGIN IMMEDIATE");
  for (let i = 0; i < count; i++) member.run(thread.run(`${key}-own-${i}`).lastInsertRowid, key);
  s.db.exec("COMMIT");
};

for (const count of [40, 400, 4000]) test(`a prepared live member checks no ${count} unrelated own-chat memberships`, () => {
  const s = Store.open(":memory:");
  try {
    addSession(s, "member");
    const thread = s.db.prepare("INSERT INTO threads (surface,channel,thread_ts,created_at) VALUES ('ember','C',?,1)");
    const member = s.db.prepare("INSERT INTO thread_sessions (thread,session,connect,joined_at) VALUES (?,'member','ember',1)");
    s.db.exec("BEGIN IMMEDIATE");
    for (let i = 0; i < count; i++) member.run(thread.run(`own-${i}`).lastInsertRowid);
    s.db.exec("COMMIT");
    prepare(s, "member");
    let oldVisits = 0, preparedVisits = 0, candidateVisits = 0, usedPrepared = false;
    s.db.function("visit_original_origin", (value) => { oldVisits++; return value; });
    s.db.function("visit_prepared_origin", (value) => { preparedVisits++; return value; });
    s.db.function("visit_candidate_member", (value) => { candidateVisits++; return value; });
    const observed = new Proxy(s.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        let traced = sql;
        if (sql === HAS_NAMING_ORIGIN) traced = sql.replace("origin.session = ?1 AND t.surface",
          "origin.session = ?1 AND visit_original_origin(origin.thread) = origin.thread AND t.surface");
        if (sql === preparedLookup) {
          usedPrepared = true;
          traced = sql.replace("surface != 'ember'", "surface != 'ember' AND visit_prepared_origin(thread) = thread");
        }
        if (sql === possibleLookup) traced = sql.replace("WHERE session = c.session LIMIT",
          "WHERE session = c.session AND visit_candidate_member(rowid) = rowid LIMIT");
        if (traced !== sql) {
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
        }
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const lookup = namingOriginProbe(makeStore(observed, "."));
    const changes = s.db.prepare("SELECT total_changes() AS n").get()!.n;
    assert.equal(lookup("member"), false);
    assert.equal(usedPrepared, true);
    assert.equal(oldVisits, 0);
    assert.equal(preparedVisits, 0);
    assert.equal(candidateVisits, 18, "the two preliminary checks inspect at most nine memberships each");
    assert.equal(s.db.prepare("SELECT total_changes() AS n").get()!.n, changes, "the read must not prepare or write an index");
  } finally { s.close(); }
});

for (const count of [8, 9]) test(`a prepared session with ${count} memberships chooses the bounded check`, () => {
  const s = Store.open(":memory:");
  try {
    addSession(s, "member"); addOwnChats(s, "member", count); prepare(s, "member");
    let indexedReads = 0;
    const observed = new Proxy(s.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const statement = target.prepare(sql);
        if (sql !== preparedLookup) return statement;
        return new Proxy(statement, { get(stmt, method) {
          if (method === "get") return (...args: any[]) => { indexedReads++; return stmt.get(...args); };
          const value = Reflect.get(stmt, method, stmt);
          return typeof value === "function" ? value.bind(stmt) : value;
        } });
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    assert.equal(namingOriginProbe(makeStore(observed, "."))("member"), false);
    assert.equal(indexedReads, count === 9 ? 1 : 0);
  } finally { s.close(); }
});

test("a prepared missing member still needs a live member in its external origin", () => {
  const s = Store.open(":memory:");
  try {
    const chat = s.openThread("slack:one", "C", "origin", null, "ann@x");
    s.joinThread(chat.id, "missing", "one");
    addOwnChats(s, "missing");
    prepare(s, "missing");
    const lookup = namingOriginProbe(makeStore(s.db, "."));
    assert.equal(lookup("missing"), false);
    addSession(s, "helper"); s.joinThread(chat.id, "helper", "one");
    assert.equal(lookup("missing"), true);
  } finally { s.close(); }
});

test("a prepared live member finds an external origin", () => {
  const s = Store.open(":memory:");
  try {
    addSession(s, "member");
    const chat = s.openThread("slack:one", "C", "origin", null, "ann@x");
    s.joinThread(chat.id, "member", "one");
    addOwnChats(s, "member");
    prepare(s, "member");
    assert.equal(namingOriginProbe(makeStore(s.db, "."))("member"), true);
  } finally { s.close(); }
});

test("a source change while the copy index is dirty uses the current source", () => {
  const s = Store.open(":memory:");
  try {
    addSession(s, "member"); addOwnChats(s, "member"); prepare(s, "member");
    const lookup = namingOriginProbe(makeStore(s.db, "."));
    assert.equal(lookup("member"), false);
    const chat = s.openThread("slack:one", "C", "new", null, "ann@x");
    s.joinThread(chat.id, "member", "one");
    assert.equal(ccSessionReady(s.db, "member"), false);
    assert.equal(lookup("member"), true);
  } finally { s.close(); }
});

test("a database without the copy index retains the old origin check", () => {
  const s = Store.open(":memory:");
  try {
    addSession(s, "member");
    const chat = s.openThread("slack:one", "C", "origin", null, "ann@x");
    s.joinThread(chat.id, "member", "one");
    s.db.exec("DROP TABLE cc_index_meta");
    assert.equal(namingOriginProbe(makeStore(s.db, "."))("member"), true);
  } finally { s.close(); }
});

test("a database without the membership index retains the old origin check", () => {
  const s = Store.open(":memory:");
  try {
    addSession(s, "member");
    const chat = s.openThread("slack:one", "C", "origin", null, "ann@x");
    s.joinThread(chat.id, "member", "one");
    s.db.exec("DROP INDEX thread_sessions_session");
    assert.equal(namingOriginProbe(makeStore(s.db, "."))("member"), true);
  } finally { s.close(); }
});

test("a member removed after the fast-path probe is checked again in the answer's snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "job-origin-prepared-"));
  const path = join(dir, "stillfail.db"), s = Store.open(path), writer = new DatabaseSync(path);
  try {
    addSession(s, "member");
    const chat = s.openThread("slack:one", "C", "origin", null, "ann@x");
    s.joinThread(chat.id, "member", "one"); addOwnChats(s, "member"); prepare(s, "member");
    let changed = false;
    const observed = new Proxy(s.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const statement = target.prepare(sql);
        if (sql !== possibleLookup) return statement;
        return new Proxy(statement, { get(stmt, method) {
          if (method === "get") return (...args: any[]) => {
            const row = stmt.get(...args);
            if (!changed && row !== undefined) { writer.prepare("DELETE FROM sessions WHERE key = ?").run("member"); changed = true; }
            return row;
          };
          const value = Reflect.get(stmt, method, stmt);
          return typeof value === "function" ? value.bind(stmt) : value;
        } });
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    assert.equal(namingOriginProbe(makeStore(observed, dir))("member"), false);
    assert.equal(changed, true);
  } finally { writer.close(); s.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("the prepared existence answer stays in the reader's snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "job-origin-prepared-"));
  const path = join(dir, "stillfail.db"), s = Store.open(path), writer = new DatabaseSync(path);
  try {
    addSession(s, "member");
    const chat = s.openThread("slack:one", "C", "origin", null, "ann@x");
    s.joinThread(chat.id, "member", "one"); addOwnChats(s, "member"); prepare(s, "member");
    let changed = false;
    const observed = new Proxy(s.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const statement = target.prepare(sql);
        if (sql !== preparedLookup) return statement;
        return new Proxy(statement, { get(stmt, method) {
          if (method === "get") return (...args: any[]) => {
            const row = stmt.get(...args);
            if (!changed && row !== undefined) { writer.prepare("DELETE FROM sessions WHERE key = ?").run("member"); changed = true; }
            return row;
          };
          const value = Reflect.get(stmt, method, stmt);
          return typeof value === "function" ? value.bind(stmt) : value;
        } });
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const lookup = namingOriginProbe(makeStore(observed, dir));
    s.db.exec("BEGIN");
    try { assert.equal(lookup("member"), true); assert.equal(changed, true); }
    finally { s.db.exec("COMMIT"); }
    assert.equal(lookup("member"), false);
  } finally { writer.close(); s.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("an older nullable thread surface is not confused with a missing thread", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(`CREATE TABLE sessions(key TEXT PRIMARY KEY);
      CREATE TABLE threads(id INTEGER PRIMARY KEY,surface TEXT);
      CREATE TABLE thread_sessions(thread INTEGER,session TEXT,PRIMARY KEY(thread,session));
      CREATE TABLE cc_index_meta(id INTEGER PRIMARY KEY,version INTEGER);
      CREATE TABLE cc_sessions(session TEXT PRIMARY KEY,complete INTEGER);
      CREATE TABLE cc_session_rows(session TEXT,thread INTEGER,surface TEXT,created_at INTEGER,last_at INTEGER,PRIMARY KEY(session,thread));
      CREATE INDEX cc_session_order ON cc_session_rows(session,last_at DESC,created_at DESC,thread DESC) WHERE surface != 'ember';
      CREATE TABLE cc_session_dirty(session TEXT,thread INTEGER,PRIMARY KEY(session,thread));
      CREATE TABLE cc_order_dispatch(thread INTEGER PRIMARY KEY);
      INSERT INTO sessions VALUES('member'); INSERT INTO threads VALUES(1,NULL);
      INSERT INTO thread_sessions VALUES(1,'member'); INSERT INTO cc_index_meta VALUES(1,1);
      INSERT INTO cc_sessions VALUES('member',1); INSERT INTO cc_session_rows VALUES('member',1,NULL,1,1);`);
    assert.equal(namingOriginProbe({ db } as ReturnType<typeof makeStore>)("member"), true);
  } finally { db.close(); }
});
