// Shared helpers for spikes: isolated runtime homes on OpenCode Go, and
// process-tree memory sampling. Never touches the user's ~/.claude or ~/.codex.
import { execFileSync, spawn, type ChildProcess } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
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
