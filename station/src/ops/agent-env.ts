// The variables a station's owners set for everything it starts for its agents (config.json `agentEnv`, docs/agent-env.md):
// an HTTP proxy the machine's network needs, mostly. They go to the runtimes (Claude Code, Codex, dsh), the logins
// (profiles' and the machine's command-line tools'), the CLI checks and the agents' background jobs, over the
// station's own environment and under a profile's variables. With a proxy among them the station's requests on a
// profile's behalf (a Claude login renewed, an allowance asked) go through it too; its own (still.fail cloud, Slack, the
// relays) never do, so a wrong proxy does not shut its pages out of the place it is fixed from.
import https from "node:https";
import { Readable } from "node:stream";

/// What a variable may be called (as a shell takes it).
export const ENV_NAME = /^[A-Za-z_][A-Za-z0-9_]*$/;
/// At most this many variables.
export const MOST_VARS = 64;
/// A value at most this long.
export const MOST_VALUE = 4096;

const PROXIES = ["HTTPS_PROXY", "HTTP_PROXY", "ALL_PROXY"];
/// What never goes through a proxy: this machine (the agents reach the station's tools here).
const LOCAL = ["localhost", "127.0.0.1", "::1"];

const isObject = (v: unknown): v is Record<string, unknown> => v !== null && typeof v === "object" && !Array.isArray(v);

let source: () => unknown = () => null;

/// Where config.json is read from (once, at start; tests set their own).
export function readAgentEnvFrom(config: () => unknown) {
  source = config;
}

/// The variables config.json sets (`agentEnv`), those of a name a shell takes.
export function agentEnv(raw: unknown = source()): Record<string, string> {
  const set = isObject(raw) ? raw.agentEnv : undefined;
  if (!isObject(set)) return {};
  return Object.fromEntries(Object.entries(set).filter((e): e is [string, string] => ENV_NAME.test(e[0]) && typeof e[1] === "string"));
}

/// Throws what is wrong with config.json's `agentEnv` (accounts/check.ts).
export function checkAgentEnv(set: unknown) {
  if (set === undefined || set === null) return;
  if (!isObject(set)) throw new Error("agentEnv: a map of variables to their values");
  const entries = Object.entries(set);
  if (entries.length > MOST_VARS) throw new Error(`agentEnv: at most ${MOST_VARS} variables`);
  for (const [key, value] of entries) {
    if (!ENV_NAME.test(key)) throw new Error(`agentEnv: invalid environment variable name ${key}`);
    if (typeof value !== "string") throw new Error(`agentEnv.${key}: a string`);
    if (value.length > MOST_VALUE || /[\0\n\r]/.test(value)) throw new Error(`agentEnv.${key}: one line of at most ${MOST_VALUE} characters`);
  }
}

/// What is wrong with a line of the variables as written: its number (from 1), and which refusal.
export type EnvLineError = { line: number; why: "notPair" | "badName" | "tooLong" | "tooMany"; name?: string };

/// The variables as people write them (as a .env file): `NAME=value` a line, blank lines and `#` comments left out, an
/// `export ` before it and quotes round the value taken off, the last of a name kept. A value as the pages show a
/// secret of `shown` (masked) stands for the one kept: it is what was read, left as it was.
export function parseEnvText(text: string, kept: Record<string, string> = {}): Record<string, string> | EnvLineError {
  const env: Record<string, string> = {};
  const lines = text.split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    let line = lines[i]!.trim();
    if (line === "" || line.startsWith("#")) continue;
    if (/^export\s/.test(line)) line = line.slice(6).trimStart();
    const at = line.indexOf("=");
    if (at <= 0) return { line: i + 1, why: "notPair" };
    const name = line.slice(0, at).trim();
    if (!ENV_NAME.test(name)) return { line: i + 1, why: "badName", name };
    let value = line.slice(at + 1).trim();
    if (value.length >= 2 && (value[0] === '"' || value[0] === "'") && value.at(-1) === value[0]) value = value.slice(1, -1);
    if (value.length > MOST_VALUE) return { line: i + 1, why: "tooLong", name };
    const before = kept[name];
    env[name] = before !== undefined && secretValue(name, before) && value === maskValue(before) ? before : value;
  }
  if (Object.keys(env).length > MOST_VARS) return { line: 0, why: "tooMany" };
  return env;
}

/// A secret as the pages show it: its first five and last four characters.
export function maskValue(value: string): string {
  if (value === "") return "";
  const chars = [...value];
  if (chars.length <= 8) return "••••";
  return `${chars.slice(0, 5).join("")}…${chars.slice(-4).join("")}`;
}

/// A variable, whatever the case it is written in (proxies are read as `HTTPS_PROXY` and `https_proxy`).
const either = (env: Record<string, string | undefined>, name: string): string | undefined => env[name] || env[name.toLowerCase()] || undefined;

/// `env` going through a proxy (in any of the usual variables): this machine left out of it, in both cases of NO_PROXY,
/// added to what they name.
export function keepLocal(env: Record<string, string>): Record<string, string> {
  if (!PROXIES.some((p) => either(env, p) !== undefined)) return env;
  const named = (either(env, "NO_PROXY") ?? "").split(",").map((h) => h.trim()).filter(Boolean);
  if (named.includes("*")) return env;
  const kept = [...named, ...LOCAL.filter((h) => !named.includes(h))].join(",");
  return { ...env, NO_PROXY: kept, no_proxy: kept };
}

/// The environment for what the station starts for its agents: its own, these variables over it, less `scrubbed`; this
/// machine kept out of a proxy.
export function startEnv(scrubbed: string[] = []): Record<string, string> {
  const env = { ...process.env, ...agentEnv() };
  return keepLocal(Object.fromEntries(Object.entries(env).filter((e): e is [string, string] => e[1] !== undefined && !scrubbed.includes(e[0]))));
}

/// Whether a value says more than it should be shown (a key, a token, a proxy's password): masked on the pages.
export const secretValue = (key: string, value: string) =>
  ["KEY", "TOKEN", "SECRET", "PASSWORD", "AUTH"].some((w) => key.toUpperCase().includes(w)) || /^[a-z][a-z0-9+.-]*:\/\/[^/@]*:[^/@]*@/i.test(value);

// ── the station's requests on a profile's behalf ─────────────────────────────────────────────────────────────────────

const agents = new Map<string, https.Agent>();

/// The agent for requests through the proxy `agentEnv` names (Node's own proxying, NO_PROXY honoured); none without one.
function proxyAgent(env: Record<string, string>): https.Agent | null {
  const proxyEnv: Record<string, string> = {};
  for (const name of [...PROXIES, "NO_PROXY"]) {
    const v = either(env, name);
    if (v !== undefined) proxyEnv[name] = v;
  }
  if (proxyEnv.HTTPS_PROXY === undefined && proxyEnv.ALL_PROXY !== undefined) proxyEnv.HTTPS_PROXY = proxyEnv.ALL_PROXY;
  if (proxyEnv.HTTPS_PROXY === undefined) return null;
  const key = JSON.stringify(proxyEnv);
  let agent = agents.get(key);
  if (agent === undefined) {
    for (const a of agents.values()) a.destroy();
    agents.clear();
    agent = new https.Agent({ keepAlive: true, proxyEnv } as https.AgentOptions);
    agents.set(key, agent);
  }
  return agent;
}

/// Statuses whose answer has no body.
const BODILESS = [101, 204, 205, 304];

/// `fetch` for a request the station makes on a profile's behalf to its model's service: through the proxy `agentEnv`
/// names when it names one, else as `fetch` does. Takes what those requests use (a method, headers, a string body, a
/// signal; redirects are not followed either way).
export async function profileFetch(url: string, init: { method?: string; headers?: Record<string, string>; body?: string; signal?: AbortSignal; redirect?: "manual" } = {}): Promise<Response> {
  const agent = url.startsWith("https:") ? proxyAgent(keepLocal(agentEnv())) : null;
  if (agent === null) return fetch(url, init);
  return new Promise<Response>((resolve, reject) => {
    // Its length said, as fetch does (not chunked).
    const headers = init.body === undefined ? init.headers : { "content-length": String(Buffer.byteLength(init.body)), ...init.headers };
    const req = https.request(url, { method: init.method ?? "GET", headers, agent, signal: init.signal }, (res) => {
      const answered = new Headers();
      for (const [k, v] of Object.entries(res.headers)) {
        if (Array.isArray(v)) for (const one of v) answered.append(k, one);
        else if (v !== undefined) answered.set(k, v);
      }
      const status = res.statusCode ?? 502;
      const body = BODILESS.includes(status) || init.method === "HEAD" ? (res.resume(), null) : (Readable.toWeb(res) as ReadableStream<Uint8Array>);
      resolve(new Response(body, { status, statusText: res.statusMessage ?? "", headers: answered }));
    });
    req.on("error", reject);
    req.end(init.body);
  });
}
