// Serves the admin client over a throwaway data dir seeded with sessions in
// every state, reusing real runtime transcripts found on this machine (read
// only). For working on the UI without touching a live ember.
// Usage: node scripts/admin-demo.ts [port]   (then open /admin)
import { EventEmitter } from "node:events";
import { existsSync, mkdtempSync, readdirSync, writeFileSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { createServer } from "node:http";
import { homedir, tmpdir } from "node:os";
import { extname, join, normalize } from "node:path";
import { AdminApi } from "../src/admin/api.ts";
import type { Connections } from "../src/connections.ts";
import type { Hub } from "../src/hub.ts";
import { INTERNAL_CHANNEL, nextTs } from "../src/chat/internal.ts";
import { LiveHub } from "../src/live.ts";
import { EMBER_SURFACE, type Attachment, type Quote } from "../src/store.ts";
import { LoginManager } from "../src/login.ts";
import { slackManifest } from "../src/admin/slack-manifest.ts";
import type { SlackApps } from "../src/chat/slack-apps.ts";
import { Settings } from "../src/settings.ts";
import { Store } from "../src/store.ts";

const port = Number(process.argv[2] ?? 4751);
const claudeHome = join(homedir(), ".ember/homes/claude-ocg");
const codexHome = join(homedir(), ".config/ember-spike/codex-home");

function transcripts(dir: string, match: (name: string) => boolean): string[] {
  if (!existsSync(dir)) return [];
  return readdirSync(dir, { recursive: true, withFileTypes: true }).filter((e) => e.isFile() && match(e.name)).map((e) => e.name);
}
const claudeIds = transcripts(join(claudeHome, "projects"), (n) => n.endsWith(".jsonl")).map((n) => n.replace(/\.jsonl$/, ""));
const codexIds = transcripts(join(codexHome, "sessions"), (n) => n.startsWith("rollout-")).map((n) => n.replace(/^rollout-.*?-(\w{8}-\w{4}-\w{4}-\w{4}-\w{12})\.jsonl$/, "$1"));

const dataDir = mkdtempSync(join(tmpdir(), "ember-admin-demo-"));
writeFileSync(join(dataDir, "config.json"), JSON.stringify({
  profiles: [
    { id: "claude-ocg", name: "OpenCode Go（Claude Code）", runtime: "claude", home: claudeHome, access: { kind: "opencode-go", key: "sk-demo-not-a-real-key-1234" } },
    { id: "codex-ocg", name: "OpenCode Go（Codex）", runtime: "codex", home: codexHome, access: { kind: "opencode-go", key: "demo-key-abcdefgh" } },
    { id: "claude-team", name: "团队 Claude 订阅", runtime: "claude", home: "homes/claude-team", access: { kind: "subscription" } },
  ],
  connects: [
    { id: "ds", name: "ember", kind: "slack", mode: "multi-session", bind: { runtime: "claude", profiles: ["claude-ocg"], model: "deepseek-flash" }, slack: { appToken: "xapp-1-demo-aaaaaaaa", botToken: "xoxb-demo-bbbbbbbb", appId: "A0DEMO" } },
    { id: "gpt", name: "ember-gpt", kind: "slack", mode: "single-session", requireMention: false, bind: { runtime: "codex", profiles: ["codex-ocg"] }, slack: { appToken: "xapp-1-demo-cccccccc", botToken: "xoxb-demo-dddddddd" } },
    { id: "claude", name: "ember-claude", kind: "slack", mode: "multi-session", bind: { runtime: "claude", profiles: ["claude-team"], model: "opus" }, enabled: false },
  ],
}));
const settings = new Settings(join(dataDir, "config.json"), dataDir);
const store = new Store(join(dataDir, "ember.db"));

const now = Date.now();
const states = new Map<string, "running" | "warm" | "cold">();
type Seed = { connect: string; extra?: { channel: string; text: string }[]; runtime: "claude" | "codex"; profile: string; id: string | undefined; text: string; ago: number; process: "running" | "warm" | "cold"; turns: [string, string | null, string | null][]; pending?: number };
const seeds: Seed[] = [
  { connect: "ds", runtime: "claude", profile: "claude-ocg", id: claudeIds[0], text: "<@U0C4KHKPWTC> 帮我看一下 Cue 的 staging 为什么今天早上发不出通知，日志在 backroom", ago: 40_000, process: "running", turns: [["input", "completed", "final"], ["input", null, null]] },
  { connect: "gpt", runtime: "codex", profile: "codex-ocg", id: codexIds[0], text: "把 bridge 的 release note 模板改成新的格式，开个 draft PR", ago: 6 * 60_000, process: "warm", turns: [["input", "completed", "block"], ["input", "completed", "final"]],
    extra: [{ channel: "C0OPS", text: "顺便看下 staging 的磁盘告警" }, { channel: "C0DEMO1", text: "PR 里记得附上截图" }] },
  { connect: "ds", runtime: "claude", profile: "claude-ocg", id: claudeIds[1], text: "<@U0C4KHKPWTC> 跑一下 zork 的 android 测试，失败的话看看是哪个", ago: 25 * 60_000, process: "cold", turns: [["input", "failed", null]] },
  { connect: "ds", runtime: "claude", profile: "claude-ocg", id: claudeIds[2], text: "<@U0C4KHKPWTC> 你好", ago: 26 * 3600_000, process: "cold", turns: [["input", "completed", "final"], ["input", "completed", "final"]] },
  { connect: "ds", runtime: "claude", profile: "claude-ocg", id: undefined, text: "<@U0C4KHKPWTC> 刚发的消息，还在排队", ago: 5_000, process: "cold", turns: [], pending: 1 },
];
seeds.forEach((seed, i) => {
  const ts = `${Math.floor((now - seed.ago) / 1000)}.${String(i).padStart(6, "0")}`;
  const single = seed.connect === "gpt";
  const key = single ? `${seed.connect}:all` : `${seed.connect}:C0DEMO${i}:${ts}`;
  store.insertSession({ key, connect: seed.connect, scope: single ? "all" : "thread", runtime: seed.runtime, profile: seed.profile, model: null,
    workspace: join(dataDir, "sessions", String(i)), token: `demo-${i}`, createdAt: now - seed.ago - 600_000, lastActiveAt: now - seed.ago });
  if (seed.id) store.setRuntimeSessionId(key, seed.id);
  if (single) { store.setBinding(seed.connect, key); store.setTitle(key, "bridge 值班"); }
  const say = (channel: string, threadTs: string, mts: string, text: string, at: number) => {
    const thread = store.openThread({ surface: "slack:T0DEMO", channel, threadTs, createdBy: `slack:${seed.connect}:U09ABCDEF` });
    store.joinThread(thread.id, key, seed.connect);
    const { seq } = store.insertMessage({ thread: thread.id, ts: mts, authorKind: "person", author: "U09ABCDEF", text, createdAt: at });
    store.deliver(seq, [key]);
    if (!seed.pending) store.markDelivered(key, [seq]);
  };
  say(`C0DEMO${i}`, ts, ts, seed.text, now - seed.ago);
  seed.extra?.forEach((m, j) => {
    const at = now - seed.ago + (j + 1) * 60_000;
    const mts = `${Math.floor(at / 1000)}.${String(j + 1).padStart(6, "0")}`;
    say(m.channel, m.channel === `C0DEMO${i}` ? ts : mts, mts, m.text, at);
  });
  seed.turns.forEach(([kind, outcome, declared], j) => {
    const id = `${key}-t${j}`;
    store.startTurn(id, key, kind as "input");
    if (outcome) store.endTurn(id, outcome, outcome === "failed" ? "model: 429 rate limit exceeded" : null, declared);
  });
  states.set(key, seed.process);
});

const demoWorkspace = (botUserId: string, botName: string) => ({ team: "Cue", teamId: "T0DEMO", url: "https://cue.slack.com/", botUserId, botName });
// ember's own chat works in the demo: messages are recorded; no agent answers.
const openChat = (key: string, user: string, title: string | null = null) => {
  const thread = store.openThread({ surface: EMBER_SURFACE, channel: INTERNAL_CHANNEL, threadTs: nextTs(), title, createdBy: user });
  store.joinThread(thread.id, key, "ember");
  return thread;
};
const hub = {
  processState: (key: string) => states.get(key) ?? "cold", stop: async () => {}, evict: async () => {},
  live: new LiveHub(() => undefined),
  newSession: (o: { runtime: "claude" | "codex"; profile?: string; model?: string; effort?: string; createdBy: string }) => {
    const key = `ember:c-${Math.random().toString(16).slice(2, 12)}`;
    const now = Date.now();
    store.insertSession({ key, connect: "ember", scope: "all", title: null, createdBy: o.createdBy, runtime: o.runtime,
      profile: o.profile ?? "cc", model: o.model ?? null, effort: o.effort ?? null, workspace: join(dataDir, "sessions", key.replace(":", "-")), token: key, createdAt: now, lastActiveAt: now });
    return { key, thread: openChat(key, o.createdBy) };
  },
  openChat,
  addToThread: (thread: number, key: string) => store.joinThread(thread, key, "ember"),
  say: (thread: number, user: string, text: string, attachments: Attachment[] = [], quotes: Quote[] = []) =>
    store.insertMessage({ thread, ts: nextTs(), authorKind: "person", author: user, text, attachments, quotes }).seq,
  archive: (key: string, archived: boolean) => store.setArchived(key, archived),
  deleteSession: async (key: string) => store.deleteSession(key),
} as unknown as Hub;
const connections = {
  changes: new EventEmitter(),
  state: (c: { enabled: boolean; id: string }) => (!c.enabled ? { state: "disabled" } : c.id === "gpt" ? { state: "reconnecting", botUserId: "UGPT", lastError: "socket closed", workspace: demoWorkspace("UGPT", "ember-gpt") } : { state: "connected", botUserId: "U0C4KHKPWTC", lastError: null, workspace: demoWorkspace("U0C4KHKPWTC", "ember") }),
  reconcile: async () => {},
  chats: new Map(["ds", "gpt"].map((id) => [id, {
    userName: async (user: string) => ({ U09ABCDEF: "左子健", U09KY0GE28K: "左子健" } as Record<string, string>)[user] ?? null,
    channelName: async (channel: string) => ({ C0OPS: "ops", C0DEMO0: "cue-dev", C0DEMO1: "bridge" } as Record<string, string>)[channel] ?? null,
  }])),
} as unknown as Connections;
// A stand-in login command that behaves like `claude auth login` / `codex login --device-auth` without signing anything in.
const fakeLogin = join(dataDir, "fake-login");
writeFileSync(fakeLogin, `#!/bin/sh
if [ "$1" = "auth" ]; then echo "visit: https://claude.com/cai/oauth/authorize?code=true&client_id=demo"; printf "Paste code here if prompted > "; read c; exit 1; fi
printf "Open https://auth.openai.com/codex/device\\nEnter code DEMO-12345\\n"; sleep 600
`, { mode: 0o755 });
// Slack's app API, answered locally.
let manifest: any = slackManifest("ember");
const slackApps = {
  configured: true,
  exportManifest: async () => structuredClone(manifest),
  updateManifest: async (_: string, next: any) => { manifest = next; return { permissionsUpdated: true }; },
  createApp: async () => ({ appId: "A0DEMO2", oauthAuthorizeUrl: "" }),
  setIcon: async () => {},
} as unknown as SlackApps;
const api = new AdminApi({
  settings, store, hub, connections, slackApps, names: new Map(),
  // With EMBER_MESH_SECRET set, requests relayed by an ember-mesh started with the same secret are accepted.
  ...(process.env.EMBER_MESH_SECRET ? { mesh: { secret: () => process.env.EMBER_MESH_SECRET!, status: () => ({ state: "running" as const, origin: null, station: null, workspace: null, name: null }) } } : {}),
  logins: new LoginManager(dataDir, { claude: fakeLogin, codex: fakeLogin }),
  checkProfile: async (p) => (p.kind === "subscription"
    ? { state: "login", detail: "还没有登录", models: null, checkedAt: Date.now() }
    : { state: "ok", detail: "OpenCode Go 可用", models: ["deepseek-flash", "glm-5", "kimi-k2", "qwen3-coder"], checkedAt: Date.now() }),
});
const ui = join(import.meta.dirname, "..", "dist", "admin");

createServer((req, res) => {
  const pathname = new URL(req.url ?? "/", "http://demo").pathname;
  if (pathname.startsWith("/admin/api/")) return void api.handle(req, res);
  // Files by path; anything else (client routes, session keys with dots) gets the app shell.
  const rel = normalize(pathname.replace(/^\/admin\/?/, "")) || "index.html";
  const types: Record<string, string> = { ".js": "text/javascript", ".css": "text/css", ".svg": "image/svg+xml", ".png": "image/png", ".webmanifest": "application/manifest+json", ".woff2": "font/woff2" };
  void readFile(join(ui, rel))
    .then((body) => res.writeHead(200, { "content-type": types[extname(rel)] ?? "text/html" }).end(body))
    .catch(() => readFile(join(ui, "index.html")).then((body) => res.writeHead(200, { "content-type": "text/html" }).end(body)))
    .catch(() => res.writeHead(404).end());
}).listen(port, "127.0.0.1", () => console.log(`admin demo on http://127.0.0.1:${port}/admin, data ${dataDir}; claude transcripts ${claudeIds.length}, codex ${codexIds.length}`));
