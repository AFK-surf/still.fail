// ember entry point: node src/main.ts
import { readFile } from "node:fs/promises";
import { rmSync } from "node:fs";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { dirname, extname, join, normalize } from "node:path";
import { fileURLToPath } from "node:url";
import { AdminApi } from "./admin/api.ts";
import { MachineLogins } from "./machine-logins.ts";
import { linkAgentHome, linkTranscripts } from "./agent-home.ts";
import { Connections } from "./connections.ts";
import { NameBook } from "./chat/names.ts";
import { SlackSurface } from "./chat/slack.ts";
import { Hub } from "./hub.ts";
import { log } from "./log.ts";
import { LoginManager } from "./login.ts";
import { InternalChat } from "./chat/internal.ts";
import { McpEndpoint } from "./mcp.ts";
import { MeshLink } from "./mesh.ts";
import { checkQuota, machineUsage } from "./quota.ts";
import { ClaudeDriver } from "./runtime/claude.ts";
import { CodexDriver } from "./runtime/codex.ts";
import { reapStaleGroups } from "./runtime/process.ts";
import { listen, PortTaken } from "./ports.ts";
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
const store = new Store(dbPath);
linkAgentHome(settings.config.agentHome, settings.config.profiles);
linkTranscripts(settings.config.dataDir, settings.config.profiles);

const reaped = await reapStaleGroups(store);
if (reaped > 0) log.warn("reaped runtime processes left by a previous run", { count: reaped });

// This is the station's Node part, run by ember-station (mesh/station): it answers the admin API on a Unix socket only
// ember-station connects to (EMBER_ADMIN_SOCKET), which serves the admin page here and relays clients' requests.
const adminSocket = process.env.EMBER_ADMIN_SOCKET;
if (!adminSocket) {
  log.error("run ember through ember-station (`ember start`), which gives this process its admin socket");
  process.exit(1);
}
// Both listen first: the agents' MCP endpoint is told to them by its address. Each answers once the station is up
// (503 until then); /healthz says when it is, for ember-station.
type Handler = (req: IncomingMessage, res: ServerResponse) => void;
let onMcp: Handler | undefined;
let onAdmin: Handler | undefined;
let up = false;
const server = createServer((req, res) => (onMcp ? onMcp(req, res) : res.writeHead(503).end()));
const adminServer = createServer((req, res) => {
  if (req.url === "/healthz") res.writeHead(up ? 200 : 503).end();
  else if (onAdmin) onAdmin(req, res);
  else res.writeHead(503).end();
});
const { http } = settings.config;
let mcpPort: number;
try {
  mcpPort = await listen(server, http.host, http.port, http.named, "agent 的 MCP 端点");
} catch (error) {
  if (!(error instanceof PortTaken)) throw error;
  log.error(error.message);
  process.exit(1);
}
if (mcpPort !== http.port) log.warn("the MCP endpoint's usual port is taken; listening on a free one", { port: mcpPort });
rmSync(adminSocket, { force: true });
await new Promise<void>((resolve) => adminServer.listen(adminSocket, resolve));
const mcpUrl = `http://${http.host}:${mcpPort}/mcp`;
// One chat connection per connect; Slack is the only kind so far.
// Slack's names for people and channels, kept on disk; learning new ones refreshes what shows them.
const slackNames = new NameBook(join(settings.config.dataDir, "slack-names.json"));
slackNames.onLearn(() => {
  for (const session of store.listSessions()) store.notify(session.key);
  for (const thread of store.listThreads("local")) store.changes.emit("thread", { id: thread.id, entries: [] });
});
const connections: Connections = new Connections(
  (connect) => new SlackSurface(connect.slack, slackNames),
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
  // A session's /o/ link on ember cloud (it opens the app where there is one, else the web), once this station is in
  // a workspace.
  link: (session) => {
    const { origin, station, workspaceId } = mesh.status();
    return origin && station && workspaceId ? `${origin}/o/${workspaceId}/${station}/${encodeURIComponent(session)}` : null;
  },
});
const mcp = new McpEndpoint((token) => store.sessionByToken(token)?.key, hub.tools());
const logins = new LoginManager(settings.config.dataDir);
const mesh = new MeshLink({ dataDir: settings.config.dataDir, traces: () => settings.config.telemetry.traces });
stationId = () => mesh.status().station;
// The machine's own Claude Code and Codex logins, read at start and again as pages ask (machine-logins.ts).
const machineLogins = new MachineLogins(process.env, machineUsage);
void machineLogins.refresh();
const admin = new AdminApi({ settings, store, hub, connections, logins, names, mesh, checkOnStart: true, machineLogins, quota: (profile) => checkQuota(profile, (p) => codex.rateLimits(p)), codexModels: (profile) => codex.models(profile) });

settings.onChange((config) => {
  reports.update();
  linkAgentHome(config.agentHome, config.profiles);
  linkTranscripts(config.dataDir, config.profiles);
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
onMcp = (req, res) => {
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
};

onAdmin = (req, res) => {
  const pathname = new URL(req.url ?? "/", "http://ember").pathname;
  if (pathname.startsWith("/admin/api/")) void admin.handle(req, res);
  else if (pathname === "/admin" || pathname.startsWith("/admin/")) void serveUi(pathname, res);
  else if (pathname === "/") res.writeHead(302, { location: "/admin" }).end();
  else res.writeHead(404).end();
};
log.info("ember listening", { mcpUrl, admin: adminSocket });

await connections.reconcile(settings.config);
if (connections.chats.size === 0) log.warn("no connect is connected; add or enable one on the admin page");
await hub.recover();
mesh.start();
up = true;

// Ends with the ember-station that runs it: orphaned, it would hold the station's runtimes with nobody to reach them.
const parent = process.ppid;
setInterval(() => {
  if (process.ppid !== parent) void shutdown("ember-station gone");
}, 2000).unref();

let stopping = false;
async function shutdown(signal: string): Promise<void> {
  if (stopping) return;
  stopping = true;
  log.info("shutting down", { signal });
  logins.stopAll();
  mesh.stop();
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
