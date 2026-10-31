// the Rust station's store/tests.rs ported (same names, same checks), and what else the write side promises: cards closed
// and withdrawn, turns, jobs, bindings and usage.
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { after, test } from "node:test";
import { zstdDecompressSync } from "node:zlib";
import {
  ANY_RUNNING, AUTO, type AuthorKind, CARD_BEFORE, CLOSED_SINCE, type EntryRow, JOBS_RUNNING, JOBS_UP, type JobRow, LATEST_DECISIONS, LIVE_SESSIONS, LOGIN_CARDS,
  MANUAL, type NewMessage, OPTIONS_BEFORE, RUNNING_SESSIONS, SAID_SINCE, SCHEMA_VERSION, SESSION_COUNTS, SESSION_JOBS, SESSION_OF_RUNTIME, STATS_OF, Store, type StoreChange, newMessage,
} from "../src/store/store.ts";
import { MERGED, SCHEMA } from "../src/store/schema.ts";
import { ACTIVE_SESSIONS, TAKEN_SINCE, TURNS_BETWEEN, TURNS_FROM, USAGE_GROUPS } from "../src/store/usage.ts";
import * as read from "../src/read/store.ts";
import { fileAway } from "./archived-before.ts";
import { testClock } from "./hub-fakes.ts";

const dirs: string[] = [];
const stores: Store[] = [];
after(() => {
  for (const s of stores) {
    try {
      s.close();
    } catch {}
  }
  for (const d of dirs) rmSync(d, { recursive: true, force: true });
});

function tempdir(): string {
  const d = mkdtempSync(join(tmpdir(), "store-test-"));
  dirs.push(d);
  return d;
}

function open(path: string, archive: string | null = null): Store {
  const s = Store.open(path, archive);
  stores.push(s);
  return s;
}

const memory = () => open(":memory:");

function session(store: Store, key: string) {
  store.insertSession({ key, connect: "ds", runtime: "claude", profile: "cc", workspace: `/w/${key}`, token: key, createdAt: 1, lastActiveAt: 1 });
}

const say = (store: Store, thread: number, ts: string, kind: AuthorKind, author: string, text: string) =>
  store.insertMessage(newMessage(thread, ts, kind, author, text));

function heard(store: Store): { changes: StoreChange[]; stop: () => void } {
  const changes: StoreChange[] = [];
  return { changes, stop: store.subscribe((c) => changes.push(c)) };
}

const archiveFile = (store: Store, thread: number) => join(store.archiveDir(), "threads", `${thread}.jsonl.zst`);

test("a database of another schema version is refused", () => {
  const path = join(tempdir(), "ember.db");
  const db = new DatabaseSync(path);
  db.exec("CREATE TABLE sessions (key TEXT); PRAGMA user_version = 8;");
  db.close();
  assert.throws(() => Store.open(path), /schema version 8; this station uses 12/);
});

test("a new database is made at version 12", () => {
  const path = join(tempdir(), "new.db");
  open(path).close();
  const db = new DatabaseSync(path, { readOnly: true });
  assert.equal((db.prepare("PRAGMA user_version").get() as any).user_version, SCHEMA_VERSION);
  assert.equal((db.prepare("PRAGMA journal_mode").get() as any).journal_mode, "wal");
  db.close();
});

test("a database from before the index on turns gets it as it is opened", () => {
  const path = join(tempdir(), "turns.db");
  open(path).close();
  const before = new DatabaseSync(path);
  before.exec("DROP INDEX turns_by_session");
  before.close();
  open(path).close();
  const db = new DatabaseSync(path, { readOnly: true });
  assert.ok(db.prepare("SELECT 1 FROM sqlite_master WHERE type = 'index' AND name = 'turns_by_session'").get() !== undefined);
  // Each session's turns are found by it (sessionStats), not by reading every turn.
  const plan = db.prepare("EXPLAIN QUERY PLAN SELECT COUNT(*) FROM turns WHERE session_key = ?").all("k") as { detail: string }[];
  assert.ok(plan.some((p) => p.detail.includes("turns_by_session")), JSON.stringify(plan));
  db.close();
});

test("a message is recorded once and delivered to every session in its thread", () => {
  const store = memory();
  session(store, "a");
  session(store, "b");
  const thread = store.openThread("slack:T1", "C1", "1.1", null, null);
  assert.equal(store.openThread("slack:T1", "C1", "1.1", null, null).id, thread.id);
  store.joinThread(thread.id, "a", "ds");
  assert.equal(store.joinThread(thread.id, "a", "ds"), false);
  store.joinThread(thread.id, "b", "gpt");
  const first = say(store, thread.id, "1.1", "person", "U1", "hi");
  assert.deepEqual(first, [1, true]);
  assert.deepEqual(say(store, thread.id, "1.1", "person", "U1", "hi"), [1, false]);
  assert.deepEqual(store.deliver(thread.id, first[0], ["a", "b"]), ["a", "b"]);
  assert.deepEqual(store.deliver(thread.id, first[0], ["a", "b"]), []);
  assert.deepEqual(store.pendingMessages("b").map((m) => [m.message.text, m.connect]), [["hi", "gpt"]]);
  store.markDelivered("a", [{ thread: thread.id, n: first[0], apart: false }]);
  assert.deepEqual(store.sessionsWithPending(), ["b"]);
  assert.equal(store.latestThread("a")!.thread.id, thread.id);
  assert.equal(store.sessionThread("b", "C1", "1.1")!.connect, "gpt");
  assert.equal(store.sessionThread("b", "C9", "1.1"), null);
});

const plain = (entries: EntryRow[]) => entries.map((e) => [e.n, e.kind, e.target !== null ? String(e.target) : (e.ts ?? ""), e.text ?? ""]);

test("a thread is a log, edits are entries of their own", () => {
  const store = memory();
  const thread = store.openThread("slack:T1", "C1", "1.1", null, null);
  const other = store.openThread("slack:T1", "C1", "2.1", null, null);
  for (const ts of ["1.1", "1.2", "1.3"]) say(store, thread.id, ts, "person", "U1", ts);
  say(store, other.id, "2.1", "person", "U1", "elsewhere");
  assert.equal(store.lastEntry(thread.id), 3);
  assert.deepEqual(store.entriesAfter(thread.id, 3), []);
  assert.equal(store.editMessage("slack:T1", "C1", "1.1", "1.1", "1.1 edited"), thread.id);
  assert.equal(store.editMessage("slack:T1", "C1", "1.1", "1.1", "1.1 edited"), null, "the same words are no change");
  assert.equal(store.editMessage("slack:T1", "C1", "1.1", "1.2", "1.2 edited"), thread.id);
  assert.equal(store.editMessage("slack:T1", "C1", "1.1", "9.9", "never seen"), null);
  store.insertMessage({ ...newMessage(thread.id, "1.4", "agent", "a", "new"), declared: "final" });
  assert.deepEqual(plain(store.entriesAfter(thread.id, 3)), [[4, "edit", "1", "1.1 edited"], [5, "edit", "2", "1.2 edited"], [6, "message", "1.4", "new"]]);
  // What was read stays true: the message entries are as they were said.
  assert.deepEqual(plain(store.entriesBetween(thread.id, 1, 2)), [[1, "message", "1.1", "1.1"], [2, "message", "1.2", "1.2"]]);
  assert.deepEqual(store.entriesBetween(thread.id, 5, 9).map((e) => e.n), [5, 6]);
  assert.deepEqual(store.entriesBefore(thread.id, 4, 2).map((e) => e.n), [2, 3]);
  assert.deepEqual(store.entriesBefore(thread.id, null, 2).map((e) => e.n), [5, 6]);
  assert.deepEqual(store.entriesAfter(other.id, 0).map((e) => e.n), [1], "each thread counts from 1");
  // Merged: the latest edit's words.
  const merged = store.messagesBefore(thread.id, null, 10).map((m) => [m.n, m.text, m.editedAt !== null]);
  assert.deepEqual(merged, [[1, "1.1 edited", true], [2, "1.2 edited", true], [3, "1.3", false], [6, "new", false]]);
  assert.deepEqual(store.messagesBefore(thread.id, 3, 1).map((m) => m.ts), ["1.2"]);
  assert.equal(store.lastMessage(thread.id)!.declared, "final");
  store.editMessage("slack:T1", "C1", "1.1", "1.1", "1.1 again");
  assert.equal(store.messagesBefore(thread.id, 2, 1)[0]!.text, "1.1 again", "the latest edit");
  // Each message's latest edit is found at once by the index of edits, as the station's SQLite (node's) plans it, not by
  // going back over the whole thread.
  const plan = (store.db.prepare("EXPLAIN QUERY PLAN SELECT * FROM merged WHERE thread = ? AND n = ?").all(thread.id, 1) as { detail: string }[]).map((r) => r.detail);
  assert.ok(plan.some((d) => d.includes("entries_edits (thread=? AND target=?)")), plan.join(" | "));
});

test("a message still pending reaches the agent as it reads at delivery", () => {
  const store = memory();
  session(store, "a");
  const thread = store.openThread("slack:T1", "C1", "1.1", null, null);
  store.joinThread(thread.id, "a", "ds");
  for (const ts of ["1.1", "1.2"]) {
    const [n] = say(store, thread.id, ts, "person", "U1", ts);
    store.deliver(thread.id, n, ["a"]);
  }
  store.editMessage("slack:T1", "C1", "1.1", "1.1", "edited");
  assert.deepEqual(store.pendingMessages("a").map((m) => [m.message.n, m.message.text]), [[1, "edited"], [2, "1.2"]]);
  assert.equal(store.sessionStats("a").get("a")!.firstText, "edited");
});

test("reads move forward only and unread counts skip the viewer's own", () => {
  const store = memory();
  session(store, "a");
  const thread = store.openThread("slack:T1", "C1", "1.1", null, null);
  store.joinThread(thread.id, "a", "ds");
  const [mine] = say(store, thread.id, "1.2", "person", "me@x", "q");
  say(store, thread.id, "1.3", "agent", "a", "answer");
  say(store, thread.id, "1.4", "person", "you@x", "also");
  store.editMessage("slack:T1", "C1", "1.1", "1.3", "answer, edited");
  const view = (viewer: string) => store.listThreads(viewer, "a", null)[0]!;
  const me = view("me@x");
  assert.deepEqual([me.unread, me.read, me.last], [2, 0, 4]);
  assert.equal(store.unreadCount("me@x", thread.id), 2, "an edit is no message of its own");
  assert.equal(view("you@x").unread, 2);
  assert.equal(store.setRead("me@x", thread.id, mine + 1), mine + 1);
  assert.equal(store.setRead("me@x", thread.id, mine), mine + 1, "never back");
  const me2 = view("me@x");
  assert.deepEqual([me2.unread, me2.read], [1, mine + 1]);
  assert.equal(view("you@x").unread, 2, "each viewer reads for themselves");
  assert.deepEqual([view("me@x").lastMessage!.ts, view("you@x").lastMessage!.text], ["1.4", "also"]);
  // Its people, and the first thing one of them said.
  assert.deepEqual([view("me@x").people, view("me@x").firstText], [["slack:ds:me@x", "slack:ds:you@x"], "q"]);
  const slack = store.openThread("slack:T1", "C1", "2.1", null, null);
  store.joinThread(slack.id, "a", "ds");
  say(store, slack.id, "2.1", "agent", "a", "hello");
  say(store, slack.id, "2.2", "person", "U2", "<@UBOT> 看看");
  say(store, slack.id, "2.3", "person", "U1", "嗯");
  say(store, slack.id, "2.4", "person", "U2", "再看");
  const slackView = store.listThreads("me@x", null, slack.id)[0]!;
  assert.deepEqual([slackView.people, slackView.firstText], [["slack:ds:U2", "slack:ds:U1"], "<@UBOT> 看看"]);
  assert.deepEqual(store.listThreads("me@x", null, null).map((t) => t.thread.id), [slack.id, thread.id], "the latest said first");
});

test("an archived thread keeps its entries in the database; one a station before wrote out to its file is read from it, and brought back", () => {
  const archive = tempdir();
  const store = open(":memory:", archive);
  session(store, "a");
  session(store, "b");
  const shared = store.openThread("slack:T1", "C1", "1.1", null, null);
  const own = store.openThread("ember", "EMBER", "2.1", null, null);
  store.joinThread(shared.id, "a", "ds");
  store.joinThread(shared.id, "b", "ds");
  store.joinThread(own.id, "a", "ember");
  const at = (m: NewMessage, at: number): NewMessage => ({ ...m, at });
  store.insertMessage(at(newMessage(own.id, "2.2", "person", "local", "看看"), 1));
  store.insertMessage(at(newMessage(own.id, "2.3", "agent", "a", "好"), 2));
  store.insertMessage(at(newMessage(shared.id, "1.1", "person", "U1", "hi"), 3));
  const before = store.listThreads("local", null, own.id)[0];
  const entries = store.entriesAfter(own.id, 0);
  const file = join(archive, "threads", `${own.id}.jsonl.zst`);

  store.setArchived("a", true, MANUAL);
  assert.ok(!existsSync(file), "archived, its entries stay where they are");
  assert.deepEqual(store.entriesAfter(own.id, 0), entries);
  assert.deepEqual(store.listThreads("local", null, own.id)[0], before);

  // As a station before archived it: written out to its file, out of the database.
  assert.equal(fileAway(store, own.id), file);
  const text = zstdDecompressSync(readFileSync(file)).toString("utf8");
  // The shape the Rust station writes (serde's EntryRow): its archives read here, and back.
  assert.ok(text.split("\n")[0]!.startsWith(`{"thread":${own.id},"n":1,"kind":"message","target":null,"ts":"2.2","authorKind":"person"`), text);
  assert.ok(text.split("\n")[1]!.startsWith(`{"agentIdentity":{"model":null,"effort":null},"thread":${own.id},"n":2,`), text);
  // Out of the database, read from the file the same way.
  assert.equal((store.db.prepare("SELECT COUNT(*) AS c FROM entries WHERE thread = ?").get(own.id) as any).c, 0);
  assert.deepEqual(store.entriesAfter(own.id, 0), entries);
  assert.deepEqual(store.entriesBefore(own.id, null, 1), entries.slice(1));
  assert.deepEqual(store.entriesBetween(own.id, 2, 2), entries.slice(1));
  assert.deepEqual(store.listThreads("local", null, own.id)[0], before);
  assert.deepEqual(store.participants("a").get("a"), ["local", "slack:ds:U1"]);

  store.setArchived("a", false, MANUAL);
  assert.ok(!existsSync(file), "shown again: back in the database");
  assert.deepEqual(store.entriesAfter(own.id, 0), entries);

  // Someone writing in one written out brings it back first.
  store.setArchived("a", true, MANUAL);
  fileAway(store, own.id);
  const h = heard(store);
  assert.deepEqual(say(store, own.id, "2.4", "person", "local", "还在吗"), [3, true]);
  assert.ok(!existsSync(file));
  assert.deepEqual(store.entriesAfter(own.id, 0).map((e) => e.n), [1, 2, 3]);
  const appended = h.changes.flatMap((c) => (c.type === "thread" && c.entries.length > 0 ? [c.entries.map((e) => e.n)] : []));
  assert.deepEqual(appended, [[3]]);
  h.stop();

  // Those written out are brought back a few at a time, the oldest first, as they read from their files.
  store.setArchived("a", true, MANUAL);
  store.setArchived("b", true, MANUAL);
  const sharedEntries = store.entriesAfter(shared.id, 0);
  fileAway(store, shared.id);
  fileAway(store, own.id);
  assert.deepEqual(store.bringInArchived(1), { brought: 1, left: 1 });
  assert.ok(!existsSync(join(archive, "threads", `${shared.id}.jsonl.zst`)) && existsSync(file));
  assert.deepEqual(store.bringInArchived(5), { brought: 1, left: 0 });
  assert.deepEqual(store.bringInArchived(5), { brought: 0, left: 0 });
  assert.ok(!existsSync(file));
  assert.deepEqual([store.entriesAfter(shared.id, 0), store.entriesAfter(own.id, 0).length], [sharedEntries, 3]);

  // Deleting the session removes an archived thread's file with it.
  fileAway(store, own.id);
  const removed = heard(store);
  store.deleteSession("a");
  assert.deepEqual(removed.changes.flatMap((c) => (c.type === "threadRemoved" ? [c.id] : [])), [own.id]);
  assert.ok(!existsSync(file));
  assert.deepEqual(store.entriesAfter(shared.id, 0).map((e) => e.text), ["hi"], "b's archived thread stays");
});

test("what lists say of a thread and a session is kept as its messages are written, and goes with them", () => {
  const store = memory();
  session(store, "a");
  const thread = store.openThread("ember", "EMBER", "1.1", null, null);
  store.joinThread(thread.id, "a", "ember");
  const state = () => store.db.prepare("SELECT last_n, said_n, person_n, letters FROM thread_state WHERE thread = ?").get(thread.id);
  const people = () => store.db.prepare("SELECT author, first_n FROM thread_people WHERE thread = ? ORDER BY first_n").all(thread.id).map((r: any) => [r.author, r.first_n]);
  assert.equal(state(), undefined);
  const [first] = say(store, thread.id, "1.2", "person", "x@a", "先看看日志");
  store.deliver(thread.id, first, ["a"]);
  say(store, thread.id, "1.3", "agent", "a", "在看");
  store.insertMessage({ ...newMessage(thread.id, "1.4", "agent", "b", "来自 [备份](https://x/o/w/s/b)：\n\n好了"), letter: { way: "in", title: "备份", link: "https://x/o/w/s/b" } });
  const [second] = say(store, thread.id, "1.5", "person", "y@a", "我也看");
  store.deliver(thread.id, second, ["a"]);
  say(store, thread.id, "1.6", "person", "x@a", "好");
  assert.deepEqual({ ...(state() as object) }, { last_n: 5, said_n: 5, person_n: 1, letters: 1 });
  assert.deepEqual(people(), [["x@a", 1], ["y@a", 4]]);
  // An edit is an entry of its own: the last, nothing else; what is said of the message as merged is its new words.
  store.editMessage("ember", "EMBER", "1.1", "1.2", "先看看今天的日志");
  assert.deepEqual({ ...(state() as object) }, { last_n: 6, said_n: 5, person_n: 1, letters: 1 });
  const [listed] = store.listThreads("x@a", null, thread.id);
  assert.deepEqual([listed!.firstText, listed!.lastMessage?.text, listed!.letters, listed!.people], ["先看看今天的日志", "好", 1, ["x@a", "y@a"]]);
  assert.equal(store.sessionStats("a").get("a")!.firstText, "先看看今天的日志");
  // The first message given goes: the next given is the first.
  store.db.prepare("DELETE FROM deliveries WHERE thread = ? AND n = ?").run(thread.id, first);
  assert.equal(store.sessionStats("a").get("a")!.firstText, "我也看");
  // The thread goes: what was kept of it with it.
  store.db.prepare("DELETE FROM entries WHERE thread = ?").run(thread.id);
  assert.equal(state(), undefined);
  assert.deepEqual(people(), []);
});

test("what two chats' agents wrote each other is neither a chat's unread nor what lists show of it, archived or not", () => {
  const data = tempdir();
  const store = open(join(data, "stillfail.db"), join(data, "archive"));
  session(store, "a");
  const thread = store.openThread("ember", "EMBER", "1.1", null, null);
  store.joinThread(thread.id, "a", "ember");
  // Opened by another chat's agent: what it is about is the chat's first message, said as any other.
  say(store, thread.id, "1.2", "agent", "b", "由 [备份](https://x/o/w/s/b) 开的 chat：\n\n看看备份");
  say(store, thread.id, "1.3", "agent", "a", "好，在看");
  // Letters: from a session here and from one of another station, and one this chat's agent wrote another chat.
  const letter = (ts: string, author: string, text: string, way: "in" | "out") =>
    store.insertMessage({ ...newMessage(thread.id, ts, "agent", author, text), letter: { way, title: "备份", link: "https://x/o/w/s/b" } });
  letter("1.4", "b", "来自 [备份](https://x/o/w/s/b)：\n\n脚本放好了", "in");
  letter("1.5", "peer/ember:c-9", "From [Backups](https://x/o/w/t/c):\n\nDone", "in");
  letter("1.6", "a", "发给 [备份](https://x/o/w/s/b)：\n\n收到", "out");
  const reader = read.openStore(data);
  const lists = () => [store.listThreads("local", null, null), read.listThreads(reader, "local", null, null)];
  for (const threads of lists()) assert.deepEqual(threads.map((t) => [t.lastMessage?.ts, t.unread, t.letters]), [["1.3", 2, 3]]);
  assert.equal(store.unreadCount("local", thread.id), 2);
  // This chat's own agent quoting one in the chat says it in the chat.
  say(store, thread.id, "1.7", "agent", "a", "来自 [备份](https://x/o/w/s/b)：\n\n照它说的改了");
  for (const threads of lists()) assert.deepEqual(threads.map((t) => [t.lastMessage?.ts, t.unread, t.letters]), [["1.7", 3, 3]]);
  // Archived: the same; written out to its file by a station before, read from it: the same.
  store.setArchived("a", true, MANUAL);
  for (const threads of lists()) assert.deepEqual(threads.map((t) => [t.lastMessage?.ts, t.unread, t.letters]), [["1.7", 3, 3]]);
  fileAway(store, thread.id);
  for (const threads of lists()) assert.deepEqual(threads.map((t) => [t.lastMessage?.ts, t.unread, t.letters]), [["1.7", 3, 3]]);
  reader.db.close();
});

test("letters from before they were marked are marked as the column comes, by the chat their heading names", () => {
  const data = tempdir();
  const path = join(data, "stillfail.db");
  const store = open(path);
  session(store, "a");
  const thread = store.openThread("ember", "EMBER", "1.1", null, null);
  store.joinThread(thread.id, "a", "ember");
  say(store, thread.id, "1.2", "agent", "b", "来自 [备份](https://x/o/w/s/b)：\n\n脚本放好了");
  say(store, thread.id, "1.3", "agent", "peer/ember:c-9", "From <https://x/o/w/t/c|Backups>:\n\nDone");
  say(store, thread.id, "1.4", "agent", "a", "来自 [备份](https://x/o/w/s/b)：\n\n照它说的改了");
  say(store, thread.id, "1.5", "agent", "b", "由 [备份](https://x/o/w/s/b) 开的 chat：\n\n看看备份");
  store.close();
  // As a station from before letters left it (from before the lists' kept state too, whose trigger reads the column).
  const db = new DatabaseSync(path);
  db.exec("DROP TRIGGER thread_state_add; DROP TRIGGER thread_state_drop; DROP TRIGGER session_first_add; DROP TRIGGER session_first_drop");
  db.exec("DROP TABLE thread_state; DROP TABLE thread_people; DROP TABLE session_first");
  db.exec("DROP VIEW merged; DROP INDEX entries_letters; ALTER TABLE entries DROP COLUMN letter");
  db.close();
  const again = open(path);
  assert.deepEqual(
    again.entriesAfter(thread.id, 0).map((e) => [e.ts, e.letter ?? null]),
    [
      ["1.2", { way: "in", title: "备份", link: "https://x/o/w/s/b" }],
      ["1.3", { way: "in", title: "Backups", link: "https://x/o/w/t/c" }],
      ["1.4", null],
      ["1.5", null],
    ],
  );
  assert.equal(again.listThreads("local", null, null)[0]?.letters, 2);
});

test("an archived thread whose file is lost reads as empty, and is counted on from what was read of it", () => {
  const data = tempdir();
  const store = open(join(data, "stillfail.db"), join(data, "archive"));
  session(store, "a");
  session(store, "b");
  const lost = store.openThread("ember", "EMBER", "1.1", null, null);
  const kept = store.openThread("ember", "EMBER", "2.1", null, null);
  store.joinThread(lost.id, "a", "ember");
  store.joinThread(kept.id, "b", "ember");
  say(store, lost.id, "1.2", "person", "local", "看看");
  say(store, lost.id, "1.3", "agent", "a", "好");
  say(store, lost.id, "1.4", "agent", "a", "做完了");
  say(store, kept.id, "2.2", "person", "local", "还有这个");
  store.setRead("local", lost.id, 3);
  store.setArchived("a", true, MANUAL);
  fileAway(store, lost.id);
  assert.deepEqual(store.lostArchives(), []);
  rmSync(archiveFile(store, lost.id));
  assert.deepEqual(store.lostArchives(), [lost.id]);

  // Every list it is in is still read, by the station and by its readers (another connection over the same file).
  const reader = read.openStore(data);
  for (const threads of [store.listThreads("local", null, null), read.listThreads(reader, "local", null, null)]) {
    assert.deepEqual(threads.map((t) => [t.thread.id, t.lastMessage?.text ?? null, t.unread]), [[kept.id, "还有这个", 0], [lost.id, null, 0]]);
  }
  assert.deepEqual(store.entriesAfter(lost.id, 0), []);
  assert.deepEqual(read.entriesAfter(reader, lost.id, 0n), []);
  assert.equal(store.lastEntry(lost.id), 0);
  reader.db.close();

  // Said in again, it comes back with that alone, numbered after what was read of it: what a client keeps of the
  // thread (1 to 3) is not numbered again.
  assert.deepEqual(say(store, lost.id, "1.5", "person", "local", "还在吗"), [4, true]);
  assert.deepEqual(store.entriesAfter(lost.id, 0).map((e) => [e.n, e.text]), [[4, "还在吗"]]);
  assert.deepEqual(store.lostArchives(), []);
  // A thread nothing was said in starts at 1 as before.
  const fresh = store.openThread("ember", "EMBER", "3.1", null, null);
  assert.deepEqual(say(store, fresh.id, "3.2", "person", "local", "新的"), [1, true]);
});

test("thread ids are never used again", () => {
  const store = memory();
  session(store, "a");
  const thread = store.openThread("ember", "EMBER", "1.1", null, null);
  store.joinThread(thread.id, "a", "ember");
  store.deleteSession("a");
  assert.ok(store.openThread("ember", "EMBER", "2.1", null, null).id > thread.id);
});

test("deleting removes the session's rows and the threads only it was in", () => {
  const store = memory();
  session(store, "a");
  session(store, "b");
  const shared = store.openThread("slack:T1", "C1", "1.1", null, null);
  const own = store.openThread("ember", "EMBER", "2.1", null, null);
  store.joinThread(shared.id, "a", "ds");
  store.joinThread(shared.id, "b", "ds");
  store.joinThread(own.id, "a", "ember");
  const [said] = say(store, shared.id, "1.1", "person", "U1", "hi");
  store.deliver(shared.id, said, ["a", "b"]);
  say(store, own.id, "2.2", "person", "local", "mine");
  store.setRead("local", own.id, 99);
  store.startTurn("t", "a", "input");
  store.setBinding("team", "a");
  store.setArchived("a", true, MANUAL);
  assert.ok(store.getSession("a")!.archivedAt! > 0);
  store.setArchived("a", false, MANUAL);
  assert.equal(store.getSession("a")!.archivedAt, null);
  const h = heard(store);
  store.deleteSession("a");
  const told = h.changes.flatMap((c) =>
    c.type === "sessionRemoved" ? [`removed ${c.key}`] : c.type === "threadRemoved" ? [`thread removed ${c.id}`] : c.type === "thread" ? [`thread ${c.id}`] : [],
  );
  assert.deepEqual(told, ["removed a", `thread removed ${own.id}`, `thread ${shared.id}`]);
  assert.equal(store.getSession("a"), null);
  assert.equal(store.getThread(own.id), null);
  assert.deepEqual(store.entriesAfter(own.id, 0), []);
  assert.deepEqual(store.threadSessions(shared.id).map((m) => m.session), ["b"]);
  assert.equal(store.pendingMessages("b").length, 1, "the other session keeps its delivery");
  assert.deepEqual(store.listTurns("a"), []);
  assert.equal(store.binding("team"), null);
});

test("the store announces what changed", () => {
  const store = memory();
  const h = heard(store);
  session(store, "a");
  const thread = store.openThread("ember", "EMBER", "1.1", null, null);
  store.joinThread(thread.id, "a", "ember");
  const [n] = say(store, thread.id, "1.2", "person", "local", "hi");
  store.deliver(thread.id, n, ["a"]);
  store.setRead("local", thread.id, n);
  store.recordProcess(42, 1, "claude", "x");
  store.forgetProcess(42);
  store.forgetProcess(42);
  const kinds = h.changes.map((c) => (["session", "thread", "read", "processes"].includes(c.type) ? c.type : "other"));
  assert.deepEqual(kinds, ["session", "session", "thread", "thread", "session", "read", "processes", "processes"]);
  assert.deepEqual(h.changes[2], { type: "thread", id: thread.id, entries: [] });
  const appended = h.changes[3]!;
  assert.ok(appended.type === "thread");
  assert.deepEqual([appended.id, appended.entries.map((e) => [e.n, e.text])], [thread.id, [[1, "hi"]]]);
  assert.deepEqual(h.changes[5], { type: "read", viewer: "local", thread: thread.id, n });
  h.stop();
  store.notify("a");
  assert.equal(h.changes.length, 8, "unsubscribed");
});

test("a session's chat is named by the thread said in last, as the lists have it, read by its rows alone", async () => {
  const time = testClock();
  await time.adjust(Date.parse("2026-10-25T00:00:00Z"));
  const store = Store.open(":memory:", null, time.clock);
  stores.push(store);
  session(store, "a");
  assert.equal(store.sessionChat("a"), null);
  const slack = store.openThread("slack", "C1", "1.1", null, null);
  const own = store.openThreadOf("ember", "EMBER", "2.1", null, null, "a");
  store.joinThread(slack.id, "a", "slack");
  store.joinThread(own.id, "a", "ember");
  say(store, slack.id, "1.2", "person", "u1", "看一下构建");
  await time.adjust(1000);
  say(store, own.id, "2.2", "person", "local", "hi");
  const named = () => [store.sessionChat("a")!.thread.id, store.sessionChat("a")!.firstText];
  // The still.fail chat said in last: its words are not asked (its title is its own, or 新对话).
  assert.deepEqual(named(), [own.id, null]);
  assert.equal(store.listThreads("", "a", null)[0]!.thread.id, own.id);
  await time.adjust(1000);
  say(store, slack.id, "1.3", "agent", "a", "好");
  assert.deepEqual(named(), [slack.id, "看一下构建"]);
  assert.equal(store.listThreads("", "a", null)[0]!.thread.id, slack.id);
});

test("a session's own chat is archived with it, a chat of its own alone; anything new said brings them back", () => {
  const store = memory();
  session(store, "a");
  const own = store.openThreadOf("ember", "EMBER", "1.1", null, null, "a");
  const other = store.openThread("ember", "EMBER", "2.1", null, null);
  store.joinThread(own.id, "a", "ember");
  store.joinThread(other.id, "a", "ember");
  say(store, other.id, "2.2", "person", "local", "hi");
  assert.equal(store.homeChat("a")!.id, own.id);
  assert.deepEqual(store.chatsOfTheirOwn().map((t) => t.id), [other.id]);
  const thread = (id: number) => store.getThread(id)!;
  const row = () => store.getSession("a")!;

  store.setArchived("a", true, AUTO);
  assert.deepEqual([row().archivedBy, thread(own.id).hiddenBy], [AUTO, AUTO]);
  assert.equal(thread(other.id).hiddenAt, null, "a chat of its own stays");
  // Its agent says something there: the session comes back, with its own chat.
  say(store, other.id, "2.3", "agent", "a", "done");
  assert.equal(row().archivedAt, null);
  assert.equal(row().shownAt, null, "brought back by what was said, not by hand");
  assert.equal(thread(own.id).hiddenAt, null);

  store.setThreadHidden(other.id, true, AUTO);
  assert.ok(thread(other.id).hiddenAt !== null);
  assert.equal(row().archivedAt, null, "its sessions stay");
  assert.ok(!existsSync(archiveFile(store, other.id)), "out of lists, its entries stay in the database");
  assert.deepEqual(store.entriesAfter(other.id, 0).map((e) => e.text), ["hi", "done"]);
  // Someone writes in it: shown again.
  say(store, other.id, "2.4", "person", "local", "again");
  assert.equal(thread(other.id).hiddenAt, null);
  // Hidden by hand, it stays hidden.
  store.setThreadHidden(other.id, true, MANUAL);
  assert.ok(store.manuallyArchived(other.id));
  say(store, other.id, "2.41", "agent", "a", "late");
  assert.ok(thread(other.id).hiddenAt !== null);
  store.setThreadHidden(other.id, false, MANUAL);

  // Archived by hand, nothing said brings it back: it takes no messages.
  store.setArchived("a", true, MANUAL);
  assert.ok(store.manuallyArchived(own.id));
  say(store, own.id, "1.2", "agent", "a", "late");
  assert.equal(row().archivedBy, MANUAL);
  assert.ok(thread(own.id).hiddenAt !== null);
  // Shown again by hand: the idle clock starts over.
  store.setArchived("a", false, MANUAL);
  assert.ok(row().shownAt !== null);
  assert.equal(store.manuallyArchived(own.id), false);

  // Archived by the station, an agent's word in its chat brings back every session that hears it.
  session(store, "b");
  store.joinThread(other.id, "b", "ember");
  store.setArchived("a", true, AUTO);
  store.setArchived("b", true, AUTO);
  say(store, other.id, "2.5", "agent", "b", "news");
  assert.deepEqual([row().archivedAt, store.getSession("b")!.archivedAt], [null, null]);
});

test("a database made before archiving gains its columns and each session's first chat is its own", () => {
  const path = join(tempdir(), "ember.db");
  const db = new DatabaseSync(path);
  const old = SCHEMA.replace("  archived_at INTEGER,\n  archived_by TEXT,\n  shown_at INTEGER,\n  cwd TEXT\n", "  archived_at INTEGER\n").replace(
    "  home TEXT,\n  hidden_at INTEGER,\n  hidden_by TEXT,\n  shown_at INTEGER,\n",
    "",
  );
  assert.ok(!old.includes("hidden_at"));
  db.exec(old);
  db.exec(`PRAGMA user_version = ${SCHEMA_VERSION}`);
  db.exec(`INSERT INTO sessions (key, connect, scope, runtime, profile, workspace, token, created_at, last_active_at, archived_at)
             VALUES ('a', 'ember', 'all', 'claude', 'cc', '/w/a', 'a', 1, 1, 5);
           INSERT INTO threads (id, surface, channel, thread_ts, created_at) VALUES (1, 'ember', 'EMBER', '1.1', 1), (2, 'ember', 'EMBER', '2.1', 2);
           INSERT INTO thread_sessions (thread, session, connect, joined_at) VALUES (1, 'a', 'ember', 1), (2, 'a', 'ember', 2);`);
  db.close();
  const store = open(path);
  const first = store.getThread(1)!;
  assert.deepEqual([first.home, first.hiddenAt, first.hiddenBy], ["a", 5, MANUAL]);
  assert.equal(store.getThread(2)!.home, null);
  assert.equal(store.getSession("a")!.archivedBy, MANUAL);
  store.close();
  // Opened again: nothing more to add.
  open(path);
});

test("a database made before clients gains the column and a message keeps its app through archiving", () => {
  const dir = tempdir();
  const path = join(dir, "ember.db");
  const db = new DatabaseSync(path);
  const old = SCHEMA.replace("  client TEXT,\n", "");
  assert.ok(!old.includes("client"));
  db.exec(old);
  // The view as it was made before.
  db.exec(MERGED.replace("m.declared, m.client, m.agent_identity,", "m.declared,"));
  db.exec(`PRAGMA user_version = ${SCHEMA_VERSION}`);
  db.close();
  const store = open(path, join(dir, "archive"));
  session(store, "a");
  const thread = store.openThread("ember", "EMBER", "1.1", null, null);
  store.joinThread(thread.id, "a", "ember");
  say(store, thread.id, "1.2", "person", "local", "旧的");
  const [n] = store.insertMessage({ ...newMessage(thread.id, "1.3", "person", "local", "新的"), client: "android 0.1.1123" });
  store.deliver(thread.id, n, ["a"]);
  const clients = () => store.messagesBefore(thread.id, null, 10).map((m) => m.client);
  assert.deepEqual(clients(), [null, "android 0.1.1123"]);
  assert.equal(store.pendingMessages("a")[0]!.message.client, "android 0.1.1123");
  store.setArchived("a", true, MANUAL);
  fileAway(store, thread.id);
  assert.deepEqual(clients(), [null, "android 0.1.1123"]);
  store.setArchived("a", false, MANUAL);
  assert.deepEqual(clients(), [null, "android 0.1.1123"]);
  store.close();
  open(path);
});

test("a widget's state is kept by session and path, its model told once until it changes", () => {
  const store = memory();
  session(store, "a");
  session(store, "b");
  const thread = store.openThread("ember", "EMBER", "3.1", null, null);
  store.joinThread(thread.id, "a", "ember");
  const path = "/w/a/uploads/pick.html";
  store.insertMessage({ ...newMessage(thread.id, "3.2", "agent", "a", "![](pick.html)"), attachments: [{ name: "pick.html", path, size: 9 }] });
  assert.equal(store.widgetState("a", path), null);
  store.putWidgetState("a", path, `{"modelContent":"red"}`, "red");
  store.putWidgetState("a", "/w/a/uploads/quiet.html", `{"privateContent":1}`, null);
  assert.equal(store.widgetState("a", path), `{"modelContent":"red"}`);
  assert.equal(store.widgetState("b", path), null, "kept per session");
  assert.deepEqual(store.untoldWidgetModels("a"), [{ path, name: "pick.html", thread: ["EMBER", "3.1"], model: "red" }]);
  store.markWidgetModelsTold("a", [[path, "red"]]);
  assert.deepEqual(store.untoldWidgetModels("a"), []);
  // The same model again is not news; another is, and one changed after it was read is not marked told.
  store.putWidgetState("a", path, `{"modelContent":"red","privateContent":2}`, "red");
  assert.deepEqual(store.untoldWidgetModels("a"), []);
  store.putWidgetState("a", path, `{"modelContent":"blue"}`, "blue");
  store.markWidgetModelsTold("a", [[path, "red"]]);
  assert.deepEqual(store.untoldWidgetModels("a").map((w) => w.model), ["blue"]);
  // A file no message of the session's threads carries: its path's name, no thread.
  store.putWidgetState("a", "/elsewhere/x.html", "{}", "x");
  const elsewhere = store.untoldWidgetModels("a").find((w) => w.path === "/elsewhere/x.html")!;
  assert.deepEqual([elsewhere.name, elsewhere.thread], ["x.html", null]);
  store.deleteSession("a");
  assert.equal(store.widgetState("a", path), null);
});

test("session fast migrates old databases and survives restart", () => {
  const path = join(tempdir(), "ember.db");
  let store = open(path);
  session(store, "old");
  store.close();
  const db = new DatabaseSync(path);
  db.exec("ALTER TABLE sessions DROP COLUMN fast");
  db.close();
  store = open(path);
  assert.equal(store.getSession("old")!.fast, null);
  store.setSessionFast("old", false);
  store.close();
  store = open(path);
  assert.equal(store.getSession("old")!.fast, false);
});

test("the latest turn is the last inserted when start times tie", () => {
  const store = memory();
  session(store, "same-ms");
  store.startTurn("first", "same-ms", "input");
  store.endTurn("first", "failed", "rate_limit: quota", null, null);
  store.startTurn("second", "same-ms", "resume");
  store.endTurn("second", "completed", null, null, null);
  store.db.exec("UPDATE turns SET started_at = 123 WHERE session_key = 'same-ms'");
  const latest = store.lastTurn("same-ms")!;
  assert.equal(latest.kind, "resume");
  assert.equal(latest.outcome, "completed");
  assert.equal(latest.detail, null);
});

test("a message keeps its model after switching, editing and archiving", () => {
  const dir = tempdir();
  const store = open(join(dir, "ember.db"), join(dir, "archive"));
  session(store, "a");
  const thread = store.openThread("ember", "EMBER", "1.1", null, null);
  store.joinThread(thread.id, "a", "ember");
  store.setSessionModel("a", "gpt-6-sol", "high");
  say(store, thread.id, "1.2", "agent", "a", "first");
  store.setSessionModel("a", "gpt-6-astra", "medium");
  say(store, thread.id, "1.3", "agent", "a", "second");
  store.editMessage("ember", "EMBER", "1.1", "1.2", "edited");
  const check = () => {
    const messages = store.messagesBefore(thread.id, null, 10);
    assert.equal(messages[0]!.agentIdentity.model, "gpt-6-sol");
    assert.equal(messages[0]!.agentIdentity.effort, "high");
    assert.equal(messages[0]!.agentIdentity.runtime, undefined);
    assert.equal(messages[1]!.agentIdentity.model, "gpt-6-astra");
    assert.equal(messages[0]!.text, "edited");
  };
  check();
  store.setArchived("a", true, MANUAL);
  check();
  store.setArchived("a", false, MANUAL);
  check();
});

test("an existing client view gains model identity even after a partial upgrade", () => {
  for (const alreadyAdded of [false, true]) {
    const path = join(tempdir(), "ember.db");
    const db = new DatabaseSync(path);
    db.exec(SCHEMA);
    // The immediately previous release already had client, but no model snapshot.
    db.exec(MERGED.replace("m.agent_identity, ", ""));
    // The broken upgrade added the column while leaving this old view in place.
    if (alreadyAdded) db.exec("ALTER TABLE entries ADD COLUMN agent_identity TEXT");
    db.exec(`PRAGMA user_version = ${SCHEMA_VERSION}`);
    db.exec(`INSERT INTO entries (thread, n, kind, ts, author_kind, author, text, client, at) VALUES (1, 1, 'message', '1.1', 'person', 'local', 'kept', 'android old', 100)`);
    db.exec(`INSERT INTO entries (thread, n, kind, target, author_kind, author, text, at) VALUES (1, 2, 'edit', 1, 'person', 'local', 'edited', 200)`);
    db.close();
    // Both the first upgrade and subsequent opens must keep existing data readable.
    for (let i = 0; i < 2; i++) {
      const store = open(path);
      const message = store.messageAt(1, "1.1")!;
      assert.equal(message.text, "edited");
      assert.equal(message.client, "android old");
      assert.equal(message.editedAt, 200);
      assert.equal(message.agentIdentity, null, "do not backfill old messages");
      assert.deepEqual(store.messagesBefore(1, null, 10), [message]);
      assert.deepEqual(store.lastMessage(1), message);
      store.close();
    }
  }
});

test("canonical and legacy system authors are read as the same kind", () => {
  const store = memory();
  const thread = store.openThread("ember", "EMBER", "1.1", null, null);
  store.db.exec(`INSERT INTO entries (thread, n, kind, ts, author_kind, author, text, at) VALUES (${thread.id}, 1, 'message', '1.1', 'stillfail', 'stillfail', 'x', 1)`);
  say(store, thread.id, "1.2", "ember", "ember", "y");
  assert.deepEqual(store.entriesAfter(thread.id, 0).map((e) => e.authorKind), ["ember", "ember"]);
  // Writes keep the legacy spelling.
  assert.equal((store.db.prepare("SELECT author_kind FROM entries WHERE n = 2").get() as any).author_kind, "ember");
});

// ── beyond tests.rs ──

test("an options card is kept as options too, and a choice that closes it ends the need", () => {
  const store = memory();
  session(store, "a");
  const thread = store.openThread("ember", "EMBER", "1.1", null, null);
  store.joinThread(thread.id, "a", "ember");
  const card = { type: "options", options: [{ label: "合并", action: "close" }, { label: "再看" }] };
  store.startTurnFor("t1", "a", "input", { profile: "cc", person: "local", thread: thread.id });
  const [n] = store.insertMessage({ ...newMessage(thread.id, "1.2", "agent", "a", "合并吗？"), card });
  const row = store.db.prepare("SELECT card, options FROM entries WHERE n = ?").get(n) as any;
  assert.deepEqual([JSON.parse(row.card), JSON.parse(row.options)], [card, card.options]);
  assert.deepEqual(store.pendingCard(thread.id)![1], card);
  // Old style: options alone become an options card.
  const [m] = store.insertMessage({ ...newMessage(thread.id, "1.3", "agent", "a", "选一个"), options: [{ label: "x" }] });
  assert.deepEqual(store.entriesBetween(thread.id, m, m)[0]!.card, { type: "options", options: [{ label: "x" }] });
  assert.equal(store.closeCard("local", thread.id, n, "合并"), false, "not the latest card");
  // Back to one card: a fresh thread.
  const t2 = store.openThread("ember", "EMBER", "2.1", null, null);
  store.joinThread(t2.id, "a", "ember");
  const [k] = store.insertMessage({ ...newMessage(t2.id, "2.2", "agent", "a", "合并吗？"), card });
  assert.equal(store.closeCard("local", t2.id, k, "合并"), false, "the agent is still composing (its turn runs)");
  store.setAbout("t1", [t2.id, k, "2.2"]);
  store.endTurn("t1", "completed", null, "need_help", null);
  assert.equal(store.closeCard("local", t2.id, k, "再看"), false, "a reply option does not close");
  const h = heard(store);
  assert.equal(store.closeCard("local", t2.id, k, "合并", "en"), true);
  assert.deepEqual(h.changes, [{ type: "session", key: "a" }, { type: "thread", id: t2.id, entries: [] }]);
  const last = store.lastTurn("a")!;
  assert.deepEqual([last.declared, last.ending, last.need], ["final", "all_done", "Chose “合并”"]);
  assert.equal(store.pendingCard(t2.id), null);
  assert.equal(store.closeCard("local", t2.id, k, "合并"), true, "closing again is no change");
  assert.equal(h.changes.length, 2);
  const answers = store.answersSince(0);
  assert.deepEqual(answers.map((a) => [a.question.n, a.by, a.answer]), [[k, "local", null]]);
  h.stop();
});

test("the cards answered lately of some threads alone are those the whole station's has in them", () => {
  const data = tempdir();
  const store = open(join(data, "stillfail.db"));
  session(store, "a");
  const card = { type: "options", options: [{ label: "x" }] };
  const threads = ["1", "2"].map((ts) => {
    const t = store.openThread("ember", "EMBER", `${ts}.0`, null, null);
    store.joinThread(t.id, "a", "ember");
    store.insertMessage({ ...newMessage(t.id, `${ts}.1`, "agent", "a", "?"), card });
    say(store, t.id, `${ts}.2`, "person", "me@x", "x");
    return t.id;
  });
  const reader = read.openStore(data);
  const whole = read.answersSince(reader, 0);
  assert.deepEqual(whole.map((a) => a.question.thread).sort(), [...threads].sort());
  assert.deepEqual(read.answersSince(reader, 0, [threads[1]!]), whole.filter((a) => a.question.thread === threads[1]));
  assert.deepEqual(read.answersSince(reader, 0, []), []);
});

test("an agent withdraws its own card only", () => {
  const store = memory();
  session(store, "a");
  const thread = store.openThread("ember", "EMBER", "1.1", null, null);
  const [n] = store.insertMessage({ ...newMessage(thread.id, "1.2", "agent", "a", "?"), card: { type: "text" } });
  assert.equal(store.withdrawCard("b", thread.id, "1.2"), false);
  assert.equal(store.withdrawCard("a", thread.id, "1.2"), true);
  assert.equal(store.pendingCard(thread.id), null);
  assert.deepEqual(store.answersSince(0), [], "withdrawn is not answered");
  assert.ok(n > 0);
});

test("an agent restates its card on its post: an edit with the same words and the new card, its latest the base of the next", () => {
  const store = memory();
  session(store, "a");
  const thread = store.openThread("ember", "EMBER", "1.1", null, null);
  const card = { type: "options", options: [{ label: "仅本次" }], vault: { request: "r_1", name: "GitHub" } };
  const [n] = store.insertMessage({ ...newMessage(thread.id, "1.2", "agent", "a", "申请使用「GitHub」"), card });
  assert.equal(store.restateCard("b", thread.id, "1.2", (c) => c), false, "not another's");
  assert.equal(store.restateCard("a", thread.id, "1.2", (c) => ({ ...c, vault: { ...c.vault, outcome: { status: "granted" } } })), true);
  assert.equal(store.restateCard("a", thread.id, "1.2", (c) => ({ ...c, seen: c.vault.outcome.status })), true);
  const edits = store.entriesAfter(thread.id, n).filter((e) => e.kind === "edit");
  assert.deepEqual(edits.map((e) => [e.target, e.text]), [[n, "申请使用「GitHub」"], [n, "申请使用「GitHub」"]]);
  assert.deepEqual(edits[1]!.card, { ...card, vault: { ...card.vault, outcome: { status: "granted" } }, seen: "granted" });
  assert.equal(store.pendingCard(thread.id)?.[1].vault.request, "r_1", "the post's card still asks: restating it decides nothing");
});

test("a turn nobody's message started goes on with the work of the one before; a wait stopped is aborted", () => {
  const store = memory();
  session(store, "a");
  assert.equal(store.hasTurns("a"), false);
  store.startTurnFor("t1", "a", "input", { profile: "cc", person: "me@x", thread: 7 });
  store.endTurn("t1", "completed", null, "waiting", 60);
  store.setWaitFor("t1", "CI", false);
  // Turns started in the same ms tie in ORDER BY started_at (as in the Rust): keep them apart.
  store.db.exec("UPDATE turns SET started_at = started_at - 1000 WHERE id = 't1'");
  store.startTurn("t2", "a", "nudge");
  const t2 = store.db.prepare("SELECT profile, person, thread FROM turns WHERE id = 't2'").get() as any;
  assert.deepEqual({ ...t2 }, { profile: null, person: "me@x", thread: 7 });
  assert.equal(store.stopWait("a"), false, "the latest turn is not waiting");
  store.endTurn("t2", "completed", null, "waiting", 30);
  assert.equal(store.stopWait("a"), true);
  const last = store.lastTurn("a")!;
  assert.deepEqual([last.outcome, last.declared, last.waitSeconds, last.detail], ["aborted", null, null, "other: stopped while waiting"]);
  assert.deepEqual([store.listTurns("a")[0]!.summary.waitFor, store.listTurns("a")[0]!.summary.waitWatch], ["CI", false]);
  assert.equal(store.toldNotes("a") > 0, true, "a new session was told every note");
  store.setToldNotes("a", 3);
  assert.equal(store.toldNotes("a"), 3);
  const stats = store.sessionStats(null).get("a")!;
  assert.deepEqual([stats.turns, stats.lastTurn!.outcome], [2, "aborted"]);
});

test("bindings tell both sessions; delivered can be taken back", () => {
  const store = memory();
  session(store, "a");
  session(store, "b");
  const h = heard(store);
  store.setBinding("team", "b");
  store.setBinding("team", "a");
  assert.deepEqual(h.changes, [{ type: "session", key: "b" }, { type: "session", key: "a" }, { type: "session", key: "b" }]);
  assert.deepEqual([...store.listBindings()], [["a", ["team"]]]);
  h.stop();
  const thread = store.openThread("ember", "EMBER", "1.1", null, null);
  store.joinThread(thread.id, "a", "ember");
  const [n] = say(store, thread.id, "1.2", "person", "local", "hi");
  store.deliver(thread.id, n, ["a"]);
  store.markDelivered("a", [{ thread: thread.id, n, apart: false }]);
  assert.deepEqual([...store.heardThreads("a")], [thread.id]);
  store.markUndelivered("a", [{ thread: thread.id, n, apart: false }]);
  assert.equal(store.pendingMessages("a").length, 1);
  assert.deepEqual([...store.heardThreads("a")], []);
});

test("jobs: started, said, ended and cleared", () => {
  const store = memory();
  session(store, "a");
  const job: JobRow = {
    id: "j1", sessionKey: "a", name: "build", command: "make", cwd: "/w/a", port: null, token: "tok", state: "running", pgid: 10,
    exitCode: null, startedAt: 1, endedAt: null, restarts: 0, log: "/w/a/j1.log", watch: true,
  };
  const h = heard(store);
  store.insertJob(job);
  assert.deepEqual(store.getJob("j1"), job);
  assert.equal(store.jobByToken("tok")!.id, "j1");
  for (let i = 0; i < 55; i++) store.addJobNotice("j1", `n${i}`);
  assert.equal(store.jobNotices("j1", 100).length, 50);
  assert.equal(store.jobNotices("j1", 1)[0]!.text, "n54");
  store.jobStarted("j1", 11, true);
  assert.deepEqual([store.getJob("j1")!.pgid, store.getJob("j1")!.restarts], [11, 1]);
  store.jobEnded("j1", "exited", 0);
  assert.deepEqual(store.clearEndedJobs("a"), [["j1", "/w/a/j1.log"]]);
  assert.deepEqual(store.listJobs(null), []);
  assert.deepEqual(h.changes.slice(-2), [{ type: "session", key: "a" }, { type: "jobRemoved", id: "j1", session: "a" }]);
  h.stop();
});

test("usage: the sessions at work are found by when their turns ended, once each, not by reading every turn", () => {
  const store = memory();
  for (const key of ["a", "b", "c"]) session(store, key);
  store.startTurn("t1", "a", "input");
  store.startTurn("t2", "b", "input");
  store.endTurn("t2", "completed", null, null, null);
  store.startTurn("t3", "b", "input");
  store.endTurn("t3", "completed", null, null, null);
  store.startTurn("t4", "b", "job");
  assert.deepEqual(store.usageActiveSessions(0).sort(), ["a", "b"]);
  assert.deepEqual(store.usageActiveSessions(Number.MAX_SAFE_INTEGER).sort(), ["a", "b"], "running ones whenever");
});

test("what the station asks again and again is planned by an index, never a scan of what grows with time", () => {
  const store = memory();
  // As the station's SQLite (node's) plans each: a scan only of an index that holds the sessions shown or running, the
  // login cards, or of the small one that counts sessions (or of what a subquery found); a table, or an index of every
  // turn, job or entry, never.
  const planned: [string, unknown[]][] = [
    [ACTIVE_SESSIONS, [0]], [LIVE_SESSIONS, []], [ANY_RUNNING, []], [RUNNING_SESSIONS, []], [JOBS_RUNNING, []], [JOBS_UP, []], [SESSION_JOBS, ["a"]],
    [STATS_OF, ["a"]], [SESSION_COUNTS, []], [LATEST_DECISIONS, [0]], [CLOSED_SINCE, [0]], [LOGIN_CARDS, ["%l1%"]], [CARD_BEFORE, [1, 9]], [OPTIONS_BEFORE, [1, 9]],
    [TURNS_FROM, ["a", 0]], [TURNS_BETWEEN, ["a", 0, 9]], [TAKEN_SINCE, ["a", "ember", 0]], [SESSION_OF_RUNTIME, ["claude", "r1"]], [SAID_SINCE, [1, 0]],
  ];
  const scans = /^SCAN (?!CONSTANT ROW$|\(subquery-\d+\)$|\w+ USING (?:COVERING )?INDEX (?:sessions_live|sessions_running|sessions_by_connect|entries_login_cards)\b)/;
  const plans = new Map<string, string[]>();
  for (const [sql, args] of planned) {
    const plan = (store.db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...(args as never[])) as { detail: string }[]).map((r) => r.detail);
    assert.ok(!plan.some((d) => scans.test(d)), `${sql}\n  ${plan.join(" | ")}`);
    plans.set(sql, plan);
  }
  // The latest card before a message: by the index of cards, not by going back over the thread to it.
  assert.ok(plans.get(CARD_BEFORE)!.some((d) => d.includes("entries_cards")), plans.get(CARD_BEFORE)!.join(" | "));
  assert.ok(plans.get(OPTIONS_BEFORE)!.some((d) => d.includes("entries_options")), plans.get(OPTIONS_BEFORE)!.join(" | "));
  assert.ok(plans.get(SAID_SINCE)!.some((d) => d.includes("entries_people_since (thread=? AND at>?)")), plans.get(SAID_SINCE)!.join(" | "));
  // Each session's latest check of the last days: from the index of their times alone.
  assert.ok(plans.get(LATEST_DECISIONS)!.some((d) => d.includes("COVERING INDEX decision_checks_lately")), plans.get(LATEST_DECISIONS)!.join(" | "));
  // The turns the usage counter reads at each part of a transcript: those of its calls' time alone.
  assert.ok(plans.get(TURNS_BETWEEN)!.some((d) => d.includes("turns_by_session (session_key=? AND started_at>? AND started_at<?)")), plans.get(TURNS_BETWEEN)!.join(" | "));
  assert.ok(plans.get(TAKEN_SINCE)!.some((d) => d.includes("deliveries_taken (session=? AND delivered_at>?)")), plans.get(TAKEN_SINCE)!.join(" | "));
  // What each says.
  session(store, "a");
  session(store, "b");
  store.setArchived("b", true, MANUAL);
  assert.deepEqual(store.liveSessions().map((s) => s.key), ["a"]);
  assert.deepEqual(store.sessionCounts(), [{ connect: "ds", ws: null, n: 2 }]);
  assert.equal(store.anyRunning(), false);
  store.startTurn("t1", "a", "input");
  const stats = store.statsOf(["a", "missing"]);
  assert.deepEqual([...stats.keys()], ["a"]);
  assert.deepEqual([stats.get("a")!.turns, stats.get("a")!.pending, stats.get("a")!.firstText, stats.get("a")!.lastTurn?.kind], [1, 0, null, "input"]);
  // In use: shown, or at work though archived.
  assert.deepEqual(store.sessionsInUse().map((s) => s.key), ["a"]);
  store.setRunning("b", true);
  assert.deepEqual(store.runningSessions().map((s) => s.key), ["b"]);
  assert.deepEqual(store.sessionsInUse().map((s) => s.key), ["a", "b"]);
  store.setRunning("a", true);
  assert.deepEqual(store.sessionsInUse().map((s) => s.key).sort(), ["a", "b"], "each once");
  // The session that went on with a runtime's session: by its current one, or one it ran in before.
  store.setRuntimeSessionId("a", "r2");
  store.ranIn("b", "r1", null);
  assert.equal(store.sessionOfRuntime("claude", "r2")?.key, "a");
  assert.equal(store.sessionOfRuntime("claude", "r1")?.key, "b");
  assert.equal(store.sessionOfRuntime("codex", "r1"), null, "another runtime's");
  assert.equal(store.sessionOfRuntime("claude", "r9"), null);
});

test("usage: where a model's context was compacted is kept as calls are recorded, and made once from those before", () => {
  const path = join(tempdir(), "stillfail.db");
  let store = open(path);
  session(store, "a");
  const call = (id: string, at: number, sent: number, model = "m", subagent = false) =>
    [{ id, at, model, subagent, fast: false, input: sent, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: subagent ? null : sent, window: null }, { turn: null, person: null, thread: null, profile: "cc" }] as const;
  store.recordUsage("/t.jsonl", { session: "a", offset: 1, model: "m" }, "claude", [
    call("c1", 1000, 120_000),
    call("s1", 1500, 5_000, "m", true), // a sub-agent's: not the session's context
    call("c2", 2000, 30_000), // compacted from 120 000
    call("c3", 3000, 40_000), // not compacted: up
    call("c4", 4000, 90_000, "other"), // another model: not compared
    call("c5", 5000, 20_000, "other"), // compacted from 90 000
    call("c6", 6000, 10_000, "other"), // under COMPACTED_FROM before: not
  ] as never);
  assert.deepEqual([...store.compactionPoints(0)].sort(), [["m", 120_000], ["other", 90_000]]);
  assert.deepEqual([...store.compactionPoints(4500)], [["other", 90_000]], "those since");
  // A database from before them: made from the calls it has, as it opens.
  store.db.exec("DROP TRIGGER usage_compactions_add; DROP TABLE usage_compactions;");
  store.close();
  store = open(path);
  assert.deepEqual([...store.compactionPoints(0)].sort(), [["m", 120_000], ["other", 90_000]]);
});

test("usage: a call is recorded once, its output grown; turns tell whom they were for", () => {
  const store = memory();
  session(store, "a");
  store.startTurnFor("t1", "a", "input", { profile: "cc", person: "me@x", thread: 3 });
  const call = { id: "c1", at: 1000, model: "m", subagent: false, fast: true, input: 1, cacheRead: 2, cacheWrite: 3, cacheWriteLong: 4, output: 5, calls: 1, context: 10, window: null };
  const of = { turn: "t1", person: "me@x", thread: 3, profile: "cc" };
  assert.equal(store.recordUsage("/t.jsonl", { session: "a", offset: 10, model: "m" }, "claude", [[call, of]]), 1);
  assert.equal(store.recordUsage("/t.jsonl", { session: "a", offset: 20, model: "m" }, "claude", [[{ ...call, output: 9 }, of]]), 0);
  assert.deepEqual(store.usageFiles().get("/t.jsonl"), { session: "a", offset: 20, model: "m" });
  const [g] = store.usageGroups(0, 2000, 0);
  assert.deepEqual([g!.calls, g!.output, g!.fast, g!.day], [1, 9, true, "1970-01-01"]);
  assert.equal(store.usageSince(), 1000);
  assert.deepEqual(store.usageTurns("a", 0, 2000).map((t) => [t.id, t.of.person, t.of.thread, t.of.profile]), [["t1", "me@x", 3, "cc"]]);
  assert.deepEqual(store.usageActiveSessions(0), ["a"]);
  const h = heard(store);
  store.usageChanged(["a"]);
  assert.deepEqual(h.changes, [{ type: "usage", sessions: ["a"] }]);
  h.stop();
});

test("usage: a session's calls added up by the database, those from before the totals and those an older station records too", () => {
  const path = join(tempdir(), "usage.db");
  const of = { turn: null, person: null, thread: null, profile: null };
  const call = (id: string, model: string | null, output: number) => ({ id, at: 1000, model, subagent: false, fast: false, input: 1, cacheRead: 2, cacheWrite: 3, cacheWriteLong: 4, output, calls: 1, context: 10, window: null });
  const first = open(path);
  session(first, "a");
  first.recordUsage("/a.jsonl", { session: "a", offset: 1, model: "m" }, "claude", [[call("c1", "m", 5), of], [call("c2", null, 1), of]]);
  first.close();
  // A database from before the totals: what was recorded is added up as it is opened.
  const before = new DatabaseSync(path);
  before.exec("DROP TRIGGER usage_totals_add; DROP TRIGGER usage_totals_grow; DROP TRIGGER usage_totals_drop; DROP TABLE usage_totals;");
  before.close();
  const store = open(path);
  // A call's output grown, a new call, and one recorded by a station process from before the totals.
  store.recordUsage("/a.jsonl", { session: "a", offset: 2, model: "m" }, "claude", [[call("c1", "m", 9), of], [call("c3", "m", 2), of]]);
  const older = new DatabaseSync(path);
  older.exec("INSERT INTO usage (id, at, session, runtime, model, input, cache_read, cache_write, cache_write_long, output) VALUES ('c4', 1000, 'a', 'claude', 'm', 1, 2, 3, 4, 7)");
  older.close();
  assert.deepEqual(
    store.usageOfSession("a").map((g) => [g.runtime, g.model, g.calls, g.input, g.cacheRead, g.cacheWrite, g.cacheWriteLong, g.output]),
    [["claude", null, 1, 1, 2, 3, 4, 1], ["claude", "m", 3, 3, 6, 9, 12, 18]],
  );
  assert.deepEqual(store.usageOfSession("b"), []);
});

test("usage: the page's days are the calls added up, as kept by quarter of an hour, whatever the range and time zone", () => {
  const path = join(tempdir(), "usage.db");
  let store = open(path);
  session(store, "a");
  session(store, "b");
  // Calls over three days, a few in each quarter, for two sessions, threads, people and models (some none).
  let seed = 7;
  const next = (n: number) => ((seed = (seed * 48271) % 2147483647), seed % n);
  const day = 86_400_000;
  const calls = Array.from({ length: 600 }, (_, i) => {
    const of = { turn: null, person: [null, "p@x", "q@x"][next(3)]!, thread: [null, 1, 2][next(3)]!, profile: [null, "cc"][next(2)]! };
    const c = { id: `c${i}`, at: day + next(3 * day), model: [null, "m", "n"][next(3)]!, subagent: false, fast: next(2) === 0, input: next(100), cacheRead: next(100), cacheWrite: next(100), cacheWriteLong: next(100), output: next(100), calls: 1 + next(3), context: null, window: null };
    return [next(2) === 0 ? "a" : "b", c, of] as const;
  });
  const record = (only: readonly (typeof calls)[number][]) => {
    for (const [key, c, of] of only) store.recordUsage(`/${key}.jsonl`, { session: key, offset: 1, model: null }, "claude", [[c, of]] as never);
  };
  record(calls.slice(0, 400));
  store.close();
  // A database from before them: made from the calls it has as it opens, kept from then on.
  const before = new DatabaseSync(path);
  before.exec("DROP TRIGGER usage_quarters_add; DROP TRIGGER usage_quarters_drop; DROP TRIGGER usage_quarters_grow; DROP TABLE usage_quarters;");
  before.close();
  store = open(path);
  record(calls.slice(400));
  // Outputs grown, and calls taken away.
  for (const [key, c, of] of calls.slice(0, 50)) store.recordUsage(`/${key}.jsonl`, { session: key, offset: 2, model: null }, "claude", [[{ ...c, output: c.output + 1000 }, of]] as never);
  store.db.exec("DELETE FROM usage WHERE id IN ('c3', 'c77', 'c450')");
  const one = `SELECT strftime('%Y-%m-%d', (at + ?3 * 60000) / 1000, 'unixepoch') AS day, session, thread, person, profile, runtime, model, fast,
      SUM(calls) AS calls, SUM(input) AS input, SUM(cache_read) AS cache_read, SUM(cache_write) AS cache_write, SUM(cache_write_long) AS cache_write_long, SUM(output) AS output
    FROM usage WHERE at >= ?1 AND at < ?2 GROUP BY day, session, thread, person, profile, runtime, model, fast`;
  const sorted = (rows: unknown[]) => rows.map((r) => JSON.stringify(r)).sort();
  const some = store.db.prepare(USAGE_GROUPS).all(day + 5 * 900_000 + 7, day * 3 - 11, 480).length;
  assert.ok(some > 100, `${some} groups`);
  const q = 900_000;
  const ranges = [[0, 2 ** 62], [day + 5 * q, day * 3], [day + 5 * q + 7, day * 3 - 11], [day * 2 + 3, day * 2 + 400], [day * 2, day * 2 + q], [day * 3 + 1, day * 2], [-5, day + q + 1]];
  for (const [from, to] of ranges) {
    for (const tz of [0, 480, -300, 330, 345, 7, -1]) {
      const kept = store.db.prepare(USAGE_GROUPS).all(from!, to!, tz);
      const a = sorted(kept), b = sorted(store.db.prepare(one).all(from!, to!, tz));
      assert.deepEqual(a, b, `${from}..${to} at ${tz}: ${JSON.stringify([a.filter((x) => !b.includes(x)).slice(0, 3), b.filter((x) => !a.includes(x)).slice(0, 3)])}`);
    }
  }
  store.close();
});

test("usage: a row is the calls it says, and a database from before says each was one, with the context it sent", () => {
  const path = join(tempdir(), "usage.db");
  const of = { turn: null, person: null, thread: null, profile: "cc" };
  const call = (id: string, at: number, input: number, more: object = {}) =>
    [{ id, at, model: "m", subagent: false, fast: false, input, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: input, window: null, ...more }, of] as const;
  let store = open(path);
  session(store, "a");
  store.recordUsage("/a.jsonl", { session: "a", offset: 1, model: "m" }, "claude", [call("c1", 1000, 120_000), call("s1", 1500, 7, { subagent: true, context: null })] as never);
  store.close();
  // As a station from before the columns kept it: its triggers too.
  const before = new DatabaseSync(path);
  before.exec(`DROP TRIGGER usage_totals_add; DROP TRIGGER usage_totals_drop; DROP TRIGGER usage_compactions_add;
    DROP TRIGGER usage_quarters_add; DROP TRIGGER usage_quarters_drop; DROP TRIGGER usage_quarters_grow; DROP TABLE usage_quarters;
    ALTER TABLE usage DROP COLUMN calls; ALTER TABLE usage DROP COLUMN context; ALTER TABLE usage DROP COLUMN context_window;
    CREATE TRIGGER usage_totals_add AFTER INSERT ON usage BEGIN
      INSERT INTO usage_totals VALUES (NEW.session, NEW.runtime, COALESCE(NEW.model, ''), NEW.fast, 1, NEW.input, NEW.cache_read, NEW.cache_write, NEW.cache_write_long, NEW.output)
      ON CONFLICT (session, runtime, model, fast) DO UPDATE SET calls = calls + 1, input = input + excluded.input;
    END;
    CREATE TRIGGER usage_totals_drop AFTER DELETE ON usage BEGIN UPDATE usage_totals SET calls = calls - 1 WHERE session = OLD.session; END;
    CREATE TRIGGER usage_compactions_add AFTER INSERT ON usage BEGIN SELECT 1; END;`);
  before.close();
  store = open(path);
  // Each call from before is one, its context what it sent (a subagent's none), as before.
  assert.deepEqual(store.lastContexts("a", 5).map((c) => [c.context, c.window]), [[120_000, null]]);
  // A turn told at once is its calls; the context it ended with is what it says, compacted from the one before.
  store.recordUsage("/a.jsonl", { session: "a", offset: 2, model: "m" }, "claude", [call("c2", 2000, 300_000, { calls: 3, context: 20_000, window: 200_000 })] as never);
  assert.deepEqual(store.usageOfSession("a").map((g) => [g.calls, g.input]), [[5, 420_007]]);
  assert.deepEqual(store.usageGroups(0, 3000, 0).reduce((n, g) => n + g.calls, 0), 5);
  assert.deepEqual(store.lastContexts("a", 1).map((c) => [c.context, c.window]), [[20_000, 200_000]]);
  assert.deepEqual([...store.compactionPoints(0)], [["m", 120_000]]);
  store.close();
});

test("a session's usage as its summary says it: kept as told, a change told as the session's only once it rests", () => {
  const data = tempdir();
  const store = open(join(data, "stillfail.db"));
  session(store, "a");
  const h = heard(store);
  const usage = { modelCalls: 2, inputTokens: 30, cachedTokens: 20, outputTokens: 4, model: "m", contextTokens: 15, contextWindow: null };
  store.setRunning("a", true);
  h.changes.length = 0;
  store.setSessionUsage("a", usage);
  assert.deepEqual(h.changes, [], "at work: its stream tells it");
  assert.deepEqual(store.sessionUsage("a"), usage);
  store.setRunning("a", false);
  h.changes.length = 0;
  store.setSessionUsage("a", usage);
  assert.deepEqual(h.changes, [], "the same: nothing");
  store.setSessionUsage("a", { ...usage, modelCalls: 3, cost: 0.5 });
  assert.deepEqual(h.changes, [{ type: "session", key: "a" }], "at rest: told as the session's");
  store.setSessionUsage("a", { ...usage, modelCalls: 4 }, true);
  assert.deepEqual(h.changes.length, 1, "quiet: not told");
  store.setSessionUsage("gone", usage);
  assert.equal(store.sessionUsage("gone"), null, "no session: none kept");
  session(store, "b");
  assert.deepEqual(store.sessionKeys().sort(), ["a", "b"]);
  const reader = read.openStore(data);
  assert.deepEqual([...read.sessionUsages(reader, null)], [["a", { ...usage, modelCalls: 4 }]]);
  assert.deepEqual([...read.sessionUsages(reader, "b")], []);
  h.stop();
});
