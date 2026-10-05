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
import { type Answers, base, entries, entry, overview, session, started, stationHost, threadView } from "./station-fixture.ts";

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

test("a_chat_at_its_end_stays_there_while_its_summary_is_ahead_of_what_is_held", async () => {
  // A message just said: the station's summary already counts it, its entry not on the device yet.
  const { host, core } = await started({ ...base(), "GET /threads": [threadView(7, 4)] });
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "thread", station: "ws/st", thread: 7 });
  await host.settle();
  apply(host, values);
  assert.deepEqual(v(values, 1).entries.map((e: { n: number }) => e.n), [1, 2, 3]);
  assert.equal(v(values, 1).end, true, "not a window short of its end: no page after it to load");
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
  assert.equal(core.inner.data.logSpan("entry", "ws/st", "7")?.count, 120);
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

test("where_a_chat_was_left_is_there_as_it_opens_after_a_restart_from_the_database", async () => {
  const first = await started();
  const ui1 = first.core.connect();
  call(first.core, ui1, 1, "chat.place", { station: "ws/st", thread: 7, seq: 2, offset: 5 });
  await first.host.settle();
  await run(first.core.inner.data.written);
  first.core.close();
  const host = first.host;
  assert.equal(host.storage.has("place/ws/st/7"), false, "not a file of its own");
  host.onFetch(() => {
    throw new HostError("offline");
  });
  host.onFetchStream(() => Effect.fail(new HostError("offline")));
  const core = await Core.create(host, { clock: host.time.clock, sample: 0, wire: () => new HostWire(host) });
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "thread", station: "ws/st", thread: 7 });
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 1).at, 2);
  assert.equal(v(values, 1).atOffset, 5);
  core.close();
});

test("where_a_chat_was_left_in_a_file_of_its_own_moves_into_the_database", async () => {
  const first = await started();
  await run(first.core.inner.data.written);
  first.core.close();
  const host = first.host;
  host.store("place/ws/st/7", { at: 2, offset: null });
  const core = await Core.create(host, { clock: host.time.clock, sample: 0, wire: () => new HostWire(host) });
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "thread", station: "ws/st", thread: 7 });
  await host.settle();
  await run(core.inner.data.written);
  assert.equal(host.storage.has("place/ws/st/7"), false);
  assert.deepEqual(core.inner.data.record("place", "ws/st/7"), { at: 2, offset: null });
  core.close();
});

test("a_chat_with_something_unread_opens_from_what_is_held_while_what_is_before_it_comes", async () => {
  const answers = base();
  answers["GET /threads"] = [threadView(7, 120, 100, 20)];
  answers["GET /threads/7/entries?limit=50"] = { last: 120, entries: entries(71, 120) };
  const { host, core } = await started(answers);
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "thread", station: "ws/st", thread: 7 });
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 1).at, 101);
  assert.deepEqual([v(values, 1).first, v(values, 1).last, v(values, 1).end], [71, 120, true]);
  core.close();
});
