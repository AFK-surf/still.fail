// client/core/src/station/tests.rs, ported (same names; the checks as the TS core's design has them: the station is
// read into records by its sync, and its topics read only those; docs/core-ts.md). The Rust tests drove the station
// module with a fake wire and sink; these drive a core over the host's fetch (station-fixture.ts).
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect } from "effect";
import { CoreError } from "../src/error.ts";
import { encode, request } from "../src/ops.ts";
import { StationAddr } from "../src/station/addr.ts";
import { SseParser } from "../src/station/sse.ts";
import { run } from "./run.ts";
import { base, entries, entry, overview, session, started, status, stationReplies, threadView } from "./station-fixture.ts";
import { merge } from "../src/entries.ts";
import { apply, call, subscribe, v } from "./helpers.ts";
import { EVICT_AFTER_MS } from "../src/store.ts";
import { EVENTS_COALESCE_MS, LINK_KEY, RECONNECT_MS } from "../src/station/sync.ts";
import type { FakeHost } from "../src/testing.ts";

const gets = (host: FakeHost, path: string) => host.requests.filter((r) => r.method === "GET" && r.url.endsWith(path)).length;
const text = (b: Uint8Array | undefined) => (b === undefined ? undefined : new TextDecoder().decode(b));

// deno-lint-ignore no-explicit-any
type J = any;
const ST = "ws/st";
const remote = () => StationAddr.parse(ST);
const op = (name: string, params: J) => request(name, { station: ST, ...params })!;
const failure = async (e: Effect.Effect<unknown, CoreError>) => {
  const r = await Effect.runPromise(Effect.result(e));
  assert.equal(r._tag, "Failure");
  return (r as { failure: CoreError }).failure;
};

test("parses_addresses", () => {
  assert.deepEqual([remote().workspace, remote().station], ["ws", "st"]);
  assert.equal(remote().toString(), "ws/st");
  for (const bad of ["", "ws", "/st", "ws/", "a/b/c", "Local"]) {
    assert.throws(() => StationAddr.parse(bad), (e: CoreError) => e.code === "invalid_params", bad);
  }
  // A station's own page, still in kept links and prefs: gone, said so.
  assert.throws(() => StationAddr.parse("local"), (e: CoreError) => e.code === "gone");
});

test("parses_sse_across_chunks", () => {
  const p = new SseParser();
  const bytes = (s: string) => new TextEncoder().encode(s);
  assert.deepEqual(p.feed(bytes("retry: 2000\n\n: ping\n\nevent: sess")), []);
  assert.deepEqual(p.feed(bytes('ion\r\ndata: {"key":"a"}\r\n\r\ndata: x\ndata:y\n\nevent: e\n')), [
    ["session", '{"key":"a"}'],
    ["message", "x\ny"],
  ]);
  const text = bytes("data: 你好\n\n");
  assert.deepEqual(p.feed(text.slice(0, 7)), []);
  assert.deepEqual(p.feed(text.slice(7)), [["e", "你好"]]);
});

test("encodes_like_the_web", () => {
  assert.equal(encode("a b/ç!"), "a%20b%2F%C3%A7!");
});

test("maps_request_errors", async () => {
  const { host, core } = await started({
    ...base(),
    "GET /overview": { connects: [] },
    "POST /sessions/k/stop": status(403, { error: "没有权限" }),
    "GET /host": status(500, "oops"),
  });
  const requests = core.inner.stations.requests;
  assert.deepEqual(await run(requests.call(remote(), "GET", "/overview", null)), { connects: [] });
  let e = await failure(core.inner.stations.perform(op("session.stop", { key: "k" }), null));
  assert.deepEqual([e.code, e.message, e.status], ["http_403", "没有权限", 403]);
  e = await failure(requests.call(remote(), "GET", "/host", null));
  assert.deepEqual([e.code, e.message, e.status], ["http_500", "请求失败（500）", 500]);
  // A bodyless named operation stays bodyless.
  const stop = host.requests.find((r) => r.url.endsWith("/sessions/k/stop"))!;
  assert.equal(stop.body?.length ?? 0, 0);
  core.close();
});

test("uploads_and_reads_files", async () => {
  const { host, core } = await started({
    ...base(),
    "POST /uploads?name=a%20b.png": { name: "a b.png" },
    "GET /sessions/k/files?name=x": status(404, { error: "没有这个文件" }),
  });
  const requests = core.inner.stations.requests;
  const saved = (await run(requests.upload(remote(), "a b.png", new Uint8Array([1, 2, 3]), null))) as J;
  assert.equal(saved.name, "a b.png");
  assert.deepEqual([...host.requests.find((r) => r.url.includes("/uploads"))!.body!], [1, 2, 3]);
  const e = await failure(requests.file(remote(), "k", "x", false, () => {}, null));
  assert.deepEqual([e.message, e.status], ["读不到文件", 404]);
  core.close();
});

test("tells_how_far_a_file_has_come", async () => {
  const big = "x".repeat(300 * 1024);
  const { core } = await started({ ...base(), "GET /sessions/k/files?name=big": big });
  const heard: [number, number | null][] = [];
  const [, bytes] = await run(core.inner.stations.requests.file(remote(), "k", "big", false, (loaded, total) => heard.push([loaded, total]), null));
  // At the start, then once past 256 KB (the size not given, it comes in one chunk here).
  assert.deepEqual(heard, [[0, null], [bytes.length, null]]);
  core.close();
});

void stationReplies;

const linkOf = (values: Map<number, unknown>, id: number) => (values.get(id) as J)?.state;

test("a_station_not_reached_is_down_and_asked_for_nothing_until_it_is", async () => {
  // Never reached: down (whatever else says otherwise), and kept so for the next start.
  const { host, core, gate } = await started({ ...base(), "GET /overview": { connects: [], profiles: [] } }, 0, undefined, (s) => (s.gate.stream = "fail"));
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "link", station: ST });
  subscribe(core, ui, 2, { topic: "overview", station: ST });
  await host.settle();
  apply(host, values);
  assert.equal(linkOf(values, 1), "offline");
  assert.equal(text(host.stored(`${LINK_KEY}/${ST}`)), "offline");
  assert.equal(gets(host, "/admin/api/overview"), 0, "down: nothing asked");
  // Reached: what it holds is read.
  gate.stream = "open";
  await host.time.pass(RECONNECT_MS * 2 + 50, 50);
  apply(host, values);
  assert.equal(linkOf(values, 1), "online");
  assert.equal(gets(host, "/admin/api/overview"), 1, "back: what it holds is read");
  assert.equal(text(host.stored(`${LINK_KEY}/${ST}`)), "online");
  core.close();
});

test("a_station_down_shows_it_is_tried_again_as_soon_as_a_person_asks", async () => {
  const { host, core, gate } = await started(base(), 0, undefined, (s) => (s.gate.stream = "fail"));
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "link", station: ST });
  await host.settle();
  apply(host, values);
  assert.equal(linkOf(values, 1), "offline");
  // 重试 (client.wake, network), and the try it starts takes a while: not "down" meanwhile.
  gate.stream = "hang";
  call(core, ui, 2, "client.wake", { away: 0, network: true });
  await host.settle();
  apply(host, values);
  assert.equal(linkOf(values, 1), "reconnecting");
  core.close();
});

const summary = (key: string, turns: number) => ({ ...session(key, turns), title: null, archivedAt: null, lastTurn: null });

test("writes_bring_what_they_touch_up_to_date", async () => {
  const { host, core } = await started({
    ...base(),
    "GET /sessions": [summary("k 1", 0), summary("other", 0)],
    "GET /sessions/k%201": { session: summary("k 1", 0), threads: [], turns: [] },
    "GET /sessions/other": { session: summary("other", 0), threads: [], turns: [] },
    "GET /threads": [],
    "POST /sessions/k%201/stop": {},
    "GET /slack/config-token": {},
    "POST /profiles/p/check": {},
    "POST /updates/channel": [],
    "POST /slack/config-tokens": {},
  });
  const perform = (name: string, params: J) => run(core.inner.stations.perform(op(name, params), null));
  await host.settle();
  assert.notEqual(core.inner.data.get({ topic: "session", station: ST, key: "k 1" }), undefined);
  const [s, k, o, other] = ["/admin/api/sessions", "/admin/api/sessions/k%201", "/admin/api/overview", "/admin/api/sessions/other"].map((p) => gets(host, p));
  await perform("session.stop", { key: "k 1" });
  await host.settle();
  assert.equal(gets(host, "/admin/api/sessions"), s + 1);
  assert.equal(gets(host, "/admin/api/sessions/k%201"), k + 1);
  assert.equal(gets(host, "/admin/api/sessions/other"), other);
  assert.equal(gets(host, "/admin/api/overview"), o);
  // A profile edit answers the overview: that is the record now, nothing is read again.
  // (Checked already: a profile not checked yet is checked as it appears, which reads the overview again.)
  const edited = { ...overview, profiles: [{ id: "p", check: { state: "ok", detail: "", checkedAt: 1 } }] };
  stationReplies(host, (req) => (req.method === "PUT" && req.url.endsWith("/profiles/p") ? edited : undefined));
  const put = await perform("profile.put", { id: "p", input: {} });
  assert.deepEqual(put, edited, JSON.stringify(host.requests.slice(-3).map((r) => [r.method, r.url])));
  assert.deepEqual(core.inner.data.get({ topic: "overview", station: ST }), edited);
  assert.equal(gets(host, "/admin/api/overview"), o);
  await perform("profile.check", { id: "p" });
  await host.settle();
  assert.equal(gets(host, "/admin/api/overview"), o + 1);
  // Put on another update channel: its versions (the overview's) read again.
  await perform("software.channel", { channel: "beta" });
  await host.settle();
  assert.equal(gets(host, "/admin/api/overview"), o + 2);
  // Another chat on a session answers its thread, which goes into the records without a request.
  const reads = host.requests.length;
  stationReplies(host, (req) => (req.method === "POST" && req.url.endsWith("/admin/api/threads") ? { ...threadView(9, 0), sessions: [{ thread: 9, session: "k 1" }] } : undefined));
  await perform("chat.forSession", { session: "k 1" });
  await host.settle();
  assert.equal((core.inner.data.get({ topic: "session", station: ST, key: "k 1" }) as J).threads[0].id, 9);
  assert.equal((core.inner.data.get({ topic: "threads", station: ST }) as J)[0].id, 9);
  // The threads and sessions are not read again for it. (The TS core reads the chat rows, which the station makes, so
  // the new chat is in the list as the station has it; and the sync brings the new chat's entries onto the device.)
  assert.deepEqual(
    host.requests.slice(reads).map((r) => `${r.method} ${r.url.replace("https://stillfail.test/admin/api", "")}`).filter((r) => !r.includes("/threads/9/entries") && r !== "GET /chats"),
    ["POST /threads"],
  );
  // A read changes nothing.
  await run(core.inner.stations.requests.call(remote(), "GET", "/slack/config-token", null));
  assert.equal(gets(host, "/admin/api/overview"), o + 2);
  // The workspace's app configuration token: every Slack connect's app is read again, as it now reads.
  let app = "no_config_token";
  stationReplies(host, (req) => (req.url.endsWith("/connects/ds/slack-app") ? { state: app } : req.url.endsWith("/overview") ? { ...edited, connects: [{ id: "ds", kind: "slack" }] } : undefined));
  core.inner.data.set({ topic: "overview", station: ST }, { ...edited, connects: [{ id: "ds", kind: "slack" }] });
  app = "ok";
  await perform("slack.addConfigToken", { refreshToken: "x" });
  assert.equal((core.inner.data.get({ topic: "slackApp", station: ST, connect: "ds" }) as J).state, "ok");
  core.close();
});

test("operation_effects_do_not_depend_on_the_wire_path", async () => {
  const { host, core } = await started({ ...base(), "POST /different-endpoint": {}, "POST /slack/verify": {}, "GET /jobs/j": { connects: [], profiles: [] } });
  await host.settle();
  const before = gets(host, "/admin/api/overview");
  const check = op("profile.check", { id: "p" });
  await run(core.inner.stations.perform({ ...check, path: "/different-endpoint" }, null));
  await host.settle();
  assert.equal(gets(host, "/admin/api/overview"), before + 1);
  await run(core.inner.stations.perform(op("slack.verify", { appToken: "app", botToken: "bot" }), null));
  await host.settle();
  assert.equal(gets(host, "/admin/api/overview"), before + 1, "checking tokens is not a settings change");
  // A response that happens to resemble an overview does not give a read write effects.
  await run(core.inner.stations.perform(op("job.get", { id: "j" }), null));
  await host.settle();
  assert.equal(gets(host, "/admin/api/overview"), before + 1);
  core.close();
});

test("archive_fallback_updates_the_session_only_after_success", async () => {
  const answers: J = { ...base(), "GET /sessions/k": { session: summary("k", 0), threads: [], turns: [] }, "GET /sessions": [summary("k", 0)] };
  const { host, core } = await started(answers);
  await host.settle();
  const archive = op("chat.archive", { thread: 7, session: "k", archived: true });
  const before = gets(host, "/admin/api/sessions/k");
  const posts = (path: string) => host.requests.filter((r) => r.method === "POST" && r.url.endsWith(path)).length;
  answers["POST /threads/7/archive"] = status(403, { error: "denied" });
  assert.equal((await failure(core.inner.stations.perform(archive, null))).status, 403);
  assert.equal(posts("/admin/api/sessions/k/archive"), 0);
  assert.equal(gets(host, "/admin/api/sessions/k"), before);
  answers["POST /threads/7/archive"] = status(404, {});
  answers["POST /sessions/k/archive"] = status(500, {});
  await failure(core.inner.stations.perform(archive, null));
  await host.settle();
  assert.equal(gets(host, "/admin/api/sessions/k"), before);
  answers["POST /sessions/k/archive"] = {};
  await run(core.inner.stations.perform(archive, null));
  await host.settle();
  assert.equal(gets(host, "/admin/api/sessions/k"), before + 1);
  assert.equal(posts("/admin/api/sessions/k/archive"), 2);
  core.close();
});

/// A log as the station said it (the topic goes out with its last line and when, in words, besides).
const raw = (log: J) => ({ text: log.text, outputAt: log.outputAt });
const sessionOf = (core: J, key: string) => core.inner.data.get({ topic: "session", station: ST, key }) as J;
const reqs = (host: FakeHost) => host.requests.filter((r) => r.url.includes("/admin/api/")).length;

test("jobs_are_put_in_place_from_their_events_and_from_stopping_them", async () => {
  const job = (id: string, state: string) => ({ id, session: "a", name: id, state, port: 4817, startedAt: 1 });
  const answers: J = {
    ...base(),
    "GET /sessions": [summary("a", 0)],
    "GET /sessions/a": { session: summary("a", 0), threads: [], turns: [], jobs: [job("j1", "running")] },
    "GET /jobs": [{ ...job("j1", "running"), chat: { id: "7", title: "t", archived: false } }],
    "POST /jobs/j1/stop": job("j1", "stopped"),
  };
  const { host, core, push } = await started(answers);
  await host.settle();
  const open = () => core.inner.data.get({ topic: "jobs", station: ST }) as J[];
  const reads = reqs(host);
  // Stopped from a page: the answer is the job as it is now, in its chat and gone from the open ones, with nothing
  // read again.
  await run(core.inner.stations.perform(op("job.stop", { id: "j1" }), null));
  await host.settle();
  assert.equal(sessionOf(core, "a").jobs[0].state, "stopped");
  assert.deepEqual(open(), []);
  assert.equal(reqs(host), reads + 1);
  // Started again elsewhere (an agent, another device): its event puts it back; which chat it is in, the list read
  // again says.
  push("job", job("j1", "running"));
  await host.time.pass(EVENTS_COALESCE_MS + 100);
  assert.equal(sessionOf(core, "a").jobs[0].state, "running");
  assert.equal(open()[0].chat.id, "7");
  assert.equal(gets(host, "/admin/api/jobs"), 2);
  // A new one goes in front of its session's; one listed keeps its chat as it changes.
  push("job", job("j2", "failed"));
  push("job", { ...job("j1", "exited"), restarts: 1 });
  await host.time.pass(EVENTS_COALESCE_MS + 100);
  const jobs = sessionOf(core, "a").jobs;
  assert.deepEqual([jobs[0].id, jobs[1].state], ["j2", "exited"]);
  assert.equal(open()[0].restarts, 1);
  assert.equal(open()[0].chat.id, "7");
  assert.equal(gets(host, "/admin/api/jobs"), 2);
  // One that was over, cleared (here or on another device): out of its chat's.
  push("job-removed", { id: "j2", session: "a" });
  await host.time.pass(EVENTS_COALESCE_MS + 100);
  assert.deepEqual(sessionOf(core, "a").jobs.map((j: J) => j.id), ["j1"]);
  core.close();
});

test("a_jobs_log_is_read_once_and_then_kept_current_by_the_stations_events", async () => {
  const { host, core, push, streams } = await started({
    ...base(),
    "GET /jobs/j1/log?lines=400": { text: "a\nb", outputAt: 5, follows: true },
    "GET /jobs/j1/log?lines=1": { text: "b", outputAt: 5, follows: true },
  });
  const ui = core.connect();
  const values = new Map();
  const log = (lines: number) => ({ topic: "jobLog", station: ST, job: "j1", lines });
  const openStreams = () => streams.filter((s) => !s.closed).map((s) => s.path);
  subscribe(core, ui, 1, log(400));
  await host.settle();
  await host.settle();
  apply(host, values);
  assert.deepEqual(raw(v(values, 1)), { text: "a\nb", outputAt: 5 });
  assert.deepEqual(openStreams(), ["/events?job=j1&lines=400"]);
  // As it grows the station says so, each topic its own lines; nothing is read again, and nothing waits to.
  subscribe(core, ui, 2, log(1));
  await host.settle();
  await host.settle();
  assert.deepEqual(openStreams(), ["/events?job=j1&lines=1&job=j1&lines=400"]);
  host.time.sleeps.length = 0;
  push("job-log", { id: "j1", lines: 400, text: "a\nb\nc", outputAt: 9 });
  push("job-log", { id: "j1", lines: 1, text: "c", outputAt: 9 });
  await host.settle();
  apply(host, values);
  assert.deepEqual(raw(v(values, 1)), { text: "a\nb\nc", outputAt: 9 });
  assert.deepEqual(raw(v(values, 2)), { text: "c", outputAt: 9 });
  await host.time.pass(5_000, 100);
  assert.deepEqual([gets(host, "/admin/api/jobs/j1/log?lines=400"), gets(host, "/admin/api/jobs/j1/log?lines=1")], [1, 1]);
  // Given up: the stream no longer asks for it (once its grace is over).
  core.receive(ui, { kind: "unsubscribe", id: 1, unsubscribe: true });
  await host.time.pass(EVICT_AFTER_MS + 500, 500);
  assert.deepEqual(openStreams(), ["/events?job=j1&lines=1"]);
  core.close();
});

test("a_jobs_log_on_a_station_that_does_not_follow_it_is_read_again_less_often_while_it_stays_the_same", async () => {
  // Deliberately otherwise (docs/core-ts.md, rule 2): the Rust core read an older station's log again and again,
  // backing off; the TS core reads it once as it opens and never again.
  const answers: J = { ...base(), "GET /jobs/j1/log?lines=1": { text: "a", outputAt: 5 } };
  const { host, core } = await started(answers);
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "jobLog", station: ST, job: "j1", lines: 1 });
  await host.settle();
  await host.settle();
  apply(host, values);
  assert.deepEqual(raw(v(values, 1)), { text: "a", outputAt: 5 });
  answers["GET /jobs/j1/log?lines=1"] = { text: "b", outputAt: 6 };
  await host.time.pass(60_000, 1_000);
  assert.equal(gets(host, "/admin/api/jobs/j1/log?lines=1"), 1);
  core.close();
});

test("requests_carry_the_trace_they_are_made_in", async () => {
  // Adapted: a topic asks nothing (rule 6), so what carries a trace is the station's reading (one trace from its
  // connecting) and a request made inside a call (its call's trace); one outside every trace has its own.
  const { host, core } = await started(base(), 1);
  const parents = host.requests.filter((r) => r.url.includes("/admin/api/")).map((r) => [r.url, r.headers.find(([k]) => k === "traceparent")?.[1] ?? ""]);
  const trace = parents[0][1].slice(3, 35);
  for (const [url, parent] of parents) {
    assert.ok(parent.startsWith("00-") && parent.endsWith("-01") && parent.length === 55, `${url}: ${parent}`);
  }
  const snapshot = ["/events", "/overview", "/sessions", "/threads", "/chats", "/jobs"].map((p) => parents.find(([u]) => u === `https://stillfail.test/admin/api${p}`)![1]);
  assert.ok(snapshot.every((p) => p.slice(3, 35) === trace), JSON.stringify(snapshot));
  // Each request is a span of its own.
  assert.equal(new Set(snapshot.map((p) => p.slice(36, 52))).size, snapshot.length);
  // Outside every trace: a trace of its own.
  await run(core.inner.stations.requests.call(remote(), "GET", "/overview", null));
  const last = host.requests.at(-1)!.headers.find(([k]) => k === "traceparent")![1];
  assert.notEqual(last.slice(3, 35), trace);
  core.close();
});

test("topics_are_read_once_and_nothing_runs_on_a_timer", async () => {
  const { host, core, streams } = await started();
  const ui = core.connect();
  const topics = [
    { topic: "session", station: ST, key: "k1" }, { topic: "sessions", station: ST }, { topic: "overview", station: ST }, { topic: "threads", station: ST },
    { topic: "thread", station: ST, thread: 7 }, { topic: "host", station: ST }, { topic: "link", station: ST }, { topic: "live", station: ST, key: "k1" },
  ];
  const reads = () => host.requests.filter((r) => r.url.includes("/admin/api/") && !r.url.includes("/events")).length;
  const before = reads();
  topics.forEach((t, i) => subscribe(core, ui, i + 1, t));
  await host.settle();
  await host.settle();
  assert.deepEqual(streams.filter((s) => !s.closed).map((s) => s.path), ["/events?host=1&live=k1&from=0&last=200"]);
  // Subscribing reads nothing: what is held shows (the stream opened anew for the host and the live session).
  assert.equal(reads(), before, JSON.stringify(host.requests.filter((r) => r.url.includes("/admin/api/") && !r.url.includes("/events")).slice(before).map((r) => r.url)));
  const requests = reqs(host);
  host.time.sleeps.length = 0;
  await host.time.pass(RECONNECT_MS * 2, 100);
  assert.equal(reqs(host), requests, "idle: no request");
  core.close();
});

// ── threads: their entries are records on the device, a chat's window is read from them ──

const edit = (n: number, target: number, text: string) => ({ thread: 7, n, kind: "edit", target, ts: null, authorKind: "person", author: "a@x.com", text, at: n });
const coalesce = (host: FakeHost) => host.time.pass(EVENTS_COALESCE_MS + 100, 50);

/// A core whose station has `answers`, and a UI on it with its values.
async function ui(answers: J, before?: Parameters<typeof started>[3]) {
  const s = await started(answers, 0, undefined, before);
  const id = s.core.connect();
  const values = new Map<number, unknown>();
  const read = async () => {
    await s.host.settle();
    apply(s.host, values);
  };
  return { ...s, ui: id, values, read };
}

const page = (values: Map<number, unknown>, id = 1) => v(values, id);
const nums = (values: Map<number, unknown>, id = 1) => page(values, id).entries.map((e: J) => e.n);
const texts = (values: Map<number, unknown>, id = 1) => merge(page(values, id).entries).map((m: J) => m.text);
const windowOf = (values: Map<number, unknown>, id = 1) => [page(values, id).first, page(values, id).last, page(values, id).end];
const thread7 = { topic: "thread", station: ST, thread: 7 };
const threadsOf = (core: J) => core.inner.data.get({ topic: "threads", station: ST }) as J[];

test("thread_events_append_entries_and_refresh_summaries", async () => {
  const answers: J = {
    ...base(),
    "GET /threads/7/entries?limit=50": { last: 12, entries: [entry(11, "a"), entry(12, "b")] },
    "GET /threads": [threadView(7, 12, 12, 0)],
    "GET /threads/7": threadView(7, 15, 12, 2),
    "GET /threads/8": threadView(8, 20, 0, 1),
  };
  const { host, core, push, values, read } = await ui(answers);
  core.receive(1, { kind: "subscribe", id: 1, subscribe: thread7 });
  await read();
  assert.deepEqual(texts(values), ["a", "b"]);
  // New entries (an edit among them), in one burst: appended at once, one known already skipped; the summary is
  // read once after it.
  push("thread", { id: 7, entries: [entry(13, "c")] });
  push("thread", { id: 7, entries: [entry(13, "c"), entry(14, "d"), edit(15, 12, "b 改了")] });
  await read();
  assert.deepEqual(nums(values), [11, 12, 13, 14, 15]);
  assert.deepEqual(texts(values), ["a", "b 改了", "c", "d"]);
  assert.equal(page(values).last, 15);
  assert.equal(gets(host, "/admin/api/threads/7"), 0, "waits for the burst to end");
  await coalesce(host);
  assert.equal(gets(host, "/admin/api/threads/7"), 1);
  assert.equal(threadsOf(core)[0].unread, 2);
  // A thread not listed yet comes in, first (its last message is the newest).
  push("thread", { id: 8, entries: [{ ...entry(20, "x"), thread: 8 }] });
  await coalesce(host);
  assert.deepEqual(threadsOf(core).map((t) => t.id), [8, 7]);
  // Reading up to the last entry: nothing unread, without a request. Short of it: counted again.
  push("read", { viewer: "a@x.com", thread: 7, n: 15 });
  await host.settle();
  assert.deepEqual([threadsOf(core)[1].unread, threadsOf(core)[1].read], [0, 15]);
  push("read", { viewer: "a@x.com", thread: 8, n: 15 });
  await coalesce(host);
  assert.equal(gets(host, "/admin/api/threads/8"), 2);
  // A thread gone: out of the list.
  answers["GET /threads/8"] = status(404, { error: "unknown thread 8" });
  push("thread", { id: 8, entries: [] });
  await coalesce(host);
  assert.equal(threadsOf(core).length, 1);
  core.close();
});

test("a_gap_is_read_once_and_what_came_meanwhile_waits_for_it", async () => {
  const { host, core, push, values, read } = await ui({
    ...base(),
    "GET /threads": [threadView(7, 3)],
    "GET /threads/7/entries?limit=50": { last: 3, entries: entries(1, 3) },
    "GET /threads/7/entries?from=4&to=5": { last: 7, entries: entries(4, 5) },
  });
  core.receive(1, { kind: "subscribe", id: 1, subscribe: thread7 });
  await read();
  // Entries 4 and 5 never came: 6 shows the gap, and 7 comes while it is read.
  push("thread", { id: 7, entries: [entry(6, "m6")] });
  push("thread", { id: 7, entries: [entry(7, "m7")] });
  await read();
  await read();
  assert.deepEqual(nums(values), [1, 2, 3, 4, 5, 6, 7]);
  assert.equal(gets(host, "/admin/api/threads/7/entries?from=4&to=5"), 1);
  assert.equal(host.requests.filter((r) => r.url.includes("/entries")).length, 2, JSON.stringify(host.requests.map((r) => r.url)));
  core.close();
});

test("a_thread_keeps_a_page_ahead_so_going_back_does_not_wait", async () => {
  // Further than the Rust core (which kept one page ahead): the whole thread is brought onto the device, so going
  // back asks the station nothing.
  const { host, core, values, read } = await ui({
    ...base(),
    "GET /threads": [threadView(7, 300)],
    "GET /threads/7/entries?limit=50": { last: 300, entries: entries(251, 300) },
    "GET /threads/7/entries?from=201&to=250": { last: 300, entries: entries(201, 250) },
    "GET /threads/7/entries?from=151&to=200": { last: 300, entries: entries(151, 200) },
    "GET /threads/7/entries?from=101&to=150": { last: 300, entries: entries(101, 150) },
    "GET /threads/7/entries?from=51&to=100": { last: 300, entries: entries(51, 100) },
    "GET /threads/7/entries?from=1&to=50": { last: 300, entries: entries(1, 50) },
  });
  await host.time.pass(1_000, 50);
  assert.equal(gets(host, "/admin/api/threads/7/entries?from=201&to=250"), 1, "the page before, brought in ahead");
  core.receive(1, { kind: "subscribe", id: 1, subscribe: thread7 });
  await read();
  const asked = host.requests.length;
  assert.equal(await run(core.inner.stationTopics.older(ST, 7)), true);
  await read();
  assert.equal(page(values).first, 201);
  assert.equal(host.requests.length, asked, "going back asks nothing");
  core.close();
});
