// End-to-end run against real runtimes (OpenCode Go), with an in-memory chat
// instead of Slack: first question, follow-up, then a follow-up after the
// session went cold. Usage: node scripts/e2e.ts [claude|codex ...]
// Needs ~/.config/ember-spike/opencode-go.env (OPENCODE_GO_KEY=…).
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import type { ChatMessage, ChatSurface, ThreadRef } from "../src/chat/types.ts";
import { parseConfig, type RuntimeKind } from "../src/config.ts";
import { Hub, sessionKey } from "../src/hub.ts";
import { McpEndpoint } from "../src/mcp.ts";
import { ClaudeDriver } from "../src/runtime/claude.ts";
import { CodexDriver } from "../src/runtime/codex.ts";
import { Store } from "../src/store.ts";

const MODEL = process.env.EMBER_E2E_MODEL ?? "deepseek-flash";
const key = /^OPENCODE_GO_KEY=(.+)$/m.exec(readFileSync(join(homedir(), ".config/ember-spike/opencode-go.env"), "utf8"))?.[1]?.trim();
if (!key) throw new Error("OPENCODE_GO_KEY missing");
const runtimes = (process.argv.slice(2).length ? process.argv.slice(2) : ["claude", "codex"]) as RuntimeKind[];

const dataDir = mkdtempSync(join(tmpdir(), "ember-e2e-"));
const codexHome = join(dataDir, "homes", "codex");
mkdirSync(codexHome, { recursive: true });
writeFileSync(join(codexHome, "config.toml"), [
  `model = "${MODEL}"`, `model_provider = "opencode-go"`, ``,
  `[model_providers.opencode-go]`, `name = "OpenCode Go"`, `base_url = "https://opencode.ai/zen/go/v1"`,
  `env_key = "OPENCODE_GO_KEY"`, `wire_api = "responses"`,
  `env_http_headers = { "x-opencode-session" = "OPENCODE_SESSION" }`, ``,
].join("\n"));

const config = parseConfig({
  http: { port: 0 },
  bots: [
    { id: "claude", runtime: "claude", profile: "claude-ocg", model: MODEL },
    { id: "codex", runtime: "codex", profile: "codex-ocg", model: MODEL },
  ],
  maxWarmClaude: 0,
  warmMinutes: 0,
  profiles: [
    { id: "claude-ocg", runtime: "claude", home: "homes/claude", env: {
      ANTHROPIC_BASE_URL: "https://opencode.ai/zen/go", ANTHROPIC_API_KEY: key,
      ANTHROPIC_CUSTOM_HEADERS: "x-opencode-session: {route}",
      ANTHROPIC_DEFAULT_HAIKU_MODEL: MODEL, ANTHROPIC_SMALL_FAST_MODEL: MODEL,
      CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1", DISABLE_AUTOUPDATER: "1",
    } },
    { id: "codex-ocg", runtime: "codex", home: "homes/codex", env: { OPENCODE_GO_KEY: key, OPENCODE_SESSION: "ember-{route}" } },
  ],
}, dataDir);

class ConsoleChat implements ChatSurface {
  readonly botUserId = "UBOT";
  readonly posts: { thread: string; text: string }[] = [];
  async start(): Promise<void> {}
  async stop(): Promise<void> {}
  async post(thread: ThreadRef, text: string): Promise<void> {
    this.posts.push({ thread: thread.threadTs, text });
    console.log(`  [post ${thread.threadTs}] ${text.replaceAll("\n", " ⏎ ").slice(0, 200)}`);
  }
  async history(): Promise<ChatMessage[]> {
    return [];
  }
}

const store = new Store(join(dataDir, "ember.db"));
const chat = new ConsoleChat();
const drivers = { claude: new ClaudeDriver(store), codex: new CodexDriver(store) };
const server = createServer((req, res) => void mcp.handle(req, res));
await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
const mcpUrl = `http://127.0.0.1:${(server.address() as { port: number }).port}/mcp`;
const hub = new Hub({ config, store, chats: new Map([["claude", chat], ["codex", chat]]), drivers, mcpUrl });
const mcp = new McpEndpoint((token) => store.sessionByToken(token)?.key, hub.tools());

/** Waits until the session has been idle (no running turn, nothing pending) for a few seconds. */
async function quiet(bot: string, threadTs: string, timeoutMs = 300_000): Promise<void> {
  const k = sessionKey(bot, "C1", threadTs);
  const deadline = Date.now() + timeoutMs;
  let calm = 0;
  while (Date.now() < deadline) {
    await new Promise((r) => setTimeout(r, 1000));
    const idle = store.getSession(k)?.running === false && store.pendingInbound(k).length === 0;
    calm = idle ? calm + 1 : 0;
    if (calm >= 4) return;
  }
  throw new Error(`session ${k} did not settle`);
}

let counter = 1;
/** Slack-style message timestamps, increasing. */
const nextTs = () => `${Math.floor(Date.now() / 1000)}.${String(counter++).padStart(6, "0")}`;
const say = (bot: string, threadTs: string, text: string, addressed: boolean) =>
  hub.accept(bot, { channel: "C1", threadTs, ts: nextTs(), user: "U1", text, addressed });

const results: Record<string, unknown>[] = [];
for (const runtime of runtimes) {
  console.log(`\n=== ${runtime}`);
  const threadTs = nextTs();
  await hub.accept(runtime, { channel: "C1", threadTs, ts: threadTs, user: "U1", addressed: true,
    text: "<@UBOT> What is 17 * 23? Compute it with a shell command and answer in the thread." });
  await quiet(runtime, threadTs);
  const afterFirst = chat.posts.filter((p) => p.thread === threadTs).length;

  await say(runtime, threadTs, "What number did you just post? Reply with only the number.", false);
  await quiet(runtime, threadTs);

  // Make the session cold: claude's process is evicted; codex's shared app-server is restarted.
  if (runtime === "claude") hub.evictIdle(Date.now() + 3_600_000);
  else await drivers.codex.shutdown();
  await new Promise((r) => setTimeout(r, 3000));
  await say(runtime, threadTs, "Say that number once more, only the number.", false);
  await quiet(runtime, threadTs);

  const posts = chat.posts.filter((p) => p.thread === threadTs).map((p) => p.text);
  const turns = store.listTurns(sessionKey(runtime, "C1", threadTs));
  results.push({
    runtime,
    firstAnswered: afterFirst > 0 && /391/.test(posts.slice(0, afterFirst).join(" ")),
    followUp391: /391/.test(posts.slice(afterFirst).join(" ")),
    afterCold391: /391/.test(posts.at(-1) ?? ""),
    turns: turns.map((t) => `${t.kind}:${t.outcome}${t.declared ? `/${t.declared}` : ""}`).join(" "),
    failures: turns.filter((t) => t.detail).map((t) => t.detail).join(" | ") || "none",
  });
}

await hub.shutdown();
server.close();
const leftover = store.listProcesses();
store.close();
console.log("\n## e2e results");
console.table(results);
console.log(`process groups still recorded after shutdown: ${leftover.length}`, leftover);
console.log(`data dir: ${dataDir}`);
process.exit(0);
