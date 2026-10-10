// The Rust core's core/tests.rs, the rest ported (same names; the checks as the TS core's design has them, its
// deliberate differences in docs/core-ts.md): workspaces kept apart, the beta channel, previews, traces, choices,
// drafts, decisions, the chat list's local overlays, jobs, the archive, forms, the changelog.
import assert from "node:assert/strict";
import { Effect, Queue } from "effect";
import { parseCall } from "../src/core/calls.ts";
import { Loads } from "../src/preview-load.ts";
import { HostWire } from "../src/station/wire.ts";
import { base64 } from "../src/util.ts";
import { test } from "node:test";
import { STORAGE_KEY } from "../src/accounts.ts";
import { Core } from "../src/core.ts";
const STATION = (station: string) => ({ station });
import { FakeHost, jsonResponse } from "../src/testing.ts";
import { account, apply, call, nowS, readsOf, subscribe, v } from "./helpers.ts";
import { run } from "./run.ts";
import { base, overview, session, started, stationHost, stationReplies, threadView } from "./station-fixture.ts";
import { apply as applyOps } from "../src/delta.ts";
import { conform } from "../src/conform.ts";
import { CoreError } from "../src/error.ts";
import { tokensOf } from "../src/forms.ts";
import * as present from "../src/present.ts";
import { PUSH_KEY } from "../src/attention.ts";
import { dbName, SOON_MS } from "../src/data.ts";
import { PENDING_PREFIX } from "../src/views/local.ts";
import { deferralKey } from "../src/decisions.ts";
import { encode } from "../src/ops.ts";
import { EXPORT_MS } from "../src/trace.ts";

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
  for (const station of ["w1/a", "w2/b"]) inner.data.set({ topic: "overview", station }, { profiles: [] });
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
  assert.deepEqual([v(values, 1).tone, v(values, 1).text], ["back", "已连上"]);
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
  assert.deepEqual([entry.blocked, entry.error?.code, entry.workspaces.length], ["这个账号还没开通测试版", "not_beta", 0]);
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
  const reads = ["/events", "/overview", "/sessions", "/threads", "/chats", "/jobs"].map((p) => host.requests.find((r) => r.url === `https://stillfail.test/admin/api${p}`)!);
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
  assert.deepEqual(said(), [{ id: 1, value: { chunk: base64(new TextEncoder().encode("data: 1\n\n")) } }]);
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
  assert.deepEqual(parseCall("preview.socket.send", { socket: "s1", binary: base64(new Uint8Array([0, 1])) }), { kind: "previewSocketSend", socket: "s1", frame: { binary: new Uint8Array([0, 1]) } });
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

test("a_decision_is_answered_in_its_chat_set_aside_on_the_device_and_dismissed_on_the_station", async () => {
  let n = 3;
  const { host, core } = await started({ ...base(), "PUT /threads/7/dismissed": {} });
  stationReplies(host, (req) => (req.method === "POST" && req.url.endsWith("/threads/7/messages") ? { n: ++n } : undefined));
  const ui = core.connect();
  const decision = { seq: 4, options: [{ label: "合", recommended: true }, { label: "先不改" }], message: { seq: 4, ts: "9.000004", text: "合吗？", authorName: "Claude" }, before: [] };
  core.inner.data.set({ topic: "chatRows", station: "ws/st" }, [{ id: "k1", session: "k1", thread: 7, decision }]);
  // Set aside: kept on the device; nothing is sent.
  call(core, ui, 2, "decision.defer", { station: "ws/st", thread: 7, seq: 4 });
  await host.settle();
  const at = deferralKey("ws/st", 7, 4);
  assert.equal(typeof (core.inner.data.get({ topic: "prefs" }) as J).decisionsDeferred[at], "number");
  assert.deepEqual(posted(host), []);
  // Answered: the option's label, quoting the post that asked; no longer set aside.
  call(core, ui, 3, "decision.answer", { station: "ws/st", thread: 7, seq: 4, option: "先不改" });
  await host.settle();
  let sent = posted(host);
  assert.equal(sent[0].text, "先不改");
  assert.deepEqual(sent[0].quotes, [{ author: "Claude", text: "合吗？", comment: "", role: "agent", ts: "9.000004" }]);
  assert.deepEqual((core.inner.data.get({ topic: "prefs" }) as J).decisionsDeferred, {});
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
  call(core, ui, 5, "draft.put", { key: "new:ws/st", text: "新的" });
  call(core, ui, 6, "draft.put", { key: "new:ws/st", text: "" });
  await host.time.pass(SOON_MS + 50);
  await host.settle();
  assert.deepEqual(kept(), ["修一下"]);
  assert.deepEqual(await ask(host, core, ui, 7, "draft.get", { key: "new:ws/st" }), { text: "", quotes: [], files: [] });
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
  await ask(host, core, ui, 2, "newChat.pick", { scope: "ws", model: "gpt-6-astra", runtime: "codex", effort: "medium" });
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
  await ask(host, again, ui, 2, "newChat.pick", { scope: "ws", model: "claude-opus-5-5", effort: "low" });
  await ask(host, again, ui, 3, "newChat.pick", { scope: "ws", model: combo.model, runtime: combo.runtime, effort: combo.effort });
  apply(host, values);
  assert.equal(v(values, 1).model.model, "gpt-6-astra");
  assert.equal(v(values, 1).effort, "medium");
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
  assert.deepEqual(n.accounts[1].quotaLine, { text: "5 小时只剩 20%", level: "amber" });
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
  assert.equal(p.saveText, "不变");
  // Kept to p2 and moved to Sonnet, which p2 does not run: back to the station's pick, said so.
  await ask(host, core, ui, 2, "pick.set", { station: "ws/st", of: "session:k1", profile: "p2" });
  await ask(host, core, ui, 3, "pick.set", { station: "ws/st", of: "session:k1", model: "claude-sonnet-5", effort: "high" });
  apply(host, values);
  p = v(values, 1);
  assert.equal(p.draft.profile ?? null, null);
  assert.ok(String(p.dropped).includes("改成了自动分配"), JSON.stringify(p));
  assert.ok(String(p.force).startsWith("指定的账号「p2」没有启用"), JSON.stringify(p));
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
  // Three characters or more: the full-text index.
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

test("notifications_are_on_until_turned_off_and_kept_so_with_no_pushes", async () => {
  const { host, core } = await started();
  let ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "notify" });
  await host.settle();
  apply(host, values);
  assert.deepEqual(v(values, 1), { on: true, asked: false, push: true, kinds: { wait: true, failed: true, done: "away", message: true }, show: [] });
  // Off (and asked, as Android moves its old settings over): pushes go, and are not taken while off.
  call(core, ui, 2, "notify.set", { on: false, asked: true });
  call(core, ui, 3, "push.register", { kind: "fcm", token: "t" });
  await host.settle();
  apply(host, values);
  assert.deepEqual(v(values, 1), { on: false, asked: true, push: false, kinds: { wait: true, failed: true, done: "away", message: true }, show: [] });
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
  assert.equal(emitted.find((m) => m.id === 1 && "value" in m).value.on, false);
  again.close();
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
  assert.deepEqual([jobs.alarm, jobs.servicesNote, jobs.jobsNote], ["restart", "1 个在重启", "1 个在盯着"]);
  assert.deepEqual([jobs.ended, jobs.clear, jobs.clearText], [1, ["k1"], "清掉 1 个已结束的"]);
  const w = jobs.jobs[1];
  assert.deepEqual([w.tone, w.meta[0].text, w.meta[1].text, w.detail], ["live", "CI 还在跑", " · 2 分钟前", "在盯着 · 1 分钟 · 1 条通知"]);
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
  assert.deepEqual([a.loading, a.note, a.errors], [false, undefined, []]);
  assert.equal(a.days.length, 2);
  assert.equal(a.days[0].label, "今天");
  const first = a.days[0].items[0];
  assert.deepEqual([first.station, first.session, first.thread, first.title, first.last, first.how, first.deletable], ["ws/st", "k1", 7, "聊 k1", "好了", "手动归档", true]);
  assert.equal(first.clock.length, 5);
  // One station: which one is not said.
  assert.equal(first.place, undefined);
  assert.deepEqual([a.days[1].items[0].how, a.days[1].items[0].deletable], ["空闲后自动归档", false]);
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
  assert.deepEqual([v(values, 1).days, v(values, 1).note], [[], "没有归档的对话。"]);
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
  assert.equal(c.days[0].label, "今天");
  assert.deepEqual(c.days[0].entries.map((e: J) => e.note), ["还没发布", "更新到 0.1.1330 后就有", "还没发布", "你的版本已包含"]);
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

test("a_newer_build_says_what_it_brings_this_app_the_changelog_read_again_when_it_came_after", async () => {
  const host = new FakeHost();
  const now = Math.round(host.nowMs() / 1000);
  const entry = (version: number, parts: string[], text: string) => ({ version, commit: "c", at: now, text: [text], fixes: [], parts });
  let out = 1335;
  let entries = [entry(1330, ["android", "web"], "修复：列表跳动"), entry(1325, ["station"], "修复：station 的"), entry(1322, ["desktop"], "新功能：桌面的")];
  host.onFetch((req) => {
    const path = req.url.replace("https://stillfail.test", "");
    if (path === "/v1/changelog") return jsonResponse(200, { entries, released: { android: out, web: out, station: 1320, desktop: 1322 } });
    if (path === "/releases/android/latest.json") return jsonResponse(200, { versionCode: out, versionName: `0.1.${out}`, file: `android/stillfail-${out}.apk`, sha256: "ab", size: 9 });
    return jsonResponse(404, {});
  });
  const core = await Core.create(host, { clock: host.time.clock, sample: 0 });
  const ui = core.connect();
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
  call(core, ui, 2, "adb.share", { station: "ws1/st1", connect: 41234, device: "Pixel" });
  await host.settle();
  apply(host, values);
  assert.deepEqual([v(values, 1).sharing, v(values, 1).station, v(values, 1).connectPort], [true, "ws1/st1", 41234]);
  assert.equal(typeof v(values, 1).until, "number");
  call(core, ui, 3, "adb.stop", {});
  await host.settle();
  apply(host, values);
  // Off again, every field of the offer gone (the clients' shape takes their absence).
  assert.deepEqual(v(values, 1), { sharing: false, phase: "off", tunnels: 0 });
  core.close();
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
