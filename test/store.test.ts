import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync } from "node:fs";
import { DatabaseSync } from "node:sqlite";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { zstdDecompressSync } from "node:zlib";
import { Store, type EntryRow } from "../src/store.ts";

test("a database of another schema version is refused: its data is moved by hand", () => {
  const path = join(mkdtempSync(join(tmpdir(), "ember-v8-")), "ember.db");
  const db = new DatabaseSync(path);
  db.exec("CREATE TABLE sessions (key TEXT); PRAGMA user_version = 8;");
  db.close();
  assert.throws(() => new Store(path), /schema version 8; this ember uses 11/);
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

test("a thread is a log: edits are entries of their own, read after n, before n, or from a to b", () => {
  const store = new Store(":memory:");
  const thread = store.openThread({ surface: "slack:T1", channel: "C1", threadTs: "1.1" });
  const other = store.openThread({ surface: "slack:T1", channel: "C1", threadTs: "2.1" });
  for (const ts of ["1.1", "1.2", "1.3"]) store.insertMessage({ thread: thread.id, ts, authorKind: "person", author: "U1", text: ts });
  store.insertMessage({ thread: other.id, ts: "2.1", authorKind: "person", author: "U1", text: "elsewhere" });
  assert.equal(store.lastEntry(thread.id), 3);
  assert.deepEqual(store.entriesAfter(thread.id, 3), []);
  assert.equal(store.editMessage("slack:T1", "C1", "1.1", "1.1", "1.1 edited"), thread.id);
  assert.equal(store.editMessage("slack:T1", "C1", "1.1", "1.1", "1.1 edited"), undefined, "the same words are no change");
  assert.equal(store.editMessage("slack:T1", "C1", "1.1", "1.2", "1.2 edited"), thread.id);
  assert.equal(store.editMessage("slack:T1", "C1", "1.1", "9.9", "never seen"), undefined);
  store.insertMessage({ thread: thread.id, ts: "1.4", authorKind: "agent", author: "a", text: "new", declared: "final" });
  assert.deepEqual(plain(store.entriesAfter(thread.id, 3)), [[4, "edit", 1, "1.1 edited"], [5, "edit", 2, "1.2 edited"], [6, "message", "1.4", "new"]]);
  // What was read stays true: the message entries are as they were said.
  assert.deepEqual(plain(store.entriesBetween(thread.id, 1, 2)), [[1, "message", "1.1", "1.1"], [2, "message", "1.2", "1.2"]]);
  assert.deepEqual(plain(store.entriesBetween(thread.id, 5, 9)).map(([n]) => n), [5, 6]);
  assert.deepEqual(store.entriesBefore(thread.id, 4, 2).map((e) => e.n), [2, 3]);
  assert.deepEqual(store.entriesBefore(thread.id, undefined, 2).map((e) => e.n), [5, 6]);
  assert.deepEqual(store.entriesAfter(other.id, 0).map((e) => e.n), [1], "each thread counts from 1");
  // Merged: the latest edit's words.
  assert.deepEqual(store.messagesBefore(thread.id, undefined, 10).map((m) => [m.n, m.text, m.editedAt !== null]), [[1, "1.1 edited", true], [2, "1.2 edited", true], [3, "1.3", false], [6, "new", false]]);
  assert.deepEqual(store.messagesBefore(thread.id, 3, 1).map((m) => m.ts), ["1.2"]);
  assert.equal(store.lastMessage(thread.id)!.declared, "final");
});

test("a message still pending reaches the agent as it reads at delivery", () => {
  const store = new Store(":memory:");
  session(store, "a");
  const thread = store.openThread({ surface: "slack:T1", channel: "C1", threadTs: "1.1" });
  store.joinThread(thread.id, "a", "ds");
  for (const ts of ["1.1", "1.2"]) store.deliver(thread.id, store.insertMessage({ thread: thread.id, ts, authorKind: "person", author: "U1", text: ts }).n, ["a"]);
  store.editMessage("slack:T1", "C1", "1.1", "1.1", "edited");
  assert.deepEqual(store.pendingMessages("a").map((m) => [m.n, m.text]), [[1, "edited"], [2, "1.2"]]);
  assert.equal(store.sessionStats("a").get("a")!.firstText, "edited");
});

test("reads move forward only; unread counts skip the viewer's own messages", () => {
  const store = new Store(":memory:");
  session(store, "a");
  const thread = store.openThread({ surface: "slack:T1", channel: "C1", threadTs: "1.1" });
  store.joinThread(thread.id, "a", "ds");
  const mine = store.insertMessage({ thread: thread.id, ts: "1.2", authorKind: "person", author: "me@x", text: "q" }).n;
  store.insertMessage({ thread: thread.id, ts: "1.3", authorKind: "agent", author: "a", text: "answer" });
  store.insertMessage({ thread: thread.id, ts: "1.4", authorKind: "person", author: "you@x", text: "also" });
  store.editMessage("slack:T1", "C1", "1.1", "1.3", "answer, edited");
  const view = (viewer: string) => store.listThreads(viewer, { session: "a" })[0]!;
  assert.deepEqual([view("me@x").unread, view("me@x").read, view("me@x").last], [2, 0, 4]);
  assert.equal(store.unreadCount("me@x", thread.id), 2, "an edit is no message of its own");
  assert.equal(view("you@x").unread, 2);
  assert.equal(store.setRead("me@x", thread.id, mine + 1), mine + 1);
  assert.equal(store.setRead("me@x", thread.id, mine), mine + 1, "never back");
  assert.deepEqual([view("me@x").unread, view("me@x").read], [1, mine + 1]);
  assert.equal(view("you@x").unread, 2, "each viewer reads for themselves");
  assert.deepEqual([view("me@x").lastMessage!.ts, view("you@x").lastMessage!.text], ["1.4", "also"]);
  // Its people, and the first thing one of them said.
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
