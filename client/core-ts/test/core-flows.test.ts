// client/core/src/core/tests.rs, the rest ported (same names; the checks as the TS core's design has them, its
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
import { account, apply, call, nowS, subscribe, v } from "./helpers.ts";
import { run } from "./run.ts";
import { base, overview, session, started, stationReplies } from "./station-fixture.ts";
import { SOON_MS } from "../src/data.ts";
import { PENDING_PREFIX } from "../src/views/local.ts";
import { deferralKey } from "../src/decisions.ts";
import { encode } from "../src/ops.ts";
import { EXPORT_MS } from "../src/trace.ts";

// deno-lint-ignore no-explicit-any
type J = any;

test("two_workspaces_are_kept_apart", async () => {
  const host = new FakeHost();
  host.store(STORAGE_KEY, [account("s1", "s1@x.com", "s1", "a1", "r", nowS() + 3600), account("s2", "s2@x.com", "s2", "a2", "r", nowS() + 3600)]);
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
  host.store(STORAGE_KEY, [account("s1", "a@x.com", "阿一", "a", "r", nowS() + 3600)]);
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
    await host.settle();
    await host.time.pass(EXPORT_MS + 100);
    const names = exports(host).flatMap(spansOf).map((s) => s.name);
    assert.ok(names.includes("GET /admin/api/memory") && names.includes("memory.get"), JSON.stringify(names));
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
  const kept = () => [...host.db].filter(([k]) => k.startsWith("draft\u0000")).map(([, val]) => JSON.parse(new TextDecoder().decode(val)).text);
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
