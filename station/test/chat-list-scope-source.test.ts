import assert from "node:assert/strict";
import { test } from "node:test";
import { FIRST_SCOPE_CONNECT, FIRST_SCOPE_SESSIONS, NEXT_SCOPE_CONNECT, recentScopeSessionsStep, SCOPE_SESSIONS,
  type RecentScopeSessionCursor } from "../src/store/chat-list-scope-source.ts";
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
