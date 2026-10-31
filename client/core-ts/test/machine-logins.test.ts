// A station's logins in the core (docs/remote-login.md): read when its stream opens and told as they change, shown in
// words; a station from before has none; a terminal's screen told on the stream while it is shown; a loopback login's
// callback taken on this device (a host that can listen) and handed to the station, only the one it waits for, once.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Effect, Queue } from "effect";
import type { LoopbackRequest, Pull } from "../src/host.ts";
import { HostError } from "../src/error.ts";
import { AFTER_MS, isCallback, toolMark } from "../src/station/machine-logins.ts";
import { apply as applyOps } from "../src/delta.ts";
import type { FakeHost } from "../src/testing.ts";
import { answers, call, subscribe, v } from "./helpers.ts";
import { base, started, stationReplies } from "./station-fixture.ts";

const ST = "ws/st";

const device = { id: "l1", name: "gh", command: ["gh", "auth", "login"], state: "code", step: "device", url: "https://github.com/login/device", domain: "github.com", code: "1A2B-C3D4", waiting: false, by: { email: "a@x.com", name: "张三" }, chat: "ember:c-1", chatTitle: "部署", startedAt: Date.UTC(2026, 9, 12, 4), expiresAt: 2 };
const past = { id: "l0", name: "npm", command: ["npm", "login"], state: "done", waiting: false, by: { email: "b@x.com", name: "李四" }, doneBy: { email: "c@x.com", name: "王五" }, startedAt: Date.UTC(2026, 9, 11, 4), expiresAt: 2, endedAt: Date.UTC(2026, 9, 11, 4, 3) };
const loopback = { id: "l2", name: "gcloud", command: ["gcloud", "auth", "login"], state: "browser", step: "loopback", url: "https://accounts.google.com/o/oauth2/auth?redirect_uri=http%3A%2F%2Flocalhost%3A8085%2F&state=s3", domain: "accounts.google.com", callback: { host: "localhost", port: 8085, path: "/", state: "s3", post: false }, waiting: false, by: { email: "a@x.com", name: "张三" }, startedAt: 3, expiresAt: 4 };

/// What the core sent since: each subscription's value (deltas applied) into `values`; the messages, for the answers.
function drain(host: FakeHost, values: Map<number, unknown>) {
  const emitted = host.takeEmitted();
  for (const [, message] of emitted) {
    const m = message as Record<string, unknown>;
    if ("value" in m) values.set(m.id as number, m.value);
    else if ("delta" in m) values.set(m.id as number, applyOps(values.get(m.id as number), m.delta as never));
  }
  return emitted;
}

const listed = () => ({ ...base(), "GET /machine-logins": { logins: [device, loopback, past] } });

test("a station's logins: read as its stream opens, in words, told as they change; a station from before has none", async () => {
  const { host, core, push } = await started(listed());
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "machineLogins", station: ST });
  subscribe(core, ui, 2, { topic: "machineLogin", station: ST, id: "l1" });
  subscribe(core, ui, 3, { topic: "machineLogin", station: ST, id: "nope" });
  await host.settle();
  drain(host, values);
  const all = v(values, 1);
  assert.deepEqual([all.supported, all.loaded, all.canLogin, all.canRelay], [true, true, true, false]);
  assert.equal(all.services, undefined, "no list of services: any login command, one way");
  const one = v(values, 2);
  assert.deepEqual([one.title, one.command, one.statusText, one.code, one.url, one.domain, one.active, one.byText], ["在 studio 上登录 gh", "gh auth login", "验证码 1A2B-C3D4", "1A2B-C3D4", "https://github.com/login/device", "github.com", true, "张三"]);
  assert.match(one.whenText, /^10\/12 \d{1,2}:\d{2}$/);
  assert.deepEqual([one.chat, one.chatTitle], ["ember:c-1", "部署"]);
  const done = all.logins.find((l: any) => l.id === "l0");
  assert.deepEqual([done.statusText, done.active, done.byText, done.doneByText, done.command], ["登录完成", false, "李四", "王五 完成", "npm login"]);
  // Ended, its card is a line.
  assert.equal(done.endedText, "已在 studio 上登录 npm");
  assert.equal(one.endedText, undefined, "under way: a card, no line");
  assert.equal(v(values, 3), null, "a login the station does not have");
  assert.equal(all.logins.find((l: any) => l.id === "l2").statusText, "等你打开浏览器");
  // Told as it ends: in place.
  push("machine-logins", { login: { ...device, state: "failed", step: undefined, code: undefined, error: "gh: device code expired", endedAt: Date.UTC(2026, 9, 12, 5) } });
  await host.settle();
  drain(host, values);
  const failed = v(values, 2);
  assert.deepEqual([failed.statusText, failed.active, failed.error, failed.code, failed.step], ["登录失败", false, "gh: device code expired", undefined, undefined]);
  assert.equal(failed.endedText, "在 studio 上登录 gh 失败：gh: device code expired");
  // Under way first, then those ended, the newest first.
  assert.deepEqual(v(values, 1).logins.map((l: any) => l.id), ["l2", "l1", "l0"]);
  core.close();

  // A station from before: GET /machine-logins is no route.
  const old = await started();
  const ui2 = old.core.connect();
  const values2 = new Map();
  subscribe(old.core, ui2, 1, { topic: "machineLogins", station: ST });
  await old.host.settle();
  drain(old.host, values2);
  assert.deepEqual([v(values2, 1).supported, v(values2, 1).loaded, v(values2, 1).logins], [false, true, []]);
  old.core.close();
});

test("those ended, a row per program: who last logged in to it, else how its latest ended; the tool tried latest first", async () => {
  const at = (h: number) => Date.UTC(2026, 9, 12, h);
  const ended = (id: string, name: string, h: number, more: object) => ({ id, name, command: [name, "auth", "login"], waiting: false, chat: `ember:${id}`, chatTitle: `t-${id}`, startedAt: at(h), expiresAt: 2, endedAt: at(h) + 60_000, ...more });
  const g1 = ended("g1", "gcloud", 1, { state: "done", doneBy: { email: "z@x.com", name: "Zanwei Guo" } });
  const g2 = ended("g2", "gcloud", 2, { state: "cancelled" });
  const g3 = ended("g3", "gcloud", 3, { state: "failed", timedOut: true });
  const h1 = ended("h1", "gh", 4, { state: "failed", error: "gh: device code expired" });
  const { host, core } = await started({ ...base(), "GET /machine-logins": { logins: [g1, h1, device, g3, g2] } });
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "machineLogins", station: ST });
  await host.settle();
  drain(host, values);
  const [gh, gcloud, ...more] = v(values, 1).tools;
  assert.deepEqual(more, [], "the gh under way is its card, not a try of a row");
  assert.deepEqual([gh.name, gh.failed, gh.countText, gh.chatTitle, gh.tries.map((l: any) => l.id)], ["gh", true, "1 次", "t-h1", ["h1"]]);
  assert.match(gh.summaryText, /^没有登录成功过 · 最近一次登录失败 · 10\/12 \d{1,2}:\d{2}$/);
  assert.deepEqual([gcloud.name, gcloud.failed, gcloud.countText, gcloud.chat, gcloud.tries.map((l: any) => l.id)], ["gcloud", false, "3 次", "ember:g1", ["g3", "g2", "g1"]]);
  assert.match(gcloud.summaryText, /^Zanwei Guo 登录 · 10\/12 \d{1,2}:\d{2}$/, "the one that went through, though two tried after it");
  assert.deepEqual([gh.mark, gcloud.mark, toolMark("python3"), toolMark("mytool")], ["github", "google-cloud", "python", undefined], "its maker's mark, none for a program not known");
  core.close();
});

test("a login's terminal: its stream asks for it while it is shown, all of it first, then the rows that changed", async () => {
  const { host, core, push, streams } = await started(listed());
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "machineLoginScreen", station: ST, id: "l1" });
  await host.settle();
  assert.ok(streams.some((s) => !s.closed && s.path.includes("login=l1")), streams.map((s) => s.path).join(" "));
  drain(host, values);
  assert.equal(v(values, 1), null, "nothing told yet");
  push("login-screen", { id: "l1", full: true, rows: { 0: "? Authenticate Git (Y/n)", 1: "", 2: "Username: " }, cursor: { x: 10, y: 2 }, echo: true, live: true });
  await host.settle();
  drain(host, values);
  assert.deepEqual(v(values, 1), { rows: ["? Authenticate Git (Y/n)", "", "Username: "], cursorX: 10, cursorY: 2, echo: true, live: true });
  push("login-screen", { id: "l1", rows: { 2: "Username: alice", 3: "Password: " }, cursor: { x: 10, y: 3 }, echo: false, live: true });
  await host.settle();
  drain(host, values);
  assert.deepEqual(v(values, 1).rows, ["? Authenticate Git (Y/n)", "", "Username: alice", "Password: "]);
  assert.equal(v(values, 1).echo, false);
  // Not shown any more: the stream lets it go.
  core.receive(ui, { kind: "unsubscribe", id: 1, unsubscribe: true });
  await host.time.pass(120_000, 1_000);
  assert.ok(!streams.some((s) => !s.closed && s.path.includes("login=l1")));
  core.close();
});

test("cancelling: the station's answer is in place at once; nothing else a client writes but the callback and a page's code", async () => {
  const { host, core } = await started(listed());
  const asked: { method: string; path: string }[] = [];
  stationReplies(host, (req) => {
    const path = req.url.replace("https://stillfail.test/admin/api", "");
    if (!path.startsWith("/machine-logins/")) return undefined;
    asked.push({ method: req.method, path });
    return { ...device, state: "cancelled", step: undefined, code: undefined, doneBy: { email: "a@x.com", name: "张三" }, endedAt: Date.UTC(2026, 9, 12, 5) };
  });
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "machineLogin", station: ST, id: "l1" });
  await host.settle();
  call(core, ui, 2, "machineLogin.cancel", { station: ST, id: "l1" });
  await host.settle();
  drain(host, values);
  assert.deepEqual(asked, [{ method: "DELETE", path: "/machine-logins/l1" }]);
  assert.deepEqual([v(values, 1).statusText, v(values, 1).doneByText, v(values, 1).endedText], ["已取消", "张三 取消", "张三 取消了在 studio 上登录 gh"]);
  // Starting one, or typing into one, is its agent's (the login tool), not a client's.
  call(core, ui, 3, "machineLogin.start", { station: ST, command: "gh auth login" });
  call(core, ui, 4, "machineLogin.input", { station: ST, id: "l1", key: "Enter" });
  await host.settle();
  const emitted = host.takeEmitted();
  assert.ok(answers(emitted, 3)?.error && answers(emitted, 4)?.error);
  core.close();
});

test("a page that gives a code to paste back: the person's on the card (not waiting on its agent), sent to the station as its answer", async () => {
  const paste = { id: "l3", name: "gcloud", command: ["gcloud", "auth", "login", "--no-launch-browser"], state: "browser", step: "open", url: "https://accounts.google.com/o/oauth2/auth?redirect_uri=https%3A%2F%2Fsdk.cloud.google.com%2Fauthcode.html&state=s4", domain: "accounts.google.com", waiting: true, paste: true, by: { email: "a@x.com", name: "张三" }, startedAt: 3, expiresAt: 4 };
  const { host, core } = await started({ ...base(), "GET /machine-logins": { logins: [paste] } });
  const asked: { method: string; path: string; body: string }[] = [];
  stationReplies(host, (req) => {
    const path = req.url.replace("https://stillfail.test/admin/api", "");
    if (!path.startsWith("/machine-logins/")) return undefined;
    asked.push({ method: req.method, path, body: new TextDecoder().decode(req.body as Uint8Array) });
    return { ...paste, state: "verifying", waiting: false, paste: undefined };
  });
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "machineLogin", station: ST, id: "l3" });
  await host.settle();
  drain(host, values);
  assert.deepEqual([v(values, 1).paste, v(values, 1).waiting, v(values, 1).step, v(values, 1).statusText], [true, false, "open", "在浏览器里登录，再把页面给出的码贴回来"]);
  call(core, ui, 2, "machineLogin.answer", { station: ST, id: "l3", text: "4/0AXlq" });
  await host.settle();
  drain(host, values);
  assert.deepEqual(asked.map((a) => [a.method, a.path, JSON.parse(a.body).text]), [["POST", "/machine-logins/l3/answer", "4/0AXlq"]]);
  core.close();
});

test("a login the station's own browser can do: its button's words (back to it while its tab is open), its page opened there by the station, the screen to view answered", async () => {
  const inStation = { ...loopback, browser: true };
  const { host, core, push } = await started({ ...base(), "GET /machine-logins": { logins: [inStation, device] } });
  const asked: { method: string; path: string }[] = [];
  stationReplies(host, (req) => {
    const path = req.url.replace("https://stillfail.test/admin/api", "");
    if (!path.startsWith("/machine-logins/")) return undefined;
    asked.push({ method: req.method, path });
    return { screen: "browser:T9" };
  });
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "machineLogin", station: ST, id: "l2" });
  subscribe(core, ui, 2, { topic: "machineLogin", station: ST, id: "l1" });
  await host.settle();
  drain(host, values);
  assert.deepEqual([v(values, 1).browser, v(values, 1).screen, v(values, 1).browserText], [true, undefined, "在 studio 的浏览器中打开"]);
  call(core, ui, 3, "machineLogin.browser", { station: ST, id: "l2" });
  await host.settle();
  const emitted = drain(host, values);
  assert.deepEqual(asked, [{ method: "POST", path: "/machine-logins/l2/browser" }]);
  assert.deepEqual(answers(emitted, 3)?.ok, { screen: "browser:T9" });
  push("machine-logins", { login: { ...inStation, screen: "browser:T9" } });
  await host.settle();
  drain(host, values);
  assert.deepEqual([v(values, 1).screen, v(values, 1).browserText], ["browser:T9", "回到 studio 的浏览器"]);
  // Ended: nothing to open, there or here.
  push("machine-logins", { login: { ...inStation, state: "done", step: undefined, endedAt: 5 } });
  await host.settle();
  drain(host, values);
  assert.deepEqual([v(values, 1).browser, v(values, 1).browserText], [undefined, undefined]);
  // A station that cannot (no Chrome, or from before) says nothing of it.
  assert.equal(v(values, 2).browser, undefined);
  core.close();
});

/// Listeners as a desktop app's host has them, here a queue a test hands requests to; what was opened, and what each
/// request was answered.
function listeners(refuse: string[] = []) {
  const opened: { port: number; host: string; closed: boolean; queue: Queue.Queue<LoopbackRequest | null> }[] = [];
  const listen = (port: number, host: string) =>
    Effect.gen(function* () {
      if (refuse.includes(host)) return yield* Effect.fail(new HostError("EADDRINUSE"));
      const queue = yield* Queue.unbounded<LoopbackRequest | null>();
      const one = { port, host, closed: false, queue };
      opened.push(one);
      yield* Effect.addFinalizer(() => Effect.sync(() => (one.closed = true)));
      return { take: Queue.take(queue) } as Pull<LoopbackRequest>;
    });
  const ask = (host: string, method: string, path: string, headers: [string, string][], body = "") =>
    new Promise<{ status: number; body: string }>((resolve) => {
      const l = opened.find((o) => o.host === host && !o.closed)!;
      Queue.offerUnsafe(l.queue, { method, path, headers, body: new TextEncoder().encode(body), respond: (status, _h, b) => resolve({ status, body: new TextDecoder().decode(b) }) });
    });
  return { opened, listen, ask };
}

test("a loopback login's callback: listened for here once opened, the one it waits for relayed to the station once", async () => {
  const { host, core, push } = await started(listed());
  const l = listeners();
  host.listen = l.listen;
  const relayed: any[] = [];
  stationReplies(host, (req) => {
    if (!req.url.endsWith("/machine-logins/l2/callback")) return undefined;
    relayed.push(JSON.parse(new TextDecoder().decode(req.body!)));
    return { status: 200, headers: { "content-type": "text/html" }, body: Buffer.from("<h1>signed in</h1>").toString("base64") };
  });
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "machineLogins", station: ST });
  subscribe(core, ui, 2, { topic: "machineLogin", station: ST, id: "l2" });
  await host.settle();
  drain(host, values);
  assert.equal(v(values, 1).canRelay, true);
  // A device code's page opens as it is: nothing listens.
  call(core, ui, 3, "machineLogin.open", { station: ST, id: "l1" });
  await host.settle();
  assert.deepEqual(answers(drain(host, values), 3)?.ok, { url: "https://github.com/login/device" });
  assert.equal(l.opened.length, 0);
  // The station on this machine: the command takes its own callback.
  call(core, ui, 4, "machineLogin.open", { station: ST, id: "l2", here: true });
  await host.settle();
  assert.equal(l.opened.length, 0);
  call(core, ui, 5, "machineLogin.open", { station: ST, id: "l2" });
  await host.settle();
  assert.deepEqual(answers(drain(host, values), 5)?.ok, { url: loopback.url });
  assert.deepEqual(l.opened.map((o) => [o.host, o.port]), [["127.0.0.1", 8085], ["::1", 8085]], "localhost: both, for the browser may try either");
  drain(host, values);
  assert.deepEqual([v(values, 2).listening, v(values, 2).statusText], [true, "等浏览器回来"]);
  // Not the one it waits for: answered here, never sent.
  const wrong = [
    l.ask("127.0.0.1", "GET", "/?code=c&state=guess", [["Host", "localhost:8085"]]),
    l.ask("127.0.0.1", "GET", "/favicon.ico", [["Host", "localhost:8085"]]),
    l.ask("::1", "GET", "/?code=c&state=s3", [["Host", "evil.example:8085"]]),
    l.ask("127.0.0.1", "POST", "/?code=c&state=s3", [["Host", "localhost:8085"]]),
  ];
  await host.settle();
  for (const w of await Promise.all(wrong)) assert.equal(w.status, 404);
  assert.equal(relayed.length, 0);
  const right = l.ask("::1", "GET", "/?code=c0de&state=s3&scope=openid", [["Host", "localhost:8085"], ["User-Agent", "Safari"]]);
  await host.settle();
  assert.deepEqual(await right, { status: 200, body: "<h1>signed in</h1>" });
  assert.deepEqual(relayed, [{ method: "GET", path: "/?code=c0de&state=s3&scope=openid", headers: { host: "localhost:8085", "user-agent": "Safari" } }]);
  // After it, only a page saying it is done; then the listeners close.
  const after = l.ask("127.0.0.1", "GET", "/?code=c0de&state=s3", [["Host", "localhost:8085"]]);
  await host.settle();
  assert.equal((await after).status, 200);
  assert.equal(relayed.length, 1, "once");
  push("machine-logins", { login: { ...loopback, state: "done", endedAt: 9 } });
  await host.time.pass(AFTER_MS + 1_000, 500);
  assert.ok(l.opened.every((o) => o.closed));
  drain(host, values);
  assert.equal(v(values, 2).listening, false);
  core.close();
});

test("a loopback login's port taken on this device says so, on its card until opened again; a page that cannot listen cannot relay", async () => {
  const { host, core } = await started(listed());
  const ui = core.connect();
  const values = new Map();
  subscribe(core, ui, 1, { topic: "machineLogins", station: ST });
  await host.settle();
  call(core, ui, 2, "machineLogin.open", { station: ST, id: "l2" });
  await host.settle();
  assert.match(String((answers(drain(host, values), 2)?.error as any)?.message), /桌面或安卓 app/);
  const l = listeners(["127.0.0.1"]);
  host.listen = l.listen;
  call(core, ui, 3, "machineLogin.open", { station: ST, id: "l2" });
  await host.settle();
  assert.equal((answers(drain(host, values), 3)?.error as any)?.message, "本机 8085 端口被占用");
  // Said on its card too, until it is opened again.
  const l2 = () => (v(values, 1) as any).logins.find((x: any) => x.id === "l2");
  await host.settle();
  drain(host, values);
  assert.deepEqual([l2().relayText, l2().listening], ["本机 8085 端口被占用", false]);
  // Only ::1 refused (a machine without IPv6): 127.0.0.1 alone.
  const v6 = listeners(["::1"]);
  host.listen = v6.listen;
  call(core, ui, 4, "machineLogin.open", { station: ST, id: "l2" });
  await host.settle();
  assert.ok(answers(drain(host, values), 4)?.ok);
  assert.deepEqual(v6.opened.map((o) => o.host), ["127.0.0.1"]);
  await host.settle();
  drain(host, values);
  assert.deepEqual([l2().relayText, l2().listening], [undefined, true]);
  call(core, ui, 5, "machineLogin.open", { station: ST, id: "gone" });
  await host.settle();
  assert.equal((answers(drain(host, values), 5)?.error as any)?.status, 404);
  core.close();
});

test("only the callback a login waits for is taken: its Host, method, path and state; a form's state in its body", () => {
  const get = { port: 8085, hosts: ["127.0.0.1"], path: "/callback", state: "s", post: false };
  const ask = (method: string, path: string, host: string, body = "") => ({ method, path, headers: [["host", host]] as [string, string][], body: new TextEncoder().encode(body) });
  assert.ok(isCallback(get, ask("GET", "/callback?state=s&code=1", "127.0.0.1:8085")));
  assert.ok(isCallback(get, ask("GET", "/callback?state=s", "[::1]:8085")));
  assert.ok(!isCallback(get, ask("GET", "/callback?state=s", "localhost:9999")));
  assert.ok(!isCallback(get, ask("GET", "/callback/x?state=s", "localhost:8085")));
  assert.ok(!isCallback(get, ask("GET", "/callback", "localhost:8085")));
  const post = { ...get, path: "/", post: true };
  assert.ok(isCallback(post, ask("POST", "/", "localhost:8085", "code=1&state=s")));
  assert.ok(!isCallback(post, ask("POST", "/", "localhost:8085", "code=1&state=t")));
  assert.ok(!isCallback(post, ask("GET", "/?state=s", "localhost:8085")));
});
