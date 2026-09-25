import assert from "node:assert/strict";
import { generateKeyPairSync, sign } from "node:crypto";
import { mkdirSync, mkdtempSync, readFileSync, statSync, writeFileSync } from "node:fs";
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
  readonly identity = { team: "Cue", teamId: "T1", url: "https://cue.slack.com/", botUserId: "UBOT", botName: "ember" };
  started = 0;
  stopped = 0;
  override async start(): Promise<void> {
    this.started++;
  }
  override async stop(): Promise<void> {
    this.stopped++;
  }
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

async function setup(options: { access?: { teamDomain: string; aud: string } } = {}) {
  const slackApps = new FakeSlackApps();
  const dataDir = mkdtempSync(join(tmpdir(), "ember-admin-"));
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
  const store = new Store(":memory:");
  const connections: FakeConnection[] = [];
  const conns = new Connections(() => {
    const c = new FakeConnection();
    connections.push(c);
    return c;
  }, (id, m) => hub.accept(id, m));
  const claude = new FakeDriver("claude");
  const hub: Hub = new Hub({ config: () => settings.config, store, chats: conns.chats, drivers: { claude, codex: new FakeDriver("codex") }, mcpUrl: "x", internal: new InternalChat(store) });
  settings.onChange((config) => void conns.reconcile(config));
  await conns.reconcile(settings.config);
  const api = new AdminApi({ settings, store, hub, connections: conns, logins, names: new Map(), slackApps: slackApps as unknown as SlackApps, checkProfile: async () => ({ state: "ok", detail: "fake", checkedAt: Date.now(), models: [] }), gate: new AccessGate(() => settings.config.adminAccess, jwks) });
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
  return { slackApps, dataDir, path, settings, store, hub, conns, claude, connections, call, base, close: () => { logins.stopAll(); server.close(); } };
}

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

test("session detail includes turns, messages and the runtime transcript", async () => {
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
    ].join("\n"));
    const list = await t.call("GET", "/sessions");
    assert.equal(list.body[0].process, "running");
    assert.equal(list.body[0].token, undefined, "session tokens are never sent to the page");
    const detail = await t.call("GET", `/sessions/${encodeURIComponent(row!.key)}`);
    assert.equal(detail.body.inbound.length, 1);
    assert.equal(detail.body.threads.length, 1);
    assert.equal(detail.body.turns.length, 1);
    assert.deepEqual(detail.body.transcript.timeline.map((e: any) => e.kind), ["user", "tool_call"]);
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
    const chat = await t.call("POST", `/sessions/${encodeURIComponent(summary.key)}/chats`, {});
    const detail = await t.call("GET", `/sessions/${encodeURIComponent(summary.key)}`);
    assert.equal(detail.body.chats[0].threadTs, chat.body.threadTs);
    assert.equal(detail.body.chats[0].creator.via, "local");
    await t.call("POST", `/chats/${chat.body.threadTs}/messages`, { text: "hello from the page" });
    const after = await t.call("GET", `/sessions/${encodeURIComponent(summary.key)}`);
    assert.deepEqual(after.body.session.participants.map((p: any) => p.id), ["slack:ds:U42", "local"]);
  } finally {
    t.close();
  }
});
