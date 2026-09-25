import assert from "node:assert/strict";
import { generateKeyPairSync, sign } from "node:crypto";
import { mkdirSync, mkdtempSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { AccessGate } from "../src/admin/access.ts";
import { AdminApi } from "../src/admin/api.ts";
import { BotConnections, type Connection } from "../src/bots.ts";
import { Hub } from "../src/hub.ts";
import { Settings } from "../src/settings.ts";
import { Store } from "../src/store.ts";
import { FakeChat, FakeDriver, message, settle } from "./fakes.ts";

class FakeConnection extends FakeChat implements Connection {
  readonly status = { connected: true, lastError: null };
  started = 0;
  stopped = 0;
  override async start(): Promise<void> {
    this.started++;
  }
  override async stop(): Promise<void> {
    this.stopped++;
  }
}

const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const jwks = async () => ({ keys: [{ ...publicKey.export({ format: "jwk" }), kid: "k1" }] });

function jwt(claims: Record<string, unknown>, kid = "k1"): string {
  const part = (value: unknown) => Buffer.from(JSON.stringify(value)).toString("base64url");
  const head = `${part({ alg: "RS256", kid })}.${part(claims)}`;
  return `${head}.${sign("RSA-SHA256", Buffer.from(head), privateKey).toString("base64url")}`;
}

async function setup(options: { access?: { teamDomain: string; aud: string } } = {}) {
  const dataDir = mkdtempSync(join(tmpdir(), "ember-admin-"));
  const path = join(dataDir, "config.json");
  writeFileSync(path, JSON.stringify({
    ...(options.access ? { admin: { access: options.access } } : {}),
    profiles: [
      { id: "cc", runtime: "claude", home: "homes/cc", env: { ANTHROPIC_API_KEY: "sk-very-secret-value", ANTHROPIC_BASE_URL: "https://example" } },
      { id: "cx", runtime: "codex", home: "homes/cx" },
    ],
    bots: [{ id: "ds", name: "ember", runtime: "claude", profiles: ["cc"], slack: { appToken: "xapp-1-aaaaaaaaaaaa", botToken: "xoxb-bbbbbbbbbbbb" } }],
  }));
  const settings = new Settings(path, dataDir);
  const store = new Store(":memory:");
  const connections: FakeConnection[] = [];
  const bots = new BotConnections(() => {
    const c = new FakeConnection();
    connections.push(c);
    return c;
  }, (botId, m) => hub.accept(botId, m));
  const claude = new FakeDriver("claude");
  const hub: Hub = new Hub({ config: () => settings.config, store, chats: bots.chats, drivers: { claude, codex: new FakeDriver("codex") }, mcpUrl: "x" });
  settings.onChange((config) => void bots.reconcile(config));
  await bots.reconcile(settings.config);
  const api = new AdminApi({ settings, store, hub, bots, gate: new AccessGate(() => settings.config.adminAccess, jwks) });
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
  return { dataDir, path, settings, store, hub, bots, claude, connections, call, base, close: () => server.close() };
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
    assert.equal(body.bots[0].slack.botToken, "xoxb-…bbbb");
    assert.equal(body.bots[0].connection.state, "connected");
    const env = Object.fromEntries(body.profiles[0].env.map((e: any) => [e.key, e]));
    assert.equal(env.ANTHROPIC_API_KEY.secret, true);
    assert.equal(env.ANTHROPIC_API_KEY.value, "sk-ve…alue");
    assert.equal(env.ANTHROPIC_BASE_URL.value, "https://example");
    assert.doesNotMatch(JSON.stringify(body), /very-secret|bbbbbbbbbbbb/);
  } finally {
    t.close();
  }
});

test("editing a bot keeps tokens that were left blank and writes config.json privately", async () => {
  const t = await setup();
  try {
    const { status } = await t.call("PUT", "/bots/ds", { name: "ember-ds", model: "deepseek-flash", slack: { appToken: "", botToken: "" } });
    assert.equal(status, 200);
    const saved = JSON.parse(readFileSync(t.path, "utf8"));
    assert.equal(saved.bots[0].name, "ember-ds");
    assert.equal(saved.bots[0].slack.botToken, "xoxb-bbbbbbbbbbbb");
    assert.equal(statSync(t.path).mode & 0o777, 0o600);
  } finally {
    t.close();
  }
});

test("adding, disabling and deleting bots follows through to connections", async () => {
  const t = await setup();
  try {
    assert.equal(t.connections.length, 1);
    await t.call("PUT", "/bots/gpt", { runtime: "codex", profiles: ["cx"], slack: { appToken: "xapp-2-cccccccccc", botToken: "xoxb-dddddddddd" } });
    await t.bots.reconcile(t.settings.config);
    assert.deepEqual([...t.bots.chats.keys()].sort(), ["ds", "gpt"]);
    await t.call("PUT", "/bots/gpt", { enabled: false });
    await t.bots.reconcile(t.settings.config);
    assert.deepEqual([...t.bots.chats.keys()], ["ds"]);
    assert.equal(t.connections[1]!.stopped, 1);
    const { body } = await t.call("GET", "/overview");
    assert.equal(body.bots.find((b: any) => b.id === "gpt").connection.state, "disabled");
    await t.call("DELETE", "/bots/gpt");
    assert.deepEqual(t.settings.config.bots.map((b) => b.id), ["ds"]);
  } finally {
    t.close();
  }
});

test("invalid edits are refused and leave the config unchanged", async () => {
  const t = await setup();
  try {
    const before = readFileSync(t.path, "utf8");
    const bad = await t.call("PUT", "/bots/x", { runtime: "claude", profiles: ["nope"] });
    assert.equal(bad.status, 400);
    assert.match(bad.body.error, /unknown profile nope/);
    const mismatch = await t.call("PUT", "/bots/x", { runtime: "codex", profiles: ["cc"] });
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
    assert.equal(detail.body.turns.length, 1);
    assert.deepEqual(detail.body.transcript.timeline.map((e: any) => e.kind), ["user", "tool_call"]);
    assert.equal((await t.call("POST", `/sessions/${encodeURIComponent(row!.key)}/stop`)).status, 200);
    assert.equal(t.claude.last.aborts, 1);
  } finally {
    t.close();
  }
});
