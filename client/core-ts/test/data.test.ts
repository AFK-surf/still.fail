// The core's data (docs/core-db.md): a SQLite database per signed-in account (db/account.ts, db/schema.ts), reached
// through Data (data.ts). What it promises: real tables, written row by row and only where something changed, by one
// writer committing a burst at once and saying what it changed; lists loaded only when read, kept current from then
// on; versions and migrations; what a newer core wrote only read; no room left said, and what was done here kept; what
// the device kept before brought over once (the former records, the Rust core's chunks).
import assert from "node:assert/strict";
import { test } from "node:test";
import { existsSync, mkdtempSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
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
  reads: string[] = [];
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
    this.reads.push(sql);
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

/// A host whose databases can be damaged: every statement on one marked damaged, but those `readable` lets through,
/// fails as SQLite's SQLITE_CORRUPT does.
function damageable() {
  const host = new FakeHost();
  const damaged = new Map<NodeSql, (sql: string) => boolean>();
  host.openDbHook = (name) => {
    let inner = host.sqls.get(name);
    if (!inner) {
      inner = new NodeSql(new DatabaseSync(":memory:"), true);
      host.sqls.set(name, inner);
    }
    const sql = inner;
    const check = (q: string) => {
      const readable = damaged.get(sql);
      if (readable && !readable(q)) throw new SqlError("SQLITE_CORRUPT: sqlite3 result code 11: database disk image is malformed", "corrupt");
    };
    return {
      exec: (q) => (check(q), sql.exec(q)),
      run: (q, p) => (check(q), sql.run(q, p)),
      all: (q, p) => (check(q), sql.all(q, p)),
      close: () => {},
    } satisfies Sql;
  };
  const runner = new Runner(host.time.clock);
  const damage = (sub: string, readable: (sql: string) => boolean) => damaged.set(host.sqls.get(dbName(sub))!, readable);
  return { host, runner, damage };
}

test("a_database_damaged_as_it_is_opened_is_made_again_with_what_was_done_here", async () => {
  const { host, runner, damage } = damageable();
  const data = new Data(host, runner, { owner: () => "s1" });
  await run(data.open(["s1"]));
  data.set(rows("w/a"), [{ id: "x" }]);
  data.putLocal("outbox", "w/a", "7", [{ id: "out-1", text: "你好" }]);
  data.putLocal("pending", "w/a", "k1", { text: "新对话" });
  await run(data.written);
  // Only the outbox still reads.
  damage("s1", (q) => /^SELECT .* FROM outbox$/.test(q));
  const before = host.sqls.get(dbName("s1"));
  const next = new Data(host, runner, { owner: () => "s1" });
  await run(next.open(["s1"]));
  assert.notEqual(host.sqls.get(dbName("s1")), before, "a new file");
  assert.deepEqual([...next.notes.values()], [], "nothing to say: it works");
  assert.deepEqual(next.locals("outbox").map(([s, k, v]) => [s, k, (v as J)[0].text]), [["w/a", "7", "你好"]], "what was done here, as far as it read");
  assert.deepEqual(next.locals("pending"), [], "what did not read is lost with the file");
  assert.equal(next.get(rows("w/a")), undefined, "what the station sent comes again from it");
  assert.deepEqual(host.reported.map((e) => e.name), ["LocalDbMadeAgain"]);
  assert.match(host.reported[0]!.message, /malformed.*1 rows/);
  // Made again, it is no import's: what the device kept before was brought into the damaged one.
  assert.deepEqual(host.rows(dbName("s1"), "SELECT value FROM meta WHERE key = 'imported'"), [["made again"]]);
  next.putLocal("outbox", "w/a", "8", [{ id: "out-2", text: "再见" }]);
  await run(next.written);
  assert.equal(next.locals("outbox").length, 2, "and it is written");
  runner.shutdown();
});

test("a_database_found_damaged_as_the_core_runs_is_marked_and_made_again_as_it_next_opens", async () => {
  const { host, runner, damage } = damageable();
  const data = new Data(host, runner, { owner: () => "s1" });
  await run(data.open(["s1"]));
  data.set(rows("w/a"), [{ id: "x" }]);
  data.putLocal("outbox", "w/a", "7", [{ id: "out-1", text: "你好" }]);
  await run(data.written);
  data.release(rows("w/a"));
  // A page of the chats is damaged: its read fails (the core ends on it), and the database is marked first.
  damage("s1", (q) => !/FROM chat\b/.test(q));
  assert.throws(() => data.get(rows("w/a")), /malformed/);
  await data.damageKept();
  assert.ok(host.storage.has(`db-damaged/${dbName("s1")}`));
  assert.equal(host.reported.length, 0, "nothing to report yet: it is made again as it next opens");
  // The core that follows.
  const next = new Data(host, runner, { owner: () => "s1" });
  await run(next.open(["s1"]));
  assert.deepEqual(next.locals("outbox").map(([, k]) => k), ["7"]);
  assert.equal(next.get(rows("w/a")), undefined);
  assert.ok(!host.storage.has(`db-damaged/${dbName("s1")}`), "the mark goes with it");
  assert.deepEqual(host.reported.map((e) => e.name), ["LocalDbMadeAgain"]);
  // Opened again: nothing more is made again.
  const third = new Data(host, runner, { owner: () => "s1" });
  await run(third.open(["s1"]));
  assert.deepEqual(third.locals("outbox").map(([, k]) => k), ["7"]);
  assert.equal(host.reported.length, 1);
  runner.shutdown();
});

test("a_database_that_cannot_be_opened_is_reported", async () => {
  const { host, runner } = fresh();
  host.openDbHook = () => new SqlError("unable to open database file", "other");
  host.memoryDb = () => new NodeSql(new DatabaseSync(":memory:"));
  const data = new Data(host, runner, { owner: () => "s1" });
  await run(data.open(["s1"]));
  assert.deepEqual([...data.notes.values()].map((n) => n.kind), ["failed"]);
  assert.deepEqual(host.reported.map((e) => [e.name, e.message]), [["LocalDbFailed", "unable to open database file"]]);
  data.set(rows("w/a"), [{ id: "x" }]);
  assert.deepEqual(data.get(rows("w/a")), [{ id: "x" }], "in memory this run");
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

test("a_sessions_detail_says_its_summary_as_the_station_last_said_it_in_its_list_too", async () => {
  const { data, open, again, runner } = fresh();
  await open();
  // Its detail, read before its station said what can be done to its context; its list, read since, says it.
  data.set({ topic: "session", station: "w/a", key: "k1" }, { session: { key: "k1", turns: 1 }, turns: [{ kind: "chat" }], jobs: [], threads: [] });
  data.set(sessions("w/a"), [{ key: "k1", turns: 1, contextActions: ["compact", "clear"] }]);
  const actions = (d: Data) => (d.get({ topic: "session", station: "w/a", key: "k1" }) as J).session.contextActions;
  assert.deepEqual(actions(data), ["compact", "clear"]);
  await run(data.written);
  assert.deepEqual(actions(await again()), ["compact", "clear"], "as the device opens again");
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
  data.keepFile("w/a", "k1", "a.png", "thumb", "image/png", "q".repeat(1000));
  await flush();
  const usage = data.cacheUsage().sort((a, b) => a.thread - b.thread);
  assert.deepEqual(usage.map((u) => [u.thread, u.view?.title ?? null, u.sessions]), [[7, "大视频", ["k1"]], [8, null, []]]);
  assert.ok(usage[0]!.bytes > 1150, "its entries, its session's transcript and what it shows small");
  data.forgetChat("w/a", 7);
  await flush();
  assert.equal(data.logSpan("entry", "w/a", "7"), null);
  assert.equal(data.logSpan("transcript", "w/a", "k1"), null);
  assert.equal(data.keptFile("w/a", "k1", "a.png", "thumb"), null);
  assert.deepEqual(data.cacheUsage().map((u) => u.thread), [8]);
  runner.shutdown();
});

test("what_chats_show_small_is_kept_and_past_its_room_the_least_lately_shown_go", async () => {
  const { data, open, host, runner, again, db } = fresh();
  await open();
  const day = 86_400_000;
  const mib = "q".repeat(1024 * 1024);
  const kept = (name: string) => data.keptFile("w/a", "k1", name, "thumb") !== null;
  assert.equal(kept("0.png"), false);
  // Larger than a thumbnail is: not kept.
  data.keepFile("w/a", "k1", "big.png", "thumb", "image/png", `${mib}q`);
  for (let i = 0; i < 64; i++) {
    host.advance(day);
    data.keepFile("w/a", "k1", `${i}.png`, "thumb", "image/png", mib);
  }
  await flush();
  const writes = db().writes().length;
  assert.deepEqual(data.keptFile("w/a", "k1", "63.png", "thumb"), { type: "image/png", bytes: mib });
  assert.deepEqual([kept("big.png"), kept("63.png")], [false, true]);
  assert.equal(data.keptFile("w/a", "k1", "63.png", "poster"), null, "a thumbnail is not a poster");
  await flush();
  assert.equal(db().writes().length, writes, "shown the day it was kept: nothing written");
  // Shown a day later, 0 is the most lately shown; past 64 MiB, the least lately shown go until 80% of it is kept.
  host.advance(day);
  assert.ok(kept("0.png"));
  data.keepFile("w/a", "k1", "64.png", "thumb", "image/png", mib);
  await run(data.written);
  const left = Array.from({ length: 65 }, (_, i) => i).filter((i) => kept(`${i}.png`));
  assert.deepEqual(left, [0, ...Array.from({ length: 50 }, (_, i) => 15 + i)]);
  // Kept as the app starts anew.
  await run(data.written);
  const later = await again();
  assert.ok(later.keptFile("w/a", "k1", "64.png", "thumb") !== null);
  runner.shutdown();
});

test("what_agents_said_is_kept_read_as_the_app_starts_anew_and_let_go_with_its_chat", async () => {
  const { data, open, runner, again } = fresh();
  await open();
  data.putThread("w/a", { id: 7, title: "长回复", sessions: [{ session: "k1" }] });
  data.putThread("w/a", { id: 8, title: "另一个", sessions: [] });
  data.putItems("entry", "w/a", "8", [[1, { text: "other" }]]);
  const tree = JSON.stringify([["p", [[0, 3]]]]);
  const chat = data.mdStore("w/a", "t:7")!;
  assert.equal(chat.has("1.a"), false);
  assert.equal(chat.get("1.a"), null);
  chat.put("1.a", tree);
  data.mdStore("w/a", "s:k1")!.put("1.b", "[]");
  data.mdStore("w/a", "t:8")!.put("1.c", "[]");
  await flush();
  assert.equal(chat.get("1.a"), tree);
  assert.equal(data.mdStore("w/a", "t:8")!.has("1.a"), true, "by its text, whichever chat asks");
  assert.equal(data.mdStore("w/b", "t:7")!.has("1.a"), false, "a station's own");
  // Counted with the chat it was read for (an agent's, with its first chat): its entries' and its trees' characters.
  assert.deepEqual(data.cacheUsage().map((u) => [u.thread, u.bytes]).sort((a, b) => a[0]! - b[0]!), [[7, tree.length + 2], [8, '{"text":"other"}'.length + 2]]);
  // Kept as the app starts anew.
  await run(data.written);
  const later = await again();
  assert.equal(later.mdStore("w/a", "t:7")!.get("1.a"), tree);
  // Its chat forgotten: what was read for it and its agent goes with it, the other chat's stays.
  later.forgetChat("w/a", 7);
  await flush();
  assert.deepEqual(["1.a", "1.b", "1.c"].map((k) => later.mdStore("w/a", "t:8")!.has(k)), [false, false, true]);
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
  db().exec("DROP TRIGGER said_put; DROP TRIGGER said_drop; DROP TABLE said;");
  const d = await again();
  assert.deepEqual(found(d, "说法"), ["w/b 10 4 新的说法"]);
  assert.deepEqual(found(d, "排查"), ["w/a 7 1 排查登录很慢"]);
  runner.shutdown();
});

test("past_its_room_agents_transcripts_least_recently_used_go_and_a_chats_messages_stay", async () => {
  const host = new FakeHost();
  const runner = new Runner(host.time.clock);
  const sql = new NodeSql(new DatabaseSync(":memory:"), true);
  host.openDbHook = () => sql;
  const data = new Data(host, runner, { owner: () => "s1", kept: 1024 * 1024 });
  await run(data.open(["s1"]));
  const big = "字".repeat(2000);
  const said = (thread: number) => Array.from({ length: 20 }, (_, i) => [i + 1, { n: i + 1, kind: "message", text: `${thread} ${big}`, at: i }] as [number, J]);
  // Three transcripts, k1 the least recently used and k3 shown; and eight threads, more than the room alone.
  data.putItems("transcript", "w/a", "k1", [[0, { text: big }], [1, { text: big }]]);
  data.putItems("transcript", "w/a", "k2", [[0, { text: big }]]);
  data.putItems("transcript", "w/a", "k3", [[0, { text: big }]]);
  await run(data.written);
  data.opened("transcript", "w/a", "k3", true);
  for (let t = 1; t <= 8; t++) {
    host.advance(60_000);
    data.putItems("entry", "w/a", String(t), said(t));
    await run(data.written);
  }
  await run(data.written);
  // The transcripts not shown went; every chat's messages stayed, and what was said in them is found.
  assert.deepEqual(sql.all("SELECT DISTINCT session FROM transcript"), [["k3"]]);
  assert.equal(data.evicted("transcript", "w/a", "k1"), true);
  assert.deepEqual(sql.all("SELECT DISTINCT thread FROM entry ORDER BY thread").map((r) => r[0]), [1, 2, 3, 4, 5, 6, 7, 8]);
  for (let t = 1; t <= 8; t++) assert.equal(data.evicted("entry", "w/a", String(t)), false);
  assert.equal(data.findSaid(["w/a"], [`1 字字字`], 50).length, 20);
  // Opened again: kept, and said to be brought back; let go no more after a restart either.
  assert.equal(data.opened("transcript", "w/a", "k1", true), true);
  assert.equal(data.evicted("transcript", "w/a", "k1"), false);
  await run(data.written);
  assert.deepEqual(sql.all("SELECT evicted FROM log_use WHERE kind = 'transcript' AND id = 'k1'"), [[0]]);
  runner.shutdown();
});

test("a_chats_messages_let_go_for_room_before_come_back_and_what_the_search_index_kept_of_them_goes", async () => {
  const { data, open, again, runner } = fresh();
  await open();
  const db = () => data.db("s1")!.sql;
  const text = (t: number, round: number) => `第 ${round} 遍 ${t} 号对话里说的话 ${"排查登录很慢".repeat(20)}`;
  // The full-text index of what was said an earlier core kept.
  db().exec(`
    CREATE VIRTUAL TABLE IF NOT EXISTS said_index USING fts5(text, content = 'said', content_rowid = 'id', tokenize = 'trigram');
    CREATE TRIGGER IF NOT EXISTS said_index_put AFTER INSERT ON said BEGIN INSERT INTO said_index (rowid, text) VALUES (new.id, new.text); END;
    CREATE TRIGGER IF NOT EXISTS said_index_drop AFTER DELETE ON said BEGIN INSERT INTO said_index (said_index, rowid, text) VALUES ('delete', old.id, old.text); END;
    CREATE TRIGGER IF NOT EXISTS said_index_set AFTER UPDATE OF text ON said WHEN old.text IS NOT new.text BEGIN
      INSERT INTO said_index (said_index, rowid, text) VALUES ('delete', old.id, old.text);
      INSERT INTO said_index (rowid, text) VALUES (new.id, new.text);
    END;
  `);
  // As that core did: a chat's messages let go for room and read again as it was opened, over and over; what the index
  // held of each went only as a deleted row's terms, kept until its segments merge.
  for (let round = 0; round < 30; round++) {
    for (let t = 1; t <= 20; t++) data.putItems("entry", "w/a", String(t), [[1, { n: 1, kind: "message", text: text(t, round), at: 1 }]]);
    await run(data.written);
    db().run("DELETE FROM entry WHERE station = 'w/a' AND thread > 1");
  }
  for (let t = 2; t <= 20; t++) db().run("INSERT INTO log_use (kind, station, id, evicted) VALUES ('entry', 'w/a', ?, 1)", [String(t)]);
  const used = () => data.db("s1")!.used();
  const before = used();
  const d = await again();
  // Opened again: none is let go, so the sync brings them all; the room the index took is the database's again, and
  // what was said is found by scanning it.
  for (let t = 1; t <= 20; t++) assert.equal(d.evicted("entry", "w/a", String(t)), false, `thread ${t}`);
  assert.ok(used() < before, `${used()} of ${before}`);
  assert.deepEqual(db().all("SELECT name FROM sqlite_master WHERE name LIKE 'said_index%'"), []);
  assert.equal(d.findSaid(["w/a"], ["第 29 遍 1 号"], 5).length, 1);
  assert.equal(d.findSaid(["w/a"], ["第 28 遍"], 5).length, 0);
  runner.shutdown();
});

test("the_room_a_database_file_holds_and_no_longer_uses_is_given_back_to_the_device_at_open", async () => {
  // A file, as the app's: what the device counts is the database's file and its write-ahead log.
  const dir = mkdtempSync(join(tmpdir(), "data-room-"));
  const host = new FakeHost();
  host.openDbHook = (name) => {
    let sql = host.sqls.get(name) as NodeSql | undefined;
    if (!sql) host.sqls.set(name, (sql = NodeSql.file(join(dir, `${name}.db`))));
    return sql;
  };
  const runner = new Runner(host.time.clock);
  const owner = () => "s1";
  const data = new Data(host, runner, { owner });
  await run(data.open(["s1"]));
  const sql = host.sqls.get(dbName("s1")) as NodeSql;
  const onDisk = () => [".db", ".db-wal"].reduce((n, end) => n + (existsSync(join(dir, dbName("s1") + end)) ? statSync(join(dir, dbName("s1") + end)).size : 0), 0);
  const free = () => Number(sql.all("PRAGMA freelist_count")[0]?.[0]) * Number(sql.all("PRAGMA page_size")[0]?.[0]);
  // As a phone's was: an earlier core's full-text index of what was said, taken away by the next (#2777), its pages left
  // free in the file.
  sql.exec(`
    CREATE VIRTUAL TABLE said_index USING fts5(text, content = 'said', content_rowid = 'id', tokenize = 'trigram');
    CREATE TRIGGER said_index_put AFTER INSERT ON said BEGIN INSERT INTO said_index (rowid, text) VALUES (new.id, new.text); END;
  `);
  for (let t = 1; t <= 40; t++) data.putItems("entry", "w/a", String(t), Array.from({ length: 50 }, (_, i) => [i + 1, { n: i + 1, kind: "message", text: `${t} 号对话第 ${i} 条 ${"排查登录很慢为什么".repeat(30)}`, at: 1 }]));
  await run(data.written);
  sql.exec("DROP TRIGGER said_index_put; DROP TABLE said_index");
  sql.all("PRAGMA wal_checkpoint(TRUNCATE)");
  const before = onDisk();
  const freed = free();
  assert.ok(freed > 256 * 1024, `${freed}`);
  const d = await again();
  // Opened again: the room the index took is the device's again; the messages stay.
  assert.equal(free(), 0);
  assert.ok(onDisk() <= before - freed, `${onDisk()} of ${before}, ${freed} free`);
  assert.equal(d.findSaid(["w/a"], ["40 号对话第 49 条"], 5).length, 1);
  // Opened yet again (nothing freed since): nothing to give back, nothing grows.
  const now = onDisk();
  await again();
  assert.ok(onDisk() <= now, `${onDisk()} of ${now}`);
  runner.shutdown();
  rmSync(dir, { recursive: true, force: true });

  async function again() {
    const d = new Data(host, runner, { owner });
    await run(d.open(["s1"]));
    return d;
  }
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
  host.store(STORAGE_KEY, [account("s1", "a@x.com", "", "tok", "r0", nowS(host) + 3600)]);
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

test("what_agents_said_in_slack_is_read_as_their_transcripts_are_written_kept_past_them_and_filled_once_where_missing", async () => {
  const { data, open, db, again, runner } = fresh();
  await open();
  const call = (to: string, text: string, callId: string) => ({ at: "1970-01-01T00:00:02Z", kind: "tool_call", tool: "mcp__stillfail__chat_post", text: JSON.stringify({ to, text }), callId });
  const told: string[] = [];
  data.onLogChange((table, station, id) => told.push(`${table} ${station} ${id}`));
  data.putItems("transcript", "w/a", "k1", [[0, { kind: "user", text: "hi" }], [1, call("C0OPS/1.2", "*好了*", "c1")]]);
  await flush();
  assert.deepEqual(data.slackSaid("w/a", "k1").map((s) => [s.i, s.to, s.text, s.failed]), [[1, "C0OPS/1.2", "**好了**", false]]);
  assert.ok(told.includes("slack w/a k1"));
  data.putItems("transcript", "w/a", "k1", [[2, { kind: "tool_result", text: "failed", ok: false, callId: "c1" }]]);
  await flush();
  assert.deepEqual(data.slackSaid("w/a", "k1").map((s) => s.failed), [true]);
  // Written again as it was: nothing read again (it stays failed).
  told.length = 0;
  data.putItems("transcript", "w/a", "k1", [[1, call("C0OPS/1.2", "*好了*", "c1")]]);
  await flush();
  assert.deepEqual([data.slackSaid("w/a", "k1").map((s) => s.failed), told], [[true], []]);
  // A core before it held the transcript only: the table is made and filled as the database opens.
  db().run("DROP TABLE slack_said", []);
  const d = await again();
  assert.deepEqual(d.slackSaid("w/a", "k1").map((s) => [s.i, s.failed]), [[1, true]]);
  // Its transcript cut before it: it goes.
  d.putItems("transcript", "w/a", "k1", [], 0);
  await flush();
  assert.deepEqual(d.slackSaid("w/a", "k1"), []);
  runner.shutdown();
});

test("the_slack_people_a_stations_agents_heard_from_are_named_by_their_slack_id_as_last_heard", async () => {
  const { data, open, runner } = fresh();
  await open();
  assert.deepEqual(data.slackNames("w/a"), []);
  const heard = (i: number, from: string, at: string) => [i, { at, kind: "user", text: `<message via="slack" thread="C0OPS/1.2" from="${from}" ts="${i}">hi</message>` }] as [number, J];
  data.putItems("transcript", "w/a", "k1", [heard(3, "Mia (U9)", "1970-01-01T00:00:03Z")]);
  await flush();
  assert.deepEqual(data.slackNames("w/a"), [["U9", "Mia"]]);
  data.putItems("transcript", "w/a", "k2", [heard(4, "Mia Wu (U9)", "1970-01-01T00:00:04Z"), heard(5, "Bo (U8)", "1970-01-01T00:00:05Z")]);
  await flush();
  assert.deepEqual(data.slackNames("w/a"), [["U9", "Mia Wu"], ["U8", "Bo"]]);
  data.putItems("transcript", "w/a", "k2", [], 3);
  await flush();
  assert.deepEqual(data.slackNames("w/a"), [["U9", "Mia"]]);
  // A bot is said as its mention: named by the id in it, as a mention of it is written.
  data.putItems("transcript", "w/a", "k3", [heard(6, "GPT-Ember (<@UB2>)", "1970-01-01T00:00:06Z")]);
  await flush();
  assert.deepEqual(data.slackNames("w/a"), [["U9", "Mia"], ["UB2", "GPT-Ember"]]);
  runner.shutdown();
});


test("a_hot_logs_number_index_tracks_appends_holes_and_truncation_without_rescanning_sql", async () => {
  const { data, open, db, runner } = fresh();
  await open();
  try {
    const ns = (items: number[]): [number, unknown][] => items.map(n => [n, { n }]);
    data.putItems("transcript", "w/a", "large", ns(Array.from({ length: 5000 }, (_, i) => i + 100)));
    await flush();
    data.logNumbers("transcript", "w/a", "large");
    db().reads = [];
    for (let i = 5100; i < 5200; i++) {
      data.putItems("transcript", "w/a", "large", ns([i]));
      assert.equal(data.logSpan("transcript", "w/a", "large")?.max, i);
      assert.equal(data.logNumbers("transcript", "w/a", "large").length, i - 99);
      assert.equal(data.logCount("transcript", "w/a", "large", 5100, i), i - 5099);
    }
    assert.equal(db().reads.filter(q => q.startsWith("SELECT i FROM transcript") || q.includes("SELECT min(i)") || q.includes("SELECT count(*) FROM transcript")).length, 0, "metadata reads use the index, even after each append");
    data.putItems("transcript", "w/a", "large", ns([98, 96, 98, 99]));
    assert.deepEqual(data.logNumbers("transcript", "w/a", "large").slice(0, 5), [96, 98, 99, 100, 101]);
    assert.equal(data.logCount("transcript", "w/a", "large", 96, 100), 4);
    data.putItems("transcript", "w/a", "large", ns([97, 100]), 100);
    assert.deepEqual(data.logNumbers("transcript", "w/a", "large"), [96, 97, 98, 99, 100]);
    assert.equal(data.logCount("transcript", "w/a", "large", 100, 96), 0);
    data.forgetLog("transcript", "w/a", "large");
    assert.deepEqual(data.logNumbers("transcript", "w/a", "large"), []);
    assert.equal(data.logSpan("transcript", "w/a", "large"), null);
    data.putItems("transcript", "w/a", "large", ns([0, 1]));
    assert.deepEqual(data.logNumbers("transcript", "w/a", "large"), [0, 1]);
  } finally { runner.shutdown(); }
});

test("a_rolled_back_log_burst_drops_the_incrementally_updated_index", async () => {
  const { data, open, db, runner } = fresh();
  await open();
  try {
    data.putItems("entry", "w/a", "7", [[1, { n: 1 }]]);
    await flush();
    data.logNumbers("entry", "w/a", "7");
    let fail = true;
    db().failing = q => {
      if (q !== "COMMIT" || !fail) return null;
      fail = false;
      return new SqlError("database or disk is full", "full");
    };
    data.putItems("entry", "w/a", "7", [[2, { n: 2 }]]);
    assert.deepEqual(data.logNumbers("entry", "w/a", "7"), [1, 2], "reads see the current transaction");
    await flush();
    assert.deepEqual(data.logNumbers("entry", "w/a", "7"), [1], "rollback removes the uncommitted number");
    assert.deepEqual(data.logSpan("entry", "w/a", "7"), { min: 1, max: 1, count: 1 });
    data.putItems("entry", "w/a", "7", [[3, { n: 3 }]]);
    assert.deepEqual(data.logNumbers("entry", "w/a", "7"), [1, 3]);
  } finally { runner.shutdown(); }
});


test("a_cached_window_reuses_payloads_without_reading_their_json_again_and_tracks_edits", async () => {
  const { data, open, db, runner } = fresh();
  await open();
  try {
    data.putItems("entry", "w/a", "7", [[1, { n: 1, text: "before" }], [3, { n: 3, text: "other" }]]);
    data.logNumbers("entry", "w/a", "7");
    const first = data.logRange("entry", "w/a", "7", 1, 3);
    db().reads = [];
    const again = data.logRange("entry", "w/a", "7", 1, 3);
    assert.deepEqual([...again.keys()], [1, 3], "the known hole stays a hole");
    assert.equal(again.get(1), first.get(1), "parsed records keep their identity");
    assert.equal(db().reads.length, 0, "no payload or metadata query for the cached window");
    data.putItems("entry", "w/a", "7", [[1, { n: 1, text: "after" }], [2, { n: 2, text: "hole filled" }]]);
    assert.deepEqual([...data.logRange("entry", "w/a", "7", 1, 3).values()], [{ n: 1, text: "after" }, { n: 2, text: "hole filled" }, { n: 3, text: "other" }]);
    data.forgetLog("entry", "w/a", "7");
    assert.equal(data.logRange("entry", "w/a", "7", 1, 3).size, 0);
  } finally { runner.shutdown(); }
});

test("log_removal_paths_invalidate_their_number_indices_and_payload_windows", async () => {
  for (const action of ["evict", "chat", "station"]) {
    const { data, open, runner } = fresh();
    await open();
    try {
      data.putThread("w/a", { id: 7, sessions: [{ session: "k1" }] });
      data.putItems("entry", "w/a", "7", [[1, { n: 1 }]]);
      data.putItems("transcript", "w/a", "k1", [[0, { text: "held" }]]);
      data.logNumbers("entry", "w/a", "7"); data.logRange("entry", "w/a", "7", 1, 1);
      data.logNumbers("transcript", "w/a", "k1"); data.logRange("transcript", "w/a", "k1", 0, 0);
      if (action === "evict") data.of("w/a")!.evict("w/a", "k1");
      else if (action === "chat") data.forgetChat("w/a", 7);
      else data.of("w/a")!.forgetStation("w/a");
      // A transcript let go for room; a chat's messages never are.
      const entries = action === "evict" ? 1 : 0;
      assert.deepEqual(data.logNumbers("entry", "w/a", "7"), entries ? [1] : [], action);
      assert.deepEqual(data.logNumbers("transcript", "w/a", "k1"), [], action);
      assert.equal(data.logRange("entry", "w/a", "7", 1, 1).size, entries, action);
      assert.equal(data.logRange("transcript", "w/a", "k1", 0, 0).size, 0, action);
    } finally { runner.shutdown(); }
  }
});
