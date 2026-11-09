import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { threads } from "../src/read/sessions.ts";
import { firstText, listThreads, makeStore } from "../src/read/store.ts";
import { installLegacyEdits } from "../src/store/legacy-edits-build.ts";
import { Store } from "../src/store/store.ts";

const viewer = (workspace: string, home: boolean) =>
  ({ sub: "u", email: "ann@x", name: "Ann", role: "member", workspace, device: "dev", home });

function fixture(path = ":memory:") {
  const store = Store.open(path);
  for (const [key, ws] of [["a", "A"], ["b", "B"], ["home", null]] as const)
    store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key,
      createdAt: 1, lastActiveAt: 1, createdBy: "ann@x", ws });
  const add = (name: string, members: string[]) => {
    const thread = store.openThreadOf("slack:one", "C1", name, name, "ann@x", members[0] ?? null);
    for (const member of members) store.joinThread(thread.id, member, "ember");
    return thread.id;
  };
  return { store, add };
}

test("a workspace list does not wait for another workspace's old edits", () => {
  const f = fixture();
  try {
    const visible = f.add("visible", ["a"]), away = f.add("away", ["b"]);
    const db = f.store.db;
    db.exec("DROP INDEX entries_edits; DROP INDEX IF EXISTS entries_target");
    const put = db.prepare("INSERT INTO entries(thread,n,kind,target,author_kind,author,text,at) VALUES(?,?,?,?,?,?,?,?)");
    put.run(away, 1, "message", null, "person", "ann@x", "other workspace", 1);
    for (let n = 2; n <= 81; n++) put.run(away, n, "edit", n + 1000, "agent", "worker", `edit-${n}`, n);
    installLegacyEdits(db);
    const reader = makeStore(db, ".");
    assert.throws(() => firstText(reader, away), { status: 503, message: "legacy edit lookup pending" });
    const one = threads(reader, viewer("A", false), "a", "en");
    assert.equal(one.length, 1);
    assert.equal(one[0].id, visible);
    assert.deepEqual(threads(reader, viewer("A", false), null, "en"), one);
    assert.throws(() => threads(reader, viewer("B", false), null, "en"), { status: 503, message: "legacy edit lookup pending" });
  } finally { f.store.close(); }
});

test("workspace lists retain shared, home and missing-session membership semantics", () => {
  const f = fixture();
  try {
    const a = f.add("a-only", ["a"]), b = f.add("b-only", ["b"]), shared = f.add("shared", ["a", "b"]);
    const home = f.add("home-only", ["home"]), missing = f.add("missing-session", ["missing"]), empty = f.add("empty", []);
    const reader = makeStore(f.store.db, ".");
    const ids = (ws: string, isHome: boolean) => threads(reader, viewer(ws, isHome), null, "en").map((t) => t.id).sort((x, y) => x - y);
    assert.deepEqual(ids("A", false), [a, shared]);
    assert.deepEqual(ids("B", false), [b, shared]);
    assert.deepEqual(ids("A", true), [a, shared, home, missing]);
    assert.ok(!ids("A", true).includes(empty));
    const fromB = threads(reader, viewer("A", false), "b", "en");
    assert.deepEqual(fromB.map((t) => t.id), [shared]);
    assert.deepEqual(fromB[0].sessions.map((m: any) => m.session), ["a", "b"]);
  } finally { f.store.close(); }
});

test("a workspace list reads membership details only for its visible threads", () => {
  const f = fixture();
  try {
    const visible = f.add("visible", ["a"]);
    for (let i = 0; i < 40; i++) f.add(`away-${i}`, ["b"]);
    const detailThreads: number[] = [];
    const observed = new Proxy(f.store.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const statement = target.prepare(sql);
        if (sql !== "SELECT * FROM thread_sessions WHERE thread = ? ORDER BY joined_at, rowid") return statement;
        return new Proxy(statement, { get(stmt, member) {
          if (member === "all") return (...args: any[]) => { detailThreads.push(Number(args[0])); return stmt.all(...args); };
          const value = Reflect.get(stmt, member, stmt);
          return typeof value === "function" ? value.bind(stmt) : value;
        } });
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    assert.deepEqual(threads(makeStore(observed, "."), viewer("A", false), null, "en").map((t) => t.id), [visible]);
    assert.ok(detailThreads.length > 0);
    assert.deepEqual([...new Set(detailThreads)], [visible]);
  } finally { f.store.close(); }
});

test("workspace selection works without the old workspace index", () => {
  const f = fixture();
  try {
    const visible = f.add("visible", ["a"]);
    f.add("away", ["b"]);
    f.store.db.exec("DROP INDEX sessions_ws");
    assert.deepEqual(threads(makeStore(f.store.db, "."), viewer("A", false), null, "en").map((t) => t.id), [visible]);
  } finally { f.store.close(); }
});

test("a database from before session workspaces treats its members as home", () => {
  const f = fixture();
  try {
    const id = f.add("old", ["a"]);
    f.store.db.exec("UPDATE sessions SET ws=NULL");
    const observed = new Proxy(f.store.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql.includes("visible_session.ws")) throw new Error("no such column: visible_session.ws");
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const reader = makeStore(observed, ".");
    assert.deepEqual(threads(reader, viewer("A", true), null, "en").map((t) => t.id), [id]);
    assert.deepEqual(threads(reader, viewer("A", false), null, "en"), []);
  } finally { f.store.close(); }
});

test("an actual old sessions table without ws is readable from another workspace", () => {
  const db = new DatabaseSync(":memory:");
  try {
    db.exec(`CREATE TABLE threads(id INTEGER PRIMARY KEY);
      CREATE TABLE reads(thread INTEGER,viewer TEXT,n INTEGER);
      CREATE TABLE sessions(key TEXT PRIMARY KEY);
      CREATE TABLE thread_sessions(thread INTEGER,session TEXT);
      INSERT INTO threads VALUES(1);
      INSERT INTO sessions VALUES('a');
      INSERT INTO thread_sessions VALUES(1,'a');`);
    assert.deepEqual(listThreads(makeStore(db, "."), "ann@x", null, null, "count", viewer("A", false)), []);
  } finally { db.close(); }
});

test("workspace selection and thread details share the reader's snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "thread-views-scope-"));
  const path = join(dir, "stillfail.db"), f = fixture(path), writer = new DatabaseSync(path);
  try {
    const id = f.add("visible", ["a"]);
    const reader = makeStore(f.store.db, dir);
    reader.db.exec("BEGIN");
    try {
      reader.db.prepare("SELECT id FROM threads WHERE id=?").get(id);
      writer.prepare("UPDATE sessions SET ws='B' WHERE key='a'").run();
      assert.deepEqual(threads(reader, viewer("A", false), null, "en").map((t) => t.id), [id]);
    }
    finally { reader.db.exec("COMMIT"); }
    assert.deepEqual(threads(reader, viewer("A", false), null, "en"), []);
  } finally { writer.close(); f.store.close(); rmSync(dir, { recursive: true, force: true }); }
});
