// The station sync and topics (docs/core-ts.md, rules 2, 3, 6): a station is linked as its workspace is reached,
// read when its stream opens, kept current by its events; topics only read what is held.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect, Queue } from "effect";
import { Core } from "../src/core.ts";
import { HostError } from "../src/error.ts";
import type { HttpRequest, Pull } from "../src/host.ts";
import { HostWire } from "../src/station/wire.ts";
import { FakeHost, jsonResponse } from "../src/testing.ts";
import { apply, call, signIn, subscribe, v } from "./helpers.ts";
import { run } from "./run.ts";

type Answers = Record<string, unknown>;

/// A station `ws/st` answering `answers` ("GET /path" → JSON), and its events stream fed by `push`.
function stationHost(answers: Answers) {
  const host = new FakeHost();
  signIn(host);
  const streams: { path: string; queue: Queue.Queue<Uint8Array | null> }[] = [];
  host.onFetch((req: HttpRequest) => {
    const path = req.url.replace("https://stillfail.test", "");
    if (path === "/v1/me") return jsonResponse(200, { workspaces: [{ id: "ws", name: "W" }], invitations: [], relay_url: null });
    if (path === "/v1/workspaces/ws") return jsonResponse(200, { id: "ws", stations: [{ id: "st", name: "studio", online: true, last_seen: null }] });
    const key = `${req.method} ${path.replace("/admin/api", "")}`;
    if (key in answers) return jsonResponse(200, answers[key]);
    if (path.startsWith("/admin/api/threads/") && path.includes("/entries")) return jsonResponse(200, { last: 0, entries: [] });
    return jsonResponse(404, { error: "no" });
  });
  host.onFetchStream((req) =>
    Effect.gen(function* () {
      const queue = yield* Queue.unbounded<Uint8Array | null>();
      streams.push({ path: req.url.replace("https://stillfail.test/admin/api", ""), queue });
      const body: Pull<Uint8Array> = { take: Queue.take(queue) };
      return { status: 200, headers: [], body };
    }),
  );
  const push = (name: string, data: unknown) => {
    const s = streams[streams.length - 1];
    Queue.offerUnsafe(s.queue, new TextEncoder().encode(`event: ${name}\ndata: ${JSON.stringify(data)}\n\n`));
  };
  const end = () => {
    const s = streams[streams.length - 1];
    Queue.offerUnsafe(s.queue, null);
  };
  return { host, streams, push, end };
}

/// A session as the station lists it (core/tests.rs `session`).
const session = (key: string, turns = 0) => ({
  key, connect: "ember", scope: "thread", title: null, createdBy: null, boundTo: [], creator: null, participants: [], runtime: "claude", profile: "p1",
  profilePinned: false, model: null, effort: null, runtimeSessionId: null, workspace: "/w", running: false, createdAt: 1, lastActiveAt: 1, archivedAt: null,
  process: "cold", turns, pending: 0, firstText: null, lastTurn: null,
});
const overview = { viewer: { via: "local" }, connects: [], profiles: [], processes: [], counts: { sessions: 1, running: 0, warm: 0 }, mesh: null, slackUsers: [], slackTeams: [], slackApps: [], disk: null, logins: [] };
const entry = (n: number, text: string) => ({ thread: 7, n, kind: "message", target: null, ts: `${n}.0`, authorKind: "person", author: "a@x.com", text, at: n });
const entries = (from: number, to: number) => Array.from({ length: to - from + 1 }, (_, i) => entry(from + i, `m${from + i}`));
const threadView = (id: number, last: number, read = last, unread = 0) => ({
  id, surface: "ember", channel: "EMBER", channelName: null, threadTs: `${id}.0`, title: null, createdBy: null, creator: null, createdAt: id,
  sessions: [{ thread: id, session: "k1", connect: "ember", joinedAt: 1 }], last, lastMessage: last > 0 ? { seq: last, text: "…", createdAt: last } : null, read, unread, people: [], firstText: null,
});

function base(): Answers {
  return {
    "GET /overview": overview,
    "GET /sessions": [session("k1")],
    "GET /sessions/k1": { session: session("k1"), threads: [], turns: [], jobs: [] },
    "GET /threads": [threadView(7, 3)],
    "GET /chats": [{ id: "7", thread: 7, session: "k1", title: "部署", agents: [], lastActiveAt: 1 }],
    "GET /chats?archived=1": [],
    "GET /jobs": [],
    "GET /footprint": {},
    "GET /threads/7/entries?limit=50": { last: 3, entries: entries(1, 3) },
    "GET /sessions/k1/timeline?before=1000000000000000&limit=200": { start: 0, entries: [] },
  };
}

async function started(answers = base()) {
  const s = stationHost(answers);
  const core = await Core.create(s.host, { clock: s.host.time.clock, sample: 0, wire: () => new HostWire(s.host) });
  await s.host.time.pass(500);
  return { ...s, core };
}

const gets = (host: FakeHost, path: string) => host.requests.filter((r) => r.method === "GET" && r.url.endsWith(path)).length;

test("a_reached_station_is_linked_read_as_its_stream_opens_and_its_topics_read_only_what_is_held", async () => {
  const { host, core, streams } = await started();
  assert.equal(streams.length, 1, "its events stream is open");
  assert.equal(streams[0].path, "/events");
  for (const path of ["/admin/api/overview", "/admin/api/sessions", "/admin/api/threads", "/admin/api/chats"]) assert.equal(gets(host, path), 1, path);
  // Its chats' entries are brought onto the device, nobody looking.
  assert.equal(gets(host, "/admin/api/threads/7/entries?limit=50"), 1);
  const before = host.requests.length;
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "overview", station: "ws/st" });
  subscribe(core, ui, 2, { topic: "link", station: "ws/st" });
  subscribe(core, ui, 3, { topic: "thread", station: "ws/st", thread: 7 });
  await host.settle();
  apply(host, values);
  assert.equal(host.requests.length, before, "subscribing asks nothing");
  assert.deepEqual(v(values, 1).connects, []);
  assert.equal(v(values, 2).state, "online");
  assert.deepEqual(v(values, 3).entries.map((e: { n: number }) => e.n), [1, 2, 3]);
  assert.equal(v(values, 3).end, true);
  core.close();
});

test("events_keep_the_records_current", async () => {
  const { host, core, push } = await started();
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "sessions", station: "ws/st" });
  subscribe(core, ui, 2, { topic: "thread", station: "ws/st", thread: 7 });
  subscribe(core, ui, 3, { topic: "chatRows", station: "ws/st" });
  await host.settle();
  apply(host, values);
  push("session", { ...session("k1", 1), title: "改了" });
  push("thread", { id: 7, entries: [entry(4, "new")] });
  push("chat", { id: "8", thread: 8, title: "新的", agents: [], lastActiveAt: 2 });
  await host.time.pass(600);
  apply(host, values);
  assert.equal(v(values, 1)[0].title, "改了");
  assert.deepEqual(v(values, 2).entries.map((e: { n: number }) => e.n), [1, 2, 3, 4]);
  assert.equal(v(values, 2).caught, 3, "said as it came: it comes in with a motion");
  assert.deepEqual(v(values, 3).map((r: { id: string }) => r.id), ["7", "8"]);
  // A burst of thread events reads the thread's summary once.
  assert.equal(gets(host, "/admin/api/threads/7"), 1);
  core.close();
});

test("what_was_held_shows_after_a_restart_before_any_network", async () => {
  const first = await started();
  await run(first.core.inner.data.written);
  first.core.close();
  const host = first.host;
  host.onFetch(() => {
    throw new HostError("offline");
  });
  host.onFetchStream(() => Effect.fail(new HostError("offline")));
  const core = await Core.create(host, { clock: host.time.clock, sample: 0, wire: () => new HostWire(host) });
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "overview", station: "ws/st" });
  subscribe(core, ui, 2, { topic: "thread", station: "ws/st", thread: 7 });
  subscribe(core, ui, 3, { topic: "chatRows", station: "ws/st" });
  await host.settle();
  apply(host, values);
  assert.deepEqual(v(values, 1).processes, []);
  assert.deepEqual(v(values, 2).entries.map((e: { n: number }) => e.n), [1, 2, 3]);
  assert.equal(v(values, 3)[0].title, "部署");
  core.close();
});

test("a_dropped_stream_is_opened_again_and_reads_what_it_missed", async () => {
  const { host, core, end, streams } = await started();
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "link", station: "ws/st" });
  await host.settle();
  end();
  await host.time.pass(100);
  apply(host, values);
  assert.equal(v(values, 1).state, "reconnecting");
  await host.time.pass(2_500, 50);
  apply(host, values);
  assert.equal(streams.length, 2);
  assert.equal(v(values, 1).state, "online");
  assert.equal(gets(host, "/admin/api/overview"), 2, "read again as it opened");
  core.close();
});

test("a_thread_is_brought_whole_onto_the_device_from_its_latest_page_back", async () => {
  const answers = base();
  answers["GET /threads"] = [threadView(7, 120)];
  answers["GET /threads/7/entries?limit=50"] = { last: 120, entries: entries(71, 120) };
  answers["GET /threads/7/entries?from=21&to=70"] = { last: 120, entries: entries(21, 70) };
  answers["GET /threads/7/entries?from=1&to=20"] = { last: 120, entries: entries(1, 20) };
  const { host, core } = await started(answers);
  await host.time.pass(500);
  const held = core.inner.data.loaded("entry", "ws/st", "7");
  assert.equal(held?.size, 120);
  core.close();
});

test("a_chat_with_something_unread_opens_at_it_and_pages_back", async () => {
  const answers = base();
  answers["GET /threads"] = [threadView(7, 120, 100, 20)];
  answers["GET /threads/7/entries?limit=50"] = { last: 120, entries: entries(71, 120) };
  answers["GET /threads/7/entries?from=21&to=70"] = { last: 120, entries: entries(21, 70) };
  answers["GET /threads/7/entries?from=1&to=20"] = { last: 120, entries: entries(1, 20) };
  const { host, core } = await started(answers);
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "thread", station: "ws/st", thread: 7 });
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 1).at, 101);
  assert.deepEqual([v(values, 1).first, v(values, 1).last, v(values, 1).end], [51, 120, true]);
  call(core, ui, 2, "chat.older", { station: "ws/st", thread: 7 });
  await host.time.pass(100);
  apply(host, values);
  assert.equal(v(values, 1).first, 1);
  assert.equal(v(values, 1).last, 120, "the whole thread fits the window: nothing goes at the other end");
  core.close();
});

test("a_write_answers_once_what_it_touched_is_read_again", async () => {
  const answers = base();
  answers["POST /sessions/k1/stop"] = { ok: true };
  const { host, core } = await started(answers);
  const ui = core.connect();
  const before = gets(host, "/admin/api/sessions");
  call(core, ui, 9, "session.stop", { station: "ws/st", key: "k1" });
  await host.settle();
  const answer = host.takeEmitted().find(([, m]) => m.id === 9);
  assert.deepEqual(answer?.[1], { id: 9, ok: { ok: true } });
  assert.equal(gets(host, "/admin/api/sessions"), before + 1);
  assert.equal(gets(host, "/admin/api/sessions/k1"), 2);
  core.close();
});

test("a_session_at_work_is_followed_live", async () => {
  const answers = base();
  answers["GET /chats"] = [{ id: "7", thread: 7, session: "k1", title: "部署", agents: [{ key: "k1", process: "running" }], lastActiveAt: 1 }];
  const { host, core, streams, push } = await started(answers);
  await host.time.pass(200);
  assert.ok(streams[streams.length - 1].path.includes("live=k1&from=0&last=200"), streams.map((s) => s.path).join(" "));
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "live", station: "ws/st", key: "k1" });
  await host.settle();
  push("live", { key: "k1", type: "timeline", start: 0, entries: [{ kind: "text", text: "hi" }], usage: { modelCalls: 1, inputTokens: 1, cachedTokens: 0, outputTokens: 1 } });
  push("live", { key: "k1", type: "steps", steps: [{ id: "s1", step: "thinking", input: "", startedAt: 1 }], phase: { phase: "thinking", elapsedMs: 0 } });
  await host.time.pass(100);
  apply(host, values);
  assert.equal(v(values, 1).loaded, true);
  assert.deepEqual(v(values, 1).timeline, [{ kind: "text", text: "hi" }]);
  assert.equal(v(values, 1).activity.now.key, "think");
  core.close();
});
