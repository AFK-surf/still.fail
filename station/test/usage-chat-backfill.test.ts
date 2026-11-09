import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { constants } from "node:sqlite";
import { test } from "node:test";
import { Readers } from "../src/read/pool.ts";
import { decisionCards, makeStore, threadsByPlace, usageChatTotals } from "../src/read/store.ts";
import { usage } from "../src/read/usage.ts";
import { backfillUsageChatStats, installUsageChatStats } from "../src/store/usage-chat-stats.ts";
import { Store } from "../src/store/store.ts";
import type { InWorkspace } from "../src/store/rows.ts";
import { MinuteReader } from "../src/usage/minute-reader.ts";

function oldSchema(store: Store) {
  const objects = store.db.prepare("SELECT type, name FROM sqlite_master WHERE name LIKE 'usage_chat_%' AND type IN ('trigger', 'table') ORDER BY type DESC").all() as { type: string; name: string }[];
  for (const object of objects) store.db.exec(`DROP ${object.type.toUpperCase()} "${object.name}"`);
}

function expected(store: Store, viewer: InWorkspace | null) {
  const reader = makeStore(store.db, ".");
  const places: Record<string, number> = {};
  let archived = 0;
  for (const row of threadsByPlace(reader, viewer)) {
    const place = row.surface.split(":")[0]!;
    places[place] = (places[place] ?? 0) + 1;
    if (row.archived) archived++;
  }
  const cards = decisionCards(reader, viewer);
  return { places, archived, cards: cards.length, picked: cards.filter((c) => c.picked).length };
}

test("old chat totals fill in bounded resumable batches while writes and workspace moves continue", () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-chat-index-"));
  const path = join(dir, "stillfail.db");
  let store = Store.open(path);
  try {
    for (const [key, ws] of [["a", "A"], ["b", "B"], ["home", null]] as const) {
      store.insertSession({ key, connect: key, runtime: "claude", profile: "cc", workspace: `/w/${key}`,
        token: key, ws, createdAt: 1, lastActiveAt: 1 });
    }
    const addCard = store.db.prepare("INSERT INTO card_outcomes (thread, n, author, labels, answered, said) VALUES (?, ?, 'agent', '[]', 1, ?)");
    const ids: number[] = [];
    for (let i = 0; i < 48; i++) {
      const t = store.openThread(i % 2 ? "slack:one" : "ember", `${i}`, `${i}`, null, null).id;
      ids.push(t);
      if (i % 4 !== 0) store.joinThread(t, i % 2 ? "a" : "b", "connect");
      if (i % 5 === 0) store.joinThread(t, "home", "connect");
      if (i % 3 === 0) addCard.run(t, 1, i % 2);
    }
    // A card whose thread has disappeared remains part of the unscoped total.
    addCard.run(-1, 1, 1);
    oldSchema(store);

    // Opening the new version installs metadata and triggers, but does not visit old chat/card contents.
    store.db.setAuthorizer((action, table, column) => action === constants.SQLITE_READ &&
      ((table === "threads" && (column === "surface" || column === "hidden_at")) ||
       (table === "card_outcomes" && (column === "author" || column === "said"))) ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try { installUsageChatStats(store.db); } finally { store.db.setAuthorizer(null); }
    const reader = makeStore(store.db, dir);
    assert.throws(() => usageChatTotals(reader, null), /chat statistics.*being filled/);
    store.db.setAuthorizer((action, table) => action === constants.SQLITE_READ && table === "usage" ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try { assert.equal(usage(reader, "en", 0n, 1n, 0n, false, null, true).history.chatsIncomplete, true); }
    finally { store.db.setAuthorizer(null); }
    assert.deepEqual(backfillUsageChatStats(store.db, 4), { done: false, processed: 4 });

    // Exercise writes on either side of the cursor as an older station would, including replacement and closure.
    store.db.prepare("UPDATE threads SET surface = 'feishu:changed', hidden_at = 1 WHERE id = ?").run(ids[1]!);
    store.db.prepare("UPDATE sessions SET ws = 'B' WHERE key = 'a'").run();
    store.db.prepare("DELETE FROM thread_sessions WHERE thread = ? AND session = 'home'").run(ids[5]!);
    store.joinThread(ids[2]!, "home", "connect");
    store.db.prepare("DELETE FROM card_outcomes WHERE thread = ? AND n = 1").run(ids[0]!);
    addCard.run(ids[2]!, 2, 0);
    store.db.prepare("INSERT INTO closed_cards VALUES (?, 2, 'person', 2)").run(ids[2]!);
    store.db.prepare("INSERT OR REPLACE INTO card_outcomes VALUES (?, 1, 'agent', '[]', 1, 1)").run(ids[3]!);
    store.close();
    store = Store.open(path);

    let step: { done: boolean; processed: number };
    do { step = backfillUsageChatStats(store.db, 4); assert.ok(step.processed <= 4); } while (!step.done);
    for (const viewer of [null, { workspace: "A", home: false }, { workspace: "B", home: false }, { workspace: "B", home: true }] as (InWorkspace | null)[]) {
      assert.deepEqual(usageChatTotals(makeStore(store.db, dir), viewer), expected(store, viewer));
    }
    const plan = (store.db.prepare("EXPLAIN QUERY PLAN SELECT place, chats, archived, cards, picked FROM usage_chat_totals WHERE kind = ? AND ws = ?").all(2, "A") as { detail: string }[]).map((r) => r.detail).join(" | ");
    assert.match(plan, /PRIMARY KEY \(kind=\? AND ws=\?\)/);
  } finally { store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("an incomplete chat summary is omitted without holding a reader or rebuilding history", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-chat-wait-"));
  const path = join(dir, "stillfail.db");
  let store = Store.open(path);
  store.openThread("ember", "old", "old", null, null);
  oldSchema(store);
  store.close();
  store = Store.open(path);
  let handover!: () => void;
  const previousGone = new Promise<void>((resolve) => { handover = resolve; });
  const readers = new Readers(dir, 1, undefined, 1, { previousGone });
  const before = store.db.prepare("SELECT * FROM usage_chat_progress").get();
  const history = readers.read("usage", { from: 0, to: 100, tz: 0, reading: false, history: true, viewer: null }, "en");
  try {
    await readers.read("checkpoint", {}, "en");
    const result = JSON.parse(await history);
    assert.equal(result.history.chatsIncomplete, true, "the chats are not said until their statistics are filled");
    assert.equal(result.history.archived, undefined);
    assert.deepEqual(result.rows, []);
    handover();
    assert.deepEqual(store.db.prepare("SELECT * FROM usage_chat_progress").get(), before);
  } finally { handover(); readers.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("chat summary waiters are released on shutdown and ready summaries skip other backfills", async () => {
  const waiting = new MinuteReader("unused", { previousGone: new Promise<void>(() => {}) });
  const pending = assert.rejects(waiting.readyChats(), /station stopping/);
  await waiting.close();
  await pending;
  const dir = mkdtempSync(join(tmpdir(), "usage-chat-ready-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path);
  store.db.exec("UPDATE usage_minute_all SET done = 0 WHERE id = 1");
  const priority = new SharedArrayBuffer(8);
  Atomics.store(new Int32Array(priority), 0, 1);
  const reader = new MinuteReader(path, { priority });
  try {
    await reader.readyChats();
    assert.equal((store.db.prepare("SELECT done FROM usage_minute_all").get() as { done: number }).done, 0);
  } finally { await reader.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("an incomplete chat summary does not attempt to fill a missing index", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-chat-error-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path);
  const thread = store.openThread("ember", "old", "old", null, null).id;
  store.db.prepare("INSERT INTO card_outcomes VALUES (?, 1, 'agent', '[]', 1, 0)").run(thread);
  oldSchema(store);
  installUsageChatStats(store.db);
  store.db.exec("DROP TABLE usage_chat_cards");
  const reader = new MinuteReader(path);
  try {
    await assert.rejects(reader.readyChats(), /chat.*unavailable/);
    await assert.rejects(reader.readyChats(), /chat.*unavailable/);
    await reader.readyRemote();
  } finally { await reader.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("maintained chat totals agree with visible records through membership and card changes", () => {
  const store = Store.open(":memory:");
  try {
    const addSession = (key: string, ws: string | null) => store.insertSession({ key, connect: key, runtime: "claude",
      profile: "cc", workspace: `/w/${key}`, token: key, ws, createdAt: 1, lastActiveAt: 1 });
    for (let i = 0; i < 6; i++) addSession(`s${i}`, ["A", "B", null][i % 3]!);
    const threads = Array.from({ length: 12 }, (_, i) => store.openThread(i % 2 ? "slack:w" : "ember", `${i}`, `${i}`, null, null).id);
    let seed = 173;
    const next = (n: number) => { seed = (seed * 48271) % 2147483647; return seed % n; };
    const db = store.db;
    const viewers: (InWorkspace | null)[] = [null, { workspace: "A", home: false }, { workspace: "A", home: true }, { workspace: "B", home: false }, { workspace: "B", home: true }];
    for (let i = 0; i < 160; i++) {
      const thread = threads[next(threads.length)]!, session = `s${next(6)}`, n = 1 + next(4);
      const operation = next(10);
      switch (operation) {
        case 0: db.prepare("INSERT OR IGNORE INTO thread_sessions (thread, session, connect, joined_at) VALUES (?, ?, 'connect', 1)").run(thread, session); break;
        case 1: db.prepare("DELETE FROM thread_sessions WHERE thread = ? AND session = ?").run(thread, session); break;
        case 2: db.prepare("UPDATE sessions SET ws = ? WHERE key = ?").run(["A", "B", null][next(3)]!, session); break;
        case 3: db.prepare("UPDATE threads SET hidden_at = ? WHERE id = ?").run(next(2) ? 1 : null, thread); break;
        case 4: db.prepare("INSERT OR REPLACE INTO card_outcomes VALUES (?, ?, 'agent', '[]', 1, ?)").run(thread, n, next(2)); break;
        case 5: db.prepare("DELETE FROM card_outcomes WHERE thread = ? AND n = ?").run(thread, n); break;
        case 6: db.prepare("INSERT OR REPLACE INTO closed_cards VALUES (?, ?, ?, 1)").run(thread, n, next(2) ? "agent" : "person"); break;
        case 7: db.prepare("INSERT OR REPLACE INTO thread_sessions (thread, session, connect, joined_at) VALUES (?, ?, 'connect', 1)").run(thread, session); break;
        case 8: db.prepare("UPDATE threads SET surface = ? WHERE id = ?").run(next(2) ? "slack:w" : "ember", thread); break;
        case 9: db.prepare("DELETE FROM closed_cards WHERE thread = ? AND n = ?").run(thread, n); break;
      }
      while (!backfillUsageChatStats(db, 4).done) {}
      for (const viewer of viewers) assert.deepEqual(usageChatTotals(makeStore(db, "."), viewer), expected(store, viewer),
        `change ${i}, operation ${operation}, thread ${thread}, viewer ${JSON.stringify(viewer)}`);
    }
    // A membership can outlive its session; the home view only owns it once the missing session actually has no workspace.
    db.prepare("INSERT OR IGNORE INTO thread_sessions (thread, session, connect, joined_at) VALUES (?, 'missing', 'connect', 1)").run(threads[0]!);
    for (const viewer of viewers) assert.deepEqual(usageChatTotals(makeStore(db, "."), viewer), expected(store, viewer));
    addSession("missing", null);
    while (!backfillUsageChatStats(db, 4).done) {}
    for (const viewer of viewers) assert.deepEqual(usageChatTotals(makeStore(db, "."), viewer), expected(store, viewer));
    db.prepare("DELETE FROM sessions WHERE key = 'missing'").run();
    while (!backfillUsageChatStats(db, 4).done) {}
    for (const viewer of viewers) assert.deepEqual(usageChatTotals(makeStore(db, "."), viewer), expected(store, viewer));
  } finally { store.close(); }
});

test("moving a session does not rewrite all of its chat statistics in the foreground", () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "s", connect: "s", runtime: "claude", profile: "cc", workspace: "/w/s",
      token: "s", ws: "A", createdAt: 1, lastActiveAt: 1 });
    for (let i = 0; i < 80; i++) {
      const thread = store.openThread("ember", `${i}`, `${i}`, null, null).id;
      store.joinThread(thread, "s", "s");
    }
    store.db.exec(`CREATE TEMP TABLE member_changes (n INTEGER NOT NULL);
      INSERT INTO member_changes VALUES (0);
      CREATE TEMP TRIGGER member_update AFTER UPDATE ON main.usage_chat_members BEGIN UPDATE member_changes SET n = n + 1; END;`);
    store.db.prepare("UPDATE sessions SET ws = 'B' WHERE key = 's'").run();
    const changes = (store.db.prepare("SELECT n FROM member_changes").get() as { n: number }).n;
    assert.equal(changes, 0, `moving the session rewrote ${changes} chat memberships in the foreground`);
    assert.throws(() => usageChatTotals(makeStore(store.db, "."), { workspace: "B", home: false }), /chat statistics.*being filled/);
    assert.deepEqual(backfillUsageChatStats(store.db, 5), { done: false, processed: 5 });
    // Another move while filling restarts the cursor so already-visited chats follow the newest workspace too.
    store.db.prepare("UPDATE sessions SET ws = 'C' WHERE key = 's'").run();
    let step: { done: boolean; processed: number };
    do { step = backfillUsageChatStats(store.db, 5); assert.ok(step.processed <= 5); } while (!step.done);
    assert.deepEqual(usageChatTotals(makeStore(store.db, "."), { workspace: "C", home: false }),
      { places: { ember: 80 }, archived: 0, cards: 0, picked: 0 });
    assert.deepEqual(usageChatTotals(makeStore(store.db, "."), { workspace: "B", home: false }),
      { places: {}, archived: 0, cards: 0, picked: 0 });
  } finally { store.close(); }
});

test("a moved session leaves affected chat totals unavailable until their scope is correct", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-chat-move-worker-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path);
  store.insertSession({ key: "s", connect: "s", runtime: "claude", profile: "cc", workspace: "/w/s",
    token: "s", ws: "A", createdAt: 1, lastActiveAt: 1 });
  const thread = store.openThread("ember", "shared", "shared", null, null).id;
  store.joinThread(thread, "s", "s");
  const worker = new MinuteReader(path);
  try {
    await worker.readyChats();
    store.db.prepare("UPDATE sessions SET ws = 'B' WHERE key = 's'").run();
    assert.throws(() => usageChatTotals(makeStore(store.db, dir), { workspace: "B", home: false }), /chat statistics.*being filled/);
    await assert.rejects(worker.readyChats({ workspace: "A", home: false }), /chat.*unavailable/);
    await assert.rejects(worker.readyChats({ workspace: "B", home: false }), /chat.*unavailable/);
    await worker.readyChats({ workspace: "C", home: false });
    assert.deepEqual(usageChatTotals(makeStore(store.db, dir), { workspace: "C", home: false }),
      { places: {}, archived: 0, cards: 0, picked: 0 });
  } finally { await worker.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("a session moving between two workspaces does not hold a third workspace's ready totals", () => {
  const store = Store.open(":memory:");
  try {
    for (const ws of ["A", "C"]) {
      store.insertSession({ key: ws, connect: ws, runtime: "claude", profile: "cc", workspace: `/w/${ws}`,
        token: ws, ws, createdAt: 1, lastActiveAt: 1 });
      const thread = store.openThread("ember", ws, ws, null, null).id;
      store.joinThread(thread, ws, ws);
    }
    store.db.prepare("UPDATE sessions SET ws = 'B' WHERE key = 'A'").run();
    const reader = makeStore(store.db, ".");
    assert.throws(() => usageChatTotals(reader, { workspace: "A", home: false }), /chat statistics.*being filled/);
    assert.throws(() => usageChatTotals(reader, { workspace: "B", home: false }), /chat statistics.*being filled/);
    assert.deepEqual(usageChatTotals(reader, { workspace: "C", home: false }), { places: { ember: 1 }, archived: 0, cards: 0, picked: 0 });
    assert.deepEqual(usageChatTotals(reader, { workspace: "C", home: true }), { places: { ember: 1 }, archived: 0, cards: 0, picked: 0 });
    assert.throws(() => usageChatTotals(reader, null), /chat statistics.*being filled/);
    store.db.prepare("UPDATE sessions SET ws = NULL WHERE key = 'A'").run();
    assert.throws(() => usageChatTotals(reader, { workspace: "C", home: true }), /chat statistics.*being filled/);
    assert.deepEqual(usageChatTotals(reader, { workspace: "C", home: false }), { places: { ember: 1 }, archived: 0, cards: 0, picked: 0 });
    while (!backfillUsageChatStats(store.db, 4).done) {}
    assert.deepEqual(usageChatTotals(reader, { workspace: "C", home: true }), { places: { ember: 2 }, archived: 0, cards: 0, picked: 0 });
  } finally { store.close(); }
});

test("a moved session does not prevent an unrelated workspace reading its totals", async () => {
  const dir = mkdtempSync(join(tmpdir(), "usage-chat-move-isolation-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path);
  store.insertSession({ key: "s", connect: "s", runtime: "claude", profile: "cc", workspace: "/w/s",
    token: "s", ws: "A", createdAt: 1, lastActiveAt: 1 });
  const thread = store.openThread("ember", "shared", "shared", null, null).id;
  store.joinThread(thread, "s", "s");
  store.db.prepare("UPDATE sessions SET ws = 'B' WHERE key = 's'").run();
  const priority = new SharedArrayBuffer(8);
  Atomics.store(new Int32Array(priority), 0, 1);
  const worker = new MinuteReader(path, { priority });
  const unavailable = assert.rejects(worker.readyChats({ workspace: "A", home: false }), /chat.*unavailable/);
  try {
    await worker.readyChats({ workspace: "C", home: false });
    await unavailable;
    assert.equal((store.db.prepare("SELECT COUNT(*) AS n FROM usage_chat_dirty").get() as { n: number }).n, 1);
    Atomics.store(new Int32Array(priority), 0, 0);
    await assert.rejects(worker.readyChats({ workspace: "B", home: false }), /chat.*unavailable/);
    assert.deepEqual(usageChatTotals(makeStore(store.db, dir), { workspace: "C", home: false }),
      { places: {}, archived: 0, cards: 0, picked: 0 });
  } finally { Atomics.store(new Int32Array(priority), 0, 0); await worker.close(); store.close(); rmSync(dir, { recursive: true, force: true }); }
});

test("replacing a session invalidates the previous workspace as well as the new one", () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "s", connect: "s", runtime: "claude", profile: "cc", workspace: "/w/s",
      token: "s", ws: "A", createdAt: 1, lastActiveAt: 1 });
    const thread = store.openThread("ember", "chat", "chat", null, null).id;
    store.joinThread(thread, "s", "s");
    store.db.exec(`INSERT OR REPLACE INTO sessions
      (key, connect, scope, runtime, profile, workspace, token, created_at, last_active_at, ws)
      VALUES ('s', 's', 'thread', 'claude', 'cc', '/w/s', 's', 1, 1, 'B')`);
    const reader = makeStore(store.db, ".");
    assert.throws(() => usageChatTotals(reader, { workspace: "A", home: false }), /chat statistics.*being filled/);
    assert.throws(() => usageChatTotals(reader, { workspace: "B", home: false }), /chat statistics.*being filled/);
    while (!backfillUsageChatStats(store.db, 4).done) {}
    assert.deepEqual(usageChatTotals(reader, { workspace: "A", home: false }), { places: {}, archived: 0, cards: 0, picked: 0 });
    assert.deepEqual(usageChatTotals(reader, { workspace: "B", home: false }), { places: { ember: 1 }, archived: 0, cards: 0, picked: 0 });
  } finally { store.close(); }
});

test("replacing another session by token invalidates the removed session's workspace", () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "s", connect: "s", runtime: "claude", profile: "cc", workspace: "/w/s",
      token: "shared", ws: "A", createdAt: 1, lastActiveAt: 1 });
    const thread = store.openThread("ember", "chat", "chat", null, null).id;
    store.joinThread(thread, "s", "s");
    store.db.exec(`INSERT OR REPLACE INTO sessions
      (key, connect, scope, runtime, profile, workspace, token, created_at, last_active_at, ws)
      VALUES ('new', 'new', 'thread', 'claude', 'cc', '/w/new', 'shared', 1, 1, 'B')`);
    const reader = makeStore(store.db, ".");
    assert.throws(() => usageChatTotals(reader, { workspace: "A", home: false }), /chat statistics.*being filled/);
    assert.deepEqual(usageChatTotals(reader, { workspace: "B", home: false }), { places: {}, archived: 0, cards: 0, picked: 0 });
    while (!backfillUsageChatStats(store.db, 4).done) {}
    assert.deepEqual(usageChatTotals(reader, { workspace: "A", home: false }), { places: {}, archived: 0, cards: 0, picked: 0 });
  } finally { store.close(); }
});

test("a returned chat keeps the cards and memberships remembered while it was absent", () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "s", connect: "s", runtime: "claude", profile: "cc", workspace: "/w/s",
      token: "s", ws: "A", createdAt: 1, lastActiveAt: 1 });
    const thread = store.openThread("ember", "chat", "chat", null, null).id;
    store.joinThread(thread, "s", "s");
    store.db.prepare("INSERT INTO card_outcomes VALUES (?, 1, 'agent', '[]', 1, 1)").run(thread);
    store.db.prepare("DELETE FROM threads WHERE id = ?").run(thread);
    store.db.prepare("INSERT OR IGNORE INTO threads (id, surface, channel, thread_ts, created_at) VALUES (?, 'ember', 'chat', 'chat', 1)").run(thread);
    const viewer = { workspace: "A", home: false };
    assert.deepEqual(usageChatTotals(makeStore(store.db, "."), viewer), expected(store, viewer));
    assert.deepEqual(usageChatTotals(makeStore(store.db, "."), viewer), { places: { ember: 1 }, archived: 0, cards: 1, picked: 1 });
  } finally { store.close(); }
});
