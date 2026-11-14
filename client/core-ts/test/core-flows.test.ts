// The Rust core's core/tests.rs, the rest ported (same names; the checks as the TS core's design has them, its
// deliberate differences): workspaces kept apart, the beta channel, previews, traces, choices,
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
import { SOCKET_RETRY_MS } from "../src/sync/cloud.ts";
import { READ_RETRY_MS } from "../src/station/sync.ts";
import { account, apply, call, nowS, readsOf, subscribe, v } from "./helpers.ts";
import { run } from "./run.ts";
import { base, chatsOf, entry, overview, session, started, stationHost, stationLater, stationReplies, status, threadView } from "./station-fixture.ts";
import { apply as applyOps } from "../src/delta.ts";
import { conform } from "../src/conform.ts";
import { CoreError } from "../src/error.ts";
import { ConnectFlows, pickOf, tokensOf } from "../src/forms.ts";
import * as present from "../src/present.ts";
import { PUSH_KEY } from "../src/attention.ts";
import { dbName, SOON_MS } from "../src/data.ts";
import { PENDING_PREFIX } from "../src/views/local.ts";
import { encode } from "../src/ops.ts";
import { EXPORT_MS } from "../src/trace.ts";
import { takeAll } from "./adb-personal-stub.ts";

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
  subscribe(core, ui, 3, { topic: "prefs" });
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 3).productName, "youdid.wtf");
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

test("the_list_changed_reads_the_account_and_the_workspaces_new_to_it_alone", async () => {
  // A member added: the cloud tells the list changed and the workspace changed. Each of the person's devices read
  // /v1/me, its sign-ins, an operator's lists and the workspace twice more besides: seven of them used up the
  // account's 120 requests a minute, and the owner's next call was refused (the locks' end to end, 2026-11-10).
  const host = new FakeHost();
  host.store(STORAGE_KEY, [account("s1", "a@x.com", "阿一", "a", "r", nowS(host) + 3600)]);
  let listed = [{ id: "ws", name: "W" }];
  host.onFetch((req) => {
    const path = req.url.replace("https://stillfail.test", "");
    if (path === "/v1/me") return jsonResponse(200, { user: { sub: "s1" }, workspaces: listed, invitations: [], relay_url: "https://relay.test" });
    if (path.startsWith("/v1/workspaces/")) return jsonResponse(200, { id: path.split("/")[3], name: "W", role: "owner", members: [], stations: [], invitations: [] });
    if (path === "/v1/auth/sessions") return jsonResponse(200, { sessions: [] });
    return jsonResponse(404, { error: "not_found" });
  });
  const core = await Core.create(host, { clock: host.time.clock, sample: 0 });
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "workspaces" });
  await host.settle();
  const asked = () => host.requests.splice(0).map((r) => `${r.method} ${r.url.replace("https://stillfail.test", "")}`).filter((r) => r.includes("/v1/") && !r.includes("/v1/telemetry") && !r.includes("/v1/events")).sort();
  assert.ok(asked().includes("GET /v1/workspaces/ws"), "read as it was first shown");
  // A member added to ws: the list and the workspace told.
  host.socketSend("/v1/events", '{"type":"workspaces"}');
  host.socketSend("/v1/events", '{"type":"workspace","id":"ws"}');
  await host.settle();
  assert.deepEqual(asked(), ["GET /v1/me", "GET /v1/workspaces/ws"]);
  // A workspace made: the one new to the list read too.
  listed = [...listed, { id: "ws2", name: "W2" }];
  host.socketSend("/v1/events", '{"type":"workspaces"}');
  await host.settle();
  assert.deepEqual(asked(), ["GET /v1/me", "GET /v1/workspaces/ws2"]);
  core.close();
});

test("a_release_missed_while_the_events_socket_was_closed_is_read_again_and_the_app_told", async () => {
  // A Mac asleep through a release: the feed's newest was kept from before, so the app got that build ready, put it in
  // as it quit, and updated again once the new one read the feed (2026-11-09, pengxiao).
  const host = new FakeHost();
  host.store(STORAGE_KEY, [account("s1", "a@x.com", "阿一", "a", "r", nowS(host) + 3600)]);
  let out = 1200;
  host.onFetch((req) => {
    const path = req.url.replace("https://stillfail.test", "");
    if (path === "/v1/me") return jsonResponse(200, { user: { sub: "s1" }, workspaces: [], invitations: [], relay_url: "https://relay.test" });
    if (path === "/releases/mac/latest.json") return jsonResponse(200, { versionCode: out, versionName: `0.1.${out}`, file: `mac/stillfail-${out}.zip`, sha256: "ab", size: 9 });
    return jsonResponse(404, { error: "not_found" });
  });
  const core = await Core.create(host, { clock: host.time.clock, sample: 0 });
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "releases" });
  await host.settle();
  apply(host, values);
  const told = v(values, 1).told;
  assert.equal((await ask(host, core, ui, 2, "app.update", { platform: "mac", versionCode: 1100 })).versionCode, 1200);
  // Told of a release: read again, and the app told.
  out = 1250;
  host.socketSend("/v1/events", '{"type":"release"}');
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 1).told, told + 1);
  assert.equal((await ask(host, core, ui, 3, "app.update", { platform: "mac", versionCode: 1100 })).versionCode, 1250);
  // The socket closed through the next release: none said, so read again as it opens again.
  host.socketClose("/v1/events");
  out = 1300;
  await host.time.pass(SOCKET_RETRY_MS * 2, 50);
  await host.settle();
  apply(host, values);
  assert.equal(host.openSockets("/v1/events"), 1);
  assert.equal(v(values, 1).told, told + 2);
  assert.equal((await ask(host, core, ui, 4, "app.update", { platform: "mac", versionCode: 1100 })).versionCode, 1300);
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
  subscribe(core, ui, 4, { topic: "prefs" });
  subscribe(core, ui, 5, { topic: "changelog", part: "station" });
  await host.settle();
  const values = new Map();
  answersOf(host, values);
  // Each part's tab its own changes, the tab asked alone with them (this app's where none is said).
  const said = (id: number) => v(values, id).tabs.map((x: J) => [x.part, x.days.flatMap((d: J) => d.entries.map((e: J) => e.lines[0].text))]);
  assert.deepEqual(said(2), [["android", ["安卓的"]], ["desktop", []], ["web", []], ["station", []], ["cloud", []]]);
  assert.deepEqual(said(5), [["android", []], ["desktop", []], ["web", []], ["station", ["station 的"]], ["cloud", []]]);
  assert.equal(brandName(), "still.fail");
  assert.equal(v(values, 4).productName, "still.fail");
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

test("a failed turn's notice and its 重试 pass through the real core", async () => {
  const failed = {
    id: "turn-1", kind: "input", outcome: "failed", declared: null, detail: "network: fetch failed",
    about: { thread: 7, seq: 1, ts: "1.0" }, startedAt: 1, endedAt: 2,
  };
  const agent = { ...session("k1", 1), lastTurn: failed };
  const notice = { ...entry(1, "⚠️ 与模型服务的连接中断，回复即可重试"), authorKind: "ember", author: "ember" };
  const { host, core } = await started({
    ...base(),
    "GET /sessions": [agent],
    "GET /sessions/k1": { session: agent, threads: [], turns: [], jobs: [] },
    "GET /threads": [threadView(7, 1)],
    "GET /threads/7/entries?limit=50": { last: 1, entries: [notice] },
  });
  try {
    stationReplies(host, (req) => req.method === "POST" && req.url.endsWith("/sessions/k1/retry") ? { ok: true } : undefined);
    const ui = core.connect();
    const values = new Map();
    subscribe(core, ui, 1, { topic: "chat", station: "ws/st", thread: 7, session: null });
    await host.settle();
    await host.settle();
    apply(host, values);
    assert.equal(v(values, 1).messages[0].notice.againSession, "k1");
    call(core, ui, 2, "session.retry", { station: "ws/st", key: "k1", thread: 7, seq: 1 });
    await host.settle();
    const sent = host.requests.find((req) => req.method === "POST" && req.url.endsWith("/sessions/k1/retry"));
    assert.ok(sent);
    assert.deepEqual(JSON.parse(new TextDecoder().decode(sent.body!)), { thread: 7, seq: 1 });
  } finally {
    core.close();
  }
});

const header = (r: { headers: [string, string][] }, name: string) => r.headers.find(([k]) => k === name)?.[1];
const exports = (host: FakeHost) => host.requests.filter((r) => r.url.endsWith("/v1/telemetry/traces"));
const spansOf = (r: { body?: Uint8Array | null }) => JSON.parse(new TextDecoder().decode(r.body!)).resourceSpans[0].scopeSpans[0].spans as J[];

test("a capacity notice and its cancel action pass through the real core", async () => {
  const retry = {
    id: "turn-1", kind: "input", outcome: "failed", declared: "waiting", detail: "overloaded: at capacity",
    about: { thread: 7, seq: 1, ts: "1.0" }, waitSeconds: 30, waitWatch: false, startedAt: 1, endedAt: 2,
  };
  const agent = { ...session("k1", 1), lastTurn: retry };
  const notice = { ...entry(1, "⚠️ 模型满载，自动重试，与额度无关"), authorKind: "ember", author: "ember" };
  const { host, core } = await started({
    ...base(),
    "GET /sessions": [agent],
    "GET /sessions/k1": { session: agent, threads: [], turns: [], jobs: [] },
    "GET /threads": [threadView(7, 1)],
    "GET /threads/7/entries?limit=50": { last: 1, entries: [notice] },
  });
  try {
    stationReplies(host, (req) => req.method === "POST" && req.url.endsWith("/sessions/k1/cancel-retry") ? { ok: true } : undefined);
    const ui = core.connect();
    const values = new Map();
    subscribe(core, ui, 1, { topic: "chat", station: "ws/st", thread: 7, session: null });
    await host.settle();
    await host.settle();
    apply(host, values);
    assert.equal(v(values, 1).messages[0].notice.retrySession, "k1");
    call(core, ui, 2, "session.cancelRetry", { station: "ws/st", key: "k1", thread: 7, seq: 1 });
    await host.settle();
    const sent = host.requests.find((req) => req.method === "POST" && req.url.endsWith("/sessions/k1/cancel-retry"));
    assert.ok(sent);
    assert.deepEqual(JSON.parse(new TextDecoder().decode(sent.body!)), { thread: 7, seq: 1 });
  } finally {
    core.close();
  }
});

test("a_chat_opening_is_one_trace_its_requests_carry_and_ember_cloud_gets", async () => {
  // Deliberately otherwise (rule 6): a chat opening reads only what is held, so it asks the station
  // nothing; what the Rust core's chat.open traced is the station's own reading, one trace from its connecting on.
  const { host, core } = await started({ ...base(), "GET /memory": { global: "" } }, 1);
  const ui = core.connect();
  const before = host.requests.length;
  subscribe(core, ui, 1, { topic: "chat", station: "ws/st", thread: 7 });
  await host.settle();
  await host.settle();
  const said = host.takeEmitted().map(([, m]) => m as J);
  assert.ok(said.some((m) => m.id === 1 && "value" in m), JSON.stringify(said).slice(0, 500));
  // (but its agent's history brought whole behind every other read, the sync's: topics.ts `#wholeHistory`)
  assert.equal(host.requests.slice(before).filter((r) => !r.url.includes("/timeline?")).length, 0, "opening a chat asks nothing");
  const reads = ["/events?running=1&views=1&rows=1&shared=1", "/overview", "/sessions", "/threads", "/chats?marks=1", "/jobs?chats=0"].map((p) => host.requests.find((r) => r.url === `https://stillfail.test/admin/api${p}`)!);
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
  const { host, core } = await started({ ...base(), ...chatsOf([{ thread: 7, session: "k1", title: "部署", agents: [agent], lastActiveAt: 1, need }]) });
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

test("the legacy app identity names newly approved devices still.fail", async () => {
  // Older app builds still identify themselves this way; the device's name should use the product name.
  const { host, core } = await started();
  const ui = core.connect();
  call(core, ui, 1, "client.device", { app: "android", build: "0.1.3628", model: "OPPO PLP110", client: "still.fail mbui", locale: "zh-CN" });
  call(core, ui, 2, "auth.begin", { redirect_uri: "r", return_to: "/" });
  await host.settle();
  const emitted = host.takeEmitted().map(([, m]) => m as J);
  const url = String(emitted.find((m) => m.id === 2 && "ok" in m).ok.url);
  assert.ok(url.includes(`name=${encode("still.fail Android · OPPO PLP110")}`), url);
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
  assert.ok(url.includes(`name=${encode("still.fail Android · OPPO Find N5")}`), url);
  call(core, ui, 3, "client.device", { app: "desktop", build: "0.1.5600", userAgent: "Macintosh; Mac OS X", machine: "林的 MacBook Air", client: "still.fail mbui", locale: "zh-CN" });
  call(core, ui, 4, "auth.begin", { redirect_uri: "r", return_to: "/" });
  await host.settle();
  const again = host.takeEmitted().map(([, m]) => m as J);
  const named = String(again.find((m) => m.id === 4 && "ok" in m).ok.url);
  assert.ok(named.includes(`name=${encode("still.fail 桌面版 · 林的 MacBook Air")}`), named);
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
  assert.ok(url.includes(`name=${encode("still.fail iOS · iPhone17,1")}`), url);
  call(core, ui, 4, "chat.send", { station: "ws/st", thread: 7, text: "hi" });
  await host.settle();
  assert.equal(posted(host)[0].client, "ios 0.1.3700");
  core.close();
});

test("sending_to_an_archived_chat_restores_it_before_delivery_and_keeps_a_failed_restore_retryable", async () => {
  const thread = { ...threadView(7, 0), hiddenAt: 42 };
  const { host, core } = await started({
    ...base(),
    "GET /threads": [thread],
    "GET /threads/7/entries?limit=50": { first: 1, last: 0, entries: [], thread },
  });
  let restored = false;
  let fail = true;
  const steps: string[] = [];
  stationReplies(host, (req) => {
    if (req.method === "DELETE" && req.url.endsWith("/threads/7/archive")) {
      steps.push("restore");
      if (fail) return status(400, { error: "restore failed" });
      restored = true;
      return { ok: true };
    }
    if (req.method === "POST" && req.url.endsWith("/threads/7/messages")) {
      assert.ok(restored, "the message cannot go before the chat is restored");
      steps.push("send");
      return { n: 1 };
    }
    return undefined;
  });
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "chat", station: "ws/st", session: "k1" });
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 1).archived, true);
  call(core, ui, 2, "chat.send", { station: "ws/st", thread: 7, text: "继续" });
  await host.settle();
  apply(host, values);
  assert.deepEqual(steps, ["restore"]);
  const pending = v(values, 1).outbox[0];
  assert.equal(pending.text, "继续");
  assert.equal(pending.state, "failed");
  assert.notEqual(pending.final, true, "restoring can be retried even when the station refused it");
  fail = false;
  call(core, ui, 3, "chat.retry", { station: "ws/st", thread: 7, id: pending.id });
  await host.settle();
  assert.deepEqual(steps, ["restore", "restore", "send"]);
  core.close();
});

test("a_message_in_the_outbox_carries_its_words_in_runs_as_its_message_will", async () => {
  const thread = threadView(7, 0);
  const { host, core } = await started({
    ...base(),
    "GET /threads": [thread],
    "GET /threads/7/entries?limit=50": { first: 1, last: 0, entries: [], thread },
  });
  stationReplies(host, (req) => (req.method === "POST" && req.url.endsWith("/threads/7/messages") ? status(500, { error: "busy" }) : undefined));
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "chat", station: "ws/st", session: "k1" });
  await host.settle();
  call(core, ui, 2, "chat.send", { station: "ws/st", thread: 7, text: "看 [首页](https://app.still.fail/w/ws/s/st/chats/s-c2) 吧" });
  await host.settle();
  apply(host, values);
  // What the page draws while it is in the outbox: the reference, never `[首页](…)` as written.
  const pending = v(values, 1).outbox[0];
  assert.deepEqual(pending.words.map((r: J) => [r.text, r.ref ?? false]), [["看 ", false], ["首页", true], [" 吧", false]]);
  core.close();
});

test("two_messages_sent_during_a_restore_do_not_lose_the_second_if_the_first_restore_fails", async () => {
  const thread: J = { ...threadView(7, 0), hiddenAt: 42 };
  const { host, core } = await started({
    ...base(),
    "GET /threads": [thread],
    "GET /threads/7/entries?limit=50": { first: 1, last: 0, entries: [], thread },
  });
  let attempts = 0;
  const sent: string[] = [];
  stationReplies(host, (req) => {
    if (req.method === "DELETE" && req.url.endsWith("/threads/7/archive")) {
      if (++attempts === 1) return status(400, { error: "restore failed" });
      thread.hiddenAt = null;
      return thread;
    }
    if (req.method === "POST" && req.url.endsWith("/threads/7/messages")) {
      assert.equal(thread.hiddenAt, null);
      sent.push(JSON.parse(new TextDecoder().decode(req.body!)).text);
      return { n: sent.length };
    }
    return undefined;
  });
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "chat", station: "ws/st", session: "k1" });
  await host.settle();
  const release = host.hold("/threads/7/archive");
  call(core, ui, 2, "chat.send", { station: "ws/st", thread: 7, text: "第一条" });
  await host.settle();
  call(core, ui, 3, "chat.send", { station: "ws/st", thread: 7, text: "第二条" });
  await host.settle();
  release();
  await host.settle();
  apply(host, values);
  assert.deepEqual(sent, ["第二条"]);
  const first = v(values, 1).outbox.find((m: J) => m.text === "第一条");
  assert.equal(first.state, "failed");
  assert.notEqual(first.final, true);
  call(core, ui, 4, "chat.retry", { station: "ws/st", thread: 7, id: first.id });
  await host.settle();
  assert.deepEqual(sent, ["第二条", "第一条"]);
  core.close();
});

test("sending_to_an_archived_session_without_a_thread_restores_it_after_making_its_chat", async () => {
  const archived = { ...session("k1"), archivedAt: 42 };
  const { host, core } = await started({
    ...base(),
    "GET /sessions": [archived],
    "GET /sessions/k1": { session: archived, threads: [], turns: [], jobs: [] },
    "GET /threads": [],
    "GET /chats": [],
  });
  const steps: string[] = [];
  stationReplies(host, (req) => {
    const path = req.url.replace("https://stillfail.test/admin/api", "");
    if (req.method === "POST" && path === "/threads") {
      steps.push("make chat");
      return threadView(7, 0);
    }
    if (req.method === "DELETE" && path === "/threads/7/archive") {
      steps.push("restore");
      return { ok: true };
    }
    if (req.method === "POST" && path === "/threads/7/messages") {
      steps.push("send");
      return { n: 1 };
    }
    return undefined;
  });
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "chat", station: "ws/st", session: "k1" });
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 1).archived, true);
  call(core, ui, 2, "chat.send", { station: "ws/st", session: "k1", text: "继续" });
  await host.settle();
  await host.settle();
  assert.deepEqual(steps, ["make chat", "restore", "send"]);
  core.close();
});

test("sending_to_an_archived_chat_uses_an_older_stations_session_restore_route", async () => {
  const thread = { ...threadView(7, 0), hiddenAt: 42 };
  const { host, core } = await started({
    ...base(),
    "GET /threads": [thread],
    "GET /threads/7/entries?limit=50": { first: 1, last: 0, entries: [], thread },
  });
  const steps: string[] = [];
  stationReplies(host, (req) => {
    if (req.method === "DELETE" && req.url.endsWith("/threads/7/archive")) {
      steps.push("thread route");
      return status(404, { error: "no route" });
    }
    if (req.method === "DELETE" && req.url.endsWith("/sessions/k1/archive")) {
      steps.push("session route");
      return { ok: true };
    }
    if (req.method === "POST" && req.url.endsWith("/threads/7/messages")) {
      steps.push("send");
      return { n: 1 };
    }
    return undefined;
  });
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "chat", station: "ws/st", session: "k1" });
  await host.settle();
  call(core, ui, 2, "chat.send", { station: "ws/st", session: "k1", text: "继续" });
  await host.settle();
  assert.deepEqual(steps, ["thread route", "session route", "send"]);
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

test("an account's topic gives the app each station once when it has two copies", async () => {
  const email = "same@x.com";
  const profiles = [
    profile("signed", "codex", [], true, 0, { email }),
    profile("borrowed", "codex", [], true, 0, { email, share: { id: "sh1", role: "user", host: "other" } }),
  ];
  const { host, core } = await started({ ...base(), "GET /overview": { ...overview, profiles } });
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "profiles", scope: "ws" });
  subscribe(core, ui, 2, { topic: "profile", scope: "ws", key: `sub:codex:${email}` });
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 1).items.length, 1, "one row");
  const row = v(values, 2);
  assert.equal(row.members.length, 2);
  assert.deepEqual(row.places.map((p: J) => [p.station, p.profileId, p.usable]), [["ws/st", "signed", true]]);
  core.close();
});

/// A core whose station has three profiles: p1 (unchecked) and p2 run Claude Code, p3 Codex (core/tests.rs
/// `choosing_core`); `speed`: its session on Codex with `fast` as given, p3 offering `fast` as `profileFast`.
async function choosing(speed = false, profileFast = false, sessionFast: boolean | null = null, switchRuntime = false, contexts = false) {
  const s = (key: string) => (speed ? { ...session(key), runtime: "codex", model: "gpt-6-astra", profile: "p3", fast: sessionFast } : session(key));
  return started({
    ...base(),
    "GET /overview": {
      ...overview,
      sessionRuntimeChange: switchRuntime,
      connectRuntimeChange: switchRuntime,
      ...(contexts ? { contextCaps: { runtimes: ["claude", "codex"], least: 100_000, windows: { "claude-opus-5-5": 1_000_000 } } } : {}),
      connects: [{ id: "c1", name: "c1", kind: "slack", mode: "multi-session", requireMention: true, enabled: true, bind: { runtime: "claude", model: "claude-opus-5-5" }, connection: { state: "connected" }, slack: { appToken: "", botToken: "" }, sessions: 0 }],
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
    "PUT /connects/c1": { ok: true },
  });
}

test("a disabled unchecked profile is checked only once it is enabled", async () => {
  const p = profile("p1", "claude", ["claude-opus-5-5"], false, 0, { enabled: false });
  const { host, core } = await started({
    ...base(),
    "GET /overview": { ...overview, profiles: [p] },
    "POST /profiles/p1/check": { state: "ok", detail: "", checkedAt: 2 },
  });
  try {
    const ui = core.connect();
    subscribe(core, ui, 1, { topic: "newChat", scope: "ws" });
    await host.settle();
    assert.equal(stationPosted(host, "/profiles/p1/check").length, 0);
    core.inner.data.set({ topic: "overview", station: "ws/st" }, { ...overview, profiles: [{ ...p, enabled: true }] });
    await host.settle();
    assert.equal(stationPosted(host, "/profiles/p1/check").length, 1);
  } finally { core.close(); }
});

test("a_new_chat_is_made_under_the_key_its_page_had_before_it_was_made_and_its_page_reads_it_so_at_once", async () => {
  const { host, core } = await choosing();
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "newChat", scope: "ws" });
  await host.settle();
  const values = new Map();
  apply(host, values);
  const next = v(values, 1).next;
  assert.ok(typeof next === "string" && next.startsWith("new:"), String(next));
  // made under it, and read under it from then (the chat's page, the moment the words were sent)
  const made = await ask(host, core, ui, 2, "newChat.create", { station: "ws/st", key: next });
  assert.equal(made.key, next);
  subscribe(core, ui, 3, { topic: "chat", station: "ws/st", thread: null, session: next });
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 3).pending, true);
  // the next one under another; a key already used is refused, not made twice
  const after = v(values, 1).next;
  assert.ok(typeof after === "string" && after.startsWith("new:") && after !== next, String(after));
  await assert.rejects(ask(host, core, ui, 4, "newChat.create", { station: "ws/st", key: next }));
  // none given: one made by the core, as before
  const own = await ask(host, core, ui, 5, "newChat.create", { station: "ws/st" });
  assert.ok(String(own.key).startsWith("new:") && own.key !== next);
  core.close();
});

// (the combinations, how hard it thinks and how fast are the core's own value's: its page is sent its model control's, `pick`)
test("new_chat_combos_are_local_to_a_workspace_persist_and_pick_model_and_depth_together", async () => {
  const { host, core } = await choosing();
  let ui = core.connect();
  const topic = { topic: "newChat", scope: "ws" };
  subscribe(core, ui, 1, topic);
  await host.settle();
  let values = new Map();
  apply(host, values);
  const own = (c: Core) => c.inner.store.get(topic) as J;
  assert.deepEqual(own(core).frequent, []);
  assert.deepEqual([v(values, 1).frequent, v(values, 1).effort, v(values, 1).accounts], [undefined, undefined, undefined], "not sent");
  await ask(host, core, ui, 2, "newChat.pick", { scope: "ws", model: "gpt-6-astra", runtime: "codex", effort: "medium", fast: true });
  apply(host, values);
  assert.deepEqual(own(core).frequent, [], "picking alone is not usage");
  core.inner.choose.used("other/st", { model: "claude-opus-5-5", runtime: "claude", effort: "high" });
  await ask(host, core, ui, 3, "newChat.create", { station: "ws/st" });
  apply(host, values);
  const combos = own(core).frequent;
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
  const combo = own(again).frequent[0];
  assert.equal(combo.model, "gpt-6-astra");
  assert.equal(combo.fast, true);
  await ask(host, again, ui, 2, "newChat.pick", { scope: "ws", model: "claude-opus-5-5", effort: "low", fast: false });
  await ask(host, again, ui, 3, "newChat.pick", { scope: "ws", model: combo.model, runtime: combo.runtime, effort: combo.effort, fast: combo.fast });
  apply(host, values);
  assert.equal(v(values, 1).model.model, "gpt-6-astra");
  assert.deepEqual([own(again).effort, own(again).fast, own(again).frequent[0].selected], ["medium", true, true]);
  again.close();
});

// What is used most is a configuration, apart from what is starred (the user, 2026-11-10: 「收藏跟常用不一样」「常用包括了
// 思考深度和速度还有上下文长度」「是一种配置」).
test("the_model_control_keeps_the_configurations_used_most_near_and_each_model_as_it_last_ran", async () => {
  const { host, core } = await choosing();
  const ui = core.connect();
  const fresh = { topic: "pick", station: "ws/st", of: "new" };
  const chat = { topic: "pick", station: "ws/st", of: "session:k1" };
  subscribe(core, ui, 1, fresh);
  subscribe(core, ui, 2, chat);
  subscribe(core, ui, 3, { topic: "newChat", scope: "ws" });
  await host.settle();
  const values = new Map();
  apply(host, values);
  const option = (n: number, model: string) => v(values, n).options.find((o: J) => o.model === model);
  // (as it last ran: a field none is left out of the topic)
  const ran = (o: J) => ["runtime", "effort", "fast"].map((f) => o.usual?.[f] ?? null);
  const combo = (c: J) => [c.model, c.runtime, c.effort ?? null, c.fast ?? null, c.context ?? null];
  for (const [n, m] of [[7, "claude-opus-5-5"], [8, "claude-sonnet-5"], [9, "gpt-6-astra"]] as const) {
    await ask(host, core, ui, n, "pick.like", { station: "ws/st", of: "new", model: m, liked: false });
  }
  apply(host, values);
  assert.deepEqual(v(values, 1).combos, [], "nothing used here yet");
  assert.equal(option(1, "gpt-6-astra").usual ?? null, null);
  core.inner.choose.used("ws/st", { model: "gpt-6-astra", runtime: "codex", effort: "medium" });
  core.inner.choose.used("ws/st", { model: "gpt-6-astra", runtime: "codex", effort: "medium" });
  core.inner.choose.used("ws/st", { model: "claude-sonnet-5", runtime: "claude", effort: null });
  core.inner.choose.used("other/st", { model: "claude-opus-5-5", runtime: "claude", effort: null });
  await host.settle();
  apply(host, values);
  // the used most first, another workspace's not at all; each said as it runs
  assert.deepEqual(v(values, 1).combos.map(combo), [["gpt-6-astra", "codex", "medium", null, null], ["claude-sonnet-5", "claude", null, null, null]]);
  assert.deepEqual(v(values, 1).combos.map((c: J) => [c.name, c.text]), [["GPT-6 Astra", "Codex · 中"], ["Sonnet 5", "CC · 默认深度"]]);
  assert.equal(option(1, "gpt-6-astra").uses, undefined);
  assert.deepEqual(ran(option(1, "gpt-6-astra")), ["codex", "medium", null]);
  assert.equal(option(1, "gpt-6-astra").usualText, "Codex · 中");
  // a chat's whose runtime is fixed: of its runtime alone
  assert.deepEqual(v(values, 2).combos.map(combo), [["claude-sonnet-5", "claude", null, null, null]]);
  // the same model run another way: another, counted on its own
  core.inner.choose.used("ws/st", { model: "gpt-6-astra", runtime: "codex", effort: "high" });
  await host.settle();
  apply(host, values);
  const combos = v(values, 1).combos.map(combo);
  assert.deepEqual(combos[0], ["gpt-6-astra", "codex", "medium", null, null]);
  assert.deepEqual(combos.slice(1).sort(), [["claude-sonnet-5", "claude", null, null, null], ["gpt-6-astra", "codex", "high", null, null]].sort());
  // picked with how it last ran (the newest of it): all of it saved at once
  const [runtime, effort, fast] = ran(option(1, "gpt-6-astra"));
  assert.deepEqual([runtime, effort, fast], ["codex", "high", null]);
  // a configuration of it pressed: all of it saved at once
  await ask(host, core, ui, 4, "pick.save", { station: "ws/st", of: "new", model: "gpt-6-astra", runtime: "codex", effort: "medium", fast: null, context: null });
  apply(host, values);
  assert.equal(v(values, 3).model.model, "gpt-6-astra");
  assert.equal((core.inner.store.get({ topic: "newChat", scope: "ws" }) as J).effort, "medium");
  // the one picked exactly as the panel has it drafted, and only that
  const selected = () => v(values, 1).combos.filter((c: J) => c.selected).map(combo);
  assert.deepEqual(selected(), [["gpt-6-astra", "codex", "medium", null, null]]);
  await ask(host, core, ui, 10, "pick.set", { station: "ws/st", of: "new", effort: "high" });
  apply(host, values);
  assert.deepEqual(selected(), [["gpt-6-astra", "codex", "high", null, null]]);
  await ask(host, core, ui, 11, "pick.set", { station: "ws/st", of: "new", fast: true });
  apply(host, values);
  assert.deepEqual(selected(), [], "how fast it runs is part of it");
  await ask(host, core, ui, 12, "pick.set", { station: "ws/st", of: "new", open: true });
  // how hard it thinks changed for it: kept for it, as it runs next time it is picked
  await ask(host, core, ui, 5, "pick.save", { station: "ws/st", of: "new", effort: null });
  await ask(host, core, ui, 6, "pick.save", { station: "ws/st", of: "new", model: "claude-sonnet-5" });
  apply(host, values);
  assert.deepEqual(ran(option(1, "gpt-6-astra")), ["codex", null, null]);
  assert.equal(option(1, "gpt-6-astra").usualText ?? null, "Codex");
  core.close();
});

test("the_configurations_used_most_keep_their_context_each_on_its_own", async () => {
  const { host, core } = await choosing(false, false, null, false, true);
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "pick", station: "ws/st", of: "new" });
  await host.settle();
  const values = new Map();
  apply(host, values);
  const opus = { model: "claude-opus-5-5", runtime: "claude", effort: "high" };
  core.inner.choose.used("ws/st", { ...opus, context: 300_000 });
  core.inner.choose.used("ws/st", { ...opus, context: 300_000 });
  core.inner.choose.used("ws/st", { ...opus, context: null });
  // (one no longer offered: none of it)
  core.inner.choose.used("ws/st", { ...opus, context: 400_000 });
  core.inner.choose.used("ws/st", { ...opus, context: 400_000 });
  core.inner.choose.used("ws/st", { ...opus, context: 400_000 });
  await host.settle();
  apply(host, values);
  assert.deepEqual(v(values, 1).combos.map((c: J) => [c.model, c.context ?? null, c.text]), [["claude-opus-5-5", 300_000, "CC · 高 · 300K"], ["claude-opus-5-5", null, "CC · 高"]]);
  // pressed: all of it made what it runs on, picked exactly
  await ask(host, core, ui, 2, "pick.save", { station: "ws/st", of: "new", ...opus, fast: null, context: 300_000 });
  apply(host, values);
  assert.deepEqual(v(values, 1).combos.map((c: J) => c.selected), [true, false]);
  core.close();
});

// A configuration used most can be taken out (the user, 2026-11-10: 「常用模型应该是一种特定配置，并且可以删掉，跟模型
// 没有关系」): that one alone, the model's others, how it last ran and the starred staying.
test("a_configuration_used_most_is_forgotten_alone_and_counted_anew_when_used_again", async () => {
  const { host, core } = await choosing();
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "pick", station: "ws/st", of: "new" });
  await host.settle();
  const values = new Map();
  apply(host, values);
  const combo = (c: J) => [c.model, c.runtime, c.effort ?? null];
  const astra = { model: "gpt-6-astra", runtime: "codex" };
  for (let i = 0; i < 3; i++) core.inner.choose.used("ws/st", { ...astra, effort: "high" });
  core.inner.choose.used("ws/st", { ...astra, effort: "medium" });
  core.inner.choose.used("ws/st", { ...astra, effort: "medium" });
  await ask(host, core, ui, 2, "pick.like", { station: "ws/st", of: "new", model: "gpt-6-astra", liked: true });
  await host.settle();
  apply(host, values);
  assert.deepEqual(v(values, 1).combos.map(combo), [["gpt-6-astra", "codex", "high"], ["gpt-6-astra", "codex", "medium"]]);
  const usual = v(values, 1).options.find((o: J) => o.model === "gpt-6-astra").usual;
  // the one forgotten, the pushed view without it
  await ask(host, core, ui, 3, "pick.forget", { station: "ws/st", of: "new", ...astra, effort: "high", fast: null, context: null });
  apply(host, values);
  assert.deepEqual(v(values, 1).combos.map(combo), [["gpt-6-astra", "codex", "medium"]]);
  assert.ok(v(values, 1).liked.includes("gpt-6-astra"), "still starred");
  assert.deepEqual(v(values, 1).options.find((o: J) => o.model === "gpt-6-astra").usual, usual, "how it last ran stays");
  // one not there: nothing changes
  const before = v(values, 1).combos;
  await ask(host, core, ui, 4, "pick.forget", { station: "ws/st", of: "new", ...astra, effort: "low", fast: null, context: null });
  apply(host, values);
  assert.deepEqual(v(values, 1).combos, before);
  // a new chat on it again: back, counted from one (after the other, used twice)
  core.inner.choose.used("ws/st", { ...astra, effort: "high" });
  await host.settle();
  apply(host, values);
  assert.deepEqual(v(values, 1).combos.map(combo), [["gpt-6-astra", "codex", "medium"], ["gpt-6-astra", "codex", "high"]]);
  core.close();
});

test("a_model_never_run_here_takes_what_is_set_by_hand_in_its_panel_and_one_that_ran_here_keeps_its_own", async () => {
  const { host, core } = await choosing();
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "pick", station: "ws/st", of: "new" });
  subscribe(core, ui, 3, { topic: "newChat", scope: "ws" });
  await host.settle();
  const values = new Map();
  apply(host, values);
  const option = (model: string) => v(values, 1).options.find((o: J) => o.model === model);
  core.inner.choose.used("ws/st", { model: "gpt-6-astra", runtime: "codex", effort: "medium" });
  await host.settle();
  apply(host, values);
  assert.equal(option("claude-sonnet-5").usual ?? null, null, "never run here");
  // its panel opened, how hard it thinks set by hand in it
  await ask(host, core, ui, 2, "pick.set", { station: "ws/st", of: "new", open: true });
  await ask(host, core, ui, 4, "pick.save", { station: "ws/st", of: "new", effort: "high" });
  apply(host, values);
  const effort = () => (core.inner.store.get({ topic: "newChat", scope: "ws" }) as J).effort;
  assert.equal(effort(), "high");
  assert.equal(option("gpt-6-astra").usual.effort, "medium", "one that ran here keeps its own");
  assert.equal(option("gpt-6-astra").usualText, "Codex · 中");
  assert.equal(option("claude-sonnet-5").usual.effort, "high", "one that never did takes it");
  assert.equal(option("claude-sonnet-5").usualText, "CC · 高");
  // opened again: nothing set by hand in it yet
  await ask(host, core, ui, 5, "pick.set", { station: "ws/st", of: "new", open: true });
  apply(host, values);
  assert.equal(option("claude-sonnet-5").usual ?? null, null);
  // set to what it already runs with: set by hand all the same
  await ask(host, core, ui, 6, "pick.save", { station: "ws/st", of: "new", effort: "high" });
  apply(host, values);
  assert.equal(option("claude-sonnet-5").usual.effort, "high");
  // picked as the panel says it runs
  const u = option("claude-sonnet-5").usual;
  await ask(host, core, ui, 7, "pick.save", { station: "ws/st", of: "new", model: "claude-sonnet-5", runtime: u.runtime, effort: u.effort, fast: u.fast, context: u.context });
  apply(host, values);
  assert.equal(v(values, 3).model.model, "claude-sonnet-5");
  assert.equal(effort(), "high");
  core.close();
});

test("merged_models_across_devin_and_agy_name_their_available_runtimes_and_single_runtime_models_show_theirs_when_multi_runtime", async () => {
  const dev = profile("dev", "devin", ["gemini-4-carbon", "swe-2"], true, 10, {
    check: { state: "ok", detail: "", checkedAt: 2, models: ["gemini-4-carbon", "swe-2"], modelEfforts: { devin: { "gemini-4-carbon": ["low", "medium", "high"], "swe-2": ["medium", "high"] } } },
  });
  const agy = profile("agy", "agy", ["gemini-4-carbon", "gpt-oss-120b"], true, 10, {
    check: { state: "ok", detail: "", checkedAt: 2, models: ["gemini-4-carbon", "gpt-oss-120b"], modelEfforts: { agy: { "gemini-4-carbon": ["low", "medium", "high"], "gpt-oss-120b": [] } } },
  });
  const { host, core } = await started({ ...base(), "GET /overview": { ...overview, profiles: [dev, agy] } });
  try {
    const ui = core.connect();
    subscribe(core, ui, 1, { topic: "pick", station: "ws/st", of: "new" });
    subscribe(core, ui, 2, { topic: "newChat", scope: "ws" });
    await host.settle();
    const values = new Map();
    apply(host, values);
    const opt = (m: string) => v(values, 1).options.find((o: J) => o.model === m);
    assert.equal(v(values, 1).showRuntime, true);
    assert.equal(v(values, 2).pick.showRuntime, true);
    assert.deepEqual(opt("gemini-4-carbon").runtimes, ["devin", "agy"]);
    assert.equal(opt("gpt-oss-120b").usualText, "AGY");
    assert.equal(opt("swe-2").usualText, "Devin");
    // Switch away to swe-2 so gemini-4-carbon is unrun in the list: shows "Devin · AGY"
    await ask(host, core, ui, 3, "pick.save", { station: "ws/st", of: "new", model: "swe-2", runtime: "devin", effort: "high" });
    apply(host, values);
    assert.equal(opt("gemini-4-carbon").usualText, "Devin · AGY");
    // Save gemini-4-carbon on agy + high, then view it from swe-2: shows "AGY / Devin · 高"
    await ask(host, core, ui, 4, "pick.save", { station: "ws/st", of: "new", model: "gemini-4-carbon", runtime: "agy", effort: "high" });
    await ask(host, core, ui, 5, "pick.save", { station: "ws/st", of: "new", model: "swe-2", runtime: "devin", effort: "high" });
    apply(host, values);
    assert.equal(opt("gemini-4-carbon").usualText, "AGY / Devin · 高");
  } finally {
    core.close();
  }
});

test("the_model_control_lists_every_starred_model_apart_from_the_configurations_used_most_and_every_model_by_its_maker", async () => {
  const { host, core } = await choosing();
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "pick", station: "ws/st", of: "new" });
  await host.settle();
  const values = new Map();
  apply(host, values);
  const option = (model: string) => v(values, 1).options.find((o: J) => o.model === model);
  // none starred yet: those the profiles named, ticked on before (a station of before `named` says what it ran: those
  // ticked on)
  assert.deepEqual(v(values, 1).liked, ["claude-opus-5-5", "claude-sonnet-5", "gpt-6-astra"], "those ticked on before");
  await ask(host, core, ui, 9, "pick.like", { station: "ws/st", of: "new", model: "claude-sonnet-5", liked: false });
  await ask(host, core, ui, 10, "pick.like", { station: "ws/st", of: "new", model: "claude-opus-5-5", liked: false });
  await ask(host, core, ui, 11, "pick.like", { station: "ws/st", of: "new", model: "gpt-6-astra", liked: false });
  apply(host, values);
  assert.deepEqual(v(values, 1).liked, [], "once changed, as changed");
  // the makers of its models, in their models' order, each with how many
  assert.deepEqual(v(values, 1).makers.map((k: J) => [k.id, k.title, k.count]), [["anthropic", "Anthropic", 2], ["openai", "OpenAI", 1]]);
  // starred, in the order starred
  await ask(host, core, ui, 2, "pick.like", { station: "ws/st", of: "new", model: "claude-sonnet-5", liked: true });
  await ask(host, core, ui, 3, "pick.like", { station: "ws/st", of: "new", model: "gpt-6-astra", liked: true });
  apply(host, values);
  assert.deepEqual(v(values, 1).liked, ["claude-sonnet-5", "gpt-6-astra"]);
  assert.equal(option("gpt-6-astra").liked, true);
  assert.equal(option("claude-opus-5-5").liked, false);
  // a starred model's configuration among those used most, and the model still among the starred: the two apart
  core.inner.choose.used("ws/st", { model: "gpt-6-astra", runtime: "codex", effort: null });
  await host.settle();
  apply(host, values);
  assert.deepEqual(v(values, 1).combos.map((c: J) => [c.model, c.runtime, c.effort ?? null]), [["gpt-6-astra", "codex", null]]);
  assert.deepEqual(v(values, 1).liked, ["claude-sonnet-5", "gpt-6-astra"]);
  // unstarred: gone from the starred, its configuration where it was
  await ask(host, core, ui, 4, "pick.like", { station: "ws/st", of: "new", model: "gpt-6-astra", liked: false });
  apply(host, values);
  assert.deepEqual(v(values, 1).liked, ["claude-sonnet-5"]);
  assert.deepEqual(v(values, 1).combos.map((c: J) => c.model), ["gpt-6-astra"]);
  assert.equal(option("gpt-6-astra").liked, false);
  core.close();
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
  // (how hard it thinks, the account kept to and who could run it are the core's own value's: the page's model control
  // says them, `pick`)
  const own = (c: Core) => c.inner.store.get(topic) as J;
  assert.deepEqual([n.kept, n.station.id], ["st", "st"]);
  assert.deepEqual([n.model.model, n.runtime, own(core).effort], ["claude-sonnet-5", "claude", "low"]);
  assert.deepEqual([n.waiting, n.blocked ?? null, own(core).pickAccount], [false, null, false]);
  assert.deepEqual([n.effort, n.pickAccount, n.accounts], [undefined, undefined, undefined], "not sent");
  // Its unchecked profile is checked, once.
  assert.equal(stationPosted(host, "/profiles/p1/check").length, 1);
  assert.equal(stationPosted(host, "/profiles/p2/check").length, 0);
  // An account kept to that does not run the model gives way to the station's pick.
  await ask(host, core, ui, 3, "newChat.pick", { scope: "ws", model: "claude-opus-5-5", profile: "p3" });
  apply(host, values);
  n = own(core);
  assert.deepEqual([n.model.model, n.effort, n.profile ?? null], ["claude-opus-5-5", "low", null]);
  assert.equal(n.accounts.length, 2);
  assert.equal(n.pickAccount, true);
  assert.deepEqual(n.accounts[0].quotaLine, { text: "5 小时 90%" });
  assert.deepEqual(n.accounts[1].quotaLine, { text: "5 小时剩余 20%", level: "amber" });
  // A model on another runtime takes it, and its default depth.
  await ask(host, core, ui, 4, "newChat.pick", { scope: "ws", model: "gpt-6-astra" });
  apply(host, values);
  assert.deepEqual([v(values, 2).runtime, own(core).effort ?? null], ["codex", null]);
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
  assert.deepEqual([v(values, 2).model.model, own(again).profile], ["claude-opus-5-5", "p2"]);
  // Kept to an account running low: the control names it, amber (that it is not the station's pick the core's own).
  assert.deepEqual(v(values, 5).account, { text: "p2@x.com", level: "amber" });
  assert.equal((again.inner.store.get({ topic: "pick", station: "ws/st", of: "new" }) as J).account.auto, false);
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

test("a chat can switch runtime through its model control when its station supports it", async () => {
  const { host, core } = await choosing(false, false, null, true);
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "pick", station: "ws/st", of: "session:k1" });
  await host.settle();
  const values = new Map();
  apply(host, values);
  assert.equal(v(values, 1).runtimeFixed, false);
  assert.ok(v(values, 1).efforts.includes("high"), "the current runtime's default model keeps its effort choices");
  await ask(host, core, ui, 2, "pick.set", { station: "ws/st", of: "session:k1", model: "gpt-6-astra", runtime: "codex" });
  apply(host, values);
  assert.equal(v(values, 1).draft.runtime, "codex");
  await ask(host, core, ui, 3, "pick.save", { station: "ws/st", of: "session:k1" });
  assert.deepEqual(stationPosted(host, "/sessions/k1/settings"), [{ runtime: "codex", model: "gpt-6-astra", effort: null, profile: null }]);
  core.close();
});

test("a connect can switch runtime through its model control when its station supports it", async () => {
  const { host, core } = await choosing(false, false, null, true);
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "pick", station: "ws/st", of: "connect:c1" });
  subscribe(core, ui, 2, { topic: "connect", scope: "ws", station: "ws/st", id: "c1" });
  await host.settle();
  const values = new Map();
  apply(host, values);
  assert.equal(v(values, 1).runtimeFixed, false);
  assert.ok(v(values, 1).options.some((o: J) => o.model === "gpt-6-astra"), "the other runtime's models are offered");
  assert.equal(v(values, 2).runtimeChanges, true);
  await ask(host, core, ui, 3, "pick.set", { station: "ws/st", of: "connect:c1", model: "gpt-6-astra", runtime: "codex" });
  await ask(host, core, ui, 4, "pick.save", { station: "ws/st", of: "connect:c1" });
  const put = host.requests.filter((r) => r.method === "PUT" && r.url.endsWith("/admin/api/connects/c1")).map((r) => JSON.parse(new TextDecoder().decode(r.body!)));
  assert.deepEqual(put, [{ bind: { model: "gpt-6-astra", effort: "", profile: null, runtime: "codex" } }]);
  core.close();
});

test("a connect stays on its runtime on a station from before", async () => {
  const { host, core } = await choosing();
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "pick", station: "ws/st", of: "connect:c1" });
  await host.settle();
  const values = new Map();
  apply(host, values);
  assert.equal(v(values, 1).runtimeFixed, true);
  assert.ok(!v(values, 1).options.some((o: J) => o.model === "gpt-6-astra"));
  core.close();
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
  assert.ok(String(p.force).startsWith("所选账号「p2」无法运行"), JSON.stringify(p));
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
  // On p1, with p2 able to take it: picked again beside 全选; hidden when narrowed to 1 account.
  assert.equal(v(values, 1).repick, "重新分配");
  await ask(host, core, ui, 2, "pick.set", { station: "ws/st", of: "session:k1", model: "claude-opus-5-5", profile: "p1", effort: "high" });
  apply(host, values);
  assert.equal(v(values, 1).repick ?? null, null);
  await assert.rejects(ask(host, core, ui, 20, "pick.repick", { station: "ws/st", of: "session:k1" }));
  // Drafted back to 全选 with another depth: repick is offered again, and the depth stays drafted.
  await ask(host, core, ui, 21, "pick.set", { station: "ws/st", of: "session:k1", profile: null, profiles: null });
  apply(host, values);
  assert.equal(v(values, 1).repick, "重新分配");
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

test("model_control_checks_multiple_accounts_collapses_all_to_select_all_and_intersects_across_models", async () => {
  const s = { ...session("k1"), model: "claude-opus-5-5", profile: "p1" };
  const { host, core } = await started({
    ...base(),
    "GET /overview": {
      ...overview,
      sessionRuntimeChange: true,
      connectRuntimeChange: true,
      accountSubsets: true,
      connects: [{ id: "c1", name: "c1", kind: "slack", mode: "multi-session", requireMention: true, enabled: true, bind: { runtime: "claude", model: "claude-opus-5-5" }, connection: { state: "connected" }, slack: { appToken: "", botToken: "" }, sessions: 0 }],
      profiles: [
        profile("p1", "claude", ["claude-opus-5-5", "claude-sonnet-5"], true, 10),
        profile("p2", "claude", ["claude-opus-5-5"], true, 20),
        profile("p4", "claude", ["claude-opus-5-5"], true, 30),
        profile("p3", "codex", ["gpt-6-astra"], true, 0),
      ],
    },
    "GET /sessions": [s],
    "GET /sessions/k1": { session: s, threads: [], turns: [], jobs: [] },
    "POST /sessions": { key: "k-new", thread: { id: 99 } },
    "POST /sessions/k1/settings": { ok: true, profile: "p2" },
    "PUT /connects/c1": { ok: true },
  });
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "pick", station: "ws/st", of: "session:k1" });
  subscribe(core, ui, 2, { topic: "pick", station: "ws/st", of: "new" });
  subscribe(core, ui, 3, { topic: "pick", station: "ws/st", of: "connect:c1" });
  await host.settle();
  const values = new Map();
  apply(host, values);

  // Unrestricted starts as 全选, and marks the active account `current: true` in a chat.
  assert.equal(v(values, 1).who, "全选");
  assert.deepEqual(
    v(values, 1).accounts.map((a: J) => [a.id, a.current === true]),
    [["p1", true], ["p2", false], ["p4", false]],
  );

  // Checking 2 of 3 accounts keeps the subset `["p1", "p2"]` and saves `profiles` to the station.
  await ask(host, core, ui, 10, "pick.set", { station: "ws/st", of: "session:k1", profiles: ["p1", "p2"] });
  apply(host, values);
  assert.deepEqual([v(values, 1).draft.profiles, v(values, 1).draft.profile ?? null, v(values, 1).who], [["p1", "p2"], null, "2 个账号"]);
  assert.equal(v(values, 1).autoNote, "在已选账号间自动切换");
  // Repicking while 2 accounts are checked keeps the 2-account pool on the station.
  assert.deepEqual(await ask(host, core, ui, 11, "pick.repick", { station: "ws/st", of: "session:k1" }), { profile: "p2", said: "已改用 p2@x.com" });
  assert.deepEqual(stationPosted(host, "/sessions/k1/settings").at(-1), { profiles: ["p1", "p2"], repick: true });
  await ask(host, core, ui, 12, "pick.save", { station: "ws/st", of: "session:k1" });
  assert.deepEqual(stationPosted(host, "/sessions/k1/settings").at(-1), { model: "claude-opus-5-5", effort: null, profile: null, profiles: ["p1", "p2"] });

  // Checking all 3 of 3 accounts automatically collapses to unrestricted 全选 (`profiles: null`, `profile: null`).
  await ask(host, core, ui, 13, "pick.set", { station: "ws/st", of: "session:k1", profiles: ["p1", "p2", "p4"] });
  apply(host, values);
  assert.deepEqual([v(values, 1).draft.profiles ?? null, v(values, 1).draft.profile ?? null, v(values, 1).who, v(values, 1).changed], [null, null, "全选", false]);

  // Intersecting across models: ["p1", "p2"] moved to Sonnet (only p1 runs it) narrows cleanly to p1 without `dropped`.
  await ask(host, core, ui, 14, "pick.set", { station: "ws/st", of: "session:k1", profiles: ["p1", "p2"], model: "claude-sonnet-5" });
  apply(host, values);
  assert.deepEqual([v(values, 1).draft.profile, v(values, 1).draft.profiles ?? null, v(values, 1).dropped ?? null], ["p1", null, null]);

  // Zero intersection: ["p2", "p4"] moved to Sonnet drops back to unrestricted with warning.
  await ask(host, core, ui, 15, "pick.set", { station: "ws/st", of: "session:k1", profiles: ["p2", "p4"], model: "claude-sonnet-5" });
  apply(host, values);
  assert.deepEqual([v(values, 1).draft.profile ?? null, v(values, 1).draft.profiles ?? null, v(values, 1).whoLevel], [null, null, "amber"]);
  assert.ok(String(v(values, 1).dropped).includes("Sonnet 5"));

  // New chat & connect also persist and send multi-account subsets.
  await ask(host, core, ui, 16, "pick.save", { station: "ws/st", of: "new", model: "claude-opus-5-5", profiles: ["p1", "p4"] });
  apply(host, values);
  assert.equal(v(values, 2).account.text, "2 个账号");
  await ask(host, core, ui, 17, "newChat.create", { station: "ws/st" });
  await host.settle();
  assert.deepEqual(stationPosted(host, "/sessions").at(-1)?.profiles, ["p1", "p4"]);

  await ask(host, core, ui, 18, "pick.save", { station: "ws/st", of: "connect:c1", profiles: ["p2", "p4"] });
  const put = host.requests.filter((r) => r.method === "PUT" && r.url.endsWith("/admin/api/connects/c1")).map((r) => JSON.parse(new TextDecoder().decode(r.body!)));
  assert.deepEqual(put.at(-1), { bind: { model: "claude-opus-5-5", effort: "", profile: null, profiles: ["p2", "p4"] } });

  // Rapidly toggling to a subset and immediately back to 全选 while the first save is still in flight sends both updates.
  await ask(host, core, ui, 19, "pick.set", { station: "ws/st", of: "session:k1", open: true });
  call(core, ui, 30, "pick.save", { station: "ws/st", of: "session:k1", profiles: ["p1", "p2"] });
  call(core, ui, 31, "pick.save", { station: "ws/st", of: "session:k1", profiles: null, profile: null });
  await host.settle();
  assert.deepEqual(
    stationPosted(host, "/sessions/k1/settings").slice(-2),
    [
      { model: "claude-opus-5-5", effort: null, profile: null, profiles: ["p1", "p2"] },
      { model: "claude-opus-5-5", effort: null, profile: null },
    ],
  );

  core.close();
});

test("multi_account_guards_older_stations_and_saved_subset_repick_to_all", async () => {
  // 1) A session already saved on a subset `["p1", "p2"]`: drafting 全选 then calling `pick.repick` sends `profile: null` (not stale `["p1", "p2"]`).
  const subSession = { ...session("k1"), model: "claude-opus-5-5", profile: "p1", profilePinned: false, profiles: ["p1", "p2"] };
  const r1 = await started({
    ...base(),
    "GET /overview": {
      ...overview,
      sessionRuntimeChange: true,
      accountSubsets: true,
      profiles: [
        profile("p1", "claude", ["claude-opus-5-5"], true, 10),
        profile("p2", "claude", ["claude-opus-5-5"], true, 20),
        profile("p4", "claude", ["claude-opus-5-5"], true, 30),
      ],
    },
    "GET /sessions": [subSession],
    "GET /sessions/k1": { session: subSession, threads: [], turns: [], jobs: [] },
    "POST /sessions/k1/settings": { ok: true, profile: "p4" },
  });
  const ui1 = r1.core.connect();
  subscribe(r1.core, ui1, 1, { topic: "pick", station: "ws/st", of: "session:k1" });
  await r1.host.settle();
  const vals1 = new Map();
  apply(r1.host, vals1);
  assert.deepEqual(v(vals1, 1).value.profiles, ["p1", "p2"]);
  await ask(r1.host, r1.core, ui1, 2, "pick.set", { station: "ws/st", of: "session:k1", profiles: null, profile: null });
  assert.deepEqual(await ask(r1.host, r1.core, ui1, 3, "pick.repick", { station: "ws/st", of: "session:k1" }), { profile: "p4", said: "已改用 p4@x.com" });
  assert.deepEqual(stationPosted(r1.host, "/sessions/k1/settings").at(-1), { profile: null, repick: true });
  apply(r1.host, vals1);
  assert.equal(v(vals1, 1).who, "全选");
  r1.core.close();

  // 2) An older station (no `accountSubsets` in overview) rejects multi-account subset saves, reverts drafts, and clamps migrated newChat subsets to single-account pin so excluded accounts are never spent.
  const oldSession = { ...session("k1"), model: "claude-opus-5-5", profile: "p1" };
  const r2 = await started({
    ...base(),
    "GET /overview": {
      ...overview,
      sessionRuntimeChange: true,
      profiles: [
        profile("p1", "claude", ["claude-opus-5-5"], true, 10),
        profile("p2", "claude", ["claude-opus-5-5"], true, 20),
        profile("p4", "claude", ["claude-opus-5-5"], true, 30),
      ],
    },
    "GET /sessions": [oldSession],
    "GET /sessions/k1": { session: oldSession, threads: [], turns: [], jobs: [] },
    "POST /sessions": { key: "k-new", thread: { id: 99 } },
    "POST /sessions/k1/settings": { ok: true, profile: "p1" },
  });
  const ui2 = r2.core.connect();
  subscribe(r2.core, ui2, 1, { topic: "pick", station: "ws/st", of: "session:k1" });
  subscribe(r2.core, ui2, 2, { topic: "pick", station: "ws/st", of: "new" });
  subscribe(r2.core, ui2, 3, { topic: "newChat", scope: "ws" });
  await r2.host.settle();
  const vals2 = new Map();
  apply(r2.host, vals2);
  await assert.rejects(ask(r2.host, r2.core, ui2, 10, "pick.save", { station: "ws/st", of: "session:k1", profiles: ["p1", "p2"] }), /Station/);
  assert.deepEqual(stationPosted(r2.host, "/sessions/k1/settings"), []);
  apply(r2.host, vals2);
  assert.equal(v(vals2, 1).who, "全选");
  // Single-account pin (`全不选 -> 点一个`) still works on older stations, and `profiles: []` drafts 全不选 cleanly.
  await ask(r2.host, r2.core, ui2, 20, "pick.set", { station: "ws/st", of: "session:k1", profiles: [] });
  apply(r2.host, vals2);
  assert.deepEqual(
    [v(vals2, 1).draft.profiles, v(vals2, 1).who, v(vals2, 1).whoLevel, v(vals2, 1).autoNote, v(vals2, 1).repick ?? null, v(vals2, 1).changed, v(vals2, 1).accountText, v(vals2, 1).accountWarn],
    [[], "未选择", "amber", "请选择至少一个账号", null, false, "未选择", true],
  );
  // Saving with 0 accounts drafted is a no-op that preserves the 0-account draft without hitting the station.
  assert.deepEqual(await ask(r2.host, r2.core, ui2, 21, "pick.save", { station: "ws/st", of: "session:k1" }), { saved: false });
  assert.deepEqual(stationPosted(r2.host, "/sessions/k1/settings"), []);
  apply(r2.host, vals2);
  assert.deepEqual(v(vals2, 1).draft.profiles, []);
  // Closing the account sub-panel (`open: false`) reverts an incomplete 0-account draft back to the saved accounts.
  await ask(r2.host, r2.core, ui2, 22, "pick.set", { station: "ws/st", of: "session:k1", open: false });
  apply(r2.host, vals2);
  assert.equal(v(vals2, 1).who, "全选");
  assert.equal(v(vals2, 1).draft.profiles, undefined);
  // Re-entering 全不选 (`profiles: []`) and tapping one account (`profiles: ["p2"]`) pins `p2` immediately.
  await ask(r2.host, r2.core, ui2, 23, "pick.set", { station: "ws/st", of: "session:k1", profiles: [] });
  await ask(r2.host, r2.core, ui2, 11, "pick.save", { station: "ws/st", of: "session:k1", profiles: ["p2"] });
  assert.deepEqual(stationPosted(r2.host, "/sessions/k1/settings"), [{ model: "claude-opus-5-5", effort: null, profile: "p2" }]);
  // Migrated local multi-account subset on an older station clamps to the first selected account (`p1`) instead of unrestricted pool.
  await ask(r2.host, r2.core, ui2, 12, "newChat.migrate", { choices: { st: { model: "claude-opus-5-5", runtime: "claude", profiles: ["p1", "p2"] } } });
  apply(r2.host, vals2);
  assert.equal(v(vals2, 2).account.text, "p1@x.com");
  assert.equal((r2.core.inner.store.get({ topic: "newChat", scope: "ws" }) as J).profile, "p1");
  assert.equal(v(vals2, 3).pick.account.text, "p1@x.com");
  await ask(r2.host, r2.core, ui2, 13, "newChat.create", { station: "ws/st" });
  await r2.host.settle();
  const created = stationPosted(r2.host, "/sessions").at(-1);
  assert.equal(created?.profile, "p1");
  assert.equal(created?.profiles, undefined);
  r2.core.close();
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
  const { host, core } = await started({ ...base(), ...chatsOf([row("a", "别的", 3), row("b", "登录页", 2), row("c", "修登录", 1)]) });
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "chatSearch", scope: "ws", query: "登录", exclude: "c" });
  await host.settle();
  const values = new Map();
  apply(host, values);
  assert.deepEqual(v(values, 1).items.map((i: J) => i.id), ["b"]);
  assert.equal(v(values, 1).items[0].station, "ws/st");
  core.close();
});

// The owner found the `@` menu's order useless: the pinned chats always first, the rest by whichever an agent last
// touched (the user, 2026-11-10).
test("the_at_menu_lists_the_chats_opened_here_latest_first_then_the_rest_by_when_they_were_last_active_pinned_or_not", async () => {
  const row = (id: string, title: string, at: number) => ({ id, session: id, thread: null, title, agents: [], last: null, unread: false, mine: true, lastActiveAt: at, connect: null, origin: null });
  const answers: J = { ...base(), ...chatsOf([row("p", "置顶的部署", 1), row("a", "部署 甲", 2), row("b", "部署 乙", 4), row("c", "别的", 3)]) };
  answers["GET /chats?marks=1"] = { ...answers["GET /chats?marks=1"], pins: { p: 9 } };
  const { host, core } = await started(answers);
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "chatSearch", scope: "ws", query: "", limit: 8 });
  subscribe(core, ui, 2, { topic: "chatSearch", scope: "ws", query: "部署", limit: 8 });
  subscribe(core, ui, 3, { topic: "chats", scope: "ws" });
  await host.settle();
  const values = new Map();
  apply(host, values);
  const ids = (n: number) => v(values, n).items.map((i: J) => i.id);
  // The pinned chat is pinned in the list, and in the menu as any other.
  assert.deepEqual(v(values, 3).days[0].items.map((i: J) => i.id), ["p"]);
  assert.deepEqual(ids(1), ["b", "c", "a", "p"]);
  assert.deepEqual(ids(2), ["b", "a", "p"]);
  // Opened: first, the latest first; the menu made again.
  call(core, ui, 4, "client.focus", { visible: true, chat: { station: "ws/st", session: "a" } });
  await host.settle();
  apply(host, values);
  assert.deepEqual(ids(1), ["a", "b", "c", "p"]);
  call(core, ui, 5, "client.focus", { chat: { station: "ws/st", session: "p" } });
  await host.settle();
  apply(host, values);
  assert.deepEqual(ids(1), ["p", "a", "b", "c"]);
  assert.deepEqual(ids(2), ["p", "a", "b"]);
  // Kept with the workspace, the latest last.
  assert.deepEqual(core.inner.data.record("chat_ref", "opened:ws"), [["ws/st", "a"], ["ws/st", "p"]]);
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
      const asked = `${req.method} ${req.url.replace("https://stillfail.test/admin/api", "")}`;
      const of = chatsOf(req.headers.some(([k, v]) => k === AT && v === "st2") ? [row("b", "部署 mini", 2)] : [row("a", "部署 studio", 3), row("c", "写在这里", 1)]);
      return asked in of ? of[asked] : undefined;
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
    ...chatsOf([{ ...row("a", 7, "别的"), last: { seq: 4 } }, { ...row("b", 8, "登录页"), last: { seq: 1 } }]),
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
  const coming = (n: number, text: string) => said(n, { author: "peer/chat:c-9", text: `来自 [备份](https://x/o/w/s/b)：\n\n${text}`, letter: { way: "in", ...backups } });
  const going = (n: number, text: string) => said(n, { text: `发给 [备份](https://x/o/w/s/b)：\n\n${text}`, letter: { way: "out", ...backups } });
  const { host, core } = await started({
    ...base(),
    "GET /threads": [{ ...threadView(7, 8), letters: 4 }],
    "GET /threads/7/entries?limit=50": { first: 1, last: 8, entries: [
      said(1, { authorKind: "person", author: "me@x", text: "改备份" }), coming(2, "脚本放好了"), going(3, "已替换"), said(4),
      // From a station before letters were marked: known by its heading.
      said(5, { author: "peer/chat:c-8", text: "来自 [部署](https://x/o/w/s/d)：\n\n部署好了" }),
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

test("letters_kept_in_their_own_log_are_no_entries_of_the_chat_and_its_letters_page_has_them_with_those_from_before_it", async () => {
  // The user, 2026-10-31: a chat its agent and its supervisor wrote each other a page of letters in opened on nothing it
  // shows ("早他妈说了要分开"). Letters are kept in their own log (GET /threads/:id/letters, numbered from 1 in it):
  // the chat's entries are what it shows, its latest page its latest messages.
  const said = (n: number, over: J = {}) => ({ thread: 7, n, kind: "message", ts: `${n}.0`, authorKind: "agent", author: "k1", authorName: null, text: "好", at: n * 10, ...over });
  const backups = { title: "备份", link: "https://x/o/w/s/b" };
  const coming = (n: number, at: number, text: string) => ({ ...said(n, { author: "peer/chat:c-9", text: `来自 [备份](https://x/o/w/s/b)：\n\n${text}`, letter: { way: "in", ...backups } }), ts: `l${n}`, at });
  const going = (n: number, at: number, text: string) => ({ ...said(n, { text: `发给 [备份](https://x/o/w/s/b)：\n\n${text}`, letter: { way: "out", ...backups } }), ts: `l${n}`, at });
  const s = await started({
    ...base(),
    "GET /threads": [{ ...threadView(7, 3), letters: 3, lettersLast: 2 }],
    // One from before their own log, among its entries; the chat's messages around it.
    "GET /threads/7/entries?limit=50": { first: 1, last: 3, entries: [said(1, { authorKind: "person", author: "me@x", text: "改备份" }), coming(2, 20, "旧的一封"), said(3)] },
    "GET /threads/7/letters?from=1&to=2": { last: 2, letters: [going(1, 25, "脚本放好了吗"), coming(2, 35, "放好了")] },
  });
  const { host, core } = s;
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "chat", station: "ws/st", thread: 7 });
  subscribe(core, ui, 2, { topic: "chatLetters", station: "ws/st", thread: 7 });
  await host.settle();
  apply(host, values);
  const chat = v(values, 1);
  assert.deepEqual(chat.messages.map((m: J) => m.seq), [1, 3]);
  assert.equal(chat.letters, 3);
  // Its letters: those from before their log and those of it, in the order written.
  const page = () => v(values, 2).chats.map((c: J) => [c.title, c.letters.map((m: J) => [m.way, m.text])]);
  assert.equal(v(values, 2).whole, true);
  assert.deepEqual(page(), [["备份", [["in", "旧的一封"], ["out", "脚本放好了吗"], ["in", "放好了"]]]]);
  // One told as it is kept: on the page, nothing of it in the chat.
  s.push("letters", { id: 7, letters: [going(3, 45, "谢谢")] });
  await host.settle();
  apply(host, values);
  assert.deepEqual(page(), [["备份", [["in", "旧的一封"], ["out", "脚本放好了吗"], ["in", "放好了"], ["out", "谢谢"]]]]);
  assert.deepEqual(v(values, 1).messages.map((m: J) => m.seq), [1, 3]);
  assert.equal(v(values, 1).letters, 4);
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
    if (path === "/sessions/k1?turns=0&jobs=now")
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
  // Restarting first, then alive, what is over left out; each with its dot and its line; the heads' notes.
  const jobs = v(values, 1);
  assert.deepEqual(jobs.jobs.map((j: J) => j.id), ["s", "w"]);
  assert.deepEqual([jobs.alarm, jobs.servicesNote, jobs.jobsNote], ["restart", "1 个在重启", "1 个运行中"]);
  const w = jobs.jobs[1];
  assert.deepEqual([w.tone, w.meta[0].text, w.meta[1].text, w.detail], ["live", "CI 还在跑", " · 2 分钟前", "运行中 · 1 分钟 · 1 条通知"]);
  assert.equal(jobs.jobs[0].meta[0].text, "正在重启");
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
      return { key: "chat:c-1", thread: { ...threadView(9, 0), createdBy: "a@x.com", sessions: [{ thread: 9, session: "chat:c-1", connect: "ember", joinedAt: 1 }] } };
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
  assert.deepEqual([v(values, 2).pending, v(values, 2).key], [false, "chat:c-1"]);
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
  const made = { ...threadView(9, 0), createdBy: "a@x.com", sessions: [{ thread: 9, session: "chat:c-1", connect: "ember", joinedAt: 1 }] };
  const atRest = session("chat:c-1");
  const working = { ...atRest, process: "running", running: true, turns: 1, lastTurn: { id: "t1", kind: "input", startedAt: 5, endedAt: null } };
  const row = (id: string, session: string, thread: number, agents: J[]) => ({ id, session, thread, title: "新对话", agents, last: null, unread: false, mine: true, lastActiveAt: thread, connect: null, origin: null });
  const marks = { card: {}, need: {}, answered: {}, suggested: [], verdicts: {}, reviews: false, kept: [], hidden: [], pins: {}, openers: {}, opened: {}, shares: {}, clientKeys: {}, teams: {}, selves: [] };
  const answers: J = { ...base(), "GET /chats": [row("7", "k1", 7, [])], "GET /chats?marks=1": marks };
  const s = await started(answers);
  const { host, core } = s;
  // A station that keeps the marks: the sidebar made here of the summaries held.
  s.push("made", { rows: true, marks: true });
  await host.settle();
  // The station as it is at each moment: what a read is answered with is what it had as it was asked.
  const now = (agent: J) => {
    answers["GET /sessions"] = [session("k1"), agent];
    answers["GET /sessions/chat%3Ac-1"] = { session: agent, threads: [], turns: agent.lastTurn ? [agent.lastTurn] : [], jobs: [] };
    answers["GET /chats"] = [row("7", "k1", 7, []), row("9", "chat:c-1", 9, [agent])];
  };
  answers["GET /threads/9"] = { ...made, last: 1 };
  stationReplies(host, (req) => {
    const path = req.url.replace("https://stillfail.test/admin/api", "");
    if (req.method === "POST" && path === "/sessions") return { key: "chat:c-1", thread: made };
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
  await host.settle();
  subscribe(core, ui, 4, { topic: "chat", station: "ws/st", thread: 9 });
  await host.settle();
  // The lists come, as the station had them before it began.
  for (const r of release) r();
  await host.settle();
  apply(host, values);
  const item = v(values, 1).days.flatMap((d: J) => d.items).find((i: J) => i.thread === 9);
  assert.deepEqual([v(values, 4).agents[0].status, item?.state], ["running", "run"]);
  core.close();
});

test("what_waited_for_a_new_chat_goes_as_soon_as_it_is_made_not_after_the_lists_are_read_again", async () => {
  const { host, core } = await started();
  stationReplies(host, (req) => {
    const path = req.url.replace("https://stillfail.test/admin/api", "");
    if (req.method === "POST" && path === "/sessions") return { key: "chat:c-1", thread: { ...threadView(9, 0), createdBy: "a@x.com", sessions: [{ thread: 9, session: "chat:c-1", connect: "ember", joinedAt: 1 }] } };
    if (req.method === "POST" && path === "/threads/9/messages") return { n: 1 };
    return undefined;
  });
  const ui = core.connect();
  // A slow link: what the new chat changes (its lists) is not read back yet.
  const release = [host.hold("/admin/api/chats?marks=1")];
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
  const row = (id: string, thread: number) => ({ id, session: id, thread, title: id, agents: [], last: { seq: 1 }, unread: false, mine: true, lastActiveAt: 15 - thread, connect: null, origin: null });
  const { host, core } = await started({ ...base(), ...chatsOf([row("k1", 7), row("k2", 8)]) });
  stationReplies(host, (req) => {
    const path = req.url.replace("https://stillfail.test/admin/api", "");
    const left = chatsOf([row("k2", 8)]);
    if (req.method === "GET" && archived && `GET ${path}` in left) return left[`GET ${path}`];
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
  // Archived: gone at once, and the station takes it.
  refused = false;
  release = host.hold("/threads/7/archive");
  archive(3);
  await host.settle();
  answersOf(host, values);
  assert.deepEqual(ids(), ["k2"]);
  release();
  await host.settle();
  assert.ok("ok" in answersOf(host, values).get(3)!);
  assert.ok(archived);
  core.close();
});

test("undoing an archive keeps the row visible while the station and its list catch up", async () => {
  let archived = false;
  const row = (id: string, thread: number) => ({ id, session: id, thread, title: id, agents: [], last: { seq: 1 }, unread: false, mine: true, lastActiveAt: 15 - thread, connect: null, origin: null });
  const rows = [row("k1", 7), row("k2", 8)];
  const { host, core } = await started({ ...base(), ...chatsOf(rows) });
  const writes: string[] = [];
  stationReplies(host, (req) => {
    const path = req.url.replace("https://stillfail.test/admin/api", "");
    if (req.method === "GET" && `GET ${path}` in chatsOf(rows)) return chatsOf(archived ? rows.slice(1) : rows)[`GET ${path}`];
    if (path === "/threads/7/archive" && (req.method === "POST" || req.method === "DELETE")) {
      writes.push(req.method);
      archived = req.method === "POST";
      return { ok: true };
    }
    return undefined;
  });
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "chats", scope: "ws" });
  subscribe(core, ui, 100, { topic: "chats", scope: "ws", mine: true });
  await host.settle();
  answersOf(host, values);
  const ids = (n = 1) => v(values, n).days.flatMap((d: J) => d.items.map((i: J) => i.id));
  const visibleThroughout = () => {
    for (const [, m] of host.takeEmitted()) {
      const x = m as J;
      if ("value" in x) values.set(x.id, x.value);
      else if ("delta" in x) values.set(x.id, applyOps(values.get(x.id), x.delta));
      else continue;
      if (x.id === 1 || x.id === 100) assert.deepEqual(ids(x.id), ["k1", "k2"]);
    }
  };
  const archive = (id: number, on: boolean) => call(core, ui, id, "chat.archive", { station: "ws/st", thread: 7, session: "k1", archived: on });
  // Undo while the archive request is still waiting: the latest choice shows and goes to the station second.
  const releaseArchive = host.hold("/threads/7/archive");
  archive(2, true);
  await host.settle();
  answersOf(host, values);
  assert.deepEqual(ids(), ["k2"]);
  const releaseUndo = host.hold("/threads/7/archive");
  archive(3, false);
  await host.settle();
  visibleThroughout();
  assert.deepEqual(ids(), ["k1", "k2"]);
  assert.deepEqual(writes, ["POST"]);
  releaseArchive();
  await host.settle();
  visibleThroughout();
  assert.deepEqual(writes, ["POST", "DELETE"]);
  assert.deepEqual(ids(), ["k1", "k2"]);
  releaseUndo();
  await host.settle();
  visibleThroughout();
  assert.equal(archived, false);
  // Undo after the archive reached the list, with the restore request held: the row still comes back at once.
  archive(4, true);
  await host.settle();
  await host.settle();
  answersOf(host, values);
  assert.deepEqual(ids(), ["k2"]);
  const releaseRestore = host.hold("/threads/7/archive");
  archive(5, false);
  await host.settle();
  visibleThroughout();
  assert.deepEqual(ids(), ["k1", "k2"]);
  releaseRestore();
  await host.settle();
  await host.settle();
  visibleThroughout();
  assert.deepEqual(ids(), ["k1", "k2"]);
  core.close();
});

test("a refused restore rolls back its row and can be tried again, with or without a thread", async () => {
  for (const thread of [7, null]) {
    let archived = false;
    let refuse = true;
    const row = { id: "k1", session: "k1", thread, title: "k1", agents: [], last: { seq: 1 }, unread: false, mine: true, lastActiveAt: 8, connect: null, origin: null };
    const other = { ...row, id: "k2", session: "k2", thread: 8, lastActiveAt: 7 };
    const rows = [row, other];
    const { host, core } = await started({ ...base(), ...chatsOf(rows) });
    const path = thread === null ? "/sessions/k1/archive" : "/threads/7/archive";
    stationReplies(host, (req) => {
      const at = req.url.replace("https://stillfail.test/admin/api", "");
      if (req.method === "GET" && `GET ${at}` in chatsOf(rows)) return chatsOf(archived ? [other] : rows)[`GET ${at}`];
      if (at === path && req.method === "POST") {
        archived = true;
        return { ok: true };
      }
      if (at === path && req.method === "DELETE") {
        if (refuse) return status(409, { error: "refused" });
        archived = false;
        return { ok: true };
      }
      return undefined;
    });
    const ui = core.connect();
    const values = new Map();
    subscribe(core, ui, 1, { topic: "chats", scope: "ws" });
    await host.settle();
    answersOf(host, values);
    const ids = () => v(values, 1).days.flatMap((d: J) => d.items.map((i: J) => i.id));
    const ask = (id: number, on: boolean) => call(core, ui, id, "chat.archive", { station: "ws/st", session: "k1", ...(thread === null ? {} : { thread }), archived: on });
    ask(2, true);
    await host.settle();
    answersOf(host, values);
    assert.deepEqual(ids(), ["k2"]);
    const release = host.hold(path);
    ask(3, false);
    await host.settle();
    answersOf(host, values);
    assert.deepEqual(ids(), ["k1", "k2"]);
    release();
    await host.settle();
    assert.ok("err" in answersOf(host, values).get(3)!);
    assert.deepEqual(ids(), ["k2"]);
    refuse = false;
    ask(4, false);
    await host.settle();
    assert.ok("ok" in answersOf(host, values).get(4)!);
    assert.deepEqual(ids().sort(), ["k1", "k2"]);
    core.close();
  }
});

test("undo holds the row while a station's shared-list events catch up", async () => {
  const shared = (id: string, thread: number, at: number) => ({
    id, session: id, thread, agents: [{ key: id, runtime: "claude" }], lastActiveAt: at, ws: null,
    named: { thread: { surface: "ember", title: id }, firstText: null, channelName: null }, mineOf: [], said: null,
  });
  const rows = [shared("k1", 7, 8), shared("k2", 8, 7)];
  const { host, core, push } = await started({ ...base(), "GET /chats?shared=1": rows }, 0, undefined, (s) => { s.gate.shared = true; });
  stationReplies(host, (req) => {
    if (req.url.endsWith("/threads/7/archive")) return { ok: true };
    if (req.url.includes("/chats?shared=1&session=k1")) return { rows: [rows[0]], scope: ["k1"] };
    return undefined;
  });
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "chats", scope: "ws" });
  await host.settle();
  answersOf(host, values);
  const ids = () => v(values, 1).days.flatMap((d: J) => d.items.map((i: J) => i.id));
  assert.deepEqual(ids(), ["k1", "k2"]);
  call(core, ui, 2, "chat.archive", { station: "ws/st", thread: 7, session: "k1", archived: true });
  await host.settle();
  push("chat-shared-removed", { id: "k1" });
  await host.settle();
  answersOf(host, values);
  assert.deepEqual(ids(), ["k2"]);
  const release = host.hold("/threads/7/archive");
  call(core, ui, 3, "chat.archive", { station: "ws/st", thread: 7, session: "k1", archived: false });
  await host.settle();
  answersOf(host, values);
  assert.deepEqual(ids(), ["k1", "k2"]);
  // Another row changing must not settle the restore while its own row is still missing.
  push("chat-shared", { ...rows[1], named: { ...rows[1].named, thread: { surface: "ember", title: "k2 changed" } } });
  await host.settle();
  answersOf(host, values);
  assert.deepEqual(ids(), ["k1", "k2"]);
  release();
  await host.settle();
  answersOf(host, values);
  assert.deepEqual(ids(), ["k1", "k2"]);
  push("chat-shared", { ...rows[1], named: { ...rows[1].named, thread: { surface: "ember", title: "k2 changed again" } } });
  await host.settle();
  answersOf(host, values);
  assert.deepEqual(ids(), ["k1", "k2"]);
  push("chat-shared", rows[0]);
  await host.settle();
  answersOf(host, values);
  assert.deepEqual(ids(), ["k1", "k2"]);
  assert.equal(core.inner.views.local.rowsQuiet("ws/st"), true);
  core.close();
});

test("a restored chat removed again before it is listed does not remain in the list", async () => {
  const shared = (id: string, thread: number, at: number) => ({
    id, session: id, thread, agents: [{ key: id, runtime: "claude" }], lastActiveAt: at, ws: null,
    named: { thread: { surface: "ember", title: id }, firstText: null, channelName: null }, mineOf: [], said: null,
  });
  const rows = [shared("k1", 7, 8), shared("k2", 8, 7)];
  const { host, core, push } = await started({ ...base(), "GET /chats?shared=1": rows }, 0, undefined, (s) => { s.gate.shared = true; });
  let visible = true;
  stationReplies(host, (req) => {
    if (req.url.endsWith("/threads/7/archive")) return { ok: true };
    if (req.url.includes("/chats?shared=1&session=k1")) return { rows: visible ? [rows[0]] : [], scope: ["k1"] };
    return undefined;
  });
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "chats", scope: "ws" });
  await host.settle();
  answersOf(host, values);
  const ids = () => v(values, 1).days.flatMap((d: J) => d.items.map((i: J) => i.id));
  call(core, ui, 2, "chat.archive", { station: "ws/st", thread: 7, session: "k1", archived: true });
  await host.settle();
  push("chat-shared-removed", { id: "k1" });
  await host.settle();
  answersOf(host, values);
  assert.deepEqual(ids(), ["k2"]);
  call(core, ui, 3, "chat.archive", { station: "ws/st", thread: 7, session: "k1", archived: false });
  await host.settle();
  answersOf(host, values);
  assert.deepEqual(ids(), ["k1", "k2"]);
  visible = false;
  push("chat-shared-removed", { id: "k1" });
  push("chat-shared", { ...rows[1], named: { ...rows[1].named, thread: { surface: "ember", title: "k2 changed" } } });
  await host.settle();
  answersOf(host, values);
  assert.deepEqual(ids(), ["k2"]);
  assert.equal(core.inner.views.local.rowsQuiet("ws/st"), true);
  core.close();
});

test("a late removal from the original archive does not end a completed undo", async () => {
  const row = {
    id: "k1", session: "k1", thread: 7, agents: [{ key: "k1", runtime: "claude" }], lastActiveAt: 8, ws: null,
    named: { thread: { surface: "ember", title: "k1" }, firstText: null, channelName: null }, mineOf: [], said: null,
  };
  const { host, core, push } = await started({ ...base(), "GET /chats?shared=1": [row] }, 0, undefined, (s) => { s.gate.shared = true; });
  stationReplies(host, (req) => {
    if (req.url.endsWith("/threads/7/archive")) return { ok: true };
    if (req.url.includes("/chats?shared=1&session=k1")) return { rows: [row], scope: ["k1"] };
    return undefined;
  });
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "chats", scope: "ws" });
  await host.settle();
  answersOf(host, values);
  const ids = () => v(values, 1).days.flatMap((d: J) => d.items.map((i: J) => i.id));
  call(core, ui, 2, "chat.archive", { station: "ws/st", thread: 7, session: "k1", archived: true });
  await host.settle();
  call(core, ui, 3, "chat.archive", { station: "ws/st", thread: 7, session: "k1", archived: false });
  await host.settle();
  answersOf(host, values);
  assert.deepEqual(ids(), ["k1"]);
  push("chat-shared-removed", { id: "k1" });
  await host.settle();
  answersOf(host, values);
  assert.deepEqual(ids(), ["k1"], "the first, delayed removal is from the archive, not proof the restore was reversed");
  push("chat-shared", row);
  await host.settle();
  answersOf(host, values);
  assert.deepEqual(ids(), ["k1"]);
  core.close();
});

test("a rearchive coalesced before the shared list can tell it settles the restore", async () => {
  const row = {
    id: "k1", session: "k1", thread: 7, agents: [{ key: "k1", runtime: "claude" }], lastActiveAt: 8, ws: null,
    named: { thread: { surface: "ember", title: "k1" }, firstText: null, channelName: null }, mineOf: [], said: null,
  };
  const { host, core, push } = await started({ ...base(), "GET /chats?shared=1": [row] }, 0, undefined, (s) => { s.gate.shared = true; });
  let visible = true;
  stationReplies(host, (req) => {
    if (req.url.endsWith("/threads/7/archive")) return { ok: true };
    if (req.url.includes("/chats?shared=1&session=k1")) return { rows: visible ? [row] : [], scope: ["k1"] };
    return undefined;
  });
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "chats", scope: "ws" });
  await host.settle();
  call(core, ui, 2, "chat.archive", { station: "ws/st", thread: 7, session: "k1", archived: true });
  await host.settle();
  push("chat-shared-removed", { id: "k1" });
  await host.settle();
  call(core, ui, 3, "chat.archive", { station: "ws/st", thread: 7, session: "k1", archived: false });
  await host.settle();
  answersOf(host, values);
  assert.equal(v(values, 1).days.flatMap((d: J) => d.items).length, 1);
  // The station did not tell a shared removal: it coalesced restore and rearchive while the row was already absent.
  visible = false;
  push("chat-changed", { thread: 7 });
  await host.settle();
  answersOf(host, values);
  assert.equal(v(values, 1).days.flatMap((d: J) => d.items).length, 0);
  assert.equal(core.inner.views.local.rowsQuiet("ws/st"), true);
  core.close();
});

test("an unrelated row cannot settle an undo before a delayed archive removal", async () => {
  const shared = (id: string, thread: number) => ({
    id, session: id, thread, agents: [{ key: id, runtime: "claude" }], lastActiveAt: 8, ws: null,
    named: { thread: { surface: "ember", title: id }, firstText: null, channelName: null }, mineOf: [], said: null,
  });
  const row = shared("k1", 7);
  const other = shared("k2", 8);
  const { host, core, push } = await started({ ...base(), "GET /chats?shared=1": [row, other] }, 0, undefined, (s) => { s.gate.shared = true; });
  stationReplies(host, (req) => {
    if (req.url.endsWith("/threads/7/archive")) return { ok: true };
    if (req.url.includes("/chats?shared=1&session=k1")) return { rows: [row], scope: ["k1"] };
    return undefined;
  });
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "chats", scope: "ws" });
  await host.settle();
  call(core, ui, 2, "chat.archive", { station: "ws/st", thread: 7, session: "k1", archived: true });
  await host.settle();
  call(core, ui, 3, "chat.archive", { station: "ws/st", thread: 7, session: "k1", archived: false });
  await host.settle();
  answersOf(host, values);
  assert.equal(core.inner.views.local.rowsQuiet("ws/st"), true, "coalesced archive and restore leave no active overlay");
  push("chat-shared", { ...other, lastActiveAt: 9 });
  await host.settle();
  answersOf(host, values);
  push("chat-shared-removed", { id: "k1" });
  await host.settle();
  answersOf(host, values);
  assert.ok(v(values, 1).days.flatMap((d: J) => d.items).some((r: J) => r.id === "k1"));
  push("chat-shared", row);
  await host.settle();
  core.close();
});

test("a newer tell wins over a restore read already on its way", async () => {
  const row = {
    id: "k1", session: "k1", thread: 7, agents: [{ key: "k1", runtime: "claude" }], lastActiveAt: 8, ws: null,
    named: { thread: { surface: "ember", title: "k1" }, firstText: null, channelName: null }, mineOf: [], said: null,
  };
  const { host, core, push } = await started({ ...base(), "GET /chats?shared=1": [row] }, 0, undefined, (s) => { s.gate.shared = true; });
  let visible = true;
  stationReplies(host, (req) => {
    if (req.url.endsWith("/threads/7/archive")) return { ok: true };
    if (req.url.includes("/chats?shared=1&session=k1")) return { rows: visible ? [row] : [], scope: ["k1"] };
    return undefined;
  });
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "chats", scope: "ws" });
  await host.settle();
  call(core, ui, 2, "chat.archive", { station: "ws/st", thread: 7, session: "k1", archived: true });
  await host.settle();
  push("chat-shared-removed", { id: "k1" });
  await host.settle();
  const release = host.hold("/chats?shared=1&session=k1&thread=7");
  call(core, ui, 3, "chat.archive", { station: "ws/st", thread: 7, session: "k1", archived: false });
  await host.settle();
  visible = false;
  push("chat-changed", { thread: 7 });
  await host.settle();
  release();
  await host.settle();
  answersOf(host, values);
  assert.equal(v(values, 1).days.flatMap((d: J) => d.items).length, 0);
  assert.equal(core.inner.views.local.rowsQuiet("ws/st"), true);
  core.close();
});

test("a failed restore reconciliation is retried after the station answers with an error", async () => {
  const row = {
    id: "k1", session: "k1", thread: 7, agents: [{ key: "k1", runtime: "claude" }], lastActiveAt: 8, ws: null,
    named: { thread: { surface: "ember", title: "k1" }, firstText: null, channelName: null }, mineOf: [], said: null,
  };
  const { host, core, push } = await started({ ...base(), "GET /chats?shared=1": [row] }, 0, undefined, (s) => { s.gate.shared = true; });
  let visible = true;
  let fail = false;
  stationReplies(host, (req) => {
    if (req.url.endsWith("/threads/7/archive")) return { ok: true };
    if (req.url.includes("/chats?shared=1&session=k1")) {
      if (fail) { fail = false; return status(500, { error: "busy" }); }
      return { rows: visible ? [row] : [], scope: ["k1"] };
    }
    return undefined;
  });
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "chats", scope: "ws" });
  await host.settle();
  call(core, ui, 2, "chat.archive", { station: "ws/st", thread: 7, session: "k1", archived: true });
  await host.settle();
  call(core, ui, 3, "chat.archive", { station: "ws/st", thread: 7, session: "k1", archived: false });
  await host.settle();
  visible = false;
  fail = true;
  push("chat-changed", { thread: 7 });
  await host.settle();
  answersOf(host, values);
  assert.equal(v(values, 1).days.flatMap((d: J) => d.items).length, 1);
  await host.time.pass(READ_RETRY_MS);
  await host.settle();
  answersOf(host, values);
  assert.equal(v(values, 1).days.flatMap((d: J) => d.items).length, 0);
  assert.equal(core.inner.views.local.rowsQuiet("ws/st"), true);
  core.close();
});

test("a confirmed restore is reconciled after restart when it was archived elsewhere", async () => {
  const row = {
    id: "k1", session: "k1", thread: 7, agents: [{ key: "k1", runtime: "claude" }], lastActiveAt: 8, ws: null,
    named: { thread: { surface: "ember", title: "k1" }, firstText: null, channelName: null }, mineOf: [], said: null,
  };
  const { host, core } = await started({ ...base(), "GET /chats?shared=1": [row] }, 0, undefined, (s) => { s.gate.shared = true; });
  let visible = true;
  stationReplies(host, (req) => {
    if (req.url.endsWith("/threads/7/archive")) return { ok: true };
    if (req.url.includes("/chats?") && req.url.includes("session=k1")) return { rows: visible ? [row] : [], scope: ["k1"] };
    if (req.url.endsWith("/chats?shared=1")) return visible ? [row] : [];
    return undefined;
  });
  let ui = core.connect();
  subscribe(core, ui, 1, { topic: "chats", scope: "ws" });
  await host.settle();
  call(core, ui, 2, "chat.archive", { station: "ws/st", thread: 7, session: "k1", archived: true });
  await host.settle();
  call(core, ui, 3, "chat.archive", { station: "ws/st", thread: 7, session: "k1", archived: false });
  await host.settle();
  assert.equal(core.inner.views.local.rowsQuiet("ws/st"), true);
  await run(core.inner.data.written);
  core.close();
  visible = false;
  host.takeEmitted();
  const again = await Core.create(host, { clock: host.time.clock, sample: 0, wire: () => new HostWire(host) });
  await host.time.pass(500);
  ui = again.connect();
  const values = new Map();
  subscribe(again, ui, 1, { topic: "chats", scope: "ws" });
  await host.settle();
  answersOf(host, values);
  assert.equal(v(values, 1).days.flatMap((d: J) => d.items).length, 0);
  assert.equal(again.inner.views.local.rowsQuiet("ws/st"), true);
  again.close();
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
    if (req.method === "GET" && path.startsWith("/chats?archived=1")) return all();
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
  await host.time.pass(1_000);
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

test("the_archive_is_looked_through_as_a_ui_asks_by_what_its_chats_said_each_once_and_a_page_not_answered_is_asked_again", async () => {
  const chat = (id: string, at: number, last: string | null) => ({ id, session: id, thread: null, title: `聊 ${id}`, last: last === null ? null : { text: last }, lastActiveAt: at, archived: { at, by: "manual", alone: false } });
  const searches: string[] = [];
  let failures = 1;
  const s = stationHost(base());
  stationReplies(s.host, (req) => {
    const path = req.url.replace("https://stillfail.test/admin/api", "");
    if (path === "/chats?archived=1&page=") return { rows: [chat("k1", 30, "好了"), chat("k2", 20, null)], next: "20:k2" };
    if (path === "/chats?archived=1&page=20%3Ak2") return { rows: [chat("k2", 20, null), chat("k3", 10, null)], next: null };
    if (path.startsWith("/search?")) {
      searches.push(path);
      return { building: false, groups: [{ kind: "message", more: false, hits: [
        { kind: "message", key: "m:3:1", title: "", text: "那次深埋的结论是回滚", at: 10, thread: 3, seq: 1, chat: "k3", archived: true },
        { kind: "message", key: "m:4:1", title: "", text: "深埋在进行中的对话里", at: 11, thread: 4, seq: 1, chat: "live", archived: false },
      ] }] };
    }
    return undefined;
  });
  stationLater(s.host, (req) => (req.url.endsWith("page=20%3Ak2") && failures-- > 0 ? Promise.resolve(jsonResponse(500, { error: "busy" })) : undefined));
  const host = s.host;
  const core = await Core.create(host, { clock: host.time.clock, sample: 0, wire: () => new HostWire(host) });
  await host.time.pass(500);
  const ui = core.connect();
  const ask = (id: number, topic: J) => core.receiveRaw(ui, { id, subscribe: topic });
  ask(1, { topic: "archive", scope: "ws", limit: 1 });
  ask(2, { topic: "archive", scope: "ws", q: "深埋" });
  ask(3, { topic: "archive", scope: "ws" });
  await host.settle();
  await host.time.pass(5_000);
  await host.settle();
  const values = new Map();
  answersOf(host, values);
  const ids = (n: number) => v(values, n).days.flatMap((d: J) => d.items.map((i: J) => i.id));
  // `limit` as a UI says it: the newest; the rest said to be there.
  assert.deepEqual([ids(1), v(values, 1).total, v(values, 1).more], [["k1"], 3, true]);
  // `q` as a UI says it: found by a message of an archived chat, on a page read after one that was not answered.
  assert.deepEqual(ids(2), ["k3"]);
  assert.match(v(values, 2).days[0].items[0].last, /深埋/);
  assert.ok(searches.every((path) => path.includes("kinds=chat%2Cmessage") && path.includes("limit=200") && path.includes("archived=1")), searches.join());
  // A chat in two pages is one row.
  assert.deepEqual(ids(3), ["k1", "k2", "k3"]);
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
  const asked: Record<string, number> = { desktop: 6, web: 7, station: 8, cloud: 9 };
  for (const [part, id] of Object.entries(asked)) subscribe(core, ui, id, { topic: "changelog", part });
  await host.settle();
  const values = new Map();
  answersOf(host, values);
  const c = v(values, 2);
  assert.deepEqual([c.app, c.build, c.loading], ["android", 1320, false]);
  // A tab a part, this app's first; the desktop's carries the web's.
  assert.deepEqual(c.tabs.map((x: J) => [x.part, x.label]), [["android", "安卓"], ["desktop", "桌面"], ["web", "网页"], ["station", "Station"], ["cloud", "云端"]]);
  const notes = (part: string) => v(values, asked[part] ?? 2).tabs.find((x: J) => x.part === part).days.flatMap((d: J) => d.entries.map((e: J) => e.note));
  assert.equal(c.tabs[0].days[0].label, "今天");
  // Each day which it is where the device is (its label only says it): the same day for all of today's.
  assert.equal(c.tabs[0].days.length, 1);
  assert.equal(c.tabs[0].days[0].day, Math.floor((now * 1000 + host.utcOffsetMin(now * 1000) * 60_000) / 86_400_000));
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
  // Asked with `news` (the chats' list's card): that alone, no tab made.
  subscribe(core, ui, 5, { topic: "changelog", news: true });
  await host.settle();
  answersOf(host, values);
  const news = v(values, 2).news;
  assert.equal(news.build, "0.1.1335");
  assert.deepEqual(news.entries.map((e: J) => e.text[0]), ["修复：列表跳动"]);
  assert.equal(v(values, 2).tabs.length, 5);
  assert.deepEqual(v(values, 5).news, news);
  assert.deepEqual([v(values, 5).app, v(values, 5).build, v(values, 5).tabs, v(values, 5).loading], ["android", 1335, [], false]);
  await ask(host, core, ui, 4, "changelog.seen", {});
  answersOf(host, values);
  assert.equal(v(values, 2).news, undefined);
  assert.equal(v(values, 5).news, undefined);
  // Read once at each start (the TS core reads it then and as the cloud's socket opens).
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
  assert.deepEqual(tabs[0].days.flatMap((d: J) => d.entries.map((e: J) => e.lines[0].text)), ["列表跳动", "更早的"]);
  core.close();
});

test("the_changelog_sends_the_tab_asked_a_page_at_a_time_and_says_how_many_more", async () => {
  const host = new FakeHost();
  const now = Math.round(host.nowMs() / 1000);
  const entry = (version: number, parts: string[]) => ({ version, commit: "c", at: now - (2000 - version) * 600, text: [`修复：第 ${version} 个`], fixes: [], parts });
  // Forty of Android's, five of the station's among them.
  const entries = Array.from({ length: 45 }, (_, i) => entry(2000 - i, i % 9 === 4 ? ["station"] : ["android"]));
  host.onFetch((req) => req.url.endsWith("/v1/changelog") ? jsonResponse(200, { entries, released: { android: 2000, station: 2000 } }) : jsonResponse(404, {}));
  const core = await Core.create(host, { clock: host.time.clock, sample: 0 });
  const ui = core.connect();
  await ask(host, core, ui, 1, "client.device", { app: "android", build: "0.1.1990" });
  subscribe(core, ui, 2, { topic: "changelog" });
  subscribe(core, ui, 3, { topic: "changelog", part: "station" });
  subscribe(core, ui, 4, { topic: "changelog", part: "nowhere", limit: 12 });
  subscribe(core, ui, 5, { topic: "changelog", limit: 60 });
  await host.settle();
  const values = new Map();
  answersOf(host, values);
  const versions = (id: number) => v(values, id).tabs.map((x: J) => [x.part, x.days.flatMap((d: J) => d.entries.map((e: J) => e.version))]);
  const android = entries.filter((e) => e.parts[0] === "android").map((e) => e.version);
  const station = entries.filter((e) => e.parts[0] === "station").map((e) => e.version);
  const others = (asked: string, shown: number[]) => ["android", "desktop", "web", "station", "cloud"].map((part) => [part, part === asked ? shown : []]);
  // A page (30) of this app's tab where none is said, the others none, and how many it has past them.
  assert.deepEqual(versions(2), others("android", android.slice(0, 30)));
  assert.equal(v(values, 2).more, 10);
  // Another tab asked: its own, all of them, nothing more.
  assert.deepEqual(versions(3), others("station", station));
  assert.equal(v(values, 3).more, undefined);
  // A tab there is not: this app's; a limit of its own.
  assert.deepEqual(versions(4), others("android", android.slice(0, 12)));
  assert.equal(v(values, 4).more, 28);
  assert.deepEqual(versions(5), others("android", android));
  assert.equal(v(values, 5).more, undefined);
  // A day's change is what the page shows of it: its words as written and whether it is this app's are news' alone.
  assert.deepEqual(Object.keys(v(values, 2).tabs[0].days[0].entries[0]).sort(), ["has", "lines", "note", "version", "versionName"]);
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
  const registrationRequest = stationPosted(host, "/feishu/registrations")[0];
  assert.deepEqual([registrationRequest.bind.runtime, registrationRequest.bind.model, registrationRequest.mode], ["codex", "gpt-6-astra", "multi-session"], "the station has the chosen settings before the scan");
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

test("connect_wizard_offers_comma_where_its_station_has_it_and_adds_a_connect_of_the_line_comma_shows", async () => {
  const { host, core } = await choosing();
  stationReplies(host, (req) => {
    const path = req.url.replace("https://stillfail.test/admin/api", "");
    if (path === "/comma/connects") return { id: "comma" };
    return undefined;
  });
  const ui = core.connect();
  const topic = connectTopic("comma");
  const form = { station: "ws/st", form: "comma" };
  await ask(host, core, ui, 1, "connect.flow.open", form);
  const flow = core.inner.forms.connects;
  withFeishu(core, []);
  assert.deepEqual(flow.value(topic).platforms, ["slack", "feishu"], "a station from before the Comma connect does not offer it");
  const at = { topic: "overview", station: "ws/st" };
  core.inner.data.set(at, { ...(structuredClone(core.inner.store.get(at)) as J), comma: true });
  assert.deepEqual(flow.value(topic).platforms, ["slack", "feishu", "comma"]);
  flow.go(topic, ui, "commaBind");
  let view = flow.value(topic);
  assert.deepEqual([view.step, view.platform, view.back, view.number, view.total], ["commaBind", "comma", "platform", 2, 3]);
  await ask(host, core, ui, 2, "pick.set", { station: "ws/st", of: "connect-new:comma", model: "gpt-6-astra", runtime: "codex" });
  await ask(host, core, ui, 3, "pick.save", { station: "ws/st", of: "connect-new:comma" });
  flow.go(topic, ui, "commaLine");
  flow.edit(topic, ui, { comma: { line: "tailcat 1.2.3.4 4750" } });
  assert.equal(flow.value(topic).comma.ready, false);
  assert.throws(() => flow.begin(topic, ui, "create", {}, false), "not a line Comma shows");
  // Comma's production shows its connector's socket address.
  flow.edit(topic, ui, { comma: { line: "comma wss://salix.comma.surf salix_conn_abc12345" } });
  assert.equal(flow.value(topic).comma.ready, true);
  flow.edit(topic, ui, { comma: { line: " comma https://api.comma.surf salix_conn_abc12345 " } });
  view = flow.value(topic);
  assert.deepEqual([view.step, view.back, view.comma.ready], ["commaLine", "commaBind", true]);
  const shaped = present.decorate(topic, structuredClone(view), { now: 0, offsetMin: 0 });
  assert.ok("ok" in conform("ConnectFlowView", shaped), JSON.stringify(conform("ConnectFlowView", shaped)));
  await ask(host, core, ui, 4, "connect.flow.create", form);
  const sent = stationPosted(host, "/comma/connects");
  assert.deepEqual([sent.length, sent[0].line, sent[0].bind.runtime, sent[0].bind.model], [1, "comma https://api.comma.surf salix_conn_abc12345", "codex", "gpt-6-astra"]);
  assert.equal(flow.value(topic).step, "done");
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
  assert.deepEqual(host.requests.filter((r) => r.method === "DELETE").map((r) => r.url.replace("https://stillfail.test/admin/api", "")), [], "closing the form does not cancel an already opened scan");
  core.close();
});

test("connect_wizard_rechecks_a_scan_done_before_the_register_request_finishes", async () => {
  const { host, core } = await choosing();
  const done = { id: "quick", url: "https://accounts.feishu.cn/x", expiresAt: 1_790_000_600_000, state: "done", appId: "cli_quick", domain: "feishu" };
  stationReplies(host, (req) => {
    const path = req.url.replace("https://stillfail.test/admin/api", "");
    if (path === "/feishu/registrations") return { id: done.id, url: done.url, expiresAt: done.expiresAt, overview: { ...(structuredClone(core.inner.store.get({ topic: "overview", station: "ws/st" })) as J), feishuRegistrations: [done] } };
    if (path === "/feishu/connects") return { id: "quick-bot" };
    return undefined;
  });
  withFeishu(core, []);
  const ui = core.connect();
  const form = { station: "ws/st", form: "quick" };
  await ask(host, core, ui, 1, "connect.flow.open", form);
  await ask(host, core, ui, 2, "connect.flow.go", { ...form, input: { to: "feishuBind" } });
  await ask(host, core, ui, 3, "pick.set", { station: "ws/st", of: "connect-new:quick", model: "gpt-6-astra", runtime: "codex" });
  await ask(host, core, ui, 4, "pick.save", { station: "ws/st", of: "connect-new:quick" });
  await ask(host, core, ui, 5, "connect.flow.go", { ...form, input: { to: "feishuWay" } });
  await ask(host, core, ui, 6, "connect.flow.register", form);
  await host.settle();
  assert.equal(stationPosted(host, "/feishu/connects").length, 1);
  assert.equal(core.inner.forms.connects.value(connectTopic("quick")).feishu.connect, "quick-bot");
  core.close();
});

test("connect_wizard_rechecks_a_finished_scan_when_the_model_becomes_available", async () => {
  const { core } = await choosing();
  withFeishu(core, []);
  const ui = core.connect();
  const topic = connectTopic("late-model");
  const selected = { valueOption: { model: "gpt-6-astra" }, value: { runtime: "codex", model: "gpt-6-astra" } };
  let picked: { valueOption: { model: string } | null; value: { runtime: string; model: string } } = selected;
  let ready = 0;
  const flow = new ConnectFlows(core.inner.store, () => ({ ok: picked }), () => {}, { ready: (t) => { if (flow.ready(t)) ready++; } });
  flow.open(topic, ui, {});
  flow.go(topic, ui, "feishuBind");
  flow.go(topic, ui, "feishuWay");
  const [generation] = flow.begin(topic, ui, "register", {}, false);
  flow.finish(topic, generation, "register", { ok: { id: "late", url: "https://accounts.feishu.cn/x", expiresAt: 1_790_000_600_000 } });
  picked = { ...selected, valueOption: null };
  withFeishu(core, [{ id: "late", url: "https://accounts.feishu.cn/x", expiresAt: 1_790_000_600_000, state: "done", appId: "cli_late", domain: "feishu" }]);
  assert.equal(ready, 0, "the scan finished before the model was available");
  picked = selected;
  core.inner.store.set(pickOf("ws/st", "late-model"), { ok: selected });
  assert.equal(ready, 1, "the picker change causes another readiness check");
  flow.drop(topic, ui);
  core.close();
});

test("connect_wizard_shows_a_station_saved_scan_even_if_the_model_is_no_longer_available", async () => {
  const { host, core } = await choosing();
  withFeishu(core, []);
  const ui = core.connect();
  const topic = connectTopic("saved-scan");
  const selected = { valueOption: { model: "gpt-6-astra" }, value: { runtime: "codex", model: "gpt-6-astra" } };
  let picked: { valueOption: { model: string } | null; value: { runtime: string; model: string } } = selected;
  let createRequests = 0;
  const flow = new ConnectFlows(core.inner.store, () => ({ ok: picked }), () => {}, { ready: (t) => { if (flow.ready(t)) createRequests++; } });
  flow.open(topic, ui, {});
  flow.go(topic, ui, "feishuBind");
  flow.go(topic, ui, "feishuWay");
  const [generation] = flow.begin(topic, ui, "register", {}, false);
  flow.finish(topic, generation, "register", { ok: { id: "saved", url: "https://accounts.feishu.cn/x", expiresAt: 1_790_000_600_000 } });
  picked = { ...selected, valueOption: null };
  const at = { topic: "overview", station: "ws/st" };
  core.inner.data.set(at, { ...(structuredClone(core.inner.store.get(at)) as J), feishuRegistrations: [{ id: "saved", url: "", expiresAt: 1_790_000_600_000, state: "done", appId: "cli_saved", domain: "feishu" }], connects: [{ id: "bot", kind: "feishu", feishu: { appId: "cli_saved" } }] });
  await host.settle(); // The overview's database write notifies its watchers on commit.
  assert.deepEqual([flow.value(topic).step, flow.value(topic).feishu.connect, createRequests], ["done", "bot", 0]);
  flow.drop(topic, ui);
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

test("pick_says_the_models_own_effort_and_its_accounts_speed_where_none_is_picked", async () => {
  for (const profileFast of [false, true]) {
    const s = (key: string) => ({ ...session(key), runtime: "codex", model: "gpt-6-astra", profile: "p3", fast: null, effort: null });
    const check = { state: "ok", detail: "", checkedAt: 1, modelEfforts: { codex: { "gpt-6-astra": ["low", "medium", "high"] } }, modelEffortDefaults: { codex: { "gpt-6-astra": "medium" } } };
    const { host, core } = await started({
      ...base(),
      "GET /overview": { ...overview, profiles: [profile("p3", "codex", ["gpt-6-astra"], true, 0, { fast: profileFast, check })] },
      "GET /sessions": [s("k1")],
      "GET /sessions/k1": { session: s("k1"), threads: [], turns: [], jobs: [] },
    });
    const ui = core.connect();
    subscribe(core, ui, 1, { topic: "pick", station: "ws/st", of: "session:k1" });
    await host.settle();
    const values = new Map();
    apply(host, values);
    assert.equal(v(values, 1).effortDefault, "medium");
    assert.equal(v(values, 1).fastPlan === true, profileFast);
    // (picked, the draft says it; the model's own stays what it is)
    await ask(host, core, ui, 2, "pick.set", { station: "ws/st", of: "session:k1", effort: "high" });
    apply(host, values);
    assert.equal(v(values, 1).draft.effort, "high");
    assert.equal(v(values, 1).effortDefault, "medium");
    core.close();
  }
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

test("the_running_core_pairs_the_phone_with_its_own_adb", async () => {
  const did: string[] = [];
  const { host, core } = await started(base(), 0, undefined, ({ host }) => {
    (host as J).adb = {
      pair: (port: number, code: string) => Effect.sync(() => void did.push(`pair ${port} ${code}`)),
      hold: (port: number) => Effect.sync(() => void did.push(`hold ${port}`)),
      open: () => Effect.die("no station is opening a tunnel"),
    };
  });
  try {
    const ui = core.connect();
    await ask(host, core, ui, 1, "client.device", { app: "android", build: "1" });
    await ask(host, core, ui, 2, "adb.ports", { connect: 5555, pair: 37115, device: "Pixel" });
    const result = await ask(host, core, ui, 3, "adb.pair", { code: "123 456" });
    assert.deepEqual(result, { message: "已配对，以后连哪台 station 都不用再配" });
    assert.deepEqual(did, ["pair 37115 123456", "hold 5555"]);
  } finally {
    core.close();
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
  assert.deepEqual(v(values, 1), { sharing: false, phase: "off", on: false, tunnels: 0, grants: [], wanted: [], known: true, lends: [], screens: [], personal: v(values, 1).personal, toConfirm: 0 });
  assert.deepEqual(v(values, 1).personal.map((p: J) => [p.standing, p.devices]), [["none", []]]);
  core.close();
});

test("a_phone_s_ports_are_taken_before_its_app_says_it_is_a_phone_and_lent_once_it_does", async () => {
  // (a process the phone started for a grant: its service gives the ports before the app has said what it is)
  const { host, core } = await started();
  takeAll(core.inner.adb);
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
  // The internal offer deadline is not the end of a chat's grant (it can end sooner or be renewed).
  assert.equal(v(values, 2).until, undefined);
  core.close();
});

test("a_phone_lends_for_its_chats_grants_only_while_its_switch_is_on_and_the_switch_outlives_its_core", async () => {
  // (2026-10-30, user: 「全局的 adb 开关，默认关闭，开启后永远开启，不会因为更新或者重启关掉」)
  const { host, core } = await started();
  takeAll(core.inner.adb);
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
  takeAll(again.inner.adb);
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
  takeAll(core.inner.adb);
  const exp = Math.floor(host.nowMs() / 1000) + 3600;
  core.inner.adb.heard("ws1/st1", { id: "g1", session: "ember:c1", chat: "c1", reason: "调试", status: "granted", scope: "chat", exp, at: 1 });
  await host.settle();
  host.takeEmitted();
  core.close();
  const again = await Core.create(host, { clock: host.time.clock, sample: 0, wire: () => new HostWire(host) });
  takeAll(again.inner.adb);
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

test("a_phone_shows_each_chat_once_ordered_by_the_last_actual_use", async () => {
  const { host, core } = await started();
  const exp = Math.floor(host.nowMs() / 1000) + 3600;
  const at = Math.floor(host.nowMs());
  const grant = (id: string, chat: string, lastUsedAt?: number) => ({
    id, session: `session-${id}`, chat, reason: `reason-${id}`, chatTitle: `title-${chat}`,
    status: "granted", scope: "chat", exp, at: 1, ...(lastUsedAt === undefined ? {} : { lastUsedAt }),
  });
  core.inner.adb.heard("ws1/st1", grant("old", "chat-a", at - 120_000));
  core.inner.adb.heard("ws1/st1", grant("other", "chat-b", at - 90_000));
  core.inner.adb.heard("ws1/st1", grant("new", "chat-a", at - 60_000));
  core.inner.adb.heard("ws1/st1", grant("unknown", "chat-c"));
  assert.deepEqual(core.inner.adb.grants().map((g: J) => [g.id, g.chat, g.lastUsedAt]), [
    ["new", "chat-a", at - 60_000], ["other", "chat-b", at - 90_000], ["unknown", "chat-c", undefined],
  ]);
  // (a station's word alone, nothing signed: shown, and lends nothing)
  assert.deepEqual(core.inner.adb.wanted(), []);
  // The view has the title and relative time, and that time advances while the page remains open.
  core.keepTime();
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "adbShare" });
  await host.settle();
  apply(host, values);
  const shown = v(values, 1).grants[0];
  assert.equal(shown.chatTitle, "title-chat-a");
  const ago = shown.time.lastUsedAt.ago;
  await host.time.pass(120_000, 50);
  await host.settle();
  apply(host, values);
  assert.notEqual(v(values, 1).grants[0].time.lastUsedAt.ago, ago);
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

test("profile_fusion_is_asked_on_demand_and_legacy_tiered_agy_picks_resolve_to_base_models", async () => {
  const agyProfile = profile("ag1", "agy", ["gemini-4-carbon", "claude-opus-5-5", "gpt-oss-120b"], true, 10, {
    check: {
      state: "ok",
      detail: "ok",
      models: ["gemini-4-carbon", "claude-opus-5-5", "gpt-oss-120b"],
      modelEfforts: { agy: { "gemini-4-carbon": ["low", "medium", "high"], "claude-opus-5-5": ["low", "medium", "high"], "gpt-oss-120b": [] } },
      modelEffortDefaults: { agy: { "gemini-4-carbon": "high", "claude-opus-5-5": "high" } },
      checkedAt: 1,
    },
  });
  const legacySession = { ...session("k1"), runtime: "agy", model: "gemini-4-carbon-high", effort: null, profile: "ag1" };
  const stationOv = {
    ...overview,
    sessionRuntimeChange: true,
    connectRuntimeChange: true,
    profiles: [
      profile("p2", "claude", ["claude-opus-5-5"], true, 80),
      agyProfile,
      profile("dv", "devin", ["gemini-4-carbon"], true, 20, {
        check: {
          state: "ok",
          detail: "ok",
          models: ["gemini-4-carbon"],
          fusionSidekicks: { "gemini-4-carbon": ["swe-2-medium"] },
          checkedAt: 1,
        },
      }),
    ],
  };
  const { host, core } = await started({
    ...base(),
    "GET /overview": stationOv,
    "GET /sessions": [legacySession],
    "GET /sessions/k1": { session: legacySession, threads: [], turns: [], jobs: [] },
    "GET /profiles/dv/fusion": { fusion: { leads: { "gpt-6-sol-max": [0] }, sides: ["swe-2-medium"] } },
  });
  const ui = core.connect();
  const got = (await ask(host, core, ui, 1, "profile.fusion", { station: "ws/st", id: "dv" })) as J;
  assert.deepEqual(got, {
    fusion: {
      leads: [{ id: "gpt-6-sol", name: "GPT-6 Sol", maker: { id: "openai", name: "OpenAI" }, sides: [0] }],
      sides: [{ id: "swe-2-medium", name: "SWE-2 · 中", maker: { id: "devin", name: "Cognition" } }],
    },
  });

  // Seed legacy tiered agy records (pre-normalization) and subscribe to `pick` for both `new` and legacy session `k1`.
  core.inner.data.put("choice", "ws:ws:station:st", { runtime: "agy", model: "gemini-4-carbon-medium", effort: "", profile: "", profiles: null, fast: null, context: null }, false);
  core.inner.data.put(
    "choice",
    "ws:ws:frequent",
    [
      { model: "gemini-4-carbon-medium", runtime: "agy", effort: null, fast: null, context: null, count: 4, last: 200 },
      { model: "gpt-oss-120b-medium", runtime: "agy", effort: null, fast: null, context: null, count: 2, last: 100 },
    ],
    false,
  );
  core.inner.data.put("choice", "ws:ws:liked", ["gemini-4-carbon-high", "gpt-oss-120b-medium"], false);

  const values = new Map();
  subscribe(core, ui, 2, { topic: "pick", station: "ws/st", of: "new" });
  subscribe(core, ui, 3, { topic: "pick", station: "ws/st", of: "session:k1" });
  await host.settle();
  apply(host, values);

  // New chat pick resolves legacy `gemini-4-carbon-medium` -> `gemini-4-carbon` at `medium`, and retains frequent combos + stars.
  // Even while drafted on `agy`, `sidekicks` are offered because `gemini-4-carbon` also runs on `devin` with Fusion sidekicks.
  const newPick = v(values, 2);
  assert.deepEqual([newPick.value.model, newPick.value.runtime, newPick.value.effort], ["gemini-4-carbon", "agy", "medium"]);
  assert.deepEqual(newPick.sidekicks.slice(0, 2), [
    { id: "", text: "无", model: "gemini-4-carbon" },
    { id: "swe-2-medium", text: "SWE-2 · 中", model: "fusion-gemini-4-carbon-sidekick-swe-2-medium", maker: { id: "devin" } },
  ]);
  assert.deepEqual(newPick.liked, ["gemini-4-carbon", "gpt-oss-120b"]);
  assert.deepEqual(
    newPick.combos.map((c: J) => [c.model, c.runtime, c.effort, c.text]),
    [
      ["gemini-4-carbon", "agy", "medium", "AGY · 中"],
      ["gpt-oss-120b", "agy", undefined, "AGY · 默认深度"],
    ],
  );
  // Legacy session `k1` with `model: "gemini-4-carbon-high", effort: null` normalizes to `gemini-4-carbon` at `high`.
  const sessionPick = v(values, 3);
  assert.deepEqual([sessionPick.value.model, sessionPick.value.runtime, sessionPick.value.effort], ["gemini-4-carbon", "agy", "high"]);

  // Unstarring normalized `gemini-4-carbon` clears legacy `gemini-4-carbon-high`, and forgetting normalized combo clears legacy history.
  core.inner.choose.like("ws/st", "gemini-4-carbon", false);
  core.inner.choose.forget("ws/st", { model: "gemini-4-carbon", runtime: "agy", effort: "medium" });
  await host.settle();
  apply(host, values);
  const afterPick = v(values, 2);
  assert.deepEqual(afterPick.liked, ["gpt-oss-120b"]);
  assert.deepEqual(afterPick.combos.map((c: J) => c.model), ["gpt-oss-120b"]);

  const { runnableOn } = await import("../src/views/models.ts");
  assert.equal(runnableOn(stationOv, { runtime: "agy", model: "gemini-4-carbon-high", profile: "ag1" }, 0).length, 1);
  core.close();
});
