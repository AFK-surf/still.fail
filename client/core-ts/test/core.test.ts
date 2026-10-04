// The Rust core's core/tests.rs, ported (same names, same checks): the protocol, the calls, the account topics and
// still.fail cloud's events socket, prefs and drafts.
import assert from "node:assert/strict";
import { test } from "node:test";
import { STORAGE_KEY } from "../src/accounts.ts";
import { answer, Core, CREDENTIAL_KEY, relaysOf } from "../src/core.ts";
import { SOCKET_IDLE_MS, SOCKET_RETRY_MS } from "../src/sync/cloud.ts";
import { run } from "./run.ts";
import { parseCall } from "../src/core/calls.ts";
import { diff } from "../src/delta.ts";
import { CoreError, HostError } from "../src/error.ts";
import { encode } from "../src/ops.ts";
import * as prefs from "../src/prefs.ts";
import { parseClientMessage } from "../src/protocol.ts";
import { EVICT_AFTER_MS } from "../src/store.ts";
import { FakeHost, jsonResponse } from "../src/testing.ts";
import { fromBase64, base64, parseJson, toJsonBytes } from "../src/util.ts";
import { account, apply, call, cloudCore, count, nowS, signIn, stationAnswers, subscribe, v, answers } from "./helpers.ts";
import { current, tr } from "../src/i18n.ts";

const code = (f: () => unknown) => {
  try {
    f();
  } catch (e) {
    return (e as CoreError).code;
  }
  throw new Error("parsed");
};

test("the_relays_are_the_list_or_the_one_from_before_there_were_several", () => {
  assert.deepEqual(relaysOf({ relay_url: "https://a", relay_urls: ["https://a", "https://b"] }), ["https://a", "https://b"]);
  assert.deepEqual(relaysOf({ relay_url: "https://a" }), ["https://a"]);
  assert.deepEqual(relaysOf({ relay_url: "https://a", relay_urls: [] }), ["https://a"]);
  assert.equal(relaysOf({}), null);
});

test("parses_the_client_messages_of_the_protocol", () => {
  assert.deepEqual(parseClientMessage({ id: 7, call: "job.stop", params: { station: "ws1/st1", id: "j1" } }), { kind: "call", id: 7, call: "job.stop", params: { station: "ws1/st1", id: "j1" } });
  assert.deepEqual(parseClientMessage({ id: 1, call: "auth.signOut" }), { kind: "call", id: 1, call: "auth.signOut", params: null });
  assert.deepEqual(parseClientMessage({ id: 4, subscribe: { topic: "chats", scope: "w", mine: true } }), { kind: "subscribe", id: 4, subscribe: { topic: "chats", scope: "w", mine: true } });
  assert.deepEqual(parseClientMessage({ id: 4, subscribe: { topic: "chats", scope: "ws" } }), { kind: "subscribe", id: 4, subscribe: { topic: "chats", scope: "ws", mine: false } });
  assert.deepEqual(parseClientMessage({ id: 5, subscribe: { topic: "chat", station: "w/s", thread: 7 } }), { kind: "subscribe", id: 5, subscribe: { topic: "chat", station: "w/s", thread: 7, session: null } });
  assert.deepEqual(parseClientMessage({ id: 6, subscribe: { topic: "chat", station: "w/s", session: "ds:C1:1.0" } }), { kind: "subscribe", id: 6, subscribe: { topic: "chat", station: "w/s", thread: null, session: "ds:C1:1.0" } });
  assert.deepEqual(parseClientMessage({ id: 8, subscribe: { topic: "session", station: "ws1/st1", key: "k" } }), { kind: "subscribe", id: 8, subscribe: { topic: "session", station: "ws1/st1", key: "k" } });
  assert.deepEqual(parseClientMessage({ id: 2, subscribe: { topic: "accounts" } }), { kind: "subscribe", id: 2, subscribe: { topic: "accounts" } });
  assert.deepEqual(parseClientMessage({ id: 3, subscribe: { topic: "workspace", workspace: "w" } }), { kind: "subscribe", id: 3, subscribe: { topic: "workspace", workspace: "w" } });
  assert.deepEqual(parseClientMessage({ id: 8, unsubscribe: true }), { kind: "unsubscribe", id: 8, unsubscribe: true });
});

test("answers_take_the_shapes_of_the_protocol", () => {
  const wire = (m: unknown) => JSON.parse(JSON.stringify(m));
  assert.deepEqual(wire(answer(7, { ok: { url: "u" } })), { id: 7, ok: { url: "u" } });
  assert.deepEqual(wire(answer(7, { ok: null })), { id: 7, ok: null });
  assert.deepEqual(wire(answer(7, { err: new CoreError("forbidden", "没有权限", 403) })), { id: 7, error: { code: "forbidden", message: "没有权限", status: 403 } });
  assert.deepEqual(wire({ id: 8, delta: diff({ t: [1] }, { t: [1, 2] }) }), { id: 8, delta: [{ path: ["t"], append: [2] }] });
  assert.deepEqual(wire(answer(9, { err: new CoreError("unknown_call", "没有这个调用：x") })), { id: 9, error: { code: "unknown_call", message: "没有这个调用：x" } });
});

test("unknown_calls_are_refused", () => {
  assert.equal(code(() => parseCall("station.delete", {})), "unknown_call");
  assert.equal(code(() => parseCall("", null)), "unknown_call");
});

test("parses_each_call", () => {
  assert.deepEqual(parseCall("auth.begin", { redirect_uri: "r", return_to: "/", device_name: "Mac" }), { kind: "authBegin", redirectUri: "r", returnTo: "/", deviceName: "Mac" });
  assert.deepEqual(parseCall("auth.complete", { query: "?code=c&state=s" }), { kind: "authComplete", query: "?code=c&state=s" });
  assert.deepEqual(parseCall("auth.signOut", { account: "sub1" }), { kind: "signOut", account: "sub1" });
  assert.deepEqual(parseCall("client.error", { source: "android.decode", message: "chat: 读不懂" }), { kind: "clientError", source: "android.decode", message: "chat: 读不懂" });
  assert.deepEqual(parseCall("workspace.rename", { account: "a", workspace: "w", name: "n" }), {
    kind: "op",
    op: { target: { cloud: "a" }, method: "PATCH", path: "/v1/workspaces/w", body: { name: "n" }, fallback: null, effect: { kind: "none" } },
  });
  assert.deepEqual(parseCall("job.stop", { station: "ws/st", id: "j1" }), {
    kind: "op",
    op: { target: { station: "ws/st" }, method: "POST", path: "/jobs/j1/stop", body: null, fallback: null, effect: { kind: "job" } },
  });
  assert.equal(code(() => parseCall("station.request", { station: "ws/st", method: "GET", path: "/sessions" })), "unknown_call");
  assert.equal(code(() => parseCall("cloud.request", { account: "a", method: "GET", path: "/v1/me" })), "unknown_call");
  const part = parseCall("station.upload.part", { station: "w/s", id: "abcdefgh12", name: "a.bin", size: 10, offset: 4, bytes: "aGVsbG8=" });
  assert.deepEqual({ ...part, bytes: [...(part as { bytes: Uint8Array }).bytes] }, { kind: "stationUploadPart", station: "w/s", id: "abcdefgh12", name: "a.bin", size: 10, offset: 4, bytes: [...new TextEncoder().encode("hello")] });
  const upload = parseCall("station.upload", { station: "w/s", name: "a.png", bytes: "aGVsbG8=" });
  assert.deepEqual({ ...upload, bytes: [...(upload as { bytes: Uint8Array }).bytes] }, { kind: "stationUpload", station: "w/s", name: "a.png", bytes: [...new TextEncoder().encode("hello")] });
  assert.deepEqual(parseCall("station.file", { station: "w/s", key: "k", name: "a.png" }), { kind: "stationFile", station: "w/s", key: "k", name: "a.png", thumb: false, progress: false });
  assert.deepEqual(parseCall("station.file", { station: "w/s", key: "k", name: "a.png", thumb: true }), { kind: "stationFile", station: "w/s", key: "k", name: "a.png", thumb: true, progress: false });
  assert.deepEqual(parseCall("station.file", { station: "w/s", key: "k", name: "a.png", progress: true }), { kind: "stationFile", station: "w/s", key: "k", name: "a.png", thumb: false, progress: true });
  assert.deepEqual(parseCall("chat.send", { station: "w/s", thread: 7, text: "hi" }), { kind: "chatSend", station: "w/s", thread: 7, text: "hi", attachments: [], quotes: [], client: null });
  assert.deepEqual(parseCall("chat.send", { station: "w/s", thread: 7, text: "hi", client: "android 0.1.1123" }), { kind: "chatSend", station: "w/s", thread: 7, text: "hi", attachments: [], quotes: [], client: "android 0.1.1123" });
  assert.deepEqual(parseCall("chat.retry", { station: "w/s", thread: 7, id: "out-1" }), { kind: "chatRetry", station: "w/s", thread: 7, id: "out-1" });
  assert.deepEqual(parseCall("chat.discard", { station: "w/s", thread: 7, id: "out-1" }), { kind: "chatDiscard", station: "w/s", thread: 7, id: "out-1" });
  assert.deepEqual(parseCall("chat.older", { station: "w/s", thread: 7 }), { kind: "chatOlder", station: "w/s", thread: 7 });
  assert.deepEqual(parseCall("history.older", { station: "w/s", key: "ember:c-1" }), { kind: "historyOlder", station: "w/s", key: "ember:c-1" });
  assert.deepEqual(parseCall("station.measure", { station: "w/s" }), { kind: "stationMeasure", station: "w/s" });
  assert.deepEqual(parseCall("chat.read", { station: "w/s", thread: 7, seq: 12 }), { kind: "chatRead", station: "w/s", thread: 7, seq: 12 });
  assert.equal(code(() => parseCall("chat.send", { station: "w/s", key: "k", text: "hi" })), "invalid_params");
  assert.deepEqual(parseCall("chat.create", { station: "w/s", runtime: "claude", model: "opus", effort: "" }), { kind: "chatCreate", station: "w/s", ask: { runtime: "claude", model: "opus" } });
  assert.deepEqual(parseCall("chat.send", { station: "w/s", session: "new:1-1", text: "hi" }), { kind: "chatSendTo", station: "w/s", session: "new:1-1", text: "hi", attachments: [], quotes: [], client: null });
  assert.deepEqual(parseCall("chat.retry", { station: "w/s", session: "k", id: "out-1" }), { kind: "chatRetryIn", station: "w/s", session: "k", id: "out-1" });
  assert.deepEqual(parseCall("decision.answer", { station: "w/s", thread: 7, seq: 4, option: " 先不改 " }), { kind: "decisionAnswer", station: "w/s", thread: 7, seq: 4, option: "先不改" });
  assert.equal(code(() => parseCall("decision.answer", { station: "w/s", thread: 7, seq: 4, option: " " })), "invalid_params");
  assert.equal(code(() => parseCall("decision.answer", { station: "w/s", thread: 7, option: "x" })), "invalid_params");
  assert.deepEqual(parseCall("decision.defer", { station: "w/s", thread: 7, seq: 4 }), { kind: "decisionDefer", station: "w/s", thread: 7, seq: 4 });
  assert.equal(code(() => parseCall("decision.defer", { station: "w/s", thread: 7 })), "invalid_params");
  assert.deepEqual(parseCall("decision.reply", { station: "w/s", thread: 7, seq: 4, text: " sk_test_1 " }), { kind: "decisionReply", station: "w/s", thread: 7, seq: 4, text: "sk_test_1", attachments: [], quotes: [] });
  assert.equal(code(() => parseCall("decision.reply", { station: "w/s", thread: 7, seq: 4, text: "  " })), "invalid_params");
  assert.equal(code(() => parseCall("decision.reply", { station: "w/s", thread: 7, text: "x" })), "invalid_params");
  assert.deepEqual(parseCall("chat.discard", { station: "w/s", session: "k", id: "out-1" }), { kind: "chatDiscardIn", station: "w/s", session: "k", id: "out-1" });
});

test("checks_params", () => {
  try {
    parseCall("auth.begin", { redirect_uri: "r" });
    assert.fail("parsed");
  } catch (e) {
    assert.equal((e as CoreError).code, "invalid_params");
    assert.ok((e as CoreError).message.includes("return_to"), (e as CoreError).message);
  }
  assert.equal(code(() => parseCall("auth.signOut", null)), "invalid_params");
  assert.equal(code(() => parseCall("workspace.rename", { account: "a", name: "n" })), "invalid_params");
  assert.equal(code(() => parseCall("station.upload", { station: "w/s", name: "n", bytes: "not base64!" })), "invalid_params");
});

test("migrate_takes_accounts_and_a_32_byte_device_key", () => {
  const key = base64(new Uint8Array(32).fill(7));
  const m = parseCall("migrate", { accounts: [{ sub: "s" }], device: key }) as { accounts: unknown; device: Uint8Array };
  assert.deepEqual([m.accounts, [...m.device]], [[{ sub: "s" }], [...new Uint8Array(32).fill(7)]]);
  assert.deepEqual(parseCall("migrate", { accounts: null }), { kind: "migrate", accounts: null, device: null });
  assert.deepEqual(parseCall("migrate", null), { kind: "migrate", accounts: null, device: null });
  assert.equal(code(() => parseCall("migrate", { device: base64(new Uint8Array(16).fill(1)) })), "invalid_params");
  assert.ok(fromBase64(key));
});

test("a_kept_credential_reaches_the_stations_without_ember_cloud", async () => {
  const host = new FakeHost();
  host.store(STORAGE_KEY, [account("s1", "a@x.com", "阿一", "a", "r", nowS() + 3600)]);
  let up = true;
  let asked = 0;
  host.onFetch((req) => {
    const path = req.url.replace("https://stillfail.test", "");
    if (!up) throw new HostError("offline");
    if (path === "/v1/me") return jsonResponse(200, { workspaces: [{ id: "ws", name: "W" }], invitations: [], relay_url: "https://relay.test" });
    if (path === "/v1/workspaces/ws/credential") {
      asked++;
      return jsonResponse(200, { credential: `c${asked}`, issued_at: nowS(), expires_at: nowS() + 30 * 86400, relay_url: "https://relay.test" });
    }
    return jsonResponse(404, { error: "not_found" });
  });
  const core = await Core.create(host, { clock: host.time.clock });
  const inner = core.inner;
  const credential = (fresh: boolean) => run(inner.cloudSync.credential("ws", "dev", fresh, null));
  const kept = (c: object, device = "dev") => toJsonBytes({ device, ...c });
  assert.equal((await credential(false)).credential, "c1");
  assert.equal((await credential(false)).credential, "c1");
  assert.equal(asked, 1);
  assert.equal((await credential(true)).credential, "c2");
  const old = { credential: "old", issued_at: nowS() - 2 * 86400, expires_at: nowS() + 28 * 86400, relay_url: "https://relay.test" };
  host.store(`${CREDENTIAL_KEY}/s1/ws`, kept(old));
  up = false;
  assert.equal((await credential(false)).credential, "old");
  await assert.rejects(credential(true));
  host.store(`${CREDENTIAL_KEY}/s1/ws`, kept({ ...old, expires_at: nowS() - 1 }));
  await assert.rejects(credential(false));
  host.store(`${CREDENTIAL_KEY}/s1/ws`, kept(old));
  up = true;
  assert.equal((await credential(false)).credential, "c3");
  host.store(`${CREDENTIAL_KEY}/s1/ws`, kept(old, "other"));
  assert.equal((await credential(false)).credential, "c4");
  await run(inner.accounts.signOut("s1"));
  await host.time.pass(10);
  assert.equal(host.stored(`${CREDENTIAL_KEY}/s1/ws`), undefined);
  core.close();
});

test("an_accounts_devices_are_a_topic_read_again_after_a_write", async () => {
  const { host, core } = await cloudCore();
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "loginSessions", account: "s1" });
  await host.settle();
  apply(host, values);
  assert.deepEqual(values.get(1), [{ id: "d1", current: true }]);
  const before = count(host, "/v1/auth/sessions");
  call(core, ui, 2, "loginSession.revoke", { account: "s1", id: "d2" });
  await host.settle();
  assert.equal(count(host, "/v1/auth/sessions"), before + 1);
  core.close();
});

test("what_a_person_does_is_under_way_until_it_answers_and_reads_are_not", async () => {
  const { host, core } = await cloudCore();
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "doing" });
  await host.settle();
  apply(host, values);
  assert.deepEqual(values.get(1), { doing: [] });
  call(core, ui, 2, "loginSession.revoke", { account: "s1", id: "d2" });
  call(core, ui, 3, "admin.me", { account: "s1" });
  const doing = core.inner.doing.value(() => false) as { doing: Record<string, unknown>[] };
  assert.equal(doing.doing.length, 1);
  assert.equal(doing.doing[0].call, "loginSession.revoke");
  assert.deepEqual(doing.doing[0].params, { account: "s1", id: "d2" });
  await host.settle();
  apply(host, values);
  assert.deepEqual(values.get(1), { doing: [] });
  core.close();
});

test("what_was_known_shows_after_a_restart_with_no_network", async () => {
  const { host, core } = await cloudCore();
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "workspaces" });
  subscribe(core, ui, 2, { topic: "workspace", workspace: "ws" });
  await host.settle();
  core.close();
  host.takeEmitted();
  host.onFetch(() => jsonResponse(503, { error: "unavailable" }));
  const again = await Core.create(host, { clock: host.time.clock });
  const ui2 = again.connect();
  const values = new Map();
  subscribe(again, ui2, 1, { topic: "workspaces" });
  subscribe(again, ui2, 2, { topic: "workspace", workspace: "ws" });
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 1)[0].workspaces[0].id, "ws");
  assert.equal(v(values, 1)[0].loaded, false);
  assert.equal(v(values, 2).stations[0].id, "st");
  // (The chats view's `me` from what was kept: views.ts, below.)
  assert.equal(again.inner.workspaces.owner("ws"), "s1");
  again.close();
});

test("account_topics_follow_the_cloud_socket", async () => {
  const { host, core } = await cloudCore();
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "workspaces" });
  subscribe(core, ui, 2, { topic: "workspace", workspace: "ws" });
  await host.settle();
  assert.deepEqual(
    host.sockets.map((s) => [s.url, s.protocols]),
    [["wss://stillfail.test/v1/events", ["stillfail-events", "stillfail-token.fresh-1"]]],
  );
  assert.deepEqual([count(host, "/v1/me"), count(host, "/v1/workspaces/ws")], [1, 1]);
  apply(host, values);
  assert.equal(v(values, 1)[0].workspaces[0].id, "ws");
  assert.equal(v(values, 1)[0].loaded, true);
  assert.equal(v(values, 2).stations[0].id, "st");
  await host.time.pass((EVICT_AFTER_MS * 5) / 4, 500);
  assert.equal(host.openSockets("/v1/events"), 1);
  core.close();
});

test("a_refused_socket_still_reads_the_topics_and_retries_with_backoff", async () => {
  const { host, core } = await cloudCore();
  host.refuseSockets = true;
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "workspaces" });
  await host.settle();
  assert.equal(count(host, "/v1/me"), 1, "read although the socket did not open");
  await host.time.pass(SOCKET_RETRY_MS * 7, 50);
  const doubling = [1_000, 2_000, 4_000];
  for (const wait of host.time.sleeps) if (doubling[0] === wait) doubling.shift();
  assert.deepEqual(doubling, [], JSON.stringify(host.time.sleeps));
  assert.equal(count(host, "/v1/me"), 1, "failed retries read nothing");
  host.refuseSockets = false;
  await host.time.pass(SOCKET_RETRY_MS * 10, 50);
  await host.settle();
  assert.equal(host.openSockets("/v1/events"), 1);
  assert.equal(count(host, "/v1/me"), 2, "read again once it opened");
  core.close();
});

test("back_after_being_away_a_socket_waiting_to_retry_tries_at_once", async () => {
  const { host, core } = await cloudCore();
  host.refuseSockets = true;
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "workspaces" });
  await host.settle();
  await host.time.pass(SOCKET_RETRY_MS * 40, 100);
  host.refuseSockets = false;
  assert.equal(host.openSockets("/v1/events"), 0);
  host.takeEmitted();
  call(core, ui, 9, "client.wake", { away: 60_000 });
  await host.time.pass(0);
  assert.equal(host.openSockets("/v1/events"), 1);
  assert.ok(host.takeEmitted().some(([, m]) => JSON.stringify(m) === JSON.stringify({ id: 9, ok: {} })));
  core.close();
});

test("a_socket_that_answered_pings_and_went_silent_is_opened_again", async () => {
  const { host, core } = await cloudCore();
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "workspaces" });
  await host.settle();
  const opened = host.sockets.length;
  assert.equal(host.openSockets("/v1/events"), 1);
  await host.time.pass(SOCKET_IDLE_MS * 2, 500);
  assert.equal(host.sockets.length, opened);
  host.socketSend("/v1/events", "pong");
  await host.time.pass(SOCKET_IDLE_MS / 2, 500);
  assert.equal(host.sockets.length, opened, "answered a while ago: still there");
  await host.time.pass(SOCKET_IDLE_MS, 500);
  assert.equal(host.sockets.length, opened + 1, "silent past its pings: opened again");
  assert.equal(host.openSockets("/v1/events"), 1);
  core.close();
});

test("a_released_app_says_nothing_of_a_channel", async () => {
  const { host, core } = await cloudCore();
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "workspaces" });
  await host.settle();
  assert.ok(count(host, "/v1/me") > 0);
  assert.ok(host.requests.every((r) => r.headers.every(([k]) => k !== "x-stillfail-channel")));
  const values = new Map();
  apply(host, values);
  assert.deepEqual([v(values, 1)[0].beta, v(values, 1)[0].blocked], [undefined, undefined]);
  core.close();
});

test("the_network_changing_opens_the_socket_again_at_once", async () => {
  const { host, core } = await cloudCore();
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "workspaces" });
  await host.settle();
  const opened = host.sockets.length;
  host.socketSend("/v1/events", "pong");
  await host.time.pass(0);
  call(core, ui, 9, "client.wake", { away: 0, network: true });
  await host.time.pass(0);
  assert.equal(host.sockets.length, opened + 1);
  assert.equal(host.openSockets("/v1/events"), 1);
  assert.equal(host.resets, 1, "the host let its connections go");
  core.close();
});

async function stationCore() {
  const host = new FakeHost();
  signIn(host);
  stationAnswers(host, () => jsonResponse(404, {}));
  const core = await Core.create(host, { clock: host.time.clock, sample: 0 });
  return { host, core };
}

test("prefs_are_kept_on_the_device_and_moved_in_once_without_writing_over", async () => {
  const { host, core } = await stationCore();
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "prefs" });
  await host.settle();
  const values = new Map();
  apply(host, values);
  assert.deepEqual([v(values, 1).onlyMine, v(values, 1).appearance, v(values, 1).rowPicture], [false, "system", "auto"]);
  assert.equal(v(values, 1).device.app, "");
  let id = 0;
  const set = (n: number, params: unknown) => call(core, ui, n, "prefs.set", params);
  set(2, { onlyMine: true, appearance: "dark", lastChat: { w1: "/w/w1/s/st/chats/k1", ws: "/w/ws/new" }, chatTabs: { "ws/st:t": { tabs: ["k1"], active: "k1" } } });
  await host.settle();
  apply(host, values);
  assert.deepEqual([v(values, 1).onlyMine, v(values, 1).appearance], [true, "dark"]);
  assert.deepEqual(v(values, 1).chatTabs["ws/st:t"], { tabs: ["k1"], active: "k1" });
  set(20, { onlyWatching: true });
  await host.settle();
  apply(host, values);
  assert.deepEqual([v(values, 1).onlyMine, v(values, 1).onlyWatching], [false, true]);
  set(21, { onlyMine: true });
  await host.settle();
  apply(host, values);
  assert.deepEqual([v(values, 1).onlyMine, v(values, 1).onlyWatching], [true, false]);
  set(22, { onlyDecisions: true });
  await host.settle();
  apply(host, values);
  assert.deepEqual([v(values, 1).onlyMine, v(values, 1).onlyWatching, v(values, 1).onlyDecisions], [false, false, true]);
  set(23, { onlyWatching: true });
  await host.settle();
  apply(host, values);
  assert.deepEqual([v(values, 1).onlyWatching, v(values, 1).onlyDecisions], [true, false]);
  set(24, { onlyMine: true });
  await host.settle();
  apply(host, values);
  set(3, { lastChat: { ws: null } });
  set(4, { fill: true, appearance: "light", rowPicture: "people", lastChat: { w1: "/w/w1/s/st/chats/old", other: "/w/other/new" } });
  await host.settle();
  apply(host, values);
  assert.deepEqual([v(values, 1).appearance, v(values, 1).rowPicture], ["dark", "people"]);
  assert.deepEqual(v(values, 1).lastChat, { w1: "/w/w1/s/st/chats/k1", other: "/w/other/new" });
  set(5, { appearance: "blue" });
  set(6, { device: { app: "web" } });
  await host.settle();
  const refused = host.takeEmitted().filter(([, m]) => "error" in m && (m.id === 5 || m.id === 6)).length;
  assert.equal(refused, 2);
  set(7, { invite: "ABCD-EFGH" });
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 1).invite, "ABCD-EFGH");
  prefs.inviteUsed(core.inner.data);
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 1).invite, undefined);
  call(core, ui, 80, "station.updateNotice", { station: "ws/st", action: "dismiss", version: "stable:2" });
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 1).stationUpdatesDismissed["ws/st"], "stable:2");
  await run(core.inner.data.written);
  core.close();
  const again = await Core.create(host, { clock: host.time.clock, sample: 0 });
  const ui2 = again.connect();
  subscribe(again, ui2, 1, { topic: "prefs" });
  await host.settle();
  const values2 = new Map();
  apply(host, values2);
  assert.deepEqual([v(values2, 1).onlyMine, v(values2, 1).appearance, v(values2, 1).lastChat.w1], [true, "dark", "/w/w1/s/st/chats/k1"]);
  assert.equal(v(values2, 1).stationUpdatesDismissed["ws/st"], "stable:2");
  assert.equal(v(values2, 1).stationUpdatesDismissed["other/st"], undefined);
  for (let i = 0; i < 205; i++) {
    call(again, ui2, 10 + i, "prefs.set", { chatTabs: { [`ws/st:${i}`]: { tabs: [], active: null } } });
    await host.settle();
  }
  apply(host, values2);
  const tabs = v(values2, 1).chatTabs;
  assert.equal(Object.keys(tabs).length, 200);
  assert.ok("ws/st:204" in tabs && !("ws/st:4" in tabs) && !("ws/st:t" in tabs));
  void id;
  again.close();
});

test("the_language_is_as_chosen_else_as_the_device_is", async () => {
  const { host, core } = await stationCore();
  const ui = core.connect();
  subscribe(core, ui, 1, { topic: "prefs" });
  await host.settle();
  const values = new Map();
  apply(host, values);
  assert.equal(v(values, 1).lang, undefined);
  const mac = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36";
  call(core, ui, 2, "client.device", { app: "web", userAgent: mac, locale: "en-US" });
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 1).lang, "en");
  assert.equal(prefs.deviceName(core.inner.data), "still.fail Web · Chrome · macOS");
  const set = (n: number, params: unknown) => call(core, ui, n, "prefs.set", params);
  set(3, { language: "zh" });
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 1).lang, "zh");
  set(4, { language: null });
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 1).lang, "en");
  set(5, { language: "fr" });
  await host.settle();
  assert.ok(host.takeEmitted().some(([, m]) => "error" in m && m.id === 5));
  call(core, ui, 6, "client.device", { app: "web", userAgent: mac, locale: "zh-CN" });
  set(7, { language: "en" });
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 1).lang, "en");
  assert.equal(current(), "zh");
  assert.equal(tr("en", "core-misc.params.missing", { field: "x" }), "Invalid params: missing x");
  core.close();
});

test("a_draft_is_kept_on_the_device_until_emptied", async () => {
  const { host, core } = await stationCore();
  const ui = core.connect();
  const topic = { topic: "draft", station: "ws/st", chat: "new" };
  subscribe(core, ui, 1, topic);
  await host.settle();
  const values = new Map();
  apply(host, values);
  assert.deepEqual(values.get(1), { text: "", quotes: [], files: [] });
  call(core, ui, 2, "draft.put", { station: "ws/st", chat: "new", text: "修一下登录", quotes: [{ author: "a", text: "b", comment: "" }], files: [{ name: "x.png", path: "up/x.png", size: 3 }] });
  await host.settle();
  apply(host, values);
  assert.equal(v(values, 1).text, "修一下登录");
  assert.equal(v(values, 1).files[0].path, "up/x.png");
  await host.time.pass(350);
  await run(core.inner.data.written);
  core.close();
  host.takeEmitted();
  let again = await Core.create(host, { clock: host.time.clock, sample: 0 });
  let ui2 = again.connect();
  subscribe(again, ui2, 1, topic);
  await host.settle();
  let values2 = new Map();
  apply(host, values2);
  assert.equal(v(values2, 1).text, "修一下登录");
  assert.equal(v(values2, 1).quotes[0].author, "a");
  call(again, ui2, 2, "draft.put", { station: "ws/st", chat: "new", text: " ", quotes: [], files: [] });
  await host.settle();
  apply(host, values2);
  assert.deepEqual(values2.get(1), { text: "", quotes: [], files: [] });
  await run(again.inner.data.written);
  again.close();
  again = await Core.create(host, { clock: host.time.clock, sample: 0 });
  ui2 = again.connect();
  subscribe(again, ui2, 1, topic);
  await host.settle();
  values2 = new Map();
  apply(host, values2);
  assert.equal(v(values2, 1).text, "");
  call(again, ui2, 3, "draft.put", { station: "ws/st", chat: "new", text: 3 });
  call(again, ui2, 4, "draft.put", { chat: "new", text: "x" });
  await host.settle();
  const refused = host.takeEmitted().filter(([, m]) => "error" in m && (m.id === 3 || m.id === 4)).length;
  assert.equal(refused, 2);
  again.close();
});

test("encodes_path_segments_like_encode_uri_component", () => {
  assert.equal(encode("ws_01-a.b~"), "ws_01-a.b~");
  assert.equal(encode("a/b c?"), "a%2Fb%20c%3F");
  assert.equal(encode("工"), "%E5%B7%A5");
});

void answers;
void parseJson;
