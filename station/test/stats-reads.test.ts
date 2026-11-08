// The workspace's statistics as a Comma connect reads them of a station (read/outflow.ts), and how a station
// answers another's read of them (comma/peer.ts).
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";
import { Store, newMessage } from "../src/store/store.ts";
import { installOutflowChatIndex, outflowChatIndexStep, outflowChatScopes } from "../src/store/outflow-index.ts";
import type { InWorkspace } from "../src/store/rows.ts";
import * as read from "../src/read/store.ts";
import { outflowChats, outflowUsage } from "../src/read/outflow.ts";
import { usageOps } from "../src/read/ops-usage.ts";
import { peerRead, textOf } from "../src/comma/peer.ts";
import { bytesOf } from "../src/mesh/bus.ts";

const dirs: string[] = [];
after(() => {
  for (const d of dirs) rmSync(d, { recursive: true, force: true });
});
const tempdir = () => {
  const d = mkdtempSync(join(tmpdir(), "stats-reads-"));
  dirs.push(d);
  return d;
};

function readyChats(store: Store, viewer: InWorkspace = { workspace: "\u0000home", home: true }): void {
  installOutflowChatIndex(store.db);
  for (const scope of outflowChatScopes(viewer)) while (!outflowChatIndexStep(store.db, scope).done) { /* bounded batches */ }
}

test("v1 usage: a Feishu person's name and email as far as the names book knows them, never their id for a name", () => {
  const dir = tempdir();
  const store = Store.open(join(dir, "stillfail.db"), null);
  after(() => store.close());
  writeFileSync(join(dir, "config.json"), JSON.stringify({ connects: [{ id: "fs", kind: "feishu", feishu: {} }] }));
  writeFileSync(join(dir, "feishu-names.json"), JSON.stringify({
    "u:fs:ou_ada": { person: { name: "Ada", email: "ada@x" }, at: 1 },
    "u:fs:ou_bo": { person: { name: "Bo", email: "" }, at: 1 },
  }));
  store.insertSession({ key: "a", connect: "fs", runtime: "claude", profile: "cc", workspace: "/w/a", token: "a", createdAt: 1, lastActiveAt: 1, createdBy: "slack:fs:ou_ada", ws: null } as never);
  const thread = store.openThreadOf("feishu:fs", "oc_1", "om_1", "A group", "slack:fs:ou_ada", "a");
  store.joinThread(thread.id, "a", "feishu:fs");
  const call = (id: string) => ({ id, at: 86_400_000 + 1, model: "claude-opus-5-5", subagent: false, fast: false, input: 1, cacheRead: 0, cacheWrite: 0, cacheWriteLong: 0, output: 1, calls: 1, context: null, window: null });
  const people = ["slack:fs:ou_ada", "slack:fs:ou_bo", "slack:fs:ou_cy"];
  store.recordUsage("/a.jsonl", { session: "a", offset: 1, model: null }, "claude", people.map((person) => [call(person), { turn: null, person, thread: thread.id, profile: "cc" }]) as never);
  const usage = outflowUsage(read.openStore(dir), "en", 86_400_000, 2 * 86_400_000, 0) as any;
  assert.deepEqual(usage.people, {
    "slack:fs:ou_ada": { name: "Ada", email: "ada@x", via: "feishu" },
    "slack:fs:ou_bo": { name: "Bo", email: null, via: "feishu" },
    "slack:fs:ou_cy": { name: null, email: null, via: "feishu" },
  });
});

test("v1 reads: the home workspace's usage and chats, field by field, no message", () => {
  const dir = tempdir();
  const store = Store.open(join(dir, "stillfail.db"), null);
  after(() => store.close());
  const session = (key: string, ws: string | null) =>
    store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: `/w/${key}`, token: key, createdAt: 1, lastActiveAt: 1, createdBy: "ann@x", ws } as never);
  session("a", null);
  session("b", "other-ws");
  // Made in the app: it names the home workspace by its id.
  session("c", "ws-home");
  const home = store.openThreadOf("ember", "CHAT", "100.1", "Fix the build", "ann@x", "a");
  const away = store.openThreadOf("ember", "CHAT", "100.2", "Theirs", "bob@x", "b");
  const app = store.openThreadOf("ember", "CHAT", "100.6", "From the app", "ann@x", "c");
  store.joinThread(home.id, "a", "ember");
  store.joinThread(away.id, "b", "ember");
  store.joinThread(app.id, "c", "ember");
  store.insertMessage(newMessage(home.id, "100.3", "person", "ann@x", "a secret plan"));
  store.startTurnFor("t1", "a", "input", { profile: "cc", person: "ann@x", thread: home.id });
  store.endTurn("t1", "done", null, "all_done", null);
  const call = (id: string, at: number) => ({ id, at, model: "claude-opus-5-5", subagent: false, fast: false, input: 100, cacheRead: 40, cacheWrite: 10, cacheWriteLong: 0, output: 5, calls: 1, context: null, window: null });
  store.recordUsage("/a.jsonl", { session: "a", offset: 1, model: null }, "claude", [[call("c1", 86_400_000 + 1), { turn: "t1", person: "ann@x", thread: home.id, profile: "cc" }]] as never);
  store.recordUsage("/b.jsonl", { session: "b", offset: 1, model: null }, "claude", [[call("c2", 86_400_000 + 2), { turn: null, person: "bob@x", thread: away.id, profile: "cc" }]] as never);
  const r = read.openStore(dir);

  const usage = outflowUsage(r, "en", 86_400_000, 2 * 86_400_000, 0) as any;
  assert.deepEqual(Object.keys(usage.rows[0]).sort(), ["account", "cacheRead", "cacheWrite", "calls", "cost", "day", "input", "model", "output", "person", "runtime", "session", "thread"].sort());
  assert.deepEqual(usage.rows.map((x: any) => [x.thread, x.person, x.calls, x.input, x.cacheWrite]), [[home.id, "ann@x", 1, 100, 10]], "another workspace's chats are not the station's to give");
  assert.ok(usage.rows[0].cost > 0);
  assert.deepEqual(usage.people, { "ann@x": { name: null, email: "ann@x", via: "cloud" } });
  const otherUsage = outflowUsage(r, "en", 86_400_000, 2 * 86_400_000, 0, { workspace: "other-ws", home: false }) as any;
  assert.deepEqual(otherUsage.rows.map((x: any) => [x.session, x.thread]), [["b", away.id]]);

  readyChats(store);
  const chats = outflowChats(r, 0) as any;
  assert.deepEqual(chats.chats.map((c: any) => [c.thread, c.title, c.state, c.creator?.email, c.surface, c.archived]), [[home.id, "Fix the build", "all_done", "ann@x", "stillfail", false]]);
  assert.ok(!JSON.stringify(chats).includes("secret"), "no message");
  // Only those with something new since.
  const later = home.createdAt + 365 * 86_400_000;
  assert.deepEqual(outflowChats(r, later) as any, { since: later, chats: [] });
  // A page at a time: the latest active first, `next` asks for the rest.
  const second = store.openThreadOf("ember", "CHAT", "100.4", "Ship it", "ann@x", "a");
  store.joinThread(second.id, "a", "ember");
  store.insertMessage(newMessage(second.id, "100.5", "person", "ann@x", "ship"));
  readyChats(store);
  const all = (outflowChats(read.openStore(dir), 0) as any).chats.map((c: any) => c.thread);
  const first = outflowChats(read.openStore(dir), 0, undefined, { limit: 1, before: null }) as any;
  const rest = outflowChats(read.openStore(dir), 0, undefined, { limit: 1, before: first.next }) as any;
  assert.deepEqual([first.chats.map((c: any) => c.thread), first.more, rest.chats.map((c: any) => c.thread), rest.more, rest.next], [[all[0]], true, [all[1]], false, null]);
  assert.equal(all.length, 2);
  // Another station of a workspace this one joined reads that workspace's, as its program's grant there asks.
  readyChats(store, { workspace: "other-ws", home: false });
  const theirs = usageOps.outflowChats!(r, { since: 0, ws: { workspace: "other-ws", home: false } }) as any;
  assert.deepEqual(theirs.chats.map((c: any) => c.title), ["Theirs"]);
  const spent = usageOps.outflowUsage!(r, { lang: "en", from: 0, to: 365 * 86_400_000, tz: 0, ws: { workspace: "other-ws", home: false } }) as any;
  assert.deepEqual([spent.rows.map((x: any) => x.person), spent.to], [["bob@x"], 31 * 86_400_000], "a span of 31 days at most, whoever asks");
  // Read here with the home workspace's id: its chats made in the app too, those that say no workspace as well.
  readyChats(store, { workspace: "ws-home", home: true });
  const own = usageOps.outflowChats!(read.openStore(dir), { since: 0, ws: { workspace: "ws-home", home: true } }) as any;
  assert.deepEqual(own.chats.map((c: any) => c.title).sort(), ["Fix the build", "From the app", "Ship it"]);
});

test("listing chats for a program does not count the chat's unread history", () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w/a", token: "a", createdAt: 1, lastActiveAt: 1 });
    const thread = store.openThreadOf("ember", "CHAT", "100.1", "A chat", "ann@x", "a");
    store.joinThread(thread.id, "a", "ember");
    const entry = store.db.prepare("INSERT INTO entries (thread, n, kind, author_kind, author, text, at) VALUES (?, ?, 'message', 'person', 'ann@x', 'body', ?)");
    store.db.exec("BEGIN");
    for (let n = 1; n <= 1_000; n++) entry.run(thread.id, n, n);
    store.db.exec("COMMIT");
    store.db.prepare("UPDATE threads SET created_at = 1 WHERE id = ?").run(thread.id);
    store.db.prepare("INSERT INTO entries (thread, n, kind, target, author_kind, author, text, at) VALUES (?, 1001, 'edit', 1000, 'person', 'ann@x', 'edited', 999999)").run(thread.id);
    readyChats(store);
    const reader = read.makeStore(store.db, ".");
    const expected = outflowChats(reader, 0, undefined, { limit: 1, before: null }) as any;
    assert.equal(expected.chats[0].lastActiveAt, read.lastSaid(reader, thread.id)?.createdAt);
    assert.equal(expected.chats[0].lastActiveAt, 1_000, "an edit does not replace the message's original activity time");
    const db = reader.db;
    const traced = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql === read.UNREAD) throw new Error("counted unread history");
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    Object.defineProperty(reader, "db", { value: traced, configurable: true });
    try { assert.deepEqual(outflowChats(reader, 0, undefined, { limit: 1, before: null }), expected); }
    finally { Object.defineProperty(reader, "db", { value: db, configurable: true }); }
  } finally { store.close(); }
});

test("a chat export reads its agents' state without counting pending deliveries", () => {
  const store = Store.open(":memory:");
  try {
    store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", createdAt: 1, lastActiveAt: 1 });
    const thread = store.openThreadOf("ember", "CHAT", "pending", "Chat", "ann@x", "a");
    store.joinThread(thread.id, "a", "ember");
    const insert = store.db.prepare("INSERT INTO deliveries (thread,n,session) VALUES (?,?,'a')");
    store.db.exec("BEGIN");
    for (let n=1; n<=500; n++) insert.run(thread.id, n);
    store.db.exec("COMMIT");
    readyChats(store);
    const reader = read.makeStore(store.db, ".");
    const expected = outflowChats(reader, 0, undefined, { limit: 1, before: null });
    const db = reader.db;
    const traced = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql.includes("FROM deliveries d INDEXED BY deliveries_pending")) throw new Error("counted pending deliveries");
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    Object.defineProperty(reader, "db", { value: traced, configurable: true });
    try { assert.deepEqual(outflowChats(reader, 0, undefined, { limit: 1, before: null }), expected); }
    finally { Object.defineProperty(reader, "db", { value: db, configurable: true }); }
  } finally { store.close(); }
});

test("a shared chat's exported agents belong to the requested workspace", () => {
  const store = Store.open(":memory:");
  try {
    for (const [key, ws, runtime] of [["a", "A", "claude"], ["b", "B", "codex"], ["home", null, "gemini"]] as const) {
      store.insertSession({ key, connect: "ember", runtime, profile: "p", workspace: "/w", token: key, createdAt: 1, lastActiveAt: 1, ws });
    }
    const thread = store.openThreadOf("ember", "CHAT", "shared", "Shared", "ann@x", "a");
    for (const key of ["a", "b", "home"]) store.joinThread(thread.id, key, "ember");
    readyChats(store, { workspace: "A", home: true });
    readyChats(store, { workspace: "B", home: false });
    const reader = read.makeStore(store.db, ".");
    const a = outflowChats(reader, 0, { workspace: "A", home: true }, { limit: 1, before: null }) as any;
    const b = outflowChats(reader, 0, { workspace: "B", home: false }, { limit: 1, before: null }) as any;
    assert.deepEqual(a.chats[0].agents.map((agent: any) => agent.runtime), ["claude", "gemini"]);
    assert.deepEqual(b.chats[0].agents.map((agent: any) => agent.runtime), ["codex"]);
  } finally { store.close(); }
});

test("export pages merge home and workspace chats once, including tied activity times", () => {
  const store = Store.open(":memory:");
  try {
    for (const [key, ws] of [["home", null], ["a", "A"], ["b", "B"]] as const)
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key, createdAt: 1, lastActiveAt: 1, ws });
    for (const [name, members] of [["one", ["a", "home"]], ["two", ["a"]], ["three", ["home"]], ["four", ["a", "home"]], ["away", ["b"]]] as const) {
      const thread = store.openThreadOf("ember", "CHAT", name, name, "ann@x", members[0]!);
      for (const member of members) store.joinThread(thread.id, member, "ember");
      store.db.prepare("UPDATE threads SET created_at=10 WHERE id=?").run(thread.id);
    }
    const viewer = { workspace: "A", home: true };
    readyChats(store, viewer);
    const reader = read.makeStore(store.db, ".");
    const first = outflowChats(reader, 10, viewer, { limit: 2, before: null }) as any;
    const second = outflowChats(reader, 10, viewer, { limit: 2, before: first.next }) as any;
    assert.deepEqual(first.chats.map((chat: any) => chat.title), ["four", "three"]);
    assert.deepEqual(second.chats.map((chat: any) => chat.title), ["two", "one"]);
    assert.deepEqual([first.more, second.more, second.next], [true, false, null]);
    assert.deepEqual((outflowChats(reader, 11, viewer) as any).chats, []);
  } finally { store.close(); }
});

test("a page of exported chats does not enumerate every session", () => {
  const store = Store.open(":memory:");
  try {
    for (const key of ["a", "b", "c"]) {
      store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key,
        createdAt: 1, lastActiveAt: 1, ws: "A" });
      const thread = store.openThreadOf("ember", "CHAT", `chat-${key}`, key, "ann@x", key);
      store.joinThread(thread.id, key, "ember");
      store.db.prepare("UPDATE threads SET created_at = 10 WHERE id = ?").run(thread.id);
    }
    store.db.exec("BEGIN");
    for (let i = 0; i < 200; i++) store.insertSession({ key: `other-${i}`, connect: "ember", runtime: "claude", profile: "cc",
      workspace: "/w", token: `other-${i}`, createdAt: 1, lastActiveAt: 1, ws: "B" });
    store.db.exec("COMMIT");
    const reader = read.makeStore(store.db, "."), viewer = { workspace: "A", home: false };
    readyChats(store, viewer);
    const first = outflowChats(reader, 0, viewer, { limit: 1, before: null }) as any;
    const second = outflowChats(reader, 0, viewer, { limit: 1, before: first.next }) as any;
    assert.deepEqual(first.chats.map((chat: any) => chat.title), ["c"]);
    assert.deepEqual(second.chats.map((chat: any) => chat.title), ["b"]);
    const db = reader.db;
    const traced = new Proxy(db, { get(target, property) {
      if (property === "prepare") return (sql: string) => {
        if (sql === "SELECT * FROM sessions ORDER BY last_active_at DESC") throw new Error("enumerated session history");
        return target.prepare(sql);
      };
      const value = Reflect.get(target, property, target);
      return typeof value === "function" ? value.bind(target) : value;
    } });
    Object.defineProperty(reader, "db", { value: traced, configurable: true });
    try {
      assert.deepEqual(outflowChats(reader, 0, viewer, { limit: 1, before: null }), first);
      assert.deepEqual(outflowChats(reader, 0, viewer, { limit: 1, before: first.next }), second);
    } finally { Object.defineProperty(reader, "db", { value: db, configurable: true }); }
  } finally { store.close(); }
});

test("another station's read: one of the statistics reads, of the workspace it asks in, its answer as bytes", async () => {
  const asked: [string, any][] = [];
  const answer = peerRead(async (op, args) => (asked.push([op, args]), JSON.stringify({ chats: [{ thread: 3 }] })), () => "ws-home", () => "en");
  const got = await answer("peer", { method: "outflow.read", op: "outflowChats", args: { since: 7, ws: { workspace: "forged", home: true } } }, "ws-home");
  assert.deepEqual(JSON.parse(await textOf(bytesOf(got)!)), { chats: [{ thread: 3 }] });
  assert.deepEqual(asked, [["outflowChats", { since: 7, lang: "en", ws: { workspace: "ws-home", home: true } }]], "the workspace is the transport's, never the request's");
  await answer("peer", { op: "outflowUsage", args: { from: 0, to: 1 } }, "ws-joined");
  assert.deepEqual(asked.at(-1)![1].ws, { workspace: "ws-joined", home: false });
  await assert.rejects(answer("peer", { op: "usage", args: {} }, "ws-home"), /no such read/, "none of the station's other reads");
  await assert.rejects(answer("peer", { op: "outflowChats", args: {} }, undefined), /workspace/);
});
