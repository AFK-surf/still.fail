import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { openJobs } from "../src/read/jobs.ts";
import { HAS_NAMING_ORIGIN, makeStore } from "../src/read/store.ts";
import { MANUAL, Store, newMessage } from "../src/store/store.ts";

const viewer = { sub: "ann@x", email: "ann@x", name: "Ann", role: "member", workspace: "A", device: "dev", home: true } as const;
const session = (s: Store, key: string) => s.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key,
  createdAt: 1, lastActiveAt: 1, createdBy: "ann@x" });
const job = (s: Store, key: string) => s.insertJob({ id: `j-${key}`, sessionKey: key, name: "job", command: "true", cwd: "/", port: null, token: key,
  state: "running", pgid: null, exitCode: null, startedAt: 1, endedAt: null, restarts: 0, log: "/dev/null", watch: false });
const result = (rows: any[]) => rows.map((j) => [j.id, j.chat?.id, j.chat?.title, j.chat?.archived]);
const own = (s: Store, name: string, members: string[]) => {
  const chat = s.openThreadOf("ember", "CHAT", name, null, "ann@x", members.at(-1) ?? null);
  for (const member of members) s.joinThread(chat.id, member, "ember");
  return chat.id;
};
const origin = (s: Store, name: string, title: string | null, members: string[], at = 1) => {
  const chat = s.openThread("slack:one", "C1", name, title, "ann@x");
  for (const member of members) s.joinThread(chat.id, member, "one");
  s.insertMessage({ ...newMessage(chat.id, name, "person", "ann@x", `Text ${name}`), at });
  return chat.id;
};

for (const later of [4, 400]) test(`a job's unnamed chat does not read ${later} later members' origins`, () => {
  const s = Store.open(":memory:");
  try {
    for (const key of ["a", "b", "c"]) session(s, key);
    job(s, "a"); own(s, "own", ["b", "c", "a"]);
    origin(s, "first", "First origin", ["b"]);
    const expected = openJobs(makeStore(s.db, "."), viewer, "en");
    assert.deepEqual(result(expected), [["j-a", "b", "First origin", false]]);
    const laterIds = new Set<number>();
    for (let i = 0; i < later; i++) laterIds.add(origin(s, `later-${i}`, null, ["c"], i + 10));
    const visited: number[] = [];
    const observed = new Proxy(s.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const statement = target.prepare(sql);
        if (!sql.startsWith("SELECT * FROM thread_sessions WHERE thread = ?") && !sql.startsWith("SELECT e.at FROM thread_state")) return statement;
        return new Proxy(statement, { get(stmt, member) {
          const value = Reflect.get(stmt, member, stmt);
          if (member === "all" || member === "get") return (...args: any[]) => {
            if (laterIds.has(Number(args[0]))) visited.push(Number(args[0]));
            return value.apply(stmt, args);
          };
          return typeof value === "function" ? value.bind(stmt) : value;
        } });
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    assert.deepEqual(openJobs(makeStore(observed, "."), viewer, "en"), expected);
    assert.deepEqual(visited, [], "a later member cannot change the selected title");
  } finally { s.close(); }
});

test("an unnamed chat finds the first member whose external origin is readable", () => {
  const s = Store.open(":memory:");
  try {
    for (const key of ["a", "c"]) session(s, key);
    job(s, "a"); own(s, "own", ["missing", "c", "a"]);
    origin(s, "unreadable", "Missing-only origin", ["missing"], 1);
    origin(s, "readable", null, ["c"], 2);
    assert.deepEqual(result(openJobs(makeStore(s.db, "."), viewer, "en")), [["j-a", "c", "Text readable", false]]);
  } finally { s.close(); }
});

test("an archived or missing earlier member can still supply a shared chat's title", () => {
  for (const missing of [false, true]) {
    const s = Store.open(":memory:");
    try {
      for (const key of ["a", "c", "helper"]) session(s, key);
      if (!missing) session(s, "b");
      job(s, "a"); own(s, "own", ["b", "c", "a"]);
      origin(s, "first", "First origin", missing ? ["b", "helper"] : ["b"], 1);
      origin(s, "later", "Later origin", ["c"], 9);
      if (!missing) s.setArchived("b", true, MANUAL);
      assert.deepEqual(result(openJobs(makeStore(s.db, "."), viewer, "en")), [["j-a", "c", "First origin", false]]);
    } finally { s.close(); }
  }
});

test("different unnamed chats can select different members' origins", () => {
  const s = Store.open(":memory:");
  try {
    for (const key of ["a", "b", "c", "d"]) session(s, key);
    job(s, "a"); job(s, "d");
    own(s, "first-chat", ["b", "a"]); own(s, "second-chat", ["c", "d"]);
    origin(s, "b-origin", "B origin", ["b"]); origin(s, "c-origin", "C origin", ["c"]);
    const rows = result(openJobs(makeStore(s.db, "."), viewer, "en")).sort((a, b) => a[0].localeCompare(b[0]));
    assert.deepEqual(rows, [["j-a", "b", "B origin", false], ["j-d", "c", "C origin", false]]);
  } finally { s.close(); }
});

test("origin selection stops before probing later members", () => {
  const s = Store.open(":memory:");
  try {
    for (const key of ["a", "b", "c"]) session(s, key);
    job(s, "a"); own(s, "own", ["b", "c", "a"]);
    const first = origin(s, "first", "First origin", ["b"]);
    const later = new Set<number>();
    for (let i = 0; i < 40; i++) later.add(origin(s, `later-${i}`, null, ["c"], i + 10));
    const visited: number[] = [];
    s.db.function("visit_naming_origin", (id) => { visited.push(Number(id)); return id; });
    let traced = false;
    const observed = new Proxy(s.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql !== HAS_NAMING_ORIGIN) return target.prepare(sql);
        const tracedSql = sql.replace("AND t.surface IS NOT ?2 AND EXISTS", "AND t.surface IS NOT ?2 AND visit_naming_origin(t.id) = t.id AND EXISTS");
        assert.notEqual(tracedSql, sql);
        const stmt = target.prepare(tracedSql);
        return new Proxy(stmt, { get(statement, member) {
          if (member === "get") return (...args: any[]) => {
            const plan = (text: string) => target.prepare(`EXPLAIN QUERY PLAN ${text}`).all(...args).map((row) => row.detail);
            assert.deepEqual(plan(tracedSql), plan(sql));
            traced = true;
            return statement.get(...args);
          };
          const value = Reflect.get(statement, member, statement);
          return typeof value === "function" ? value.bind(statement) : value;
        } });
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    assert.deepEqual(result(openJobs(makeStore(observed, "."), viewer, "en")), [["j-a", "b", "First origin", false]]);
    assert.ok(traced);
    assert.ok(visited.includes(first));
    assert.deepEqual(visited.filter((id) => later.has(id)), []);
  } finally { s.close(); }
});

test("one job read checks a shared member's origins once across many chats", () => {
  const s = Store.open(":memory:");
  try {
    session(s, "a"); job(s, "a");
    let visits = 0, probes = 0;
    s.db.function("visit_naming_membership", (id) => { visits++; return id; });
    const observed = new Proxy(s.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql !== HAS_NAMING_ORIGIN) return target.prepare(sql);
        const tracedSql = sql.replace("origin.session = ?1 AND t.surface", "origin.session = ?1 AND visit_naming_membership(origin.thread) = origin.thread AND t.surface");
        assert.notEqual(tracedSql, sql);
        const stmt = target.prepare(tracedSql);
        return new Proxy(stmt, { get(statement, member) {
          if (member === "get") return (...args: any[]) => {
            const plan = (text: string) => target.prepare(`EXPLAIN QUERY PLAN ${text}`).all(...args).map((row) => row.detail);
            assert.deepEqual(plan(tracedSql), plan(sql));
            probes++;
            return statement.get(...args);
          };
          const value = Reflect.get(statement, member, statement);
          return typeof value === "function" ? value.bind(statement) : value;
        } });
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const read = () => {
      visits = 0; probes = 0;
      assert.equal(openJobs(makeStore(observed, "."), viewer, "en").length, 1);
      assert.equal(probes, 1);
      return visits;
    };
    for (let i = 0; i < 40; i++) own(s, `own-${i}`, ["a"]);
    assert.equal(read(), 40);
    for (let i = 40; i < 400; i++) own(s, `own-${i}`, ["a"]);
    assert.equal(read(), 400);
  } finally { s.close(); }
});

test("the selected member and origin details share the reader's snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "job-origin-snapshot-"));
  const path = join(dir, "stillfail.db"), s = Store.open(path), writer = new DatabaseSync(path);
  try {
    for (const key of ["a", "b", "c"]) session(s, key);
    job(s, "a"); own(s, "own", ["b", "c", "a"]);
    const first = origin(s, "first", "First origin", ["b"]);
    origin(s, "second", "Second origin", ["c"]);
    let changed = false;
    const observed = new Proxy(s.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const statement = target.prepare(sql);
        if (sql !== HAS_NAMING_ORIGIN) return statement;
        return new Proxy(statement, { get(stmt, member) {
          if (member === "get") return (...args: any[]) => {
            const row = stmt.get(...args);
            if (!changed && row !== undefined) {
              writer.prepare("UPDATE threads SET surface = 'ember' WHERE id = ?").run(first);
              changed = true;
            }
            return row;
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
      assert.deepEqual(result(openJobs(reader, viewer, "en")), [["j-a", "b", "First origin", false]]);
      assert.equal(changed, true);
    } finally { reader.db.exec("COMMIT"); }
    assert.deepEqual(result(openJobs(reader, viewer, "en")), [["j-a", "b", "Second origin", false]]);
  } finally { writer.close(); s.close(); rmSync(dir, { recursive: true, force: true }); }
});
