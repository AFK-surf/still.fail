// The Rust core's core/tests.rs, the rest ported (same names; the checks as the TS core's design has them, its
// deliberate differences in docs/core-ts.md): workspaces kept apart, the beta channel, previews, traces, choices,
// drafts, decisions, the chat list's local overlays, jobs, the archive, forms, the changelog.
import assert from "node:assert/strict";
import { Effect, Queue } from "effect";
import { parseCall } from "../src/core/calls.ts";
import { Loads } from "../src/preview-load.ts";
import type { HttpRequest } from "../src/host.ts";
import type { StationAddr } from "../src/station/addr.ts";
import { HostWire, type RequestHead, type StationWire } from "../src/station/wire.ts";
import { base64 } from "../src/util.ts";
import { test } from "node:test";
import { STORAGE_KEY } from "../src/accounts.ts";
import { name as brandName } from "../src/brand.ts";
import { Core } from "../src/core.ts";
const STATION = (station: string) => ({ station });
import { FakeHost, jsonResponse } from "../src/testing.ts";
import { account, apply, call, nowS, readsOf, subscribe, v } from "./helpers.ts";
import { run } from "./run.ts";
import { base, entry, overview, session, started, stationHost, stationLater, stationReplies, threadView } from "./station-fixture.ts";
import { apply as applyOps } from "../src/delta.ts";
import { conform } from "../src/conform.ts";
import { CoreError } from "../src/error.ts";
import { tokensOf } from "../src/forms.ts";
import * as present from "../src/present.ts";
import { PUSH_KEY } from "../src/attention.ts";
import { dbName, SOON_MS } from "../src/data.ts";
import { PENDING_PREFIX } from "../src/views/local.ts";
import { encode } from "../src/ops.ts";
import { EXPORT_MS } from "../src/trace.ts";

/// A draft as written, without the name the core gives it (its own test: draft-id.test.ts).
const noId = ({ id: _, ...d }: any) => d;

// deno-lint-ignore no-explicit-any
type J = any;

test("two_workspaces_are_kept_apart", async () => {
  const host = new FakeHost();
  host.store(STORAGE_KEY, [account("s1", "s1@x.com", "s1", "a1", "r", nowS(host) + 3600), account("s2", "s2@x.com", "s2", "a2", "r", nowS(host) + 3600)]);
  let w1Stations = true;
  host.onFetch((req) => {
    const path = req.url.replace("https://stillfail.test", "");
    const ofS1 = req.headers.some(([k, val]) => k === "authorization" && val === "Bearer a1");
    if (path === "/v1/me") return jsonResponse(200, { workspaces: [{ id: ofS1 ? "w1" : "w2", name: "W" }], invitations: [], relay_url: "https://relay.test" });
    if (path === "/v1/workspaces/w1") return jsonResponse(200, { id: "w1", stations: w1Stations ? [{ id: "a", name: "一号", online: false }] : [] });
    if (path === "/v1/workspaces/w2") return jsonResponse(200, { id: "w2", stations: [{ id: "b", name: "二号", online: false }] });
    return jsonResponse(404, { error: "not_found" });
  });
  const core = await Core.create(host, { clock: host.time.clock, sample: 0 });
  const inner = core.inner;
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "workspace", workspace: "w1" });
  subscribe(core, ui, 2, { topic: "workspace", workspace: "w2" });
  await host.settle();
  assert.deepEqual([inner.workspaces.owner("w1"), inner.workspaces.owner("w2")], ["s1", "s2"]);
  for (const station of ["w1/a", "w2/b"]) inner.data.set({ topic: "overview", station }, { ...overview, profiles: [] });
  // A station slow in W1: W1's status and the plain one say so, W2's does not.
  const w1 = inner.workspaces.of("w1").status;
  const slow = w1.begin(STATION("w1/a"), "读取对话", false);
  w1.skip(3_000);
  subscribe(core, ui, 3, { topic: "status", workspace: "w1" });
  subscribe(core, ui, 4, { topic: "status", workspace: "w2" });
  subscribe(core, ui, 5, { topic: "status" });
  await host.settle();
  apply(host, values);
  assert.ok(String(v(values, 3).text).startsWith("一号 读取对话 · 3 秒"), JSON.stringify(v(values, 3)));
  assert.equal(v(values, 4).state ?? null, null, JSON.stringify(v(values, 4)));
  assert.equal(v(values, 5).items.length, 1);
  // The plain one says the station's workspace too (its name, not held here: its id): two workspaces are said in it.
  assert.equal(v(values, 5).items[0].text, "一号 · w1 读取对话", JSON.stringify(v(values, 5)));
  // What a new chat was last started on: each workspace's own.
  call(core, ui, 6, "newChat.pick", { scope: "w1", station: "a" });
  await host.settle();
  subscribe(core, ui, 7, { topic: "newChat", scope: "w1" });
  subscribe(core, ui, 8, { topic: "newChat", scope: "w2" });
  await host.settle();
  apply(host, values);
  assert.deepEqual([v(values, 7).kept, v(values, 8).kept], ["a", ""]);
  // W1 read again without its station: what was kept of it goes, W2's stays.
  w1Stations = false;
  await run(inner.cloudSync.refreshAccount("s1"));
  await host.settle();
  assert.equal(inner.data.get({ topic: "overview", station: "w1/a" }), undefined);
  assert.notEqual(inner.data.get({ topic: "overview", station: "w2/b" }), undefined);
  // W1's account signs out: W1 is no one's, W2 is as it was.
  await run(inner.accounts.signOut("s1"));
  await host.time.pass(10);
  assert.deepEqual([inner.workspaces.owner("w1"), inner.workspaces.owner("w2")], [null, "s2"]);
  assert.notEqual(inner.data.get({ topic: "overview", station: "w2/b" }), undefined);
  slow.end();
  core.close();
});

test("a_chats_connection_says_only_what_is_of_its_workspace", async () => {
  const { host, core } = await started();
  const inner = core.inner;
  const ui = core.connect();
  const values = new Map();
  const settle = async () => {
    await host.settle();
    await host.settle();
  };
  subscribe(core, ui, 1, { topic: "connection", station: "ws/st" });
  await settle();
  apply(host, values);
  assert.deepEqual(v(values, 1), { items: [] });
  // Slow in another workspace: nothing of it here.
  const other = inner.workspaces.of("w9").status;
  const there = other.begin(STATION("w9/s"), "读取对话", false);
  other.skip(3_000);
  other.changed();
  await settle();
  apply(host, values);
  assert.deepEqual(v(values, 1), { items: [] });
  // Slow here: said at once (it has lasted a while), then 已连上 a moment once over.
  const ws = inner.workspaces.of("ws").status;
  const here = ws.begin(STATION("ws/st"), "读取对话", false);
  ws.skip(3_000);
  ws.changed();
  await settle();
  apply(host, values);
  assert.equal(v(values, 1).tone, "busy");
  assert.ok(String(v(values, 1).text).startsWith("studio 读取对话 · 3 秒"), JSON.stringify(v(values, 1)));
  here.end();
  await settle();
  apply(host, values);
  assert.deepEqual([v(values, 1).tone, v(values, 1).text], ["back", "已连接"]);
  there.end();
  core.close();
});

test("a_beta_app_says_so_and_an_account_not_let_in_is_blocked", async () => {
  const host = new FakeHost();
  host.isBeta = true;
  host.store(STORAGE_KEY, [account("s1", "a@x.com", "阿一", "a", "r", nowS(host) + 3600)]);
  let letIn = false;
  host.onFetch((req) => {
    const release = (code: number) => ({ versionCode: code, versionName: `0.1.${code}`, file: `android/stillfail-${code}.apk`, sha256: "ab", size: 9 });
    const saysBeta = req.headers.some(([k, val]) => k === "x-stillfail-channel" && val === "beta");
    const path = req.url.replace("https://stillfail.test", "");
    if (path === "/v1/me") {
      // As still.fail cloud gates a beta app's calls.
      if (saysBeta && !letIn) return jsonResponse(403, { error: "not_beta" });
      return jsonResponse(200, { user: { sub: "s1", beta: letIn }, workspaces: [{ id: "ws", name: "W" }], invitations: [], relay_url: "https://relay.test" });
    }
    if (path === "/releases/android/latest.json") return jsonResponse(200, release(1200));
    if (path === "/releases/android/beta/latest.json") return jsonResponse(200, release(1250));
    return jsonResponse(404, { error: "not_found" });
  });
  const core = await Core.create(host, { clock: host.time.clock, sample: 0 });
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "workspaces" });
  await host.settle();
  apply(host, values);
  let entry = v(values, 1)[0];
  assert.deepEqual([entry.blocked, entry.error?.code, entry.workspaces.length], ["此账号尚未开通测试版", "not_beta", 0]);
  assert.ok(host.requests.filter((r) => r.url.includes("/v1/")).every((r) => r.headers.some(([k]) => k === "x-stillfail-channel")));
  // Let in: its workspaces, marked as let in, nothing blocked.
  letIn = true;
  host.socketSend("/v1/events", '{"type":"workspaces"}');
  await host.settle();
  apply(host, values);
  entry = v(values, 1)[0];
  assert.deepEqual([entry.beta, entry.blocked, entry.workspaces[0].id], [true, undefined, "ws"]);
  // Its newer builds are the beta feed's.
  call(core, ui, 2, "app.update", { platform: "android", versionCode: 1100 });
  await host.settle();
  const answer = host.takeEmitted().map(([, m]) => m as J).find((m) => m.id === 2 && "ok" in m);
  assert.equal(answer?.ok.versionCode, 1250);
  core.close();
});

test("an_app_of_its_own_on_the_test_channel_reads_its_changelog_is_named_still_fail_and_takes_its_own_feed", async () => {
  // still.fail mbui: a build of every commit, the test channel's, but not youdid.wtf
  const host = new FakeHost();
  host.isBeta = true;
  const now = Math.round(host.nowMs() / 1000);
  const entry = (version: number, parts: string[], text: string) => ({ version, commit: "c", at: now, text: [text], fixes: [], parts });
  host.onFetch((req) => {
    const path = req.url.replace("https://stillfail.test", "");
    const beta = req.headers.some(([k, val]) => k === "x-stillfail-channel" && val === "beta");
    // The test channel's changelog a commit an entry, each its parts'; the stable channel's a release an entry, every part's.
    if (path === "/v1/changelog" && beta) return jsonResponse(200, { entries: [entry(1330, ["android"], "修复：安卓的"), entry(1325, ["station"], "修复：station 的")], released: { android: 1330, station: 1325 } });
    if (path === "/v1/changelog") return jsonResponse(200, { entries: [entry(1300, ["android", "desktop", "web", "station", "cloud"], "修复：一次发布的")], released: { android: 1300, station: 1300 } });
    if (path === "/releases/android/mbui/latest.json") return jsonResponse(200, { versionCode: 1330, versionName: "0.1.1330", file: "android/mbui/stillfail-1330.apk", sha256: "ab", size: 9 });
    return jsonResponse(404, {});
  });
  let core = await Core.create(host, { clock: host.time.clock, sample: 0 });
  const ui = core.connect();
  await ask(host, core, ui, 1, "client.device", { app: "android", build: "0.1.1320", client: "still.fail mbui" });
  subscribe(core, ui, 2, { topic: "changelog" });
  await host.settle();
  const values = new Map();
  answersOf(host, values);
  // Each part's tab its own changes.
  assert.deepEqual(v(values, 2).tabs.map((x: J) => [x.part, x.days.flatMap((d: J) => d.entries.map((e: J) => e.text[0]))]), [
    ["android", ["修复：安卓的"]], ["desktop", []], ["web", []], ["station", ["修复：station 的"]], ["cloud", []],
  ]);
  assert.equal(brandName(), "still.fail");
  // Its newer builds from its own feed as it names it, not that feed's beta.
  const newer = await ask(host, core, ui, 3, "app.update", { platform: "android/mbui", versionCode: 1320 });
  assert.equal(newer.versionCode, 1330);
  assert.ok(host.requests.every((r) => !r.url.includes("/mbui/beta/")));
  // Started again: named so before the device says what it is.
  await run(core.inner.data.written);
  core.close();
  core = await Core.create(host, { clock: host.time.clock, sample: 0 });
  assert.equal(brandName(), "still.fail");
  core.close();
});

const header = (r: { headers: [string, string][] }, name: string) => r.headers.find(([k]) => k === name)?.[1];
const exports = (host: FakeHost) => host.requests.filter((r) => r.url.endsWith("/v1/telemetry/traces"));
const spansOf = (r: { body?: Uint8Array | null }) => JSON.parse(new TextDecoder().decode(r.body!)).resourceSpans[0].scopeSpans[0].spans as J[];

test("a_chat_opening_is_one_trace_its_requests_carry_and_ember_cloud_gets", async () => {
  // Deliberately otherwise (docs/core-ts.md, rule 6): a chat opening reads only what is held, so it asks the station
  // nothing; what the Rust core's chat.open traced is the station's own reading, one trace from its connecting on.
  const { host, core } = await started({ ...base(), "GET /memory": { global: "" } }, 1);
  const ui = core.connect();
  const before = host.requests.length;
  subscribe(core, ui, 1, { topic: "chat", station: "ws/st", thread: 7 });
  await host.settle();
  await host.settle();
  const said = host.takeEmitted().map(([, m]) => m as J);
  assert.ok(said.some((m) => m.id === 1 && "value" in m), JSON.stringify(said).slice(0, 500));
  assert.equal(host.requests.length, before, "opening a chat asks nothing");
  const reads = ["/events?running=1", "/overview", "/sessions", "/threads", "/chats", "/jobs"].map((p) => host.requests.find((r) => r.url === `https://stillfail.test/admin/api${p}`)!);
  const parents = reads.map((r) => header(r, "traceparent")!);
  const trace = parents[0].slice(3, 35);
  assert.ok(parents.every((p) => p.slice(3, 35) === trace && p.endsWith("-01")), JSON.stringify(parents));
  // Spans wait to go out together.
  await host.time.pass(EXPORT_MS + 100);
  const sent = exports(host);
  assert.equal(sent.length, 1);
  assert.equal(header(sent[0], "authorization"), "Bearer tok");
  assert.equal(header(sent[0], "traceparent"), undefined, "sending spans is no trace");
  const spans = spansOf(sent[0]);
  const named = (name: string) => {
    const s = spans.find((x) => x.name === name);
    assert.ok(s, `no ${name}: ${JSON.stringify(spans.map((x) => x.name))}`);
    return s;
  };
  const connect = named("station.connect");
  assert.equal(connect.traceId, trace);
  assert.equal(connect.parentSpanId, undefined);
  assert.equal(named("GET /admin/api/events").parentSpanId, connect.spanId);
  const read = named("station.read");
  assert.equal(read.parentSpanId, connect.spanId);
  const threads = named("GET /admin/api/threads");
  assert.equal(threads.parentSpanId, read.spanId);
  assert.ok(parents.some((p) => p.slice(36, 52) === threads.spanId), "the request carries its own span");
  assert.equal(named("GET /admin/api/sessions").parentSpanId, read.spanId);
  // The chat's page waiting for it: a trace of its own, saying how much of its wait was the core making it.
  const open = named("chat.open");
  assert.equal(open.parentSpanId, undefined);
  const attrs = Object.fromEntries(open.attributes.map((a: J) => [a.key, Object.values(a.value)[0]]));
  assert.equal(attrs["stillfail.anew"], true);
  assert.ok(Number(attrs["stillfail.work_ms"]) >= 0 && Number(attrs["stillfail.computes"]) >= 1, JSON.stringify(attrs));
  assert.equal(open.status.code, 1);
  const text = JSON.stringify(spans);
  assert.ok(!text.includes("a@x.com") && !text.includes('"tok"'), text);
  // Nothing new: nothing more is sent.
  await host.time.pass(EXPORT_MS + 100);
  assert.equal(exports(host).length, 1);
  core.close();
});

test("calls_are_traces_and_nothing_goes_out_when_tracing_is_off", async () => {
  {
    const { host, core } = await started({ ...base(), "GET /memory": { global: "" } }, 1);
    const ui = core.connect();
    call(core, ui, 1, "memory.get", { station: "ws/st" });
    // Asking nothing, answered at once: not sent. Failing at once: sent.
    call(core, ui, 2, "chat.place", { station: "ws/st", thread: 7, seq: 3 });
    call(core, ui, 3, "picture", { url: "ftp://nope" });
    await host.settle();
    await host.time.pass(EXPORT_MS + 100);
    const names = exports(host).flatMap(spansOf).map((s) => s.name);
    assert.ok(names.includes("GET /admin/api/memory") && names.includes("memory.get"), JSON.stringify(names));
    assert.ok(!names.includes("chat.place") && names.includes("picture"), JSON.stringify(names));
    core.close();
  }
  const { host, core } = await started({ ...base(), "GET /memory": { global: "" } }, 0);
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "chat", station: "ws/st", thread: 7 });
  call(core, ui, 2, "memory.get", { station: "ws/st" });
  await host.settle();
  await host.time.pass(EXPORT_MS + 100);
  assert.equal(exports(host).length, 0);
  // Stations still hear that these are not recorded.
  const parents = host.requests.map((r) => header(r, "traceparent")).filter((p): p is string => p !== undefined);
  assert.ok(parents.length > 0 && parents.every((p) => p.endsWith("-00")), JSON.stringify(parents));
  core.close();
});

test("a_failure_let_go_of_is_a_failed_span_of_its_own", async () => {
  const { host, core } = await started({ ...base(), "GET /memory": { global: "" } }, 1);
  await host.time.pass(EXPORT_MS + 100);
  const before = exports(host).length;
  // Forked and let go of, as a kept file written in the background is: nothing waits on it.
  core.inner.runner.fork(Effect.ignore(Effect.fail(CoreError.host("disk full")), { log: "Unhandled", message: "speeds kept" }));
  core.inner.runner.fork(Effect.ignore(Effect.fail(CoreError.host("not told"))));
  await host.settle();
  await host.time.pass(EXPORT_MS + 100);
  const spans = exports(host).slice(before).flatMap(spansOf).filter((s) => s.name === "ignored");
  assert.equal(spans.length, 1, JSON.stringify(spans));
  const attrs = Object.fromEntries(spans[0].attributes.map((a: J) => [a.key, Object.values(a.value)[0]]));
  assert.deepEqual([attrs["stillfail.ignored"], attrs["error.type"], spans[0].status.code], ["speeds kept", "host", 2]);
  core.close();
});

test("a_streamed_preview_hands_its_answer_on_as_it_comes_until_cancelled_or_its_page_goes", async () => {
  const { host, core } = await started({ ...base(), "GET /memory": { global: "" } });
  // The service's answer: open, its body coming as it is sent here.
  const bodies: { queue: Queue.Queue<Uint8Array | null>; closed: boolean }[] = [];
  host.onFetchStream((req) =>
    Effect.gen(function* () {
      const queue = yield* Queue.unbounded<Uint8Array | null>();
      if (!req.url.includes("/preview/")) return { status: 200, headers: [], body: { take: Queue.take(queue) } };
      const body = { queue, closed: false };
      bodies.push(body);
      yield* Effect.addFinalizer(() => Effect.sync(() => (body.closed = true)));
      return { status: 200, headers: [["content-type", "text/event-stream"]] as [string, string][], body: { take: Queue.take(queue) } };
    }),
  );
  const ui = core.connect();
  const preview = (id: number) => call(core, ui, id, "station.preview", { station: "ws/st", port: 5180, method: "GET", path: "/events", stream: true });
  preview(1);
  await host.settle();
  const asked = [...host.requests].reverse().find((r) => r.url.includes("/preview/"))!;
  assert.equal(asked.url, "https://stillfail.test/admin/api/preview/5180/events");
  const said = () => host.takeEmitted().map(([, m]) => JSON.parse(JSON.stringify(m)));
  assert.deepEqual(said(), [{ id: 1, value: { head: { status: 200, headers: [["content-type", "text/event-stream"]] } } }]);
  const load = core.inner.workspaces.ofStation("ws/st").part("previewLoad", () => new Loads()) as Loads;
  assert.equal(load.value({ topic: "previewLoad", station: "ws/st", port: 5180 }).percent, 100);
  // Nothing is said to be waited on once its head came, however long its body goes on.
  core.inner.status.skip(3_000);
  assert.equal((core.inner.status.value() as J).state ?? null, null);
  Queue.offerUnsafe(bodies[0].queue, new TextEncoder().encode("data: 1\n\n"));
  await host.settle();
  // Each piece beside its value, not in it.
  const piece = host.takeEmitted().map(([, m]) => m as J);
  assert.deepEqual(piece.map((m) => ({ id: m.id, value: m.value })), [{ id: 1, value: { chunk: true } }]);
  assert.equal(new TextDecoder().decode(piece[0].bytes), "data: 1\n\n");
  // Cancelled: it answers so, and the body is let go (the station stops asking the service).
  core.receive(ui, { kind: "cancel", id: 1, cancel: true });
  await host.settle();
  assert.deepEqual(said(), [{ id: 1, error: { code: "cancelled", message: "已取消" } }]);
  assert.ok(bodies[0].closed);
  // A page gone takes its calls with it.
  preview(2);
  await host.settle();
  core.disconnect(ui);
  await host.settle();
  assert.ok(bodies[1].closed);
  assert.equal(core.inner.calls.size, 0);
  // Any other call runs to its end, cancelled or not: a write is not dropped halfway.
  const ui2 = core.connect();
  call(core, ui2, 3, "memory.get", { station: "ws/st" });
  core.receive(ui2, { kind: "cancel", id: 3, cancel: true });
  core.disconnect(ui2);
  await host.settle();
  assert.ok(said().some((m) => m.id === 3 && "ok" in m), "answered, not cancelled");
  core.close();
});

test("a_preview_socket_is_only_carried_by_the_mesh_and_its_messages_are_checked", async () => {
  const { host, core } = await started();
  const ui = core.connect();
  call(core, ui, 1, "preview.socket", { station: "ws/st", port: 5180, path: "/", socket: "s1" });
  call(core, ui, 2, "preview.socket.send", { socket: "s1", text: "hi" });
  await host.settle();
  const said = new Map(host.takeEmitted().map(([, m]) => [(m as J).id, JSON.parse(JSON.stringify(m))]));
  assert.equal(said.get(1).error.code, "unsupported");
  assert.equal(said.get(2).error.code, "not_found", "no socket open by that name");
  assert.throws(() => parseCall("preview.socket.send", { socket: "s1", text: "a", close: [1000, ""] }));
  assert.deepEqual(parseCall("preview.socket.send", { socket: "s1", close: [4001, "done"] }), { kind: "previewSocketSend", socket: "s1", frame: { close: [4001, "done"] } });
  assert.deepEqual(parseCall("preview.socket.send", { socket: "s1", binary: true }, new Uint8Array([0, 1])), { kind: "previewSocketSend", socket: "s1", frame: { binary: new Uint8Array([0, 1]) } });
  assert.throws(() => parseCall("preview.socket.send", { socket: "s1", binary: true }), "a binary frame's bytes come beside the call");
  core.close();
});

test("a_preview_socket_closed_before_it_opens_does_not_wait_for_the_station", async () => {
  // A station that never answers a socket: the page's close ends it; what was sent before it is let go with it.
  const { host, core } = await started(base(), 0, (h) => {
    const wire = new HostWire(h);
    return { request: (s, head, body) => wire.request(s, head, body), socket: () => Effect.never };
  });
  const ui = core.connect();
  call(core, ui, 1, "preview.socket", { station: "ws/st", port: 5180, path: "/", socket: "s1" });
  await host.settle();
  call(core, ui, 2, "preview.socket.send", { socket: "s1", text: "early" });
  call(core, ui, 3, "preview.socket.send", { socket: "s1", close: [1001, "gone"] });
  await host.settle();
  const said = new Map(host.takeEmitted().map(([, m]) => [(m as J).id, JSON.parse(JSON.stringify(m))]));
  assert.deepEqual(said.get(1), { id: 1, ok: { code: 1001, reason: "gone" } });
  assert.deepEqual([said.get(2).ok, said.get(3).ok], [null, null]);
  core.close();
});

const posted = (host: FakeHost, path = "/threads/7/messages") =>
  host.requests.filter((r) => r.method === "POST" && r.url.endsWith(path)).map((r) => JSON.parse(new TextDecoder().decode(r.body!)));
const errors = (host: FakeHost, ids: number[]) => host.takeEmitted().filter(([, m]) => ids.includes((m as J).id) && "error" in (m as J)).length;

test("a_decision_is_answered_in_its_chat_and_dismissed_on_the_station", async () => {
  let n = 3;
  const { host, core } = await started({ ...base(), "PUT /threads/7/dismissed": {} });
  stationReplies(host, (req) => (req.method === "POST" && req.url.endsWith("/threads/7/messages") ? { n: ++n } : undefined));
  const ui = core.connect();
  const decision = { seq: 4, options: [{ label: "合", recommended: true }, { label: "先不改" }], message: { seq: 4, ts: "9.000004", text: "合吗？", authorName: "Claude" }, before: [] };
  core.inner.data.set({ topic: "chatRows", station: "ws/st" }, [{ id: "k1", session: "k1", thread: 7, decision }]);
  // Answered: the option's label, quoting the post that asked.
  call(core, ui, 3, "decision.answer", { station: "ws/st", thread: 7, seq: 4, option: "先不改" });
  await host.settle();
  let sent = posted(host);
  assert.equal(sent[0].text, "先不改");
  assert.deepEqual(sent[0].quotes, [{ author: "Claude", text: "合吗？", comment: "", role: "agent", ts: "9.000004" }]);
  // Dismissed: the station keeps it for the viewer.
  call(core, ui, 7, "decision.dismiss", { station: "ws/st", thread: 7, seq: 4 });
  await host.settle();
  const dismissed = host.requests.filter((r) => r.method === "PUT" && r.url.endsWith("/threads/7/dismissed")).map((r) => JSON.parse(new TextDecoder().decode(r.body!)));
  assert.deepEqual(dismissed, [{ n: 4 }]);
  // An option it does not offer, or a decision no longer pending: refused.
  host.takeEmitted();
  call(core, ui, 4, "decision.answer", { station: "ws/st", thread: 7, seq: 4, option: "别的" });
  call(core, ui, 5, "decision.answer", { station: "ws/st", thread: 7, seq: 3, option: "合" });
  await host.settle();
  assert.equal(errors(host, [4, 5]), 2);
  assert.equal(posted(host).length, 1);
  // Both options and text cards accept free-form replies; text cards have no choices.
  core.inner.data.set({ topic: "chatRows", station: "ws/st" }, [{ id: "k1", session: "k1", thread: 7, decision }]);
  call(core, ui, 8, "decision.reply", { station: "ws/st", thread: 7, seq: 4, text: "随便" });
  await host.settle();
  assert.equal(errors(host, [8]), 0);
  assert.equal(posted(host)[1].text, "随便");
  assert.equal(posted(host)[1].quotes[0].ts, "9.000004");
  // The shared chat composer can send a file alone and additional quoted passages.
  const attachments = [{ name: "screen.png", path: "uploads/screen.png", size: 12 }];
  const extraQuotes = [{ author: "林晓", text: "看这一处", comment: "", role: "person" }];
  call(core, ui, 12, "decision.reply", { station: "ws/st", thread: 7, seq: 4, text: "", attachments, quotes: extraQuotes });
  await host.settle();
  assert.deepEqual(posted(host)[2].attachments, attachments);
  assert.equal(posted(host)[2].quotes[0].ts, "9.000004");
  assert.deepEqual(posted(host)[2].quotes[1], extraQuotes[0]);
  const card = { seq: 6, card: { type: "text", placeholder: "sk_" }, message: { seq: 6, ts: "9.000006", text: "key？", authorName: "Claude" }, before: [] };
  core.inner.data.set({ topic: "chatRows", station: "ws/st" }, [{ id: "k1", session: "k1", thread: 7, card }]);
  host.takeEmitted();
  call(core, ui, 9, "decision.answer", { station: "ws/st", thread: 7, seq: 6, option: "sk_" });
  call(core, ui, 10, "decision.reply", { station: "ws/st", thread: 7, seq: 5, text: "sk_test_1" });
  await host.settle();
  assert.equal(errors(host, [9, 10]), 2, "an option of a text card; a card no longer pending");
  call(core, ui, 11, "decision.reply", { station: "ws/st", thread: 7, seq: 6, text: " sk_test_1 " });
  await host.settle();
  sent = posted(host);
  assert.equal(sent.length, 4);
  assert.equal(sent[3].text, "sk_test_1");
  assert.deepEqual(sent[3].quotes, [{ author: "Claude", text: "key？", comment: "", role: "agent", ts: "9.000006" }]);
  core.close();
});

test("what_an_agent_needs_let_go_in_its_chat_is_said_let_go_at_once_and_back_when_its_station_refuses", async () => {
  const agent = { ...session("k1"), status: "idle", lastTurn: { id: "t", kind: "input", startedAt: 1, endedAt: 2, outcome: "completed", declared: "block", ending: "need_help", need: "在手机上试新列表" } };
  const need = { seq: 3, message: { seq: 3, thread: 7, ts: "9.000003", authorKind: "agent", author: "k1", authorName: "Claude", text: "你试一下", attachments: [], quotes: [], declared: null, createdAt: 1, editedAt: null }, before: [] };
  const { host, core } = await started({ ...base(), "GET /chats": [{ id: "7", thread: 7, session: "k1", title: "部署", agents: [agent], lastActiveAt: 1, need }] });
  // The station's answer held until told: what is said meanwhile is the core's own.
  let answer: (res: ReturnType<typeof jsonResponse>) => void = () => {};
  stationLater(host, (req) => (req.method === "PUT" && req.url.endsWith("/threads/7/dismissed") ? new Promise((r) => (answer = r)) : undefined));
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "chat", station: "ws/st", thread: 7 });
  await host.settle();
  apply(host, values);
  const state = () => [v(values, 1).stateLead, v(values, 1).stateAsk ?? null];
  assert.deepEqual(state(), ["need", 3]);
  // Let go: said so before the station answers.
  call(core, ui, 2, "decision.dismiss", { station: "ws/st", thread: 7, seq: 3 });
  await host.settle();
  apply(host, values);
  assert.deepEqual(state(), ["dismissed", null]);
  assert.equal(v(values, 1).stateText, "已忽略：在手机上试新列表");
  // Refused: what it needs is back, to be let go again.
  answer(jsonResponse(403, { error: "不行" }));
  await host.settle();
  apply(host, values);
  assert.deepEqual(state(), ["need", 3]);
  core.close();
});

test("an_app_of_its_own_names_the_device_by_itself_not_by_still_fail", async () => {
  // still.fail mbui (apps/mbui) runs this core too: those approving its device tell it apart from still.fail's own app
  const { host, core } = await started();
  const ui = core.connect();
  call(core, ui, 1, "client.device", { app: "android", build: "0.1.3628", model: "OPPO PLP110", client: "still.fail mbui", locale: "zh-CN" });
  call(core, ui, 2, "auth.begin", { redirect_uri: "r", return_to: "/" });
  await host.settle();
  const emitted = host.takeEmitted().map(([, m]) => m as J);
  const url = String(emitted.find((m) => m.id === 2 && "ok" in m).ok.url);
  assert.ok(url.includes(`name=${encode("still.fail mbui Android · OPPO PLP110")}`), url);
  core.close();
});

test("a_device_whose_host_says_its_own_name_is_named_by_it_which_of_the_persons_devices_it_is", async () => {
  // The phone's name as its settings say, the Mac's own: in place of the model or the system
  const { host, core } = await started();
  const ui = core.connect();
  call(core, ui, 1, "client.device", { app: "android", build: "0.1.5600", model: "OPPO PLP110", machine: " OPPO Find N5 ", client: "still.fail mbui", locale: "zh-CN" });
  call(core, ui, 2, "auth.begin", { redirect_uri: "r", return_to: "/" });
  await host.settle();
  const emitted = host.takeEmitted().map(([, m]) => m as J);
  const url = String(emitted.find((m) => m.id === 2 && "ok" in m).ok.url);
  assert.ok(url.includes(`name=${encode("still.fail mbui Android · OPPO Find N5")}`), url);
  call(core, ui, 3, "client.device", { app: "desktop", build: "0.1.5600", userAgent: "Macintosh; Mac OS X", machine: "林的 MacBook Air", client: "still.fail mbui", locale: "zh-CN" });
  call(core, ui, 4, "auth.begin", { redirect_uri: "r", return_to: "/" });
  await host.settle();
  const again = host.takeEmitted().map(([, m]) => m as J);
  const named = String(again.find((m) => m.id === 4 && "ok" in m).ok.url);
  assert.ok(named.includes(`name=${encode("still.fail mbui 桌面版 · 林的 MacBook Air")}`), named);
  core.close();
});

test("an_iphone_app_is_a_phone_named_by_its_model_and_its_messages_say_it", async () => {
  // still.fail mbui on iOS: a phone as Android's, its device named so, a message going with the app it is sent from
  const { host, core } = await started();
  stationReplies(host, (req) => (req.method === "POST" && req.url.endsWith("/threads/7/messages") ? { n: 4 } : undefined));
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "prefs" });
  call(core, ui, 2, "client.device", { app: "ios", build: "0.1.3700", model: "iPhone17,1", client: "still.fail mbui" });
  await host.settle();
  const values = new Map();
  apply(host, values);
  assert.deepEqual(v(values, 1).device, { app: "ios", phone: true, handoff: false });
  call(core, ui, 3, "auth.begin", { redirect_uri: "r", return_to: "/" });
  await host.settle();
  const emitted = host.takeEmitted().map(([, m]) => m as J);
  const url = String(emitted.find((m) => m.id === 3 && "ok" in m).ok.url);
  assert.ok(url.includes(`name=${encode("still.fail mbui iOS · iPhone17,1")}`), url);
  call(core, ui, 4, "chat.send", { station: "ws/st", thread: 7, text: "hi" });
  await host.settle();
  assert.equal(posted(host)[0].client, "ios 0.1.3700");
  core.close();
});

test("a_chat_whose_agent_is_in_slack_threads_copies_what_is_sent_to_those_ticked", async () => {
  const { host, core } = await started({
    ...base(),
    "GET /threads": [{ ...threadView(7, 0), cc: [
      { thread: 21, surface: "slack:T1", channel: "C1", threadTs: "1.0", channelName: "still-fail" },
      { thread: 22, surface: "feishu:fs", channel: "oc_1", threadTs: "2.0", channelName: "产品讨论" },
    ] }],
    "GET /threads/7/entries?limit=50": { first: 1, last: 0, entries: [] },
  });
  stationReplies(host, (req) => (req.method === "POST" && req.url.endsWith("/threads/7/messages") ? { n: 1 } : undefined));
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "chat", station: "ws/st", thread: 7 });
  await host.settle();
  apply(host, values);
  // None ticked until ticked: a message goes to the chat alone.
  assert.deepEqual(v(values, 1).cc, [
    { thread: 21, place: "#still-fail", via: "slack", on: false },
    { thread: 22, place: "产品讨论", via: "feishu", on: false },
  ]);
  call(core, ui, 2, "chat.send", { station: "ws/st", thread: 7, text: "here" });
  await host.settle();
  assert.equal(posted(host)[0].cc, undefined);
  // Both ticked: the chat says so, and what is sent goes to both.
  call(core, ui, 3, "chat.cc", { station: "ws/st", thread: 7, to: 21, on: true });
  call(core, ui, 4, "chat.cc", { station: "ws/st", thread: 7, to: 22, on: true });
  await host.settle();
  apply(host, values);
  assert.deepEqual(v(values, 1).cc.map((o: J) => o.on), [true, true]);
  call(core, ui, 5, "chat.send", { station: "ws/st", thread: 7, text: "there too" });
  await host.settle();
  assert.deepEqual(posted(host)[1].cc, [21, 22]);
  // One unticked.
  call(core, ui, 6, "chat.cc", { station: "ws/st", thread: 7, to: 21, on: false });
  call(core, ui, 7, "chat.send", { station: "ws/st", thread: 7, text: "to feishu" });
  await host.settle();
  apply(host, values);
  assert.deepEqual(v(values, 1).cc.map((o: J) => o.on), [false, true]);
  assert.deepEqual(posted(host)[2].cc, [22]);
  core.close();
});

test("the_device_says_what_it_is_once_and_the_core_decides_what_follows", async () => {
  const { host, core } = await started();
  stationReplies(host, (req) => (req.method === "POST" && req.url.endsWith("/threads/7/messages") ? { n: 4 } : undefined));
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "prefs" });
  const phone = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";
  call(core, ui, 2, "client.device", { app: "web", build: "0.1.9", userAgent: phone });
  await host.settle();
  let values = new Map();
  apply(host, values);
  assert.deepEqual(v(values, 1).device, { app: "web", phone: true, handoff: false });
  // A message goes with the app it is sent from, unless the UI says.
  call(core, ui, 3, "chat.send", { station: "ws/st", thread: 7, text: "hi" });
  await host.settle();
  assert.equal(posted(host)[0].client, "web 0.1.9 (phone)");
  // A computer's browser: its links are offered to the desktop app first; it signs in by its browser's name.
  const mac = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36";
  call(core, ui, 4, "client.device", { app: "web", userAgent: mac });
  call(core, ui, 5, "auth.begin", { redirect_uri: "r", return_to: "/" });
  call(core, ui, 6, "client.device", { app: "phone" });
  await host.settle();
  const emitted = host.takeEmitted().map(([, m]) => m as J);
  const url = String(emitted.find((m) => m.id === 5 && "ok" in m).ok.url);
  assert.ok(url.includes(`name=${encode("still.fail 网页版 · Chrome · macOS")}`), url);
  assert.ok(emitted.some((m) => m.id === 6 && "error" in m));
  core.receive(ui, { kind: "unsubscribe", id: 1, unsubscribe: true });
  subscribe(core, ui, 7, { topic: "prefs" });
  await host.settle();
  values = new Map();
  apply(host, values);
  assert.deepEqual(v(values, 7).device, { app: "web", phone: false, handoff: true });
  core.close();
});

/// A call answered: its `ok`, or its error thrown (core/tests.rs `call`); what else came stays to be read.
async function ask(host: FakeHost, core: Core, ui: number, id: number, name: string, params: unknown): Promise<J> {
  call(core, ui, id, name, params);
  await host.settle();
  let out: { ok: J } | { error: J } | null = null;
  const rest: typeof host.emitted = [];
  for (const [c, m] of host.takeEmitted()) {
    const x = m as J;
    if (x.id === id && "ok" in x) out = { ok: x.ok };
    else if (x.id === id && "error" in x) out = { error: x.error };
    else rest.push([c, m]);
  }
  host.emitted.push(...rest);
  if (!out) throw new Error(`${name} not answered`);
  if ("error" in out) throw Object.assign(new Error(out.error.message), out.error);
  return out.ok;
}

const stationPosted = (host: FakeHost, path: string) =>
  host.requests.filter((r) => r.method === "POST" && r.url.endsWith(`/admin/api${path}`)).map((r) => (r.body && r.body.length > 0 ? JSON.parse(new TextDecoder().decode(r.body)) : null));

test("a_draft_written_as_it_is_typed_is_one_write_and_read_by_its_key", async () => {
  const { host, core } = await started();
  const ui = core.connect();
  for (const [id, text] of [[1, "修"], [2, "修一"], [3, "修一下"]] as const) call(core, ui, id, "draft.put", { key: "ws/st:thread:7", text, quotes: [], files: [] });
  await host.settle();
  const kept = () => host.rows(dbName("s1"), "SELECT json FROM draft ORDER BY station, chat").map(([json]) => JSON.parse(json as string).text);
  // There at once; on the device a moment after the last change, as it is then.
  assert.deepEqual(kept(), []);
  assert.equal((await ask(host, core, ui, 4, "draft.get", { key: "ws/st:thread:7" })).text, "修一下");
  await host.time.pass(SOON_MS + 50);
  await host.settle();
  assert.deepEqual(kept(), ["修一下"]);
  // Emptied before it was written: nothing is written after all.
  call(core, ui, 5, "draft.put", { key: "new:ws", text: "新的" });
  call(core, ui, 6, "draft.put", { key: "new:ws", text: "" });
  await host.time.pass(SOON_MS + 50);
  await host.settle();
  assert.deepEqual(kept(), ["修一下"]);
  assert.deepEqual(noId(await ask(host, core, ui, 7, "draft.get", { key: "new:ws" })), { text: "", quotes: [], files: [] });
  core.close();
});

test("a_profile_added_through_the_flow_is_posted_and_answers_its_id", async () => {
  const { host, core } = await started({ ...base(), "GET /overview": { ...overview, apiProviders: [{ id: "jev" }, { id: "groq" }] }, "POST /profiles": { id: "jev", overview: {} } });
  const ui = core.connect();
  // (The Rust test named a station of no workspace, which its fetch-everything wire still answered; here it is the
  // workspace's own, whose overview the core holds.)
  const params = { station: "ws/st", form: "add-test" };
  await ask(host, core, ui, 1, "profile.flow.open", params);
  const edit = (input: unknown) => ({ station: "ws/st", form: "add-test", input });
  await ask(host, core, ui, 2, "profile.flow.edit", edit({ provider: "jev" }));
  await ask(host, core, ui, 3, "profile.flow.edit", edit({ key: "k" }));
  await ask(host, core, ui, 4, "profile.flow.submit", params);
  const sent = stationPosted(host, "/profiles");
  assert.equal(sent.length, 1, "the add reaches the station");
  assert.equal(sent[0].access.provider, "jev");
  core.close();
});

test("token_forms_publish_core_validation_and_keep_the_legacy_call_working", async () => {
  const { host, core } = await started({
    ...base(),
    "POST /slack/verify": { identity: { team: "T", teamId: "T1", url: "https://t.slack.com", botUserId: "B1", botName: "bot" }, errors: [] },
  });
  const ui = core.connect();
  const topic = { topic: "slackTokens", station: "ws/st", form: "f" };
  subscribe(core, ui, 1, topic);
  assert.equal((await ask(host, core, ui, 10, "slack.tokens.edit", { station: "ws/st", form: "f", input: { appToken: "app", botToken: "bot" } })).ready, true);
  const form = { station: "ws/st", form: "f" };
  assert.equal(await ask(host, core, ui, 11, "slack.tokens.verify", form), true);
  const values = new Map();
  apply(host, values);
  assert.equal(v(values, 1).verified.botName, "bot");
  assert.equal(stationPosted(host, "/slack/verify").length, 1);
  assert.equal(await ask(host, core, ui, 12, "slack.tokens.verify", form), true);
  assert.equal(stationPosted(host, "/slack/verify").length, 1, "a verified draft need not be checked again");
  // Existing pages still call the original operation.
  await ask(host, core, ui, 13, "slack.verify", { station: "ws/st", appToken: "app", botToken: "bot" });
  assert.equal(stationPosted(host, "/slack/verify").length, 2);
  await ask(host, core, ui, 14, "slack.tokens.drop", form);
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 1).appToken, "");
  await assert.rejects(ask(host, core, ui, 15, "slack.tokens.verify", form));
  core.close();
});

const profile = (id: string, runtime: string, models: string[], checked: boolean, used: number, extra: J = {}) => ({
  id, name: `${id}@x.com`, runtime, runtimes: [runtime], access: { kind: "subscription", key: "" }, home: "/h", homeExists: true, model: null, models,
  env: [], usedBy: [], loginCommand: "", check: checked ? { state: "ok", detail: "", checkedAt: 1 } : null,
  quota: { state: "ok", windows: [{ label: "5 小时", usedPercent: used, resetsAt: null }], detail: null, checkedAt: 1 }, ...extra,
});

/// A core whose station has three profiles: p1 (unchecked) and p2 run Claude Code, p3 Codex (core/tests.rs
/// `choosing_core`); `speed`: its session on Codex with `fast` as given, p3 offering `fast` as `profileFast`.
async function choosing(speed = false, profileFast = false, sessionFast: boolean | null = null) {
  const s = (key: string) => (speed ? { ...session(key), runtime: "codex", model: "gpt-6-astra", profile: "p3", fast: sessionFast } : session(key));
  return started({
    ...base(),
    "GET /overview": {
      ...overview,
      profiles: [
        profile("p1", "claude", ["claude-opus-5-5", "claude-sonnet-5"], false, 10),
        profile("p2", "claude", ["claude-opus-5-5"], true, 80),
        profile("p3", "codex", ["gpt-6-astra"], true, 0, speed ? { fast: profileFast } : {}),
      ],
    },
    "GET /sessions": [s("k1")],
    "GET /sessions/k1": { session: s("k1"), threads: [], turns: [], jobs: [] },
    "GET /machine-sessions": { sessions: [{ runtime: "codex", id: "m1", cwd: "/Users/bob/src/x", updatedAt: 0 }] },
    "POST /profiles/p1/check": { state: "ok", detail: "", checkedAt: 2 },
    "POST /sessions/k1/settings": { ok: true },
  });
}

test("new_chat_combos_are_local_to_a_workspace_persist_and_pick_model_and_depth_together", async () => {
  const { host, core } = await choosing();
  let ui = core.connect();
  const topic = { topic: "newChat", scope: "ws" };
  subscribe(core, ui, 1, topic);
  await host.settle();
  let values = new Map();
  apply(host, values);
  assert.deepEqual(v(values, 1).frequent, []);
  await ask(host, core, ui, 2, "newChat.pick", { scope: "ws", model: "gpt-6-astra", runtime: "codex", effort: "medium", fast: true });
  apply(host, values);
  assert.deepEqual(v(values, 1).frequent, [], "picking alone is not usage");
  core.inner.choose.used("other/st", { model: "claude-opus-5-5", runtime: "claude", effort: "high" });
  await ask(host, core, ui, 3, "newChat.create", { station: "ws/st" });
  apply(host, values);
  const combos = v(values, 1).frequent;
  assert.equal(combos.length, 1, "another workspace's history must not appear");
  assert.equal(combos[0].effort, "medium");
  await run(core.inner.data.written);
  core.close();
  host.takeEmitted();
  const again = await Core.create(host, { clock: host.time.clock, sample: 0, wire: () => new HostWire(host) });
  ui = again.connect();
  subscribe(again, ui, 1, topic);
  await host.settle();
  values = new Map();
  apply(host, values);
  const combo = v(values, 1).frequent[0];
  assert.equal(combo.model, "gpt-6-astra");
  assert.equal(combo.fast, true);
  await ask(host, again, ui, 2, "newChat.pick", { scope: "ws", model: "claude-opus-5-5", effort: "low", fast: false });
  await ask(host, again, ui, 3, "newChat.pick", { scope: "ws", model: combo.model, runtime: combo.runtime, effort: combo.effort, fast: combo.fast });
  apply(host, values);
  assert.equal(v(values, 1).model.model, "gpt-6-astra");
  assert.equal(v(values, 1).effort, "medium");
  assert.equal(v(values, 1).fast, true);
  assert.equal(v(values, 1).frequent[0].selected, true);
  again.close();
});

test("a_new_chat_runs_on_what_was_last_picked_there_as_far_as_the_station_still_has_it", async () => {
  const { host, core } = await choosing();
  let ui = core.connect();
  // What the page kept before the core did comes in once.
  await ask(host, core, ui, 1, "newChat.migrate", { choices: { st: { runtime: "claude", model: "claude-sonnet-5", effort: "low", profile: "" } }, last: "st" });
  const topic = { topic: "newChat", scope: "ws" };
  subscribe(core, ui, 2, topic);
  await host.settle();
  let values = new Map();
  apply(host, values);
  let n = v(values, 2);
  assert.deepEqual([n.kept, n.station.id], ["st", "st"]);
  assert.deepEqual([n.model.model, n.runtime, n.effort], ["claude-sonnet-5", "claude", "low"]);
  assert.deepEqual([n.waiting, n.blocked ?? null, n.pickAccount], [false, null, false]);
  // Its unchecked profile is checked, once.
  assert.equal(stationPosted(host, "/profiles/p1/check").length, 1);
  assert.equal(stationPosted(host, "/profiles/p2/check").length, 0);
  // An account kept to that does not run the model gives way to the station's pick.
  await ask(host, core, ui, 3, "newChat.pick", { scope: "ws", model: "claude-opus-5-5", profile: "p3" });
  apply(host, values);
  n = v(values, 2);
  assert.deepEqual([n.model.model, n.effort, n.profile ?? null], ["claude-opus-5-5", "low", null]);
  assert.equal(n.accounts.length, 2);
  assert.equal(n.pickAccount, true);
  assert.deepEqual(n.accounts[0].quotaLine, { text: "5 小时 90%" });
  assert.deepEqual(n.accounts[1].quotaLine, { text: "5 小时剩余 20%", level: "amber" });
  // A model on another runtime takes it, and its default depth.
  await ask(host, core, ui, 4, "newChat.pick", { scope: "ws", model: "gpt-6-astra" });
  apply(host, values);
  assert.deepEqual([v(values, 2).runtime, v(values, 2).effort ?? null], ["codex", null]);
  // Kept across a restart; what an older page kept does not come in over it.
  await run(core.inner.data.written);
  core.close();
  host.takeEmitted();
  const again = await Core.create(host, { clock: host.time.clock, sample: 0, wire: () => new HostWire(host) });
  await host.time.pass(500);
  ui = again.connect();
  await ask(host, again, ui, 1, "newChat.migrate", { choices: { st: { runtime: "claude", model: "claude-sonnet-5", effort: "", profile: "" } } });
  subscribe(again, ui, 2, topic);
  await host.settle();
  values = new Map();
  apply(host, values);
  assert.equal(v(values, 2).model.model, "gpt-6-astra");
  // The model control of a new chat there: picked in its panel, then saved as what it runs on.
  subscribe(again, ui, 5, { topic: "pick", station: "ws/st", of: "new" });
  await host.settle();
  apply(host, values);
  assert.deepEqual([v(values, 5).changed, v(values, 5).value.runtime, v(values, 5).account ?? null], [false, "codex", null]);
  await ask(host, again, ui, 6, "pick.set", { station: "ws/st", of: "new", model: "claude-opus-5-5", profile: "p2" });
  apply(host, values);
  const p = v(values, 5);
  assert.deepEqual([p.changed, p.draft.runtime, p.draft.profile, p.who], [true, "claude", "p2", "p2"]);
  assert.equal(v(values, 2).model.model, "gpt-6-astra", "only a draft until saved");
  assert.equal((await ask(host, again, ui, 7, "pick.save", { station: "ws/st", of: "new" })).saved, true);
  apply(host, values);
  assert.deepEqual([v(values, 2).model.model, v(values, 2).profile], ["claude-opus-5-5", "p2"]);
  // Kept to an account running low: the control names it, amber.
  assert.deepEqual(v(values, 5).account, { text: "p2@x.com", auto: false, level: "amber" });
  // A chat made there is asked for with it, and the scope's next new chat starts there too.
  const made = await ask(host, again, ui, 8, "newChat.create", { station: "ws/st" });
  assert.ok(String(made.key).startsWith(PENDING_PREFIX), JSON.stringify(made));
  // named as the core names what it makes (localId), not from the clock: a replay gets the recorded key again
  assert.match(String(made.key), /^new:chat-[0-9a-f]{18}$/);
  await host.settle();
  const last = stationPosted(host, "/sessions").at(-1);
  assert.deepEqual([last?.model, last?.profile], ["claude-opus-5-5", "p2"]);
  // Refused: no scope, no station.
  await assert.rejects(ask(host, again, ui, 9, "newChat.pick", { model: "x" }));
  await assert.rejects(ask(host, again, ui, 10, "pick.set", { station: "ws/st", of: "nothing" }));
  again.close();
});

test("a_sessions_model_control_says_what_changes_and_saves_it_on_the_station", async () => {
  const { host, core } = await choosing();
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "pick", station: "ws/st", of: "session:k1" });
  await host.settle();
  const values = new Map();
  apply(host, values);
  let p = v(values, 1);
  // It runs on p1, the station's pick, with no model set.
  assert.deepEqual([p.runtimeFixed, p.value.model ?? null, p.account.text], [true, null, "自动 · p1@x.com"]);
  assert.equal(p.saveText, "无变更");
  // Kept to p2 and moved to Sonnet, which p2 does not run: back to the station's pick, said so.
  await ask(host, core, ui, 2, "pick.set", { station: "ws/st", of: "session:k1", profile: "p2" });
  await ask(host, core, ui, 3, "pick.set", { station: "ws/st", of: "session:k1", model: "claude-sonnet-5", effort: "high" });
  apply(host, values);
  p = v(values, 1);
  assert.equal(p.draft.profile ?? null, null);
  assert.ok(String(p.dropped).includes("已改为自动分配"), JSON.stringify(p));
  assert.ok(String(p.force).startsWith("所选账号「p2」未启用"), JSON.stringify(p));
  assert.equal(p.whoLevel, "amber");
  assert.equal(p.becomes[1], "high");
  assert.equal(p.changed, true);
  await ask(host, core, ui, 4, "pick.save", { station: "ws/st", of: "session:k1" });
  assert.deepEqual(stationPosted(host, "/sessions/k1/settings"), [{ model: "claude-sonnet-5", effort: "high", profile: null }]);
  // Opened again: from what it runs on.
  await ask(host, core, ui, 5, "pick.set", { station: "ws/st", of: "session:k1", open: true });
  apply(host, values);
  assert.equal(v(values, 1).draft.effort ?? null, null);
  // The machine's own sessions come each with its line.
  const listed = await ask(host, core, ui, 6, "machineSessions.list", { station: "ws/st" });
  assert.ok(String(listed.sessions[0].meta).startsWith("Codex · ~/src/x · "), JSON.stringify(listed));
  core.close();
});

test("a_sessions_account_is_picked_again_beside_auto_and_says_which", async () => {
  const { host, core } = await choosing();
  let picked = "p2";
  stationReplies(host, (req) => (req.method === "POST" && req.url.endsWith("/sessions/k1/settings") ? { ok: true, profile: picked } : undefined));
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "pick", station: "ws/st", of: "session:k1" });
  await host.settle();
  const values = new Map();
  apply(host, values);
  // On p1, with p2 able to take it: picked again beside 自动.
  assert.equal(v(values, 1).repick, "重新分配");
  // Kept to p1 in the panel, another depth too: the account gives way to the station's pick, the depth stays drafted.
  await ask(host, core, ui, 2, "pick.set", { station: "ws/st", of: "session:k1", profile: "p1", effort: "high" });
  assert.deepEqual(await ask(host, core, ui, 3, "pick.repick", { station: "ws/st", of: "session:k1" }), { profile: "p2", said: "已改用 p2@x.com" });
  assert.deepEqual(stationPosted(host, "/sessions/k1/settings"), [{ profile: null, repick: true }]);
  apply(host, values);
  assert.deepEqual([v(values, 1).draft.profile ?? null, v(values, 1).draft.effort], [null, "high"]);
  // The station keeps it where it was: said so.
  picked = "p1";
  assert.equal((await ask(host, core, ui, 4, "pick.repick", { station: "ws/st", of: "session:k1" })).said, "仍使用 p1@x.com");
  // A new chat's control has nothing to pick again.
  subscribe(core, ui, 5, { topic: "pick", station: "ws/st", of: "new" });
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 5).repick ?? null, null);
  await assert.rejects(ask(host, core, ui, 6, "pick.repick", { station: "ws/st", of: "new" }));
  core.close();
});

test("a_chat_referred_to_goes_out_as_a_link_to_it", async () => {
  const { host, core } = await started();
  stationReplies(host, (req) => (req.method === "POST" && req.url.endsWith("/threads/7/messages") ? { n: 4 } : undefined));
  const ui = core.connect();
  assert.deepEqual(await ask(host, core, ui, 1, "chat.ref", { station: "ws/st", id: "ember:c 1", title: "排查 [登录]", base: "https://x" }), { mark: "@[排查 登录]" });
  assert.deepEqual(await ask(host, core, ui, 2, "chat.ref", { station: "w2/st", id: "k2", title: "云上的", base: "https://x" }), { mark: "@[云上的]" });
  // Kept by a page before the core kept them: one to a station's own page (gone) is no workspace's.
  await ask(host, core, ui, 3, "chat.refs", { links: [["旧的", "https://x/w/ws/s/st/chats/a"], ["本机", "/admin/chats/b"]] });
  call(core, ui, 4, "chat.send", { station: "ws/st", thread: 7, text: "看 @[排查 登录]、@[云上的]、@[旧的]、@[本机] 和 @[不知道]" });
  await host.settle();
  // Another workspace's chat is none of this one's: its mark stays as written.
  assert.equal(posted(host).at(-1).text, "看 [排查 登录](https://x/w/ws/s/st/chats/ember%3Ac%201)、@[云上的]、[旧的](https://x/w/ws/s/st/chats/a)、@[本机] 和 @[不知道]");
  core.close();
});

test("an_address_of_a_stations_own_page_kept_from_before_is_said_gone", async () => {
  const { host, core } = await started();
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "chat", station: "local", thread: 7 });
  subscribe(core, ui, 2, { topic: "overview", station: "local" });
  call(core, ui, 3, "chat.send", { station: "local", thread: 7, text: "hi" });
  await host.settle();
  const codes = new Map(host.takeEmitted().map(([, m]) => m as J).filter((m) => "error" in m).map((m) => [m.id, m.error.code]));
  assert.deepEqual([codes.get(1), codes.get(2), codes.get(3)], ["gone", "gone", "gone"], JSON.stringify([...codes]));
  core.close();
});

test("the_chats_a_few_words_find_are_a_view_of_the_list", async () => {
  const row = (id: string, title: string, at: number) => ({ id, session: id, thread: null, title, agents: [], last: null, unread: false, mine: true, lastActiveAt: at, connect: null, origin: null });
  const { host, core } = await started({ ...base(), "GET /chats": [row("a", "别的", 3), row("b", "登录页", 2), row("c", "修登录", 1)] });
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "chatSearch", scope: "ws", query: "登录", exclude: "c" });
  await host.settle();
  const values = new Map();
  apply(host, values);
  assert.deepEqual(v(values, 1).items.map((i: J) => i.id), ["b"]);
  assert.equal(v(values, 1).items[0].station, "ws/st");
  core.close();
});

test("the_at_menu_written_on_one_station_finds_the_chats_of_every_station_of_its_workspace_the_others_saying_so", async () => {
  // `ws/st` (studio) and `ws/st2` (mini), both answering at the same origin: which one a request is for, as the wire says.
  const AT = "x-test-station";
  const wire = (host: FakeHost) => {
    const inner = new HostWire(host);
    return { request: (station: StationAddr, head: RequestHead, body: Uint8Array) => inner.request(station, { ...head, headers: [...head.headers, [AT, station.station]] }, body) } as StationWire;
  };
  const row = (id: string, title: string, at: number) => ({ id, session: id, thread: null, title, agents: [], last: null, unread: false, mine: true, lastActiveAt: at, connect: null, origin: null });
  const { host, core } = await started(base(), 0, wire, (x) => {
    x.cloud.also = { stations: [{ id: "st", name: "studio", online: true, last_seen: null }, { id: "st2", name: "mini", online: true, last_seen: null }] };
    stationReplies(x.host, (req: HttpRequest) => {
      const [path, query] = req.url.replace("https://stillfail.test/admin/api", "").split("?");
      if (path !== "/chats" || (query ?? "").includes("archived")) return undefined;
      return req.headers.some(([k, v]) => k === AT && v === "st2") ? [row("b", "部署 mini", 2)] : [row("a", "部署 studio", 3), row("c", "写在这里", 1)];
    });
  });
  const ui = core.connect();
  // As the composer asks, written in `c` on `ws/st`.
  subscribe(core, ui, 1, { topic: "chatSearch", scope: "ws", query: "部署", station: "ws/st", exclude: "c", limit: 8, elsewhere: true });
  subscribe(core, ui, 2, { topic: "chatSearch", scope: "ws", query: "", station: "ws/st", exclude: "c", limit: 8, elsewhere: true });
  await host.settle();
  await host.time.pass(500);
  await host.settle();
  const values = new Map();
  apply(host, values);
  const shown = (n: number) => v(values, n).items.map((i: J) => [i.station, i.id, i.otherStation ?? false]);
  assert.deepEqual(shown(1), [["ws/st", "a", false], ["ws/st2", "b", true]]);
  assert.deepEqual(shown(2), [["ws/st", "a", false], ["ws/st2", "b", true]]);
  core.close();
});

test("a_new_chat_stays_on_the_station_picked_while_it_is_down_and_says_so", async () => {
  // `ws/st2` (mini) is not reached.
  const wire = (host: FakeHost) => {
    const inner = new HostWire(host);
    return {
      request: (station: StationAddr, head: RequestHead, body: Uint8Array) => station.station === "st2" ? Effect.fail(new CoreError("mesh", "unreached")) : inner.request(station, head, body),
    } as StationWire;
  };
  const { host, core } = await started(base(), 0, wire, (x) => {
    x.cloud.also = { stations: [{ id: "st", name: "studio", online: true, last_seen: null }, { id: "st2", name: "mini", online: false, last_seen: null }] };
  });
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "newChat", scope: "ws" });
  await host.time.pass(500);
  await host.settle();
  apply(host, values);
  // Never picked: the first up.
  assert.deepEqual([v(values, 1).station.id, v(values, 1).down], ["st", false]);
  call(core, ui, 2, "newChat.pick", { scope: "ws", station: "st2" });
  await host.settle();
  apply(host, values);
  // Picked, down, another up: it stays, said to be down, and can still be left for the other.
  assert.deepEqual([v(values, 1).station.id, v(values, 1).down], ["st2", true]);
  assert.deepEqual(v(values, 1).stations.map((s: J) => s.id), ["st", "st2"]);
  // What is picked on the page then is the down one's, not the other's.
  call(core, ui, 3, "newChat.pick", { scope: "ws", effort: "high" });
  await host.settle();
  assert.equal((core.inner.data.record("choice", "ws:ws:station:st2") as J).effort, "high");
  assert.equal(core.inner.data.record("choice", "ws:ws:station:st"), undefined);
  core.close();
});

test("the_messages_a_few_words_find_are_those_of_the_chats_listed_newest_first_as_last_edited", async () => {
  const row = (id: string, thread: number, title: string) => ({ id, session: id, thread, title, agents: [], last: null, unread: false, mine: true, lastActiveAt: thread, connect: null, origin: null });
  const said = (thread: number, n: number, text: string, at: number) => ({ thread, n, kind: "message", ts: `${n}.0`, authorKind: "person", author: "a@x", authorName: "阿甲", text, at });
  const { host, core } = await started({
    ...base(),
    "GET /chats": [row("a", 7, "别的"), row("b", 8, "登录页")],
    "GET /threads": [threadView(7, 4, 4, 0), threadView(8, 1, 1, 0)],
    "GET /threads/7/entries?limit=50": {
      first: 1,
      last: 4,
      entries: [
        said(7, 1, "先看一下 **登录流程** 哪里慢", 1000),
        said(7, 2, "无关的话", 2000),
        said(7, 3, "第一行\n很长很长很长很长的前文，一直一直一直说到这里才终于提到了 Login 页面的问题，后面还有一些", 3000),
        { thread: 7, n: 4, kind: "edit", target: 2, text: "改成也说登录", at: 4000 },
      ],
    },
    "GET /threads/8/entries?limit=50": { first: 1, last: 1, entries: [said(8, 1, "登录按钮", 500)] },
  });
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "chatSearch", scope: "ws", query: "登录", messages: 10 });
  subscribe(core, ui, 2, { topic: "chatSearch", scope: "ws", query: "登录" });
  subscribe(core, ui, 3, { topic: "chatSearch", scope: "ws", query: "login 页面", messages: 10, exclude: "b" });
  subscribe(core, ui, 4, { topic: "chatSearch", scope: "ws", query: "登录流程", messages: 10 });
  await host.settle();
  const values = new Map();
  apply(host, values);
  // Newest first; the edited one by its edit's words; each with its chat's row and who said it.
  assert.deepEqual(v(values, 1).messages.map((m: J) => [m.thread, m.seq, m.text]), [[7, 2, "改成也说登录"], [7, 1, "先看一下 登录流程 哪里慢"], [8, 1, "登录按钮"]]);
  const first = v(values, 1).messages[1];
  assert.equal(first.chat.id, "a");
  assert.equal(first.by, "阿甲");
  assert.deepEqual(first.marks, [{ from: 5, to: 7 }]);
  assert.equal(typeof first.time.createdAt, "object");
  // Not asked for: none looked for.
  assert.deepEqual(v(values, 2).messages ?? [], []);
  // The words looked for, as a message opened from the search marks them.
  assert.deepEqual(v(values, 3).words, ["login", "页面"]);
  // Every word, case aside, on the line that has them; a line's start cut to the words.
  const cut = v(values, 3).messages;
  assert.deepEqual(cut.map((m: J) => m.seq), [3]);
  assert.ok(cut[0].text.startsWith("…") && cut[0].text.includes("Login 页面"), cut[0].text);
  assert.equal(cut[0].text.slice(cut[0].marks[0].from, cut[0].marks[0].to), "Login");
  // Three characters or more, as any.
  assert.deepEqual(v(values, 4).messages.map((m: J) => m.seq), [1]);
  core.close();
});

test("a_chat_shown_has_its_unread_line_and_is_read_while_its_end_is_in_view", async () => {
  const said = (n: number) => ({ thread: 7, n, kind: "message", ts: `${n}.0`, authorKind: "agent", author: "k1", authorName: null, text: "好", at: n });
  const { host, core } = await started({
    ...base(),
    "GET /threads": [threadView(7, 3, 1, 2)],
    "GET /threads/7/entries?limit=50": { first: 1, last: 3, entries: [said(1), said(2), said(3)] },
    "PUT /threads/7/read": { n: 3 },
  });
  let ui = core.connect();
  let values = new Map();
  subscribe(core, ui, 1, { topic: "chat", station: "ws/st", thread: 7 });
  await host.settle();
  apply(host, values);
  // Not shown by any page yet: the line as it will be (its first value opens there).
  assert.equal(v(values, 1).messages.length, 3);
  assert.equal(v(values, 1).unreadLine, 2);
  // Shown: the line over the first not read when it was opened; not read while its end is out of view.
  call(core, ui, 2, "client.focus", { visible: true, focused: true, chat: { station: "ws/st", thread: 7, end: false } });
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 1).unreadLine, 2);
  const reads = () => host.requests.filter((r) => r.method === "PUT" && r.url.endsWith("/threads/7/read")).length;
  assert.equal(reads(), 0);
  // Its end in view: read up to the newest, once; the line stays for the visit.
  call(core, ui, 3, "client.focus", { chat: { station: "ws/st", thread: 7, end: true } });
  await host.settle();
  call(core, ui, 4, "client.focus", { visible: true });
  await host.settle();
  apply(host, values);
  assert.equal(reads(), 1);
  assert.equal(v(values, 1).unreadLine, 2);
  // The page gone: the visit ends with it; opened again, nothing unread.
  core.disconnect(ui);
  ui = core.connect();
  subscribe(core, ui, 1, { topic: "chat", station: "ws/st", thread: 7 });
  call(core, ui, 2, "client.focus", { visible: true, chat: { station: "ws/st", thread: 7 } });
  await host.settle();
  values = new Map();
  apply(host, values);
  assert.equal(v(values, 1).unreadLine ?? null, null);
  core.close();
});

// The desktop app opened again on the chat shown before the new chat it was left on (2026-10-26): the new chat told the
// core nothing, so the chat stayed the one the workspace went back to.
test("a_workspace_goes_back_to_its_new_chat_once_one_shows_after_a_chat_and_so_when_the_app_opens_again", async () => {
  const { host, core } = await started();
  let ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "workspaceMarks", workspace: "ws" });
  call(core, ui, 2, "client.focus", { visible: true, workspace: "ws", chat: { station: "ws/st", thread: 7, session: "k1" } });
  await host.settle();
  apply(host, values);
  assert.deepEqual(v(values, 1).workspaces.ws.chat, { station: "ws/st", key: "k1" });
  // Its new chat shown in its place: what the workspace goes back to.
  call(core, ui, 3, "client.focus", { left: { station: "ws/st", thread: 7, session: "k1" }, newChat: "ws" });
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 1).workspaces.ws.chat, undefined);
  // Opened again: the same.
  core.close();
  const again = await Core.create(host, { clock: host.time.clock, sample: 0, wire: () => new HostWire(host) });
  ui = again.connect();
  const after = new Map();
  subscribe(again, ui, 1, { topic: "workspaceMarks", workspace: "ws" });
  await host.settle();
  apply(host, after);
  assert.ok(v(after, 1).workspaces.ws);
  assert.equal(v(after, 1).workspaces.ws.chat, undefined);
  // A chat shown after it: that chat again.
  call(again, ui, 2, "client.focus", { chat: { station: "ws/st", thread: 7, session: "k1" } });
  await host.settle();
  apply(host, after);
  assert.deepEqual(v(after, 1).workspaces.ws.chat, { station: "ws/st", key: "k1" });
  again.close();
});

test("what_two_chats_agents_wrote_each_other_is_not_in_the_chat_but_on_its_letters_page_by_the_other_chat", async () => {
  const said = (n: number, over: J = {}) => ({ thread: 7, n, kind: "message", ts: `${n}.0`, authorKind: "agent", author: "k1", authorName: null, text: "好", at: n, ...over });
  const backups = { title: "备份", link: "https://x/o/w/s/b" };
  const coming = (n: number, text: string) => said(n, { author: "peer/ember:c-9", text: `来自 [备份](https://x/o/w/s/b)：\n\n${text}`, letter: { way: "in", ...backups } });
  const going = (n: number, text: string) => said(n, { text: `发给 [备份](https://x/o/w/s/b)：\n\n${text}`, letter: { way: "out", ...backups } });
  const { host, core } = await started({
    ...base(),
    "GET /threads": [{ ...threadView(7, 8), letters: 4 }],
    "GET /threads/7/entries?limit=50": { first: 1, last: 8, entries: [
      said(1, { authorKind: "person", author: "me@x", text: "改备份" }), coming(2, "脚本放好了"), going(3, "已替换"), said(4),
      // From a station before letters were marked: known by its heading.
      said(5, { author: "peer/ember:c-8", text: "来自 [部署](https://x/o/w/s/d)：\n\n部署好了" }),
      coming(6, "**补充**一点\n\n第二段"),
      // The chat's own agent quoting one in the chat says it in the chat.
      said(7, { text: "来自 [备份](https://x/o/w/s/b)：\n\n它的 agent 说了这句" }), said(8),
    ] },
  });
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "chat", station: "ws/st", thread: 7 });
  subscribe(core, ui, 2, { topic: "chatLetters", station: "ws/st", thread: 7 });
  await host.settle();
  apply(host, values);
  const chat = v(values, 1);
  assert.deepEqual(chat.messages.map((m: J) => m.seq), [1, 4, 7, 8]);
  assert.equal(chat.letters, 4);
  // Pages go by entries: what the chat does not show moves them too.
  assert.deepEqual([chat.firstEntry, chat.lastEntry], [1, 8]);
  const page = v(values, 2);
  assert.equal(page.whole, true);
  // By the other chat, the one written with last first; both ways, in the order written, without their headings.
  assert.deepEqual(page.chats.map((c: J) => [c.title, c.link, c.letters.map((m: J) => [m.seq, m.way, m.text])]), [
    ["备份", "https://x/o/w/s/b", [[2, "in", "脚本放好了"], [3, "out", "已替换"], [6, "in", "**补充**一点\n\n第二段"]]],
    ["部署", "https://x/o/w/s/d", [[5, "in", "部署好了"]]],
  ]);
  // In brief, for the page's list: the last letter's words on a line, by whom when it went out of here.
  assert.deepEqual(page.chats.map((c: J) => [c.key, c.last, c.lastActiveAt]), [["https://x/o/w/s/b", "补充一点 第二段", 6], ["https://x/o/w/s/d", "部署好了", 5]]);
  // Coming in: by that chat's agent, its name opening that chat; going out: by this chat's own agent.
  const [incoming, outgoing] = page.chats[0].letters;
  assert.equal(incoming.by.name, "「备份」的 agent");
  assert.equal(incoming.by.from, "https://x/o/w/s/b");
  assert.equal(outgoing.by.agent, "k1");
  assert.ok(incoming.md !== undefined, "drawn as the chat draws an agent's words");
  core.close();
});

test("notifications_are_on_until_turned_off_and_kept_so_with_no_pushes", async () => {
  const { host, core } = await started();
  let ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "notify" });
  await host.settle();
  apply(host, values);
  // (the workspaces the accounts are in apart: as the fixture's are)
  const settings = (x: J) => Object.fromEntries(Object.entries(x).filter(([k]) => k !== "workspaces"));
  assert.deepEqual(settings(v(values, 1)), { on: true, asked: false, push: true, kinds: { wait: true, failed: true, done: "away", message: true }, preview: true, muted: [], permission: "unknown", show: [] });
  // What the system allows, as the app finds it: shown to every UI, not kept.
  call(core, ui, 4, "notify.permission", { state: "denied" });
  call(core, ui, 5, "notify.set", { preview: false });
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 1).permission, "denied");
  assert.equal(v(values, 1).preview, false);
  // Off (and asked, as Android moves its old settings over): pushes go, and are not taken while off.
  call(core, ui, 2, "notify.set", { on: false, asked: true });
  call(core, ui, 3, "push.register", { kind: "fcm", token: "t" });
  await host.settle();
  apply(host, values);
  assert.deepEqual(settings(v(values, 1)), { on: false, asked: true, push: false, kinds: { wait: true, failed: true, done: "away", message: true }, preview: false, muted: [], permission: "denied", show: [] });
  assert.equal(host.stored(PUSH_KEY), undefined);
  // Kept across a restart.
  core.close();
  const again = await Core.create(host, { clock: host.time.clock, sample: 0, wire: () => new HostWire(host) });
  ui = again.connect();
  subscribe(again, ui, 1, { topic: "notify" });
  call(again, ui, 2, "notice.pushed", {});
  call(again, ui, 3, "notice.claim", { id: "n1" });
  await host.settle();
  const emitted = host.takeEmitted().map(([, m]) => m as J);
  const ok = (id: number) => emitted.find((m) => m.id === id && "ok" in m)?.ok;
  assert.deepEqual([ok(2), ok(3)], [{ show: false }, { show: false }]);
  const after = emitted.find((m) => m.id === 1 && "value" in m).value;
  assert.deepEqual([after.on, after.preview, after.permission], [false, false, "unknown"], "the setting kept, the system's answer asked again");
  again.close();
});

test("a_push_registration_says_what_this_device_shows_and_is_given_again_as_that_changes", async () => {
  const { host, core } = await started();
  const posted: J[] = [];
  stationReplies(host, (req) => {
    if (req.method !== "POST" || !req.url.endsWith("/v1/push")) return undefined;
    posted.push(JSON.parse(new TextDecoder().decode(req.body ?? new Uint8Array())));
    return {};
  });
  const ui = core.connect();
  call(core, ui, 1, "push.register", { kind: "fcm", token: "t" });
  await host.settle();
  assert.deepEqual(posted.map((p) => [p.token, p.preview, p.kinds]), [["t", true, { wait: true, failed: true, done: "away", message: true }]]);
  // Its preview off, people's messages off: given again saying so (the cloud makes its pushes so), not waited on.
  call(core, ui, 2, "notify.set", { preview: false, kinds: { message: false } });
  await host.settle();
  assert.deepEqual(posted.slice(1).map((p) => [p.token, p.preview, p.kinds.message, p.kinds.failed]), [["t", false, false, true]]);
  // Said again as it was: nothing given.
  call(core, ui, 3, "notify.set", { preview: false });
  await host.settle();
  assert.equal(posted.length, 2);
  // A workspace turned off: given again saying so (the cloud sends nothing of it).
  call(core, ui, 4, "notify.set", { workspaces: { w9: false } });
  await host.settle();
  assert.deepEqual(posted.slice(2).map((p) => p.muted), [["w9"]]);
  core.close();
});

test("an_ios_apns_token_is_registered_as_it_is_and_taken_off_by_it", async () => {
  const { host, core } = await started();
  const sent: [string, J][] = [];
  stationReplies(host, (req) => {
    if (!req.url.endsWith("/v1/push")) return undefined;
    sent.push([req.method, JSON.parse(new TextDecoder().decode(req.body ?? new Uint8Array()))]);
    return {};
  });
  const ui = core.connect();
  const token = "ab".repeat(32);
  call(core, ui, 1, "push.register", { kind: "apns", token, sandbox: true });
  await host.settle();
  assert.deepEqual(sent.map(([m, p]) => [m, p.kind, p.token, p.sandbox]), [["POST", "apns", token, true]]);
  call(core, ui, 2, "push.unregister", {});
  await host.settle();
  assert.deepEqual(sent.slice(1), [["DELETE", { token }]]);
  core.close();
});

/// What came out: subscription values (deltas applied) into `values`, and the calls' answers (core/tests.rs `answers`).
function answersOf(host: FakeHost, values: Map<number, unknown>): Map<number, { ok: J } | { err: string }> {
  const out = new Map<number, { ok: J } | { err: string }>();
  for (const [, m] of host.takeEmitted()) {
    const x = m as J;
    if ("value" in x) values.set(x.id, x.value);
    else if ("delta" in x) values.set(x.id, applyOps(values.get(x.id), x.delta));
    else if ("ok" in x) out.set(x.id, { ok: x.ok });
    else if ("error" in x) out.set(x.id, { err: x.error.message });
  }
  return out;
}

test("a_chats_jobs_are_shown_as_the_core_puts_them_and_a_jobs_output_says_when_it_last_grew", async () => {
  let logReads = 0;
  let now = 0;
  const job = (id: string, patch: J) => ({ id, session: "k1", name: id, state: "running", port: null, startedAt: now - 60_000, command: "watch", ...patch });
  const s = stationHost(base());
  now = Math.round(s.host.nowMs());
  stationReplies(s.host, (req) => {
    const path = req.url.replace("https://stillfail.test/admin/api", "");
    if (path === "/sessions/k1")
      return {
        session: session("k1"), threads: [], turns: [],
        jobs: [job("w", { notices: [{ at: now - 120_000, text: "CI 还在跑" }] }), job("s", { port: 4817, state: "exited", restarts: 1 }), job("done", { state: "exited", exitCode: 0, endedAt: now - 30_000 })],
      };
    if (path.startsWith("/jobs/w/log")) {
      logReads++;
      return { text: "step 3\n", outputAt: now - 180_000, follows: true };
    }
    return undefined;
  });
  const core = await Core.create(s.host, { clock: s.host.time.clock, sample: 0, wire: () => new HostWire(s.host) });
  const host = s.host;
  await host.time.pass(500);
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "chatJobs", station: "ws/st", thread: 7 });
  subscribe(core, ui, 2, { topic: "jobLog", station: "ws/st", job: "w", lines: 1 });
  await host.settle();
  await host.settle();
  // The station follows the log on its stream, opened again for it.
  assert.ok(s.streams.at(-1)!.path.includes("job=w&lines=1"), s.streams.at(-1)!.path);
  const values = new Map();
  apply(host, values);
  // Restarting first, then alive, then what is over; each with its dot and its line; the heads' notes.
  const jobs = v(values, 1);
  assert.deepEqual(jobs.jobs.map((j: J) => j.id), ["s", "w", "done"]);
  assert.deepEqual([jobs.alarm, jobs.servicesNote, jobs.jobsNote], ["restart", "1 个在重启", "1 个运行中"]);
  assert.deepEqual([jobs.ended, jobs.clear, jobs.clearText], [1, ["k1"], "清除 1 个已结束的"]);
  const w = jobs.jobs[1];
  assert.deepEqual([w.tone, w.meta[0].text, w.meta[1].text, w.detail], ["live", "CI 还在跑", " · 2 分钟前", "运行中 · 1 分钟 · 1 条通知"]);
  assert.deepEqual([jobs.jobs[0].meta[0].text, jobs.jobs[2].tone], ["正在重启", "off"]);
  // Its output: the last line and when, in words; the station follows it, so it is not read again.
  assert.deepEqual([v(values, 2).last, v(values, 2).said], ["step 3", "最后输出 · 3 分钟前"]);
  const before = logReads;
  await host.time.pass(5_000, 100);
  assert.equal(logReads, before);
  core.close();
});

test("a_new_chat_is_there_at_once_and_what_is_sent_to_it_goes_in_once_the_station_has_made_it", async () => {
  let up = false;
  const { host, core } = await started();
  stationReplies(host, (req) => {
    const path = req.url.replace("https://stillfail.test/admin/api", "");
    if (req.method === "POST" && path === "/sessions") {
      if (!up) return undefined;
      return { key: "ember:c-1", thread: { ...threadView(9, 0), createdBy: "a@x.com", sessions: [{ thread: 9, session: "ember:c-1", connect: "ember", joinedAt: 1 }] } };
    }
    if (req.method === "POST" && path === "/threads/9/messages") return { n: 1 };
    return undefined;
  });
  const ui = core.connect();
  const values = new Map();
  const key = String((await ask(host, core, ui, 1, "chat.create", { station: "ws/st", runtime: "claude", model: "opus" })).key);
  assert.ok(key.startsWith(PENDING_PREFIX), key);
  // The station could not make it (it answers 404 here): what is sent waits, and has it tried again.
  subscribe(core, ui, 2, { topic: "chat", station: "ws/st", session: key });
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 2).pending, true);
  up = true;
  call(core, ui, 3, "chat.send", { station: "ws/st", session: key, text: "修一下登录", client: "android 0.1.1123" });
  await host.settle();
  await host.settle();
  // What is written (a list read as what changed of it is no write).
  const asked = host.requests.filter((r) => r.method === "POST" && r.url.includes("/admin/api/") && readsOf(r).length === 0).map((r) => [r.url.replace("https://stillfail.test/admin/api", ""), new TextDecoder().decode(r.body!)]);
  assert.deepEqual(asked.map(([p]) => p), ["/sessions", "/sessions", "/threads/9/messages"]);
  // It carries the key given here: the station's rows say it of the chat made.
  assert.deepEqual(JSON.parse(asked[0][1]), { runtime: "claude", model: "opus", clientKey: key });
  // With the app it was sent from, which waited with it.
  const sent = JSON.parse(asked[2][1]);
  assert.deepEqual([sent.text, sent.client], ["修一下登录", "android 0.1.1123"]);
  // The page is the station's chat now, under the key it was opened with, and says the one the station gave it.
  apply(host, values);
  assert.deepEqual([v(values, 2).pending, v(values, 2).key], [false, "ember:c-1"]);
  core.close();
});

test("a_chat_made_here_is_a_new_chat_all_along_until_it_is_named", async () => {
  // Sent from a new chat, its page was called by the words sent, then (made, read by its station before the message was
  // in it) what the station called a chat with nothing said in it, then by the words again as the station had them:
  // the bar's title went and came. It is a new chat, as its station calls it, until people or its agent name it.
  const made = { ...threadView(7, 0), createdBy: "a@x.com" };
  const { host, core } = await started({ ...base(), "GET /threads": [made], "GET /chats": [{ id: "7", thread: 7, session: "k1", title: "新对话", agents: [], lastActiveAt: 1 }], "GET /threads/7/entries?limit=50": { first: 1, last: 0, entries: [] } });
  stationReplies(host, (req) => {
    const path = req.url.replace("https://stillfail.test/admin/api", "");
    if (req.method === "POST" && path === "/sessions") return { key: "k1", thread: made };
    if (req.method === "POST" && path === "/threads/7/messages") return { n: 1 };
    return undefined;
  });
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "chat", station: "ws/st", thread: 7 });
  await host.settle();
  apply(host, values);
  const key = String((await ask(host, core, ui, 2, "chat.create", { station: "ws/st", runtime: "claude", model: "opus" })).key);
  subscribe(core, ui, 4, { topic: "chat", station: "ws/st", session: key });
  await host.settle();
  apply(host, values);
  const titles = [v(values, 1).title, v(values, 4).title];
  call(core, ui, 3, "chat.send", { station: "ws/st", session: key, text: "\n修一下登录\n就是那个按钮" });
  await host.settle();
  await host.settle();
  apply(host, values);
  titles.push(v(values, 1).title, v(values, 4).title);
  // by its thread and by the key it was asked for with, before what is sent to it and after: the same
  assert.deepEqual(titles, ["新对话", "新对话", "新对话", "新对话"]);
  core.close();
});

test("a_new_chats_lists_read_before_its_agent_began_and_come_after_it_was_told_at_work_keep_it_at_work", async () => {
  // What a new chat changes is read again as its first message goes: the station as it was then, its agent not at work
  // yet. On a slow link that came after the station told the agent at work, and had it at rest again: no activity, no
  // mark, for the whole of its turn (2026-10-25). What was told after a read was asked is no older than what it brings.
  const made = { ...threadView(9, 0), createdBy: "a@x.com", sessions: [{ thread: 9, session: "ember:c-1", connect: "ember", joinedAt: 1 }] };
  const atRest = session("ember:c-1");
  const working = { ...atRest, process: "running", running: true, turns: 1, lastTurn: { id: "t1", kind: "input", startedAt: 5, endedAt: null } };
  const row = (id: string, session: string, thread: number, agents: J[]) => ({ id, session, thread, title: "新对话", agents, last: null, unread: false, mine: true, lastActiveAt: thread, connect: null, origin: null });
  const answers: J = { ...base(), "GET /chats": [row("7", "k1", 7, [])] };
  const s = await started(answers);
  const { host, core } = s;
  // The station as it is at each moment: what a read is answered with is what it had as it was asked.
  const now = (agent: J) => {
    answers["GET /sessions"] = [session("k1"), agent];
    answers["GET /sessions/ember%3Ac-1"] = { session: agent, threads: [], turns: agent.lastTurn ? [agent.lastTurn] : [], jobs: [] };
    answers["GET /chats"] = [row("7", "k1", 7, []), row("9", "ember:c-1", 9, [agent])];
  };
  answers["GET /threads/9"] = { ...made, last: 1 };
  stationReplies(host, (req) => {
    const path = req.url.replace("https://stillfail.test/admin/api", "");
    if (req.method === "POST" && path === "/sessions") return { key: "ember:c-1", thread: made };
    if (req.method === "POST" && path === "/threads/9/messages") return { n: 1 };
    return undefined;
  });
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "chats", scope: "ws" });
  await host.settle();
  // A slow link: the lists, asked as the chat is made, come long after.
  const release = [host.hold("/admin/api/changed/sessions"), host.hold("/admin/api/changed/chats")];
  now(atRest);
  const key = String((await ask(host, core, ui, 2, "chat.create", { station: "ws/st", runtime: "claude", model: "opus" })).key);
  call(core, ui, 3, "chat.send", { station: "ws/st", session: key, text: "修一下登录" });
  await host.settle();
  s.push("thread", { id: 9, entries: [{ ...entry(1, "修一下登录"), thread: 9 }] });
  // Its agent begins: the station tells it, and has it so from now.
  now(working);
  s.push("session", working);
  s.push("chat", row("9", "ember:c-1", 9, [working]));
  await host.settle();
  subscribe(core, ui, 4, { topic: "chat", station: "ws/st", thread: 9 });
  await host.settle();
  // The lists come, as the station had them before it began.
  for (const r of release) r();
  await host.settle();
  apply(host, values);
  const item = v(values, 1).days.flatMap((d: J) => d.items).find((i: J) => i.id === "9");
  assert.deepEqual([v(values, 4).agents[0].status, item?.state], ["running", "run"]);
  core.close();
});

test("what_waited_for_a_new_chat_goes_as_soon_as_it_is_made_not_after_the_lists_are_read_again", async () => {
  const { host, core } = await started();
  stationReplies(host, (req) => {
    const path = req.url.replace("https://stillfail.test/admin/api", "");
    if (req.method === "POST" && path === "/sessions") return { key: "ember:c-1", thread: { ...threadView(9, 0), createdBy: "a@x.com", sessions: [{ thread: 9, session: "ember:c-1", connect: "ember", joinedAt: 1 }] } };
    if (req.method === "POST" && path === "/threads/9/messages") return { n: 1 };
    return undefined;
  });
  const ui = core.connect();
  // A slow link: what the new chat changes (its lists, the footprint) is not read back yet.
  const release = [host.hold("/admin/api/chats"), host.hold("/admin/api/footprint")];
  const key = String((await ask(host, core, ui, 1, "chat.create", { station: "ws/st", runtime: "claude", model: "opus" })).key);
  call(core, ui, 2, "chat.send", { station: "ws/st", session: key, text: "修一下登录" });
  await host.settle();
  await host.settle();
  const posted = host.requests.filter((r) => r.method === "POST" && r.url.includes("/admin/api/")).map((r) => r.url.replace("https://stillfail.test/admin/api", ""));
  assert.ok(posted.includes("/threads/9/messages"), posted.join(", "));
  for (const r of release) r();
  await host.settle();
  core.close();
});

test("a_chat_being_archived_leaves_the_list_at_once_and_comes_back_if_it_could_not_be", async () => {
  let archived = false;
  let refused = true;
  const row = (id: string, thread: number) => ({ id, session: id, thread, title: id, agents: [], last: null, unread: false, mine: true, lastActiveAt: 1, connect: null, origin: null });
  const { host, core } = await started({ ...base(), "GET /chats": [row("k1", 7), row("k2", 8)] });
  stationReplies(host, (req) => {
    const path = req.url.replace("https://stillfail.test/admin/api", "");
    if (req.method === "GET" && path === "/chats" && archived) return [row("k2", 8)];
    if (req.method === "POST" && path === "/threads/7/archive" && !refused) {
      archived = true;
      return { ok: true };
    }
    return undefined;
  });
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "chats", scope: "ws" });
  await host.settle();
  const values = new Map();
  answersOf(host, values);
  const ids = () => v(values, 1).days.flatMap((d: J) => d.items.map((i: J) => i.id));
  assert.deepEqual(ids(), ["k1", "k2"]);
  // (The station refuses with 404 here where the Rust test's said 409 「还在跑」: either is a refusal.)
  const archive = (id: number) => call(core, ui, id, "chat.archive", { station: "ws/st", thread: 7, session: "k1", archived: true });
  // Gone at once, while the station has not answered.
  let release = host.hold("/threads/7/archive");
  archive(2);
  await host.settle();
  assert.equal(answersOf(host, values).size, 0);
  assert.deepEqual(ids(), ["k2"]);
  // It could not be: back, and the call says why.
  release();
  await host.settle();
  assert.ok("err" in answersOf(host, values).get(2)!);
  assert.deepEqual(ids(), ["k1", "k2"]);
  // Archived: its station's rows, read again before the answer, no longer have it.
  refused = false;
  release = host.hold("/threads/7/archive");
  archive(3);
  await host.settle();
  answersOf(host, values);
  assert.deepEqual(ids(), ["k2"]);
  release();
  await host.settle();
  assert.ok("ok" in answersOf(host, values).get(3)!);
  assert.deepEqual(ids(), ["k2"]);
  assert.ok(archived);
  core.close();
});

test("the_archive_is_its_stations_archived_chats_newest_first_by_day_and_one_restored_or_deleted_leaves_it", async () => {
  const gone: string[] = [];
  let now = 0;
  const chat = (id: string, thread: number, archived: J) => ({ id, session: id, thread, title: `聊 ${id}`, last: { text: "好了" }, lastActiveAt: now - 9e8, archived });
  const all = () =>
    [
      chat("k2", 8, { at: now - 3 * 86_400_000, by: "auto", alone: true }),
      chat("k1", 7, { at: now, by: "manual", alone: false }),
      // A station from before the archive answers the chats it shows: not archived ones.
      chat("k3", 9, null),
    ].filter((c) => !gone.includes(c.id));
  const s = stationHost(base());
  now = Math.round(s.host.nowMs());
  stationReplies(s.host, (req) => {
    const path = req.url.replace("https://stillfail.test/admin/api", "");
    if (req.method === "GET" && path === "/chats?archived=1") return all();
    if (req.method === "DELETE" && path === "/threads/7/archive") {
      gone.push("k1");
      return { ok: true };
    }
    if (req.method === "DELETE" && path === "/sessions/k2") {
      gone.push("k2");
      return { ok: true };
    }
    return undefined;
  });
  const host = s.host;
  const core = await Core.create(host, { clock: host.time.clock, sample: 0, wire: () => new HostWire(host) });
  await host.time.pass(500);
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "archive", scope: "ws" });
  await host.settle();
  const values = new Map();
  answersOf(host, values);
  const a = v(values, 1);
  assert.deepEqual([a.wait.reading, a.note, a.errors], [false, undefined, []]);
  assert.equal(a.days.length, 2);
  assert.equal(a.days[0].label, "今天");
  const first = a.days[0].items[0];
  assert.deepEqual([first.station, first.session, first.thread, first.title, first.last, first.how, first.deletable], ["ws/st", "k1", 7, "聊 k1", "好了", "手动归档", true]);
  assert.equal(first.clock.length, 5);
  // One station: which one is not said.
  assert.equal(first.place, undefined);
  assert.deepEqual([a.days[1].items[0].how, a.days[1].items[0].deletable], ["空闲后自动归档", false]);
  assert.deepEqual([first.id, a.total, a.more], ["k1", 2, false]);
  // Looked for by words in its title, or only the newest so many: the rest said to be left out.
  subscribe(core, ui, 4, { topic: "archive", scope: "ws", q: "K2" });
  subscribe(core, ui, 5, { topic: "archive", scope: "ws", limit: 1 });
  subscribe(core, ui, 6, { topic: "archive", scope: "ws", q: "nothing like it" });
  await host.settle();
  answersOf(host, values);
  const ids = (n: number) => v(values, n).days.flatMap((d: J) => d.items.map((i: J) => i.id));
  assert.deepEqual([ids(4), v(values, 4).total, v(values, 4).more], [["k2"], 1, false]);
  assert.deepEqual([ids(5), v(values, 5).total, v(values, 5).more], [["k1"], 2, true]);
  assert.deepEqual([ids(6), v(values, 6).note], [[], "没有匹配的归档对话"]);
  // Put back in the list: it leaves the archive before the call answers.
  call(core, ui, 2, "chat.archive", { station: "ws/st", thread: 7, session: "k1", archived: false });
  await host.settle();
  assert.ok("ok" in answersOf(host, values).get(2)!);
  const sessions = () => v(values, 1).days.flatMap((d: J) => d.items.map((i: J) => i.session));
  assert.deepEqual(sessions(), ["k2"]);
  // Deleted: the same, and with nothing left the page says so.
  call(core, ui, 3, "session.delete", { station: "ws/st", key: "k2" });
  await host.settle();
  assert.ok("ok" in answersOf(host, values).get(3)!);
  assert.deepEqual([v(values, 1).days, v(values, 1).note], [[], "暂无已归档的对话"]);
  core.close();
});

test("the_changelog_says_what_this_app_has_and_what_an_update_brought_until_seen", async () => {
  const host = new FakeHost();
  const now = Math.round(host.nowMs() / 1000);
  host.onFetch((req) => {
    if (!req.url.endsWith("/v1/changelog")) return jsonResponse(404, {});
    const entry = (version: number, parts: string[], text: string) => ({ version, commit: "c", at: now, text: [text], fixes: [], parts });
    return jsonResponse(200, {
      entries: [entry(1340, ["android"], "修复：还没发布的"), entry(1330, ["android", "web"], "修复：列表跳动"), entry(1325, ["station"], "修复：station 的"), entry(1310, ["android"], "新功能：更早的")],
      released: { android: 1335, web: 1335, station: 1320, desktop: null },
    });
  });
  let core = await Core.create(host, { clock: host.time.clock, sample: 0 });
  let ui = core.connect();
  await ask(host, core, ui, 1, "client.device", { app: "android", build: "0.1.1320" });
  subscribe(core, ui, 2, { topic: "changelog" });
  await host.settle();
  const values = new Map();
  answersOf(host, values);
  const c = v(values, 2);
  assert.deepEqual([c.app, c.build, c.loading], ["android", 1320, false]);
  // A tab a part, this app's first; the desktop's carries the web's.
  assert.deepEqual(c.tabs.map((x: J) => [x.part, x.label]), [["android", "安卓"], ["desktop", "桌面"], ["web", "网页"], ["station", "Station"], ["cloud", "云端"]]);
  const notes = (part: string) => c.tabs.find((x: J) => x.part === part).days.flatMap((d: J) => d.entries.map((e: J) => e.note));
  assert.equal(c.tabs[0].days[0].label, "今天");
  assert.deepEqual(notes("android"), ["未发布", "更新到 0.1.1330 后可用", ""]);
  // Another part's tab says what is not out of that part.
  assert.deepEqual(notes("desktop"), [""]);
  assert.deepEqual(notes("station"), ["未发布"]);
  assert.deepEqual(notes("cloud"), []);
  // The first build seen here: nothing is news.
  assert.equal(c.news, undefined, JSON.stringify(c));
  // Updated, the app started again: what it brought, until seen.
  await run(core.inner.data.written);
  core.close();
  core = await Core.create(host, { clock: host.time.clock, sample: 0 });
  ui = core.connect();
  await ask(host, core, ui, 3, "client.device", { app: "android", build: "0.1.1335" });
  subscribe(core, ui, 2, { topic: "changelog" });
  await host.settle();
  answersOf(host, values);
  const news = v(values, 2).news;
  assert.equal(news.build, "0.1.1335");
  assert.deepEqual(news.entries.map((e: J) => e.text[0]), ["修复：列表跳动"]);
  await ask(host, core, ui, 4, "changelog.seen", {});
  answersOf(host, values);
  assert.equal(v(values, 2).news, undefined);
  // Read once at each start (the TS core reads it then and as the cloud's socket opens: docs/core-ts.md).
  assert.equal(host.requests.filter((r) => r.url.endsWith("/v1/changelog")).length, 2);
  core.close();
});

test("the_changelog_whose_every_change_is_every_parts_is_one_list", async () => {
  // The stable channel's: a release an entry, each every part's; a tab a part would show the same in each.
  const host = new FakeHost();
  const now = Math.round(host.nowMs() / 1000);
  const every = ["android", "cloud", "desktop", "station", "web"];
  const entry = (version: number, text: string) => ({ version, commit: "", at: now, text: [text], fixes: [], parts: every });
  host.onFetch((req) => req.url.endsWith("/v1/changelog")
    ? jsonResponse(200, { entries: [entry(1330, "修复：列表跳动"), entry(1300, "新功能：更早的")], released: { android: 1330, desktop: 1330, station: 1330, web: 1330 } })
    : jsonResponse(404, {}));
  const core = await Core.create(host, { clock: host.time.clock, sample: 0 });
  const ui = core.connect();
  await ask(host, core, ui, 1, "client.device", { app: "desktop", build: "0.1.1330" });
  subscribe(core, ui, 2, { topic: "changelog" });
  await host.settle();
  const values = new Map();
  answersOf(host, values);
  const tabs = v(values, 2).tabs;
  assert.deepEqual(tabs.map((x: J) => x.part), ["desktop"]);
  assert.deepEqual(tabs[0].days.flatMap((d: J) => d.entries.map((e: J) => e.text[0])), ["修复：列表跳动", "新功能：更早的"]);
  core.close();
});

test("a_newer_build_says_what_it_brings_this_app_the_changelog_read_again_when_it_came_after", async () => {
  const host = new FakeHost();
  const now = Math.round(host.nowMs() / 1000);
  const entry = (version: number, parts: string[], text: string) => ({ version, commit: "c", at: now, text: [text], fixes: [], parts });
  let out = 1335;
  let entries = [entry(1330, ["android", "web"], "修复：列表跳动"), entry(1325, ["station"], "修复：station 的"), entry(1322, ["desktop"], "新功能：桌面的")];
  host.onFetch((req) => {
    const path = req.url.replace("https://stillfail.test", "");
    if (path === "/v1/changelog") return jsonResponse(200, { entries, released: { android: out, web: out, station: 1320, desktop: 1322 } });
    if (path === "/releases/android/latest.json" || path === "/releases/android/mbui/latest.json") return jsonResponse(200, { versionCode: out, versionName: `0.1.${out}`, file: `android/stillfail-${out}.apk`, sha256: "ab", size: 9 });
    return jsonResponse(404, {});
  });
  const core = await Core.create(host, { clock: host.time.clock, sample: 0 });
  const ui = core.connect();
  await ask(host, core, ui, 9, "client.device", { app: "android", build: "0.1.1320" });
  await host.settle();
  const reads = () => host.requests.filter((r) => r.url.endsWith("/v1/changelog")).length;
  // From 1320, 1335 brings Android one line (the station's and the desktop's are not the app's).
  let newer = await ask(host, core, ui, 1, "app.update", { platform: "android", versionCode: 1320 });
  assert.deepEqual([newer.versionCode, newer.news], [1335, ["修复：列表跳动"]]);
  // From 1330, nothing: the home screen does not offer it.
  newer = await ask(host, core, ui, 2, "app.update", { platform: "android", versionCode: 1330 });
  assert.deepEqual([newer.versionCode, newer.news], [1335, []]);
  assert.equal(reads(), 1, "the changelog read at the start knew 1335");
  // A build out after the changelog kept was read: it is read again first, and the build's lines are known with it.
  out = 1340;
  entries = [entry(1338, ["android"], "新功能：新的"), ...entries];
  newer = await ask(host, core, ui, 3, "app.update", { platform: "android", versionCode: 1330, now: true });
  assert.deepEqual([newer.versionCode, newer.news], [1340, ["新功能：新的"]]);
  assert.equal(reads(), 2);
  // What a build brings is this app's, whatever its feed is named (still.fail mbui's: android/mbui).
  newer = await ask(host, core, ui, 4, "app.update", { platform: "android/mbui", versionCode: 1330, now: true });
  assert.deepEqual([newer.versionCode, newer.news], [1340, ["新功能：新的"]]);
  core.close();
});

const connectTopic = (form: string) => ({ topic: "connectFlow", station: "ws/st", form });

test("connect_wizard_owns_steps_tokens_and_submission_on_all_clients", async () => {
  const { host, core } = await choosing();
  stationReplies(host, (req) => {
    const path = req.url.replace("https://stillfail.test/admin/api", "");
    if (path === "/slack/verify") return { identity: { team: "Team", teamId: "T", url: "https://t.slack.com", botUserId: "B", botName: "bot" }, errors: [] };
    if (path === "/connects") return { id: "new" };
    return undefined;
  });
  const ui = core.connect();
  const topic = connectTopic("wizard");
  const form = { station: "ws/st", form: "wizard" };
  await ask(host, core, ui, 1, "connect.flow.open", form);
  const flow = core.inner.forms.connects;
  const view = flow.value(topic);
  assert.equal(view.gettingToken, true, "desktop has the config form on its first step");
  assert.equal(view.total, 4);
  const shaped = present.decorate(topic, structuredClone(view), { now: 0, offsetMin: 0 });
  assert.ok("ok" in conform("ConnectFlowView", shaped), JSON.stringify(conform("ConnectFlowView", shaped)));
  assert.throws(() => flow.go(topic, ui, "bind"), "cannot skip token verification");
  flow.go(topic, ui, "manual");
  assert.equal(flow.value(topic).total, 2);
  await ask(host, core, ui, 2, "slack.tokens.edit", { station: "ws/st", form: "wizard", input: { appToken: "app", botToken: "bot" } });
  await ask(host, core, ui, 3, "connect.flow.verify", form);
  assert.equal(flow.value(topic).step, "bind");
  await ask(host, core, ui, 4, "pick.set", { station: "ws/st", of: "connect-new:wizard", model: "gpt-6-astra", runtime: "codex" });
  await ask(host, core, ui, 5, "pick.save", { station: "ws/st", of: "connect-new:wizard" });
  const created = await ask(host, core, ui, 6, "connect.flow.create", form);
  assert.equal(created.id, "new");
  const sent = stationPosted(host, "/connects");
  assert.equal(sent.length, 1);
  assert.deepEqual([sent[0].bind.model, sent[0].bind.runtime, sent[0].bind.effort, sent[0].slack.appToken], ["gpt-6-astra", "codex", "", "app"]);
  await assert.rejects(ask(host, core, ui, 7, "connect.flow.create", form), "a completed form cannot create twice");
  await ask(host, core, ui, 8, "connect.flow.drop", form);
  assert.throws(() => flow.value(topic));
  assert.equal(core.inner.forms.tokens.value(tokensOf("ws/st", "wizard")).appToken, "");
  core.close();
});

test("connect_wizard_isolates_forms_handles_resume_and_discards_closed_results", async () => {
  const { host, core } = await choosing();
  const ui = core.connect();
  const other = core.connect();
  for (const [id, form] of [[1, "one"], [2, "two"]] as const) await ask(host, core, ui, id, "connect.flow.open", { station: "ws/st", form, input: { mobile: true } });
  const flow = core.inner.forms.connects;
  const one = connectTopic("one");
  const two = connectTopic("two");
  assert.equal(flow.value(one).gettingToken, false, "mobile shows a token page, not the desktop inline form");
  assert.throws(() => flow.edit(one, other, { config: "secret" }));
  assert.throws(() => flow.edit(one, ui, { requireMention: "false" }));
  flow.go(one, ui, "token");
  flow.edit(one, ui, { config: "xoxe.xoxp-wrong" });
  assert.equal(typeof flow.value(one).configError, "string");
  assert.throws(() => flow.begin(one, ui, "config", {}, false));
  flow.edit(one, ui, { config: " xoxe-1-long-enough-refresh-token " });
  const [generation, name, params] = flow.begin(one, ui, "config", {}, false);
  assert.equal(name, "slack.addConfigToken");
  assert.equal(params.refreshToken, "xoxe-1-long-enough-refresh-token");
  assert.throws(() => flow.go(one, ui, "back"));
  assert.throws(() => flow.begin(one, ui, "config", {}, false));
  flow.drop(one, ui);
  flow.open(one, ui, { mobile: true, resume: "existing" });
  assert.equal(flow.finish(one, generation, "config", { ok: { teamId: "late" } }), false);
  assert.deepEqual([flow.value(one).step, flow.value(one).back], ["install", "close"]);
  await ask(host, core, ui, 3, "pick.set", { station: "ws/st", of: "connect-new:one", model: "gpt-6-astra", runtime: "codex" });
  await ask(host, core, ui, 4, "pick.save", { station: "ws/st", of: "connect-new:one" });
  assert.equal(flow.value(one).pick.value.model, "gpt-6-astra");
  assert.notEqual(flow.value(two).pick.value.model, "gpt-6-astra");
  core.disconnect(ui);
  assert.throws(() => flow.value(one));
  assert.throws(() => flow.value(two));
  core.close();
});

test("connect_wizard_configuration_and_oauth_install_keep_one_draft", async () => {
  const { host, core } = await choosing();
  const ui = core.connect();
  const topic = connectTopic("oauth");
  const flow = core.inner.forms.connects;
  flow.open(topic, ui, { mobile: true });
  await host.settle();
  flow.go(topic, ui, "token");
  flow.edit(topic, ui, { config: "xoxe-1-a-refresh-token-for-test" });
  let [generation] = flow.begin(topic, ui, "config", {}, false);
  flow.finish(topic, generation, "config", { ok: { teamId: "T" } });
  const overviewTopic = { topic: "overview", station: "ws/st" };
  const ov = structuredClone(core.inner.store.get(overviewTopic)) as J;
  ov.slackTeams = [{ teamId: "T", teamName: "Team" }];
  core.inner.data.set(overviewTopic, ov);
  assert.equal(flow.value(topic).config, "");
  let name: string;
  let params: J;
  [generation, name, params] = flow.begin(topic, ui, "make", {}, false);
  assert.equal(name, "slack.makeApp");
  assert.equal(params.team, "T");
  assert.equal(Object.keys(params.settings.groups).length, 16);
  flow.finish(topic, generation, "make", { err: CoreError.invalid("try again") });
  assert.equal(flow.value(topic).step, "app");
  [generation] = flow.begin(topic, ui, "make", {}, false);
  flow.finish(topic, generation, "make", { ok: { appId: "A" } });
  ov.slackApps = [{ appId: "A", state: "oauth-state", installed: true }];
  core.inner.data.set(overviewTopic, ov);
  const tokens = { appToken: "app-token", botToken: "" };
  [generation, name, params] = flow.begin(topic, ui, "verify", tokens, false);
  assert.equal(name, "slack.verify");
  assert.equal(params.install, "oauth-state");
  flow.finish(topic, generation, "verify", { ok: { identity: null, errors: ["invalid token"] } });
  assert.equal(flow.value(topic).step, "install");
  [generation] = flow.begin(topic, ui, "verify", tokens, false);
  flow.finish(topic, generation, "verify", { ok: { identity: { teamId: "T" }, errors: [] } });
  assert.throws(() => flow.begin(topic, ui, "create", tokens, false));
  [, name, params] = flow.begin(topic, ui, "create", tokens, true);
  assert.equal(name, "connect.create");
  assert.deepEqual(params.input.slack, { appToken: "app-token", install: "oauth-state" });
  assert.ok(host.requests.every((r) => !r.url.includes("slack.com")));
  core.close();
});

/// Its station with the Feishu connect: the overview says the bots being made (none at first).
function withFeishu(core: Core, registrations: J[]): void {
  const at = { topic: "overview", station: "ws/st" };
  core.inner.data.set(at, { ...(structuredClone(core.inner.store.get(at)) as J), feishuRegistrations: registrations });
}

test("connect_wizard_offers_feishu_where_its_station_has_it_and_adds_a_scanned_bot_on_its_own", async () => {
  const { host, core } = await choosing();
  const waiting = { id: "r1", url: "https://accounts.feishu.cn/oauth/v1/app/verify?flow_id=abc&name=still.fail", expiresAt: 1_790_000_600_000, state: "waiting" };
  stationReplies(host, (req) => {
    const path = req.url.replace("https://stillfail.test/admin/api", "");
    if (req.method === "POST" && path === "/feishu/registrations") return { ...waiting, overview: { ...(structuredClone(core.inner.store.get({ topic: "overview", station: "ws/st" })) as J), feishuRegistrations: [waiting] } };
    if (req.method === "DELETE" && path.startsWith("/feishu/registrations/")) return {};
    if (path === "/feishu/connects") return { id: "codex-bot" };
    return undefined;
  });
  const ui = core.connect();
  const topic = connectTopic("feishu");
  const form = { station: "ws/st", form: "feishu" };
  await ask(host, core, ui, 1, "connect.flow.open", form);
  const flow = core.inner.forms.connects;
  // A station from before the Feishu connect: Slack's steps at once.
  assert.deepEqual([flow.value(topic).step, flow.value(topic).platforms], ["team", ["slack"]]);
  withFeishu(core, []);
  let view = flow.value(topic);
  assert.deepEqual([view.step, view.platforms, view.back, view.number, view.total], ["platform", ["slack", "feishu"], "close", 1, 5]);
  assert.throws(() => flow.go(topic, ui, "feishuWay"), "the platform comes first");
  flow.go(topic, ui, "feishuBind");
  view = flow.value(topic);
  assert.deepEqual([view.step, view.platform, view.back, view.number, view.total], ["feishuBind", "feishu", "platform", 2, 4]);
  await ask(host, core, ui, 2, "pick.set", { station: "ws/st", of: "connect-new:feishu", model: "gpt-6-astra", runtime: "codex" });
  await ask(host, core, ui, 3, "pick.save", { station: "ws/st", of: "connect-new:feishu" });
  flow.go(topic, ui, "feishuWay");
  await ask(host, core, ui, 4, "connect.flow.register", form);
  view = flow.value(topic);
  assert.equal(view.step, "feishuScan");
  assert.equal(view.feishu.registration.id, "r1");
  assert.equal(typeof view.feishu.stateText, "string");
  const code = view.feishu.qr;
  assert.ok(code.size >= 21 && (code.size - 17) % 4 === 0, String(code.size));
  assert.deepEqual([code.rows.length, code.rows.every((r: string) => r.length === code.size && /^[01]+$/.test(r))], [code.size, true]);
  assert.equal(code.rows[0].slice(0, 7), "1111111", "a finder pattern in its corner");
  const shaped = present.decorate(topic, structuredClone(view), { now: 0, offsetMin: 0 });
  assert.ok("ok" in conform("ConnectFlowView", shaped), JSON.stringify(conform("ConnectFlowView", shaped)));
  assert.equal(stationPosted(host, "/feishu/connects").length, 0, "nothing added before the bot is made");
  // Made: the connect is added without being asked, once.
  withFeishu(core, [{ ...waiting, state: "done", appId: "cli_1", domain: "feishu" }]);
  await host.settle();
  withFeishu(core, [{ ...waiting, state: "done", appId: "cli_1", domain: "feishu" }]);
  await host.settle();
  const sent = stationPosted(host, "/feishu/connects");
  assert.equal(sent.length, 1);
  assert.deepEqual([sent[0].feishu, sent[0].bind.model, sent[0].bind.runtime, sent[0].mode], [{ registration: "r1" }, "gpt-6-astra", "codex", "multi-session"]);
  view = flow.value(topic);
  assert.deepEqual([view.step, view.feishu.connect, view.feishu.creating], ["done", "codex-bot", false]);
  assert.equal(host.requests.filter((r) => r.method === "DELETE").length, 0, "a bot made is not let go of");
  core.close();
});

test("connect_wizard_checks_a_feishu_app_of_ones_own_and_lets_go_of_a_bot_not_made", async () => {
  const { host, core } = await choosing();
  let verified = 0;
  stationReplies(host, (req) => {
    const path = req.url.replace("https://stillfail.test/admin/api", "");
    if (path === "/feishu/verify") return ++verified === 1 ? { identity: null, errors: ["app_secret 无效"] } : { identity: { botName: "Codex 机器人", tenant: { key: "t", name: "某公司" } }, errors: [] };
    if (req.method === "POST" && path === "/feishu/registrations") return { id: "r2", url: "https://accounts.feishu.cn/x", expiresAt: 1 };
    if (req.method === "DELETE" && path.startsWith("/feishu/registrations/")) return {};
    if (path === "/feishu/connects") return { id: "own-bot" };
    return undefined;
  });
  withFeishu(core, []);
  const ui = core.connect();
  const flow = core.inner.forms.connects;
  const topic = connectTopic("own");
  const form = { station: "ws/st", form: "own" };
  await ask(host, core, ui, 1, "connect.flow.open", form);
  await ask(host, core, ui, 2, "connect.flow.go", { ...form, input: { to: "feishuBind" } });
  await ask(host, core, ui, 3, "pick.set", { station: "ws/st", of: "connect-new:own", model: "gpt-6-astra", runtime: "codex" });
  await ask(host, core, ui, 4, "pick.save", { station: "ws/st", of: "connect-new:own" });
  flow.go(topic, ui, "feishuWay");
  assert.equal(flow.value(topic).feishu.way, "scan");
  flow.edit(topic, ui, { feishu: { way: "app" } });
  assert.equal(flow.value(topic).feishu.way, "app");
  flow.go(topic, ui, "feishuApp");
  assert.equal(flow.value(topic).feishu.canVerify, false);
  assert.throws(() => flow.edit(topic, ui, { feishu: { lark: "yes" } }));
  await ask(host, core, ui, 5, "connect.flow.edit", { ...form, input: { feishu: { appId: " cli_9 ", appSecret: "wrong", lark: true } } });
  await ask(host, core, ui, 6, "connect.flow.verify", form);
  let view = flow.value(topic);
  assert.deepEqual([view.feishu.verified, view.feishu.errors], [false, ["app_secret 无效"]]);
  await assert.rejects(ask(host, core, ui, 7, "connect.flow.create", form), "not verified");
  await ask(host, core, ui, 8, "connect.flow.edit", { ...form, input: { feishu: { appSecret: "right" } } });
  assert.deepEqual(flow.value(topic).feishu.errors, [], "what was found wrong goes once it is changed");
  await ask(host, core, ui, 9, "connect.flow.verify", form);
  view = flow.value(topic);
  assert.deepEqual([view.feishu.verified, view.feishu.identity.botName], [true, "Codex 机器人"]);
  assert.deepEqual(stationPosted(host, "/feishu/verify").at(-1), { appId: "cli_9", appSecret: "right", domain: "lark" });
  const created = await ask(host, core, ui, 10, "connect.flow.create", form);
  assert.equal(created.id, "own-bot");
  assert.deepEqual(stationPosted(host, "/feishu/connects")[0].feishu, { appId: "cli_9", appSecret: "right", domain: "lark" });
  assert.deepEqual([flow.value(topic).step, flow.value(topic).feishu.connect], ["done", "own-bot"]);
  // A bot being made by scanning, the wizard closed: its station stops waiting for it.
  const other = { station: "ws/st", form: "gone" };
  withFeishu(core, []);
  await ask(host, core, ui, 11, "connect.flow.open", other);
  await ask(host, core, ui, 12, "connect.flow.go", { ...other, input: { to: "feishuBind" } });
  await ask(host, core, ui, 13, "pick.set", { station: "ws/st", of: "connect-new:gone", model: "gpt-6-astra", runtime: "codex" });
  await ask(host, core, ui, 14, "pick.save", { station: "ws/st", of: "connect-new:gone" });
  await ask(host, core, ui, 15, "connect.flow.go", { ...other, input: { to: "feishuWay" } });
  await ask(host, core, ui, 16, "connect.flow.register", other);
  assert.equal(flow.value(connectTopic("gone")).feishu.registration.state, "waiting", "as it was started, before the overview says");
  await ask(host, core, ui, 17, "connect.flow.drop", other);
  await host.settle();
  assert.deepEqual(host.requests.filter((r) => r.method === "DELETE").map((r) => r.url.replace("https://stillfail.test/admin/api", "")), ["/feishu/registrations/r2"]);
  core.close();
});

test("an_agent_provided_close_option_never_posts_a_chat_message", async () => {
  const { host, core } = await started({ ...base(), "PUT /threads/7/closed-card": {} });
  const ui = core.connect();
  const card = { seq: 4, card: { type: "options", options: [{ label: "不需要部署", action: "close" }, { label: "部署" }] }, message: { seq: 4, ts: "9.000004", text: "部署吗？", authorName: "Claude" } };
  core.inner.data.set({ topic: "chatRows", station: "ws/st" }, [{ id: "k1", session: "k1", thread: 7, card }]);
  call(core, ui, 71, "decision.answer", { station: "ws/st", thread: 7, seq: 4, option: "不需要部署" });
  await host.settle();
  const closed = host.requests.filter((r) => r.method === "PUT" && r.url.endsWith("/threads/7/closed-card")).map((r) => JSON.parse(new TextDecoder().decode(r.body!)));
  assert.deepEqual(closed, [{ n: 4, option: "不需要部署" }]);
  assert.ok(!host.requests.some((r) => r.method === "POST" && r.url.endsWith("/threads/7/messages")));
  core.close();
});

test("preview_load_topic_reports_pending_finished_and_cancelled_resources", async () => {
  const { host, core } = await started();
  host.onFetchStream(() =>
    Effect.gen(function* () {
      const queue = yield* Queue.unbounded<Uint8Array | null>();
      return { status: 200, headers: [["content-type", "image/png"]] as [string, string][], body: { take: Queue.take(queue) } };
    }),
  );
  const ui = core.connect();
  subscribe(core, ui, 90, { topic: "previewLoad", station: "ws/st", port: 5180 });
  await host.settle();
  const values = new Map();
  const last = () => {
    apply(host, values);
    return v(values, 90);
  };
  assert.equal(last().total, 0);
  call(core, ui, 1, "station.preview", { station: "ws/st", port: 5180, method: "GET", path: "/slow.png", stream: true });
  await host.settle();
  const loading = last();
  assert.equal(loading.percent, 0);
  assert.equal(loading.resources[0].status, 200);
  core.receive(ui, { kind: "cancel", id: 1, cancel: true });
  await host.settle();
  const cancelled = last();
  assert.deepEqual([cancelled.percent, cancelled.failed, cancelled.resources[0].error], [100, 1, "已取消"]);
  core.close();
});

test("session_speed_pick_sends_true_false_and_null_and_new_chats_keep_it", async () => {
  const { host, core } = await choosing(true);
  const ui = core.connect();
  subscribe(core, ui, 9, { topic: "newChat", scope: "ws" });
  subscribe(core, ui, 1, { topic: "pick", station: "ws/st", of: "session:k1" });
  await host.settle();
  const values = new Map();
  apply(host, values);
  assert.equal(v(values, 1).fastAvailable, true);
  for (const fast of [true, false]) {
    await ask(host, core, ui, 2, "pick.set", { station: "ws/st", of: "session:k1", fast });
    apply(host, values);
    assert.equal(v(values, 1).draft.fast, fast);
    assert.equal(v(values, 1).changed, true);
    await ask(host, core, ui, 3, "pick.save", { station: "ws/st", of: "session:k1" });
    assert.equal(stationPosted(host, "/sessions/k1/settings").at(-1).fast, fast);
  }
  await ask(host, core, ui, 4, "newChat.pick", { scope: "ws", station: "st", model: "gpt-6-astra", fast: false });
  await ask(host, core, ui, 5, "newChat.create", { station: "ws/st" });
  await host.settle();
  assert.equal(stationPosted(host, "/sessions").at(-1).fast, false);
  await ask(host, core, ui, 6, "newChat.pick", { scope: "ws", fast: null });
  await ask(host, core, ui, 7, "newChat.create", { station: "ws/st" });
  await host.settle();
  assert.equal("fast" in stationPosted(host, "/sessions").at(-1), false);
  core.close();
});

test("speed_summary_only_shows_effective_fast_and_ignores_unsaved_drafts", async () => {
  for (const profileFast of [false, true]) {
    for (const sessionFast of [null, false, true]) {
      const { host, core } = await choosing(true, profileFast, sessionFast);
      const ui = core.connect();
      subscribe(core, ui, 1, { topic: "pick", station: "ws/st", of: "session:k1" });
      await host.settle();
      const values = new Map();
      apply(host, values);
      const expected = (sessionFast ?? profileFast) ? "Fast" : undefined;
      assert.equal(v(values, 1).fastText, expected, `${profileFast} ${sessionFast}`);
      assert.equal(v(values, 1).fastAvailable, true);
      await ask(host, core, ui, 2, "pick.set", { station: "ws/st", of: "session:k1", fast: !(sessionFast ?? profileFast) });
      apply(host, values);
      assert.equal(v(values, 1).fastText, expected, "drafts do not change the summary");
      subscribe(core, ui, 9, { topic: "newChat", scope: "ws" });
      subscribe(core, ui, 3, { topic: "pick", station: "ws/st", of: "new" });
      await host.settle();
      for (const pinned of [false, true]) {
        await ask(host, core, ui, 4, "newChat.pick", { scope: "ws", station: "st", model: "gpt-6-astra", profile: pinned ? "p3" : "", fast: sessionFast });
        apply(host, values);
        assert.equal(v(values, 3).fastText, (sessionFast ?? (pinned && profileFast)) ? "Fast" : undefined, `${profileFast} ${sessionFast} ${pinned}`);
      }
      core.close();
    }
  }
});

test("lends_the_phone_s_adb_through_its_calls_and_topic", async () => {
  const { host, core } = await started();
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "adbShare" });
  await host.settle();
  const values = new Map();
  apply(host, values);
  assert.deepEqual([v(values, 1).sharing, v(values, 1).phase], [false, "off"]);
  // Only a phone has an adb to lend: a Mac's core reaches TCP too, and its card says it cannot (2026-10-27).
  subscribe(core, ui, 4, { topic: "adbCard", station: "ws1/st1" });
  call(core, ui, 5, "client.device", { app: "desktop", build: "1", userAgent: "Macintosh; Mac OS X" });
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 4).lendable, false);
  call(core, ui, 6, "client.device", { app: "android", build: "1" });
  await host.settle();
  apply(host, values);
  assert.deepEqual([v(values, 4).lendable, v(values, 4).line], [true, "未共享"]);
  call(core, ui, 2, "adb.share", { station: "ws1/st1", connect: 41234, device: "Pixel" });
  await host.settle();
  apply(host, values);
  assert.deepEqual([v(values, 1).sharing, v(values, 1).station, v(values, 1).connectPort], [true, "ws1/st1", 41234]);
  assert.equal(typeof v(values, 1).until, "number");
  call(core, ui, 3, "adb.stop", {});
  await host.settle();
  apply(host, values);
  // Off again, every field of the offer gone (the clients' shape takes their absence).
  assert.deepEqual(v(values, 1), { sharing: false, phase: "off", on: false, tunnels: 0, grants: [], wanted: [], known: true, lasts: "chat", lends: [] });
  core.close();
});

test("a_phone_s_ports_are_taken_before_its_app_says_it_is_a_phone_and_lent_once_it_does", async () => {
  // (a process the phone started for a grant: its service gives the ports before the app has said what it is)
  const { host, core } = await started();
  const exp = Math.floor(host.nowMs() / 1000) + 3600;
  core.inner.adb.heard("ws1/st1", { id: "g1", session: "ember:c1", chat: "c1", reason: "调试", status: "granted", scope: "chat", exp, at: 1 });
  const ui = core.connect();
  const ported = await ask(host, core, ui, 1, "adb.ports", { connect: 41234, device: "Pixel" });
  assert.equal(ported, null);
  subscribe(core, ui, 2, { topic: "adbShare" });
  await ask(host, core, ui, 3, "client.device", { app: "android", build: "1" });
  await ask(host, core, ui, 4, "adb.on", { on: true });
  await host.settle();
  const values = new Map();
  apply(host, values);
  assert.deepEqual(v(values, 2).lends.map((l: J) => l.station), ["ws1/st1"]);
  core.close();
});

test("a_phone_lends_for_its_chats_grants_only_while_its_switch_is_on_and_the_switch_outlives_its_core", async () => {
  // (2026-10-30, user: 「全局的 adb 开关，默认关闭，开启后永远开启，不会因为更新或者重启关掉」)
  const { host, core } = await started();
  const exp = Math.floor(host.nowMs() / 1000) + 3600;
  const ui = core.connect();
  await ask(host, core, ui, 1, "client.device", { app: "android", build: "1" });
  await ask(host, core, ui, 2, "adb.ports", { connect: 41234, device: "Pixel" });
  subscribe(core, ui, 3, { topic: "adbShare" });
  core.inner.adb.heard("ws1/st1", { id: "g1", session: "ember:c1", chat: "c1", reason: "调试", status: "granted", scope: "chat", exp, at: 1 });
  await host.settle();
  const values = new Map();
  apply(host, values);
  // off at first: granted, and lent to none
  assert.deepEqual([v(values, 3).on, v(values, 3).wanted, v(values, 3).lends], [false, ["ws1/st1"], []]);
  await ask(host, core, ui, 4, "adb.on", { on: true });
  await host.settle();
  apply(host, values);
  assert.deepEqual([v(values, 3).on, v(values, 3).lends.map((l: J) => l.station)], [true, ["ws1/st1"]]);
  await host.settle();
  host.takeEmitted();
  core.close();
  // the app's process gone and back (updated, the phone started again): on as it was
  const again = await Core.create(host, { clock: host.time.clock, sample: 0, wire: () => new HostWire(host) });
  const ui2 = again.connect();
  subscribe(again, ui2, 1, { topic: "adbShare" });
  await host.time.pass(500);
  await host.settle();
  const after = new Map(host.takeEmitted().map(([, m]) => m as J).filter((m) => "value" in m).map((m) => [m.id, m.value]));
  assert.equal(v(after, 1).on, true);
  await ask(host, again, ui2, 2, "client.device", { app: "android", build: "1" });
  await ask(host, again, ui2, 3, "adb.on", { on: false });
  await host.settle();
  apply(host, after);
  assert.deepEqual([v(after, 1).on, v(after, 1).lends], [false, []]);
  again.close();
});

test("a_phone_s_grants_kept_on_the_device_lend_it_from_a_core_started_anew", async () => {
  // (lent for a chat's grant; the app's process gone and back, the phone started again: no station reached yet)
  const { host, core } = await started();
  const exp = Math.floor(host.nowMs() / 1000) + 3600;
  core.inner.adb.heard("ws1/st1", { id: "g1", session: "ember:c1", chat: "c1", reason: "调试", status: "granted", scope: "chat", exp, at: 1 });
  await host.settle();
  host.takeEmitted();
  core.close();
  const again = await Core.create(host, { clock: host.time.clock, sample: 0, wire: () => new HostWire(host) });
  const ui = again.connect();
  subscribe(again, ui, 1, { topic: "adbShare" });
  await host.time.pass(500);
  await host.settle();
  const emitted = host.takeEmitted();
  const values = new Map(emitted.map(([, m]) => m as J).filter((m) => "value" in m).map((m) => [m.id, m.value]));
  assert.ok(values.has(1), JSON.stringify(emitted).slice(0, 2000));
  assert.deepEqual([v(values, 1).known, v(values, 1).wanted, v(values, 1).grants.map((g: J) => g.id)], [true, ["ws1/st1"], ["g1"]]);
  again.close();
});

test("automatic_decision_drafts_require_a_model_and_preserve_failed_saves", async () => {
  const { host, core } = await choosing();
  const ui = core.connect();
  const other = core.connect();
  const topic = { topic: "decisionForm", station: "ws/st", form: "automatic-test" };
  await ask(host, core, ui, 1, "automaticDecisions.form.open", { station: "ws/st", form: "automatic-test" });
  const forms = core.inner.forms.decisions;
  assert.ok("ok" in conform("AutomaticDecisionDraft", forms.value(topic)), JSON.stringify(forms.value(topic)));
  assert.throws(() => forms.change(topic, other, "edit", { enabled: true }));
  forms.change(topic, ui, "edit", { enabled: true });
  assert.throws(() => forms.begin(topic, ui));
  forms.change(topic, ui, "edit", { model: "gpt-6-luna" });
  assert.deepEqual(forms.begin(topic, ui), { completion: { enabled: true, model: "gpt-6-luna" } });
  assert.throws(() => forms.change(topic, ui, "edit", { enabled: false }));
  forms.finish(topic, ui, false);
  assert.equal(forms.value(topic).dirty, true);
  forms.begin(topic, ui);
  forms.finish(topic, ui, true);
  assert.equal(forms.value(topic).dirty, false);
  forms.change(topic, ui, "drop", {});
  assert.equal(forms.value(topic), null);
  core.close();
});

test("the_spans_a_core_sends_say_which_build_of_its_app_it_is_once_its_ui_has_said", async () => {
  const { host, core } = await started(base(), 1);
  const ui = core.connect();
  call(core, ui, 1, "client.device", { app: "android", build: "0.1.2420" });
  await host.settle();
  await host.time.pass(EXPORT_MS + 100);
  const sent = exports(host);
  assert.equal(sent.length, 1);
  const resource = JSON.parse(new TextDecoder().decode(sent[0].body!)).resourceSpans[0].resource.attributes as J[];
  assert.deepEqual(resource.find((a) => a.key === "service.version")?.value, { stringValue: "0.1.2420" });
  core.close();
});
