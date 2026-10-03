// client/core/src/cloud.rs, status.rs, workspace.rs, ops.rs and trace.rs tests, ported.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Accounts, STORAGE_KEY } from "../src/accounts.ts";
import { Cloud } from "../src/cloud.ts";
import { CoreError } from "../src/error.ts";
import { holdLanguage } from "../src/i18n.ts";
import { request } from "../src/ops.ts";
import { Runner } from "../src/runtime.ts";
import { RELAY, Status, stationWhat, value } from "../src/status.ts";
import { FakeHost, jsonResponse } from "../src/testing.ts";
import { EXPORT_MS, Kind, Tracer, route } from "../src/trace.ts";
import { ofAddress, Workspaces } from "../src/workspace.ts";
import * as brand from "../src/brand.ts";
import { cloudError } from "../src/cloud.ts";
import { parseJson } from "../src/util.ts";

holdLanguage();

async function cloud(host: FakeHost) {
  host.store(STORAGE_KEY, [{ sub: "s", email: "s@x.com", name: "", picture: "", access: "tok", refresh: "ref", access_expires: Date.now() / 1000 + 3600 }]);
  const runner = new Runner(host.time.clock);
  return new Cloud(host, await Accounts.load(host), new Tracer(host, runner, 1), new Status(host, runner));
}
const header = (r: { headers: [string, string][] }, name: string) => r.headers.find(([k]) => k === name)?.[1];

test("request_adds_the_token_and_json", async () => {
  const host = new FakeHost();
  host.onFetch(() => jsonResponse(200, { ok: true }));
  const c = await cloud(host);
  assert.deepEqual(await c.me("s"), { ok: true });
  await c.request("s", "PATCH", "/v1/workspaces/w", { name: "新" });
  const [a, b] = host.requests;
  assert.deepEqual([a.method, a.url], ["GET", "https://stillfail.test/v1/me"]);
  assert.equal(header(a, "authorization"), "Bearer tok");
  assert.equal(header(a, "content-type"), undefined);
  assert.equal(a.body, null);
  assert.equal(header(b, "content-type"), "application/json");
  assert.deepEqual(parseJson(b.body!), { name: "新" });
});

test("errors_map_to_codes_and_messages", async () => {
  const host = new FakeHost();
  host.onFetch((req) => {
    const last = req.url.split("/").pop();
    if (last === "known") return jsonResponse(404, { error: "workspace_not_found" });
    if (last === "unknown") return jsonResponse(409, { error: "something_new" });
    return { status: 502, headers: [], body: new TextEncoder().encode("<html>bad gateway") };
  });
  const c = await cloud(host);
  const err = async (p: Promise<unknown>) => {
    try {
      await p;
    } catch (e) {
      return (e as CoreError).toJSON();
    }
    throw new Error("ok");
  };
  assert.deepEqual(await err(c.request("s", "GET", "/v1/known", null)), { code: "workspace_not_found", message: "找不到这个 workspace，或者你已经不在里面了", status: 404 });
  assert.deepEqual(await err(c.request("s", "GET", "/v1/unknown", null)), { code: "something_new", message: "something_new", status: 409 });
  assert.deepEqual(await err(c.request("s", "GET", "/v1/html", null)), { code: "http_502", message: "http_502", status: 502 });
  assert.equal((await err(c.me("nobody"))).code, "signed_out");
  assert.equal(host.requests.length, 3);
});

test("a_credential_is_asked_for_the_device", async () => {
  const host = new FakeHost();
  host.onFetch(() => jsonResponse(200, { credential: "c", issued_at: 1.0, expires_at: 10.0, relay_url: "https://relay" }));
  const c = await cloud(host);
  const credential = await c.credential("s", "ws 1", "dev-key");
  assert.deepEqual([credential.credential, credential.expires_at], ["c", 10]);
  const r = host.requests[0];
  assert.deepEqual([r.method, r.url], ["POST", "https://stillfail.test/v1/workspaces/ws%201/credential"]);
  assert.deepEqual(parseJson(r.body!), { device: "dev-key" });
});

test("what_the_core_says_names_the_channels_product", () => {
  for (const [on, name] of [[false, "still.fail"], [true, "youdid.wtf"]] as const) {
    brand.setTestChannel(on);
    assert.equal(cloudError("invalid_email", 400).message, `要填对方登录 ${name} 用的邮箱`);
  }
  brand.setTestChannel(false);
});

test("says_nothing_until_a_wait_is_slow_then_what_and_how_fast", () => {
  const host = new FakeHost();
  const status = new Status(host, new Runner(host.time.clock));
  status.setNames((a) => (a === "ws/s1" ? "studio" : null));
  const wait = status.begin({ station: "ws/s1" }, stationWhat("GET", "/threads/3/entries?limit=50"), false);
  assert.equal((status.value() as { state: unknown }).state, null);
  status.skew += 3_000;
  const v = () => status.value() as { state: unknown; text: string; items: { detail: string; text: string }[] };
  assert.equal(v().text, "studio 读取对话 · 3 秒");
  assert.equal(v().items[0].detail, "已等 3 秒，还没收到数据");
  wait.received(300 * 1024);
  assert.equal(v().items[0].detail, "已收 300 KB，3 秒");
  assert.equal(v().text, "studio 读取对话 · 3 秒 · 300 KB/s");
  wait.end();
  assert.equal(v().state, null);
});

test("a_connection_goes_first_and_a_socket_down_is_trouble", () => {
  const host = new FakeHost();
  const status = new Status(host, new Runner(host.time.clock));
  status.begin({ station: "ws/s1" }, "读取对话", false);
  status.begin(RELAY, "连接", true);
  status.skew += 2_500;
  const v = () => status.value() as { state: unknown; text: string; items: { text: string }[] };
  assert.equal(v().state, "slow");
  assert.equal(v().text, "正在连接 relay · 2 秒 · 共 2 项");
  assert.equal(v().items[1].text, "读取对话");
  const now = status.now();
  status.socketDown("a", "网络错误", now + 4_000);
  assert.equal(v().state, "slow", "not yet: it may be back at once");
  status.skew += 2_000;
  assert.equal(v().state, "trouble");
  assert.equal(v().text, "连不上 still.fail cloud，2 秒后重试 · 共 3 项");
  status.socketDown("a", "网络错误", now + 8_000);
  assert.equal(v().items[0].text, "连不上 still.fail cloud，6 秒后重试（第 2 次）");
  status.socketUp("a");
  assert.equal(v().state, "slow");
});

test("a_workspaces_status_is_its_own_waits_its_accounts_socket_and_the_relay", () => {
  const host = new FakeHost();
  const runner = new Runner(host.time.clock);
  const [w1, w2, device] = [new Status(host, runner), new Status(host, runner), new Status(host, runner)];
  w1.begin({ station: "w1/s" }, "读取对话", false);
  device.begin({ cloud: true }, "读取 workspace", false);
  device.begin(RELAY, "连接", true);
  const now = device.now();
  device.socketDown("a1", "网络错误", now + 9_000);
  device.socketDown("a2", "网络错误", now + 4_000);
  for (const s of [w1, w2, device]) s.skip(2_500);
  const texts = (v: unknown) => (v as { items: { text: string }[] }).items.map((i) => i.text);
  assert.deepEqual(texts(value([[w2, "all"], [device, { for: ["a2"] }]])), ["连不上 still.fail cloud，2 秒后重试", "正在连接 relay"]);
  assert.deepEqual(texts(value([[w1, "all"], [device, { for: ["a1"] }]])), ["连不上 still.fail cloud，7 秒后重试", "正在连接 relay", "读取对话"]);
  assert.deepEqual(texts(value([[w2, "all"], [device, { for: [] }]])), ["正在连接 relay"]);
  assert.deepEqual(texts(value([[w1, "all"], [w2, "all"], [device, "all"]])), ["连不上 still.fail cloud，2 秒后重试", "正在连接 relay", "读取对话", "still.fail cloud 读取 workspace"]);
});

test("a_station_is_in_the_workspace_its_address_names", () => {
  assert.equal(ofAddress("ws/st"), "ws");
  const host = new FakeHost();
  const workspaces = new Workspaces(host, new Runner(host.time.clock));
  assert.equal(workspaces.ofStation("ws/a"), workspaces.ofStation("ws/b"));
  assert.notEqual(workspaces.ofStation("ws/a"), workspaces.ofStation("other/a"));
  workspaces.setOwners(new Map([["ws", "s1"]]));
  assert.equal(workspaces.owner("ws"), "s1");
  assert.equal(workspaces.owner("other"), null);
  workspaces.setOwners(new Map());
  assert.equal(workspaces.owner("ws"), null);
});

const req = (name: string, params: unknown) => request(name, params)!;

test("operations_make_their_requests", () => {
  let r = req("job.stop", { station: "w/s", id: "job 1" });
  assert.deepEqual([r.target, r.method, r.path, r.body], [{ station: "w/s" }, "POST", "/jobs/job%201/stop", null]);
  r = req("job.clearEnded", { station: "ws/st", session: "ember:c-1" });
  assert.deepEqual([r.method, r.path], ["DELETE", "/sessions/ember%3Ac-1/jobs"]);
  r = req("session.settings", { station: "ws/st", key: "k", model: "m", profile: null });
  assert.deepEqual(r.body, { model: "m", profile: null });
  r = req("workspace.setRole", { account: "a", workspace: "w1", member: "x@y.z", role: "admin" });
  assert.deepEqual([r.target, r.method, r.path], [{ cloud: "a" }, "PATCH", "/v1/workspaces/w1/members/x%40y.z"]);
  assert.equal(req("invitation.accept", { account: "a", token: "t" }).path, "/v1/invitations/accept");
  r = req("software.channel", { station: "w/s", channel: "beta" });
  assert.deepEqual([r.target, r.method, r.path, r.body], [{ station: "w/s" }, "POST", "/updates/channel", { channel: "beta" }]);
  r = req("software.auto", { station: "w/s", on: true });
  assert.deepEqual([r.method, r.path, r.body], ["POST", "/updates/auto", { on: true }]);
  r = req("admin.setBeta", { account: "a", user: "sub-1", on: true });
  assert.deepEqual([r.method, r.path, r.body], ["POST", "/v1/admin/users/sub-1/beta", { on: true }]);
  r = req("admin.feedbackStatus", { account: "a", id: "01J0000000000000000000000A", status: "fixed" });
  assert.deepEqual([r.target, r.method, r.path, r.body], [{ cloud: "a" }, "POST", "/v1/admin/feedback/01J0000000000000000000000A/status", { status: "fixed" }]);
});

test("pinning_a_chat_goes_by_its_session", () => {
  const r = req("chat.pin", { station: "ws/st", session: "ember:c-1", pinned: true });
  assert.deepEqual([r.method, r.path], ["PUT", "/sessions/ember%3Ac-1/pin"]);
  assert.equal(req("chat.pin", { station: "ws/st", session: "k", pinned: false }).method, "DELETE");
});

test("a_decision_is_dismissed_on_its_chats_thread", () => {
  const r = req("decision.dismiss", { station: "ws/st", thread: 7, seq: 4 });
  assert.deepEqual([r.target, r.method, r.path, r.body], [{ station: "ws/st" }, "PUT", "/threads/7/dismissed", { n: 4 }]);
  assert.throws(() => request("decision.dismiss", { station: "ws/st", thread: 7 }));
});

test("archiving_a_chat_falls_back_to_its_session", () => {
  const r = req("chat.archive", { station: "ws/st", thread: 7, session: "k", archived: true });
  assert.deepEqual([r.method, r.path], ["POST", "/threads/7/archive"]);
  const f = r.fallback!;
  assert.deepEqual([f.method, f.path, f.effect], ["POST", "/sessions/k/archive", { kind: "session", key: "k" }]);
  const r2 = req("chat.archive", { station: "ws/st", session: "k", archived: false });
  assert.deepEqual([r2.method, r2.path, r2.fallback], ["DELETE", "/sessions/k/archive", null]);
});

test("renaming_a_chat_names_its_thread_or_its_session", () => {
  let r = req("chat.rename", { station: "ws/st", thread: 7, session: "k", title: "值班" });
  assert.deepEqual([r.method, r.path, r.body], ["PUT", "/threads/7/title", { title: "值班" }]);
  r = req("chat.rename", { station: "ws/st", session: "k", title: "" });
  assert.deepEqual([r.method, r.path, r.body], ["POST", "/sessions/k/title", { title: "" }]);
});

test("unknown_names_and_missing_params", () => {
  assert.equal(request("nothing.here", {}), null);
  assert.equal(request("station.request", {}), null);
  assert.throws(() => request("job.stop", { station: "ws/st" }));
});

test("routes_hide_ids_and_queries", () => {
  assert.equal(route("/admin/api/threads/42/messages?before=9&limit=50"), "/admin/api/threads/:id/messages");
  assert.equal(route("/admin/api/sessions/slack:T1:C1:1790000000.0001/live?from=3"), "/admin/api/sessions/:id/live");
  assert.equal(route("/admin/api/sessions/abc/files?name=报告.pdf"), "/admin/api/sessions/:id/files");
  assert.equal(route("/admin/api/profiles/cc/check"), "/admin/api/profiles/:id/check");
  assert.equal(route("/v1/workspaces/01J8ZK4Q3M5N6P7R8S9T0V1W2X/stations/9f3a"), "/v1/workspaces/:id/stations/:id");
  assert.equal(route("/v1/invitations/preview"), "/v1/invitations/preview");
  assert.equal(route("/admin/api/events"), "/admin/api/events");
});

function exported(bodies: unknown[]) {
  return bodies.flatMap((b) => (b as { resourceSpans: { scopeSpans: { spans: Record<string, unknown>[] }[] }[] }).resourceSpans[0].scopeSpans[0].spans);
}

test("spans_nest_and_go_out_in_one_batch", async () => {
  const host = new FakeHost();
  const tracer = new Tracer(host, new Runner(host.time.clock), 1);
  const bodies: unknown[] = [];
  tracer.setExport(async (b) => void bodies.push(parseJson(b)));
  const root = tracer.root("chat.open", Kind.Internal);
  root.set("stillfail.station", "st");
  const context = root.context;
  // A child under the root's context, handed on after an await.
  await Promise.resolve();
  const child = tracer.span("GET /admin/api/threads", Kind.Client, context);
  child.set("http.response.status_code", 200);
  child.end();
  assert.equal(tracer.current(), null);
  tracer.span("GET /admin/api/overview", Kind.Client).end();
  root.end();
  assert.equal(bodies.length, 0);
  await host.time.pass(EXPORT_MS + 20, 100);
  assert.equal(bodies.length, 1);
  const spans = exported(bodies);
  assert.deepEqual(spans.map((s) => s.name), ["GET /admin/api/threads", "GET /admin/api/overview", "chat.open"]);
  const [c, other, r] = spans;
  assert.equal(c.traceId, r.traceId);
  assert.equal(c.parentSpanId, r.spanId);
  assert.notEqual(other.traceId, r.traceId);
  assert.equal(r.parentSpanId, undefined);
  assert.deepEqual((c.attributes as unknown[])[0], { key: "http.response.status_code", value: { intValue: "200" } });
  assert.deepEqual((r.attributes as unknown[])[0], { key: "stillfail.station", value: { stringValue: "st" } });
  const [start, end] = [BigInt(r.startTimeUnixNano as string), BigInt(r.endTimeUnixNano as string)];
  assert.ok(end >= start && start > 1_700_000_000_000_000_000n);
  assert.equal(context.traceparent(), `00-${r.traceId}-${r.spanId}-01`);
});

test("nothing_is_recorded_when_off_and_a_dropped_span_is_cancelled", async () => {
  const host = new FakeHost();
  const off = new Tracer(host, new Runner(host.time.clock), 0);
  const bodies: unknown[] = [];
  off.setExport(async (b) => void bodies.push(parseJson(b)));
  const root = off.root("chat.send", Kind.Internal);
  assert.ok(root.context.traceparent().endsWith("-00"));
  off.enter(root.context, () => off.span("POST /admin/api/threads/1/messages", Kind.Client).end());
  root.end();
  await host.time.pass(EXPORT_MS + 20, 100);
  assert.equal(bodies.length, 0);
  assert.deepEqual(host.time.sleeps, []);
  const on = new Tracer(host, new Runner(host.time.clock), 1);
  const onBodies: unknown[] = [];
  on.setExport(async (b) => void onBodies.push(parseJson(b)));
  on.root("chat.open", Kind.Internal).cancel();
  await host.time.pass(EXPORT_MS + 20, 100);
  assert.deepEqual((exported(onBodies)[0].attributes as unknown[])[0], { key: "stillfail.cancelled", value: { boolValue: true } });
});
