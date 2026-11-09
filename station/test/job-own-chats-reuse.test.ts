import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { openJobs } from "../src/read/jobs.ts";
import { makeStore } from "../src/read/store.ts";
import { Store } from "../src/store/store.ts";

for (const count of [4, 400]) for (const archived of [false, true]) test(`job chat names reuse members of ${count} chats within one read (archived ${archived})`, () => {
  const s = Store.open(":memory:");
  try {
    s.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a",
      createdAt: 1, lastActiveAt: 1, createdBy: "ann@x" });
    s.insertJob({ id: "job-a", sessionKey: "a", name: "job", command: "true", cwd: "/", port: null, token: "job-a",
      state: "running", pgid: null, exitCode: null, startedAt: 1, endedAt: null, restarts: 0, log: "/dev/null", watch: false });
    if (archived) s.db.prepare("UPDATE sessions SET archived_at=1 WHERE key='a'").run();
    const add = s.db.prepare("INSERT INTO threads(surface,channel,thread_ts,title,created_at,home,hidden_at) VALUES ('ember','CHAT',?,?,?,'a',?)");
    const member = s.db.prepare("INSERT INTO thread_sessions(thread,session,connect,joined_at) VALUES (?,'a','ember',1)");
    const ids: number[] = [];
    for (let i = 0; i < count; i++) {
      const id = Number(add.run(`chat-${i}`, i === 0 ? "Selected" : "Other", i + 1, archived ? 1 : null).lastInsertRowid);
      ids.push(id); member.run(id);
    }
    const memberReads = new Map<number, number>(), saidReads = new Map<number, number>();
    const observed = new Proxy(s.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const statement = target.prepare(sql);
        const members = sql === "SELECT * FROM thread_sessions WHERE thread = ? ORDER BY joined_at, rowid";
        const said = sql.startsWith("SELECT e.at FROM thread_state t JOIN entries e ON e.thread = t.thread AND e.n = t.said_n");
        if (!members && !said) return statement;
        return new Proxy(statement, { get(stmt, method) {
          if (method === "all" && members) return (...args: any[]) => {
            memberReads.set(args[0], (memberReads.get(args[0]) ?? 0) + 1); return stmt.all(...args);
          };
          if (method === "get" && said) return (...args: any[]) => {
            saidReads.set(args[0], (saidReads.get(args[0]) ?? 0) + 1); return stmt.get(...args);
          };
          const value = Reflect.get(stmt, method, stmt); return typeof value === "function" ? value.bind(stmt) : value;
        } });
      };
      const value = Reflect.get(target, property, target); return typeof value === "function" ? value.bind(target) : value;
    } });
    const viewer = { sub: "ann@x", email: "ann@x", name: "Ann", role: "member" as const, workspace: "A", device: "dev", home: true };
    const reader = makeStore(observed, ".");
    assert.deepEqual(openJobs(reader, viewer, "en")[0]?.chat, { id: "a", title: "Selected", archived });
    for (const id of ids) { assert.equal(memberReads.get(id), 1); assert.equal(saidReads.get(id), 1); }
    s.db.prepare("UPDATE threads SET title='Changed' WHERE id=?").run(ids[0]);
    assert.deepEqual(openJobs(reader, viewer, "en")[0]?.chat, { id: "a", title: "Changed", archived });
    for (const id of ids) { assert.equal(memberReads.get(id), 2); assert.equal(saidReads.get(id), 2); }
  } finally { s.close(); }
});

test("reused members remain in the read snapshot and are reloaded in the next read", () => {
  const dir = mkdtempSync(join(tmpdir(), "job-chat-members-"));
  const path = join(dir, "stillfail.db"), s = Store.open(path), writer = new DatabaseSync(path);
  try {
    for (const key of ["a", "b"]) s.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc",
      workspace: "/w", token: key, createdAt: 1, lastActiveAt: 1, createdBy: "ann@x" });
    s.insertJob({ id: "job-a", sessionKey: "a", name: "job", command: "true", cwd: "/", port: null, token: "job-a",
      state: "running", pgid: null, exitCode: null, startedAt: 1, endedAt: null, restarts: 0, log: "/dev/null", watch: false });
    const thread = s.openThreadOf("ember", "CHAT", "shared", "Shared", "ann@x", "a");
    s.joinThread(thread.id, "a", "ember"); s.joinThread(thread.id, "b", "ember");
    s.db.prepare("UPDATE thread_sessions SET joined_at=CASE session WHEN 'a' THEN 1 ELSE 2 END WHERE thread=?").run(thread.id);
    let changed = false;
    const observed = new Proxy(s.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        const stmt = target.prepare(sql);
        if (sql !== "SELECT * FROM thread_sessions WHERE thread = ? ORDER BY joined_at, rowid") return stmt;
        return new Proxy(stmt, { get(statement, method) {
          if (method === "all") return (...args: any[]) => {
            const rows = statement.all(...args);
            if (!changed && args[0] === thread.id) {
              writer.prepare("DELETE FROM thread_sessions WHERE thread=? AND session='a'").run(thread.id); changed = true;
            }
            return rows;
          };
          const value = Reflect.get(statement, method, statement); return typeof value === "function" ? value.bind(statement) : value;
        } });
      };
      const value = Reflect.get(target, property, target); return typeof value === "function" ? value.bind(target) : value;
    } });
    const viewer = { sub: "ann@x", email: "ann@x", name: "Ann", role: "member" as const, workspace: "A", device: "dev", home: true };
    const reader = makeStore(observed, dir);
    reader.db.exec("BEGIN");
    try {
      assert.equal(openJobs(reader, viewer, "en")[0]?.chat?.title, "Shared");
      assert.equal(changed, true);
    } finally { reader.db.exec("COMMIT"); }
    assert.notEqual(openJobs(reader, viewer, "en")[0]?.chat?.title, "Shared");
  } finally { writer.close(); s.close(); rmSync(dir, { recursive: true, force: true }); }
});
