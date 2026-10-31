// The station sync and topics (docs/core-ts.md, rules 2, 3, 6): a station is linked as its workspace is reached,
// read when its stream opens, kept current by its events; topics only read what is held.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect, Queue } from "effect";
import { RUNTIMES } from "../src/format.ts";
import { Core } from "../src/core.ts";
import { HostError } from "../src/error.ts";
import type { HttpRequest, Pull } from "../src/host.ts";
import { HostWire } from "../src/station/wire.ts";
import { FakeHost, jsonResponse } from "../src/testing.ts";
import { answers as answered, apply, call, readsOf, signIn, subscribe, v } from "./helpers.ts";
import { run } from "./run.ts";
import { type Answers, base, entries, entry, overview, session, started, stationHost, stationLater, threadView } from "./station-fixture.ts";

const gets = (host: FakeHost, path: string) => host.requests.flatMap(readsOf).filter((url) => url.endsWith(path)).length;

test("a_reached_station_is_linked_read_as_its_stream_opens_and_its_topics_read_only_what_is_held", async () => {
  const { host, core, streams } = await started();
  assert.equal(streams.length, 1, "its events stream is open");
  const read = host.requests.find(r => r.url.endsWith("/admin/api/overview"));
  assert.equal(read?.headers.find(([key]) => key === "stillfail-runtimes")?.[1], RUNTIMES.join(","));
  assert.equal(streams[0].path, "/events?running=1");
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

test("a_chat_window_holds_WINDOW_of_what_it_shows_so_a_chat_mostly_of_letters_keeps_both_its_ends", async () => {
  // Agents writing each other (letters, not shown in the chat): 300 entries, 3 of them shown. Its window holds WINDOW
  // of what it shows: paging back keeps its end, paging on its start (by entries, each dropped what the other brought,
  // what was in view going and coming back, on and on). All of them shown, what is past WINDOW goes at the other end.
  const opened = async (letters: boolean, read: number, unread: number) => {
    const of = (from: number, to: number) => entries(from, to).map((e) => (!letters || [1, 120, 300].includes(e.n) ? e : { ...e, authorKind: "agent", author: "k1", letter: { way: "out", title: "备份", link: null } }));
    const answers = base();
    answers["GET /threads"] = [threadView(7, 300, read, unread)];
    answers["GET /threads/7/entries?limit=50"] = { last: 300, entries: of(251, 300) };
    for (let from = 1; from <= 251; from += 50) answers[`GET /threads/7/entries?from=${from}&to=${from + 49}`] = { last: 300, entries: of(from, from + 49) };
    const { host, core } = await started(answers);
    const ui = core.connect();
    const values = new Map();
    subscribe(core, ui, 1, { topic: "thread", station: "ws/st", thread: 7 });
    await host.settle();
    apply(host, values);
    const window = () => [v(values, 1).first, v(values, 1).last, v(values, 1).end];
    const page = async (id: number, name: string) => {
      call(core, ui, id, name, { station: "ws/st", thread: 7 });
      await host.time.pass(100);
      apply(host, values);
      return window();
    };
    return { core, window, page };
  };
  const pages = async (letters: boolean, read: number, unread: number, name: string, opens: unknown[], then: unknown[][]) => {
    const s = await opened(letters, read, unread);
    assert.deepEqual(s.window(), opens);
    for (const [i, w] of then.entries()) assert.deepEqual(await s.page(i + 2, name), w, `${letters ? "letters" : "all shown"}: ${name} ${i + 1}`);
    s.core.close();
  };
  // Opened at its end, paging back; opened at its first entry (unread), paging on.
  await pages(true, 300, 0, "chat.older", [251, 300, true], [[201, 300, true], [151, 300, true], [101, 300, true], [51, 300, true], [1, 300, true]]);
  await pages(true, 0, 300, "chat.newer", [1, 50, false], [[1, 100, false], [1, 150, false], [1, 200, false], [1, 250, false], [1, 300, true]]);
  await pages(false, 300, 0, "chat.older", [251, 300, true], [[201, 300, true], [151, 300, true], [101, 250, false], [51, 200, false], [1, 150, false]]);
  await pages(false, 0, 300, "chat.newer", [1, 50, false], [[1, 100, false], [1, 150, false], [51, 200, false], [101, 250, false], [151, 300, true]]);
});

test("a_write_answers_once_what_it_touched_is_read_again", async () => {
  const answers = base();
  answers["POST /sessions/k1/stop"] = { ok: true };
  answers["POST /sessions/k1/warm"] = { ok: true };
  const { host, core } = await started(answers);
  const ui = core.connect();
  const before = gets(host, "/admin/api/sessions");
  call(core, ui, 9, "session.stop", { station: "ws/st", key: "k1" });
  await host.settle();
  const answer = host.takeEmitted().find(([, m]) => m.id === 9);
  assert.deepEqual(answer?.[1], { id: 9, ok: { ok: true } });
  // Its own detail; the lists that show it its station tells as they change.
  assert.equal(gets(host, "/admin/api/sessions"), before);
  assert.equal(gets(host, "/admin/api/sessions/k1"), 2);
  // Warmed as someone types: nothing read, its station tells its new state.
  const reads = host.requests.length;
  call(core, ui, 10, "session.warm", { station: "ws/st", key: "k1" });
  await host.settle();
  assert.deepEqual(host.requests.slice(reads).map((r) => `${r.method} ${r.url.replace("https://stillfail.test/admin/api", "")}`), ["POST /sessions/k1/warm"]);
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

test("an_important_activity_reaches_the_live_topic_ahead_of_a_routine_call", async () => {
  const answers = base();
  answers["GET /chats"] = [{ id: "7", thread: 7, session: "k1", title: "部署", agents: [{ key: "k1", process: "running" }], lastActiveAt: 1 }];
  const { host, core, push } = await started(answers);
  try {
    const ui = core.connect();
    const values = new Map();
    const usage = { modelCalls: 0, inputTokens: 0, cachedTokens: 0, outputTokens: 0 };
    subscribe(core, ui, 1, { topic: "live", station: "ws/st", key: "k1" });
    await host.settle();
    push("live", {
      key: "k1", type: "timeline", start: 0, usage,
      entries: [
        { kind: "user", text: "fix it" },
        { kind: "tool_call", tool: "apply_patch", callId: "edit", text: "{}" },
        { kind: "tool_call", tool: "Read", callId: "read", text: "{}" },
      ],
    });
    await host.time.pass(100);
    apply(host, values);
    assert.equal(v(values, 1).activity.now.key, "edit");
    assert.equal(v(values, 1).activity.now.important, true, "the live topic carries the step's importance");
    push("live", {
      key: "k1", type: "timeline", start: 3, usage,
      entries: [{ kind: "tool_result", callId: "edit", ok: true, text: "done" }],
    });
    await host.time.pass(100);
    apply(host, values);
    assert.equal(v(values, 1).activity.now.key, "read");
    assert.notEqual(v(values, 1).activity.now.important, true);
  } finally {
    core.close();
  }
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

test("a_chat_says_it_waits_on_its_station_only_while_none_of_what_it_opens_with_is_on_the_device", async () => {
  // Chat 7's latest page is on the device; none of chat 8's, its read held up. A page opening waits for the core's
  // answer (mbui sfapp page_ready): 7's view, however long the core takes to read it, never `waiting` before it (its
  // page slid in as its messages' bones, then them, 2026-10-31); 8 says at once it waits, its page showing its
  // messages to come, then its view as they are here.
  const answers = base();
  answers["GET /threads"] = [threadView(7, 120), threadView(8, 30)];
  answers["GET /threads/7/entries?limit=50"] = { last: 120, entries: entries(71, 120) };
  const held: (() => void)[] = [];
  const { host, core } = await started(answers, 0, undefined, (s) =>
    stationLater(s.host, (req) => {
      if (!/\/threads\/8\/entries/.test(req.url)) return undefined;
      return new Promise((answer) => held.push(() => answer(jsonResponse(200, { last: 30, entries: entries(1, 30) }))));
    }));
  assert.equal(core.inner.data.logSpan("entry", "ws/st", "8"), null, "none of 8 here");
  host.takeEmitted();
  const ui = core.connect();
  const said = (id: number) => host.takeEmitted().map(([, m]) => m as Record<string, unknown>).filter((m) => m.id === id);
  subscribe(core, ui, 1, { topic: "chat", station: "ws/st", thread: 7, session: null });
  subscribe(core, ui, 2, { topic: "chat", station: "ws/st", thread: 8, session: null });
  await host.time.pass(50, 10);
  const emitted = host.takeEmitted().map(([, m]) => m as Record<string, unknown>);
  const of7 = emitted.filter((m) => m.id === 1);
  const of8 = emitted.filter((m) => m.id === 2);
  assert.ok(of7.length > 0 && of7.every((m) => !("waiting" in m)), "7 on the device: its view, never waiting");
  assert.ok("value" in of7[0]!, "its first message its view");
  assert.deepEqual(of8, [{ id: 2, waiting: true }], "8 waits on its station");
  // one more subscriber of 8 is told so too
  subscribe(core, ui, 3, { topic: "chat", station: "ws/st", thread: 8, session: null });
  assert.deepEqual(said(3), [{ id: 3, waiting: true }]);
  for (const answer of held.splice(0)) answer();
  await host.time.pass(500, 10);
  const later = said(2);
  assert.ok(later.length > 0 && later.every((m) => !("waiting" in m)), "then its view");
  assert.ok("value" in later[0]!);
  core.close();
});

test("a_chat_whose_unread_came_while_the_app_was_away_opens_at_once_with_what_is_held_and_what_came_joins_it", async () => {
  // Read to 120 here; the app away while 121..125 were said. As it opens again its lists say so before those entries
  // are on the device: the chat opens with what is held, where it opens (121) not here yet, and they join it as they
  // come, the unread line over the first of them.
  const answers = base();
  answers["GET /threads"] = [threadView(7, 120)];
  answers["GET /threads/7/entries?limit=50"] = { last: 120, entries: entries(71, 120) };
  const first = await started(answers);
  await run(first.core.inner.data.written);
  first.core.close();
  const host = first.host;
  answers["GET /threads"] = [threadView(7, 125, 120, 5)];
  // (its entries answered once let go; what came since, its agent's)
  const asked: (() => void)[] = [];
  stationLater(host, (req) => {
    const query = /\/threads\/7\/entries\?(.*)$/.exec(req.url)?.[1];
    if (query === undefined) return undefined;
    const q = new URLSearchParams(query);
    const from = q.has("after") ? Number(q.get("after")) + 1 : Number(q.get("from") ?? 76);
    const to = Number(q.get("to") ?? 125);
    const said = entries(from, to).map((e) => (e.n > 120 ? { ...e, authorKind: "agent", author: "k1" } : e));
    return new Promise((answer) => asked.push(() => answer(jsonResponse(200, { last: 125, entries: said }))));
  });
  const core = await Core.create(host, { clock: host.time.clock, sample: 0, wire: () => new HostWire(host) });
  await host.time.pass(500, 10);
  assert.equal((core.inner.data.thread("ws/st", 7) as { unread?: number }).unread, 5, "its lists read");
  assert.equal(core.inner.data.logSpan("entry", "ws/st", "7")?.max, 120, "what came not");
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "thread", station: "ws/st", thread: 7 });
  subscribe(core, ui, 2, { topic: "chat", station: "ws/st", thread: 7, session: null });
  await host.time.pass(50, 10);
  apply(host, values);
  assert.deepEqual([v(values, 1).at, v(values, 1).first, v(values, 1).last, v(values, 1).end], [121, 71, 120, true]);
  assert.equal(v(values, 2).messages.at(-1).seq, 120);
  assert.equal(v(values, 2).unreadLine, undefined, "none yet: nothing unread is here");
  for (const answer of asked.splice(0)) answer();
  await host.time.pass(500, 10);
  apply(host, values);
  assert.deepEqual([v(values, 1).first, v(values, 1).last], [71, 125]);
  assert.equal(v(values, 2).messages.at(-1).seq, 125);
  assert.equal(v(values, 2).unreadLine, 121);
  core.close();
});

test("a_step_ends_on_new_steps_the_live_value_already_shown_keeps_as_they_were", async () => {
  const { applyStep } = await import("../src/station/sync.ts");
  const view = { steps: [] as unknown[], phase: null, rate: null, usage: null, loaded: true };
  applyStep(view, { kind: "start", id: "s1", step: "Bash", input: "ls" }, 1000);
  applyStep(view, { kind: "start", id: "s2", step: "Read", input: "a.ts" }, 2000);
  // The live topic's value holds these steps as they were made (shared, frozen when that is checked).
  const shown = Object.freeze(view.steps.map((s) => Object.freeze(s)));
  view.steps = shown as unknown[];
  applyStep(view, { kind: "end", id: "s1" }, 3000);
  assert.deepEqual(view.steps.map((s) => [(s as { id: string }).id, (s as { ended?: boolean }).ended ?? false]), [["s1", true], ["s2", false]]);
  assert.equal(view.steps[1], shown[1]);
  assert.equal((shown[0] as { ended?: boolean }).ended, undefined);
});

test("a_chat_is_looked_in_whole_and_its_window_goes_about_a_message_found", async () => {
  const pages = (answers: Answers) => {
    for (let from = 201; from >= 1; from -= 50) answers[`GET /threads/7/entries?from=${from}&to=${from + 49}`] = { last: 300, entries: entries(from, from + 49) };
  };
  const answers = base();
  answers["GET /threads"] = [threadView(7, 300)];
  answers["GET /threads/7/entries?limit=50"] = { last: 300, entries: entries(251, 300) };
  const { host, core } = await started(answers);
  const ui = core.connect();
  const values = new Map();
  // What call `id` answered (the topics' values kept up with what was told meanwhile).
  const ok = (id: number) => {
    const answer = answered(host.emitted.slice(), id);
    apply(host, values);
    return answer?.ok;
  };
  subscribe(core, ui, 1, { topic: "thread", station: "ws/st", thread: 7 });
  await host.time.pass(500);
  apply(host, values);
  assert.deepEqual([v(values, 1).first, v(values, 1).last, v(values, 1).end], [251, 300, true]);
  // Its older pages not on the device (the station did not answer them): what is held is looked in, and said so.
  call(core, ui, 2, "chat.find", { station: "ws/st", thread: 7, query: "M27" });
  await host.settle();
  assert.deepEqual(ok(2), { words: ["m27"], hits: [270, 271, 272, 273, 274, 275, 276, 277, 278, 279].map((seq) => ({ seq, count: 1 })), held: 50, of: 300, whole: false });
  // Asked to bring the rest: read first, then all of it looked in.
  pages(answers);
  call(core, ui, 3, "chat.find", { station: "ws/st", thread: 7, query: "m27", bring: true });
  await host.time.pass(500);
  const found = ok(3) as { hits: { seq: number }[]; held: number; whole: boolean };
  assert.deepEqual([found.hits.map((h) => h.seq), found.held, found.whole], [[27, 270, 271, 272, 273, 274, 275, 276, 277, 278, 279], 300, true]);
  // The window about the one found far back: a page on either side; one near the end reaches it.
  call(core, ui, 4, "chat.around", { station: "ws/st", thread: 7, seq: 27 });
  await host.settle();
  apply(host, values);
  assert.deepEqual([v(values, 1).first, v(values, 1).last, v(values, 1).end], [1, 76, false]);
  call(core, ui, 5, "chat.around", { station: "ws/st", thread: 7, seq: 40 });
  await host.settle();
  apply(host, values);
  assert.deepEqual([v(values, 1).first, v(values, 1).last], [1, 76], "well within the window: left as it is");
  call(core, ui, 6, "chat.around", { station: "ws/st", thread: 7, seq: 270 });
  await host.settle();
  apply(host, values);
  assert.deepEqual([v(values, 1).first, v(values, 1).last, v(values, 1).end], [220, 300, true]);
  core.close();
});
