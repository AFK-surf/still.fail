// Configuration comes from one JSON file: $EMBER_CONFIG, else <dataDir>/config.json
// with dataDir from $EMBER_DATA (default ~/.ember). Slack tokens may come from
// SLACK_APP_TOKEN / SLACK_BOT_TOKEN instead of the file.
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { isAbsolute, join, resolve } from "node:path";

export type RuntimeKind = "claude" | "codex";
export const RUNTIMES: readonly RuntimeKind[] = ["claude", "codex"];

export interface Profile {
  id: string;
  runtime: RuntimeKind;
  /** The runtime's config home: CLAUDE_CONFIG_DIR or CODEX_HOME. */
  home: string;
  /**
   * Extra environment for this profile's processes. In values, `{route}` is
   * replaced with a per-session routing id (claude) or the profile id (codex,
   * whose app-server is shared), e.g. for provider session-affinity headers.
   */
  env: Record<string, string>;
  model?: string;
}

export interface Config {
  dataDir: string;
  http: { host: string; port: number };
  slack: { appToken: string; botToken: string };
  defaults: { runtime: RuntimeKind; model?: string };
  /** Per-channel overrides of the default runtime and model. */
  channels: Record<string, { runtime?: RuntimeKind; model?: string }>;
  profiles: Profile[];
  /** How many times a turn that ended without final/block is nudged before giving up. */
  maxNudges: number;
  /** Idle claude processes kept alive at most this long before they may be evicted. */
  warmMs: number;
  /** Idle claude processes beyond this count are evicted, oldest first, once past warmMs. */
  maxWarmClaude: number;
}

interface RawConfig {
  http?: { host?: string; port?: number };
  slack?: { appToken?: string; botToken?: string };
  defaults?: { runtime?: RuntimeKind; model?: string };
  channels?: Record<string, { runtime?: RuntimeKind; model?: string }>;
  profiles?: { id: string; runtime: RuntimeKind; home: string; env?: Record<string, string>; model?: string }[];
  maxNudges?: number;
  warmMinutes?: number;
  maxWarmClaude?: number;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const dataDir = resolve(env.EMBER_DATA ?? join(homedir(), ".ember"));
  const path = env.EMBER_CONFIG ?? join(dataDir, "config.json");
  const raw: RawConfig = existsSync(path) ? JSON.parse(readFileSync(path, "utf8")) as RawConfig : {};
  return parseConfig(raw, dataDir, env);
}

export function parseConfig(raw: RawConfig, dataDir: string, env: NodeJS.ProcessEnv = {}): Config {
  const appToken = raw.slack?.appToken ?? env.SLACK_APP_TOKEN ?? "";
  const botToken = raw.slack?.botToken ?? env.SLACK_BOT_TOKEN ?? "";
  const profiles = (raw.profiles ?? []).map((p): Profile => {
    if (!RUNTIMES.includes(p.runtime)) throw new Error(`profile ${p.id}: unknown runtime ${String(p.runtime)}`);
    const home = isAbsolute(p.home) ? p.home : join(dataDir, p.home);
    return { id: p.id, runtime: p.runtime, home, env: p.env ?? {}, ...(p.model ? { model: p.model } : {}) };
  });
  const ids = new Set<string>();
  for (const p of profiles) {
    if (ids.has(p.id)) throw new Error(`duplicate profile id ${p.id}`);
    ids.add(p.id);
  }
  const runtime = raw.defaults?.runtime ?? profiles[0]?.runtime ?? "claude";
  return {
    dataDir,
    http: { host: raw.http?.host ?? "127.0.0.1", port: raw.http?.port ?? 4750 },
    slack: { appToken, botToken },
    defaults: { runtime, ...(raw.defaults?.model ? { model: raw.defaults.model } : {}) },
    channels: raw.channels ?? {},
    profiles,
    maxNudges: raw.maxNudges ?? 2,
    warmMs: (raw.warmMinutes ?? 30) * 60_000,
    maxWarmClaude: raw.maxWarmClaude ?? 4,
  };
}

/** The profile for a new session of `runtime`. Account pooling comes later; for now the first match. */
export function profileFor(config: Config, runtime: RuntimeKind): Profile | undefined {
  return config.profiles.find((p) => p.runtime === runtime);
}

export function expandRoute(env: Record<string, string>, route: string): Record<string, string> {
  return Object.fromEntries(Object.entries(env).map(([k, v]) => [k, v.replaceAll("{route}", route)]));
}
