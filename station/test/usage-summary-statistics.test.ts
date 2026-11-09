import assert from "node:assert/strict";
import { constants } from "node:sqlite";
import { test } from "node:test";
import { makeStore } from "../src/read/store.ts";
import { usageHistory } from "../src/read/usage.ts";
import { Store } from "../src/store/store.ts";
import { backfillUsageChatStats } from "../src/store/usage-chat-stats.ts";

test("usage history reads chat and card totals from statistics rather than enumerating the records", () => {
  const store = Store.open(":memory:");
  try {
    for (const [key, ws] of [["a", "workspace-a"], ["b", "workspace-b"]]) {
      store.insertSession({ key: key!, connect: key!, runtime: "claude", profile: "cc", workspace: `/w/${key}`,
        token: key!, ws: ws!, createdAt: 1, lastActiveAt: 1 });
    }
    const thread = (surface: string, id: string, members: string[], picked: boolean) => {
      const t = store.openThread(surface, id, id, null, null).id;
      for (const member of members) store.joinThread(t, member, member);
      store.db.prepare("INSERT INTO card_outcomes (thread, n, author, labels, answered, said) VALUES (?, 1, 'agent', '[]', 1, ?)")
        .run(t, picked ? 1 : 0);
      return t;
    };
    thread("slack:a", "a", ["a"], true);
    const b = thread("feishu:b", "b", ["b"], false);
    const shared = thread("slack:shared", "shared", ["a", "b"], true);
    thread("ember", "orphan", [], false);
    store.db.prepare("UPDATE threads SET hidden_at = 1 WHERE id = ?").run(b);
    store.db.prepare("INSERT OR REPLACE INTO card_outcomes VALUES (?, 1, 'agent', '[]', 1, 1)").run(shared);
    store.db.prepare("INSERT OR REPLACE INTO thread_sessions (thread, session, connect, joined_at) VALUES (?, 'a', 'a', 1)").run(shared);

    // Neither the source chats and their memberships nor the per-card outcomes should be enumerated to answer the
    // summary. Changes above, including a shared chat and an archived chat, must already be reflected in statistics.
    const records = new Set(["threads", "thread_sessions", "card_outcomes", "closed_cards"]);
    store.db.setAuthorizer((action, table) => action === constants.SQLITE_READ && records.has(table ?? "")
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try {
      const summary = usageHistory(makeStore(store.db, "."), 0n, { workspace: "workspace-a", home: true });
      assert.deepEqual(summary.places, { slack: 2, ember: 1 });
      assert.deepEqual([summary.cards, summary.picked, summary.archived], [3, 2, 0]);
    } finally {
      store.db.setAuthorizer(null);
    }

    // More than one session in the same workspace must count the shared chat once. Moving one away must leave it
    // visible through the other; closing a card and archiving a chat update the same maintained totals.
    store.insertSession({ key: "a2", connect: "a2", runtime: "claude", profile: "cc", workspace: "/w/a2",
      token: "a2", ws: "workspace-a", createdAt: 1, lastActiveAt: 1 });
    store.joinThread(shared, "a2", "a2");
    store.db.prepare("UPDATE sessions SET ws = 'workspace-b' WHERE key = 'a'").run();
    while (!backfillUsageChatStats(store.db, 4).done) {}
    store.db.prepare("UPDATE card_outcomes SET said = 0 WHERE thread = ?").run(shared);
    store.db.prepare("INSERT INTO closed_cards (thread, n, viewer, at) VALUES (?, 1, 'person', 2)").run(shared);
    store.db.prepare("UPDATE threads SET hidden_at = 3 WHERE id = ?").run(shared);

    store.db.setAuthorizer((action, table) => action === constants.SQLITE_READ && records.has(table ?? "")
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try {
      const summary = usageHistory(makeStore(store.db, "."), 0n, { workspace: "workspace-a", home: true });
      assert.deepEqual(summary.places, { slack: 1, ember: 1 });
      assert.deepEqual([summary.cards, summary.picked, summary.archived], [2, 1, 1]);
    } finally {
      store.db.setAuthorizer(null);
    }

    // A home session and a session in the requested workspace can both see the same thread. Their contributions
    // still represent a single chat and card, not one of each per membership.
    store.db.prepare("UPDATE sessions SET ws = NULL WHERE key = 'a2'").run();
    while (!backfillUsageChatStats(store.db, 4).done) {}
    store.db.prepare("UPDATE closed_cards SET viewer = 'agent' WHERE thread = ? AND n = 1").run(shared);
    store.db.setAuthorizer((action, table) => action === constants.SQLITE_READ && records.has(table ?? "")
      ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try {
      const summary = usageHistory(makeStore(store.db, "."), 0n, { workspace: "workspace-b", home: true });
      assert.deepEqual(summary.places, { slack: 2, feishu: 1, ember: 1 });
      assert.deepEqual([summary.cards, summary.picked, summary.archived], [4, 1, 2]);
    } finally {
      store.db.setAuthorizer(null);
    }
  } finally {
    store.close();
  }
});

test("joining one workspace does not rewrite a shared chat's other workspace totals", () => {
  const store = Store.open(":memory:");
  try {
    const thread = store.openThread("ember", "shared", "shared", null, null).id;
    for (let i = 0; i < 80; i++) {
      const key = `s${i}`, ws = `workspace-${i}`;
      store.insertSession({ key, connect: key, runtime: "claude", profile: "cc", workspace: `/w/${key}`,
        token: key, ws, createdAt: 1, lastActiveAt: 1 });
      store.joinThread(thread, key, key);
    }
    store.insertSession({ key: "new", connect: "new", runtime: "claude", profile: "cc", workspace: "/w/new",
      token: "new", ws: "new", createdAt: 1, lastActiveAt: 1 });
    store.db.exec(`CREATE TEMP TABLE scope_changes (n INTEGER NOT NULL);
      INSERT INTO scope_changes VALUES (0);
      CREATE TEMP TRIGGER scope_insert AFTER INSERT ON main.usage_chat_scopes BEGIN UPDATE scope_changes SET n = n + 1; END;
      CREATE TEMP TRIGGER scope_delete AFTER DELETE ON main.usage_chat_scopes BEGIN UPDATE scope_changes SET n = n + 1; END;`);
    store.joinThread(thread, "new", "new");
    const changes = (store.db.prepare("SELECT n FROM scope_changes").get() as { n: number }).n;
    assert.ok(changes <= 2, `joining one workspace changed ${changes} scopes`);
    store.insertSession({ key: "new2", connect: "new2", runtime: "claude", profile: "cc", workspace: "/w/new2",
      token: "new2", ws: "new", createdAt: 1, lastActiveAt: 1 });
    store.db.exec("UPDATE scope_changes SET n = 0");
    store.db.prepare("INSERT OR REPLACE INTO thread_sessions (thread, session, connect, joined_at) VALUES (?, 'new2', 'new2', 1)").run(thread);
    store.db.prepare("DELETE FROM thread_sessions WHERE thread = ? AND session = 'new'").run(thread);
    assert.equal((store.db.prepare("SELECT n FROM scope_changes").get() as { n: number }).n, 0,
      "another session in the same workspace does not change its contribution");
    store.db.prepare("DELETE FROM thread_sessions WHERE thread = ? AND session = 'new2'").run(thread);
    assert.equal((store.db.prepare("SELECT n FROM scope_changes").get() as { n: number }).n, 1,
      "the last session takes away only its workspace's contribution");
  } finally { store.close(); }
});
