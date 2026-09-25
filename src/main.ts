// ember entry point: node src/main.ts
import { createServer } from "node:http";
import { join } from "node:path";
import { SlackSurface } from "./chat/slack.ts";
import { loadConfig } from "./config.ts";
import { Hub } from "./hub.ts";
import { log } from "./log.ts";
import { McpEndpoint } from "./mcp.ts";
import { ClaudeDriver } from "./runtime/claude.ts";
import { CodexDriver } from "./runtime/codex.ts";
import { reapStaleGroups } from "./runtime/process.ts";
import { Store } from "./store.ts";

const config = loadConfig();
if (config.profiles.length === 0) throw new Error("no profiles configured; see docs/operations.md");
const store = new Store(join(config.dataDir, "ember.db"));

const reaped = await reapStaleGroups(store);
if (reaped > 0) log.warn("reaped runtime processes left by a previous run", { count: reaped });

const chat = new SlackSurface(config.slack);
const mcpUrl = `http://${config.http.host}:${config.http.port}/mcp`;
const hub = new Hub({
  config, store, chat, mcpUrl,
  drivers: { claude: new ClaudeDriver(store), codex: new CodexDriver(store) },
});
const mcp = new McpEndpoint((token) => store.sessionByToken(token)?.key, hub.tools());

const server = createServer((req, res) => {
  if (req.url === "/mcp") {
    void mcp.handle(req, res).catch((error) => {
      log.error("mcp request failed", { error });
      if (!res.headersSent) res.writeHead(500).end();
    });
  } else if (req.url === "/health") {
    res.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify({ ok: true }));
  } else {
    res.writeHead(404).end();
  }
});
await new Promise<void>((resolve) => server.listen(config.http.port, config.http.host, resolve));
log.info("ember listening", { mcpUrl });

await chat.start((message) => hub.accept(message));
await hub.recover();
const evictTimer = setInterval(() => hub.evictIdle(), 60_000);

let stopping = false;
async function shutdown(signal: string): Promise<void> {
  if (stopping) return;
  stopping = true;
  log.info("shutting down", { signal });
  clearInterval(evictTimer);
  await chat.stop();
  await hub.shutdown();
  server.close();
  store.close();
  process.exit(0);
}
process.on("SIGTERM", () => void shutdown("SIGTERM"));
process.on("SIGINT", () => void shutdown("SIGINT"));
