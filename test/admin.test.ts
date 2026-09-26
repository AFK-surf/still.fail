import assert from "node:assert/strict";
import { generateKeyPairSync, sign } from "node:crypto";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { AccessGate } from "../src/admin/access.ts";
import { AdminApi } from "../src/admin/api.ts";
import { Connections, type Connection } from "../src/connections.ts";
import { Hub } from "../src/hub.ts";
import { InternalChat } from "../src/chat/internal.ts";
import { slackManifest } from "../src/admin/slack-manifest.ts";
import { SlackApiError, type SlackApps } from "../src/chat/slack-apps.ts";
import { LoginManager } from "../src/login.ts";
import { Settings } from "../src/settings.ts";
import { Store } from "../src/store.ts";
import { FakeChat, FakeDriver, message, settle } from "./fakes.ts";

class FakeConnection extends FakeChat implements Connection {
  readonly status = { connected: true, lastError: null };
  readonly identity = { team: "Acme", teamId: "T1", url: "https://acme.slack.com/", botUserId: "UBOT", botName: "ember" };
  started = 0;
  stopped = 0;
  override async start(): Promise<void> {
    this.started++;
  }
  override async stop(): Promise<void> {
    this.stopped++;
  }
  onStatus(): void {}
}

/** Follows an event stream (/events), gathering what it sends. */
async function follow(url: string, headers: Record<string, string> = {}) {
  const controller = new AbortController();
  const response = await fetch(url, { headers, signal: controller.signal });
  const events: { event: string; data: any }[] = [];
  const reader = response.body!.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  void (async () => {
    try {
      for (;;) {
        const { value, done } = await reader.read();
        if (done) return;
        buffer += decoder.decode(value, { stream: true });
        let end: number;
        while ((end = buffer.indexOf("\n\n")) >= 0) {
          const chunk = buffer.slice(0, end);
          buffer = buffer.slice(end + 2);
          const event = /^event: (.+)$/m.exec(chunk)?.[1];
          const data = /^data: (.+)$/m.exec(chunk)?.[1];
          if (event && data) events.push({ event, data: JSON.parse(data) });
        }
      }
    } catch {
      // closed
    }
  })();
  /** The first event (after `from`) that `match` accepts, once it has come. */
  const next = async (event: string, match: (data: any) => boolean = () => true, from = 0) => {
    for (let i = 0; i < 300; i++) {
      const found = events.slice(from).find((e) => e.event === event && match(e.data));
      if (found) return found.data;
      await new Promise((r) => setTimeout(r, 10));
    }
    throw new Error(`no ${event} event; got ${events.map((e) => e.event).join(", ")}`);
  };
  return { events, next, close: () => controller.abort() };
}

/** Stands in for `claude auth login` and `codex login --device-auth`. */
const fakeLogin = (() => {
  const path = join(mkdtempSync(join(tmpdir(), "ember-fake-login-")), "fake-login");
  writeFileSync(path, `#!/bin/sh
if [ "$1" = "auth" ]; then
  echo "Opening browser to sign in…"
  echo "If the browser didn't open, visit: https://claude.com/cai/oauth/authorize?code=true&client_id=x&state=y"
  printf "Paste code here if prompted > "
  read code
  [ "$code" = "good-code" ] && { echo "Login successful"; exit 0; }
  echo "OAuth error: invalid code"; exit 1
fi
printf "1. Open this link\\n   \\033[94mhttps://auth.openai.com/codex/device\\033[0m\\n2. Enter this one-time code\\n   \\033[94mABCD-12345\\033[0m\\n"
sleep 0.3
echo "Successfully logged in"
`, { mode: 0o755 });
  return path;
})();

const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const jwks = async () => ({ keys: [{ ...publicKey.export({ format: "jwk" }), kid: "k1" }] });

function jwt(claims: Record<string, unknown>, kid = "k1"): string {
  const part = (value: unknown) => Buffer.from(JSON.stringify(value)).toString("base64url");
  const head = `${part({ alg: "RS256", kid })}.${part(claims)}`;
  return `${head}.${sign("RSA-SHA256", Buffer.from(head), privateKey).toString("base64url")}`;
}

/** Records what ember asks of Slack's app API. */
class FakeSlackApps {
  configured = true;
  manifest: any = slackManifest("ember");
  updates: any[] = [];
  icons = 0;
  async exportManifest() { return structuredClone(this.manifest); }
  async updateManifest(_appId: string, manifest: any) {
    const before = [...this.manifest.oauth_config.scopes.bot].sort().join();
    this.updates.push(manifest);
    this.manifest = manifest;
    return { permissionsUpdated: before !== [...manifest.oauth_config.scopes.bot].sort().join() };
  }
  async createApp() { return { appId: "A0NEW", oauthAuthorizeUrl: "" }; }
  async setIcon() {
    this.icons++;
    throw new SlackApiError("apps.icon.set", "app_not_owned_by_manager_app");
  }
}

async function setup(options: { access?: { teamDomain: string; aud: string }; store?: Store; dataDir?: string; quota?: () => void; spans?: any[] } = {}) {
  const slackApps = new FakeSlackApps();
  const dataDir = options.dataDir ?? mkdtempSync(join(tmpdir(), "ember-admin-"));
  const logins = new LoginManager(dataDir, { claude: fakeLogin, codex: fakeLogin });
  const path = join(dataDir, "config.json");
  writeFileSync(path, JSON.stringify({
    ...(options.access ? { admin: { access: options.access } } : {}),
    profiles: [
      { id: "cc", runtime: "claude", home: "homes/cc", env: { ANTHROPIC_API_KEY: "sk-very-secret-value", ANTHROPIC_BASE_URL: "https://example" } },
      { id: "cx", runtime: "codex", home: "homes/cx" },
    ],
    connects: [{ id: "ds", name: "ember", kind: "slack", mode: "multi-session", bind: { runtime: "claude", profiles: ["cc"] }, slack: { appToken: "xapp-1-aaaaaaaaaaaa", botToken: "xoxb-bbbbbbbbbbbb", appId: "A0DS" } }],
  }));
  const settings = new Settings(path, dataDir);
  const store = options.store ?? new Store(":memory:");
  const connections: FakeConnection[] = [];
  const conns = new Connections(() => {
    const c = new FakeConnection();
    connections.push(c);
    return c;
  }, (id, event) => hub.receive(id, event));
  const claude = new FakeDriver("claude");
  const hub: Hub = new Hub({ config: () => settings.config, store, chats: conns.chats, drivers: { claude, codex: new FakeDriver("codex") }, mcpUrl: "x", internal: new InternalChat() });
  settings.onChange((config) => void conns.reconcile(config));
  await conns.reconcile(settings.config);
  const api = new AdminApi({
    settings, store, hub, connections: conns, logins, names: new Map(), slackApps: slackApps as unknown as SlackApps,
    checkProfile: async () => ({ state: "ok", detail: "fake", checkedAt: Date.now(), models: [] }), gate: new AccessGate(() => settings.config.adminAccess, jwks),
    ...(options.quota ? { quota: async () => { options.quota!(); return { state: "ok" as const, windows: [{ label: "5 小时", usedPercent: 12, resetsAt: null }], detail: null, checkedAt: Date.now() }; } } : {}),
    ...(options.spans ? { mesh: { secret: () => null, status: () => ({ state: "off" as const, origin: null, station: null, workspace: null, workspaceId: null, name: null }), span: (span: object) => options.spans!.push(span) } } : {}),
  });
  const server = createServer((req, res) => void api.handle(req, res));
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const base = `http://127.0.0.1:${(server.address() as { port: number }).port}/admin/api`;
  const call = async (method: string, route: string, bodyValue?: unknown, headers: Record<string, string> = {}) => {
    const response = await fetch(`${base}${route}`, {
      method,
      headers: { "content-type": "application/json", ...headers },
      ...(bodyValue === undefined ? {} : { body: JSON.stringify(bodyValue) }),
    });
    return { status: response.status, headers: response.headers, body: await response.json() as any };
  };
  return { slackApps, dataDir, path, settings, store, hub, conns, claude, connections, call, base, close: () => { logins.stopAll(); server.closeAllConnections(); server.close(); } };
}

test("a request in a recorded trace is a span of it, without ids or queries", async () => {
  const spans: any[] = [];
  const t = await setup({ spans });
  const trace = "4bf92f3577b34da6a3ce929d0e0e4736";
  const settle = () => new Promise((r) => setTimeout(r, 50));
  try {
    const before = Date.now();
    assert.equal((await t.call("GET", "/overview", undefined, { traceparent: `00-${trace}-00f067aa0ba902b7-01` })).status, 200);
    assert.equal((await t.call("GET", "/threads/123/entries?limit=5", undefined, { traceparent: `00-${trace}-00f067aa0ba902b8-01` })).status, 404);
    // Not recorded by the caller, or no trace at all: no span.
    await t.call("GET", "/overview", undefined, { traceparent: `00-${trace}-00f067aa0ba902b7-00` });
    await t.call("GET", "/overview");
    await settle();
    assert.equal(spans.length, 2);
    const [overview, entries] = spans;
    assert.equal(overview.traceId, trace);
    assert.equal(overview.parentSpanId, "00f067aa0ba902b7");
    assert.match(overview.spanId, /^[0-9a-f]{16}$/);
    assert.equal(overview.name, "GET /admin/api/overview");
    assert.equal(overview.kind, 2);
    const start = Number(BigInt(overview.startTimeUnixNano) / 1_000_000n);
    assert.ok(start >= before - 1 && BigInt(overview.endTimeUnixNano) >= BigInt(overview.startTimeUnixNano));
    const attributes = Object.fromEntries(overview.attributes.map((a: any) => [a.key, Object.values(a.value)[0]]));
    assert.equal(attributes["http.response.status_code"], "200");
    assert.equal(attributes["ember.via"], "local");
    assert.ok(Number(attributes["http.response.size"]) > 100);
    assert.equal(entries.name, "GET /admin/api/threads/:id/entries");
    assert.deepEqual(entries.status, { code: 1 });

    // A stream's span ends as it opens, not when it closes.
    const events = await follow(`${t.base}/events`, { traceparent: `00-${trace}-00f067aa0ba902b9-01` });
    await settle();
    assert.equal(spans.length, 3);
    assert.equal(spans[2].name, "GET /admin/api/events");
    assert.ok(spans[2].attributes.some((a: any) => a.key === "ember.stream" && a.value.boolValue === true));
    events.close();
    await settle();
    assert.equal(spans.length, 3);
  } finally {
    t.close();
  }
});

test("local visits need no sign-in", async () => {
  const t = await setup();
  try {
    const { status, body } = await t.call("GET", "/overview");
    assert.equal(status, 200);
    assert.deepEqual(body.viewer, { via: "local" });
  } finally {
    t.close();
  }
});

test("tunneled visits are refused until Cloudflare Access is configured", async () => {
  const t = await setup();
  try {
    const { status, body } = await t.call("GET", "/overview", undefined, { "cf-connecting-ip": "203.0.113.9" });
    assert.equal(status, 403);
    assert.match(body.error, /Cloudflare Access/);
  } finally {
    t.close();
  }
});

test("tunneled visits need a valid Access token for this team and application", async () => {
  const access = { teamDomain: "afk", aud: "app-aud" };
  const t = await setup({ access });
  const good = { iss: "https://afk.cloudflareaccess.com", aud: ["app-aud"], email: "dev@example.com", exp: Date.now() / 1000 + 600 };
  const via = (token?: string) => ({ "cf-connecting-ip": "203.0.113.9", ...(token ? { "cf-access-jwt-assertion": token } : {}) });
  try {
    const ok = await t.call("GET", "/overview", undefined, via(jwt(good)));
    assert.equal(ok.status, 200);
    assert.deepEqual(ok.body.viewer, { via: "access", email: "dev@example.com" });
    const cases: [Record<string, string>, RegExp][] = [
      [via(), /缺少/],
      [via(jwt({ ...good, aud: ["other"] })), /不属于这个应用/],
      [via(jwt({ ...good, iss: "https://evil.cloudflareaccess.com" })), /别的团队/],
      [via(jwt({ ...good, exp: Date.now() / 1000 - 3600 })), /过期/],
      [via(jwt(good).replace(/\.[^.]+$/, ".AAAA")), /签名无效/],
      [via(jwt(good, "unknown-kid")), /签名无效/],
    ];
    for (const [headers, message] of cases) {
      const denied = await t.call("GET", "/overview", undefined, headers);
      assert.equal(denied.status, 403);
      assert.match(denied.body.error, message);
    }
  } finally {
    t.close();
  }
});

test("secrets are masked in the overview", async () => {
  const t = await setup();
  try {
    const { body } = await t.call("GET", "/overview");
    assert.equal(body.connects[0].slack.botToken, "xoxb-…bbbb");
    assert.equal(body.connects[0].connection.state, "connected");
    const env = Object.fromEntries(body.profiles[0].env.map((e: any) => [e.key, e]));
    assert.equal(env.ANTHROPIC_API_KEY.secret, true);
    assert.equal(env.ANTHROPIC_API_KEY.value, "sk-ve…alue");
    assert.equal(env.ANTHROPIC_BASE_URL.value, "https://example");
    assert.doesNotMatch(JSON.stringify(body), /very-secret|bbbbbbbbbbbb/);
  } finally {
    t.close();
  }
});

test("editing a connect keeps tokens that were left blank and writes config.json privately", async () => {
  const t = await setup();
  try {
    const { status } = await t.call("PUT", "/connects/ds", { name: "ember-ds", bind: { model: "deepseek-flash" }, slack: { appToken: "", botToken: "" } });
    assert.equal(status, 200);
    const saved = JSON.parse(readFileSync(t.path, "utf8"));
    assert.equal(saved.connects[0].name, "ember-ds");
    assert.equal(saved.connects[0].slack.botToken, "xoxb-bbbbbbbbbbbb");
    assert.equal(saved.connects[0].bind.model, "deepseek-flash");
    assert.equal(saved.bots, undefined);
    assert.equal(statSync(t.path).mode & 0o777, 0o600);
  } finally {
    t.close();
  }
});

test("adding, disabling and deleting connects follows through to connections", async () => {
  const t = await setup();
  try {
    assert.equal(t.connections.length, 1);
    await t.call("PUT", "/connects/gpt", { bind: { runtime: "codex", profiles: ["cx"] }, slack: { appToken: "xapp-2-cccccccccc", botToken: "xoxb-dddddddddd" } });
    await t.conns.reconcile(t.settings.config);
    assert.deepEqual([...t.conns.chats.keys()].sort(), ["ds", "gpt"]);
    await t.call("PUT", "/connects/gpt", { enabled: false });
    await t.conns.reconcile(t.settings.config);
    assert.deepEqual([...t.conns.chats.keys()], ["ds"]);
    assert.equal(t.connections[1]!.stopped, 1);
    const { body } = await t.call("GET", "/overview");
    assert.equal(body.connects.find((b: any) => b.id === "gpt").connection.state, "disabled");
    await t.call("DELETE", "/connects/gpt");
    assert.deepEqual(t.settings.config.connects.map((b) => b.id), ["ds"]);
  } finally {
    t.close();
  }
});

test("invalid edits are refused and leave the config unchanged", async () => {
  const t = await setup();
  try {
    const before = readFileSync(t.path, "utf8");
    const bad = await t.call("PUT", "/connects/x", { bind: { runtime: "claude", profiles: ["nope"] } });
    assert.equal(bad.status, 400);
    assert.match(bad.body.error, /unknown profile nope/);
    const mismatch = await t.call("PUT", "/connects/x", { bind: { runtime: "codex", profiles: ["cc"] } });
    assert.match(mismatch.body.error, /profile cc is claude/);
    const inUse = await t.call("DELETE", "/profiles/cc");
    assert.equal(inUse.status, 400);
    assert.match(inUse.body.error, /used by ds/);
    assert.equal(readFileSync(t.path, "utf8"), before);
  } finally {
    t.close();
  }
});

test("profile env: strings set, null removes, omitted keys stay", async () => {
  const t = await setup();
  try {
    await t.call("PUT", "/profiles/cc", { env: { ANTHROPIC_BASE_URL: null, EXTRA: "1" } });
    assert.deepEqual(t.settings.config.profiles[0]!.env, { ANTHROPIC_API_KEY: "sk-very-secret-value", EXTRA: "1" });
    assert.equal((await t.call("PUT", "/profiles/cc", { env: { "BAD NAME": "x" } })).status, 400);
    await t.call("PUT", "/profiles/new-one", { runtime: "codex" });
    assert.equal(t.settings.config.profiles.at(-1)!.home, join(t.dataDir, "homes/new-one"));
  } finally {
    t.close();
  }
});

test("editing a profile's access keeps a blank key but never carries it to another kind", async () => {
  const t = await setup();
  try {
    assert.equal((await t.call("PUT", "/profiles/cx", { access: { kind: "opencode-go", key: "ocg-key-123456" } })).status, 200);
    assert.equal(t.settings.config.profiles.find((p) => p.id === "cx")!.env.OPENCODE_GO_KEY, "ocg-key-123456");
    await t.call("PUT", "/profiles/cx", { name: "Codex OCG", access: { kind: "opencode-go", key: "" } });
    const cx = t.settings.config.profiles.find((p) => p.id === "cx")!;
    assert.equal(cx.access.key, "ocg-key-123456");
    assert.equal(cx.name, "Codex OCG");
    const switched = await t.call("PUT", "/profiles/cx", { access: { kind: "subscription", key: "" } });
    assert.equal(switched.status, 200);
    assert.equal(t.settings.config.profiles.find((p) => p.id === "cx")!.access.key, "");
    const { body } = await t.call("GET", "/overview");
    assert.equal(body.profiles.find((p: any) => p.id === "cx").loginCommand, `CODEX_HOME=${join(t.dataDir, "homes/cx")} codex login`);
  } finally {
    t.close();
  }
});

test("session detail is the session, its threads and turns; its transcript comes live from any entry on", async () => {
  const t = await setup();
  try {
    await t.hub.accept("ds", message({ text: "<@UBOT> hi" }));
    await settle();
    const [row] = t.store.listSessions();
    const projects = join(t.dataDir, "homes/cc/projects/-work");
    mkdirSync(projects, { recursive: true });
    writeFileSync(join(projects, `${row!.runtimeSessionId}.jsonl`), [
      JSON.stringify({ type: "user", timestamp: "2026-09-26T00:00:00Z", message: { content: "hi" } }),
      JSON.stringify({ type: "assistant", message: { content: [{ type: "tool_use", name: "Bash", input: { command: "ls" } }] } }),
    ].join("\n") + "\n");
    const list = await t.call("GET", "/sessions");
    assert.equal(list.body[0].process, "running");
    assert.equal(list.body[0].token, undefined, "session tokens are never sent to the page");
    const detail = await t.call("GET", `/sessions/${encodeURIComponent(row!.key)}`);
    assert.deepEqual(Object.keys(detail.body).sort(), ["session", "threads", "turns"]);
    assert.equal(detail.body.threads.length, 1);
    assert.equal(detail.body.threads[0].lastMessage.text, "<@UBOT> hi");
    assert.equal(detail.body.threads[0].surface, "slack:T1");
    assert.equal(detail.body.turns.length, 1);
    // Its transcript comes on the events stream opened for it, from the entry asked for.
    const live = await follow(`${t.base}/events?live=${encodeURIComponent(row!.key)}&from=1&live=nobody&from=0`);
    const timeline = await live.next("live", (m) => m.type === "timeline");
    assert.deepEqual([timeline.key, timeline.start, timeline.entries.map((e: any) => e.kind)], [row!.key, 1, ["tool_call"]]);
    assert.ok(!live.events.some((e) => e.event === "live" && e.data.key === "nobody"), "a session that is not there is left out");
    live.close();
    assert.equal((await t.call("POST", `/sessions/${encodeURIComponent(row!.key)}/stop`)).status, 200);
    assert.equal(t.claude.last.aborts, 1);
  } finally {
    t.close();
  }
});

test("a single-session connect can be set to wake without a mention", async () => {
  const t = await setup();
  try {
    assert.equal((await t.call("PUT", "/connects/ds", { mode: "single-session", requireMention: false })).status, 200);
    const { body } = await t.call("GET", "/overview");
    assert.equal(body.connects[0].mode, "single-session");
    assert.equal(body.connects[0].requireMention, false);
    await t.call("PUT", "/connects/ds", { mode: "multi-session" });
    assert.equal(t.settings.config.connects[0]!.requireMention, true, "multi-session always needs a mention");
  } finally {
    t.close();
  }
});

test("a legacy bots config is rewritten as connects on load", async () => {
  const dataDir = mkdtempSync(join(tmpdir(), "ember-legacy-"));
  const path = join(dataDir, "config.json");
  writeFileSync(path, JSON.stringify({
    profiles: [{ id: "cc", runtime: "claude", home: "homes/cc" }],
    bots: [{ id: "ds", runtime: "claude", profile: "cc", model: "m" }],
  }));
  const settings = new Settings(path, dataDir);
  assert.deepEqual(settings.config.connects.map((c) => [c.id, c.mode, c.bind.model]), [["ds", "multi-session", "m"]]);
  const saved = JSON.parse(readFileSync(path, "utf8"));
  assert.equal(saved.bots, undefined);
  assert.deepEqual(saved.connects[0].bind, { runtime: "claude", profiles: ["cc"], model: "m" });
});

test("a subscription sign-in runs on the ember host and relays the link, the code and the result", async () => {
  const t = await setup();
  try {
    await t.call("PUT", "/profiles/sub", { runtime: "claude", access: { kind: "subscription" } });
    const wait = async (profile: string, state: string) => {
      for (let i = 0; i < 500; i++) {
        const { body } = await t.call("GET", `/profiles/${profile}/login`);
        if (body.job?.state === state) return body.job;
        await new Promise((r) => setTimeout(r, 30));
      }
      throw new Error(`login of ${profile} never reached ${state}`);
    };
    assert.equal((await t.call("POST", "/profiles/cc/login")).status, 400, "keyed profiles do not sign in");
    await t.call("POST", "/profiles/sub/login");
    const job = await wait("sub", "needs_code");
    assert.match(job.url, /^https:\/\/claude\.com\/cai\/oauth\/authorize\?/);
    await t.call("POST", "/profiles/sub/login-code", { code: "wrong" });
    assert.match((await wait("sub", "failed")).error, /invalid code/);
    await t.call("POST", "/profiles/sub/login");
    await wait("sub", "needs_code");
    await t.call("POST", "/profiles/sub/login-code", { code: " good-code " });
    await wait("sub", "done");

    await t.call("PUT", "/profiles/cxs", { runtime: "codex", access: { kind: "subscription" } });
    await t.call("POST", "/profiles/cxs/login");
    const device = await wait("cxs", "needs_approval");
    assert.equal(device.url, "https://auth.openai.com/codex/device");
    assert.equal(device.userCode, "ABCD-12345");
    await wait("cxs", "done");
    const { body } = await t.call("GET", "/overview");
    assert.equal(body.profiles.find((p: any) => p.id === "cxs").login.state, "done");
  } finally {
    t.close();
  }
});

test("a connect's Slack app is edited through its manifest; new permissions need approval in Slack", async () => {
  const t = await setup();
  try {
    const app = await t.call("GET", "/connects/ds/slack-app");
    assert.equal(app.body.state, "ok");
    assert.equal(app.body.settings.name, "ember");
    assert.equal(app.body.links.install, "https://api.slack.com/apps/A0DS/install-on-team");
    const renamed = await t.call("PUT", "/connects/ds/slack-app", { name: "ember-ds", description: "DS agent" });
    assert.equal(renamed.body.permissionsUpdated, false);
    assert.equal(t.slackApps.manifest.display_information.name, "ember-ds");
    const fewer = await t.call("PUT", "/connects/ds/slack-app", { groups: { files: false }, icon: "data:image/png;base64,AAAA" });
    assert.equal(fewer.body.permissionsUpdated, true);
    assert.match(fewer.body.iconError, /API 创建/);
    assert.equal((await t.call("PUT", "/connects/ds/slack-app", { backgroundColor: "red" })).status, 400);
    // Token edits keep the app id ember learned.
    await t.call("PUT", "/connects/ds", { slack: { botToken: "xoxb-new-token-123" } });
    assert.equal(t.settings.config.connects[0]!.slack.appId, "A0DS");
  } finally {
    t.close();
  }
});

test("connects, sessions and chats remember who created them", async () => {
  const t = await setup();
  try {
    await t.call("PUT", "/connects/fresh", { bind: { runtime: "claude", profiles: ["cc"] } });
    assert.deepEqual(t.settings.config.connects.find((c) => c.id === "fresh")!.createdBy, { id: "local", name: "本机管理页" });
    await t.call("PUT", "/connects/fresh", { name: "renamed" });
    assert.equal(t.settings.config.connects.find((c) => c.id === "fresh")!.createdBy?.id, "local", "editing keeps the creator");
    const { body } = await t.call("GET", "/overview");
    assert.equal(body.connects.find((c: any) => c.id === "ds").createdBy, null, "older connects have none");
    await t.call("PUT", "/connects/ds", { owner: { id: "Bob@Example.test", name: "Bob" } });
    assert.deepEqual(t.settings.config.connects.find((c) => c.id === "ds")!.createdBy, { id: "bob@example.test", name: "Bob" });
    assert.equal((await t.call("PUT", "/connects/ds", { owner: { id: "not an email" } })).status, 400);

    await t.hub.accept("ds", message({ text: "<@UBOT> hi", user: "U42" }));
    await settle();
    const [summary] = (await t.call("GET", "/sessions")).body;
    assert.deepEqual(summary.creator, { id: "slack:ds:U42", name: "U42", email: null, via: "slack" });
    assert.deepEqual(summary.participants.map((p: any) => p.id), ["slack:ds:U42"]);
    const chat = await t.call("POST", "/threads", { session: summary.key, title: "排查" });
    assert.equal(chat.body.surface, "ember");
    assert.equal(chat.body.creator.via, "local");
    assert.deepEqual(chat.body.sessions.map((m: any) => [m.session, m.connect]), [[summary.key, "ember"]]);
    assert.equal((await t.call("POST", `/threads/${chat.body.id}/messages`, { text: "  " })).status, 400);
    await t.call("POST", `/threads/${chat.body.id}/messages`, { text: "hello from the page" });
    const after = await t.call("GET", `/sessions/${encodeURIComponent(summary.key)}`);
    assert.deepEqual(after.body.session.participants.map((p: any) => p.id), ["slack:ds:U42", "local"]);
    assert.deepEqual(after.body.threads.map((x: any) => x.title), ["排查", null]);
    assert.deepEqual(after.body.threads.map((x: any) => [x.firstText, x.people.map((p: any) => p.id)]), [
      ["hello from the page", ["local"]], ["<@UBOT> hi", ["slack:ds:U42"]],
    ]);
    const slackThread = after.body.threads[1];
    assert.equal((await t.call("POST", `/threads/${slackThread.id}/messages`, { text: "hi" })).status, 400, "Slack threads are written in Slack");
  } finally {
    t.close();
  }
});

test("the station reports the machine it runs on", async () => {
  const t = await setup();
  try {
    const { status, body } = await t.call("GET", "/host");
    assert.equal(status, 200);
    assert.ok(body.hostname && body.cpus > 0);
    assert.ok(body.memory.totalBytes > 0 && body.memory.usedBytes > 0 && body.memory.usedBytes <= body.memory.totalBytes);
    assert.ok(body.disk.totalBytes > 0 && body.disk.freeBytes <= body.disk.totalBytes);
  } finally {
    t.close();
  }
});

test("files sent to a session land in its workspace and reach the agent as paths", async () => {
  const t = await setup();
  try {
    await t.hub.accept("ds", message({ text: "<@UBOT> hi" }));
    await settle();
    const [summary] = (await t.call("GET", "/sessions")).body;
    const key = encodeURIComponent(summary.key);
    const chat = (await t.call("POST", "/threads", { session: summary.key })).body;
    const say = (input: unknown) => t.call("POST", `/threads/${chat.id}/messages`, input);
    const upload = await fetch(`${t.base}/sessions/${key}/files?name=${encodeURIComponent("../../report.txt")}`, { method: "POST", body: "hello file" });
    const file = await upload.json() as any;
    assert.equal(upload.status, 200);
    assert.match(file.path, /\/uploads\/[^/]+-report\.txt$/, "a name cannot climb out of the upload directory");
    assert.equal(readFileSync(file.path, "utf8"), "hello file");
    assert.equal((await say({ text: "看看", attachments: [{ ...file, path: "/etc/hosts" }] })).status, 400);
    assert.equal((await say({ text: "看看这个", attachments: [file] })).status, 200);
    await settle();
    assert.match(t.claude.last.steers.at(-1) ?? t.claude.last.prompts.at(-1)!, new RegExp(`看看这个\n\nAttached files:\n- ${file.path.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`));
    const page = (await t.call("GET", `/threads/${chat.id}/entries`)).body;
    assert.deepEqual(page.entries[0].attachments.map((a: any) => a.name), [file.name]);
    assert.equal(page.entries[0].text, "看看这个", "the words are stored as typed");
    assert.equal(page.entries[0].authorName, "管理员");
    const back = await fetch(`${t.base}/sessions/${key}/files?name=${encodeURIComponent(file.path.split("/").at(-1))}`);
    assert.equal(await back.text(), "hello file");
    assert.equal((await fetch(`${t.base}/sessions/${key}/files?name=${encodeURIComponent("../../../config.json")}`)).status, 404);
    await say({ text: "改一下", quotes: [{ author: "deepseek-flash", role: "agent", ts: "1790383286.536000", text: "第一行\n第二行", comment: "这里不对" }] });
    await settle();
    const sent = [...t.claude.last.steers, ...t.claude.last.prompts].join("\n---\n");
    assert.match(sent, /\[Quote\] From your own earlier message 1790383286\.536000 in this conversation:\n> 第一行\n> 第二行\nTheir comment on it: 这里不对\n\n改一下/);
    const after = (await t.call("GET", `/threads/${chat.id}/entries`)).body;
    assert.equal(after.entries.at(-1).quotes[0].comment, "这里不对");
    // The agent answers with an image; it is copied into the uploads and measured.
    const png = Buffer.alloc(24); png.writeUInt32BE(0x89504e47, 0); png.write("IHDR", 12, "ascii"); png.writeUInt32BE(320, 16); png.writeUInt32BE(200, 20);
    const shot = join(t.dataDir, "chart.png"); writeFileSync(shot, png);
    const post = t.hub.tools().find((x) => x.name === "chat_post")!;
    await post.run(summary.key, { to: `EMBER/${chat.threadTs}`, text: "图在这", files: [shot] });
    const reply = (await t.call("GET", `/threads/${chat.id}/entries?after=${after.last}`)).body.entries.at(-1);
    assert.deepEqual([reply.authorKind, reply.author, reply.authorName], ["agent", summary.key, "ember"]);
    assert.deepEqual([reply.attachments[0].name, reply.attachments[0].width, reply.attachments[0].height], ["chart.png", 320, 200]);
    assert.match(reply.attachments[0].path, /\/uploads\/.+-chart\.png$/);
    await assert.rejects(post.run(summary.key, { to: `EMBER/${chat.threadTs}`, text: "x", files: ["/no/such/file.png"] }), /no such file/);
  } finally {
    t.close();
  }
});

test("a new chat makes a session of its own with the chosen runtime, model and effort", async () => {
  const t = await setup();
  try {
    assert.equal((await t.call("POST", "/sessions", { runtime: "gpt" })).status, 400);
    assert.equal((await t.call("POST", "/sessions", { runtime: "claude", effort: "turbo" })).status, 400);
    assert.equal((await t.call("POST", "/sessions", { runtime: "claude", model: "deepseek-flash" })).status, 400, "no profile has the model enabled");
    await t.call("PUT", "/profiles/cc", { models: ["deepseek-flash", "deepseek-flash", " glm-5 "] });
    const { body: ov } = await t.call("GET", "/overview");
    assert.deepEqual(ov.profiles.find((p: any) => p.id === "cc").models, ["deepseek-flash", "glm-5"]);
    const made = await t.call("POST", "/sessions", { runtime: "claude", model: "deepseek-flash", effort: "high", title: "新对话" });
    assert.equal(made.status, 200);
    assert.deepEqual([made.body.thread.surface, made.body.thread.title, made.body.thread.sessions[0].session], ["ember", "新对话", made.body.key]);
    const key = encodeURIComponent(made.body.key);
    assert.equal((await t.call("POST", `/threads/${made.body.thread.id}/messages`, { text: "开始吧" })).status, 200);
    await settle();
    const { body } = await t.call("GET", `/sessions/${key}`);
    assert.equal(body.session.connect, "ember");
    assert.equal(body.session.profile, "cc");
    assert.deepEqual([body.session.model, body.session.effort], ["deepseek-flash", "high"]);
    assert.equal(body.session.creator.via, "local");
    assert.equal(body.threads[0].lastMessage.text, "开始吧");
    assert.equal(t.claude.last.options.model, "deepseek-flash");
    assert.match(t.claude.last.prompts[0]!, /开始吧/);
  } finally {
    t.close();
  }
});

test("thread entries: the latest page, pages back, what came after n, and a gap from a to b", async () => {
  const t = await setup();
  try {
    const { thread } = t.hub.newSession({ runtime: "claude", createdBy: "local" });
    for (let i = 1; i <= 5; i++) t.hub.say(thread.id, "local", `m${i}`);
    const latest = (await t.call("GET", `/threads/${thread.id}/entries?limit=2`)).body;
    assert.deepEqual([latest.entries.map((e: any) => [e.n, e.text, e.authorName]), latest.last], [[[4, "m4", "管理员"], [5, "m5", "管理员"]], 5]);
    const back = (await t.call("GET", `/threads/${thread.id}/entries?before=4&limit=10`)).body;
    assert.deepEqual(back.entries.map((e: any) => e.text), ["m1", "m2", "m3"]);
    assert.deepEqual((await t.call("GET", `/threads/${thread.id}/entries?from=2&to=3`)).body.entries.map((e: any) => e.n), [2, 3]);
    assert.deepEqual((await t.call("GET", `/threads/${thread.id}/entries?after=5`)).body.entries, []);
    // A Slack thread takes edits: entries after the ones read, which never change.
    await t.hub.accept("ds", message({ ts: "7.000001", threadTs: "7.000001", text: "<@UBOT> one" }));
    await t.hub.accept("ds", message({ ts: "7.000002", threadTs: "7.000001", addressed: false, text: "two" }));
    const slack = t.store.threadAt("slack:T1", "C1", "7.000001")!;
    const opened = (await t.call("GET", `/threads/${slack.id}/entries`)).body;
    await t.hub.receive("ds", { kind: "changed", channel: "C1", threadTs: "7.000001", ts: "7.000001", text: "<@UBOT> one, edited" });
    t.hub.say(thread.id, "local", "m6");
    const since = (await t.call("GET", `/threads/${slack.id}/entries?after=${opened.last}`)).body;
    assert.deepEqual(since.entries.map((e: any) => [e.n, e.kind, e.target, e.text]), [[3, "edit", 1, "<@UBOT> one, edited"]]);
    assert.equal(since.last, 3);
    assert.deepEqual((await t.call("GET", `/threads/${slack.id}/entries?from=1&to=2`)).body.entries, opened.entries);
    assert.deepEqual((await t.call("GET", `/threads/${thread.id}/entries?after=5`)).body.entries.map((e: any) => e.text), ["m6"]);
    // Lists carry the last n and the latest message as merged.
    const [view] = (await t.call("GET", `/threads?session=${encodeURIComponent(t.store.threadSessions(slack.id)[0]!.session)}`)).body;
    assert.deepEqual([view.last, view.lastMessage.seq, view.lastMessage.text], [3, 2, "two"]);
    assert.equal((await t.call("GET", `/threads/${thread.id}/entries?from=2`)).status, 400);
    assert.equal((await t.call("GET", "/threads/999/entries")).status, 404);
  } finally {
    t.close();
  }
});

test("read positions and unread counts are per viewer, and only move forward", async () => {
  const access = { teamDomain: "afk", aud: "app-aud" };
  const t = await setup({ access });
  const dev = { "cf-connecting-ip": "203.0.113.9", "cf-access-jwt-assertion": jwt({ iss: "https://afk.cloudflareaccess.com", aud: ["app-aud"], email: "dev@example.com", exp: Date.now() / 1000 + 600 }) };
  try {
    const { key, thread } = t.hub.newSession({ runtime: "claude", createdBy: "local" });
    const first = t.hub.say(thread.id, "local", "mine");
    t.hub.say(thread.id, "dev@example.com", "theirs");
    t.store.insertMessage({ thread: thread.id, ts: "9.000001", authorKind: "agent", author: key, text: "answer" });
    const unread = async (headers: Record<string, string> = {}) => (await t.call("GET", `/threads?session=${encodeURIComponent(key)}`, undefined, headers)).body[0].unread;
    assert.equal(await unread(), 2, "a viewer's own messages are not unread for them");
    assert.equal(await unread(dev), 2);
    const localEvents = await follow(`${t.base}/events`);
    const devEvents = await follow(`${t.base}/events`, dev);
    const put = await t.call("PUT", `/threads/${thread.id}/read`, { n: first + 1 });
    assert.deepEqual(put.body, { viewer: "local", thread: thread.id, n: first + 1 });
    assert.equal(await unread(), 1);
    assert.equal(await unread(dev), 2);
    assert.deepEqual(await localEvents.next("read"), { viewer: "local", thread: thread.id, n: first + 1 });
    await t.call("PUT", `/threads/${thread.id}/read`, { n: first }, dev);
    await devEvents.next("read");
    assert.equal(devEvents.events.filter((e) => e.event === "read").length, 1, "a read goes only to its viewer");
    assert.equal((await t.call("PUT", `/threads/${thread.id}/read`, { n: 1 })).body.n, first + 1, "never back");
    const [view] = (await t.call("GET", `/threads?session=${encodeURIComponent(key)}`)).body;
    assert.deepEqual([view.read, view.unread, view.last, view.lastMessage.text], [first + 1, 1, 3, "answer"]);
    localEvents.close();
    devEvents.close();
  } finally {
    t.close();
  }
});

test("sessions can be archived, shown again, and deleted with their workspace", async () => {
  const t = await setup();
  try {
    await t.hub.accept("ds", message({ text: "<@UBOT> hi" }));
    await settle();
    const [summary] = (await t.call("GET", "/sessions")).body;
    const key = encodeURIComponent(summary.key);
    const [thread] = (await t.call("GET", "/threads")).body;
    const entries = (await t.call("GET", `/threads/${thread.id}/entries`)).body;
    const archived = await t.call("POST", `/sessions/${key}/archive`);
    assert.ok(archived.body.archivedAt > 0);
    // Its thread is read from its archive file, the same way.
    assert.equal(existsSync(join(t.store.archiveDir, "threads", `${thread.id}.jsonl.zst`)), true);
    assert.deepEqual((await t.call("GET", `/threads/${thread.id}/entries`)).body, entries);
    assert.deepEqual((await t.call("GET", "/threads")).body, [thread]);
    assert.deepEqual((await t.call("GET", "/sessions")).body, []);
    assert.deepEqual((await t.call("GET", "/sessions?archived=1")).body.map((s: any) => s.key), [summary.key]);
    await t.call("DELETE", `/sessions/${key}/archive`);
    assert.equal((await t.call("GET", "/sessions")).body.length, 1);
    assert.equal(existsSync(summary.workspace), true);
    assert.equal((await t.call("DELETE", `/sessions/${key}`)).status, 200);
    assert.equal(existsSync(summary.workspace), false);
    assert.equal(t.claude.last.disposed, true);
    assert.equal((await t.call("GET", `/sessions/${key}`)).status, 404);
    assert.deepEqual((await t.call("GET", "/threads")).body, []);
  } finally {
    t.close();
  }
});

test("/events announces each kind of change", async () => {
  let quotas = 0;
  const t = await setup({ quota: () => quotas++ });
  try {
    await t.call("GET", "/overview");
    assert.equal(quotas, 0, "quotas are not asked while nobody follows");
    const events = await follow(`${t.base}/events`);
    await events.next("overview", (o) => o.profiles.some((p: any) => p.quota?.windows[0]?.usedPercent === 12));
    assert.equal(quotas, 2, "following starts a quota round");
    await t.hub.accept("ds", message({ ts: "8.000001", threadTs: "8.000001", text: "<@UBOT> hi" }));
    const key = "ds:C1:8.000001";
    const session = await events.next("session", (s) => s.key === key && s.process === "running");
    assert.equal(session.creator.via, "slack");
    const thread = await events.next("thread", (x) => x.entries.length === 1);
    assert.deepEqual([thread.entries[0].text, thread.entries[0].authorKind, thread.entries[0].n], ["<@UBOT> hi", "person", 1]);
    await events.next("overview", (o) => o.counts.running === 1);
    let from = events.events.length;
    await t.call("PUT", "/profiles/cx", { name: "Codex 2" });
    await events.next("overview", (o) => o.profiles.some((p: any) => p.name === "Codex 2"), from);
    from = events.events.length;
    await t.call("POST", "/profiles/cc/check");
    await events.next("overview", (o) => o.profiles.find((p: any) => p.id === "cc").check?.detail === "fake", from);
    t.claude.last.end({ kind: "aborted" });
    await events.next("overview", (o) => o.counts.running === 0 && o.counts.warm === 1);
    await t.call("DELETE", `/sessions/${encodeURIComponent(key)}`);
    assert.deepEqual(await events.next("session-removed"), { key });
    assert.deepEqual(await events.next("thread-removed"), { id: thread.id });
    assert.equal(events.events.some((e) => e.event === "host"), false, "host only for those asking");
    const host = await follow(`${t.base}/events?host=1`);
    assert.ok((await host.next("host")).cpus > 0);
    host.close();
    events.close();
  } finally {
    t.close();
  }
});

test("profile checks and quotas are kept, so a restart shows them at once", async () => {
  const dataDir = mkdtempSync(join(tmpdir(), "ember-admin-"));
  const store = new Store(join(dataDir, "ember.db"));
  const first = await setup({ store, dataDir, quota: () => undefined });
  try {
    await first.call("POST", "/profiles/cc/check");
    await first.call("POST", "/profiles/cc/quota");
  } finally {
    first.close();
  }
  const again = await setup({ store: new Store(join(dataDir, "ember.db")), dataDir });
  try {
    const cc = (await again.call("GET", "/overview")).body.profiles.find((p: any) => p.id === "cc");
    assert.equal(cc.check.detail, "fake");
    assert.equal(cc.quota.windows[0].usedPercent, 12);
  } finally {
    again.close();
  }
});

test("the sidebar is one kind of item, an agent merged with its internal chat; a Slack thread only lends it a title, connect and origin", async () => {
  const t = await setup();
  try {
    await t.hub.accept("ds", message({ ts: "5.000001", threadTs: "5.000001", user: "U42", text: "<@UBOT>  部署挂了\n第二行" }));
    await settle();
    const slackKey = "ds:C1:5.000001";
    const origin = { teamName: "Acme", channel: "C1", channelName: null, threadTs: "5.000001" };
    const rows = async () => (await t.call("GET", "/chats")).body as any[];
    const agentRow = (await rows()).find((r) => r.id === slackKey);
    assert.deepEqual({ ...agentRow, agents: undefined, lastActiveAt: undefined }, {
      id: slackKey, session: slackKey, thread: null, title: "部署挂了", agents: undefined, last: null,
      unread: false, mine: false, lastActiveAt: undefined, connect: "ds", origin,
    });
    assert.deepEqual(Object.keys(agentRow.agents[0]).sort(), ["effort", "key", "lastTurn", "model", "pending", "process", "runtime"]);
    assert.equal((await rows()).length, 1, "the Slack thread is no item of its own");

    // A chat made on ember: its item, from no connect.
    const made = (await t.call("POST", "/sessions", { runtime: "claude" })).body;
    // An item's id is its agent's session, chat or no chat.
    const own = (await rows()).find((r) => r.id === made.key);
    assert.deepEqual([own.thread, own.session, own.title, own.connect, own.origin, own.last, own.mine], [made.thread.id, made.key, "（还没有消息）", null, null, null, true]);

    // The Slack agent's internal chat: the same item, now with its chat, titled by the Slack thread until it has words of its own.
    const chat = (await t.call("POST", "/threads", { session: slackKey })).body;
    let list = await rows();
    assert.equal(list.filter((r) => r.id === slackKey).length, 1, "still one item, at the same id");
    let row = list.find((r) => r.id === slackKey);
    assert.equal(row.thread, chat.id);
    assert.deepEqual([row.session, row.title, row.connect, row.origin, row.agents.map((a: any) => a.key)], [slackKey, "部署挂了", "ds", origin, [slackKey]]);
    t.hub.say(chat.id, "local", "看看日志");
    row = (await rows()).find((r) => r.id === slackKey);
    assert.deepEqual([row.title, row.last.text, row.last.authorKind, row.unread, row.mine], ["看看日志", "看看日志", "person", false, true]);
    // What the agent says is unread until read; the Slack thread's messages never show in the chat.
    const said = t.store.insertMessage({ thread: chat.id, ts: "9.000001", authorKind: "agent", author: slackKey, text: "x".repeat(300) }).n;
    row = (await rows()).find((r) => r.id === slackKey);
    assert.deepEqual([row.unread, row.last.text.length, row.last.seq], [true, 200, said]);
    await t.call("PUT", `/threads/${chat.id}/read`, { n: said });
    assert.equal((await rows()).find((r) => r.id === slackKey).unread, false);
    assert.deepEqual((await t.call("GET", `/threads/${chat.id}/entries`)).body.entries.map((e: any) => e.text), ["看看日志", "x".repeat(300)]);

    // Archived: its item goes.
    await t.call("POST", `/sessions/${encodeURIComponent(slackKey)}/archive`);
    assert.deepEqual((await rows()).map((r) => r.id), [made.key]);
  } finally {
    t.close();
  }
});

test("a viewer can say a Slack user is them: the station then takes that user for the viewer", async () => {
  const access = { teamDomain: "afk", aud: "app-aud" };
  const t = await setup({ access });
  const dev = { "cf-connecting-ip": "203.0.113.9", "cf-access-jwt-assertion": jwt({ iss: "https://afk.cloudflareaccess.com", aud: ["app-aud"], email: "dev@example.com", exp: Date.now() / 1000 + 600 }) };
  try {
    await t.hub.accept("ds", message({ ts: "6.000001", threadTs: "6.000001", user: "U42", text: "<@UBOT> 看一下" }));
    await t.hub.accept("ds", message({ ts: "6.000002", threadTs: "6.000001", user: "U7", addressed: false, text: "我也在" }));
    await settle();
    const key = "ds:C1:6.000001";
    const mine = async (headers: Record<string, string> = {}) => (await t.call("GET", "/chats", undefined, headers)).body.find((r: any) => r.session === key).mine;
    const slackUnread = async (headers: Record<string, string> = {}) => (await t.call("GET", `/threads?session=${encodeURIComponent(key)}`, undefined, headers)).body[0].unread;
    assert.equal(await mine(dev), false);
    assert.equal(await slackUnread(dev), 2);
    const devEvents = await follow(`${t.base}/events`, dev);
    const localEvents = await follow(`${t.base}/events`);

    // "这是我" on the session's creator: the agent's row is now the local viewer's, and only their stream hears of it.
    const bound = await t.call("PUT", "/me/slack/U42");
    assert.deepEqual(bound.body.slackUsers, ["U42"]);
    assert.equal(await mine(), true);
    assert.equal(await mine(dev), false, "bindings are per viewer");
    await localEvents.next("chat", (r) => r.session === key && r.mine);
    await localEvents.next("overview", (o) => o.slackUsers.includes("U42"));
    await settle();
    assert.equal(devEvents.events.some((e) => e.event === "chat" && e.data.mine), false);
    // U7 only wrote in the Slack thread: their words are dev's own now, but the agent's row is not dev's —
    // with no chat yet, only whoever started the session counts.
    assert.deepEqual((await t.call("PUT", "/me/slack/U7", undefined, dev)).body.slackUsers, ["U7"]);
    assert.equal(await mine(dev), false);
    assert.equal(await slackUnread(dev), 1);
    await devEvents.next("overview", (o) => o.slackUsers.includes("U7"));
    assert.deepEqual((await t.call("GET", "/overview", undefined, dev)).body.slackUsers, ["U7"]);

    // "不是我": as before.
    await t.call("DELETE", "/me/slack/U7", undefined, dev);
    assert.equal(await mine(dev), false);
    assert.equal(await slackUnread(dev), 2);

    // Items change on the stream: the agent's item, once it has a chat, is the same item (its id is the session) with it.
    const from = localEvents.events.length;
    const chat = (await t.call("POST", "/threads", { session: key })).body;
    const changed = await localEvents.next("chat", (r) => r.thread === chat.id, from);
    assert.deepEqual([changed.id, changed.title], [key, "看一下"]);
    assert.ok(!localEvents.events.slice(from).some((e) => e.event === "chat-removed"), "nothing leaves the sidebar");
    devEvents.close();
    localEvents.close();
  } finally {
    t.close();
  }
});
