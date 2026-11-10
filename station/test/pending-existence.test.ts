import assert from "node:assert/strict";
import { constants } from "node:sqlite";
import { test } from "node:test";
import { Effect } from "effect";
import * as stores from "../src/store/store.ts";
import { Rig } from "./hub-fakes.ts";

function fixture() {
  const store = stores.Store.open(":memory:");
  store.insertSession({ key: "s", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w/s", token: "s", createdAt: 1, lastActiveAt: 1 });
  const thread = store.openThread("ember", "ember", "chat", null, null).id;
  store.joinThread(thread, "s", "ember");
  return { store, thread };
}

test("checking for pending work stops after one message and does not read its body", () => {
  const { store, thread } = fixture();
  try {
    assert.equal(store.pendingMessages("s").length, 0);
    const insert = store.db.prepare("INSERT INTO entries (thread, n, kind, author_kind, author, text, at) VALUES (?, ?, 'message', 'person', 'a', 'body', ?)");
    const deliver = store.db.prepare("INSERT INTO deliveries (thread, n, session) VALUES (?, ?, 's')");
    store.db.exec("BEGIN");
    for (let n = 1; n <= 2_000; n++) {
      insert.run(thread, n, n);
      deliver.run(thread, n);
    }
    store.db.exec("COMMIT");
    store.db.setAuthorizer((action, table, column) => action === constants.SQLITE_READ && table === "entries" && ["text", "attachments", "quotes"].includes(column ?? "") ? constants.SQLITE_DENY : constants.SQLITE_OK);
    try { assert.equal((store as any).hasPending("s"), true); }
    finally { store.db.setAuthorizer(null); }

    const sql = (stores as any).HAS_PENDING_MESSAGE as string;
    const plan = (store.db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all("s") as { detail: string }[]).map((r) => r.detail).join(" | ");
    assert.match(plan, /deliveries_pending \(session=\?\)/);
    let examined = 0;
    store.db.function("count_examined", (n) => { examined++; return n; });
    const probed = sql.replace("d.delivered_at IS NULL", "d.delivered_at IS NULL AND count_examined(d.n) IS NOT NULL");
    assert.ok(store.db.prepare(probed).get("s"));
    assert.equal(examined, 1, "more pending messages do not increase the work of an existence check");
    assert.equal((store as any).hasPending("other"), false);
  } finally { store.close(); }
});

test("the existence check follows the same joins as pending messages and letters", () => {
  const { store, thread } = fixture();
  try {
    // Old or partially removed data can leave a delivery without a corresponding message or membership.
    store.db.prepare("INSERT INTO deliveries (thread, n, session) VALUES (?, 999, 's')").run(thread);
    assert.equal(store.pendingMessages("s").length, 0);
    assert.equal((store as any).hasPending("s"), false);
    store.db.prepare("INSERT INTO letters (thread, n, ts, author_kind, author, text, at, letter) VALUES (?, 1, 'l', 'agent', 'a', 'letter', 1, '{}')").run(thread);
    store.db.prepare("INSERT INTO letter_deliveries (thread, n, session) VALUES (?, 1, 's')").run(thread);
    assert.equal(store.pendingMessages("s").length, 1);
    assert.equal((store as any).hasPending("s"), true);
    const sql = (stores as any).HAS_PENDING_LETTER as string;
    const plan = (store.db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all("s") as { detail: string }[]).map((r) => r.detail).join(" | ");
    assert.match(plan, /letter_deliveries_pending \(session=\?\)/);
    store.db.prepare("DELETE FROM thread_sessions WHERE thread = ? AND session = 's'").run(thread);
    assert.equal(store.pendingMessages("s").length, 0);
    assert.equal((store as any).hasPending("s"), false);
  } finally { store.close(); }
});

test("listing pending sessions skips the remaining deliveries of a session", () => {
  const { store, thread } = fixture();
  try {
    const insert = store.db.prepare("INSERT INTO deliveries (thread, n, session) VALUES (?, ?, 's')");
    store.db.exec("BEGIN");
    for (let n = 1; n <= 2_000; n++) insert.run(thread, n);
    store.db.exec("COMMIT");
    let examined = 0;
    store.db.function("count_examined", (s) => { examined++; return s; });
    const db = store.db;
    const traced = new Proxy(db, {
      get(target, property) {
        if (property === "prepare") return (sql: string) => target.prepare(
          sql.includes("letter_deliveries") && sql.includes("deliveries")
            ? sql.replace(/WHERE (?:[a-z]\.)?delivered_at IS NULL/g, (where) => `${where} AND count_examined(session) IS NOT NULL`)
            : sql,
        );
        const value = Reflect.get(target, property, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    Object.defineProperty(store, "db", { value: traced, configurable: true });
    try {
      assert.deepEqual(store.sessionsWithPending(), ["s"]);
      assert.equal(examined, 1, "more deliveries for the same session do not grow the list's work");
    } finally { Object.defineProperty(store, "db", { value: db, configurable: true }); }
  } finally { store.close(); }
});

test("pending session enumeration merges messages and letters in the same order, once each", () => {
  const { store, thread } = fixture();
  try {
    const message = store.db.prepare("INSERT INTO deliveries (thread, n, session, delivered_at) VALUES (?, ?, ?, ?)");
    message.run(thread, 1, "s", null);
    message.run(thread, 2, "z", null);
    message.run(thread, 3, "hidden", 1);
    const letter = store.db.prepare("INSERT INTO letter_deliveries (thread, n, session, delivered_at) VALUES (?, ?, ?, ?)");
    letter.run(thread, 1, "s", null);
    letter.run(thread, 2, "a", null);
    letter.run(thread, 3, "delivered", 1);
    assert.deepEqual(store.sessionsWithPending(), ["a", "s", "z"]);
    const plan = (store.db.prepare(`EXPLAIN QUERY PLAN ${stores.PENDING_SESSIONS}`).all() as { detail: string }[]).map((r) => r.detail).join(" | ");
    assert.match(plan, /SEARCH deliveries USING INDEX deliveries_pending \(session>\?\)/);
    assert.match(plan, /SEARCH letter_deliveries USING INDEX letter_deliveries_pending \(session>\?\)/);
  } finally { store.close(); }
});

test("rejoining one workspace does not enumerate every workspace's pending sessions", async () => {
  const rig = new Rig();
  const list = rig.store.listSessions;
  try {
    for (let i = 0; i < 8; i++) rig.store.insertSession({ key: `s${i}`, connect: "ember", runtime: "claude", profile: "cc", workspace: `/w/${i}`, token: `s${i}`, createdAt: 1, lastActiveAt: 1, ws: "W2" });
    const all = rig.store.sessionsWithPending;
    rig.store.sessionsWithPending = () => { throw new Error("enumerated other workspaces"); };
    rig.store.listSessions = () => { throw new Error("read all session history"); };
    try { assert.doesNotThrow(() => rig.hub.backIn("W2")); }
    finally { rig.store.sessionsWithPending = all; }
  } finally { rig.store.listSessions = list; await rig.close(); }
});

for (const stillJoined of [false, true]) test(`a workspace rejoining during index setup resumes only if still joined (${stillJoined})`, async () => {
  const rig = new Rig({ workspaces: ["home", "W2"] });
  try {
    rig.store.insertSession({ key: "waiting", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "waiting", createdAt: 1, lastActiveAt: 1, ws: "W2" });
    const thread = rig.store.openThread("ember", "ember", "chat", null, null).id;
    rig.store.joinThread(thread, "waiting", "ember");
    rig.store.db.prepare("INSERT INTO entries (thread,n,kind,author_kind,author,text,at) VALUES (?,1,'message','person','a','body',1)").run(thread);
    rig.store.db.prepare("INSERT INTO deliveries (thread,n,session) VALUES (?,1,'waiting')").run(thread);
    const actor = rig.hub.actor(rig.store.getSession("waiting")!);
    let kicks = 0;
    actor.kick = async () => { kicks++; };
    rig.store.db.prepare("UPDATE workspace_activity_meta SET complete=0 WHERE id=1").run();
    const completed = Promise.withResolvers<boolean>();
    let requests = 0;
    rig.hub.waitForWorkspaceActivity = () => { requests++; return completed.promise; };
    rig.hub.backIn("W2"); rig.hub.backIn("W2");
    assert.equal(requests, 1);
    assert.equal(kicks, 0);
    if (!stillJoined) rig.workspaces = ["home"];
    rig.store.db.prepare("UPDATE workspace_activity_meta SET complete=1 WHERE id=1").run();
    completed.resolve(true);
    await Promise.resolve();
    assert.equal(kicks, stillJoined ? 1 : 0);
  } finally { await rig.close(); }
});

test("rejoining resumes its running sessions and pending messages and letters only", async () => {
  const rig = new Rig();
  try {
    for (const [key, ws, connect, at] of [["running", "W2", "cl", 9], ["message", "W2", "cl", 8], ["letter", "W2", "cl", 7],
      ["orphan", "W2", "cl", 6], ["offline", "W2", "offline", 5], ["other", "W1", "cl", 4]] as const) {
      rig.store.insertSession({ key, connect, runtime: "claude", profile: "cc", workspace: `/w/${key}`, token: key, createdAt: 1, lastActiveAt: at, ws });
    }
    const db = rig.store.db;
    const thread = rig.store.openThread("cl", "cl", "chat", null, null).id;
    for (const key of ["running", "message", "letter", "orphan", "other"]) rig.store.joinThread(thread, key, "cl");
    const offlineThread = rig.store.openThread("offline", "offline", "chat", null, null).id;
    rig.store.joinThread(offlineThread, "offline", "offline");
    db.prepare("UPDATE sessions SET running = 1 WHERE key IN ('running', 'offline', 'other')").run();
    db.prepare("INSERT INTO entries (thread, n, kind, author_kind, author, text, at) VALUES (?, 1, 'message', 'person', 'a', 'body', 1)").run(thread);
    db.prepare("INSERT INTO letters (thread, n, ts, author_kind, author, text, at, letter) VALUES (?, 2, 'l', 'agent', 'a', 'letter', 1, '{}')").run(thread);
    db.prepare("INSERT INTO deliveries (thread, n, session) VALUES (?, 1, 'message'), (?, 1, 'running'), (?, 999, 'orphan')").run(thread, thread, thread);
    db.prepare("INSERT INTO letter_deliveries (thread, n, session) VALUES (?, 2, 'letter')").run(thread);
    const resumed: string[] = [];
    for (const row of rig.store.listSessions()) {
      const actor = rig.hub.actor(row);
      actor.recover = async () => { resumed.push(`recover:${row.key}`); };
      actor.kick = async () => { resumed.push(`kick:${row.key}`); };
    }
    rig.hub.backIn("W2");
    assert.deepEqual(resumed, ["recover:running", "kick:message", "kick:letter"]);
  } finally { await rig.close(); }
});

test("leaving a workspace checks its live actors without reading session history", async () => {
  const rig = new Rig();
  const list = rig.store.listSessions;
  const get = rig.store.getSession;
  try {
    for (let i = 0; i < 200; i++) rig.store.insertSession({ key: `old${i}`, connect: "ember", runtime: "claude", profile: "cc", workspace: `/w/${i}`,
      token: `old${i}`, createdAt: 1, lastActiveAt: 1, ws: "W1" });
    for (const [key, ws] of [["here", "W2"], ["elsewhere", "W1"], ["timer-here", "W2"], ["timer-elsewhere", "W1"]] as const) rig.store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: `/w/${key}`,
      token: key, createdAt: 1, lastActiveAt: 1, ws });
    const suspended: string[] = [];
    for (const key of ["here", "elsewhere"]) {
      const actor = rig.hub.actor(rig.store.getSession(key)!);
      actor.suspend = async () => { suspended.push(key); };
    }
    const deadlines = (rig.hub as any).deadlines as Map<string, unknown>;
    deadlines.set("here", Effect.runFork(Effect.never));
    deadlines.set("elsewhere", Effect.runFork(Effect.never));
    deadlines.set("timer-here", Effect.runFork(Effect.never));
    deadlines.set("timer-elsewhere", Effect.runFork(Effect.never));
    const checked: string[] = [];
    rig.store.listSessions = () => { throw new Error("session history was read"); };
    // (A session's workspace is asked as `sessionWs`, kept once read: asked here of each, none twice from the database.)
    const ws = rig.store.sessionWs;
    rig.store.sessionWs = function (key) { checked.push(key); return ws.call(this, key); };
    await rig.hub.leftWorkspace("W2");
    assert.deepEqual(suspended, ["here"]);
    assert.equal(deadlines.has("here"), false);
    assert.equal(deadlines.has("elsewhere"), true);
    assert.equal(deadlines.has("timer-here"), false, "a deadline can outlive its actor");
    assert.equal(deadlines.has("timer-elsewhere"), true);
    assert.deepEqual([...new Set(checked)].sort(), ["elsewhere", "here", "timer-elsewhere", "timer-here"]);
  } finally {
    rig.store.listSessions = list;
    rig.store.getSession = get;
    delete (rig.store as { sessionWs?: unknown }).sessionWs;
    await rig.close();
  }
});

test("a restart with only a shared runtime host reads only running sessions", async () => {
  for (const runners of [[], ["codex-cx"]]) {
    const rig = new Rig();
    const list = rig.store.listSessions;
    const hub = rig.newHub({ chats: () => undefined, runners });
    try {
      for (let i = 0; i < 200; i++) rig.store.insertSession({ key: `old${i}`, connect: "ember", runtime: "claude", profile: "cc", workspace: `/w/${i}`,
        token: `old${i}`, createdAt: 1, lastActiveAt: 1 });
      rig.store.insertSession({ key: "running-codex", connect: "ember", runtime: "codex", profile: "cx", workspace: rig.dir,
        token: "running-codex", runtimeSessionId: "running-runtime", createdAt: 1, lastActiveAt: 1 });
      rig.store.db.prepare("UPDATE sessions SET running = 1 WHERE key = ?").run("running-codex");
      rig.codex.left = { id: "running-runtime", busy: true };
      rig.store.listSessions = () => { throw new Error("session history was read"); };
      await hub.takeUp();
      assert.equal(rig.codex.last().sessionId, "running-runtime", "the running shared-host session is still taken up");
    } finally {
      rig.store.listSessions = list;
      await hub.shutdown();
      await rig.close();
    }
  }
});

test("resuming an idle session checks for pending work without loading its messages", async () => {
  const rig = new Rig();
  try {
    rig.store.insertSession({ key: "s", connect: "cl", runtime: "claude", profile: "cc", workspace: "/w/s", token: "s", createdAt: 1, lastActiveAt: 1 });
    const actor = rig.hub.actor(rig.store.getSession("s")!);
    let resumed = 0;
    (actor as any).startTurn = async () => { resumed++; };
    const load = rig.store.pendingMessages;
    rig.store.pendingMessages = () => { throw new Error("loaded pending message bodies"); };
    try { await actor.goOn(); }
    finally { rig.store.pendingMessages = load; }
    assert.equal(resumed, 1);
  } finally { await rig.close(); }
});
