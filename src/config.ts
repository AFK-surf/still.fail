// Configuration comes from one JSON file: $EMBER_CONFIG, else <dataDir>/config.json
// with dataDir from $EMBER_DATA (default ~/.ember).
//
// A bot is one Slack app bound to one runtime and model: "@claude" runs Claude
// Code on a Claude subscription, "@ds" runs deepseek through OpenCode Go, and
// so on. Profiles are the runtime accounts bots draw from; bots may share them.
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

export interface Bot {
  /** Stable id; part of session keys, so do not rename a bot that has sessions. */
  id: string;
  /** How the bot refers to itself in its instructions. */
  name: string;
  slack: { appToken: string; botToken: string };
  runtime: RuntimeKind;
  /** Accounts this bot may run on, in order of preference; all of `runtime`. */
  profiles: string[];
  model?: string;
}

export interface Config {
  dataDir: string;
  /** Shared MEMORY.md and skills/ linked into every profile home. */
  agentHome: string;
  http: { host: string; port: number };
  bots: Bot[];
  profiles: Profile[];
  /** How many times a turn that ended without final/block is nudged before giving up. */
  maxNudges: number;
  /** Idle claude processes kept alive at most this long before they may be evicted. */
  warmMs: number;
  /** Idle claude processes beyond this count are evicted, oldest first, once past warmMs. */
  maxWarmClaude: number;
}

interface RawConfig {
  agentHome?: string;
  http?: { host?: string; port?: number };
  bots?: { id: string; name?: string; slack?: { appToken?: string; botToken?: string }; runtime: RuntimeKind; profiles?: string[]; profile?: string; model?: string }[];
  profiles?: { id: string; runtime: RuntimeKind; home: string; env?: Record<string, string>; model?: string }[];
  maxNudges?: number;
  warmMinutes?: number;
  maxWarmClaude?: number;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const dataDir = resolve(env.EMBER_DATA ?? join(homedir(), ".ember"));
  const path = env.EMBER_CONFIG ?? join(dataDir, "config.json");
  const raw: RawConfig = existsSync(path) ? JSON.parse(readFileSync(path, "utf8")) as RawConfig : {};
  return parseConfig(raw, dataDir);
}

export function parseConfig(raw: RawConfig, dataDir: string): Config {
  const profiles = (raw.profiles ?? []).map((p): Profile => {
    if (!RUNTIMES.includes(p.runtime)) throw new Error(`profile ${p.id}: unknown runtime ${String(p.runtime)}`);
    const home = isAbsolute(p.home) ? p.home : join(dataDir, p.home);
    return { id: p.id, runtime: p.runtime, home, env: p.env ?? {}, ...(p.model ? { model: p.model } : {}) };
  });
  unique("profile", profiles.map((p) => p.id));

  const bots = (raw.bots ?? []).map((b): Bot => {
    if (!/^[a-z0-9][a-z0-9-]*$/.test(b.id)) throw new Error(`bot id ${JSON.stringify(b.id)}: use lowercase letters, digits and dashes`);
    if (!RUNTIMES.includes(b.runtime)) throw new Error(`bot ${b.id}: unknown runtime ${String(b.runtime)}`);
    const ids = b.profiles ?? (b.profile ? [b.profile] : []);
    if (ids.length === 0) throw new Error(`bot ${b.id}: no profiles`);
    for (const id of ids) {
      const profile = profiles.find((p) => p.id === id);
      if (!profile) throw new Error(`bot ${b.id}: unknown profile ${id}`);
      if (profile.runtime !== b.runtime) throw new Error(`bot ${b.id}: profile ${id} is ${profile.runtime}, the bot runs ${b.runtime}`);
    }
    return {
      id: b.id,
      name: b.name ?? b.id,
      slack: { appToken: b.slack?.appToken ?? "", botToken: b.slack?.botToken ?? "" },
      runtime: b.runtime,
      profiles: ids,
      ...(b.model ? { model: b.model } : {}),
    };
  });
  unique("bot", bots.map((b) => b.id));

  const agentHome = raw.agentHome ?? "agent";
  return {
    dataDir,
    agentHome: isAbsolute(agentHome) ? agentHome : join(dataDir, agentHome),
    http: { host: raw.http?.host ?? "127.0.0.1", port: raw.http?.port ?? 4750 },
    bots,
    profiles,
    maxNudges: raw.maxNudges ?? 2,
    warmMs: (raw.warmMinutes ?? 30) * 60_000,
    maxWarmClaude: raw.maxWarmClaude ?? 4,
  };
}

function unique(kind: string, ids: string[]): void {
  const seen = new Set<string>();
  for (const id of ids) {
    if (seen.has(id)) throw new Error(`duplicate ${kind} id ${id}`);
    seen.add(id);
  }
}

/** The profile a new session of `bot` runs on. Account pooling comes later; for now the first. */
export function profileFor(config: Config, bot: Bot): Profile {
  const profile = config.profiles.find((p) => p.id === bot.profiles[0]);
  if (!profile) throw new Error(`bot ${bot.id}: profile ${bot.profiles[0]} is not configured`);
  return profile;
}

export function expandRoute(env: Record<string, string>, route: string): Record<string, string> {
  return Object.fromEntries(Object.entries(env).map(([k, v]) => [k, v.replaceAll("{route}", route)]));
}
