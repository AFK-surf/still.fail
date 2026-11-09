import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { openJobs } from "../src/read/jobs.ts";
import { makeStore } from "../src/read/store.ts";
import { MANUAL, Store, newMessage } from "../src/store/store.ts";

const viewer = { sub: "ann@x", email: "ann@x", name: "Ann", role: "member", workspace: "A", device: "dev", home: true } as const;
const session = (s: Store, key: string) => s.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key,
  createdAt: 1, lastActiveAt: 1, createdBy: "ann@x" });
const job = (s: Store, key: string) => s.insertJob({ id: `j-${key}`, sessionKey: key, name: "job", command: "true", cwd: "/", port: null, token: key,
  state: "running", pgid: null, exitCode: null, startedAt: 1, endedAt: null, restarts: 0, log: "/dev/null", watch: false });
const result = (rows: any[]) => rows.map((j) => [j.id, j.chat?.id, j.chat?.title, j.chat?.archived]);

for (const owner of ["a", "b"]) test(`a named shared chat does not read ${owner}'s unrelated origins`, () => {
  const s = Store.open(":memory:");
  try {
    session(s, "a"); session(s, "b"); job(s, "a");
    const chat = s.openThreadOf("ember", "CHAT", "own", "Given title", "ann@x", "a");
    s.joinThread(chat.id, "a", "ember");
    s.joinThread(chat.id, "b", "ember");
    const reader = makeStore(s.db, ".");
    const expected = openJobs(reader, viewer, "en");
    assert.deepEqual(result(expected), [["j-a", "a", "Given title", false]]);
    const origins = new Set<number>();
    for (let i = 0; i < 400; i++) {
      const t = s.openThread("slack:one", "C1", `origin-${i}`, null, "ann@x");
      s.joinThread(t.id, owner, "one");
      s.insertMessage({ ...newMessage(t.id, `msg-${i}`, "person", "ann@x", `Origin ${i}`), at: i + 2 });
      origins.add(t.id);
    }
    const visited: number[] = [];
    const observed = new Proxy(s.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const statement = target.prepare(sql);
        if (!sql.startsWith("SELECT * FROM thread_sessions WHERE thread = ?") && !sql.startsWith("SELECT e.at FROM thread_state")) return statement;
        return new Proxy(statement, { get(stmt, member) {
          const value = Reflect.get(stmt, member, stmt);
          if (member === "all" || member === "get") return (...args: any[]) => {
            if (origins.has(Number(args[0]))) visited.push(Number(args[0]));
            return value.apply(stmt, args);
          };
          return typeof value === "function" ? value.bind(stmt) : value;
        } });
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    assert.deepEqual(openJobs(makeStore(observed, "."), viewer, "en"), expected);
    assert.deepEqual(visited, [], "an already named chat needs no origin details");
  } finally { s.close(); }
});

test("an unnamed shared chat may use an archived member's origin before its active member's", () => {
  const s = Store.open(":memory:");
  try {
    session(s, "a"); session(s, "b"); job(s, "a");
    const chat = s.openThreadOf("ember", "CHAT", "own", null, "ann@x", "a");
    s.joinThread(chat.id, "b", "ember");
    s.joinThread(chat.id, "a", "ember");
    const old = s.openThread("slack:one", "C1", "old", "B origin", "ann@x");
    const recent = s.openThread("slack:one", "C1", "recent", "A origin", "ann@x");
    s.joinThread(old.id, "b", "one");
    s.joinThread(recent.id, "a", "one");
    s.insertMessage({ ...newMessage(old.id, "old", "person", "ann@x", "old"), at: 1 });
    s.insertMessage({ ...newMessage(recent.id, "new", "person", "ann@x", "new"), at: 9 });
    s.setArchived("b", true, MANUAL);
    assert.deepEqual(result(openJobs(makeStore(s.db, "."), viewer, "en")), [["j-a", "a", "B origin", false]]);
  } finally { s.close(); }
});

test("a missing member's origin remains usable when another member of that origin exists", () => {
  const s = Store.open(":memory:");
  try {
    session(s, "a"); session(s, "other"); job(s, "a");
    const chat = s.openThreadOf("ember", "CHAT", "own", null, "ann@x", "a");
    s.joinThread(chat.id, "missing", "ember");
    s.joinThread(chat.id, "a", "ember");
    const origin = s.openThread("slack:one", "C1", "origin", "Missing member origin", "ann@x");
    s.joinThread(origin.id, "missing", "one");
    s.joinThread(origin.id, "other", "one");
    assert.deepEqual(result(openJobs(makeStore(s.db, "."), viewer, "en")), [["j-a", "a", "Missing member origin", false]]);
  } finally { s.close(); }
});

test("job selection keeps the sidebar's order across multiple named chats", () => {
  const s = Store.open(":memory:");
  try {
    session(s, "a"); job(s, "a");
    const older = s.openThreadOf("ember", "CHAT", "old", "Older", "ann@x", "a");
    const newer = s.openThreadOf("ember", "CHAT", "new", "Newer", "ann@x", "a");
    s.joinThread(older.id, "a", "ember");
    s.joinThread(newer.id, "a", "ember");
    s.insertMessage({ ...newMessage(older.id, "old", "person", "ann@x", "old"), at: 1 });
    s.insertMessage({ ...newMessage(newer.id, "new", "person", "ann@x", "new"), at: 9 });
    assert.deepEqual(result(openJobs(makeStore(s.db, "."), viewer, "en")), [["j-a", "a", "Older", false]]);
  } finally { s.close(); }
});

test("finding a job's chats does not traverse unrelated station chats", () => {
  const s = Store.open(":memory:");
  try {
    session(s, "a"); job(s, "a");
    const chat = s.openThreadOf("ember", "CHAT", "own", "Given title", "ann@x", "a");
    s.joinThread(chat.id, "a", "ember");
    let visited = 0, traced = false;
    s.db.function("visit_job_scope_thread", (id) => { visited++; return id; });
    const observed = new Proxy(s.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (!sql.startsWith("SELECT DISTINCT t.id FROM thread_sessions m") || !sql.includes("AND t.surface = ?2")) return target.prepare(sql);
        const tracedSql = sql.replace("AND t.surface = ?2", "AND t.surface = ?2 AND visit_job_scope_thread(t.id) = t.id");
        const stmt = target.prepare(tracedSql);
        return new Proxy(stmt, { get(statement, member) {
          if (member === "all") return (...args: any[]) => {
            const plan = (text: string) => target.prepare(`EXPLAIN QUERY PLAN ${text}`).all(...args).map((row) => row.detail);
            assert.deepEqual(plan(tracedSql), plan(sql));
            traced = true;
            return statement.all(...args);
          };
          const value = Reflect.get(statement, member, statement);
          return typeof value === "function" ? value.bind(statement) : value;
        } });
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const read = () => {
      visited = 0;
      assert.deepEqual(result(openJobs(makeStore(observed, "."), viewer, "en")), [["j-a", "a", "Given title", false]]);
      assert.ok(traced);
      return visited;
    };
    const add = (start: number, end: number) => {
      for (let i = start; i < end; i++) {
        const other = s.openThreadOf("ember", "CHAT", `other-${i}`, "Other", "ann@x", "b");
        s.joinThread(other.id, "b", "ember");
      }
    };
    add(0, 40);
    const before = read();
    add(40, 400);
    const after = read();
    assert.ok(before > 0);
    assert.equal(after, before, `finding the job's chat visited ${before}, then ${after}, station chats`);
  } finally { s.close(); }
});

test("job names remain readable without the session membership index", () => {
  const s = Store.open(":memory:");
  try {
    session(s, "a"); session(s, "b"); job(s, "a");
    const chat = s.openThreadOf("ember", "CHAT", "own", null, "ann@x", "a");
    s.joinThread(chat.id, "b", "ember");
    s.joinThread(chat.id, "a", "ember");
    const origin = s.openThread("slack:one", "C1", "origin", "Origin", "ann@x");
    s.joinThread(origin.id, "b", "one");
    const reader = makeStore(s.db, ".");
    const expected = openJobs(reader, viewer, "en");
    assert.deepEqual(result(expected), [["j-a", "b", "Origin", false]]);
    s.db.exec("DROP INDEX thread_sessions_session; DROP INDEX sessions_ws");
    assert.deepEqual(openJobs(reader, viewer, "en"), expected);
  } finally { s.close(); }
});

test("the scope and the selected title share the reader's snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "job-chat-scope-"));
  const path = join(dir, "stillfail.db"), s = Store.open(path), writer = new DatabaseSync(path);
  try {
    session(s, "a"); session(s, "b"); job(s, "a");
    const chat = s.openThreadOf("ember", "CHAT", "own", "Given title", "ann@x", "a");
    s.joinThread(chat.id, "a", "ember");
    s.joinThread(chat.id, "b", "ember");
    const origin = s.openThread("slack:one", "C1", "origin", "Later origin", "ann@x");
    s.joinThread(origin.id, "b", "one");
    let changed = false;
    const observed = new Proxy(s.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const statement = target.prepare(sql);
        if (!sql.startsWith("SELECT DISTINCT t.id FROM thread_sessions m")) return statement;
        return new Proxy(statement, { get(stmt, member) {
          if (member === "all") return (...args: any[]) => {
            const rows = stmt.all(...args);
            if (!changed) {
              writer.prepare("UPDATE threads SET title = NULL WHERE id = ?").run(chat.id);
              changed = true;
            }
            return rows;
          };
          const value = Reflect.get(stmt, member, stmt);
          return typeof value === "function" ? value.bind(stmt) : value;
        } });
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const reader = makeStore(observed, dir);
    reader.db.exec("BEGIN");
    try {
      assert.deepEqual(result(openJobs(reader, viewer, "en")), [["j-a", "a", "Given title", false]]);
      assert.equal(changed, true);
    } finally { reader.db.exec("COMMIT"); }
    assert.deepEqual(result(openJobs(reader, viewer, "en")), [["j-a", "a", "Later origin", false]]);
  } finally { writer.close(); s.close(); rmSync(dir, { recursive: true, force: true }); }
});
