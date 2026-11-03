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
  ANY_RUNNING, AUTO, type AuthorKind, CARD_BEFORE, CLOSED_SINCE, CLOSED_THREAD_SINCE, type EntryRow, HEARD_IN, JOBS_RUNNING, JOBS_UP, type JobRow, LATEST_DECISIONS, LIVE_SESSIONS, LOGIN_CARDS, MODELS_USED_BY,
  MANUAL, type NewMessage, OPTIONS_BEFORE, PEOPLE_SAID_AFTER, RUNNING_SESSIONS, SAID_SINCE, SCHEMA_VERSION, SESSION_COUNTS, SESSION_JOBS, SESSION_OF_RUNTIME, STATS_OF, Store, type StoreChange, newMessage,
} from "../src/store/store.ts";
import { MERGED, SCHEMA } from "../src/store/schema.ts";
import { CC_THREADS_SQL } from "../src/store/rows.ts";
import { ACTIVE_SESSIONS, TAKEN_SINCE, TURNS_BETWEEN, TURNS_FROM } from "../src/store/usage.ts";
import { detailQuery } from "../src/store/usage-detail.ts";
import { REMOTE_RUNS_ALL, REMOTE_RUNS_OF } from "../src/store/remote-runs.ts";
import * as read from "../src/read/store.ts";
import { type CardEnd, cardsEnded } from "../src/connects/card-ends.ts";
import { fileAway } from "./archived-before.ts";
import { testClock } from "./hub-fakes.ts";
import type { Viewer } from "../src/mesh/credential.ts";

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

test("a write waits its turn while another of the station's writers writes, not refused at once", () => {
  // Begun deferred, a transaction that read first was refused at its first write (SQLITE_BUSY_SNAPSHOT, "database is
  // locked", no wait) where another connection wrote meanwhile: the usage worker filling its statistics, and a person's
  // message was not sent (ccvm, 2026-11-03).
  const path = join(tempdir(), "s.db");
  const store = open(path);
  const other = new DatabaseSync(path, { timeout: 0 });
  // SQLite as it is: read, another writes, then write.
  const raw = new DatabaseSync(path, { timeout: 0 });
  raw.exec("BEGIN");
  raw.prepare("SELECT count(*) FROM sessions").get();
  other.exec("INSERT INTO kept_chats (viewer, thread) VALUES ('x', 1)");
  assert.throws(() => raw.exec("INSERT INTO kept_chats (viewer, thread) VALUES ('y', 2)"), /locked/);
  raw.exec("ROLLBACK");
  // The store's: the writing taken as it begins, so another writer waits for it (or is refused itself) instead.
  const begun: string[] = [];
  // (the connection itself's: the store's is a proxy that times what it runs, store/timed.ts)
  store.db.exec = function (this: DatabaseSync, sql: string) {
    begun.push(sql);
    return DatabaseSync.prototype.exec.call(this, sql);
  };
  session(store, "k");
  const thread = store.openThread("ember", "EMBER", "1.0", null, null).id;
  say(store, thread, "1.1", "person", "a@x", "hi");
  assert.ok(begun.length > 0 && begun.every((sql) => sql !== "BEGIN"), `every transaction takes the writing as it begins: ${begun.filter((s) => s.startsWith("BEGIN"))}`);
  assert.ok(begun.includes("BEGIN IMMEDIATE"));
  raw.close();
  other.close();
});

test("a database of another schema version is refused", () => {
  const path = join(tempdir(), "ember.db");
  const db = new DatabaseSync(path);
  db.exec("CREATE TABLE sessions (key TEXT); PRAGMA user_version = 8;");
  db.close();
  assert.throws(() => Store.open(path), /schema version 8; this station uses 13/);
});

test("a new database is made at version 13", () => {
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

test("counting people for a title stops at the threshold even in a long conversation", () => {
  const store = memory();
  const thread = store.openThread("ember", "EMBER", "many", null, null).id;
  const insert = store.db.prepare("INSERT INTO entries (thread, n, kind, author_kind, author, text, at) VALUES (?, ?, 'message', 'person', 'p', 'hello', ?)");
  store.db.exec("BEGIN");
  for (let n = 1; n <= 2_000; n++) insert.run(thread, n, n);
  store.db.exec("COMMIT");
  const count = store.peopleSaidAfter.bind(store);
  assert.equal(count(thread, 0, 5), 5);
  assert.equal(count(thread, 1_998, 5), 2);
  assert.equal(count(thread, 2_000, 5), 0);
  assert.equal(count(thread, 0, 2), 2);
  assert.equal(count(thread, 0, 0), 0);
  const plan = store.db.prepare(`EXPLAIN QUERY PLAN ${PEOPLE_SAID_AFTER}`).all(thread, 0, 5) as { detail: string }[];
  assert.match(plan.map((p) => p.detail).join(" | "), /SEARCH entries USING (?:COVERING )?INDEX entries_people_by_n \(thread=\? AND n>\?\)/);
  let examined = 0;
  store.db.function("count_examined", (n) => { examined++; return n; });
  const probed = PEOPLE_SAID_AFTER.replace("n > ?", "n > ? AND count_examined(n) IS NOT NULL");
  const query = store.db.prepare(probed);
  assert.equal((query.get(thread, 0, 5) as { c: number }).c, 5);
  assert.equal(examined, 5, "only the messages needed for the decision are visited");
  examined = 0;
  assert.equal((query.get(thread, 1_000, 5) as { c: number }).c, 5);
  assert.equal(examined, 5, "more matching history does not increase the work");
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

test("an archived thread keeps its entries in the database", () => {
  const archive = tempdir();
  const store = open(":memory:", archive);
  session(store, "a");
  const own = store.openThread("ember", "EMBER", "2.1", null, null);
  store.joinThread(own.id, "a", "ember");
  say(store, own.id, "2.2", "person", "local", "看看");
  say(store, own.id, "2.3", "agent", "a", "好");
  const before = store.listThreads("local", null, own.id)[0];
  const entries = store.entriesAfter(own.id, 0);
  store.setArchived("a", true, MANUAL);
  assert.ok(!existsSync(join(archive, "threads", `${own.id}.jsonl.zst`)), "archived, its entries stay where they are");
  assert.deepEqual(store.entriesAfter(own.id, 0), entries);
  assert.deepEqual(store.listThreads("local", null, own.id)[0], before);
});

test("a database of version 12 has the threads a station before wrote out to files brought back, and goes to 13", () => {
  const data = tempdir();
  const path = join(data, "stillfail.db");
  const archive = join(data, "archive");
  const store = open(path, archive);
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
  const before = store.listThreads("local", null, null);
  const entries = [store.entriesAfter(own.id, 0), store.entriesAfter(shared.id, 0)];
  store.setArchived("a", true, MANUAL);
  store.setArchived("b", true, MANUAL);
  const files = [fileAway(store, own.id), fileAway(store, shared.id)];
  // The shape the Rust station wrote (serde's EntryRow).
  const text = zstdDecompressSync(readFileSync(files[0]!)).toString("utf8");
  assert.ok(text.split("\n")[0]!.startsWith(`{"thread":${own.id},"n":1,"kind":"message","target":null,"ts":"2.2","authorKind":"person"`), text);
  store.db.exec("CREATE TABLE IF NOT EXISTS items (thread INTEGER)");
  store.close();

  const again = open(path, archive);
  assert.deepEqual([again.entriesAfter(own.id, 0), again.entriesAfter(shared.id, 0)], entries);
  assert.deepEqual(again.listThreads("local", null, null), before);
  assert.deepEqual(again.participants("a").get("a"), ["local", "slack:ds:U1"]);
  assert.ok(files.every((f) => !existsSync(f)), "the files go once their entries are back");
  const has = (type: string, name: string) => again.db.prepare("SELECT 1 FROM sqlite_master WHERE type = ? AND name = ?").get(type, name) !== undefined;
  assert.ok(!has("table", "items") && !has("index", "threads_archived"));
  assert.equal((again.db.prepare("PRAGMA user_version").get() as any).user_version, SCHEMA_VERSION);
  // Said in again, numbered on.
  assert.deepEqual(say(again, own.id, "2.4", "person", "local", "还在吗"), [3, true]);
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
  // Archived: the same.
  store.setArchived("a", true, MANUAL);
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
  db.exec("DROP VIEW merged; DROP INDEX entries_letters; DROP INDEX entries_said; ALTER TABLE entries DROP COLUMN letter");
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

test("an archived thread whose file is lost comes back empty, and is counted on from what was read of it", () => {
  const data = tempdir();
  const path = join(data, "stillfail.db");
  const before = open(path, join(data, "archive"));
  session(before, "a");
  session(before, "b");
  const lost = before.openThread("ember", "EMBER", "1.1", null, null);
  const kept = before.openThread("ember", "EMBER", "2.1", null, null);
  before.joinThread(lost.id, "a", "ember");
  before.joinThread(kept.id, "b", "ember");
  say(before, lost.id, "1.2", "person", "local", "看看");
  say(before, lost.id, "1.3", "agent", "a", "好");
  say(before, lost.id, "1.4", "agent", "a", "做完了");
  say(before, kept.id, "2.2", "person", "local", "还有这个");
  before.setRead("local", lost.id, 3);
  before.setArchived("a", true, MANUAL);
  rmSync(fileAway(before, lost.id));
  before.close();
  const store = open(path, join(data, "archive"));

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

test("old transcript records keep their runtime when a chat changes runtime", () => {
  const path = join(tempdir(), "ember.db");
  let store = open(path);
  session(store, "old");
  store.setRuntimeSessionId("old", "earlier");
  store.ranIn("old", "earlier", "cc");
  store.close();
  const db = new DatabaseSync(path);
  db.exec("ALTER TABLE runtime_sessions DROP COLUMN runtime");
  db.close();
  store = open(path);
  store.setSessionRuntime("old", "codex", "cx", false, null, null, null, null);
  assert.deepEqual(store.runtimeSessionSources("old"), [{ id: "earlier", runtime: "claude", profile: "cc" }]);
  assert.equal(store.sessionOfRuntime("claude", "earlier")?.key, "old");
  assert.equal(store.sessionOfRuntime("codex", "earlier"), null);
  store.close();
  store = open(path);
  assert.equal(store.runtimeSessionSources("old")[0]!.runtime, "claude");
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
  assert.equal(store.statsOf(["same-ms"]).get("same-ms")!.lastTurn!.outcome, "completed");
  assert.equal(store.stopWait("same-ms", true), false, "stopping an allowance wait does not change an older turn");
  store.startTurn("third", "same-ms", "resume");
  store.endTurn("third", "failed", "rate_limit: quota", null, null);
  store.db.exec("UPDATE turns SET started_at = 123 WHERE session_key = 'same-ms'");
  assert.equal(store.stopWait("same-ms", true), true);
  assert.equal(store.lastTurn("same-ms")!.outcome, "aborted");
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
    assert.equal(messages[0]!.agentIdentity.runtime, "claude");
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
  assert.deepEqual(h.changes, [{ type: "session", key: "a" }, { type: "thread", id: t2.id, entries: [], closed: k }]);
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

test("a card stops waiting as a person writes, a newer card comes, its agent withdraws it or someone closes it: each said once", () => {
  const store = memory();
  session(store, "a");
  const thread = store.openThread("slack", "C1", "1.1", null, null);
  const h = heard(store);
  const ended = () => h.changes.splice(0).flatMap((c) => cardsEnded(store, c)).map((e) => [e.message.ts, e.end]);
  const options = { type: "options", options: [{ label: "合并", action: "close" }, { label: "先不" }] };
  store.insertMessage({ ...newMessage(thread.id, "1.2", "agent", "a", "合并吗？"), card: options });
  assert.deepEqual(ended(), [], "a first card replaces nothing");
  say(store, thread.id, "1.3", "person", "U1", "再想想");
  assert.deepEqual(ended(), [["1.2", { why: "message", by: "U1", byTs: "1.3" }]]);
  say(store, thread.id, "1.4", "person", "U2", "还有");
  assert.deepEqual(ended(), [], "only the first message after it closes it");
  store.insertMessage({ ...newMessage(thread.id, "1.5", "agent", "a", "那这样？"), card: options });
  store.insertMessage({ ...newMessage(thread.id, "1.6", "agent", "a", "还是这样？"), card: { type: "text" } });
  assert.deepEqual(ended(), [["1.5", { why: "replaced" }]]);
  assert.equal(store.withdrawCard("a", thread.id, "1.6"), true);
  assert.deepEqual(ended(), [["1.6", { why: "withdrawn" }]]);
  store.insertMessage({ ...newMessage(thread.id, "1.7", "agent", "a", "那就？"), card: options });
  assert.deepEqual(ended(), [], "one withdrawn before it is not replaced again");
  assert.equal(store.closeCard("local", thread.id, store.messageAt(thread.id, "1.7")!.n, "合并"), true);
  assert.deepEqual(ended(), [["1.7", { why: "closed" }]]);
  say(store, thread.id, "1.8", "person", "U1", "好");
  assert.deepEqual(ended(), [], "one closed is not closed again by a message");
  store.insertMessage({ ...newMessage(thread.id, "1.9", "agent", "a", "最后？"), card: options });
  say(store, thread.id, "1.10", "person", "U1", "嗯");
  assert.deepEqual(ended().map(([, e]) => (e as CardEnd).why), ["message"]);
  assert.equal(store.withdrawCard("a", thread.id, "1.9"), true);
  assert.equal(store.withdrawCard("a", thread.id, "1.9"), true);
  assert.deepEqual(ended(), [], "one answered and withdrawn after keeps its answer");
  h.stop();
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
  assert.deepEqual([...store.heardThreads("a", [thread.id, 999])], [thread.id]);
  store.markUndelivered("a", [{ thread: thread.id, n, apart: false }]);
  assert.equal(store.pendingMessages("a").length, 1);
  assert.deepEqual([...store.heardThreads("a", [thread.id])], []);
});

// On ccvm (2026-11-03) a session's detail read its 378 jobs, each with its notices and its log looked at.
test("jobs: a session's detail as a device asks it lists its latest and those still up, by indexes", async () => {
  const store = memory();
  session(store, "a");
  const job = (i: number, over: Partial<JobRow> = {}): JobRow => ({
    id: `j${i}`, sessionKey: "a", name: `job ${i}`, command: "make", cwd: "/w/a", port: null, token: `t${i}`, state: "exited", pgid: null,
    exitCode: 0, startedAt: 10 + i, endedAt: 20 + i, restarts: 0, log: `/w/a/j${i}.log`, watch: false, ...over,
  });
  // The first a service still up, the second running: both from long ago; then 60 over.
  store.insertJob(job(0, { port: 4000 }));
  store.insertJob(job(1, { state: "running", endedAt: null, exitCode: null }));
  for (let i = 2; i < 62; i++) store.insertJob(job(i));
  const { session: detail } = await import("../src/read/sessions.ts");
  const viewer: Viewer = { sub: "u", email: "a@x", name: "A", role: "owner", workspace: "ws", device: "d", home: true };
  const r = read.makeStore(store.db, tempdir());
  const ids = (now: boolean) => detail(r, "a", viewer, "en", 0, now).jobs.map((j: any) => j.id);
  const latest = Array.from({ length: read.JOBS_NOW }, (_, k) => `j${61 - k}`);
  assert.deepEqual(ids(true), [...latest, "j1", "j0"], "the latest, newest first, then the old ones still up");
  assert.equal(ids(false).length, 62, "all of them, as a device from before asks");
  for (const [sql, args] of [[read.LATEST_JOBS, ["a", 5]], [read.UP_JOBS_OF, ["a"]]] as const) {
    const plan = (store.db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...args) as { detail: string }[]).map((p) => p.detail);
    assert.ok(plan.every((d) => !/^SCAN jobs/.test(d)) && !plan.some((d) => d.includes("TEMP B-TREE")), plan.join(" | "));
  }
});

test("what is written of a chat beside what is said in it is told as written: archive review, shares, chats opened from it", () => {
  const store = memory();
  session(store, "a");
  const h = heard(store);
  store.suggestArchive("a", 7, 12);
  store.setArchiveVerdict("a", 7, 12, { picked: "archive" });
  store.clearArchiveSuggestion("a", 7);
  store.setChatShare("a", [{ workspace: "w2", name: "Two" }], true, "a@x");
  store.insertOpened({ childStation: "", child: "b", parentStation: "", parent: "a", key: "k", title: "子对话", link: null, openerTitle: null });
  h.stop();
  const marks = h.changes.filter((c) => c.type === "chatMark").map(({ type: _, ...m }: any) => m);
  assert.deepEqual(marks.map((m: any) => m.opened ? { ...m, opened: { ...m.opened, createdAt: 0 } } : m), [
    { thread: 7, session: "a", archive: { suggested: 12 } },
    { thread: 7, session: "a", archive: { verdict: { picked: "archive" } } },
    { thread: 7, session: "a", archive: { suggested: null } },
    { thread: null, session: "a", share: { to: [{ workspace: "w2", name: "Two" }], write: true } },
    { thread: null, session: "a", opened: { childStation: "", child: "b", parent: "a", title: "子对话", openerTitle: null, createdAt: 0 } },
  ]);
});

// On ccvm (2026-11-03) the archive was made whole at once: its 1,398 chats in 60 s, every other read of devices waiting.
test("the archive a page at a time, the latest archived first, each by the index of those archived; the sidebar by those shown", async () => {
  const time = testClock();
  await time.adjust(Date.parse("2026-11-03T00:00:00Z"));
  const store = Store.open(":memory:", null, time.clock);
  stores.push(store);
  for (const key of ["a", "b", "c", "d", "e"]) session(store, key);
  for (const key of ["b", "d", "a", "e"]) {
    await time.adjust(1000);
    store.setArchived(key, true, MANUAL);
  }
  const r = read.makeStore(store.db, tempdir());
  const pages: string[][] = [];
  let before: [number, string] = [Number.MAX_SAFE_INTEGER, "\uffff"];
  for (;;) {
    const page = read.archivedPage(r, before, 3);
    pages.push(page.map((i) => i.id));
    if (page.length < 3) break;
    before = [page.at(-1)!.at, page.at(-1)!.id];
  }
  assert.deepEqual(pages.flat().filter((id) => !/^\d+$/.test(id)), ["e", "a", "d", "b"], "each once, the latest archived first");
  assert.deepEqual(read.shownSessions(r).map((x) => x.key), ["c"]);
  for (const [sql, args] of [[read.ARCHIVED_PAGE, [Number.MAX_SAFE_INTEGER, "\uffff", 3]], [read.SHOWN_SESSIONS, []]] as const) {
    const plan = (store.db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...args) as { detail: string }[]).map((p) => p.detail);
    assert.ok(!plan.some((d) => /^SCAN (sessions|threads)\b/.test(d) && !d.includes("INDEX sessions_live")), plan.join(" | "));
  }
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
  const detail = detailQuery(1n, 1_000_001n, 1n, { workspace: "ws", home: false })!;
  // As the station's SQLite (node's) plans each: a scan only of an index that holds the sessions shown or running, the
  // login cards, or of the small one that counts sessions (or of what a subquery found); a table, or an index of every
  // turn, job or entry, never.
  const planned: [string, unknown[]][] = [
    [read.ORIGINAL_RUNTIME, ["a"]],
    [ACTIVE_SESSIONS, [0]], [LIVE_SESSIONS, []], [ANY_RUNNING, []], [RUNNING_SESSIONS, []], [JOBS_RUNNING, []], [JOBS_UP, []], [SESSION_JOBS, ["a"]],
    [STATS_OF, ["a"]], [SESSION_COUNTS, []], [LATEST_DECISIONS, [0]], [CLOSED_SINCE, [0]], [CLOSED_THREAD_SINCE, [1, 0]], [LOGIN_CARDS, ["%l1%"]], [CARD_BEFORE, [1, 9]], [OPTIONS_BEFORE, [1, 9]],
    [TURNS_FROM, ["a", 0]], [TURNS_BETWEEN, ["a", 0, 9]], [TAKEN_SINCE, ["a", "ember", 0]], [SESSION_OF_RUNTIME, ["claude", "r1"]], [SAID_SINCE, [1, 0]],
    [HEARD_IN, ["a", 1]], [MODELS_USED_BY, ["a@x", 0]], [REMOTE_RUNS_OF, ["ws", 0]], [REMOTE_RUNS_ALL, [0]],
    [detail.sql, detail.args], [read.USAGE_DETAIL_DAY_SCOPED, [1n, "ws"]],
  ];
  const scans = /^SCAN (?!CONSTANT ROW$|parts$|\(subquery-\d+\)$|\w+ USING (?:COVERING )?INDEX (?:sessions_live|sessions_running|sessions_by_connect|entries_login_cards)\b)/;
  const plans = new Map<string, string[]>();
  for (const [sql, args] of planned) {
    const plan = (store.db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...(args as never[])) as { detail: string }[]).map((r) => r.detail);
    // The detail query materializes only keys sought inside the requested range, then scans those keys in session
    // order. It must still seek the underlying lookup below (asserted separately), not scan the historical table.
    assert.ok(!plan.some((d) => scans.test(d)
      && !(sql === detail.sql && d === "SCAN target" && plan.includes("MATERIALIZE targets"))
      && !(sql === read.USAGE_DETAIL_DAY_SCOPED && d === "SCAN e" && (plan.includes("MATERIALIZE edge") || plan.includes("CO-ROUTINE edge")))
      && !(sql === read.USAGE_DETAIL_DAY_SCOPED && d === "SCAN p" && plan.includes("CO-ROUTINE parts"))), `${sql}\n  ${plan.join(" | ")}`);
    plans.set(sql, plan);
  }
  // A session's messages not delivered yet: by the index of those alone, not every message it was ever given; and its
  // turns not counted (auto-archiving read each shown session's every delivery and turn so: 13 s and 22 s on ccvm).
  assert.ok(plans.get(STATS_OF)!.some((d) => d.includes("deliveries_pending (session=?)")), plans.get(STATS_OF)!.join(" | "));
  assert.ok(!plans.get(STATS_OF)!.some((d) => d.includes("COVERING INDEX turns_by_session")), plans.get(STATS_OF)!.join(" | "));
  // Whether a session heard from a thread: by its deliveries there alone, not every message it was ever given (3.3 s on
  // the main thread on ccvm); the models someone's chats ran on from the index alone.
  assert.ok(plans.get(HEARD_IN)!.some((d) => d.includes("deliveries_session (session=? AND thread=?)")), plans.get(HEARD_IN)!.join(" | "));
  assert.ok(plans.get(MODELS_USED_BY)!.some((d) => d.includes("COVERING INDEX sessions_models (created_by=? AND created_at>?)")), plans.get(MODELS_USED_BY)!.join(" | "));
  assert.ok(plans.get(REMOTE_RUNS_OF)!.some((d) => d.includes("PRIMARY KEY (ws=? AND at>?)")), plans.get(REMOTE_RUNS_OF)!.join(" | "));
  assert.ok(plans.get(REMOTE_RUNS_ALL)!.some((d) => d.includes("PRIMARY KEY (at>?)")), plans.get(REMOTE_RUNS_ALL)!.join(" | "));
  assert.ok(plans.get(detail.sql)!.some((d) => d.includes("usage_detail_lookup_scope (scope=? AND level=? AND bucket>? AND bucket<?)")), plans.get(detail.sql)!.join(" | "));
  assert.ok(plans.get(read.USAGE_DETAIL_DAY_SCOPED)!.some((d) => d.includes("usage_detail_scope_ws (ws=?)")), plans.get(read.USAGE_DETAIL_DAY_SCOPED)!.join(" | "));
  assert.ok(plans.get(read.USAGE_DETAIL_DAY_SCOPED)!.some((d) => d.includes("PRIMARY KEY (session=? AND level=? AND bucket>? AND bucket<?)")), plans.get(read.USAGE_DETAIL_DAY_SCOPED)!.join(" | "));
  // The latest card before a message: by the index of cards, not by going back over the thread to it.
  assert.ok(plans.get(CARD_BEFORE)!.some((d) => d.includes("entries_cards")), plans.get(CARD_BEFORE)!.join(" | "));
  assert.ok(plans.get(OPTIONS_BEFORE)!.some((d) => d.includes("entries_options")), plans.get(OPTIONS_BEFORE)!.join(" | "));
  assert.ok(plans.get(SAID_SINCE)!.some((d) => d.includes("entries_people_since (thread=? AND at>?)")), plans.get(SAID_SINCE)!.join(" | "));
  assert.ok(plans.get(CLOSED_THREAD_SINCE)!.some((d) => d.includes("closed_cards_thread_at (thread=? AND at>?)")), plans.get(CLOSED_THREAD_SINCE)!.join(" | "));
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
  assert.deepEqual(stats.get("a"), { pending: 0, lastTurn: stats.get("a")!.lastTurn });
  assert.equal(stats.get("a")!.lastTurn?.kind, "input");
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

test("what is told as chats change is planned by the size of what it finds, not by a chat's or a session's history", () => {
  const store = memory();
  // As node's SQLite plans each, over the file the readers read: a chat's unread messages counted from the index of its
  // messages alone; an agent's message during a turn by the index of theirs by time; a session's turns as counted, its
  // undelivered messages by the index of those alone, its latest turn by its index; the Slack threads a chat copies to,
  // by their last entry; and of the items a change touched, or of a chat, their own shares, openers and snapshots. Each
  // as it was read every message of a chat, every turn or delivery of a session, or every row of its table: a notice of
  // a chat of 534 messages read 479 pages, 3 to 16 s on ccvm short of memory (2026-11-02), every telling after it waiting.
  const planned: [string, unknown[]][] = [
    [read.UNREAD, [1, 0, "[]"]], [read.ASKED_DURING, [1, 0, 9]], [`${read.SESSION_STATS} WHERE s.key = ?`, ["a"]], [read.LAST_TURN, ["a"]], [read.LATEST_TURNS, ["a", 1]], [CC_THREADS_SQL, [1]],
    [read.SHARES_OF, ['["a"]']], [read.OPENERS_OF, ['["a"]']], [read.OPENED_OF, ['["a"]']], [read.PUBLISHED_OF, ["[1]"]],
    [`${read.SEEN_OF} WHERE key IN (SELECT value FROM json_each(?))`, ['["a"]']], [read.TOLD_BLOCKED, ["a", 0, 9]], [read.RUNNING_OF, ['["a"]']],
  ];
  const scans = /^SCAN (?!CONSTANT ROW$|\(subquery-\d+\)$|json_each VIRTUAL TABLE\b)/;
  const plans = new Map<string, string[]>();
  for (const [sql, args] of planned) {
    const plan = (store.db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...(args as never[])) as { detail: string }[]).map((r) => r.detail);
    assert.ok(!plan.some((d) => scans.test(d)), `${sql}\n  ${plan.join(" | ")}`);
    plans.set(sql, plan);
  }
  const has = (sql: string, step: string) => assert.ok(plans.get(sql)!.some((d) => d.includes(step)), `${step}\n  ${plans.get(sql)!.join(" | ")}`);
  const lacks = (sql: string, step: string) => assert.ok(!plans.get(sql)!.some((d) => d.includes(step)), `${step}\n  ${plans.get(sql)!.join(" | ")}`);
  has(read.UNREAD, "COVERING INDEX entries_said (thread=? AND n>?)");
  has(read.ASKED_DURING, "entries_agent_at (thread=? AND at>? AND at<?)");
  const stats = `${read.SESSION_STATS} WHERE s.key = ?`;
  has(stats, "c USING PRIMARY KEY (session=?)");
  has(stats, "w USING PRIMARY KEY (session=?)");
  // Whether a turn of it ended before its work was kept: its first by its end, from the index alone.
  has(stats, "o USING COVERING INDEX turns_by_end (session_key=?");
  has(stats, "deliveries_pending (session=?)");
  lacks(stats, "COVERING INDEX turns_by_session");
  lacks(stats, "deliveries_session");
  has(read.LAST_TURN, "turns_by_session (session_key=?)");
  // A session's latest turns by the index of its turns, from its end: not every turn read and sorted.
  has(read.LATEST_TURNS, "turns_by_session (session_key=?)");
  lacks(read.LATEST_TURNS, "TEMP B-TREE");
  has(CC_THREADS_SQL, "e USING INDEX sqlite_autoindex_entries_1 (thread=? AND n=?)");
  lacks(CC_THREADS_SQL, "e USING INDEX sqlite_autoindex_entries_1 (thread=?)");
  has(read.SHARES_OF, "chat_shares USING INDEX sqlite_autoindex_chat_shares_1 (session=?)");
  has(read.OPENERS_OF, "o USING INDEX sqlite_autoindex_opened_chats_1 (child_station=? AND child=?)");
  has(read.OPENED_OF, "o USING INDEX opened_chats_by_key (parent_station=? AND parent=?)");
  has(read.PUBLISHED_OF, "published USING INDEX published_by_thread (thread=?)");
  has(read.TOLD_BLOCKED, "turns_by_end (session_key=? AND ended_at>? AND ended_at<?)");
  // The jobs running of some sessions: by an index (of those running, or of their sessions' jobs), never every job.
  has(read.RUNNING_OF, "SEARCH jobs USING INDEX");
  // Which workspace each session is in (each usage read's, for every session it names, and for every one there is):
  // from the index of them alone, not the sessions themselves.
  has(`${read.SEEN_OF} WHERE key IN (SELECT value FROM json_each(?))`, "SEARCH sessions USING COVERING INDEX sessions_ws (key=?)");
  assert.deepEqual((store.db.prepare(`EXPLAIN QUERY PLAN ${read.SEEN_OF}`).all() as { detail: string }[]).map((r) => r.detail), ["SCAN sessions USING COVERING INDEX sessions_ws"]);
});

test("a session's turns are counted as they are written and removed, and once from those before", () => {
  const path = join(tempdir(), "stillfail.db");
  let store = open(path);
  session(store, "a");
  session(store, "b");
  store.startTurn("t1", "a", "input");
  store.startTurn("t2", "a", "input");
  store.startTurn("t3", "b", "input");
  const turns = (s: Store) => {
    const r = read.makeStore(s.db, tempdir());
    return Object.fromEntries([...read.sessionStats(r, null)].map(([key, stats]) => [key, stats.turns]));
  };
  assert.deepEqual(turns(store), { a: 2, b: 1 });
  store.deleteSession("b");
  assert.deepEqual(turns(store), { a: 2 });
  assert.deepEqual(store.db.prepare("SELECT session, n FROM session_turns").all().map((r: any) => [r.session, r.n]), [["a", 2]]);
  // A database from before the count: made from the turns it has, as it opens.
  store.db.exec("DROP TRIGGER session_turns_add; DROP TRIGGER session_turns_drop; DROP TABLE session_turns;");
  store.startTurn("t4", "a", "input");
  store.close();
  store = open(path);
  assert.deepEqual(turns(store), { a: 3 });
});

// On ccvm (2026-11-03) a device read a session with its every turn (3,685 of them, 25 s) to add up how long they ran.
test("a session's work is kept as its turns end and go, from when it began to be kept; one with turns ended before says none", async () => {
  const time = testClock();
  await time.adjust(Date.parse("2026-11-03T00:00:00Z"));
  const path = join(tempdir(), "stillfail.db");
  const opened = () => {
    const s = Store.open(path, null, time.clock);
    stores.push(s);
    return s;
  };
  let store = opened();
  session(store, "a");
  session(store, "b");
  const MIN = 60_000;
  const work = (s: Store) => Object.fromEntries([...read.sessionStats(read.makeStore(s.db, tempdir()), null)].map(([key, stats]) => [key, stats.workMs]));
  await time.adjust(MIN);
  store.startTurn("t1", "a", "input");
  await time.adjust(5 * MIN);
  store.endTurn("t1", "completed", null, null, null);
  store.startTurn("t2", "a", "input");
  await time.adjust(2 * MIN);
  store.startTurn("t3", "b", "input");
  assert.deepEqual(work(store), { a: 5 * MIN, b: 0 }, "a turn running is not counted yet");
  store.endTurn("t2", "completed", null, null, null);
  assert.deepEqual(work(store), { a: 7 * MIN, b: 0 });
  // Its detail without its turns, as a device asks it (`?turns=0`); all of them as one from before does.
  const { session: detail } = await import("../src/read/sessions.ts");
  const viewer: Viewer = { sub: "u", email: "a@x", name: "A", role: "owner", workspace: "ws", device: "d", home: true };
  const r = read.makeStore(store.db, tempdir());
  assert.deepEqual(detail(r, "a", viewer, "en", 0).turns, []);
  assert.deepEqual(detail(r, "a", viewer, "en").turns.map((t: any) => t.id), ["t1", "t2"]);
  assert.deepEqual([detail(r, "a", viewer, "en", 0).session.turns, detail(r, "a", viewer, "en", 0).session.workMs], [2, 7 * MIN]);
  // A database from before the work was kept: nothing added up from its turns as it opens, and a session with a turn
  // ended by then says none; one whose turns all end after, its work.
  store.db.exec("DROP TRIGGER session_work_add; DROP TRIGGER session_work_end; DROP TRIGGER session_work_drop; DROP TABLE session_work; DROP TABLE session_work_from;");
  await time.adjust(MIN);
  store.endTurn("t3", "completed", null, null, null);
  store.close();
  await time.adjust(MIN);
  store = opened();
  assert.equal((store.db.prepare("SELECT COUNT(*) AS n FROM session_work").get() as { n: number }).n, 0, "none read from the turns before");
  session(store, "c");
  store.startTurn("t4", "c", "input");
  await time.adjust(3 * MIN);
  store.endTurn("t4", "completed", null, null, null);
  store.startTurn("t5", "a", "input");
  await time.adjust(MIN);
  store.endTurn("t5", "completed", null, null, null);
  assert.deepEqual(work(store), { a: null, b: null, c: 3 * MIN });
  // Gone with the session's turns.
  store.deleteSession("c");
  assert.deepEqual(store.db.prepare("SELECT session, ms FROM session_work ORDER BY session").all().map((x: any) => [x.session, x.ms]), [["a", MIN]]);
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
  store.usageChanged(["a"], 1000);
  assert.deepEqual(h.changes, [{ type: "usage", sessions: ["a"] }, { type: "usage", sessions: ["a"], from: 1000 }]);
  h.stop();
});

test("usage: a missing old session total does not reconstruct calls and new writes are kept apart", () => {
  const path = join(tempdir(), "usage.db");
  const of = { turn: null, person: null, thread: null, profile: null };
  const call = (id: string, model: string | null, output: number) => ({ id, at: 1000, model, subagent: false, fast: false, input: 1, cacheRead: 2, cacheWrite: 3, cacheWriteLong: 4, output, calls: 1, context: 10, window: null });
  const first = open(path);
  session(first, "a");
  first.recordUsage("/a.jsonl", { session: "a", offset: 1, model: "m" }, "claude", [[call("c1", "m", 5), of], [call("c2", null, 1), of]]);
  first.close();
  // A database from before the totals: old calls remain untouched as it is opened.
  const before = new DatabaseSync(path);
  before.exec("DROP TRIGGER usage_totals_add; DROP TRIGGER usage_totals_grow; DROP TRIGGER usage_totals_drop; DROP TABLE usage_totals;");
  before.close();
  const store = open(path);
  // A call's output grown, a new call, and one recorded by a station process from before the totals.
  store.recordUsage("/a.jsonl", { session: "a", offset: 2, model: "m" }, "claude", [[call("c1", "m", 9), of], [call("c3", "m", 2), of]]);
  const older = new DatabaseSync(path);
  older.exec("INSERT INTO usage (id, at, session, runtime, model, input, cache_read, cache_write, cache_write_long, output) VALUES ('c4', 1000, 'a', 'claude', 'm', 1, 2, 3, 4, 7)");
  older.close();
  assert.deepEqual(store.usageOfSession("a"), [], "a partial session total is not shown as a lifetime total");
  assert.deepEqual(store.db.prepare("SELECT runtime, model, calls, input, cache_read, cache_write, cache_write_long, output FROM usage_totals WHERE session = 'a'")
    .all().map((r) => [r.runtime, r.model, r.calls, r.input, r.cache_read, r.cache_write, r.cache_write_long, r.output]),
  [["claude", "m", 2, 2, 4, 6, 8, 9]], "only new calls contribute to the incremental total");
  assert.deepEqual(store.usageOfSession("b"), []);
});

test("usage: the page's days are the calls added up from statistics, whatever the range and time zone", () => {
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
  // The current detail index remains usable if the obsolete quarter table is absent on an older database.
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
  const fromStats = (from: number, to: number, tz: number) => {
    const query = detailQuery(BigInt(from), BigInt(to), BigInt(tz), null);
    return query === null ? [] : store.db.prepare(query.sql).all(...query.args);
  };
  const some = fromStats(day + 5 * 900_000 + 7, day * 3 - 11, 480).length;
  assert.ok(some > 100, `${some} groups`);
  const q = 900_000;
  const ranges = [[0, 2 ** 62], [day + 5 * q, day * 3], [day + 5 * q + 7, day * 3 - 11], [day * 2 + 3, day * 2 + 400], [day * 2, day * 2 + q], [day * 3 + 1, day * 2], [-5, day + q + 1]];
  for (const [from, to] of ranges) {
    for (const tz of [0, 480, -300, 330, 345, 7, -1]) {
      const kept = fromStats(from!, to!, tz);
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
  const detailObjects = before.prepare("SELECT type, name FROM sqlite_master WHERE (name LIKE 'usage_detail_%' OR name = 'usage_detail') AND type IN ('trigger', 'table') ORDER BY type DESC").all() as { type: string; name: string }[];
  for (const object of detailObjects) before.exec(`DROP ${object.type.toUpperCase()} "${object.name}"`);
  before.exec(`DROP TRIGGER usage_totals_add; DROP TRIGGER usage_totals_drop; DROP TRIGGER usage_compactions_add;
    DROP TRIGGER usage_main_calls_usage_drop; DROP TRIGGER usage_main_calls_usage_change; DROP TRIGGER usage_main_calls_add; DROP TRIGGER usage_main_calls_drop;
    DROP TABLE usage_main_calls; DROP TABLE usage_compaction_events; DROP TABLE usage_compaction_backfill;
    DROP TRIGGER usage_quarters_add; DROP TRIGGER usage_quarters_drop; DROP TRIGGER usage_quarters_grow; DROP TABLE usage_quarters;
    DROP TRIGGER usage_minute_add; DROP TRIGGER usage_minute_drop; DROP TRIGGER usage_minute_grow;
    DROP TRIGGER usage_minute_session_add; DROP TRIGGER usage_minute_session_move; DROP TRIGGER usage_minute_session_drop;
    DROP TABLE usage_minute; DROP TABLE usage_day_quarters; DROP TABLE usage_minute_scope; DROP TABLE usage_minute_sessions; DROP TABLE usage_minute_seen; DROP TABLE usage_minute_all;
    ALTER TABLE usage DROP COLUMN calls; ALTER TABLE usage DROP COLUMN context; ALTER TABLE usage DROP COLUMN context_window;
    CREATE TRIGGER usage_totals_add AFTER INSERT ON usage BEGIN
      INSERT INTO usage_totals VALUES (NEW.session, NEW.runtime, COALESCE(NEW.model, ''), NEW.fast, 1, NEW.input, NEW.cache_read, NEW.cache_write, NEW.cache_write_long, NEW.output)
      ON CONFLICT (session, runtime, model, fast) DO UPDATE SET calls = calls + 1, input = input + excluded.input;
    END;
    CREATE TRIGGER usage_totals_drop AFTER DELETE ON usage BEGIN UPDATE usage_totals SET calls = calls - 1 WHERE session = OLD.session; END;
    CREATE TRIGGER usage_compactions_add AFTER INSERT ON usage BEGIN SELECT 1; END;`);
  before.close();
  store = open(path);
  // The old call remains intact; an unfinished context index does not claim it is complete.
  assert.deepEqual(store.db.prepare("SELECT context, context_window FROM usage WHERE id = 'c1'").get(),
    Object.assign(Object.create(null), { context: null, context_window: null }));
  assert.deepEqual(store.lastContexts("a", 5), []);
  // A turn told at once is its calls; the context it ended with is what it says, compacted from the one before.
  store.recordUsage("/a.jsonl", { session: "a", offset: 2, model: "m" }, "claude", [call("c2", 2000, 300_000, { calls: 3, context: 20_000, window: 200_000 })] as never);
  assert.deepEqual(store.usageOfSession("a").map((g) => [g.calls, g.input]), [[5, 420_007]]);
  assert.deepEqual(store.usageGroups(0, 3000, 0).map((g) => [g.calls, g.input]), [[3, 300_000]],
    "the new detail starts with the call recorded after the upgrade");
  assert.deepEqual(store.lastContexts("a", 1), []);
  assert.deepEqual([...store.compactionPoints(0)], []);
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

test("a session's starter: whom its chat was started for, before anyone wrote in it (a chat an agent opened)", () => {
  const store = memory();
  store.insertSession({ key: "opened", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w/opened", token: "opened", createdAt: 1, lastActiveAt: 1, createdBy: "Pat@Example.com" });
  const thread = store.openThread("ember", "EMBER", "3.1", null, "Pat@Example.com");
  store.joinThread(thread.id, "opened", "ember");
  say(store, thread.id, "3.2", "agent", "opened", "开始");
  assert.equal(store.starter("opened"), "pat@example.com", "started for Pat, though only its agent has written");
  // A session of before createdBy was kept: the first person who wrote in it.
  session(store, "older");
  const older = store.openThread("ember", "EMBER", "4.1", null, null);
  store.joinThread(older.id, "older", "ember");
  say(store, older.id, "4.2", "person", "Bob@x.com", "hi");
  assert.equal(store.starter("older"), "bob@x.com");
  session(store, "nobody");
  assert.equal(store.starter("nobody"), null);
});
