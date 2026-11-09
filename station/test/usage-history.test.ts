import assert from "node:assert/strict";
import { constants } from "node:sqlite";
import { test } from "node:test";
import { makeStore, VISIBLE_USAGE_CARDS } from "../src/read/store.ts";
import { usage, usageHistory } from "../src/read/usage.ts";
import { Store } from "../src/store/store.ts";

function session(store: Store, key: string, ws: string | null) {
  store.insertSession({ key, connect: key, runtime: "claude", profile: "cc", workspace: `/w/${key}`, token: key, ws, createdAt: 1, lastActiveAt: 1 });
}

test("missing old decision results leave the available usage and chat totals visible", () => {
  const store = Store.open(":memory:");
  try {
    session(store, "a", "workspace-a");
    const thread = store.openThread("ember", "CHAT", "chat", null, null).id;
    store.joinThread(thread, "a", "ember");
    store.recordUsage("/a", { session: "a", offset: 1, model: "m" }, "claude", [[{
      id: "call", at: 60_000, model: "m", subagent: false, fast: false, input: 2, cacheRead: 0,
      cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null,
    }, { turn: null, thread, person: null, profile: "cc" }]]);
    store.db.exec("CREATE TABLE card_outcomes_incomplete (id INTEGER PRIMARY KEY)");
    const result = usage(makeStore(store.db, "."), "en", 0n, 180_000n, 0n, false, null, true);
    assert.equal(result.history.cardsIncomplete, true);
    assert.equal(result.history.cards, undefined);
    assert.equal(result.history.picked, undefined);
    assert.deepEqual(result.history.places, { ember: 1 });
    assert.deepEqual(result.history.days.map((day: { tokens: number }) => day.tokens), [3]);
  } finally { store.close(); }
});

test("usage history counts only the chats and cards visible in the viewer's workspace", () => {
  const store = Store.open(":memory:");
  try {
    session(store, "a", "workspace-a");
    session(store, "b", "workspace-b");
    const thread = (surface: string, id: string, members: string[], picked: boolean) => {
      const t = store.openThread(surface, id, id, null, null).id;
      for (const member of members) store.joinThread(t, member, member);
      store.db.prepare("INSERT INTO card_outcomes (thread, n, author, labels, answered, said) VALUES (?, 1, 'agent', '[]', 1, ?)").run(t, picked ? 1 : 0);
      return t;
    };
    thread("slack:a", "a", ["a"], true);
    const b = thread("feishu:b", "b", ["b"], false);
    thread("slack:shared", "shared", ["a", "b"], true);
    thread("ember", "orphan", [], false);
    store.db.prepare("UPDATE threads SET hidden_at = 1 WHERE id = ?").run(b);
    const reader = makeStore(store.db, ".");

    const a = usageHistory(reader, 0n, { workspace: "workspace-a", home: true });
    assert.deepEqual(a.places, { slack: 2, ember: 1 });
    assert.deepEqual([a.cards, a.picked, a.archived], [3, 2, 0]);
    const other = usageHistory(reader, 0n, { workspace: "workspace-b", home: false });
    assert.deepEqual(other.places, { feishu: 1, slack: 1 });
    assert.deepEqual([other.cards, other.picked, other.archived], [2, 1, 1]);
    const all = usageHistory(reader, 0n, null);
    assert.deepEqual([all.cards, all.picked, all.archived], [4, 2, 1]);

    const plan = store.db.prepare(`EXPLAIN QUERY PLAN ${VISIBLE_USAGE_CARDS}`).all("workspace-a", 1) as { detail: string }[];
    assert.match(plan.map((r) => r.detail).join(" | "), /SEARCH c USING PRIMARY KEY \(thread=\?\)/);
    let visited = 0;
    store.db.function("visited_card", (n) => { visited++; return n; });
    const tracked = store.db.prepare(VISIBLE_USAGE_CARDS.replace("ON c.thread = v.thread", "ON c.thread = v.thread AND visited_card(c.n) IS NOT NULL"));
    assert.equal(tracked.all("workspace-a", 1).length, 3);
    assert.equal(visited, 3);
    const insert = store.db.prepare("INSERT INTO card_outcomes (thread, n, author, labels, answered, said) VALUES (?, ?, 'agent', '[]', 1, 0)");
    store.db.exec("BEGIN");
    for (let n = 2; n <= 2_001; n++) insert.run(b, n);
    store.db.exec("COMMIT");
    visited = 0;
    assert.equal(tracked.all("workspace-a", 1).length, 3);
    assert.equal(visited, 3, "another workspace's card history does not add examined cards");
  } finally {
    store.close();
  }
});
