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
import { base, overview, session, started, status, stationReplies, threadView } from "./station-fixture.ts";
import { apply, call, subscribe } from "./helpers.ts";
import { LINK_KEY, RECONNECT_MS } from "../src/station/sync.ts";
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
