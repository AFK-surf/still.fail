// The workspace's statistics a Comma connect sends (comma/stats.ts): kept as rows numbered as they change, read of this
// station and the others of its workspace (comma/peer.ts), and sent a page at a time as Comma holds them, against a
// stand-in for Comma's connector socket on a local port. Nothing reaches the real Comma.
import assert from "node:assert/strict";
import { createServer } from "node:http";
import type { AddressInfo } from "node:net";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { after, test } from "node:test";
import { WebSocketServer } from "ws";
import { workspaceRead } from "../src/comma/peer.ts";
import { CommaStats, PAGE_BYTES, PAGE_ROWS, type RevIndex, type StationRows, chatOf, chatRef, heldFrom, nextPage, probePage, taskWire } from "../src/comma/stats.ts";
import { routerSays } from "../src/comma/chats.ts";
import { CommaSurface } from "../src/comma/surface.ts";
import { CommaTasks } from "../src/comma/tasks.ts";
import { Rig } from "./hub-fakes.ts";
import { newMessage } from "../src/store/store.ts";
import { installOutflowChatIndex, outflowChatIndexStep, outflowChatScopes } from "../src/store/outflow-index.ts";
import * as read from "../src/read/store.ts";
import { HOME, outflowChats } from "../src/read/outflow.ts";

type Json = any;

const dirs: string[] = [];
after(() => {
  for (const d of dirs) rmSync(d, { recursive: true, force: true });
});
const tempdir = () => {
  const d = mkdtempSync(join(tmpdir(), "comma-stats-"));
  dirs.push(d);
  return d;
};

const DAY = 24 * 60 * 60_000;
const FROM = Date.UTC(2026, 10, 1);
const usageRow = (day: string, session: string, person: string, calls = 1) => ({
  day, session, thread: 7, person, account: "cc", runtime: "claude", model: "claude-opus-5-5", calls, input: 10, cacheRead: 0, cacheWrite: 0, output: 5, cost: 0.01,
});
const chat = (thread: number, state: string) => ({
  thread, surface: "stillfail", title: "Fix the build", state, creator: { ref: "ann@x", name: null, email: "ann@x", via: "cloud" }, createdAt: FROM, lastActiveAt: FROM + 1, archived: false, agents: [{ runtime: "claude", model: null }],
});
const here = (rows: Json[], people: Json = {}, chats: Json[] = []): StationRows => ({ usage: { rows, people }, chats });
const nothing = async () => ({ stations: [], unread: [] });
const quiet = () => () => {};

const rows = (index: RevIndex) => index.since(0, 1000).map((r) => ({ kind: r.kind, removed: r.removed, row: r.removed ? null : JSON.parse(r.json) }));

test("the index keeps each station's rows as they changed: a person by their email, a chat by its thread, a row gone tombstoned, an unread station's kept", () => {
  const stats = CommaStats.at(tempdir(), nothing, quiet);
  try {
    const people = { "slack:fs:ou_ada": { name: "Ada", email: "ada@x", via: "feishu" }, "slack:fs:ou_bo": { name: "Bo", email: null, via: "feishu" } };
    const first = [
      here([usageRow("2026-11-01", "a", "slack:fs:ou_ada"), usageRow("2026-11-02", "a", "slack:fs:ou_bo")], people, [chat(7, "need_human")]),
      { station: "st-there", ...here([usageRow("2026-11-02", "b", "ann@x")]) },
    ];
    assert.deepEqual(stats.apply(first, [], FROM), { stats: 4, tasks: 1 });
    const kept = rows(stats.stats);
    assert.deepEqual(kept.filter((r) => r.kind === "usage").map((r) => [r.row.person, r.row.personRef, r.row.station ?? null]), [
      ["ada@x", "slack:fs:ou_ada", null], ["Bo", "slack:fs:ou_bo", null], ["ann@x", "ann@x", "st-there"],
    ]);
    assert.deepEqual(kept.filter((r) => r.kind === "task").map((r) => [r.row.thread, r.row.state, r.row.creator]), [[7, "need_human", "ann@x"]]);
    const rev = stats.stats.rev();
    assert.deepEqual(stats.apply(first, [], FROM), { stats: 0, tasks: 0 }, "given again unchanged: nothing moves");
    assert.equal(stats.stats.rev(), rev);

    // Bo's day is another's after all, and the other station could not be read this time.
    assert.deepEqual(stats.apply([here([usageRow("2026-11-01", "a", "slack:fs:ou_ada")], people, [chat(7, "all_done")])], ["st-there"], FROM), { stats: 2, tasks: 1 });
    const now = rows(stats.stats);
    assert.equal(now.filter((r) => r.removed).length, 1, "Bo's row is gone");
    assert.ok(now.some((r) => r.row?.station === "st-there"), "the unread station's row stays");
    assert.ok(now.some((r) => r.kind === "task" && r.row.state === "all_done"));
    // A day before the build's span is never tombstoned by it.
    assert.equal(stats.apply([here([], people, [])], [], FROM + 2 * DAY).stats, 0);
  } finally { stats.close(); }
});

test("pages bring Comma from what it holds to the index's rev, at most a page's rows each; tombstones go once every connection holds them", () => {
  const stats = CommaStats.at(tempdir(), nothing, quiet);
  try {
    const many = Array.from({ length: PAGE_ROWS + 5 }, (_, i) => usageRow("2026-11-02", `s${i}`, "ann@x"));
    stats.apply([here(many)], [], FROM);
    const probe = probePage(stats.stats);
    assert.deepEqual([probe.rows.length, probe.since, probe.through], [0, stats.stats.rev(), stats.stats.rev()]);
    // A Comma holding nothing of this epoch: all again, from the start, a page within Comma's bounds at a time.
    const first = nextPage(stats.stats, { epoch: null, through: 0 })!;
    assert.deepEqual([first.reset, first.since], [true, 0]);
    let page: ReturnType<typeof nextPage> = first;
    let held = { epoch: first.epoch as string | null, through: 0 };
    let sent = 0;
    while (page !== null) {
      assert.ok(page.rows.length <= PAGE_ROWS && Buffer.byteLength(JSON.stringify(page.rows)) <= PAGE_BYTES);
      assert.equal(page.since, held.through);
      sent += page.rows.length;
      held = { epoch: page.epoch, through: page.through };
      page = nextPage(stats.stats, held);
    }
    assert.deepEqual([sent, held.through], [many.length, stats.stats.rev()]);
    stats.apply([here(many.slice(1))], [], FROM);
    assert.equal(stats.stats.since(0, 1000).filter((r) => r.removed).length, 1);
    stats.stats.held("two", 0);
    stats.stats.held("one", stats.stats.rev());
    assert.equal(stats.stats.since(0, 1000).filter((r) => r.removed).length, 1, "another connection does not hold it yet");
    stats.stats.held("two", stats.stats.rev());
    assert.equal(stats.stats.since(0, 1000).filter((r) => r.removed).length, 0);
    assert.deepEqual(heldFrom({ epoch: "e", through: 3 }), { epoch: "e", through: 3 });
    assert.equal(heldFrom("no"), null);
  } finally { stats.close(); }
});

test("a build reads this station's usage and chats of the home workspace and each other station's; one that does not answer is unread", async () => {
  const asked: [string, string, Json][] = [];
  const answer = (station: string, op: string, args: Json) => {
    asked.push([station, op, args]);
    if (station === "st-down") throw new Error("not reachable");
    if (op === "outflowUsage") return JSON.stringify({ rows: [usageRow("2026-11-02", `${station}-s`, "ann@x")], people: {} });
    // Chats a page at a time: the first page says there are more.
    return JSON.stringify(args.before === undefined ? { chats: [chat(1, "working")], more: true, next: "5.1" } : { chats: [chat(2, "waiting")], more: false, next: null });
  };
  const read = workspaceRead({
    of: () => ({ workspace: "ws-home", home: true }),
    here: async (op, args) => answer("", op, args),
    others: async () => ["st-there", "st-down"],
    there: async (station, op, args) => answer(station, op, args),
  });
  const got = await read(FROM, FROM + DAY);
  assert.deepEqual(got.unread, ["st-down"]);
  assert.deepEqual(got.stations.map((s) => [s.station ?? "", s.usage.rows.length, s.chats.map((c: Json) => c.thread)]), [["", 1, [1, 2]], ["st-there", 1, [1, 2]]]);
  assert.deepEqual(asked[0], ["", "outflowUsage", { from: FROM, to: FROM + DAY, tz: 0, ws: { workspace: "ws-home", home: true } }]);
  assert.deepEqual(asked.filter(([s, op]) => s === "st-there" && op === "outflowChats").map(([, , a]) => a.before ?? null), [null, "5.1"]);
});

test("a build of a workspace the station joined reads that workspace's chats here and its other stations'", async () => {
  const asked: [string, string, Json][] = [];
  const answer = (station: string, op: string, args: Json) => {
    asked.push([station, op, args]);
    if (op === "outflowUsage") return JSON.stringify({ rows: [usageRow("2026-11-02", `${station}-s`, "ann@x")], people: {} });
    return JSON.stringify({ chats: [chat(3, "working")], more: false, next: null });
  };
  const read = workspaceRead({
    of: () => ({ workspace: "ws-joined", home: false }),
    here: async (op, args) => answer("", op, args),
    others: async () => ["st-joined"],
    there: async (station, op, args) => answer(station, op, args),
  });
  const got = await read(FROM, FROM + DAY);
  assert.deepEqual(got.stations.map((s) => [s.station ?? "", s.usage.rows.length, s.chats.map((c: Json) => c.thread)]), [["", 1, [3]], ["st-joined", 1, [3]]]);
  assert.deepEqual(asked.filter(([s]) => s === "").map(([, , a]) => a.ws), [{ workspace: "ws-joined", home: false }, { workspace: "ws-joined", home: false }]);
});

test("connected, the station sends Comma what it lacks of the statistics, and again as they change; a Comma from before ends it", async () => {
  const pages: Json[] = [];
  const tasks: Json[] = [];
  let refuse = false;
  let held: Json = { epoch: null, through: 0 };
  const wss = new WebSocketServer({ noServer: true });
  const server = createServer((_req, res) => res.writeHead(404).end());
  let metadata: Json = null;
  let comma: import("ws").WebSocket | null = null;
  const answers = new Map<string, Json>();
  server.on("upgrade", (req, socket, head) =>
    wss.handleUpgrade(req, socket, head, (ws) => {
      comma = ws;
      ws.on("message", (data) => {
        const f = JSON.parse(String(data));
        if (f.type === "response" || f.type === "error") answers.set(f.id, f);
        if (f.type === "metadata") metadata = f;
        if (f.type !== "request") return;
        if (f.method === "task.index") tasks.push(f.params);
        if (f.method !== "stats.index") return void ws.send(JSON.stringify({ id: f.id, type: "response", result: {} }));
        pages.push(f.params);
        if (refuse) return void ws.send(JSON.stringify({ id: f.id, type: "error", error: "unknown method" }));
        if (f.params.reset || f.params.epoch === held.epoch) held = { epoch: f.params.epoch, through: f.params.through };
        ws.send(JSON.stringify({ id: f.id, type: "response", result: held }));
      });
      ws.send(JSON.stringify({ type: "connected", connector_run_id: "run_1", device_id: "dev_1" }));
    }),
  );
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  const rig = new Rig();
  const dir = tempdir();
  let builds = 0;
  let previousExited!: () => void;
  const previous = new Promise<void>((resolve) => { previousExited = resolve; });
  const stats = CommaStats.at(dir, async () => (builds++, { stations: [here([usageRow("2026-11-02", "a", "ann@x")], {}, [chat(7, "need_human")])], unread: [] }), quiet, previous);
  const old = new DatabaseSync(join(dir, "comma-stats.db"));
  let locked = false;
  let guardAttempts = 0;
  const following = stats.stats.following.bind(stats.stats);
  stats.stats.following = () => { guardAttempts++; return following(); };
  const asked: Json[] = [];
  const chats = {
    read: async (ref: string, after: number, limit: number) => (asked.push(["read", ref, after, limit]), { title: "Fix", messages: [], through: 3 }),
    say: async (ref: string, text: string, key: string, requester: string, connect: string) => (asked.push(["say", ref, text, key, requester, connect]), { seq: 4 }),
  };
  const surface = new CommaSurface({ connect: "cm", server: base, token: "salix_conn_test123", name: "mac", tasks: new CommaTasks(join(dir, "tasks.json")), store: rig.store, models: () => [], stats, chats });
  const until = async (f: () => boolean) => {
    for (let i = 0; i < 500 && !f(); i++) await new Promise((r) => setTimeout(r, 10));
    assert.ok(f());
  };
  try {
    await surface.start(async () => {});
    await until(() => metadata !== null);
    assert.deepEqual([pages.length, tasks.length], [0, 0], "the old process may still send its own epoch");
    await stats.settled();
    old.exec("BEGIN IMMEDIATE"); locked = true;
    previousExited();
    await until(() => guardAttempts > 0);
    assert.deepEqual([pages.length, tasks.length], [0, 0], "a locked index is retried before it is sent");
    old.exec("ROLLBACK"); locked = false;
    await until(() => metadata !== null && held.through > 0);
    assert.deepEqual([metadata.capabilities.stats_index, metadata.capabilities.task_index], [1, 1]);
    assert.equal(builds, 1, "connected: built once");
    const sent = pages.flatMap((p) => p.rows);
    assert.deepEqual(sent.map((r: Json) => [r.source, r.kind]), [["stillfail", "usage"], ["stillfail", "task"]]);
    // The chats go as Comma's Task index too, a Task waiting for its person as needs_review.
    await until(() => tasks.some((p) => p.rows.length > 0));
    assert.deepEqual(tasks.flatMap((p) => p.rows).map((r: Json) => [r.thread, r.task, r.status, r.created_by]), [["7", "7", "needs_review", "ann@x"]]);

    // The Router reads a chat of the index and writes in it.
    const request = async (id: string, method: string, params: Json) => {
      comma!.send(JSON.stringify({ id, type: "request", method, params }));
      await until(() => answers.has(id));
      return answers.get(id);
    };
    assert.deepEqual((await request("r1", "task.read", { task: "7", after: 1, limit: 500 })).result, { title: "Fix", messages: [], through: 3 });
    assert.deepEqual((await request("r2", "task.say", { task: "7", text: "选 main", key: "k1", requester: "Router", requester_name: "星火工作室" })).result, { seq: 4 });
    assert.match((await request("r3", "task.say", { task: "7", text: " " })).error, /text/);
    assert.deepEqual(asked, [["read", "7", 1, 100], ["say", "7", "选 main", "k1", "星火工作室", "cm"]]);

    // Changed: the next page carries only what changed.
    stats.apply([here([usageRow("2026-11-02", "a", "ann@x", 2)], {}, [chat(7, "need_human")])], [], FROM);
    const before = pages.length;
    await until(() => held.through === stats.stats.rev());
    assert.deepEqual(pages.slice(before).flatMap((p) => p.rows).map((r: Json) => r.row.calls), [2]);

    // A Comma that does not take the pages: no more are sent.
    refuse = true;
    stats.apply([here([usageRow("2026-11-02", "a", "ann@x", 3)], {}, [chat(7, "need_human")])], [], FROM);
    await until(() => pages.at(-1)?.through === stats.stats.rev());
    const last = pages.length;
    stats.apply([here([usageRow("2026-11-02", "a", "ann@x", 4)], {}, [chat(7, "need_human")])], [], FROM);
    await new Promise((r) => setTimeout(r, 1500));
    assert.equal(pages.length, last);
  } finally {
    if (locked) old.exec("ROLLBACK");
    old.close();
    await surface.stop();
    stats.close();
    wss.close();
    await new Promise<void>((resolve) => server.close(() => resolve()));
    await rig.hub.shutdown();
  }
});

test("closing a Comma connection stops retrying a locked index guard", async () => {
  const wss = new WebSocketServer({ noServer: true });
  const server = createServer((_req, res) => res.writeHead(404).end());
  let metadata = false, closed = false, indexRequests = 0;
  server.on("upgrade", (req, socket, head) => wss.handleUpgrade(req, socket, head, (ws) => {
    ws.on("close", () => { closed = true; });
    ws.on("message", (data) => {
      const frame = JSON.parse(String(data));
      if (frame.type === "metadata") metadata = true;
      if (frame.type !== "request") return;
      if (frame.method === "stats.index" || frame.method === "task.index") indexRequests++;
      ws.send(JSON.stringify({ id: frame.id, type: "response", result: {} }));
    });
    ws.send(JSON.stringify({ type: "connected", connector_run_id: "run_1", device_id: "dev_1" }));
  }));
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const rig = new Rig(), dir = tempdir();
  let previousExited!: () => void;
  const previous = new Promise<void>((resolve) => { previousExited = resolve; });
  const stats = CommaStats.at(dir, nothing, quiet, previous);
  const old = new DatabaseSync(join(dir, "comma-stats.db"));
  let locked = false, attempts = 0;
  const following = stats.stats.following.bind(stats.stats);
  stats.stats.following = () => { attempts++; return following(); };
  const surface = new CommaSurface({ connect: "cm", server: `http://127.0.0.1:${(server.address() as AddressInfo).port}`, token: "salix_conn_test123", name: "mac", tasks: new CommaTasks(join(dir, "tasks.json")), store: rig.store, models: () => [], stats });
  const until = async (f: () => boolean) => {
    for (let i = 0; i < 500 && !f(); i++) await new Promise((r) => setTimeout(r, 10));
    assert.ok(f());
  };
  try {
    await surface.start(async () => {});
    await until(() => metadata);
    await stats.settled();
    old.exec("BEGIN IMMEDIATE"); locked = true;
    previousExited();
    await until(() => attempts > 0);
    await surface.stop();
    await until(() => closed);
    const stoppedAt = attempts;
    old.exec("ROLLBACK"); locked = false;
    await new Promise((r) => setTimeout(r, 100));
    assert.equal(attempts, stoppedAt);
    assert.equal(indexRequests, 0);
  } finally {
    if (locked) old.exec("ROLLBACK");
    old.close();
    await surface.stop();
    stats.close();
    wss.close();
    await new Promise<void>((resolve) => server.close(() => resolve()));
    await rig.hub.shutdown();
  }
});

test("the Task index: a chat of this station by its thread, another station's with it; how it stands as a Task's status; a chat gone tombstoned, an unread station's kept", () => {
  const stats = CommaStats.at(tempdir(), nothing, quiet);
  try {
    stats.apply([here([], {}, [chat(7, "need_human"), chat(8, "working"), { ...chat(9, "all_done"), archived: true }]), { station: "st-there", ...here([], {}, [chat(3, "all_done")]) }], [], FROM);
    assert.deepEqual(rows(stats.tasks).map((r) => [r.row.task, r.row.status]), [["7", "needs_review"], ["8", "in_progress"], ["9", "archived"], ["3@st-there", "done"]]);
    assert.deepEqual([chatOf(chatRef(3, "st-there")), chatOf("7"), chatOf("x")], [{ thread: 3, station: "st-there" }, { thread: 7, station: null }, null]);
    const wire = stats.tasks.since(0, 10).map(taskWire);
    assert.deepEqual(Object.keys(wire[0]!).sort(), ["created_at", "created_by", "labels", "last_activity_at", "model", "rev", "runtime", "status", "task", "thread", "title"]);
    stats.apply([here([], {}, [chat(7, "need_human")])], ["st-there"], FROM);
    assert.deepEqual(rows(stats.tasks).filter((r) => r.removed).length, 2, "8 and 9 are gone, the unread station's stays");
    assert.ok(rows(stats.tasks).some((r) => r.row?.task === "3@st-there"));
  } finally { stats.close(); }
});

test("the Task index says what a chat asks of whom now, within Comma's bounds, and its link; nothing of an archived chat's, nor of a station from before", () => {
  const stats = CommaStats.at(tempdir(), nothing, quiet);
  try {
    const many = Array.from({ length: 12 }, (_, i) => `P${i}@X`);
    stats.apply([here([], {}, [
      { ...chat(7, "need_human"), attention: { kind: "need", waitsFor: ["Bob@X", "bob@x", "not an email", "x".repeat(200) + "@x"], note: "Should 1389 ship?" }, url: "https://still.fail/o/ws/st/a" },
      { ...chat(8, "all_done"), attention: { kind: "done", waitsFor: ["ann@x"], note: "\u{1F600}".repeat(400) } },
      { ...chat(9, "ended"), attention: { kind: "failed", waitsFor: many, note: null }, url: "http://localhost/o/ws/st/c" },
      { ...chat(10, "all_done"), archived: true, attention: { kind: "done", waitsFor: ["ann@x"], note: "Merged" }, url: "https://still.fail/o/ws/st/d" },
      { ...chat(11, "working"), attention: { kind: "nudge", waitsFor: ["ann@x"], note: "hi" }, url: `https://still.fail/${"x".repeat(500)}` },
      chat(12, "all_done"),
    ])], [], FROM);
    const wire = new Map(stats.tasks.since(0, 10).map(taskWire).map((w: Json) => [w.task, w]));
    const need = wire.get("7");
    assert.deepEqual([need.attention, need.waits_for, need.note, need.url, need.status], ["need", ["bob@x"], "Should 1389 ship?", "https://still.fail/o/ws/st/a", "needs_review"]);
    const done = wire.get("8");
    assert.deepEqual([done.attention, done.waits_for, [...done.note].length, done.url], ["done", ["ann@x"], 300, undefined], "a note of 300 characters at most, by code point");
    const failed = wire.get("9");
    assert.deepEqual([failed.attention, failed.waits_for, "note" in failed, "url" in failed], ["failed", many.slice(0, 8).map((m) => m.toLowerCase()), false, false], "8 at most; a link only https");
    const archived = wire.get("10");
    assert.deepEqual([archived.status, "attention" in archived, "waits_for" in archived, "note" in archived, archived.url], ["archived", false, false, false, "https://still.fail/o/ws/st/d"]);
    const odd = wire.get("11");
    assert.deepEqual(["attention" in odd, "url" in odd], [false, false], "a kind Comma does not know, a link too long: none");
    assert.deepEqual(Object.keys(wire.get("12")).sort(), ["created_at", "created_by", "labels", "last_activity_at", "model", "rev", "runtime", "status", "task", "thread", "title"], "a station from before: the row as it was");
    // A row of the largest still fits Comma's page of bytes, and pages are cut by bytes.
    const big = Array.from({ length: PAGE_ROWS }, (_, i) => ({ ...chat(100 + i, "need_human"), title: "\u{1F600}".repeat(200),
      attention: { kind: "need", waitsFor: Array.from({ length: 8 }, (_, j) => `${"p".repeat(190)}${j}@x.io`), note: "\u{1F600}".repeat(300) },
      url: `https://still.fail/${"u".repeat(480)}` }));
    stats.apply([here([], {}, big)], [], FROM);
    const page = nextPage(stats.tasks, { epoch: null, through: 0 }, taskWire)!;
    assert.ok(page.rows.length > 1 && page.rows.length < PAGE_ROWS);
    assert.ok(Buffer.byteLength(JSON.stringify(page.rows)) <= PAGE_BYTES);
    assert.equal(page.rows[0].waits_for.length, 8);
  } finally { stats.close(); }
});

test("the Router writes in a chat of the workspace as itself, once per key; a chat of another workspace or a Slack thread is refused", async () => {
  const rig = new Rig();
  const stats = CommaStats.at(tempdir(), nothing, quiet);
  try {
    rig.store.insertSession({ key: "a", connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: "a", createdAt: 1, lastActiveAt: 1, ws: null } as never);
    const thread = rig.store.openThreadOf("ember", "CHAT", "chat", "A chat", "ann@x", "a");
    rig.store.joinThread(thread.id, "a", "ember");
    const home = rig.hub.wsOf("a");
    const w = { thread: thread.id, text: "选 main", key: "cm:k1", requester: "Router", connect: "cm" };
    const n = routerSays(rig.hub, stats, home, w);
    assert.equal(routerSays(rig.hub, stats, home, w), n, "the same key: the same message");
    const said = rig.store.entriesAfter(thread.id, 0).filter((e) => e.kind === "message");
    assert.deepEqual(said.map((e) => [e.authorKind, e.author, e.text]), [["person", "slack:cm:Router", "选 main"]]);
    assert.throws(() => routerSays(rig.hub, stats, "another-ws", { ...w, key: "cm:k2" }), /no such chat/);
    const slack = rig.store.openThread("slack:ember", "C1", "100.1", null, null);
    assert.throws(() => routerSays(rig.hub, stats, home, { ...w, thread: slack.id, key: "cm:k3" }));
  } finally {
    stats.close();
    await rig.hub.shutdown();
  }
});

test("the Task index says which chats a Comma Router wrote in, with a key or without, after its idempotency record is gone; nothing of the others, nor of a station from before", async () => {
  const rig = new Rig();
  const stats = CommaStats.at(tempdir(), nothing, quiet);
  try {
    const chatOfKey = (key: string) => {
      rig.store.insertSession({ key, connect: "ember", runtime: "claude", profile: "cc", workspace: "/w", token: key, createdAt: 1, lastActiveAt: 1, ws: null } as never);
      const thread = rig.store.openThreadOf("ember", "CHAT", key, key, "ann@x", key);
      rig.store.joinThread(thread.id, key, "ember");
      return thread.id;
    };
    const keyed = chatOfKey("keyed");
    const unkeyed = chatOfKey("unkeyed");
    const people = chatOfKey("people");
    const home = rig.hub.wsOf("keyed");
    routerSays(rig.hub, stats, home, { thread: keyed, text: "选 main", key: "cm:k1", requester: "Router", connect: "cm" });
    routerSays(rig.hub, stats, home, { thread: unkeyed, text: "ship it", key: "", requester: "Ops", connect: "cm" });
    rig.store.insertMessage(newMessage(people, "people.1", "person", "ann@x", "please"));
    // The idempotency record is cleaned up after BUILD_DAYS: what the index says does not go with it.
    rig.store.db.exec("DELETE FROM comma_router_once_targets; DELETE FROM comma_router_once;");
    installOutflowChatIndex(rig.store.db);
    for (const scope of outflowChatScopes(HOME)) while (!outflowChatIndexStep(rig.store.db, scope).done) { /* bounded batches */ }
    const got = outflowChats(read.makeStore(rig.store.db, rig.dir), 0) as Json;
    const by = new Map<number, Json>(got.chats.map((c: Json) => [c.thread, c]));
    assert.deepEqual([by.get(keyed).router, by.get(unkeyed).router, "router" in by.get(people)], [true, true, false]);

    // As the Task index carries it; a row that comes to say it is a row changed, which Comma is sent again.
    const before = got.chats.map((c: Json) => (c.thread === people ? c : { ...c, router: undefined }));
    stats.apply([here([], {}, before)], [], FROM);
    const rev = stats.tasks.rev();
    assert.ok(stats.tasks.since(0, 10).map(taskWire).every((w: Json) => !("router" in w)), "a station from before: no field");
    assert.equal(stats.apply([here([], {}, got.chats)], [], FROM).tasks, 2);
    const wire = new Map(stats.tasks.since(rev, 10).map(taskWire).map((w: Json) => [w.task, w]));
    assert.deepEqual([...wire.keys()].sort(), [String(keyed), String(unkeyed)].sort());
    assert.ok([...wire.values()].every((w: Json) => w.router === true && w.rev > rev));
    assert.deepEqual(stats.apply([here([], {}, [{ ...by.get(people), router: "yes" }, by.get(keyed), by.get(unkeyed)])], [], FROM).tasks, 0, "only true says it");
  } finally {
    stats.close();
    await rig.hub.shutdown();
  }
});
