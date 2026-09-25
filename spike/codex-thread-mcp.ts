// Spike 3b: in ONE shared codex app-server, can each thread carry its own MCP
// token through thread/start `config`, so the MCP server can tell sessions
// apart? config.toml has no MCP server; it exists only per thread.
// Usage: node spike/codex-thread-mcp.ts [cwd]
import { randomBytes } from "node:crypto";
import { codexEnv, MODEL, report, startAppServer, startWhoamiServer } from "./lib.ts";

const cwd = process.argv[2] ?? process.cwd();
const names = ["thread-A", "thread-B", "thread-C"];
const tokens = names.map(() => randomBytes(16).toString("hex"));
const server = await startWhoamiServer(new Map(tokens.map((token, i) => [token, names[i]!])));
const app = await startAppServer(cwd, codexEnv("ember-spike-thread-mcp"));

const perThreadConfig = (token: string) => ({
  "mcp_servers.ember.url": server.url,
  "mcp_servers.ember.http_headers": { Authorization: `Bearer ${token}` },
});

const rows: Record<string, unknown>[] = [];
try {
  const threads = await Promise.all(tokens.map(async (token) =>
    (await app.request("thread/start", { cwd, model: MODEL, approvalPolicy: "never", config: perThreadConfig(token) })).thread.id as string));
  // Run the three turns concurrently: the tokens must not bleed across threads.
  await Promise.all(threads.map(async (threadId, i) => {
    const items = await app.runTurn(threadId,
      "Call the whoami tool from the ember MCP server and reply with exactly what it returned.");
    rows.push({
      expected: names[i],
      mcpCalls: items.filter((item) => item?.type === "mcpToolCall").map((item) => `${item.server}.${item.tool}:${item.status}`).join(",") || "none",
      answer: String(items.filter((item) => item?.type === "agentMessage").at(-1)?.text ?? "").slice(0, 120),
    });
  }));
} catch (error) {
  rows.push({ error: String(error).slice(0, 300) });
} finally {
  app.killTree();
  server.close();
}

report(`per-thread MCP token in one shared app-server (model ${MODEL})`, rows);
report("requests the MCP server saw", server.seen);
