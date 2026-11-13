import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { keyPart, sandboxName } from "../src/agents/sandbox-name.ts";
import { disableSandboxIndex, enableSandboxIndex, SANDBOX_SESSION, sandboxIndexReady, sandboxIndexStep, sandboxSessions } from "../src/store/sandbox-index.ts";

const schema = `CREATE TABLE sessions (key TEXT PRIMARY KEY, token TEXT NOT NULL UNIQUE, last_active_at INTEGER NOT NULL)`;
const add = `INSERT INTO sessions (key, token, last_active_at) VALUES (?, ?, ?)`;
const name = (key: string) => sandboxName(keyPart(key));
const finish = (db: DatabaseSync, limit = 3) => {
  let steps = 0;
  while (!sandboxIndexReady(db)) {
    const result = sandboxIndexStep(db, limit);
    assert.ok(result.visited <= limit);
    assert.ok(++steps < 1000);
  }
};
const expected = (db: DatabaseSync, names: string[]) => {
  const all = db.prepare("SELECT key FROM sessions ORDER BY last_active_at DESC").all() as { key: string }[];
  const owners = new Map(all.map(({ key }) => [name(key), key]));
  return new Map(names.flatMap((n) => owners.has(n) ? [[n, owners.get(n)!] as const] : []));
};

for (const recursive of [false, true]) test(`old writers and replacements keep sandbox ownership exact (recursive triggers ${recursive})`, () => {
  const dir = mkdtempSync(join(tmpdir(), "sandbox-name-index-"));
  const path = join(dir, "store.db");
  const db = new DatabaseSync(path);
  const old = new DatabaseSync(path);
  try {
    db.exec(`PRAGMA journal_mode=WAL; ${schema}`);
    old.exec(`PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    const insert = old.prepare(add);
    const replace = old.prepare(add.replace("INSERT", "INSERT OR REPLACE"));
    const replaceRow = old.prepare("INSERT OR REPLACE INTO sessions (rowid,key,token,last_active_at) VALUES (?,?,?,?)");
    const ignore = old.prepare(add.replace("INSERT", "INSERT OR IGNORE"));
    const update = old.prepare("UPDATE OR REPLACE sessions SET key = ?, token = ? WHERE key = ?");
    const drop = old.prepare("DELETE FROM sessions WHERE key = ?");
    insert.run("b-existing", "one", 7);
    insert.run("m-existing", "two", 8);
    insert.run("z-existing", "three", 9);
    enableSandboxIndex(db);
    assert.equal(sandboxSessions(db, [name("b-existing")]), null);
    assert.equal(sandboxIndexStep(db, 1).visited, 1);
    insert.run("a-new-before-cursor", "four", 10);
    replace.run("new-from-token-conflict", "two", 11);
    ignore.run("ignored", "one", 12);
    update.run("updated", "three", "z-existing");
    drop.run("b-existing");
    const keys = ["a-new-before-cursor", "b-existing", "m-existing", "new-from-token-conflict",
      "z-existing", "updated", "ignored", "a sandbox owned elsewhere"];
    const names = keys.map(name);
    assert.equal(sandboxSessions(db, names), null);
    finish(db, 1);
    assert.deepEqual(sandboxSessions(db, names), expected(db, names));
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM sandbox_name_dirty").get()?.n, 0);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM sandbox_name_rows").get()?.n,
      db.prepare("SELECT COUNT(*) AS n FROM sessions").get()?.n);
    const victim = old.prepare("SELECT rowid AS id FROM sessions WHERE key = ?").get("updated")?.id;
    assert.ok(typeof victim === "number");
    replaceRow.run(victim, "rowid-replacement", "rowid-token", 14);
    finish(db);
    assert.deepEqual(sandboxSessions(db, [name("updated"), name("rowid-replacement")]),
      new Map([[name("rowid-replacement"), "rowid-replacement"]]));
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM sandbox_name_rows").get()?.n,
      db.prepare("SELECT COUNT(*) AS n FROM sessions").get()?.n);
    const rowToReplace = old.prepare("SELECT rowid AS id FROM sessions WHERE key = ?").get("new-from-token-conflict")?.id;
    assert.ok(typeof rowToReplace === "number");
    old.prepare("UPDATE OR REPLACE sessions SET rowid = ? WHERE key = ?").run(rowToReplace, "rowid-replacement");
    finish(db);
    assert.deepEqual(sandboxSessions(db, [name("new-from-token-conflict"), name("rowid-replacement")]),
      new Map([[name("rowid-replacement"), "rowid-replacement"]]));
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM sandbox_name_rows").get()?.n,
      db.prepare("SELECT COUNT(*) AS n FROM sessions").get()?.n);
    insert.run("last", "last-token", 13);
    assert.equal(sandboxSessions(db, [...names, name("last")]), null);
    finish(db);
    assert.deepEqual(sandboxSessions(db, [...names, name("last")]), expected(db, [...names, name("last")]));
  } finally { old.close(); db.close(); rmSync(dir, { recursive: true, force: true }); }
});

for (const recursive of [false, true]) test(`sandbox ownership follows interleaved session changes (recursive triggers ${recursive})`, () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(`${schema}; PRAGMA recursive_triggers = ${recursive ? "ON" : "OFF"}`);
    const replace = db.prepare(add.replace("INSERT", "INSERT OR REPLACE"));
    const ignore = db.prepare(add.replace("INSERT", "INSERT OR IGNORE"));
    const rename = db.prepare("UPDATE OR REPLACE sessions SET key = ?, token = ? WHERE key = ?");
    const drop = db.prepare("DELETE FROM sessions WHERE key = ?");
    const activity = db.prepare("UPDATE sessions SET last_active_at = ? WHERE key = ?");
    const keys = ["a", "chat:c-12345678901234567890", "A/B", "a_b", "名字", "🧪🧪a",
      "z", "emoji-🧪-longer-than-twenty-four", "s:old", "other"];
    const names = keys.map(name);
    replace.run(keys[0]!, "token-0", 0);
    enableSandboxIndex(db);
    let state = 0x5a17;
    const next = () => (state = (Math.imul(state, 1664525) + 1013904223) >>> 0);
    for (let i = 0; i < 300; i++) {
      const key = keys[next() % keys.length]!, other = keys[next() % keys.length]!;
      const token = `token-${next() % 6}`;
      switch (next() % 5) {
        case 0: replace.run(key, token, i); break;
        case 1: ignore.run(key, token, i); break;
        case 2: rename.run(key, token, other); break;
        case 3: drop.run(key); break;
        default: activity.run(i, key);
      }
      if (i % 4 === 0) sandboxIndexStep(db, 1);
      if (i % 19 === 0) {
        finish(db, 3);
        assert.deepEqual(sandboxSessions(db, names), expected(db, names));
      }
    }
    finish(db, 3);
    assert.deepEqual(sandboxSessions(db, names), expected(db, names));
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM sandbox_name_rows").get()?.n,
      db.prepare("SELECT COUNT(*) AS n FROM sessions").get()?.n);
  } finally { db.close(); }
});

test("a failed name batch rolls its records and cursor back together", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(schema);
    db.prepare(add).run("one", "t1", 1);
    db.prepare(add).run("two", "t2", 2);
    enableSandboxIndex(db);
    db.exec(`CREATE TRIGGER fail_name BEFORE INSERT ON sandbox_name_rows
      WHEN NEW.session = 'two' BEGIN SELECT RAISE(ABORT, 'test failure'); END`);
    assert.throws(() => sandboxIndexStep(db, 10), /test failure/);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM sandbox_name_rows").get()?.n, 0);
    assert.equal(db.prepare("SELECT cursor FROM sandbox_name_meta").get()?.cursor, null);
    db.exec("DROP TRIGGER fail_name");
    finish(db);
    assert.deepEqual(sandboxSessions(db, [name("one"), name("two")]), expected(db, [name("one"), name("two")]));
  } finally { db.close(); }
});

test("new sessions cannot extend the historical preparation; their keys are journalled", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(schema);
    const put = db.prepare(add);
    put.run("a", "one", 1);
    put.run("b", "two", 2);
    enableSandboxIndex(db);
    for (let i = 0; i < 6; i++) {
      put.run(`z-${i}`, `z-token-${i}`, i + 10);
      sandboxIndexStep(db, 1);
    }
    assert.equal(db.prepare("SELECT phase FROM sandbox_name_meta").get()?.phase, 2);
    finish(db, 1);
    const names = ["a", "b", ...Array.from({ length: 6 }, (_, i) => `z-${i}`)].map(name);
    assert.deepEqual(sandboxSessions(db, names), expected(db, names));
  } finally { db.close(); }
});

test("turning sandboxes off stops the journal; turning them back on repairs old names", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(schema);
    db.prepare(add).run("old", "t1", 1);
    enableSandboxIndex(db);
    finish(db);
    disableSandboxIndex(db);
    db.prepare("DELETE FROM sessions WHERE key = ?").run("old");
    db.prepare(add).run("new", "t2", 2);
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM sandbox_name_dirty").get()?.n, 0);
    enableSandboxIndex(db);
    assert.equal(sandboxSessions(db, [name("old"), name("new")]), null);
    finish(db, 1);
    assert.deepEqual(sandboxSessions(db, [name("old"), name("new")]), new Map([[name("new"), "new"]]));
    assert.equal(db.prepare("SELECT COUNT(*) AS n FROM sandbox_name_rows").get()?.n, 1);
  } finally { db.close(); }
});

test("a sandbox name seeks its own sessions and preparation seeks keys", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(schema);
    enableSandboxIndex(db);
    const lookup = db.prepare(`EXPLAIN QUERY PLAN ${SANDBOX_SESSION}`).all("name") as { detail: string }[];
    assert.match(lookup.map((r) => r.detail).join(" | "), /SEARCH n USING (?:COVERING )?INDEX sandbox_name_lookup/);
    assert.match(lookup.map((r) => r.detail).join(" | "), /SEARCH s USING INDEX sqlite_autoindex_sessions_1/);
    const next = db.prepare("EXPLAIN QUERY PLAN SELECT key FROM sessions WHERE key > ? ORDER BY key LIMIT ?")
      .all("cursor", 64) as { detail: string }[];
    assert.match(next.map((r) => r.detail).join(" | "), /SEARCH sessions USING COVERING INDEX sqlite_autoindex_sessions_1/);
    const displaced = db.prepare(`EXPLAIN QUERY PLAN SELECT s.key FROM sessions s
      WHERE (s.token = ? OR s.rowid = ?) AND s.key IS NOT ?`).all("token", 1, "new") as { detail: string }[];
    assert.doesNotMatch(displaced.map((r) => r.detail).join(" | "), /SCAN s(?:\\s|$)/);
  } finally { db.close(); }
});

test("if two sessions have the same sandbox name, the previous activity order decides the owner", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(schema);
    const insert = db.prepare(add);
    insert.run("first", "one", 10);
    insert.run("second", "two", 3);
    insert.run("third", "three", 3);
    enableSandboxIndex(db);
    finish(db);
    db.exec("UPDATE sandbox_name_rows SET name = 'same'");
    assert.equal(db.prepare(SANDBOX_SESSION).get("same")?.key, "third");
    db.prepare("UPDATE sessions SET last_active_at = ? WHERE key = ?").run(1, "first");
    assert.equal(db.prepare(SANDBOX_SESSION).get("same")?.key, "first");
  } finally { db.close(); }
});

test("an unknown index version is neither read nor changed", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(schema);
    enableSandboxIndex(db);
    db.exec("UPDATE sandbox_name_meta SET version = 999");
    assert.throws(() => enableSandboxIndex(db), /incompatible/);
    assert.throws(() => disableSandboxIndex(db), /incompatible/);
    assert.equal(db.prepare("SELECT version FROM sandbox_name_meta").get()?.version, 999);
  } finally { db.close(); }
});

test("the readiness check and sandbox ownership use one snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "sandbox-name-snapshot-"));
  const path = join(dir, "db");
  const db = new DatabaseSync(path), old = new DatabaseSync(path);
  try {
    db.exec(`PRAGMA journal_mode=WAL; ${schema}`);
    db.prepare(add).run("session", "token", 1);
    enableSandboxIndex(db);
    finish(db);
    let changed = false;
    const observed = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const stmt = target.prepare(sql);
        if (!sql.startsWith("SELECT 1 FROM sandbox_name_meta")) return stmt;
        return new Proxy(stmt, { get(statement, part) {
          if (part === "get") return (...args: Parameters<typeof stmt.get>) => {
            const result = statement.get(...args);
            if (!changed) { changed = true; old.prepare("DELETE FROM sessions WHERE key = ?").run("session"); }
            return result;
          };
          const value = Reflect.get(statement, part, statement);
          return typeof value === "function" ? value.bind(statement) : value;
        } });
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    assert.deepEqual(sandboxSessions(observed, [name("session")]), new Map([[name("session"), "session"]]));
    assert.equal(sandboxSessions(db, [name("session")]), null);
    finish(db);
    assert.deepEqual(sandboxSessions(db, [name("session")]), new Map());
  } finally { old.close(); db.close(); rmSync(dir, { recursive: true, force: true }); }
});
