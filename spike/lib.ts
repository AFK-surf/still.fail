// Shared helpers for spikes: isolated runtime homes on OpenCode Go, and
// process-tree memory sampling. Never touches the user's ~/.claude or ~/.codex.
import { execFileSync, spawn, type ChildProcess } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { homedir } from "node:os";
import { join } from "node:path";
import { createInterface } from "node:readline";

export const SPIKE_ROOT = join(homedir(), ".config", "ember-spike");
export const MODEL = process.env.EMBER_SPIKE_MODEL ?? "deepseek-flash";
const OPENCODE_BASE = "https://opencode.ai/zen/go";

function opencodeKey(): string {
  const text = readFileSync(join(SPIKE_ROOT, "opencode-go.env"), "utf8");
  const key = /^OPENCODE_GO_KEY=(.+)$/m.exec(text)?.[1]?.trim();
  if (!key) throw new Error("OPENCODE_GO_KEY missing from ~/.config/ember-spike/opencode-go.env");
  return key;
}

/** Env for `claude` against OpenCode Go in an isolated config home. No login, no helper. */
export function claudeEnv(routingId: string): NodeJS.ProcessEnv {
  const home = join(SPIKE_ROOT, "claude-home");
  mkdirSync(home, { recursive: true });
  const env: NodeJS.ProcessEnv = { ...process.env };
  for (const name of ["ANTHROPIC_AUTH_TOKEN", "CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT"]) delete env[name];
  return {
    ...env,
    CLAUDE_CONFIG_DIR: home,
    ANTHROPIC_BASE_URL: OPENCODE_BASE,
    // OpenCode Go's /messages wants x-api-key; ANTHROPIC_AUTH_TOKEN (Bearer) gets 401.
    ANTHROPIC_API_KEY: opencodeKey(),
    ANTHROPIC_CUSTOM_HEADERS: `x-opencode-session: ${routingId}`,
    ANTHROPIC_MODEL: MODEL,
    ANTHROPIC_DEFAULT_OPUS_MODEL: MODEL,
    ANTHROPIC_DEFAULT_SONNET_MODEL: MODEL,
    ANTHROPIC_DEFAULT_HAIKU_MODEL: MODEL,
    ANTHROPIC_SMALL_FAST_MODEL: MODEL,
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1",
    DISABLE_AUTOUPDATER: "1",
  };
}

/** Env for `codex` against OpenCode Go in an isolated CODEX_HOME. */
export function codexEnv(routingId: string): NodeJS.ProcessEnv {
  const home = join(SPIKE_ROOT, "codex-home");
  mkdirSync(home, { recursive: true });
  writeFileSync(join(home, "config.toml"), [
    `model = "${MODEL}"`,
    `model_provider = "opencode-go"`,
    ``,
    `[model_providers.opencode-go]`,
    `name = "OpenCode Go"`,
    `base_url = "${OPENCODE_BASE}/v1"`,
    `env_key = "OPENCODE_GO_KEY"`,
    `wire_api = "responses"`,
    `env_http_headers = { "x-opencode-session" = "OPENCODE_SESSION" }`,
    ``,
  ].join("\n"));
  const env: NodeJS.ProcessEnv = { ...process.env };
  delete env.OPENAI_API_KEY;
  return { ...env, CODEX_HOME: home, OPENCODE_GO_KEY: opencodeKey(), OPENCODE_SESSION: routingId };
}

export interface TreeSample {
  pids: number[];
  rssMb: number;
  /** macOS phys_footprint of each process in the tree, when `footprint` can read it. */
  footprintMb: number | null;
}

/** Memory of `root` and all its descendants. */
export function sampleTree(root: number): TreeSample {
  const rows = execFileSync("ps", ["-axo", "pid=,ppid=,rss="], { encoding: "utf8" })
    .trim().split("\n").map((line) => line.trim().split(/\s+/).map(Number) as [number, number, number]);
  const children = new Map<number, number[]>();
  for (const [pid, ppid] of rows) children.set(ppid, [...(children.get(ppid) ?? []), pid]);
  const pids: number[] = [];
  const stack = [root];
  while (stack.length > 0) {
    const pid = stack.pop()!;
    if (!rows.some(([p]) => p === pid)) continue;
    pids.push(pid);
    stack.push(...(children.get(pid) ?? []));
  }
  const rssKb = rows.filter(([pid]) => pids.includes(pid)).reduce((sum, [, , rss]) => sum + rss, 0);
  return { pids, rssMb: Math.round(rssKb / 1024), footprintMb: footprint(pids) };
}

function footprint(pids: number[]): number | null {
  if (pids.length === 0) return 0;
  try {
    const out = execFileSync("footprint", pids.map(String), { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
    // "Footprint: 256 MB" lines per process, plus a summary; sum the per-process ones.
    let total = 0;
    for (const match of out.matchAll(/\[\s*\d+\]:.*?Footprint:\s*([\d.]+)\s*(KB|MB|GB)/g)) {
      const value = Number(match[1]);
      total += match[2] === "GB" ? value * 1024 : match[2] === "KB" ? value / 1024 : value;
    }
    return total > 0 ? Math.round(total) : null;
  } catch {
    return null;
  }
}

/** Samples `root`'s tree every `everyMs` until stopped; reports the peak. */
export function peakSampler(root: number, everyMs = 500): { stop(): TreeSample } {
  let peak: TreeSample = { pids: [], rssMb: 0, footprintMb: null };
  const timer = setInterval(() => {
    const sample = sampleTree(root);
    if (sample.rssMb > peak.rssMb) peak = sample;
  }, everyMs);
  return {
    stop() {
      clearInterval(timer);
      const last = sampleTree(root);
      return last.rssMb > peak.rssMb ? last : peak;
    },
  };
}

export const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

/** Spawns a line-oriented child in its own process group so the whole tree can be killed. */
export function spawnLines(command: string, args: string[], options: { cwd: string; env: NodeJS.ProcessEnv }):
  { child: ChildProcess; lines: AsyncIterable<string>; send(obj: unknown): void; killTree(): void } {
  const child = spawn(command, args, { ...options, stdio: ["pipe", "pipe", "pipe"], detached: true });
  child.stderr!.on("data", (chunk) => process.stderr.write(`[${command} stderr] ${chunk}`));
  const lines = createInterface({ input: child.stdout! });
  return {
    child,
    lines,
    send(obj) { child.stdin!.write(JSON.stringify(obj) + "\n"); },
    killTree() { try { process.kill(-child.pid!, "SIGTERM"); } catch { /* already gone */ } },
  };
}

/**
 * A minimal streamable-HTTP MCP server with one `whoami` tool. It maps the
 * caller's bearer token to a session name, so a spike can tell who called.
 */
export async function startWhoamiServer(sessions: ReadonlyMap<string, string>):
  Promise<{ url: string; seen: Record<string, unknown>[]; close(): void }> {
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
  return { url, seen, close: () => server.close() };
}

export interface AppServer {
  pid: number;
  request(method: string, params: unknown): Promise<any>;
  /** Starts a turn and resolves with the items it completed, once `turn/completed` arrives. */
  runTurn(threadId: string, text: string, timeoutMs?: number): Promise<any[]>;
  killTree(): void;
}

/** One `codex app-server` over stdio, initialized. Server->client requests are refused. */
export async function startAppServer(cwd: string, env: NodeJS.ProcessEnv): Promise<AppServer> {
  const proc = spawnLines("codex", ["app-server", "--listen", "stdio://"], { cwd, env });
  let nextId = 1;
  const pending = new Map<number, { resolve(v: any): void; reject(e: Error): void }>();
  const turns = new Map<string, { items: any[]; done(): void }>();
  (async () => {
    for await (const line of proc.lines) {
      const msg = JSON.parse(line) as Record<string, any>;
      if (typeof msg.id === "number" && ("result" in msg || "error" in msg) && pending.has(msg.id)) {
        const waiter = pending.get(msg.id)!;
        pending.delete(msg.id);
        if (msg.error) waiter.reject(new Error(JSON.stringify(msg.error)));
        else waiter.resolve(msg.result);
      } else if (msg.id !== undefined && msg.method) {
        proc.send({ id: msg.id, error: { code: -32601, message: "not supported in spike" } });
      } else if (msg.method === "item/completed") {
        turns.get(msg.params?.threadId)?.items.push(msg.params?.item);
      } else if (msg.method === "turn/completed") {
        turns.get(msg.params?.threadId)?.done();
      }
    }
  })();
  const request = (method: string, params: unknown): Promise<any> => {
    const id = nextId++;
    proc.send({ id, method, params });
    return new Promise((resolve, reject) => pending.set(id, { resolve, reject }));
  };
  await request("initialize", { clientInfo: { name: "ember-spike", version: "0" }, capabilities: { experimentalApi: true } });
  proc.send({ method: "initialized", params: {} });
  return {
    pid: proc.child.pid!,
    request,
    async runTurn(threadId, text, timeoutMs = 180_000) {
      const items: any[] = [];
      const done = new Promise<void>((resolve) => turns.set(threadId, { items, done: resolve }));
      await request("turn/start", { threadId, input: [{ type: "text", text }] });
      let timer: NodeJS.Timeout | undefined;
      const timeout = new Promise<never>((_, reject) => {
        timer = setTimeout(() => reject(new Error(`turn on ${threadId} timed out`)), timeoutMs);
      });
      try {
        await Promise.race([done, timeout]);
      } finally {
        clearTimeout(timer);
        turns.delete(threadId);
      }
      return items;
    },
    killTree: proc.killTree,
  };
}

/** Runs a command with stdin closed (both CLIs otherwise wait on it). Rejects on non-zero exit. */
export function run(command: string, args: string[], options: { cwd: string; env: NodeJS.ProcessEnv; timeout: number }):
  Promise<{ stdout: string; stderr: string }> {
  return new Promise((resolve, reject) => {
    const started = Date.now();
    const child = spawn(command, args, { cwd: options.cwd, env: options.env, stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "";
    let stderr = "";
    child.stdout!.on("data", (chunk) => { stdout += chunk; });
    child.stderr!.on("data", (chunk) => { stderr += chunk; });
    const timer = setTimeout(() => child.kill("SIGTERM"), options.timeout);
    child.on("close", (code, signal) => {
      clearTimeout(timer);
      const elapsed = `${Math.round((Date.now() - started) / 1000)}s`;
      if (code === 0) resolve({ stdout, stderr });
      else reject(Object.assign(new Error(`exit ${code ?? signal} after ${elapsed}`), { stderr: `exit ${code ?? signal} after ${elapsed}: ${stderr}` }));
    });
  });
}

export function report(title: string, rows: Record<string, unknown>[]): void {
  console.log(`\n## ${title}`);
  console.table(rows);
}
