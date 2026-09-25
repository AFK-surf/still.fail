// ember entry point: node src/main.ts
import { readFile } from "node:fs/promises";
import { createServer, type ServerResponse } from "node:http";
import { dirname, extname, join, normalize } from "node:path";
import { fileURLToPath } from "node:url";
import { AdminApi } from "./admin/api.ts";
import { linkAgentHome } from "./agent-home.ts";
import { BotConnections } from "./bots.ts";
import { SlackSurface } from "./chat/slack.ts";
import { Hub } from "./hub.ts";
import { log } from "./log.ts";
import { McpEndpoint } from "./mcp.ts";
import { ClaudeDriver } from "./runtime/claude.ts";
import { CodexDriver } from "./runtime/codex.ts";
import { reapStaleGroups } from "./runtime/process.ts";
import { Settings } from "./settings.ts";
import { Store } from "./store.ts";

const settings = Settings.load();
const store = new Store(join(settings.dataDir, "ember.db"));
linkAgentHome(settings.config.agentHome, settings.config.profiles);

const reaped = await reapStaleGroups(store);
if (reaped > 0) log.warn("reaped runtime processes left by a previous run", { count: reaped });

const mcpUrl = `http://${settings.config.http.host}:${settings.config.http.port}/mcp`;
const bots = new BotConnections((bot) => new SlackSurface(bot.slack), (botId, message) => hub.accept(botId, message));
const hub = new Hub({
  config: () => settings.config,
  store,
  chats: bots.chats,
  mcpUrl,
  drivers: { claude: new ClaudeDriver(store), codex: new CodexDriver(store) },
});
const mcp = new McpEndpoint((token) => store.sessionByToken(token)?.key, hub.tools());
const admin = new AdminApi({ settings, store, hub, bots });

settings.onChange((config) => {
  linkAgentHome(config.agentHome, config.profiles);
  void bots.reconcile(config);
});

const UI_DIR = join(dirname(fileURLToPath(import.meta.url)), "admin", "ui");
const TYPES: Record<string, string> = {
  ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8", ".svg": "image/svg+xml",
};

/** /admin and client-side routes get the app shell; /admin/assets/* are files. */
async function serveUi(pathname: string, res: ServerResponse): Promise<void> {
  const file = pathname.startsWith("/admin/assets/") ? normalize(pathname.slice("/admin/assets/".length)) : "index.html";
  if (file.startsWith("..")) {
    res.writeHead(400).end();
    return;
  }
  try {
    const content = await readFile(join(UI_DIR, file));
    res.writeHead(200, { "content-type": TYPES[extname(file)] ?? "application/octet-stream", "cache-control": "no-cache" }).end(content);
  } catch {
    res.writeHead(404).end();
  }
}

const server = createServer((req, res) => {
  const pathname = new URL(req.url ?? "/", "http://ember").pathname;
  if (pathname === "/mcp") {
    void mcp.handle(req, res).catch((error) => {
      log.error("mcp request failed", { error });
      if (!res.headersSent) res.writeHead(500).end();
    });
  } else if (pathname === "/health") {
    res.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify({ ok: true }));
  } else if (pathname.startsWith("/admin/api/")) {
    void admin.handle(req, res);
  } else if (pathname === "/admin" || pathname.startsWith("/admin/")) {
    void serveUi(pathname, res);
  } else if (pathname === "/") {
    res.writeHead(302, { location: "/admin" }).end();
  } else {
    res.writeHead(404).end();
  }
});
await new Promise<void>((resolve) => server.listen(settings.config.http.port, settings.config.http.host, resolve));
log.info("ember listening", { mcpUrl, admin: `http://${settings.config.http.host}:${settings.config.http.port}/admin` });

await bots.reconcile(settings.config);
if (bots.chats.size === 0) log.warn("no bot is connected; add or enable one on the admin page");
await hub.recover();
const evictTimer = setInterval(() => hub.evictIdle(), 60_000);

let stopping = false;
async function shutdown(signal: string): Promise<void> {
  if (stopping) return;
  stopping = true;
  log.info("shutting down", { signal });
  clearInterval(evictTimer);
  await bots.stopAll();
  await hub.shutdown();
  server.close();
  store.close();
  process.exit(0);
}
process.on("SIGTERM", () => void shutdown("SIGTERM"));
process.on("SIGINT", () => void shutdown("SIGINT"));
