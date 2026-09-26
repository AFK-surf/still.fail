// ember entry point: node src/main.ts
import { readFile } from "node:fs/promises";
import { createServer, type ServerResponse } from "node:http";
import { dirname, extname, join, normalize } from "node:path";
import { fileURLToPath } from "node:url";
import { AdminApi } from "./admin/api.ts";
import { linkAgentHome } from "./agent-home.ts";
import { Connections } from "./connections.ts";
import { SlackSurface, slackTeamOf } from "./chat/slack.ts";
import { Hub } from "./hub.ts";
import { log } from "./log.ts";
import { LoginManager } from "./login.ts";
import { InternalChat } from "./chat/internal.ts";
import { McpEndpoint } from "./mcp.ts";
import { MeshSupervisor } from "./mesh.ts";
import { checkQuota } from "./quota.ts";
import { ClaudeDriver } from "./runtime/claude.ts";
import { CodexDriver } from "./runtime/codex.ts";
import { reapStaleGroups } from "./runtime/process.ts";
import { Settings } from "./settings.ts";
import { Store } from "./store.ts";
import { builtKey, ErrorReports } from "./telemetry.ts";

const settings = Settings.load();
// Built by `pnpm build` from web/ into dist/admin.
const UI_DIR = join(dirname(fileURLToPath(import.meta.url)), "..", "dist", "admin");
// Errors before the mesh supervisor is made are reported without the station's id.
let stationId = (): string | null => null;
const reports = new ErrorReports({ key: builtKey(UI_DIR), enabled: () => settings.config.telemetry.errors, station: () => stationId() });
/** Display names of people who reached this station through ember cloud, by email. */
const names = new Map<string, string>();
const dbPath = join(settings.dataDir, "ember.db");
// Moving older data into threads names Slack threads by team; ask Slack once, before the store opens.
const teams = new Map<string, string>();
if (Store.needsTeams(dbPath)) {
  await Promise.all(settings.config.connects.filter((c) => c.slack.botToken).map(async (c) => {
    const team = await slackTeamOf(c.slack.botToken);
    if (team) teams.set(c.id, team);
  }));
}
const store = new Store(dbPath, { teams });
linkAgentHome(settings.config.agentHome, settings.config.profiles);

const reaped = await reapStaleGroups(store);
if (reaped > 0) log.warn("reaped runtime processes left by a previous run", { count: reaped });

const mcpUrl = `http://${settings.config.http.host}:${settings.config.http.port}/mcp`;
// One chat connection per connect; Slack is the only kind so far.
const connections: Connections = new Connections(
  (connect) => new SlackSurface(connect.slack),
  (connectId, event): Promise<void> => hub.receive(connectId, event),
);
const codex = new CodexDriver(store);
const hub: Hub = new Hub({
  config: () => settings.config,
  store,
  chats: connections.chats,
  internal: new InternalChat((user) => names.get(user) ?? (user === "local" ? "管理员" : user)),
  mcpUrl,
  drivers: { claude: new ClaudeDriver(store), codex },
});
const mcp = new McpEndpoint((token) => store.sessionByToken(token)?.key, hub.tools());
const logins = new LoginManager(settings.config.dataDir);
const mesh = new MeshSupervisor({ dataDir: settings.config.dataDir, admin: `http://127.0.0.1:${settings.config.adminHttp.port}` });
stationId = () => mesh.status().station;
const admin = new AdminApi({ settings, store, hub, connections, logins, names, mesh, checkOnStart: true, quota: (profile) => checkQuota(profile, (p) => codex.rateLimits(p)) });

settings.onChange((config) => {
  reports.update();
  linkAgentHome(config.agentHome, config.profiles);
  void connections.reconcile(config);
});

const TYPES: Record<string, string> = {
  ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8",
  ".svg": "image/svg+xml", ".png": "image/png", ".webmanifest": "application/manifest+json", ".woff2": "font/woff2",
};

/** Files under dist/admin by path; anything else gets index.html, where the client router takes over. */
async function serveUi(pathname: string, res: ServerResponse): Promise<void> {
  const relative = normalize(pathname.slice("/admin".length)).replace(/^\/+/, "");
  if (relative.startsWith("..")) {
    res.writeHead(400).end();
    return;
  }
  const hashed = relative.startsWith("assets/");
  for (const file of relative && extname(relative) ? [relative, "index.html"] : ["index.html"]) {
    try {
      const content = await readFile(join(UI_DIR, file));
      res.writeHead(200, {
        "content-type": TYPES[extname(file)] ?? "application/octet-stream",
        // Vite fingerprints assets; the shell must always be revalidated.
        "cache-control": hashed && file === relative ? "public, max-age=31536000, immutable" : "no-cache",
      }).end(content);
      return;
    } catch {
      // try the next candidate
    }
  }
  res.writeHead(503, { "content-type": "text/plain; charset=utf-8" }).end("admin client not built: run `pnpm build`");
}

// Agents' MCP endpoint: loopback only.
const server = createServer((req, res) => {
  const pathname = new URL(req.url ?? "/", "http://ember").pathname;
  if (pathname === "/mcp") {
    void mcp.handle(req, res).catch((error) => {
      log.error("mcp request failed", { error });
      if (!res.headersSent) res.writeHead(500).end();
    });
  } else if (pathname === "/health") {
    res.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify({ ok: true }));
  } else {
    res.writeHead(404).end();
  }
});
await new Promise<void>((resolve) => server.listen(settings.config.http.port, settings.config.http.host, resolve));

// The admin page on its own port, the only one a tunnel should point at.
const adminServer = createServer((req, res) => {
  const pathname = new URL(req.url ?? "/", "http://ember").pathname;
  if (pathname.startsWith("/admin/api/")) void admin.handle(req, res);
  else if (pathname === "/admin" || pathname.startsWith("/admin/")) void serveUi(pathname, res);
  else if (pathname === "/") res.writeHead(302, { location: "/admin" }).end();
  else res.writeHead(404).end();
});
const { host: adminHost, port: adminPort } = settings.config.adminHttp;
await new Promise<void>((resolve) => adminServer.listen(adminPort, adminHost, resolve));
log.info("ember listening", { mcpUrl, admin: `http://${adminHost}:${adminPort}/admin` });

await connections.reconcile(settings.config);
if (connections.chats.size === 0) log.warn("no connect is connected; add or enable one on the admin page");
await hub.recover();
mesh.start();

let stopping = false;
async function shutdown(signal: string): Promise<void> {
  if (stopping) return;
  stopping = true;
  log.info("shutting down", { signal });
  logins.stopAll();
  await mesh.stop();
  await connections.stopAll();
  await hub.shutdown();
  server.close();
  adminServer.close();
  store.close();
  await reports.shutdown();
  process.exit(0);
}
process.on("SIGTERM", () => void shutdown("SIGTERM"));
process.on("SIGINT", () => void shutdown("SIGINT"));
