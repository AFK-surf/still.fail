import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { openJobs } from "../src/read/jobs.ts";
import { LATEST_NAMING_ORIGIN, makeStore } from "../src/read/store.ts";
import { Store, newMessage } from "../src/store/store.ts";

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
const origin = (s: Store, name: string, title: string | null, members: string[], at: number | null) => {
  const chat = s.openThread("slack:one", "C1", name, title, "ann@x");
  for (const member of members) s.joinThread(chat.id, member, "one");
  if (at !== null) s.insertMessage({ ...newMessage(chat.id, name, "person", "ann@x", `Text ${name}`), at });
  return chat.id;
};

for (const older of [4, 400]) test(`a job loads only its latest origin's details with ${older} older origins`, () => {
  const s = Store.open(":memory:");
  try {
    session(s, "a"); session(s, "b"); job(s, "a"); own(s, "own", ["b", "a"]);
    origin(s, "latest", "Latest origin", ["b"], 10_000);
    const expected = openJobs(makeStore(s.db, "."), viewer, "en");
    assert.deepEqual(result(expected), [["j-a", "b", "Latest origin", false]]);
    const otherIds = new Set<number>();
    for (let i = 0; i < older; i++) otherIds.add(origin(s, `older-${i}`, null, ["b"], i + 1));
    let details = 0;
    const observed = new Proxy(s.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const statement = target.prepare(sql);
        if (!sql.startsWith("SELECT * FROM thread_sessions WHERE thread = ?") && !sql.startsWith("SELECT e.at FROM thread_state")) return statement;
        return new Proxy(statement, { get(stmt, member) {
          const value = Reflect.get(stmt, member, stmt);
          if (member === "all" || member === "get") return (...args: any[]) => {
            if (otherIds.has(Number(args[0]))) details++;
            return value.apply(stmt, args);
          };
          return typeof value === "function" ? value.bind(stmt) : value;
        } });
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    assert.deepEqual(openJobs(makeStore(observed, "."), viewer, "en"), expected);
    assert.equal(details, 0, "older origins cannot affect this job's name");
  } finally { s.close(); }
});

test("latest origin uses message time, then creation time and thread id", () => {
  const s = Store.open(":memory:");
  try {
    session(s, "a"); session(s, "b"); job(s, "a"); own(s, "own", ["b", "a"]);
    const first = origin(s, "first", "First", ["b"], 20);
    const second = origin(s, "second", "Second", ["b"], 10);
    const created = s.db.prepare("UPDATE threads SET created_at = ? WHERE id = ?");
    created.run(1, first); created.run(2, second);
    const reader = makeStore(s.db, ".");
    assert.deepEqual(result(openJobs(reader, viewer, "en")), [["j-a", "b", "First", false]]);
    s.db.prepare("UPDATE entries SET at = 20 WHERE thread = ? AND kind = 'message'").run(second);
    assert.deepEqual(result(openJobs(reader, viewer, "en")), [["j-a", "b", "Second", false]]);
    created.run(2, first);
    assert.deepEqual(result(openJobs(reader, viewer, "en")), [["j-a", "b", "Second", false]]);
  } finally { s.close(); }
});

test("an edit does not change origin order, while the chosen first text includes edits", () => {
  const s = Store.open(":memory:");
  try {
    session(s, "a"); session(s, "b"); job(s, "a"); own(s, "own", ["b", "a"]);
    origin(s, "old", null, ["b"], 10);
    origin(s, "new", null, ["b"], 20);
    s.editMessage("slack:one", "C1", "old", "old", "Edited old");
    const reader = makeStore(s.db, ".");
    assert.deepEqual(result(openJobs(reader, viewer, "en")), [["j-a", "b", "Text new", false]]);
    s.editMessage("slack:one", "C1", "new", "new", "Edited new");
    assert.deepEqual(result(openJobs(reader, viewer, "en")), [["j-a", "b", "Edited new", false]]);
  } finally { s.close(); }
});

test("a thread without a message uses zero for origin ordering", () => {
  const s = Store.open(":memory:");
  try {
    session(s, "a"); session(s, "b"); job(s, "a"); own(s, "own", ["b", "a"]);
    origin(s, "negative", "Negative", ["b"], -1);
    origin(s, "empty", "Empty", ["b"], null);
    assert.deepEqual(result(openJobs(makeStore(s.db, "."), viewer, "en")), [["j-a", "b", "Empty", false]]);
  } finally { s.close(); }
});

test("shared origins can be latest for different members of different job chats", () => {
  const s = Store.open(":memory:");
  try {
    for (const key of ["a", "b", "c", "d"]) session(s, key);
    job(s, "a"); job(s, "d"); own(s, "first-chat", ["b", "a"]); own(s, "second-chat", ["c", "d"]);
    origin(s, "shared", "Shared", ["b", "c"], 10);
    origin(s, "c-new", "C latest", ["c"], 20);
    const rows = result(openJobs(makeStore(s.db, "."), viewer, "en")).sort((a, b) => a[0].localeCompare(b[0]));
    assert.deepEqual(rows, [["j-a", "b", "Shared", false], ["j-d", "c", "C latest", false]]);
  } finally { s.close(); }
});

test("many independent jobs select their origins together", () => {
  const s = Store.open(":memory:");
  try {
    const expected = new Map<string, string>();
    for (let i = 0; i < 400; i++) {
      const key = `s-${i}`;
      session(s, key); job(s, key);
      origin(s, `origin-${i}`, `Origin ${i}`, [key], i);
      expected.set(`j-${key}`, `Origin ${i}`);
    }
    let selections = 0;
    const observed = new Proxy(s.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const statement = target.prepare(sql);
        if (sql !== LATEST_NAMING_ORIGIN) return statement;
        return new Proxy(statement, { get(stmt, member) {
          if (member === "all") return (...args: any[]) => { selections++; return stmt.all(...args); };
          const value = Reflect.get(stmt, member, stmt);
          return typeof value === "function" ? value.bind(stmt) : value;
        } });
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const rows = openJobs(makeStore(observed, "."), viewer, "en");
    assert.deepEqual(new Map(rows.map((j) => [j.id, j.chat?.title])), expected);
    assert.equal(selections, 1);
  } finally { s.close(); }
});

test("the latest origin and its details share the reader's snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "job-latest-origin-"));
  const path = join(dir, "stillfail.db"), s = Store.open(path), writer = new DatabaseSync(path);
  try {
    session(s, "a"); session(s, "b"); job(s, "a"); own(s, "own", ["b", "a"]);
    origin(s, "first", "First", ["b"], 10);
    const second = origin(s, "second", "Second", ["b"], 20);
    let changed = false;
    const observed = new Proxy(s.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const statement = target.prepare(sql);
        if (sql !== LATEST_NAMING_ORIGIN) return statement;
        return new Proxy(statement, { get(stmt, member) {
          if (member === "all") return (...args: any[]) => {
            const rows = stmt.all(...args);
            if (!changed && rows.some((row: any) => row.id !== null)) {
              writer.prepare("UPDATE entries SET at = 0 WHERE thread = ? AND kind = 'message'").run(second);
              writer.prepare("UPDATE threads SET title = 'Changed' WHERE id = ?").run(second);
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
      assert.deepEqual(result(openJobs(reader, viewer, "en")), [["j-a", "b", "Second", false]]);
      assert.equal(changed, true);
    } finally { reader.db.exec("COMMIT"); }
    assert.deepEqual(result(openJobs(reader, viewer, "en")), [["j-a", "b", "First", false]]);
  } finally { writer.close(); s.close(); rmSync(dir, { recursive: true, force: true }); }
});
