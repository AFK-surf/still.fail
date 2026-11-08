import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { routerReads } from "../src/comma/chats.ts";
import { peerRead, textOf } from "../src/comma/peer.ts";
import { CommaSurface } from "../src/comma/surface.ts";
import { bytesOf } from "../src/mesh/bus.ts";
import { usageOps } from "../src/read/ops-usage.ts";
import { outflowMessages } from "../src/read/outflow.ts";
import { Readers } from "../src/read/pool.ts";
import { LEGACY_PAGE_ORDINARY_KEYS_AFTER, makeStore, messageEntriesAfter, PAGE_LETTER_CANDIDATES_AFTER, PAGE_ORDINARY_KEYS_AFTER } from "../src/read/store.ts";
import { installLegacySaid, legacySaidDrainThread, legacySaidStep } from "../src/store/legacy-said-build.ts";
import { PAGE_LETTER_KEYS_AFTER, pageLetterStep } from "../src/store/page-letter-index.ts";
import { installSaidState } from "../src/store/said-state.ts";
import { Store } from "../src/store/store.ts";

function fixture(path = ":memory:") {
  const store = Store.open(path), db = store.db;
  store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w/a",
    token: "a", createdAt: 1, lastActiveAt: 1, createdBy: "ann@x", ws: null });
  const thread = store.openThreadOf("ember", "CHAT", "100.1", "A chat", "ann@x", "a");
  store.joinThread(thread.id, "a", "ember");
  const put = db.prepare("INSERT INTO entries(thread,n,kind,target,letter,author_kind,author,text,at) VALUES(?,?,?,?,?,?,?,?,?)");
  const add = (n: number, kind: string, text: string, letter: string | null = null) =>
    put.run(thread.id, n, kind, kind === "edit" ? 1 : null, letter, "person", "ann@x", text, n);
  return { store, db, thread: thread.id, add };
}

const stats = { taskTitle: () => "A chat" } as any;

test("a Router page counts messages rather than intervening edits", async () => {
  const f = fixture();
  try {
    f.add(1, "message", "first");
    for (let n = 2; n <= 7; n++) f.add(n, "edit", `edit-${n}`);
    f.add(8, "message", "next");
    f.add(9, "edit", "later edit");
    f.add(10, "message", "last");
    const reader = makeStore(f.db, ".");
    const raw = outflowMessages(reader, f.thread, 1, 5);
    assert.deepEqual(raw.messages.map((m: any) => m.kind), ["edit", "edit", "edit", "edit", "edit"]);
    assert.equal(raw.more, true);
    assert.equal(raw.messagesOnly, undefined, "the old peer answer is unchanged");
    const reads = {
      home: () => null,
      here: async (op: string, args: any) => {
        assert.equal(op, "outflowMessages");
        return JSON.stringify(outflowMessages(reader, args.thread, args.after, args.limit, undefined, args.messagesOnly === true));
      },
      there: async () => { throw new Error("unexpected peer"); },
    };
    const first = await routerReads(stats, reads, String(f.thread), 1, 1);
    assert.deepEqual(first.messages.map((m: any) => [m.seq, m.text]), [[8, "next"]]);
    assert.equal(first.through, 10);
    const second = await routerReads(stats, reads, String(f.thread), 8, 5);
    assert.deepEqual(second.messages.map((m: any) => [m.seq, m.text]), [[10, "last"]]);
    assert.equal(second.through, 10);
  } finally { f.store.close(); }
});

test("a message page merges ordinary messages and letters in order, retaining original text", () => {
  const f = fixture();
  try {
    const letter = JSON.stringify({ way: "in", title: "Other chat", link: null });
    f.add(1, "message", "ordinary");
    f.add(2, "edit", "edited ordinary");
    f.add(3, "edit", "letter metadata on an edit", letter);
    f.add(4, "message", "letter", letter);
    f.add(5, "message", "last");
    const reader = makeStore(f.db, ".");
    const page = outflowMessages(reader, f.thread, 0, 2, undefined, true);
    assert.deepEqual(page.messages.map((m: any) => [m.n, m.text]), [[1, "ordinary"], [4, "letter"]]);
    assert.equal(page.messagesOnly, true);
    assert.equal(page.more, true);
    assert.equal(page.last, 5);
    assert.deepEqual(outflowMessages(reader, f.thread, 4, 2, undefined, true).messages.map((m: any) => m.n), [5]);
    const ordinary = f.db.prepare(`EXPLAIN QUERY PLAN ${PAGE_ORDINARY_KEYS_AFTER}`).all(f.thread, 0, 2).map((r) => String(r.detail));
    const letters = f.db.prepare(`EXPLAIN QUERY PLAN ${PAGE_LETTER_CANDIDATES_AFTER}`).all(f.thread, 0, 66).map((r) => String(r.detail));
    assert.ok(ordinary.some((p) => p.includes("entries_said")), ordinary.join("\n"));
    assert.ok(letters.some((p) => p.includes("entries_letters")), letters.join("\n"));
  } finally { f.store.close(); }
});

test("a prepared letter page follows old writes in ascending order", () => {
  const f = fixture();
  try {
    const letter = JSON.stringify({ way: "in", title: "Other chat", link: null });
    f.add(1, "message", "ordinary");
    f.add(3, "message", "removed letter", letter);
    f.add(5, "message", "kept letter", letter);
    while (!pageLetterStep(f.db, f.thread).done) { /* prepare */ }
    f.db.prepare("UPDATE entries SET kind='edit' WHERE thread=? AND n=3").run(f.thread);
    f.add(2, "message", "new letter", letter);
    const reader = makeStore(f.db, ".");
    assert.deepEqual(messageEntriesAfter(reader, f.thread, 0, 3).map((e) => [e.n, e.text]),
      [[1, "ordinary"], [2, "new letter"], [5, "kept letter"]]);
    assert.deepEqual(messageEntriesAfter(reader, f.thread, 2, 3).map((e) => e.n), [5]);
  } finally { f.store.close(); }
});

for (const mode of ["current", "letters", "legacy"] as const) test(`message pages match the entries after old writes (${mode})`, () => {
  const f = fixture();
  try {
    const letter = JSON.stringify({ way: "in", title: "Other chat", link: null });
    for (let n = 1; n <= 137; n++)
      f.add(n, n % 4 === 0 || n % 7 === 0 ? "edit" : "message", `entry-${n}`, n % 3 === 0 ? letter : null);
    if (mode !== "current") while (!pageLetterStep(f.db, f.thread).done) { /* prepare */ }
    if (mode === "legacy") {
      installLegacySaid(f.db);
      f.db.exec("DROP INDEX entries_said");
      installSaidState(f.db);
      while (!legacySaidStep(f.db).ready) { /* prepare */ }
    }
    // An older writer can change prepared rows without rebuilding either index immediately.
    f.db.prepare("UPDATE entries SET kind='edit' WHERE thread=? AND n=5").run(f.thread);
    f.db.prepare("UPDATE entries SET kind='message',letter=? WHERE thread=? AND n=8").run(letter, f.thread);
    f.db.prepare("UPDATE entries SET letter=NULL WHERE thread=? AND n=9").run(f.thread);
    f.db.prepare("DELETE FROM entries WHERE thread=? AND n=11").run(f.thread);
    for (let n = 138; n <= 147; n++) f.add(n, n % 4 === 0 ? "edit" : "message", `entry-${n}`, n % 3 === 0 ? letter : null);
    const reader = makeStore(f.db, ".");
    const reference = f.db.prepare("SELECT n,text FROM entries WHERE thread=? AND n>? AND kind='message' ORDER BY n LIMIT ?");
    for (const after of [0, 1, 5, 8, 11, 42, 100, 136, 140, 147]) for (const limit of [1, 2, 5, 10, 37]) {
      const expected = reference.all(f.thread, after, limit).map((row) => [row.n, row.text]);
      const actual = messageEntriesAfter(reader, f.thread, after, limit).map((entry) => [entry.n, entry.text]);
      assert.deepEqual(actual, expected, `after ${after}, limit ${limit}`);
    }
  } finally { f.store.close(); }
});

for (const kind of ["ordinary", "letters"] as const) test(`a prepared old ${kind} lookup visits only the requested page`, () => {
  const f = fixture();
  try {
    const letter = kind === "letters" ? JSON.stringify({ way: "in", title: "Other chat", link: null }) : null;
    f.db.exec("BEGIN");
    for (let n = 1; n <= 3000; n++) f.add(n, "message", `message-${n}`, letter);
    f.db.exec("COMMIT");
    if (kind === "ordinary") {
      installLegacySaid(f.db);
      f.db.exec("DROP INDEX entries_said");
      installSaidState(f.db);
      while (!legacySaidStep(f.db).ready) { /* prepare */ }
    } else while (!pageLetterStep(f.db, f.thread).done) { /* prepare */ }
    let visited = 0;
    f.db.function("observe_message_after", (_n) => { visited++; return 1; });
    const observed = new Proxy(f.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (kind === "ordinary" && sql === LEGACY_PAGE_ORDINARY_KEYS_AFTER)
          sql = sql.replace("n>?2 ORDER BY n", "n>?2 AND observe_message_after(n) ORDER BY n");
        if (kind === "letters" && sql === PAGE_LETTER_KEYS_AFTER)
          sql = sql.replace("b.n>CAST(?3 AS INTEGER)", "b.n>CAST(?3 AS INTEGER) AND observe_message_after(b.n)");
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const page = messageEntriesAfter(makeStore(observed, "."), f.thread, 0, 10);
    assert.deepEqual(page.map((e) => e.n), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    assert.equal(visited, 10);
  } finally { f.store.close(); }
});

test("the message page and its index readiness share a snapshot", () => {
  const dir = mkdtempSync(join(tmpdir(), "comma-message-after-"));
  const path = join(dir, "stillfail.db"), f = fixture(path), writer = new DatabaseSync(path);
  try {
    f.add(1, "message", "before");
    let changed = false;
    const observed = new Proxy(f.db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql === PAGE_ORDINARY_KEYS_AFTER && !changed) {
          changed = true;
          writer.prepare("UPDATE entries SET text='after' WHERE thread=? AND n=1").run(f.thread);
        }
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    const reader = makeStore(observed, dir);
    assert.deepEqual(messageEntriesAfter(reader, f.thread, 0, 1).map((e) => e.text), ["before"]);
    assert.ok(changed);
    assert.deepEqual(messageEntriesAfter(reader, f.thread, 0, 1).map((e) => e.text), ["after"]);
  } finally { writer.close(); f.store.close(); rmSync(dir, { recursive: true, force: true }); }
});

for (const missingIndex of [false, true]) test(`a long old letter tail is bounded and can be prepared (missing index ${missingIndex})`, () => {
  const f = fixture();
  try {
    const letter = JSON.stringify({ way: "in", title: "Other chat", link: null });
    for (let n = 1; n <= 66; n++) f.add(n, "edit", `edit-${n}`, letter);
    f.add(67, "message", "after the edits");
    if (missingIndex) f.db.exec("DROP INDEX entries_letters");
    const reader = makeStore(f.db, ".");
    assert.throws(() => messageEntriesAfter(reader, f.thread, 0, 1), /page letter lookup pending/);
    while (!pageLetterStep(f.db, f.thread).done) { /* bounded preparation */ }
    assert.deepEqual(messageEntriesAfter(reader, f.thread, 0, 1).map((e) => e.text), ["after the edits"]);
  } finally { f.store.close(); }
});

test("an old ordinary-message index is prepared before a long edit run is crossed", () => {
  const f = fixture();
  try {
    for (let n = 1; n <= 66; n++) f.add(n, "edit", `edit-${n}`);
    f.add(67, "message", "after the edits");
    installLegacySaid(f.db);
    f.db.exec("DROP INDEX entries_said");
    installSaidState(f.db);
    const reader = makeStore(f.db, ".");
    assert.throws(() => messageEntriesAfter(reader, f.thread, 0, 1), /legacy said lookup pending/);
    while (!legacySaidStep(f.db).ready) { /* bounded preparation */ }
    while (legacySaidDrainThread(f.db, f.thread) > 0) { /* reconcile old writes */ }
    assert.deepEqual(messageEntriesAfter(reader, f.thread, 0, 1).map((e) => e.text), ["after the edits"]);
  } finally { f.store.close(); }
});

for (const edits of [64, 65]) test(`an unprepared old message lookup handles ${edits} edits`, () => {
  const f = fixture();
  try {
    for (let n = 1; n <= edits; n++) f.add(n, "edit", `edit-${n}`);
    f.add(edits + 1, "message", "kept");
    installLegacySaid(f.db);
    f.db.exec("DROP INDEX entries_said");
    installSaidState(f.db);
    const reader = makeStore(f.db, ".");
    if (edits === 64) assert.deepEqual(messageEntriesAfter(reader, f.thread, 0, 1).map((e) => e.text), ["kept"]);
    else assert.throws(() => messageEntriesAfter(reader, f.thread, 0, 1), /legacy said lookup pending/);
  } finally { f.store.close(); }
});

for (const old of ["ordinary", "letters"] as const) test(`the Router read prepares its old ${old} lookup after handover`, async () => {
  const dir = mkdtempSync(join(tmpdir(), "comma-message-after-worker-"));
  const f = fixture(join(dir, "stillfail.db"));
  const previous = Promise.withResolvers<void>();
  let readers: Readers | undefined;
  try {
    const letter = old === "letters" ? JSON.stringify({ way: "in", title: "Other chat", link: null }) : null;
    for (let n = 1; n <= 150; n++) f.add(n, "edit", `edit-${n}`, letter);
    f.add(151, "message", "kept");
    if (old === "ordinary") {
      installLegacySaid(f.db);
      f.db.exec("DROP INDEX entries_said");
      installSaidState(f.db);
    } else f.db.exec("DROP INDEX entries_letters");
    const empty = f.store.openThreadOf("ember", "CHAT", "100.empty", null, "ann@x", "a");
    f.store.joinThread(empty.id, "a", "ember");
    readers = new Readers(dir, 1, undefined, 1, { previousGone: previous.promise });
    let finished = false;
    const pending = readers.read("outflowMessages", { thread: f.thread, after: 0, limit: 1, messagesOnly: true }, "en")
      .then((value) => { finished = true; return value; });
    const other = JSON.parse(await readers.read("outflowMessages", { thread: empty.id, after: 0, limit: 1, messagesOnly: true }, "en"));
    assert.deepEqual(other.messages, []);
    assert.equal(finished, false);
    previous.resolve();
    const result = JSON.parse(await pending);
    assert.deepEqual(result.messages.map((m: any) => [m.n, m.text]), [[151, "kept"]]);
    assert.equal(result.messagesOnly, true);
  } finally {
    previous.resolve();
    readers?.close();
    f.store.close();
    rmSync(dir, { recursive: true, force: true });
  }
});

test("the messages-only option crosses the peer read and preserves workspace scope", async () => {
  const f = fixture();
  try {
    f.add(1, "message", "first");
    for (let n = 2; n <= 7; n++) f.add(n, "edit", `edit-${n}`);
    f.add(8, "message", "next");
    const reader = makeStore(f.db, "."), asked: any[] = [];
    const answer = peerRead(async (op, args, lang) => {
      asked.push(args);
      return JSON.stringify(usageOps[op]!(reader, { ...(args as any), lang }));
    }, () => "home", () => "en", () => 0, () => {});
    const reads = {
      home: () => "home",
      here: async () => { throw new Error("unexpected local read"); },
      there: async (_id: string, op: string, args: any) => textOf(bytesOf(await answer("caller", { op, args }, "home"))!),
    };
    const result = await routerReads(stats, reads, `${f.thread}@other`, 1, 5);
    assert.deepEqual(result.messages.map((m: any) => [m.seq, m.text]), [[8, "next"]]);
    assert.equal(result.through, 8);
    assert.equal(asked.length, 1);
    assert.equal(asked[0].messagesOnly, true);
    assert.deepEqual(asked[0].ws, { workspace: "home", home: true });
  } finally { f.store.close(); }
});

test("an older peer's raw pages are followed past edits", async () => {
  const f = fixture();
  try {
    f.add(1, "message", "first");
    for (let n = 2; n <= 7; n++) f.add(n, "edit", `edit-${n}`);
    f.add(8, "message", "next");
    const reader = makeStore(f.db, "."), requests: any[] = [];
    const reads = {
      home: () => "home",
      here: async () => { throw new Error("unexpected local read"); },
      there: async (id: string, op: string, args: any) => {
        assert.equal(id, "other");
        assert.equal(op, "outflowMessages");
        requests.push(args);
        return JSON.stringify(outflowMessages(reader, args.thread, args.after, args.limit));
      },
    };
    const result = await routerReads(stats, reads, `${f.thread}@other`, 1, 5);
    assert.deepEqual(result.messages.map((m: any) => [m.seq, m.text]), [[8, "next"]]);
    assert.equal(result.through, 8);
    assert.deepEqual(requests.map((r) => [r.after, r.limit, r.messagesOnly]), [[1, 5, true], [6, 100, true]]);
  } finally { f.store.close(); }
});

test("an older peer with an endless edit run is refused after a bounded number of pages", async () => {
  let calls = 0;
  const reads = {
    home: () => null,
    here: async (_op: string, args: any) => {
      calls++;
      return JSON.stringify({ messages: Array.from({ length: args.limit }, (_, i) => ({ n: args.after + i + 1, kind: "edit" })),
        more: true, last: 10000 });
    },
    there: async () => { throw new Error("unexpected peer"); },
  };
  await assert.rejects(routerReads(stats, reads, "1", 0, 1), /needs an update/);
  assert.equal(calls, 8);
});

test("a workspace change while paging an older peer prevents a Router reply", async () => {
  let allowed = true, calls = 0;
  const waiting = Promise.withResolvers<void>(), resume = Promise.withResolvers<void>();
  const reads = {
    home: () => "home",
    here: async () => { throw new Error("unexpected local read"); },
    there: async (_id: string, _op: string, args: any) => {
      if (++calls === 1) return JSON.stringify({ messages: [{ n: 1, kind: "edit" }, { n: 2, kind: "edit" }], more: true, last: 3 });
      waiting.resolve();
      await resume.promise;
      return JSON.stringify({ messages: [{ n: 3, kind: "message", text: "private", at: 3 }], more: false, last: 3 });
    },
  };
  const sent: any[] = [];
  const socket = { send: (data: string) => sent.push(JSON.parse(data)) };
  const surface = new CommaSurface({ connect: "one", server: "http://127.0.0.1", token: "test", name: "one",
    tasks: {} as never, store: {} as never, models: () => [], inScope: () => allowed,
    chats: { read: (ref, after, limit) => routerReads(stats, reads, ref, after, limit), say: async () => ({}) } });
  (surface as any).socket_ = socket;
  (surface as any).frame(socket, { type: "request", id: "read", method: "task.read", params: { task: "1@other", limit: 2 } }, () => {});
  await waiting.promise;
  allowed = false;
  resume.resolve();
  await new Promise<void>((resolve) => setImmediate(resolve));
  assert.equal(calls, 2);
  assert.equal(sent.length, 1);
  assert.equal(sent[0].type, "error");
  assert.equal(JSON.stringify(sent).includes("private"), false);
});

test("a peer cannot advance a message page with a repeated or invalid position", async () => {
  for (const reply of [
    { messages: [], more: true, last: 3 },
    { messages: [{ n: 1, kind: "edit" }, { n: 1, kind: "edit" }], more: true, last: 3 },
    { messages: [{ n: 1, kind: "edit" }], more: false, last: 0 },
    { messages: [{ n: 1, kind: "edit" }], messagesOnly: true, more: false, last: 1 },
    { messages: [], more: "yes", last: 3 },
    { messages: [], messagesOnly: true, more: true, last: 3 },
    { messages: [], messagesOnly: true, last: 3 },
  ]) {
    const reads = { home: () => null, here: async () => JSON.stringify(reply), there: async () => "null" };
    await assert.rejects(routerReads(stats, reads, "1", 0, 2), /message (cursor does not continue|answer is incomplete)/);
  }
});

test("an older peer that rolls its history back between pages is refused", async () => {
  let calls = 0;
  const reads = { home: () => null,
    here: async () => JSON.stringify(++calls === 1
      ? { messages: [{ n: 1, kind: "message", text: "old" }, { n: 2, kind: "edit" }], more: true, last: 3 }
      : { messages: [], more: false, last: 0 }),
    there: async () => "null" };
  await assert.rejects(routerReads(stats, reads, "1", 0, 2), /message answer is incomplete/);
  assert.equal(calls, 2);
});
