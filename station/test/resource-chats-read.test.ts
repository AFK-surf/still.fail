// A resource snapshot names only the chats whose processes are in it. Its cost must not grow with other chats.
import assert from "node:assert/strict";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { makeStore } from "../src/read/store.ts";
import { resourceChats } from "../src/read/usage.ts";

test("naming processes reads only the sessions being named", () => {
  const db = new DatabaseSync(":memory:");
  db.exec("CREATE TABLE sessions (key TEXT PRIMARY KEY, ws TEXT); CREATE TABLE threads (id INTEGER PRIMARY KEY); CREATE TABLE thread_sessions (session TEXT, thread INTEGER, joined_at INTEGER)");
  const insert = db.prepare("INSERT INTO sessions VALUES (?, ?)");
  for (let i = 0; i < 2000; i++) insert.run(`other-${i}`, "another-workspace");
  insert.run("mine", "my-workspace");
  insert.run("private", "another-workspace");
  let sessionsRead = 0;
  const observed = {
    prepare(sql: string) {
      const statement = db.prepare(sql);
      const sessions = /\bFROM sessions\b/i.test(sql);
      return {
        all: (...params: any[]) => {
          const rows = statement.all(...params);
          if (sessions) sessionsRead += rows.length;
          return rows;
        },
        get: (...params: any[]) => {
          const row = statement.get(...params);
          if (sessions && row !== undefined) sessionsRead++;
          return row;
        },
      };
    },
  } as unknown as DatabaseSync;
  try {
    const answer = resourceChats(makeStore(observed, "."), ["mine", "private"], { workspace: "my-workspace", home: false });
    assert.deepEqual(answer, { mine: { thread: null, title: null }, private: null });
    assert.ok(sessionsRead <= 2, `read ${sessionsRead} sessions to name two`);
  } finally {
    db.close();
  }
});
