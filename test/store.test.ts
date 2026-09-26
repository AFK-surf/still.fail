import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Store } from "../src/store.ts";

/** A database as ember left it at schema v9, with a row of every kind. */
function v9(): string {
  const path = join(mkdtempSync(join(tmpdir(), "ember-v9-")), "ember.db");
  const db = new DatabaseSync(path);
  db.exec(`
    CREATE TABLE sessions (key TEXT PRIMARY KEY, connect TEXT NOT NULL, channel TEXT NOT NULL, thread_ts TEXT NOT NULL, runtime TEXT NOT NULL,
      profile TEXT NOT NULL, model TEXT, runtime_session_id TEXT, workspace TEXT NOT NULL, token TEXT NOT NULL UNIQUE, running INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL, last_active_at INTEGER NOT NULL, scope TEXT NOT NULL DEFAULT 'thread', title TEXT, created_by TEXT, effort TEXT);
    CREATE TABLE chats (thread_ts TEXT PRIMARY KEY, session_key TEXT NOT NULL, title TEXT, created_by TEXT NOT NULL, created_at INTEGER NOT NULL);
    CREATE TABLE chat_messages (thread_ts TEXT NOT NULL, ts TEXT NOT NULL, role TEXT NOT NULL, user TEXT NOT NULL, text TEXT NOT NULL,
      created_at INTEGER NOT NULL, attachments TEXT, quotes TEXT, PRIMARY KEY (thread_ts, ts));
    CREATE TABLE bindings (connect TEXT PRIMARY KEY, session_key TEXT NOT NULL);
    CREATE TABLE inbound (connect TEXT NOT NULL, channel TEXT NOT NULL, ts TEXT NOT NULL, session_key TEXT NOT NULL, user TEXT NOT NULL, text TEXT NOT NULL,
      status TEXT NOT NULL, received_at INTEGER NOT NULL, thread_ts TEXT NOT NULL DEFAULT '', PRIMARY KEY (connect, channel, ts));
    CREATE INDEX inbound_pending ON inbound (session_key, status, ts);
    CREATE TABLE turns (id TEXT PRIMARY KEY, session_key TEXT NOT NULL, kind TEXT NOT NULL, started_at INTEGER NOT NULL, ended_at INTEGER, outcome TEXT, detail TEXT, declared TEXT);
    CREATE TABLE processes (pgid INTEGER PRIMARY KEY, started_at INTEGER NOT NULL, runtime TEXT NOT NULL, label TEXT NOT NULL);

    INSERT INTO sessions (key, connect, channel, thread_ts, runtime, profile, workspace, token, created_at, last_active_at, scope, created_by) VALUES
      ('ds:C1:100.000001', 'ds', 'C1', '100.000001', 'claude', 'cc', '/w/1', 't1', 900, 2000, 'thread', 'slack:ds:U1'),
      ('team:s-1', 'team', 'C2', '200.000001', 'claude', 'cc', '/w/2', 't2', 1400, 2600, 'all', 'slack:team:U1'),
      ('ember:c-1', 'ember', '', '', 'codex', 'cx', '/w/3', 't3', 2900, 3100, 'all', 'local'),
      ('team:s-2', 'team', '', '', 'claude', 'cc', '/w/4', 't4', 3500, 3500, 'all', 'local');
    INSERT INTO bindings VALUES ('team', 'team:s-1');
    INSERT INTO turns (id, session_key, kind, started_at, ended_at, outcome) VALUES ('turn-1', 'ds:C1:100.000001', 'input', 1001, 1500, 'completed');
    INSERT INTO inbound (connect, channel, ts, session_key, user, text, status, received_at, thread_ts) VALUES
      ('ds', 'C1', '100.000001', 'ds:C1:100.000001', 'U1', '<@UBOT> hi', 'delivered', 1000, '100.000001'),
      ('team', 'C2', '200.000001', 'team:s-1', 'U1', 'a', 'delivered', 1500, '200.000001'),
      ('ds', 'C1', '100.000002', 'ds:C1:100.000001', 'U2', 'more', 'pending', 2000, '100.000001'),
      -- the same Slack message, seen by a second connect whose session is in the thread too
      ('team', 'C1', '100.000002', 'team:s-1', 'U2', 'more', 'delivered', 2001, '100.000001'),
      ('team', 'C3', '300.000001', 'team:s-1', 'U3', 'b', 'delivered', 2500, '300.000001'),
      ('ember', 'EMBER', '500.000002', 'ember:c-1', 'local', '[Quote] From … 看看这个 Attached files: …', 'delivered', 3000, '500.000001');
    INSERT INTO chats VALUES ('500.000001', 'ember:c-1', '排查', 'local', 2950);
    INSERT INTO chat_messages VALUES
      ('500.000001', '500.000002', 'person', 'local', '看看这个', 3000, '[{"name":"a.png","path":"/w/3/uploads/a.png","size":3}]', '[{"author":"Claude","text":"x","comment":"y"}]'),
      ('500.000001', '500.000003', 'agent', 'UEMBER', '好的', 3050, NULL, NULL);
    PRAGMA user_version = 9;
  `);
  db.close();
  return path;
}

test("a v9 database moves into threads, messages and deliveries", () => {
  const path = v9();
  assert.equal(Store.needsTeams(path), true);
  const store = new Store(path, { teams: new Map([["ds", "T1"], ["team", "T1"]]) });
  assert.equal(Store.needsTeams(path), false);
  const raw = new DatabaseSync(path, { readOnly: true });
  assert.equal((raw.prepare("PRAGMA user_version").get() as any).user_version, 10);
  assert.deepEqual((raw.prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('inbound', 'chats', 'chat_messages')").all()), []);
  const columns = (raw.prepare("PRAGMA table_info(sessions)").all() as { name: string }[]).map((c) => c.name);
  assert.equal(columns.includes("channel") || columns.includes("thread_ts"), false);
  raw.close();

  const threads = store.listThreads("local");
  assert.deepEqual(threads.map((t) => `${t.surface} ${t.channel}/${t.threadTs}`).sort(), [
    "ember EMBER/500.000001", "slack:T1 C1/100.000001", "slack:T1 C2/200.000001", "slack:T1 C3/300.000001",
  ]);
  const c1 = store.threadAt("slack:T1", "C1", "100.000001")!;
  assert.equal(c1.createdBy, "slack:ds:U1");
  assert.deepEqual(store.threadSessions(c1.id).map((m) => [m.session, m.connect]), [["ds:C1:100.000001", "ds"], ["team:s-1", "team"]]);
  assert.deepEqual(store.messagesBefore(c1.id, undefined, 10).map((m) => [m.ts, m.author, m.text]), [["100.000001", "U1", "<@UBOT> hi"], ["100.000002", "U2", "more"]]);
  // One message, two deliveries, each as it was.
  assert.deepEqual(store.pendingMessages("ds:C1:100.000001").map((m) => [m.ts, m.connect]), [["100.000002", "ds"]]);
  assert.deepEqual(store.pendingMessages("team:s-1"), []);
  assert.deepEqual(store.sessionStats("ds:C1:100.000001").get("ds:C1:100.000001")!.pending, 1);

  const chat = store.threadAt("ember", "EMBER", "500.000001")!;
  assert.deepEqual([chat.title, chat.createdBy], ["排查", "local"]);
  const [typed, answered] = store.messagesBefore(chat.id, undefined, 10);
  assert.deepEqual([typed!.authorKind, typed!.author, typed!.text], ["person", "local", "看看这个"], "the page's own record wins over what the agent was sent");
  assert.equal(typed!.attachments[0]!.name, "a.png");
  assert.equal(typed!.quotes[0]!.comment, "y");
  assert.deepEqual([answered!.authorKind, answered!.author], ["agent", "ember:c-1"]);
  assert.deepEqual(store.pendingMessages("ember:c-1"), []);
  assert.deepEqual(store.heardThreads("ember:c-1"), new Set([chat.id]));

  // seq keeps the order things were said in; rev starts out the same.
  const all = threads.flatMap((t) => store.messagesBefore(t.id, undefined, 10)).sort((a, b) => a.seq - b.seq);
  assert.deepEqual(all.map((m) => m.ts), ["100.000001", "200.000001", "100.000002", "300.000001", "500.000002", "500.000003"]);
  assert.deepEqual(all.map((m) => m.rev), all.map((m) => m.seq));

  assert.equal(store.getSession("team:s-2")!.archivedAt, null);
  assert.deepEqual(store.sessionThreads("team:s-2"), []);
  assert.equal(store.binding("team"), "team:s-1");
  assert.equal(store.listTurns("ds:C1:100.000001").length, 1);
  assert.deepEqual(store.participants().get("team:s-1"), ["slack:team:U1", "slack:team:U2", "slack:team:U3"]);
  store.close();
});

test("without a connect's team its threads are named by the connect", () => {
  const store = new Store(v9());
  assert.deepEqual(store.listThreads("local").map((t) => `${t.surface} ${t.channel}`).sort(), [
    "ember EMBER", "slack:ds C1", "slack:team C1", "slack:team C2", "slack:team C3",
  ]);
  store.close();
});

test("older schemas without a migration path are refused", () => {
  const path = join(mkdtempSync(join(tmpdir(), "ember-v8-")), "ember.db");
  const db = new DatabaseSync(path);
  db.exec("CREATE TABLE sessions (key TEXT); PRAGMA user_version = 8;");
  db.close();
  assert.throws(() => new Store(path), /schema version 8/);
});

function session(store: Store, key: string): void {
  store.insertSession({ key, connect: "ds", scope: "thread", runtime: "claude", profile: "cc", model: null, workspace: `/w/${key}`, token: key, createdAt: 1, lastActiveAt: 1 });
}

test("a message is recorded once and delivered to every session in its thread", () => {
  const store = new Store(":memory:");
  session(store, "a");
  session(store, "b");
  const thread = store.openThread({ surface: "slack:T1", channel: "C1", threadTs: "1.1" });
  assert.equal(store.openThread({ surface: "slack:T1", channel: "C1", threadTs: "1.1" }).id, thread.id);
  store.joinThread(thread.id, "a", "ds");
  assert.equal(store.joinThread(thread.id, "a", "ds"), false);
  store.joinThread(thread.id, "b", "gpt");
  const first = store.insertMessage({ thread: thread.id, ts: "1.1", authorKind: "person", author: "U1", text: "hi" });
  assert.equal(first.fresh, true);
  assert.deepEqual(store.insertMessage({ thread: thread.id, ts: "1.1", authorKind: "person", author: "U1", text: "hi" }), { seq: first.seq, fresh: false });
  assert.deepEqual(store.deliver(first.seq, ["a", "b"]), ["a", "b"]);
  assert.deepEqual(store.deliver(first.seq, ["a", "b"]), []);
  assert.deepEqual(store.pendingMessages("b").map((m) => [m.text, m.connect]), [["hi", "gpt"]]);
  store.markDelivered("a", [first.seq]);
  assert.deepEqual(store.sessionsWithPending(), ["b"]);
  assert.equal(store.latestThread("a")!.id, thread.id);
  assert.equal(store.sessionThread("b", "C1", "1.1")!.connect, "gpt");
  assert.equal(store.sessionThread("b", "C9", "1.1"), undefined);
});

test("a cursor sees new messages, edits and deletes; history pages back by seq", () => {
  const store = new Store(":memory:");
  const thread = store.openThread({ surface: "slack:T1", channel: "C1", threadTs: "1.1" });
  const other = store.openThread({ surface: "slack:T1", channel: "C1", threadTs: "2.1" });
  const seqs = ["1.1", "1.2", "1.3"].map((ts) => store.insertMessage({ thread: thread.id, ts, authorKind: "person", author: "U1", text: ts }).seq);
  store.insertMessage({ thread: other.id, ts: "2.1", authorKind: "person", author: "U1", text: "elsewhere" });
  const cursor = store.threadRev(thread.id);
  assert.deepEqual(store.messagesAfter(thread.id, cursor), []);
  assert.equal(store.editMessage("slack:T1", "C1", "1.1", "1.1 edited"), thread.id);
  assert.equal(store.editMessage("slack:T1", "C1", "1.1", "1.1 edited"), undefined, "the same words are no change");
  assert.equal(store.deleteMessage("slack:T1", "C1", "1.2"), thread.id);
  assert.equal(store.editMessage("slack:T1", "C1", "9.9", "never seen"), undefined);
  store.insertMessage({ thread: thread.id, ts: "1.4", authorKind: "agent", author: "a", text: "new", declared: "final" });
  const changed = store.messagesAfter(thread.id, cursor);
  assert.deepEqual(changed.map((m) => [m.ts, m.text, m.editedAt !== null, m.deletedAt !== null]), [
    ["1.1", "1.1 edited", true, false], ["1.2", "", false, true], ["1.4", "new", false, false],
  ]);
  assert.equal(changed.at(-1)!.declared, "final");
  assert.equal(store.threadRev(thread.id), Math.max(...changed.map((m) => m.rev)));
  assert.deepEqual(store.messagesAfter(thread.id, store.threadRev(thread.id)), []);
  assert.deepEqual(store.messagesBefore(thread.id, seqs[2], 1).map((m) => m.ts), ["1.2"]);
  assert.deepEqual(store.messagesBefore(thread.id, undefined, 2).map((m) => m.ts), ["1.3", "1.4"]);
});

test("reads move forward only; unread counts skip the viewer's own and deleted messages", () => {
  const store = new Store(":memory:");
  session(store, "a");
  const thread = store.openThread({ surface: "ember", channel: "EMBER", threadTs: "1.1" });
  store.joinThread(thread.id, "a", "ember");
  const mine = store.insertMessage({ thread: thread.id, ts: "1.2", authorKind: "person", author: "me@x", text: "q" }).seq;
  store.insertMessage({ thread: thread.id, ts: "1.3", authorKind: "agent", author: "a", text: "answer" });
  store.insertMessage({ thread: thread.id, ts: "1.4", authorKind: "person", author: "you@x", text: "also" });
  store.deleteMessage("ember", "EMBER", "1.4");
  const view = (viewer: string) => store.listThreads(viewer, { session: "a" })[0]!;
  assert.deepEqual([view("me@x").unread, view("me@x").read], [1, 0]);
  assert.equal(view("you@x").unread, 2);
  assert.equal(store.setRead("me@x", thread.id, mine + 1), mine + 1);
  assert.equal(store.setRead("me@x", thread.id, mine), mine + 1, "never back");
  assert.deepEqual([view("me@x").unread, view("me@x").read], [0, mine + 1]);
  assert.equal(view("you@x").unread, 2, "each viewer reads for themselves");
  assert.equal(view("me@x").last!.ts, "1.4");
});

test("archiving hides; deleting removes the session's rows and the threads only it was in", () => {
  const store = new Store(":memory:");
  session(store, "a");
  session(store, "b");
  const shared = store.openThread({ surface: "slack:T1", channel: "C1", threadTs: "1.1" });
  const own = store.openThread({ surface: "ember", channel: "EMBER", threadTs: "2.1" });
  store.joinThread(shared.id, "a", "ds");
  store.joinThread(shared.id, "b", "ds");
  store.joinThread(own.id, "a", "ember");
  const said = store.insertMessage({ thread: shared.id, ts: "1.1", authorKind: "person", author: "U1", text: "hi" }).seq;
  store.deliver(said, ["a", "b"]);
  store.insertMessage({ thread: own.id, ts: "2.2", authorKind: "person", author: "local", text: "mine" });
  store.setRead("local", own.id, 99);
  store.startTurn("t", "a", "input");
  store.setBinding("team", "a");
  store.setArchived("a", true);
  assert.ok(store.getSession("a")!.archivedAt! > 0);
  store.setArchived("a", false);
  assert.equal(store.getSession("a")!.archivedAt, null);
  const events: string[] = [];
  store.changes.on("session-removed", (key) => events.push(`removed ${key}`));
  store.changes.on("thread", (t: { id: number }) => events.push(`thread ${t.id}`));
  store.deleteSession("a");
  assert.deepEqual(events, ["removed a", `thread ${shared.id}`]);
  assert.equal(store.getSession("a"), undefined);
  assert.equal(store.getThread(own.id), undefined);
  assert.deepEqual(store.messagesBefore(own.id, undefined, 10), []);
  assert.deepEqual(store.threadSessions(shared.id).map((m) => m.session), ["b"]);
  assert.equal(store.pendingMessages("b").length, 1, "the other session keeps its delivery");
  assert.equal(store.listTurns("a").length, 0);
  assert.equal(store.binding("team"), undefined);
});

test("the store announces what changed", () => {
  const store = new Store(":memory:");
  const seen: [string, unknown][] = [];
  for (const name of ["session", "thread", "read", "processes"]) store.changes.on(name, (data) => seen.push([name, data]));
  session(store, "a");
  const thread = store.openThread({ surface: "ember", channel: "EMBER", threadTs: "1.1" });
  store.joinThread(thread.id, "a", "ember");
  const { seq } = store.insertMessage({ thread: thread.id, ts: "1.2", authorKind: "person", author: "local", text: "hi" });
  store.deliver(seq, ["a"]);
  store.setRead("local", thread.id, seq);
  store.recordProcess(42, 1, "claude", "x");
  store.forgetProcess(42);
  store.forgetProcess(42);
  const kinds = seen.map(([name]) => name);
  assert.deepEqual(kinds, ["session", "session", "thread", "thread", "session", "read", "processes", "processes"]);
  const said = seen[3]![1] as { id: number; rev: number; messages: { text: string }[] };
  assert.deepEqual([said.id, said.messages.map((m) => m.text), said.rev], [thread.id, ["hi"], 1]);
  assert.deepEqual(seen[5]![1], { viewer: "local", thread: thread.id, seq });
});
