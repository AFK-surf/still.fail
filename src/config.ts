// Configuration comes from one JSON file: $EMBER_CONFIG, else <dataDir>/config.json
// with dataDir from $EMBER_DATA (default ~/.ember).
//
// A bot is one Slack app bound to one runtime and model: "@claude" runs Claude
// Code on a Claude subscription, "@ds" runs deepseek through OpenCode Go, and
// so on. Profiles are the runtime accounts bots draw from; bots may share them.
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { isAbsolute, join, resolve } from "node:path";
import { ACCESS_KINDS, accessEnv, KEYED, type AccessKind } from "./profiles.ts";

export type RuntimeKind = "claude" | "codex";
export const RUNTIMES: readonly RuntimeKind[] = ["claude", "codex"];

export interface Profile {
  id: string;
  /** Shown instead of the id. */
  name: string;
  runtime: RuntimeKind;
  /** How the runtime reaches its models; `key` is set for keyed kinds. */
  access: { kind: AccessKind; key: string };
  /** The runtime's config home: CLAUDE_CONFIG_DIR or CODEX_HOME. */
  home: string;
  /**
   * The environment for this profile's processes: what the access kind needs
   * plus `customEnv`. In values, `{route}` is replaced with a per-session
   * routing id (claude) or the profile id (codex, whose app-server is shared).
   */
  env: Record<string, string>;
  /** Variables set by hand; they win over derived ones. */
  customEnv: Record<string, string>;
  model?: string;
}

export interface Bot {
  /** Stable id; part of session keys, so do not rename a bot that has sessions. */
  id: string;
  /** A disabled bot keeps its config and sessions but is not connected. */
  enabled: boolean;
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
  /** Where the admin page listens: its own port, so a public tunnel never reaches the agents' MCP endpoint. */
  adminHttp: { host: string; port: number };
  /** Cloudflare Access application guarding the public admin page; null refuses tunneled requests. */
  adminAccess: { teamDomain: string; aud: string } | null;
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

export interface RawBot {
  id: string;
  name?: string;
  enabled?: boolean;
  slack?: { appToken?: string; botToken?: string };
  runtime: RuntimeKind;
  profiles?: string[];
  profile?: string;
  model?: string;
}

export interface RawProfile {
  id: string;
  name?: string;
  runtime: RuntimeKind;
  access?: { kind: AccessKind; key?: string };
  home: string;
  env?: Record<string, string>;
  model?: string;
}

/** config.json as written; parseConfig turns it into a validated Config. */
export interface RawConfig {
  agentHome?: string;
  admin?: { host?: string; port?: number; access?: { teamDomain?: string; aud?: string } };
  http?: { host?: string; port?: number };
  bots?: RawBot[];
  profiles?: RawProfile[];
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
    if (typeof p.id !== "string" || !/^[a-z0-9][a-z0-9-]*$/.test(p.id)) throw new Error(`profile id ${JSON.stringify(p.id)}: use lowercase letters, digits and dashes`);
    if (typeof p.home !== "string" || !p.home) throw new Error(`profile ${p.id}: home is required`);
    if (!RUNTIMES.includes(p.runtime)) throw new Error(`profile ${p.id}: unknown runtime ${String(p.runtime)}`);
    const home = isAbsolute(p.home) ? p.home : join(dataDir, p.home);
    const kind = p.access?.kind ?? "env";
    if (!ACCESS_KINDS[p.runtime].includes(kind)) throw new Error(`profile ${p.id}: ${p.runtime} cannot use access ${String(kind)}`);
    const key = p.access?.key?.trim() ?? "";
    if (KEYED.has(kind) && !key) throw new Error(`profile ${p.id}: access ${kind} needs a key`);
    const customEnv = p.env ?? {};
    return {
      id: p.id, name: p.name?.trim() || p.id, runtime: p.runtime, access: { kind, key }, home,
      env: { ...accessEnv(p.runtime, kind, key, p.model), ...customEnv }, customEnv,
      ...(p.model ? { model: p.model } : {}),
    };
  });
  unique("profile", profiles.map((p) => p.id));

  const bots = (raw.bots ?? []).map((b): Bot => {
    if (typeof b.id !== "string" || !/^[a-z0-9][a-z0-9-]*$/.test(b.id)) throw new Error(`bot id ${JSON.stringify(b.id)}: use lowercase letters, digits and dashes`);
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
      enabled: b.enabled ?? true,
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
    adminHttp: { host: raw.admin?.host ?? "127.0.0.1", port: raw.admin?.port ?? 4760 },
    adminAccess: raw.admin?.access?.teamDomain && raw.admin.access.aud
      ? { teamDomain: raw.admin.access.teamDomain, aud: raw.admin.access.aud }
      : null,
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
