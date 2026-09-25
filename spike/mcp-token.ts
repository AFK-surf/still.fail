// Spike 3: can an HTTP MCP server identify the calling session from a token the
// runtime reads out of its environment? Claude: header with ${VAR} expansion in
// user-scope config. Codex: bearer_token_env_var. Usage: node spike/mcp-token.ts [cwd]
import { randomBytes } from "node:crypto";
import { existsSync, readFileSync, writeFileSync, appendFileSync } from "node:fs";
import { createServer } from "node:http";
import { join } from "node:path";
import { claudeEnv, codexEnv, MODEL, report, run, SPIKE_ROOT } from "./lib.ts";

const cwd = process.argv[2] ?? process.cwd();
const TOKEN_VAR = "EMBER_SESSION_TOKEN";
const sessions = new Map([
  [randomBytes(16).toString("hex"), "claude-session-A"],
  [randomBytes(16).toString("hex"), "codex-session-B"],
]);
const [tokenA, tokenB] = [...sessions.keys()] as [string, string];
const seen: Record<string, unknown>[] = [];

const server = createServer((req, res) => {
  if (req.method !== "POST") { res.writeHead(405).end(); return; }
  let body = "";
  req.on("data", (chunk) => { body += chunk; });
  req.on("end", () => {
    const auth = req.headers.authorization ?? "";
    const who = sessions.get(auth.replace(/^Bearer\s+/i, "")) ?? null;
    const msg = JSON.parse(body) as { id?: number | string; method: string; params?: any };
    seen.push({ method: msg.method, authorized: who ?? `NO (${auth ? auth.slice(0, 24) + "…" : "missing"})` });
    if (!who) { res.writeHead(401, { "content-type": "application/json" }).end(JSON.stringify({ error: "unauthorized" })); return; }
    if (msg.id === undefined) { res.writeHead(202).end(); return; }
    const reply = (result: unknown) =>
      res.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify({ jsonrpc: "2.0", id: msg.id, result }));
    switch (msg.method) {
      case "initialize":
        return reply({ protocolVersion: msg.params?.protocolVersion ?? "2025-06-18", capabilities: { tools: {} }, serverInfo: { name: "ember", version: "0" } });
      case "tools/list":
        return reply({ tools: [{ name: "whoami", description: "Return which ember session the caller is.", inputSchema: { type: "object", properties: {}, additionalProperties: false } }] });
      case "tools/call":
        return reply({ content: [{ type: "text", text: `You are ${who}.` }] });
      default:
        return res.writeHead(200, { "content-type": "application/json" })
          .end(JSON.stringify({ jsonrpc: "2.0", id: msg.id, error: { code: -32601, message: "not found" } }));
    }
  });
});
await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
const url = `http://127.0.0.1:${(server.address() as { port: number }).port}/mcp`;

// Claude: user-scope server in the isolated config home, token referenced as ${VAR}.
const claude = claudeEnv("ember-spike-mcp-a");
const claudeJson = join(claude.CLAUDE_CONFIG_DIR!, ".claude.json");
const config = existsSync(claudeJson) ? JSON.parse(readFileSync(claudeJson, "utf8")) : {};
config.mcpServers = { ember: { type: "http", url, headers: { Authorization: `Bearer \${${TOKEN_VAR}}` } } };
writeFileSync(claudeJson, JSON.stringify(config, null, 2));

// Codex: bearer_token_env_var names the variable; codex reads it at connect time.
const codex = codexEnv("ember-spike-mcp-b");
appendFileSync(join(codex.CODEX_HOME!, "config.toml"),
  `\n[mcp_servers.ember]\nurl = "${url}"\nbearer_token_env_var = "${TOKEN_VAR}"\n`);

const ask = "Call the whoami tool from the ember MCP server and reply with exactly what it returned.";
const results: Record<string, unknown>[] = [];
try {
  const c = await run("claude", ["-p", ask, "--dangerously-skip-permissions", "--model", MODEL],
    { cwd, env: { ...claude, [TOKEN_VAR]: tokenA }, timeout: 180_000 });
  results.push({ runtime: "claude", expected: "claude-session-A", answer: c.stdout.trim().slice(0, 200) });
} catch (error: any) {
  results.push({ runtime: "claude", expected: "claude-session-A", answer: `FAILED: ${String(error.stderr || error.message).slice(0, 300)}` });
}
try {
  const x = await run("codex", ["exec", "--json", "--skip-git-repo-check", "--dangerously-bypass-approvals-and-sandbox", ask],
    { cwd, env: { ...codex, [TOKEN_VAR]: tokenB }, timeout: 180_000 });
  const events = x.stdout.trim().split("\n").flatMap((line) => { try { return [JSON.parse(line)]; } catch { return []; } });
  const items = events.filter((e) => e.type === "item.completed").map((e) => e.item);
  results.push({ runtime: "codex", expected: "codex-session-B",
    answer: String(items.filter((i: any) => i.type === "agent_message").at(-1)?.text ?? "").slice(0, 200) });
  console.log("codex items:", JSON.stringify(items.map((i: any) => ({ type: i.type, ...(i.type === "error" ? { message: i.message } : {}),
    ...(i.type === "mcp_tool_call" ? { server: i.server, tool: i.tool, status: i.status } : {}) }))));
  console.log("codex stderr tail:", x.stderr.slice(-1500));
} catch (error: any) {
  results.push({ runtime: "codex", expected: "codex-session-B", answer: `FAILED: ${String(error.stderr || error.message).slice(-300)}` });
}
server.close();

report(`MCP token via env (model ${MODEL}, spike root ${SPIKE_ROOT})`, results);
report("requests the MCP server saw", seen);
