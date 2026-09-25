// Spike 3: can an HTTP MCP server identify the calling session from a token the
// runtime reads out of its environment? Claude: header with ${VAR} expansion in
// user-scope config. Codex: bearer_token_env_var. Usage: node spike/mcp-token.ts [cwd]
import { randomBytes } from "node:crypto";
import { existsSync, readFileSync, writeFileSync, appendFileSync } from "node:fs";
import { join } from "node:path";
import { claudeEnv, codexEnv, MODEL, report, run, SPIKE_ROOT, startWhoamiServer } from "./lib.ts";

const cwd = process.argv[2] ?? process.cwd();
const TOKEN_VAR = "EMBER_SESSION_TOKEN";
const [tokenA, tokenB] = [randomBytes(16).toString("hex"), randomBytes(16).toString("hex")];
const server = await startWhoamiServer(new Map([[tokenA, "claude-session-A"], [tokenB, "codex-session-B"]]));

// Claude: user-scope server in the isolated config home, token referenced as ${VAR}.
const claude = claudeEnv("ember-spike-mcp-a");
const claudeJson = join(claude.CLAUDE_CONFIG_DIR!, ".claude.json");
const config = existsSync(claudeJson) ? JSON.parse(readFileSync(claudeJson, "utf8")) : {};
config.mcpServers = { ember: { type: "http", url: server.url, headers: { Authorization: `Bearer \${${TOKEN_VAR}}` } } };
writeFileSync(claudeJson, JSON.stringify(config, null, 2));

// Codex: bearer_token_env_var names the variable; codex reads it at connect time.
const codex = codexEnv("ember-spike-mcp-b");
appendFileSync(join(codex.CODEX_HOME!, "config.toml"),
  `\n[mcp_servers.ember]\nurl = "${server.url}"\nbearer_token_env_var = "${TOKEN_VAR}"\n`);

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
} catch (error: any) {
  results.push({ runtime: "codex", expected: "codex-session-B", answer: `FAILED: ${String(error.stderr || error.message).slice(-300)}` });
}
server.close();

report(`MCP token via env (model ${MODEL}, spike root ${SPIKE_ROOT})`, results);
report("requests the MCP server saw", server.seen);
