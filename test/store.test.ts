import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { zstdDecompressSync } from "node:zlib";
import { Store, type EntryRow } from "../src/store.ts";

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

test("a v9 database moves into threads, their entries and deliveries", () => {
  const path = v9();
  assert.equal(Store.needsTeams(path), true);
  const store = new Store(path, { teams: new Map([["ds", "T1"], ["team", "T1"]]) });
  assert.equal(Store.needsTeams(path), false);
  const raw = new DatabaseSync(path, { readOnly: true });
  assert.equal((raw.prepare("PRAGMA user_version").get() as any).user_version, 11);
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

  // Each thread's entries keep the order things were said in.
  assert.deepEqual(store.entriesAfter(c1.id, 0).map((e) => [e.n, e.kind, e.ts]), [[1, "message", "100.000001"], [2, "message", "100.000002"]]);

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
  assert.deepEqual(first, { n: 1, fresh: true });
  assert.deepEqual(store.insertMessage({ thread: thread.id, ts: "1.1", authorKind: "person", author: "U1", text: "hi" }), { n: 1, fresh: false });
  assert.deepEqual(store.deliver(thread.id, first.n, ["a", "b"]), ["a", "b"]);
  assert.deepEqual(store.deliver(thread.id, first.n, ["a", "b"]), []);
  assert.deepEqual(store.pendingMessages("b").map((m) => [m.text, m.connect]), [["hi", "gpt"]]);
  store.markDelivered("a", [{ thread: thread.id, n: first.n }]);
  assert.deepEqual(store.sessionsWithPending(), ["b"]);
  assert.equal(store.latestThread("a")!.id, thread.id);
  assert.equal(store.sessionThread("b", "C1", "1.1")!.connect, "gpt");
  assert.equal(store.sessionThread("b", "C9", "1.1"), undefined);
});

const plain = (entries: EntryRow[]) => entries.map((e) => [e.n, e.kind, e.target ?? e.ts, e.text]);

test("a thread is a log: edits and deletes are entries of their own, read after n, before n, or from a to b", () => {
  const store = new Store(":memory:");
  const thread = store.openThread({ surface: "slack:T1", channel: "C1", threadTs: "1.1" });
  const other = store.openThread({ surface: "slack:T1", channel: "C1", threadTs: "2.1" });
  for (const ts of ["1.1", "1.2", "1.3"]) store.insertMessage({ thread: thread.id, ts, authorKind: "person", author: "U1", text: ts });
  store.insertMessage({ thread: other.id, ts: "2.1", authorKind: "person", author: "U1", text: "elsewhere" });
  assert.equal(store.lastEntry(thread.id), 3);
  assert.deepEqual(store.entriesAfter(thread.id, 3), []);
  assert.equal(store.editMessage("slack:T1", "C1", "1.1", "1.1", "1.1 edited"), thread.id);
  assert.equal(store.editMessage("slack:T1", "C1", "1.1", "1.1", "1.1 edited"), undefined, "the same words are no change");
  assert.equal(store.deleteMessage("slack:T1", "C1", "1.1", "1.2"), thread.id);
  assert.equal(store.deleteMessage("slack:T1", "C1", "1.1", "1.2"), undefined, "deleted once");
  assert.equal(store.editMessage("slack:T1", "C1", "1.1", "1.2", "too late"), undefined, "a deleted message takes no edit");
  assert.equal(store.editMessage("slack:T1", "C1", "1.1", "9.9", "never seen"), undefined);
  store.insertMessage({ thread: thread.id, ts: "1.4", authorKind: "agent", author: "a", text: "new", declared: "final" });
  assert.deepEqual(plain(store.entriesAfter(thread.id, 3)), [[4, "edit", 1, "1.1 edited"], [5, "delete", 2, null], [6, "message", "1.4", "new"]]);
  // What was read stays true: the message entries are as they were said.
  assert.deepEqual(plain(store.entriesBetween(thread.id, 1, 2)), [[1, "message", "1.1", "1.1"], [2, "message", "1.2", "1.2"]]);
  assert.deepEqual(plain(store.entriesBetween(thread.id, 5, 9)).map(([n]) => n), [5, 6]);
  assert.deepEqual(store.entriesBefore(thread.id, 4, 2).map((e) => e.n), [2, 3]);
  assert.deepEqual(store.entriesBefore(thread.id, undefined, 2).map((e) => e.n), [5, 6]);
  assert.deepEqual(store.entriesAfter(other.id, 0).map((e) => e.n), [1], "each thread counts from 1");
  // Merged: the latest edit's words, the deleted one gone.
  assert.deepEqual(store.messagesBefore(thread.id, undefined, 10).map((m) => [m.n, m.text, m.editedAt !== null]), [[1, "1.1 edited", true], [3, "1.3", false], [6, "new", false]]);
  assert.deepEqual(store.messagesBefore(thread.id, 3, 1).map((m) => m.ts), ["1.1"]);
  assert.equal(store.lastMessage(thread.id)!.declared, "final");
  assert.equal(store.messageAt(thread.id, "1.2")!.deletedAt !== null, true);
});

test("a message still pending reaches the agent as it reads at delivery", () => {
  const store = new Store(":memory:");
  session(store, "a");
  const thread = store.openThread({ surface: "slack:T1", channel: "C1", threadTs: "1.1" });
  store.joinThread(thread.id, "a", "ds");
  for (const ts of ["1.1", "1.2"]) store.deliver(thread.id, store.insertMessage({ thread: thread.id, ts, authorKind: "person", author: "U1", text: ts }).n, ["a"]);
  store.editMessage("slack:T1", "C1", "1.1", "1.1", "edited");
  store.deleteMessage("slack:T1", "C1", "1.1", "1.2");
  assert.deepEqual(store.pendingMessages("a").map((m) => [m.n, m.text, m.deletedAt !== null]), [[1, "edited", false], [2, "1.2", true]]);
  assert.equal(store.sessionStats("a").get("a")!.firstText, "edited");
});

test("reads move forward only; unread counts skip the viewer's own and deleted messages", () => {
  const store = new Store(":memory:");
  session(store, "a");
  const thread = store.openThread({ surface: "slack:T1", channel: "C1", threadTs: "1.1" });
  store.joinThread(thread.id, "a", "ds");
  const mine = store.insertMessage({ thread: thread.id, ts: "1.2", authorKind: "person", author: "me@x", text: "q" }).n;
  store.insertMessage({ thread: thread.id, ts: "1.3", authorKind: "agent", author: "a", text: "answer" });
  store.insertMessage({ thread: thread.id, ts: "1.4", authorKind: "person", author: "you@x", text: "also" });
  store.deleteMessage("slack:T1", "C1", "1.1", "1.4");
  const view = (viewer: string) => store.listThreads(viewer, { session: "a" })[0]!;
  assert.deepEqual([view("me@x").unread, view("me@x").read, view("me@x").last], [1, 0, 4]);
  assert.equal(store.unreadCount("me@x", thread.id), 1);
  assert.equal(view("you@x").unread, 2);
  assert.equal(store.setRead("me@x", thread.id, mine + 1), mine + 1);
  assert.equal(store.setRead("me@x", thread.id, mine), mine + 1, "never back");
  assert.deepEqual([view("me@x").unread, view("me@x").read], [0, mine + 1]);
  assert.equal(view("you@x").unread, 2, "each viewer reads for themselves");
  assert.equal(view("me@x").lastMessage!.ts, "1.3", "a deleted message is gone from lists");
  // Its people, and the first thing one of them said (a deleted message is no longer said).
  assert.deepEqual([view("me@x").people, view("me@x").firstText], [["slack:ds:me@x", "slack:ds:you@x"], "q"]);
  const slack = store.openThread({ surface: "slack:T1", channel: "C1", threadTs: "2.1" });
  store.joinThread(slack.id, "a", "ds");
  store.insertMessage({ thread: slack.id, ts: "2.1", authorKind: "agent", author: "a", text: "hello" });
  store.insertMessage({ thread: slack.id, ts: "2.2", authorKind: "person", author: "U2", text: "<@UBOT> 看看" });
  store.insertMessage({ thread: slack.id, ts: "2.3", authorKind: "person", author: "U1", text: "嗯" });
  store.insertMessage({ thread: slack.id, ts: "2.4", authorKind: "person", author: "U2", text: "再看" });
  const [slackView] = store.listThreads("me@x", { thread: slack.id });
  assert.deepEqual([slackView!.people, slackView!.firstText], [["slack:ds:U2", "slack:ds:U1"], "<@UBOT> 看看"]);
  assert.deepEqual(store.listThreads("me@x").map((t) => t.id), [slack.id, thread.id], "the latest said first");
});

test("archiving writes a thread out to a zstd file and back; the same reads answer from it", () => {
  const archive = mkdtempSync(join(tmpdir(), "ember-archive-"));
  const store = new Store(":memory:", { archive });
  session(store, "a");
  session(store, "b");
  const shared = store.openThread({ surface: "slack:T1", channel: "C1", threadTs: "1.1" });
  const own = store.openThread({ surface: "ember", channel: "EMBER", threadTs: "2.1" });
  store.joinThread(shared.id, "a", "ds");
  store.joinThread(shared.id, "b", "ds");
  store.joinThread(own.id, "a", "ember");
  store.insertMessage({ thread: own.id, ts: "2.2", authorKind: "person", author: "local", text: "看看", at: 1 });
  store.insertMessage({ thread: own.id, ts: "2.3", authorKind: "agent", author: "a", text: "好", at: 2 });
  store.insertMessage({ thread: shared.id, ts: "1.1", authorKind: "person", author: "U1", text: "hi", at: 3 });
  const before = store.listThreads("local", { thread: own.id })[0]!;
  const entries = store.entriesAfter(own.id, 0);
  const file = join(archive, "threads", `${own.id}.jsonl.zst`);

  store.setArchived("a", true);
  assert.equal(existsSync(file), true, "every session of it is archived");
  assert.equal(existsSync(join(archive, "threads", `${shared.id}.jsonl.zst`)), false, "b still takes part");
  assert.deepEqual(zstdDecompressSync(readFileSync(file)).toString().trim().split("\n").map((l) => JSON.parse(l)), entries);
  // Out of the database, read from the file the same way.
  assert.deepEqual(store.entriesAfter(own.id, 0), entries);
  assert.deepEqual(store.entriesBefore(own.id, undefined, 1), entries.slice(1));
  assert.deepEqual(store.entriesBetween(own.id, 2, 2), entries.slice(1));
  assert.deepEqual(store.listThreads("local", { thread: own.id })[0], before);
  assert.deepEqual(store.participants("a").get("a"), ["local", "slack:ds:U1"]);

  store.setArchived("a", false);
  assert.equal(existsSync(file), false, "shown again: back in the database");
  assert.deepEqual(store.entriesAfter(own.id, 0), entries);

  // Someone writing in an archived thread brings it back first.
  store.setArchived("a", true);
  const heard: unknown[] = [];
  store.changes.on("thread", (t) => heard.push(t));
  assert.deepEqual(store.insertMessage({ thread: own.id, ts: "2.4", authorKind: "person", author: "local", text: "还在吗" }), { n: 3, fresh: true });
  assert.equal(existsSync(file), false);
  assert.deepEqual(store.entriesAfter(own.id, 0).map((e) => e.n), [1, 2, 3]);
  assert.deepEqual((heard as { entries: EntryRow[] }[]).map((t) => t.entries.map((e) => e.n)), [[3]]);

  // Deleting the session removes an archived thread's file with it.
  store.setArchived("a", true);
  store.setArchived("b", true);
  assert.equal(existsSync(join(archive, "threads", `${shared.id}.jsonl.zst`)), true);
  const removed: unknown[] = [];
  store.changes.on("thread-removed", (t) => removed.push(t));
  store.deleteSession("a");
  assert.deepEqual(removed, [{ id: own.id }]);
  assert.equal(existsSync(file), false);
  assert.deepEqual(store.entriesAfter(shared.id, 0).map((e) => e.text), ["hi"], "b's archived thread stays");
});

test("thread ids are never used again", () => {
  const store = new Store(":memory:");
  session(store, "a");
  const thread = store.openThread({ surface: "ember", channel: "EMBER", threadTs: "1.1" });
  store.joinThread(thread.id, "a", "ember");
  store.deleteSession("a");
  assert.ok(store.openThread({ surface: "ember", channel: "EMBER", threadTs: "2.1" }).id > thread.id);
});

test("deleting removes the session's rows and the threads only it was in", () => {
  const store = new Store(":memory:");
  session(store, "a");
  session(store, "b");
  const shared = store.openThread({ surface: "slack:T1", channel: "C1", threadTs: "1.1" });
  const own = store.openThread({ surface: "ember", channel: "EMBER", threadTs: "2.1" });
  store.joinThread(shared.id, "a", "ds");
  store.joinThread(shared.id, "b", "ds");
  store.joinThread(own.id, "a", "ember");
  const said = store.insertMessage({ thread: shared.id, ts: "1.1", authorKind: "person", author: "U1", text: "hi" }).n;
  store.deliver(shared.id, said, ["a", "b"]);
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
  store.changes.on("thread-removed", (t: { id: number }) => events.push(`thread removed ${t.id}`));
  store.changes.on("thread", (t: { id: number }) => events.push(`thread ${t.id}`));
  store.deleteSession("a");
  assert.deepEqual(events, ["removed a", `thread removed ${own.id}`, `thread ${shared.id}`]);
  assert.equal(store.getSession("a"), undefined);
  assert.equal(store.getThread(own.id), undefined);
  assert.deepEqual(store.entriesAfter(own.id, 0), []);
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
  const { n } = store.insertMessage({ thread: thread.id, ts: "1.2", authorKind: "person", author: "local", text: "hi" });
  store.deliver(thread.id, n, ["a"]);
  store.setRead("local", thread.id, n);
  store.recordProcess(42, 1, "claude", "x");
  store.forgetProcess(42);
  store.forgetProcess(42);
  const kinds = seen.map(([name]) => name);
  assert.deepEqual(kinds, ["session", "session", "thread", "thread", "session", "read", "processes", "processes"]);
  assert.deepEqual(seen[2]![1], { id: thread.id, entries: [] });
  const said = seen[3]![1] as { id: number; entries: EntryRow[] };
  assert.deepEqual([said.id, said.entries.map((e) => [e.n, e.text])], [thread.id, [[1, "hi"]]]);
  assert.deepEqual(seen[5]![1], { viewer: "local", thread: thread.id, n });
});

/** A database as ember left it at schema v10: an edited, a deleted and a plain message, deliveries and reads. */
function v10(): string {
  const path = join(mkdtempSync(join(tmpdir(), "ember-v10-")), "ember.db");
  const db = new DatabaseSync(path);
  db.exec(`
    CREATE TABLE sessions (key TEXT PRIMARY KEY, connect TEXT NOT NULL, scope TEXT NOT NULL, title TEXT, created_by TEXT, runtime TEXT NOT NULL,
      profile TEXT NOT NULL, model TEXT, effort TEXT, runtime_session_id TEXT, workspace TEXT NOT NULL, token TEXT NOT NULL UNIQUE,
      running INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, last_active_at INTEGER NOT NULL, archived_at INTEGER);
    CREATE TABLE threads (id INTEGER PRIMARY KEY, surface TEXT NOT NULL, channel TEXT NOT NULL, thread_ts TEXT NOT NULL, title TEXT, created_by TEXT,
      created_at INTEGER NOT NULL, UNIQUE (surface, channel, thread_ts));
    CREATE TABLE thread_sessions (thread INTEGER NOT NULL, session TEXT NOT NULL, connect TEXT NOT NULL, joined_at INTEGER NOT NULL, PRIMARY KEY (thread, session));
    CREATE INDEX thread_sessions_session ON thread_sessions (session);
    CREATE TABLE messages (seq INTEGER PRIMARY KEY AUTOINCREMENT, rev INTEGER NOT NULL UNIQUE, thread INTEGER NOT NULL, ts TEXT NOT NULL,
      author_kind TEXT NOT NULL, author TEXT NOT NULL, text TEXT NOT NULL, attachments TEXT, quotes TEXT, declared TEXT,
      created_at INTEGER NOT NULL, edited_at INTEGER, deleted_at INTEGER, UNIQUE (thread, ts));
    CREATE INDEX messages_thread_rev ON messages (thread, rev);
    CREATE TABLE deliveries (message INTEGER NOT NULL, session TEXT NOT NULL, delivered_at INTEGER, PRIMARY KEY (message, session));
    CREATE INDEX deliveries_pending ON deliveries (session) WHERE delivered_at IS NULL;
    CREATE INDEX deliveries_session ON deliveries (session, message);
    CREATE TABLE reads (viewer TEXT NOT NULL, thread INTEGER NOT NULL, seq INTEGER NOT NULL, at INTEGER NOT NULL, PRIMARY KEY (viewer, thread));
    CREATE TABLE profile_status (profile TEXT PRIMARY KEY, check_json TEXT, checked_at INTEGER, quota_json TEXT, quota_at INTEGER);
    CREATE TABLE bindings (connect TEXT PRIMARY KEY, session_key TEXT NOT NULL);
    CREATE TABLE turns (id TEXT PRIMARY KEY, session_key TEXT NOT NULL, kind TEXT NOT NULL, started_at INTEGER NOT NULL, ended_at INTEGER, outcome TEXT, detail TEXT, declared TEXT);
    CREATE TABLE processes (pgid INTEGER PRIMARY KEY, started_at INTEGER NOT NULL, runtime TEXT NOT NULL, label TEXT NOT NULL);

    INSERT INTO sessions (key, connect, scope, runtime, profile, workspace, token, created_at, last_active_at) VALUES
      ('ds:C1:1.1', 'ds', 'thread', 'claude', 'cc', '/w/1', 't1', 1, 1), ('ember:c-1', 'ember', 'all', 'claude', 'cc', '/w/2', 't2', 1, 1);
    INSERT INTO threads VALUES (1, 'slack:T1', 'C1', '1.1', NULL, 'slack:ds:U1', 10), (2, 'ember', 'EMBER', '2.1', '问', 'me@x', 20);
    INSERT INTO thread_sessions VALUES (1, 'ds:C1:1.1', 'ds', 10), (2, 'ember:c-1', 'ember', 20);
    -- seq across threads; in thread 1 the second message was deleted (words cleared) and the first edited.
    INSERT INTO messages (seq, rev, thread, ts, author_kind, author, text, attachments, created_at, edited_at, deleted_at) VALUES
      (1, 6, 1, '1.1', 'person', 'U1', 'hi, edited', NULL, 100, 500, NULL),
      (2, 2, 2, '2.2', 'person', 'me@x', '看看', '[{"name":"a.png","path":"/w/2/uploads/a.png","size":3}]', 200, NULL, NULL),
      (3, 7, 1, '1.2', 'person', 'U2', '', NULL, 300, NULL, 600),
      (4, 4, 1, '1.3', 'agent', 'ds:C1:1.1', 'answer', NULL, 400, NULL, NULL),
      (5, 5, 2, '2.3', 'agent', 'ember:c-1', '好', NULL, 450, NULL, NULL);
    INSERT INTO deliveries VALUES (1, 'ds:C1:1.1', 150), (3, 'ds:C1:1.1', NULL), (2, 'ember:c-1', 250);
    INSERT INTO reads VALUES ('me@x', 1, 3, 700), ('me@x', 2, 2, 700), ('local', 1, 1, 700);
    PRAGMA user_version = 10;
  `);
  db.close();
  return path;
}

test("a v10 database moves its messages into entry logs", () => {
  const path = v10();
  const store = new Store(path);
  const raw = new DatabaseSync(path, { readOnly: true });
  assert.equal((raw.prepare("PRAGMA user_version").get() as any).user_version, 11);
  assert.deepEqual(raw.prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'messages%'").all(), []);
  raw.close();
  // In thread order; the edited message has its edited words, the deleted one is followed by its delete.
  assert.deepEqual(plain(store.entriesAfter(1, 0)), [[1, "message", "1.1", "hi, edited"], [2, "message", "1.2", ""], [3, "delete", 2, null], [4, "message", "1.3", "answer"]]);
  assert.deepEqual(store.entriesAfter(1, 0).map((e) => [e.authorKind, e.author, e.at]), [["person", "U1", 100], ["person", "U2", 300], ["person", "U2", 600], ["agent", "ds:C1:1.1", 400]]);
  assert.deepEqual(plain(store.entriesAfter(2, 0)), [[1, "message", "2.2", "看看"], [2, "message", "2.3", "好"]]);
  assert.equal(store.entriesAfter(2, 0)[0]!.attachments[0]!.name, "a.png");
  // Deliveries and reads point at (thread, n).
  assert.deepEqual(store.pendingMessages("ds:C1:1.1").map((m) => [m.thread, m.n, m.deletedAt]), [[1, 2, 600]]);
  assert.deepEqual(store.heardThreads("ember:c-1"), new Set([2]));
  const summary = (viewer: string, id: number) => store.listThreads(viewer, { thread: id })[0]!;
  assert.deepEqual([summary("me@x", 1).read, summary("me@x", 2).read, summary("local", 1).read], [3, 1, 1]);
  assert.deepEqual([summary("me@x", 1).unread, summary("local", 1).unread], [1, 1]);
  assert.deepEqual([summary("me@x", 1).last, summary("me@x", 1).lastMessage!.text], [4, "answer"]);
  // New entries follow on; new threads never take an old id.
  assert.deepEqual(store.insertMessage({ thread: 1, ts: "1.4", authorKind: "person", author: "U1", text: "more" }), { n: 5, fresh: true });
  assert.equal(store.openThread({ surface: "ember", channel: "EMBER", threadTs: "3.1" }).id, 3);
  store.close();
});
