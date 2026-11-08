// The MoonBit builder of the recent chats (station/mb, src/recent) makes the index's four parts as the TypeScript
// does and prepares the requested scopes as `RecentChatPreparation` does: the same schema, and for the same chats,
// scope by scope and batch by batch, the same answers and the same tables, before and after the station writes.
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { MbProcess, mbReaderBinary } from "../src/read/mb-reader.ts";
import { RecentChatBuilder } from "../src/read/recent-chat-builder.ts";
import { recentChatIds } from "../src/store/chat-list.ts";
import { readPreparedRecentHome } from "../src/store/chat-list-home-overlap.ts";
import { readGlobalRecentChatIndex } from "../src/store/chat-list-index.ts";
import { RecentChatPreparation, type RecentChatScope } from "../src/store/chat-list-prepare.ts";
import { readPreparedRecentWorkspace } from "../src/store/chat-list-scope-rows.ts";
import { Store } from "../src/store/store.ts";

const binary = mbReaderBinary();

function session(store: Store, key: string, ws: string | null, connect = "ember") {
  store.insertSession({ key, connect, runtime: "claude", profile: "cc", workspace: "/w", token: key, createdAt: 1, lastActiveAt: 1, ws } as Parameters<Store["insertSession"]>[0]);
}

/// A station's database: sessions in workspaces A and B, of the default home, and 70 of workspaces of their own; 300
/// chats of theirs, most with a home, some shared, most with a message; one chat without a home shared by the 70.
function station(shared = 70) {
  const dir = mkdtempSync(join(tmpdir(), "mb-recent-"));
  const path = join(dir, "stillfail.db");
  const store = Store.open(path, join(dir, "archive")), db = store.db;
  for (const [key, ws] of [["a", "A"], ["b", "B"], ["h", null], ["a2", "A"]] as const) session(store, key, ws);
  // (each of a connection of its own: a workspace's scan meets more than 64 connections and goes on by rowid)
  for (let i = 0; i < shared; i++) session(store, `w${i}`, `W${i}`, `c${i}`);
  db.exec("BEGIN");
  const threads: number[] = [];
  for (let i = 0; i < 300; i++) {
    const owner = ["a", "b", "h", "a2"][i % 4]!;
    // (a third without a home: their members decide where they are)
    const thread = store.openThreadOf("ember", "CHAT", `chat-${i}`, `chat ${i}`, "ann@x", i % 3 === 0 ? null : owner).id;
    if (i % 5 === 0) db.prepare("UPDATE threads SET home = ? WHERE id = ?").run(["b", "a", "h", "nobody"][i % 4], thread);
    else store.joinThread(thread, owner, "ember");
    if (i % 7 === 0) store.joinThread(thread, "b", "ember");
    if (i % 11 === 0) store.joinThread(thread, "missing", "ember");
    db.prepare("UPDATE threads SET created_at = ? WHERE id = ?").run(i, thread);
    if (i % 4 !== 0) db.prepare("INSERT INTO entries (thread,n,kind,author_kind,author,text,at) VALUES (?,1,'message','person','ann@x','body',?)").run(thread, 1000 + (i * 37) % 300);
    threads.push(thread);
  }
  const wide = store.openThread("ember", "CHAT", "wide", "wide", "ann@x").id;
  for (let i = 0; i < shared; i++) store.joinThread(wide, `w${i}`, "ember");
  store.joinThread(wide, "a", "ember");
  db.prepare("UPDATE threads SET created_at = 400 WHERE id = ?").run(wide);
  threads.push(wide);
  db.exec("COMMIT");
  return { dir, path, store, threads, wide, close: () => { store.close(); rmSync(dir, { recursive: true, force: true }); } };
}

/// What the station writes meanwhile, the same on both.
function writes(f: ReturnType<typeof station>, round: number) {
  const { store, threads, wide } = f, db = store.db;
  const say = (thread: number, n: number, at: number) =>
    db.prepare("INSERT INTO entries (thread,n,kind,author_kind,author,text,at) VALUES (?,?,'message','person','ann@x','new',?)").run(thread, n, at);
  if (round === 1) {
    const fresh = store.openThread("ember", "CHAT", "fresh", "fresh", "ann@x").id;
    store.joinThread(fresh, "a", "ember");
    store.joinThread(fresh, "missing", "ember");
    db.prepare("UPDATE threads SET created_at = 500 WHERE id = ?").run(fresh);
    say(threads[3]!, 2, 5000);
    say(wide, 1, 6000);
  }
  if (round === 3) {
    db.prepare("UPDATE sessions SET ws = NULL WHERE key = 'b'").run();
    db.prepare("UPDATE threads SET home = 'a' WHERE id = ?").run(wide);
    db.prepare("DELETE FROM threads WHERE id = ?").run(threads[8]!);
    store.joinThread(threads[9]!, "a", "ember");
  }
  if (round === 6) {
    db.prepare("UPDATE sessions SET ws = 'A' WHERE key = 'h'").run();
    say(threads[10]!, 3, 7000);
    db.prepare("DELETE FROM thread_sessions WHERE thread = ? AND session = 'a'").run(threads[1]!);
    db.prepare("UPDATE threads SET home = NULL WHERE id = ?").run(threads[0]!);
  }
}

const bare = (sql: string | null) => (sql ?? "").replace(/\s+/g, "");
function schema(store: Store): string {
  return JSON.stringify((store.db.prepare("SELECT type, name, tbl_name, sql FROM sqlite_master WHERE name LIKE 'recent%' ORDER BY type, name").all() as { sql: string | null }[])
    .map((row) => ({ ...row, sql: bare(row.sql) })));
}
/// Every table of the index, a row a line, sorted.
function tables(store: Store): string[] {
  const names = (store.db.prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'recent%' ORDER BY name").all() as { name: string }[]).map((r) => r.name);
  return names.flatMap((name) => (store.db.prepare(`SELECT * FROM ${name}`).all() as object[]).map((r) => `${name} ${JSON.stringify(r)}`)).sort();
}

/// The rows only one side has, none when the tables are the same.
function same(ours: string[], theirs: string[], what: string) {
  const a = new Set(ours), b = new Set(theirs);
  assert.deepEqual({ ours: ours.filter((r) => !b.has(r)), theirs: theirs.filter((r) => !a.has(r)) }, { ours: [], theirs: [] }, what);
}

const page = (db: Store["db"], { ws, home }: RecentChatScope) => ws === null ? readGlobalRecentChatIndex(db, 400)
  : ws === home ? readPreparedRecentHome(db, ws, 400) : readPreparedRecentWorkspace(db, ws, 400);

/// Both databases, the TypeScript preparing one and the MoonBit builder the other; `settle` asks both for the scopes
/// until each is ready, `change(round)` written to both before each round, and compares them after every round.
function both(shared?: number) {
  assert.notEqual(binary, null, "the MoonBit reader is built (station/mb/build.sh, or STILLFAIL_MB_READER)");
  const ts = station(shared), mb = station(shared);
  const builder = new MbProcess(binary!, ["--builder", "recent-chat", "--db", mb.path]);
  const preparation = new RecentChatPreparation(ts.store.db);
  const ask = async (scope: RecentChatScope) => {
    const answered = new Promise<{ done: boolean; error?: string }>((resolve) => builder.once("message", resolve));
    builder.postMessage({ scope: JSON.stringify([scope.ws, scope.home]) });
    const ours = await answered;
    assert.equal(ours.error, undefined);
    return ours.done;
  };
  const settle = async (scopes: RecentChatScope[], change: (f: ReturnType<typeof station>, round: number) => void = () => {}) => {
    let round = 0, steps = 0;
    for (let open = scopes; open.length > 0 && round < 500; round++) {
      change(ts, round); change(mb, round);
      const left: RecentChatScope[] = [];
      for (const scope of open) {
        const ours = await ask(scope), theirs = preparation.step(scope).done;
        assert.equal(ours, theirs, `scope ${JSON.stringify(scope)} at round ${round}`);
        steps++;
        if (!ours) left.push(scope);
      }
      if (round === 0) assert.equal(schema(mb.store), schema(ts.store), "the same tables and triggers");
      same(tables(mb.store), tables(ts.store), `the same tables after round ${round}`);
      open = left;
    }
    assert.equal(schema(mb.store), schema(ts.store));
    for (const scope of scopes) {
      assert.deepEqual(page(mb.store.db, scope), recentChatIds(mb.store.db, scope.ws, scope.home, 400), JSON.stringify(scope));
      assert.deepEqual(page(mb.store.db, scope), page(ts.store.db, scope));
    }
    return { round, steps };
  };
  return { ts, mb, settle, close: async () => { await builder.terminate(); ts.close(); mb.close(); } };
}

test("the MoonBit builder prepares the station's, a workspace's and home's recent chats as the TypeScript does", async () => {
  const f = both();
  try {
    const scopes = [{ ws: null, home: "A" }, { ws: "B", home: "A" }, { ws: "A", home: "A" }];
    const { round, steps } = await f.settle(scopes, writes);
    assert.ok(round > 7, `the writes came while it prepared (${round} rounds)`);
    assert.ok(steps > scopes.length * 4, `in batches (${steps} steps)`);
    assert.deepEqual(f.mb.store.db.prepare("SELECT ws, scan_rowids FROM recent_scope_tracked WHERE kind = 1 ORDER BY ws").all().map((r) => ({ ...r })),
      [{ ws: "A", scan_rowids: 1 }, { ws: "B", scan_rowids: 1 }], "the scans went on by rowid past 64 connections");
  } finally { await f.close(); }
});

test("a chat in more than 64 prepared workspaces has its order change dispatched in batches, as the TypeScript does", async () => {
  const f = both();
  try {
    const scopes: RecentChatScope[] = [{ ws: "A", home: "A" }];
    for (let i = 0; i < 70; i++) scopes.push({ ws: `W${i}`, home: "A" });
    await f.settle(scopes);
    const dispatched = () => (f.mb.store.db.prepare("SELECT COUNT(*) AS n FROM recent_scope_order_dispatch").get() as { n: number }).n;
    // a message in the chat all 70 share, then one more while its change is being dispatched
    const say = (n: number, at: number) => (g: ReturnType<typeof station>, round: number) => {
      if (round === 0) g.store.db.prepare("INSERT INTO entries (thread,n,kind,author_kind,author,text,at) VALUES (?,?,'message','person','ann@x','new',?)").run(g.wide, n, at);
    };
    say(1, 8000)(f.ts, 0); say(1, 8000)(f.mb, 0);
    assert.equal(dispatched(), 1, "the change waits to be dispatched");
    await f.settle(scopes, (g, round) => say(2, 9000)(g, round - 1));
    assert.equal(dispatched(), 0);
  } finally { await f.close(); }
});

test("the builder prepares a requested scope behind a pending write, and gives the permit back", async () => {
  assert.notEqual(binary, null);
  const f = station(4);
  const priority = new SharedArrayBuffer(8), flags = new Int32Array(priority);
  Atomics.add(flags, 0, 1);
  const builder = new RecentChatBuilder(f.path, { priority }, undefined, binary);
  try {
    const ready = builder.readyScope({ ws: "A", home: "A" });
    let settled = false;
    void ready.then(() => { settled = true; }, () => { settled = true; });
    await new Promise((resolve) => setTimeout(resolve, 100));
    assert.equal(settled, false, "nothing prepared while the write is pending");
    Atomics.sub(flags, 0, 1);
    await ready;
    assert.deepEqual(readPreparedRecentHome(f.store.db, "A", 400), recentChatIds(f.store.db, "A", "A", 400));
    assert.equal(Atomics.load(flags, 1), 0, "the permit given back");
  } finally {
    await builder.close();
    f.close();
  }
});

test("an invalid scope is answered with an error, and the builder goes on", async () => {
  assert.notEqual(binary, null);
  const f = station(0);
  const builder = new MbProcess(binary!, ["--builder", "recent-chat", "--db", f.path]);
  try {
    const ask = (scope: string) => {
      const answered = new Promise<{ done: boolean; error?: string }>((resolve) => builder.once("message", resolve));
      builder.postMessage({ scope });
      return answered;
    };
    assert.deepEqual(await ask("[1, 2]"), { done: false, error: "invalid recent chat scope" });
    let done = false;
    for (let i = 0; i < 50 && !done; i++) done = (await ask(JSON.stringify([null, null]))).done;
    assert.equal(done, true);
  } finally {
    await builder.terminate();
    f.close();
  }
});
