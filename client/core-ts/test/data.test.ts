// The core's data (docs/core-db.md): a SQLite database per signed-in account (db/account.ts, db/schema.ts), reached
// through Data (data.ts). What it promises: real tables, written row by row and only where something changed, by one
// writer committing a burst at once and saying what it changed; lists loaded only when read, kept current from then
// on; versions and migrations; what a newer core wrote only read; no room left said, and what was done here kept; what
// the device kept before brought over once (the former records, the Rust core's chunks).
import assert from "node:assert/strict";
import { test } from "node:test";
import { DatabaseSync } from "node:sqlite";
import { Data, dbName, type RowChange } from "../src/data.ts";
import { CHUNK, importFormer } from "../src/db/import.ts";
import { placesFor } from "../src/db/account.ts";
import { VERSION } from "../src/db/schema.ts";
import { type Sql, type SqlRow, type SqlValue, SqlError } from "../src/host.ts";
import { NodeSql } from "../src/hosts/node-sql.ts";
import type { Topic } from "../src/protocol.ts";
import { Runner } from "../src/runtime.ts";
import { FakeHost, flush } from "../src/testing.ts";
import { run } from "./run.ts";

// deno-lint-ignore no-explicit-any
type J = any;

const rows = (station: string): Topic => ({ topic: "chatRows", station });
const threads = (station: string): Topic => ({ topic: "threads", station });
const sessions = (station: string): Topic => ({ topic: "sessions", station });
const overview = (station: string): Topic => ({ topic: "overview", station });

/// A database that counts what is asked of it (and can be made to fail).
class Counted implements Sql {
  readonly inner: NodeSql;
  statements: string[] = [];
  /// What fails, by the start of its SQL (a full disk).
  failing: ((sql: string) => SqlError | null) | null = null;
  constructor(inner: NodeSql) {
    this.inner = inner;
  }
  #fail(sql: string): void {
    const e = this.failing?.(sql);
    if (e) throw e;
  }
  exec(sql: string): void {
    this.statements.push(sql);
    this.#fail(sql);
    this.inner.exec(sql);
  }
  run(sql: string, params?: readonly SqlValue[]): number {
    this.statements.push(sql);
    this.#fail(sql);
    return this.inner.run(sql, params);
  }
  all(sql: string, params?: readonly SqlValue[]): SqlRow[] {
    return this.inner.all(sql, params);
  }
  close(): void {}
  writes(): string[] {
    return this.statements.filter((s) => /^(INSERT|UPDATE|DELETE)/.test(s));
  }
  commits(): number {
    return this.statements.filter((s) => s === "COMMIT").length;
  }
}

/// A host whose accounts' databases are counted; owners as given (account → its workspaces).
function fresh(owners: Record<string, string[]> = { s1: ["w", "w1", "w2"] }) {
  const host = new FakeHost();
  const counted = new Map<string, Counted>();
  host.openDbHook = (name) => {
    let c = counted.get(name);
    if (!c) {
      const sql = new NodeSql(new DatabaseSync(":memory:"), true);
      host.sqls.set(name, sql);
      c = new Counted(sql);
      counted.set(name, c);
    }
    return c;
  };
  const runner = new Runner(host.time.clock);
  const owner = (ws: string) => Object.entries(owners).find(([, list]) => list.includes(ws))?.[0] ?? null;
  const data = new Data(host, runner, { owner });
  const told: Topic[] = [];
  data.onChange((t) => told.push(t));
  // Opened: every topic may have changed ("*"); what a test hears is what comes after.
  const open = async (subs = Object.keys(owners)) => {
    await run(data.open(subs));
    told.length = 0;
  };
  const db = (sub = "s1") => counted.get(dbName(sub))!;
  const again = async () => {
    const d = new Data(host, runner, { owner });
    await run(d.open(Object.keys(owners)));
    return d;
  };
  return { host, runner, data, told, open, db, again, counted };
}

test("each_account_has_its_own_database_made_at_the_current_version", async () => {
  const { host, data, open, db, runner } = fresh({ s1: ["w1"], s2: ["w2"] });
  await open();
  assert.deepEqual([...host.sqls.keys()].sort(), [dbName("s1"), dbName("s2")]);
  assert.equal(db("s1").all("PRAGMA user_version")[0][0], VERSION);
  // A station's is kept by the account that reaches its workspace, and only there.
  data.set(rows("w1/a"), [{ id: "x" }]);
  data.set(rows("w2/b"), [{ id: "y" }]);
  data.set(rows("w3/c"), [{ id: "z" }]);
  await run(data.written);
  assert.deepEqual(db("s1").all("SELECT station, id FROM chat"), [["w1/a", "x"]]);
  assert.deepEqual(db("s2").all("SELECT station, id FROM chat"), [["w2/b", "y"]]);
  assert.equal(data.get(rows("w3/c")), undefined, "a workspace no account reaches keeps nothing");
  // Signing out removes the account's database.
  await run(data.accounts(["s1"]));
  assert.deepEqual([...host.sqls.keys()], [dbName("s1")]);
  assert.equal(data.get(rows("w2/b")), undefined);
  assert.deepEqual(data.get(rows("w1/a")), [{ id: "x" }]);
  runner.shutdown();
});

test("dbs_are_named_by_their_account_whatever_it_holds", () => {
  assert.equal(dbName("google-oauth2|123"), "account-google-oauth2_7c123");
  assert.equal(dbName("a/b.c"), "account-a_2fb_2ec");
});

test("a_database_a_newer_core_wrote_is_only_read_and_says_so", async () => {
  const { host, runner } = fresh();
  const sql = new NodeSql(new DatabaseSync(":memory:"), true);
  sql.exec("PRAGMA user_version = 99; CREATE TABLE workspace (id TEXT PRIMARY KEY, json TEXT NOT NULL, confirmed INTEGER); INSERT INTO workspace VALUES ('w', '{\"id\":\"w\",\"name\":\"新\"}', 1);");
  host.openDbHook = () => sql;
  const data = new Data(host, runner, { owner: () => "s1" });
  let noted = 0;
  data.onNote = () => noted++;
  await run(data.open(["s1"]));
  assert.deepEqual(data.get({ topic: "workspace", workspace: "w" }), { id: "w", name: "新" });
  assert.deepEqual([...data.notes.values()], [{ kind: "newer", detail: null }]);
  assert.equal(noted, 1);
  data.set({ topic: "workspace", workspace: "w" }, { id: "w", name: "旧" });
  await run(data.written);
  assert.deepEqual(data.get({ topic: "workspace", workspace: "w" }), { id: "w", name: "新" }, "nothing is written");
  assert.equal(sql.all("PRAGMA user_version")[0][0], 99);
  runner.shutdown();
});

test("a_database_another_process_holds_is_one_in_memory_this_run_and_says_so", async () => {
  const { host, runner } = fresh();
  host.openDbHook = () => new SqlError("database is locked", "busy");
  host.memoryDb = () => new NodeSql(new DatabaseSync(":memory:"));
  const data = new Data(host, runner, { owner: () => "s1" });
  await run(data.open(["s1"]));
  assert.deepEqual([...data.notes.values()].map((n) => n.kind), ["busy"]);
  data.set(rows("w/a"), [{ id: "x" }]);
  assert.deepEqual(data.get(rows("w/a")), [{ id: "x" }], "it works this run");
  runner.shutdown();
});

test("a_burst_of_writes_is_one_transaction_and_tells_once_it_is_committed", async () => {
  const { data, told, open, db, runner } = fresh();
  await open();
  const before = db().commits();
  data.set(rows("w/a"), [{ id: "x", n: 1 }]);
  data.set(overview("w/a"), { connects: [] });
  data.putChat("w/a", { id: "y", n: 1 });
  // Read at once, before it is committed.
  assert.deepEqual(data.get(rows("w/a")), [{ id: "x", n: 1 }, { id: "y", n: 1 }]);
  assert.equal(told.length, 0, "told once committed");
  await flush();
  assert.equal(db().commits() - before, 1, "one transaction");
  assert.deepEqual(told.map((t) => t.topic).sort(), ["chatRows", "overview"]);
  runner.shutdown();
});

test("a_list_read_again_writes_only_the_rows_that_changed", async () => {
  const { data, open, db, runner } = fresh();
  await open();
  const list = Array.from({ length: 50 }, (_, i) => ({ id: `c${i}`, title: `第 ${i} 个`, lastActiveAt: 1000 - i }));
  data.set(rows("w/a"), list);
  await run(data.written);
  let writes = db().writes().length;
  // The same again: nothing written but when it was confirmed.
  data.set(rows("w/a"), list.map((r) => ({ ...r })));
  await run(data.written);
  assert.deepEqual(db().writes().slice(writes).map((s) => s.split(" ").slice(0, 3).join(" ")), ["INSERT INTO list"]);
  writes = db().writes().length;
  // A new chat on top and one changed: those two rows, and nothing else, though every row moved down.
  data.set(rows("w/a"), [{ id: "new", title: "新", lastActiveAt: 2000 }, ...list.map((r, i) => (i === 7 ? { ...r, title: "改了" } : r))]);
  await run(data.written);
  assert.equal(db().writes().slice(writes).filter((s) => s.startsWith("INSERT OR REPLACE INTO chat")).length, 2);
  assert.deepEqual(
    (data.get(rows("w/a")) as J[]).slice(0, 3).map((r: J) => r.id),
    ["new", "c0", "c1"],
    "in the order the station gave",
  );
  // Gone from the list: deleted.
  data.set(rows("w/a"), [{ id: "new", title: "新", lastActiveAt: 2000 }]);
  await run(data.written);
  assert.deepEqual(db().all("SELECT id FROM chat"), [["new"]]);
  // Read and empty is known; never read is not.
  data.set(rows("w/a"), []);
  assert.deepEqual(data.get(rows("w/a")), []);
  assert.equal(data.get(rows("w/b")), undefined);
  runner.shutdown();
});

test("places_keep_the_rows_already_in_order_where_they_are", () => {
  assert.deepEqual(placesFor([null, null, null]), [0, 1, 2]);
  assert.deepEqual(placesFor([null, 0, 1, 2]), [-1, 0, 1, 2]);
  assert.deepEqual(placesFor([0, 2, 1]), [0, 0.5, 1], "the one moved goes between its neighbours");
  const moved = placesFor([0, 3, 1, 2]);
  assert.ok(moved[0] < moved[1] && moved[1] < moved[2] && moved[2] < moved[3]);
  assert.deepEqual([moved[0], moved[2], moved[3]], [0, 1, 2], "the run kept in order stays");
});

test("a_list_is_loaded_when_read_and_kept_current_by_the_writer", async () => {
  const { data, open, runner } = fresh();
  await open();
  data.set(rows("w/a"), [{ id: "x", n: 1 }, { id: "y", n: 1 }]);
  await run(data.written);
  data.release(rows("w/a"));
  assert.equal(data.loaded(rows("w/a")), false, "not loaded until read");
  const first = data.shared(rows("w/a")) as J[];
  assert.equal(data.loaded(rows("w/a")), true);
  assert.ok(Object.isFrozen(first[0]));
  data.putChat("w/a", { id: "y", n: 2 });
  const next = data.shared(rows("w/a")) as J[];
  assert.equal(next[0], first[0], "a row that did not change is the same object");
  assert.notEqual(next[1], first[1]);
  assert.deepEqual(next[1], { id: "y", n: 2 });
  data.release(rows("w/a"));
  assert.equal(data.loaded(rows("w/a")), false);
  assert.deepEqual(data.get(rows("w/a")), [{ id: "x", n: 1 }, { id: "y", n: 2 }]);
  runner.shutdown();
});

test("what_it_holds_is_there_after_a_restart", async () => {
  const { data, open, again, runner } = fresh();
  await open();
  data.set(rows("w/s"), [{ id: "b", title: "二" }, { id: "a", title: "一" }]);
  data.set(overview("w/s"), { connects: [] });
  await run(data.written);
  const later = await again();
  // The order the station gave is kept.
  assert.deepEqual(later.get(rows("w/s")), [{ id: "b", title: "二" }, { id: "a", title: "一" }]);
  assert.deepEqual(later.get(overview("w/s")), { connects: [] });
  runner.shutdown();
});

test("a_read_position_is_updated_in_place_and_the_rows_follow", async () => {
  const { data, open, db, runner } = fresh();
  await open();
  data.set(threads("w/a"), [{ id: 7, last: 10, read: 4, unread: 6, sessions: [{ session: "k1" }], lastMessage: { createdAt: 5 } }]);
  data.set(rows("w/a"), [{ id: "k1", session: "k1", thread: 7, unread: true, mine: true, last: { seq: 10 } }]);
  data.set({ topic: "session", station: "w/a", key: "k1" }, { session: { key: "k1", turns: 0 }, turns: [], jobs: [], threads: [] });
  await run(data.written);
  const writes = db().writes().length;
  assert.equal(data.setRead("w/a", 7, 8), true, "something is still unread: the count is read again");
  await run(data.written);
  assert.deepEqual(db().writes().slice(writes).map((s) => s.split(" ").slice(0, 2).join(" ")), ["UPDATE thread"], "the thread's columns only");
  assert.equal((data.get(threads("w/a")) as J)[0].read, 8);
  assert.equal(data.setRead("w/a", 7, 10), false);
  const thread = (data.get(threads("w/a")) as J)[0];
  assert.deepEqual([thread.read, thread.unread], [10, 0]);
  assert.equal((data.get(rows("w/a")) as J)[0].unread, false);
  // The session's detail shows its threads as they are now.
  assert.equal((data.get({ topic: "session", station: "w/a", key: "k1" }) as J).threads[0].read, 10);
  runner.shutdown();
});

test("a_sessions_detail_holds_its_threads_as_their_rows_are", async () => {
  const { data, open, runner } = fresh();
  await open();
  data.set(sessions("w/a"), [{ key: "k1", turns: 1 }]);
  data.set({ topic: "session", station: "w/a", key: "k1" }, { session: { key: "k1", turns: 1 }, turns: [{ kind: "chat" }], jobs: [], threads: [{ id: 9, sessions: [{ session: "k1" }], title: "旧" }] });
  data.putThread("w/a", { id: 9, sessions: [{ session: "k1" }], title: "新" });
  const detail = data.get({ topic: "session", station: "w/a", key: "k1" }) as J;
  assert.equal(detail.threads[0].title, "新");
  assert.equal(detail.session.key, "k1");
  // A session gone takes its threads that had no one else with it.
  data.dropSession("w/a", "k1");
  assert.equal(data.get({ topic: "session", station: "w/a", key: "k1" }), undefined);
  assert.equal(data.thread("w/a", 9), undefined);
  assert.deepEqual(data.get(sessions("w/a")), []);
  runner.shutdown();
});

test("a_session_event_says_whether_its_detail_is_to_be_read_again", async () => {
  const { data, open, runner } = fresh();
  await open();
  data.set(sessions("w/a"), [{ key: "k1", turns: 0, lastTurn: null }]);
  assert.equal(data.putSummary("w/a", { key: "k1", turns: 0, lastTurn: null }), true, "no detail held");
  data.set({ topic: "session", station: "w/a", key: "k1" }, { session: { key: "k1", turns: 0, lastTurn: null }, turns: [], jobs: [], threads: [] });
  assert.equal(data.putSummary("w/a", { key: "k1", turns: 0, lastTurn: null, title: "x" }), false);
  assert.equal(data.putSummary("w/a", { key: "k1", turns: 1, lastTurn: { kind: "chat" } }), true);
  // New ones come first; archived ones leave the list.
  data.putSummary("w/a", { key: "k2", turns: 0 });
  assert.deepEqual((data.get(sessions("w/a")) as J[]).map((s) => s.key), ["k2", "k1"]);
  data.putSummary("w/a", { key: "k1", turns: 1, archivedAt: 5 });
  assert.deepEqual((data.get(sessions("w/a")) as J[]).map((s) => s.key), ["k2"]);
  assert.equal((data.get({ topic: "session", station: "w/a", key: "k1" }) as J).session.archivedAt, 5);
  runner.shutdown();
});

test("a_burst_says_each_chat_row_before_and_after", async () => {
  const { data, open, runner } = fresh();
  await open();
  const heard: [string, RowChange[], boolean][] = [];
  data.onChats((station, changes, first) => heard.push([station, changes, first]));
  data.set(rows("w/a"), [{ id: "x", n: 1 }]);
  await flush();
  assert.deepEqual(heard, [["w/a", [{ id: "x", before: undefined, after: { id: "x", n: 1 } }], true]]);
  heard.length = 0;
  data.putChat("w/a", { id: "x", n: 2 });
  data.putChat("w/a", { id: "x", n: 3 });
  data.dropChat("w/a", "nothing");
  await flush();
  assert.deepEqual(heard, [["w/a", [{ id: "x", before: { id: "x", n: 1 }, after: { id: "x", n: 3 } }], false]]);
  runner.shutdown();
});

test("the_rows_that_ask_something_and_the_first_screen_are_found_by_their_columns", async () => {
  const { host, runner } = fresh();
  const data = new Data(host, runner, { owner: () => "s1", derive: { tone: (r) => (r.unread === true && r.mine === true ? "done" : null), asks: (r) => r.decision !== undefined } });
  await run(data.open(["s1"]));
  data.set(rows("w/a"), [
    { id: "old", lastActiveAt: 1 },
    { id: "pinned", lastActiveAt: 0, pinned: 50 },
    { id: "new", lastActiveAt: 9 },
    { id: "unread", lastActiveAt: 5, unread: true, mine: true },
    { id: "asks", lastActiveAt: 4, decision: { seq: 1 } },
  ]);
  data.set(rows("w/b"), [{ id: "b", lastActiveAt: 7 }]);
  assert.deepEqual(data.chatHead(["w/a", "w/b"], 3).map(([s, r]) => `${s} ${r.id}`), ["w/a pinned", "w/a new", "w/b b"]);
  assert.deepEqual(data.marked(["w/a"]).map(([, r]) => r.id).sort(), ["asks", "unread"]);
  data.setRead("w/a", 0, 0);
  data.putChat("w/a", { id: "unread", lastActiveAt: 5, unread: false, mine: true });
  assert.deepEqual(data.marked(["w/a"]).map(([, r]) => r.id), ["asks"]);
  runner.shutdown();
});

test("a_logs_items_are_written_once_and_read_by_range", async () => {
  const { data, open, db, runner } = fresh();
  await open();
  const logs: string[] = [];
  data.onLogChange((table, station, id) => logs.push(`${table} ${station} ${id}`));
  data.putItems("entry", "w/a", "7", Array.from({ length: 100 }, (_, i) => [i + 1, { n: i + 1 }]));
  await flush();
  assert.deepEqual(logs, ["entry w/a 7"]);
  const writes = db().writes().length;
  data.putItems("entry", "w/a", "7", [[50, { n: 50 }], [101, { n: 101 }]]);
  await flush();
  assert.equal(db().writes().length - writes, 1, "the one not held");
  assert.deepEqual(data.logSpan("entry", "w/a", "7"), { min: 1, max: 101, count: 101 });
  assert.deepEqual([...data.logRange("entry", "w/a", "7", 99, 200).keys()], [99, 100, 101]);
  assert.equal(data.logCount("entry", "w/a", "7", 1, 10), 10);
  // A transcript written anew from before its end is cut there.
  data.putItems("transcript", "w/a", "k1", [[0, { a: 1 }], [1, { a: 2 }], [2, { a: 3 }]]);
  data.putItems("transcript", "w/a", "k1", [[1, { a: 9 }]], 1);
  assert.deepEqual([...data.logRange("transcript", "w/a", "k1", 0, 10).values()], [{ a: 1 }, { a: 9 }]);
  data.dropThread("w/a", 7);
  assert.equal(data.logSpan("entry", "w/a", "7"), null);
  runner.shutdown();
});

test("what_is_kept_of_each_chat_is_counted_and_forgotten", async () => {
  const { data, open, runner } = fresh();
  await open();
  data.putThread("w/a", { id: 7, title: "大视频", sessions: [{ session: "k1" }] });
  data.putItems("entry", "w/a", "7", [[1, { text: "x".repeat(100) }], [2, { text: "y" }]]);
  data.putItems("transcript", "w/a", "k1", [[0, { a: "z".repeat(50) }]]);
  data.putItems("entry", "w/a", "8", [[1, { text: "other" }]]);
  await flush();
  const usage = data.cacheUsage().sort((a, b) => a.thread - b.thread);
  assert.deepEqual(usage.map((u) => [u.thread, u.title, u.sessions]), [[7, "大视频", ["k1"]], [8, null, []]]);
  assert.ok(usage[0]!.bytes > 150, "its entries and its session's transcript");
  data.forgetChat("w/a", 7);
  await flush();
  assert.equal(data.logSpan("entry", "w/a", "7"), null);
  assert.equal(data.logSpan("transcript", "w/a", "k1"), null);
  assert.deepEqual(data.cacheUsage().map((u) => u.thread), [8]);
  runner.shutdown();
});

test("a_full_disk_is_said_and_what_was_done_here_is_kept", async () => {
  const { data, open, db, runner } = fresh();
  await open();
  data.set(rows("w/a"), [{ id: "x" }]);
  await run(data.written);
  // The disk is full for one burst.
  let full = true;
  db().failing = (sql) => {
    if (sql !== "COMMIT" || !full) return null;
    full = false;
    return new SqlError("database or disk is full", "full");
  };
  data.set(rows("w/a"), [{ id: "x" }, { id: "y" }]);
  data.putLocal("outbox", "w/a", "7", [{ id: "out-1", text: "你好" }]);
  await flush();
  assert.deepEqual([...data.notes.values()].map((n) => n.kind), ["full"]);
  assert.deepEqual(data.get(rows("w/a")), [{ id: "x" }], "what came from the station waits for it again");
  db().failing = null;
  // What was done here was written on its own.
  assert.deepEqual(data.locals("outbox").map(([s, k, v]) => [s, k, (v as J)[0].text]), [["w/a", "7", "你好"]]);
  data.set(rows("w/a"), [{ id: "x" }, { id: "y" }]);
  await flush();
  assert.deepEqual(data.notes.size, 0, "room again: no longer said");
  assert.deepEqual(data.get(rows("w/a")), [{ id: "x" }, { id: "y" }]);
  runner.shutdown();
});

test("retain_forgets_the_stations_no_one_reaches", async () => {
  const { data, open, db, runner } = fresh({ s1: ["w1", "w2"] });
  await open();
  data.set(rows("w1/s"), [{ id: "a" }]);
  data.set(rows("w2/s"), [{ id: "a" }]);
  data.set({ topic: "workspace", workspace: "w2" }, { id: "w2" });
  data.putItems("entry", "w2/s", "7", [[1, { n: 1 }]]);
  data.putItems("entry", "w1/s", "7", [[1, { n: 1 }]]);
  await run(data.written);
  data.retain((s) => s.startsWith("w1/"), new Set(["w1"]));
  await run(data.written);
  assert.deepEqual(db().all("SELECT DISTINCT station FROM chat"), [["w1/s"]]);
  assert.deepEqual(db().all("SELECT DISTINCT station FROM entry"), [["w1/s"]]);
  assert.deepEqual(db().all("SELECT id FROM workspace"), []);
  runner.shutdown();
});

test("what_was_said_is_found_by_its_words_as_its_entries_change", async () => {
  const { data, open, db, runner, again } = fresh();
  await open();
  const said = (n: number, text: string, at = n) => [n, { n, kind: "message", text, at }] as [number, J];
  const found = (d: Data, ...words: string[]) => d.findSaid(["w/a", "w/b"], words, 10).map((f) => `${f.station} ${f.thread} ${f.seq} ${f.text}`);
  data.putItems("entry", "w/a", "7", [said(1, "排查登录很慢"), said(2, "Deploy the LOGIN page"), [3, { n: 3, kind: "edit", target: 1, text: "排查注册很慢", at: 9 }]]);
  data.putItems("entry", "w/b", "8", [said(1, "登录好了", 5)]);
  data.putItems("entry", "w/c", "9", [said(1, "登录别处的")]);
  data.set(rows("w/c"), [{ id: "z" }]);
  await run(data.written);
  // The edit's words are the message's; newest first; only the stations asked about.
  assert.deepEqual(found(data, "登录"), ["w/b 8 1 登录好了"]);
  assert.deepEqual(found(data, "注册"), ["w/a 7 1 排查注册很慢"]);
  // Case aside, every word, through the index (three or more) and without it (shorter).
  assert.deepEqual(found(data, "login", "de"), ["w/a 7 2 Deploy the LOGIN page"]);
  assert.deepEqual(found(data, "login", "zz"), []);
  // An edit read before its message (older pages come later) keeps its words.
  data.putItems("entry", "w/b", "10", [[5, { n: 5, kind: "edit", target: 4, text: "新的说法", at: 6 }]]);
  data.putItems("entry", "w/b", "10", [said(4, "旧的说法", 4)]);
  await run(data.written);
  assert.deepEqual(found(data, "说法"), ["w/b 10 4 新的说法"]);
  assert.deepEqual(db().all("SELECT at FROM said WHERE thread = 10"), [[4]]);
  // A thread cut: the words of what went go with it, a message whose edit went has its own again.
  data.putItems("entry", "w/a", "7", [], 1);
  await run(data.written);
  assert.deepEqual(found(data, "login"), []);
  assert.deepEqual(found(data, "排查"), ["w/a 7 1 排查登录很慢"]);
  // A thread dropped, a station forgotten: all its words go.
  data.dropThread("w/b", 8);
  data.retain((s) => s !== "w/c", null);
  await run(data.written);
  assert.deepEqual(found(data, "登录"), ["w/a 7 1 排查登录很慢"]);
  assert.deepEqual(db().all("SELECT station, thread, seq FROM said ORDER BY station, thread, seq"), [["w/a", 7, 1], ["w/b", 10, 4]]);
  // A database from before (none of it) has it filled from the entries held when opened.
  db().exec("DROP TRIGGER said_put; DROP TRIGGER said_drop; DROP TABLE said_index; DROP TABLE said;");
  const d = await again();
  assert.deepEqual(found(d, "说法"), ["w/b 10 4 新的说法"]);
  assert.deepEqual(found(d, "排查"), ["w/a 7 1 排查登录很慢"]);
  runner.shutdown();
});

test("without_full_text_search_what_was_said_is_scanned", async () => {
  const { host, runner } = fresh();
  const inner = new NodeSql(new DatabaseSync(":memory:"), true);
  // A build without FTS5.
  const sql: Sql = {
    exec: (q) => {
      if (/fts5/i.test(q)) throw new SqlError("no such module: fts5", "other");
      inner.exec(q);
    },
    run: (q, p) => inner.run(q, p),
    all: (q, p) => inner.all(q, p),
    close: () => {},
  };
  host.openDbHook = () => sql;
  const data = new Data(host, runner, { owner: () => "s1" });
  await run(data.open(["s1"]));
  data.putItems("entry", "w/a", "7", [[1, { n: 1, kind: "message", text: "登录流程太慢", at: 1 }]]);
  await run(data.written);
  assert.deepEqual(data.findSaid(["w/a"], ["登录流程"], 5).map((f) => f.seq), [1]);
  assert.deepEqual(inner.all("SELECT name FROM sqlite_master WHERE name LIKE 'said_index%'"), []);
  runner.shutdown();
});

test("past_its_room_the_logs_least_recently_used_go_transcripts_first_and_come_back_when_opened", async () => {
  const host = new FakeHost();
  const runner = new Runner(host.time.clock);
  const sql = new NodeSql(new DatabaseSync(":memory:"), true);
  host.openDbHook = () => sql;
  const data = new Data(host, runner, { owner: () => "s1", kept: 1024 * 1024 });
  await run(data.open(["s1"]));
  const big = "字".repeat(2000);
  const said = (thread: number) => Array.from({ length: 20 }, (_, i) => [i + 1, { n: i + 1, kind: "message", text: `${thread} ${big}`, at: i }] as [number, J]);
  // Two transcripts and eight threads, thread 1 the least recently used; thread 2 shown.
  data.putItems("transcript", "w/a", "k1", [[0, { text: big }], [1, { text: big }]]);
  data.putItems("transcript", "w/a", "k2", [[0, { text: big }]]);
  await run(data.written);
  data.opened("entry", "w/a", "2", true);
  for (let t = 1; t <= 8; t++) {
    host.advance(60_000);
    data.putItems("entry", "w/a", String(t), said(t));
    await run(data.written);
  }
  await run(data.written);
  const db = data.db("s1")!;
  assert.ok(db.used() <= 1024 * 1024, `${db.used()}`);
  // The transcripts went first; then the threads least recently used, not the one shown.
  assert.deepEqual(sql.all("SELECT count(*) FROM transcript"), [[0]]);
  const kept = sql.all("SELECT DISTINCT thread FROM entry ORDER BY thread").map((r) => r[0]);
  assert.ok(kept.includes(2) && kept.includes(8) && !kept.includes(1), JSON.stringify(kept));
  assert.equal(data.evicted("entry", "w/a", "1"), true);
  assert.equal(data.evicted("transcript", "w/a", "k1"), true);
  assert.equal(data.evicted("entry", "w/a", "2"), false);
  // What was said in it goes with it.
  assert.deepEqual(data.findSaid(["w/a"], ["1 字字字"], 5), []);
  // Opened again: kept, and said to be brought back; let go no more after a restart either.
  assert.equal(data.opened("entry", "w/a", "1", true), true);
  assert.equal(data.evicted("entry", "w/a", "1"), false);
  await run(data.written);
  assert.deepEqual(sql.all("SELECT evicted FROM log_use WHERE kind = 'entry' AND id = '1'"), [[0]]);
  assert.deepEqual(sql.all("SELECT count(*) FROM log_use WHERE evicted = 1 AND kind = 'transcript'"), [[2]]);
  runner.shutdown();
});

test("model_selection_survives_old_events_and_finishes_without_reverting", async () => {
  const { data, open, again, runner } = fresh();
  await open();
  const topic = overview("w/s");
  data.set(topic, { profiles: [{ id: "p", models: ["a"] }] });
  assert.ok(data.beginModels("w/s", "p", ["a", "b"]));
  assert.ok(!data.beginModels("w/s", "p", []));
  data.update(topic, (o) => ({ ...(o as J), name: "event while saving" }));
  assert.deepEqual((data.get(topic) as J).profiles[0].models, ["a"]);
  assert.deepEqual((data.shown(topic) as J).profiles[0].models, ["a", "b"]);
  assert.deepEqual((data.shown(topic) as J).profiles[0].modelsSaving, ["b"]);
  await run(data.written);
  const restart = await again();
  assert.deepEqual((restart.shown(topic) as J).profiles[0].models, ["a"]);
  data.set(topic, { profiles: [{ id: "p", models: ["a", "b"] }] });
  assert.deepEqual((data.shown(topic) as J).profiles[0].modelsSaving, ["b"]);
  data.endModels("w/s", "p");
  assert.deepEqual((data.shown(topic) as J).profiles[0].models, ["a", "b"]);
  assert.equal((data.shown(topic) as J).profiles[0].modelsSaving, undefined);
  runner.shutdown();
});

test("an_update_changes_what_is_known_only", async () => {
  const { data, open, runner } = fresh();
  await open();
  const topic = overview("w/s");
  data.update(topic, (v) => ({ ...(v as J), x: 1 }));
  assert.equal(data.get(topic), undefined);
  data.set(topic, { x: 0 });
  data.update(topic, (v) => ({ ...(v as J), x: 1 }));
  assert.deepEqual(data.get(topic), { x: 1 });
  assert.throws(() => data.update(rows("w/s"), (v) => v), /row by row/);
  runner.shutdown();
});

test("a_draft_is_there_at_once_and_written_after_its_last_change", async () => {
  const { host, data, open, db, runner } = fresh();
  await open();
  const topic = { topic: "draft", station: "w/s", chat: "new" };
  data.setSoon(topic, { text: "你" });
  data.setSoon(topic, { text: "你好" });
  assert.deepEqual(data.get(topic), { text: "你好" });
  assert.deepEqual(db().all("SELECT json FROM draft"), []);
  await host.time.pass(400);
  assert.deepEqual(db().all("SELECT json FROM draft"), [['{"text":"你好"}']]);
  data.forgetTopic(topic);
  await run(data.written);
  assert.deepEqual(db().all("SELECT json FROM draft"), []);
  runner.shutdown();
});

test("the_devices_values_are_its_own_not_an_accounts", async () => {
  const { host, data, open, again, runner } = fresh();
  await open();
  data.set({ topic: "prefs" }, { appearance: "dark" });
  data.put("choice", "last", "w/s");
  data.put("choice", "ws:w:last", "s");
  await host.time.pass(10);
  assert.ok(host.storage.has("device/prefs"));
  const later = await again();
  assert.deepEqual(later.get({ topic: "prefs" }), { appearance: "dark" });
  assert.equal(later.record("choice", "last"), "w/s");
  assert.equal(later.record("choice", "ws:w:last"), "s", "a workspace's picks are in its account's database");
  await run(later.accounts([]));
  assert.equal(later.record("choice", "ws:w:last"), undefined);
  assert.deepEqual(later.get({ topic: "prefs" }), { appearance: "dark" }, "signing out leaves the device's");
  runner.shutdown();
});

// ── what the device kept before ──

const entry = (n: number) => ({ thread: 7, n, kind: "message", text: `m${n}` });

/// The former records store as the core before this one left it (data.ts then: one record per row, `list` the ids).
function formerRecords(host: FakeHost) {
  const put = (table: string, key: string, value: unknown) => host.legacyPut(table, key, value);
  put("me", "s1", { workspaces: [{ id: "w1" }], relay_url: "https://relay" });
  put("me", "s2", { workspaces: [{ id: "w1" }, { id: "w2" }] });
  put("workspace", "w1", { id: "w1", stations: [{ id: "a" }] });
  put("workspace", "w2", { id: "w2", stations: [{ id: "b" }] });
  put("overview", "w1/a", { connects: [] });
  put("list", "row\u0001w1/a", ["k2", "k1"]);
  put("row", "w1/a\u0001k1", { id: "k1", thread: 7, title: "一" });
  put("row", "w1/a\u0001k2", { id: "k2", title: "二" });
  put("list", "thread\u0001w1/a", [7]);
  put("thread", "w1/a\u00017", { id: 7, last: 3, read: 1, sessions: [{ session: "k1" }] });
  put("session", "w1/a\u0001k1", { session: { key: "k1" }, turns: [], jobs: [], threads: [] });
  put("entry", "w1/a\u00017\u0001000000000001", entry(1));
  put("entry", "w1/a\u00017\u0001000000000002", entry(2));
  put("transcript", "w1/a\u0001k1\u0001000000000000", { kind: "user" });
  put("outbox", "w1/a\u00017", [{ id: "out-3", text: "还没发出去", state: "sending" }]);
  put("draft", "w1/a\u0001new", { text: "写了一半" });
  put("choice", "ws:w1:last", "a");
  put("choice", "last", "w1/a");
  put("prefs", "device", { appearance: "dark" });
  put("confirmed", "list\u0001row\u0001w1/a", 1234);
  put("row", "w2/b\u0001z", { id: "z" });
  put("list", "row\u0001w2/b", ["z"]);
}

test("what_the_former_records_held_comes_over_once_each_account_taking_its_own", async () => {
  const { host, runner, counted } = fresh({ s1: ["w1"], s2: ["w2"] });
  formerRecords(host);
  const owners: Record<string, string> = { w1: "s1", w2: "s2" };
  const data = new Data(host, runner, { owner: (ws) => owners[ws] ?? null });
  data.onOpened = (db) => importFormer(host, runner, data, ["s1", "s2"], db);
  await run(data.open(["s1", "s2"]));
  await host.time.pass(50);
  await run(data.written);
  // s1 signed in first: w1 is its, with all of it; s2 has its own and w2.
  assert.deepEqual((data.get(rows("w1/a")) as J[]).map((r) => r.id), ["k2", "k1"]);
  assert.deepEqual(data.get(overview("w1/a")), { connects: [] });
  assert.equal((data.thread("w1/a", 7) as J).read, 1);
  assert.deepEqual([...data.logRange("entry", "w1/a", "7", 1, 9).values()], [entry(1), entry(2)]);
  assert.deepEqual([...data.logRange("transcript", "w1/a", "k1", 0, 9).values()], [{ kind: "user" }]);
  assert.deepEqual(data.get({ topic: "draft", station: "w1/a", chat: "new" }), { text: "写了一半" });
  assert.deepEqual(data.locals("outbox").map(([s, k]) => `${s} ${k}`), ["w1/a 7"]);
  assert.equal(data.record("choice", "ws:w1:last"), "a");
  assert.equal(data.record("choice", "last"), "w1/a");
  assert.deepEqual(data.get({ topic: "prefs" }), { appearance: "dark" });
  assert.deepEqual(data.get(rows("w2/b")), [{ id: "z" }]);
  assert.deepEqual(counted.get(dbName("s1"))!.all("SELECT station FROM chat GROUP BY station"), [["w1/a"]]);
  assert.deepEqual(counted.get(dbName("s2"))!.all("SELECT station FROM chat GROUP BY station"), [["w2/b"]]);
  assert.equal(counted.get(dbName("s1"))!.all("SELECT confirmed FROM list WHERE list = 'chats'")[0][0], 1234);
  // Left where it was (an older core still finds it); not brought again.
  assert.ok(host.db.size > 0);
  data.dropChat("w1/a", "k2");
  await run(data.written);
  const later = new Data(host, runner, { owner: (ws) => owners[ws] ?? null });
  later.onOpened = (db) => importFormer(host, runner, later, ["s1", "s2"], db);
  await run(later.open(["s1", "s2"]));
  await host.time.pass(50);
  assert.deepEqual((later.get(rows("w1/a")) as J[]).map((r) => r.id), ["k1"]);
  runner.shutdown();
});

function rustKept(host: FakeHost) {
  // Thread 7 of `w1/a` holds 250 ..= 300: chunk 0 (entries 1..=256) from 250, chunk 1 to 300.
  const put = (k: string, v: unknown) => host.storage.set(k, new TextEncoder().encode(JSON.stringify(v)));
  put("kept", {
    "thread/w1/a/7": { station: "w1/a", opened: 1, chunks: { 0: 10, 1: 10 } },
    "transcript/w1/a/k1": { station: "w1/a", opened: 1, chunks: { 0: 10 } },
    "thread/w1/a/8": { station: "w1/a", opened: 1, chunks: { 0: 10 } },
  });
  put("thread/w1/a/7/meta", { first: 250, last: 300 });
  put("thread/w1/a/7/0", Array.from({ length: CHUNK - 250 + 1 }, (_, i) => entry(250 + i)));
  put("thread/w1/a/7/1", Array.from({ length: 300 - 257 + 1 }, (_, i) => entry(257 + i)));
  put("transcript/w1/a/k1/meta", { first: 0, last: 2 });
  put("transcript/w1/a/k1/0", [{ kind: "user" }, { kind: "assistant" }, { kind: "result" }]);
  // A chunk out of place (an entry not where the meta says): not read.
  put("thread/w1/a/8/meta", { first: 1, last: 2 });
  put("thread/w1/a/8/0", [entry(1), entry(5)]);
}

test("what_the_rust_core_kept_in_chunks_comes_over_once", async () => {
  const { host, runner } = fresh({ s1: ["w1"] });
  host.legacyPut("me", "s1", { workspaces: [{ id: "w1" }] });
  rustKept(host);
  const data = new Data(host, runner, { owner: () => "s1" });
  data.onOpened = (db) => importFormer(host, runner, data, ["s1"], db);
  await run(data.open(["s1"]));
  await host.time.pass(50);
  assert.equal(data.logSpan("entry", "w1/a", "7")?.count, 51);
  assert.deepEqual(data.logRange("entry", "w1/a", "7", 250, 250).get(250), entry(250));
  assert.deepEqual(data.logRange("entry", "w1/a", "7", 300, 300).get(300), entry(300));
  assert.deepEqual([...data.logRange("transcript", "w1/a", "k1", 0, 9).keys()], [0, 1, 2]);
  assert.equal(data.logSpan("entry", "w1/a", "8"), null);
  assert.ok(host.storage.has("thread/w1/a/7/0"), "left as it was");
  runner.shutdown();
});

test("a_core_answers_its_first_view_from_the_database_before_any_network", async () => {
  const { Core } = await import("../src/core.ts");
  const { STORAGE_KEY } = await import("../src/accounts.ts");
  const { account, nowS, subscribe } = await import("./helpers.ts");
  const host = new FakeHost();
  host.store(STORAGE_KEY, [account("s1", "a@x.com", "", "tok", "r0", nowS() + 3600)]);
  // What an earlier run kept: the account's workspace and a station's chats.
  const sql = new NodeSql(new DatabaseSync(":memory:"), true);
  host.sqls.set(dbName("s1"), sql);
  const runner = new Runner(host.time.clock);
  const seed = new Data(host, runner, { owner: () => "s1" });
  await run(seed.open(["s1"]));
  seed.put("me", "s1", { workspaces: [{ id: "ws", name: "W" }], relay_url: null });
  seed.set({ topic: "workspace", workspace: "ws" }, { id: "ws", stations: [{ id: "st", name: "studio", online: true }] });
  seed.set(rows("ws/st"), [{ id: "k1", session: "k1", title: "上次的对话", lastActiveAt: host.nowMs(), agents: [], mine: true, unread: false, last: null }]);
  await run(seed.written);
  runner.shutdown();
  // No network at all.
  host.onFetch(() => new Promise(() => {}));
  const core = await Core.create(host, { clock: host.time.clock });
  subscribe(core, 1, 1, { topic: "chats", scope: "ws", mine: false });
  await flush();
  const said = host.takeEmitted().map(([, m]) => m as J);
  const first = said.find((m) => m.id === 1 && "value" in m);
  assert.ok(first, `answered at once: ${JSON.stringify(said).slice(0, 500)}`);
  assert.deepEqual(first.value.days.flatMap((d: J) => d.items.map((i: J) => i.title)), ["上次的对话"]);
  core.close();
});
