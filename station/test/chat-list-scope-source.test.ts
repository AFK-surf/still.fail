import assert from "node:assert/strict";
import { test } from "node:test";
import { FIRST_SCOPE_CONNECT, FIRST_SCOPE_HOME_THREADS, FIRST_SCOPE_MEMBER_THREADS, FIRST_SCOPE_SESSIONS,
  NEXT_SCOPE_CONNECT, recentScopeSessionThreadsStep, recentScopeSessionsStep, SCOPE_HOME_THREADS, SCOPE_MEMBER_THREADS,
  SCOPE_MEMBER_WITHOUT_HOME, SCOPE_SESSIONS, type RecentScopeSessionCursor, type RecentScopeThreadCursor } from "../src/store/chat-list-scope-source.ts";
import { Store } from "../src/store/store.ts";

test("a workspace's old sessions are sought by connection in bounded steps", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    const expected: string[] = [];
    for (let i = 0; i < 110; i++) {
      const key = `agent-${i}`;
      const connect = ["a", "b", "c", "d"][i % 4]!;
      const ws = i % 5 === 0 ? "here" : "elsewhere";
      store.insertSession({ key, connect, runtime: "claude", profile: "cc", workspace: "/work",
        token: key, createdAt: i, lastActiveAt: i, ws });
      if (ws === "here") expected.push(key);
    }
    db.prepare("UPDATE sessions SET rowid = ? WHERE key = 'agent-0'").run(9_007_199_254_741_011n);
    let cursor: RecentScopeSessionCursor = { connect: null, after: null, done: false };
    const found: string[] = [];
    for (let step = 0; step < 100 && !cursor.done; step++) {
      const result = recentScopeSessionsStep(db, "here", cursor, 3);
      assert.ok(result.sessions.length <= 3);
      found.push(...result.sessions.map((session) => session.key));
      cursor = result.cursor;
    }
    assert.equal(cursor.done, true);
    assert.deepEqual([...found].sort(), expected.sort());
    assert.deepEqual(recentScopeSessionsStep(db, "here", cursor, 3), { sessions: [], cursor });
    assert.throws(() => recentScopeSessionsStep(db, "here", cursor, 0), RangeError);
  } finally { store.close(); }
});

test("workspace session batches use the existing covering order without sorting the workspace", () => {
  const store = Store.open(":memory:");
  try {
    for (const [sql, args] of [[FIRST_SCOPE_CONNECT, []], [NEXT_SCOPE_CONNECT, ["a"]],
      [FIRST_SCOPE_SESSIONS, ["a", "here", 3]], [SCOPE_SESSIONS, ["a", "here", 0n, 3]]] as const) {
      const rows = store.db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...args) as { detail: string }[];
      const plan = rows.map((row) => row.detail).join("; ");
      assert.match(plan, /sessions_by_connect/, plan);
      assert.doesNotMatch(plan, /TEMP B-TREE/, plan);
      if (sql === FIRST_SCOPE_SESSIONS || sql === SCOPE_SESSIONS) assert.match(plan, /connect=\? AND ws=\?/, plan);
    }
  } finally { store.close(); }
});

test("a session's home and member chats are found in bounded source batches", () => {
  const store = Store.open(":memory:");
  const db = store.db;
  try {
    const expected: bigint[] = [];
    for (let i = 0; i < 125; i++) {
      const id = store.openThread("ember", "EMBER", `chat-${i}`, "Chat", null).id;
      if (i < 3) {
        db.prepare("UPDATE threads SET home = 'ours' WHERE id = ?").run(id);
        expected.push(BigInt(id));
      } else if (i < 8) expected.push(BigInt(id));
      else db.prepare("UPDATE threads SET home = 'someone-else' WHERE id = ?").run(id);
      store.joinThread(id, "ours", "ember");
    }
    db.prepare("UPDATE thread_sessions SET rowid = ? WHERE thread = ? AND session = 'ours'")
      .run(9_007_199_254_741_013n, expected.at(-1)!);
    let cursor: RecentScopeThreadCursor = { phase: "home", after: null };
    const found: bigint[] = [];
    let steps = 0;
    while (cursor.phase !== "done" && steps++ < 100) {
      const result = recentScopeSessionThreadsStep(db, "ours", cursor, 3);
      assert.ok(result.visited <= 3, "the home filter is applied after the source limit");
      found.push(...result.threads);
      cursor = result.cursor;
    }
    assert.equal(cursor.phase, "done");
    assert.deepEqual(found.sort((a, b) => a < b ? -1 : a > b ? 1 : 0), expected);
    assert.deepEqual(recentScopeSessionThreadsStep(db, "ours", cursor, 3), { threads: [], visited: 0, cursor });
    assert.throws(() => recentScopeSessionThreadsStep(db, "ours", cursor, 0), RangeError);
  } finally { store.close(); }
});

test("a session's chat sources seek the existing indexes before applying the limit", () => {
  const store = Store.open(":memory:");
  try {
    for (const [sql, args, index] of [[FIRST_SCOPE_HOME_THREADS, ["ours", 3], "threads_home"],
      [SCOPE_HOME_THREADS, ["ours", 0n, 3], "threads_home"], [FIRST_SCOPE_MEMBER_THREADS, ["ours", 3], "thread_sessions_session"],
      [SCOPE_MEMBER_THREADS, ["ours", 0n, 3], "thread_sessions_session"], [SCOPE_MEMBER_WITHOUT_HOME, [1n], "INTEGER PRIMARY KEY"]] as const) {
      const plan = (store.db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...args) as { detail: string }[]).map((row) => row.detail).join("; ");
      assert.ok(plan.includes(index) && plan.includes("SEARCH"), plan);
      assert.doesNotMatch(plan, /TEMP B-TREE/, plan);
    }
  } finally { store.close(); }
});
