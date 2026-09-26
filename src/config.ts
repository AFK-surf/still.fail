// Configuration comes from one JSON file: $EMBER_CONFIG, else <dataDir>/config.json
// with dataDir from $EMBER_DATA (default ~/.ember).
//
// A connect is one way in: today a Slack app, later WeChat.
// Each connect is bound to one model (runtime + account + model) and decides
// how conversations map to sessions. Profiles are the runtime accounts
// connects draw from; connects may share them.
import type { ConfigToken } from "./chat/slack-apps.ts";
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
  /** The runtime a subscription signs in with (or custom variables are for); for a keyed profile, its first runtime. */
  runtime: RuntimeKind;
  /** The runtimes it can run: the station sets each one up for the account (runtimesOf). */
  runtimes: RuntimeKind[];
  /** How the runtime reaches its models; `key` is set for keyed kinds. */
  access: { kind: AccessKind; key: string };
  /** The runtimes' config home: CLAUDE_CONFIG_DIR and CODEX_HOME (their files do not overlap). */
  home: string;
  /**
   * The environment for this profile's processes, by runtime: what the access kind needs there plus `customEnv`. In
   * values, `{route}` is replaced with a per-session routing id (claude) or the profile id (codex, whose app-server is
   * shared).
   */
  envs: Partial<Record<RuntimeKind, Record<string, string>>>;
  /** Variables set by hand; they win over derived ones. */
  customEnv: Record<string, string>;
  model?: string;
  /** Models this profile may be used for, chosen by hand from what its check found. None until someone picks. */
  models: string[];
}

export type ConnectKind = "slack";
export const CONNECT_KINDS: readonly ConnectKind[] = ["slack"];

/**
 * multi-session: each thread is its own session, started by an @mention.
 * single-session: one session takes every thread the connect sees; with
 * requireMention a new thread needs an @mention, replies in threads the
 * session is already part of do not.
 */
export type ConnectMode = "multi-session" | "single-session";
export const CONNECT_MODES: readonly ConnectMode[] = ["multi-session", "single-session"];

/** The model a connect runs: a runtime, the accounts it may use, and a model. */
/** Reasoning effort each runtime accepts. */
export const EFFORTS: Record<RuntimeKind, readonly string[]> = {
  claude: ["low", "medium", "high", "xhigh", "max"],
  codex: ["minimal", "low", "medium", "high", "xhigh"],
};

export interface Binding {
  runtime: RuntimeKind;
  /** How hard the model thinks; the runtime's default when absent. */
  effort?: string;
  /** Sessions run on the profiles of `runtime` that have this model enabled, picked per session (pool.ts). */
  model?: string;
}

export interface Connect {
  /** Stable id; part of session keys, so do not rename a connect that has sessions. */
  id: string;
  /** How the agent refers to itself. */
  name: string;
  /** A disabled connect keeps its config and sessions but is not connected. */
  enabled: boolean;
  kind: ConnectKind;
  mode: ConnectMode;
  /** single-session only: whether starting on a new thread needs an @mention. */
  requireMention: boolean;
  /** appId is known once ember created the app or looked it up. */
  slack: { appToken: string; botToken: string; appId?: string };
  /** Who added it from the admin page: an email, or "local"; absent for older or hand-written ones. */
  createdBy?: { id: string; name: string };
  bind: Binding;
}

export interface Config {
  dataDir: string;
  /** Where the admin page listens: its own port, so a public tunnel never reaches the agents' MCP endpoint. */
  adminHttp: { host: string; port: number };
  /** Cloudflare Access application guarding the public admin page; null refuses tunneled requests. */
  adminAccess: { teamDomain: string; aud: string } | null;
  /** Slack app configuration tokens, one per Slack workspace: ember makes and edits apps there with them. */
  slackConfigTokens: ConfigToken[];
  /** Shared MEMORY.md and skills/ linked into every profile home. */
  agentHome: string;
  http: { host: string; port: number };
  connects: Connect[];
  profiles: Profile[];
  /** How many times a turn that ended without final/block is nudged before giving up. */
  maxNudges: number;
  /** Idle claude processes kept alive at most this long before they may be evicted. */
  warmMs: number;
  /** Idle claude processes beyond this count are evicted, oldest first, once past warmMs. */
  maxWarmClaude: number;
  /** What this station sends ember (docs/telemetry.md), each only if its operator says so: errors to PostHog; traces (the spans of traced requests, through ember-mesh; read when it starts) to ember cloud. */
  telemetry: { errors: boolean; traces: boolean };
}

export interface RawConnect {
  id: string;
  name?: string;
  enabled?: boolean;
  kind?: ConnectKind;
  mode?: ConnectMode;
  requireMention?: boolean;
  slack?: { appToken?: string; botToken?: string; appId?: string };
  createdBy?: { id: string; name: string };
  bind: { runtime: RuntimeKind; model?: string; effort?: string };
}

export interface RawProfile {
  id: string;
  name?: string;
  /** Needed for a subscription (which one) and custom variables; keyed kinds run every runtime they can. */
  runtime?: RuntimeKind;
  access?: { kind: AccessKind; key?: string };
  home: string;
  env?: Record<string, string>;
  model?: string;
  models?: string[];
}

/** config.json as written; parseConfig turns it into a validated Config. */
export interface RawConfig {
  agentHome?: string;
  admin?: { host?: string; port?: number; access?: { teamDomain?: string; aud?: string } };
  http?: { host?: string; port?: number };
  connects?: RawConnect[];
  slackConfigTokens?: ConfigToken[];
  profiles?: RawProfile[];
  maxNudges?: number;
  warmMinutes?: number;
  maxWarmClaude?: number;
  telemetry?: { errors?: boolean; traces?: boolean };
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
    const home = isAbsolute(p.home) ? p.home : join(dataDir, p.home);
    const kind = p.access?.kind ?? "env";
    const runtimes = runtimesOf(kind, p.runtime);
    if (runtimes.length === 0) throw new Error(`profile ${p.id}: ${String(kind)} needs a runtime (${RUNTIMES.join(" or ")})`);
    if (!runtimes.every((r) => ACCESS_KINDS[r].includes(kind))) throw new Error(`profile ${p.id}: ${runtimes.join("/")} cannot use access ${String(kind)}`);
    const key = p.access?.key?.trim() ?? "";
    if (KEYED.has(kind) && !key) throw new Error(`profile ${p.id}: access ${kind} needs a key`);
    const customEnv = p.env ?? {};
    return {
      id: p.id, name: p.name?.trim() || p.id, runtime: runtimes[0]!, runtimes, access: { kind, key }, home,
      envs: Object.fromEntries(runtimes.map((r) => [r, { ...accessEnv(r, kind, key, p.model), ...customEnv }])), customEnv,
      ...(p.model ? { model: p.model } : {}),
      models: [...new Set((p.models ?? []).filter((m) => typeof m === "string" && m.trim()).map((m) => m.trim()))],
    };
  });
  unique("profile", profiles.map((p) => p.id));

  const connects = (raw.connects ?? []).map((c): Connect => {
    if (typeof c.id !== "string" || !/^[a-z0-9][a-z0-9-]*$/.test(c.id)) throw new Error(`connect id ${JSON.stringify(c.id)}: use lowercase letters, digits and dashes`);
    const kind = c.kind ?? "slack";
    if (!CONNECT_KINDS.includes(kind)) throw new Error(`connect ${c.id}: unknown kind ${String(kind)}`);
    const mode = c.mode ?? "multi-session";
    if (!CONNECT_MODES.includes(mode)) throw new Error(`connect ${c.id}: unknown mode ${String(mode)}`);
    const runtime = c.bind?.runtime;
    if (!RUNTIMES.includes(runtime)) throw new Error(`connect ${c.id}: unknown runtime ${String(runtime)}`);
    if (c.bind.effort && !EFFORTS[runtime].includes(c.bind.effort)) throw new Error(`connect ${c.id}: ${runtime} has no effort ${c.bind.effort}; use ${EFFORTS[runtime].join(", ")}`);
    return {
      id: c.id,
      name: c.name?.trim() || c.id,
      enabled: c.enabled ?? true,
      kind,
      mode,
      requireMention: mode === "multi-session" ? true : c.requireMention ?? true,
      slack: { appToken: c.slack?.appToken ?? "", botToken: c.slack?.botToken ?? "", ...(c.slack?.appId ? { appId: c.slack.appId } : {}) },
      bind: { runtime, ...(c.bind.model ? { model: c.bind.model } : {}), ...(c.bind.effort ? { effort: c.bind.effort } : {}) },
      ...(c.createdBy?.id ? { createdBy: { id: c.createdBy.id, name: c.createdBy.name ?? "" } } : {}),
    };
  });
  unique("connect", connects.map((c) => c.id));

  const agentHome = raw.agentHome ?? "agent";
  return {
    dataDir,
    adminHttp: { host: raw.admin?.host ?? "127.0.0.1", port: raw.admin?.port ?? 4760 },
    adminAccess: raw.admin?.access?.teamDomain && raw.admin.access.aud
      ? { teamDomain: raw.admin.access.teamDomain, aud: raw.admin.access.aud }
      : null,
    slackConfigTokens: (raw.slackConfigTokens ?? []).filter((t) => t.refreshToken && t.teamId),
    agentHome: isAbsolute(agentHome) ? agentHome : join(dataDir, agentHome),
    http: { host: raw.http?.host ?? "127.0.0.1", port: raw.http?.port ?? 4750 },
    connects,
    profiles,
    maxNudges: raw.maxNudges ?? 2,
    warmMs: (raw.warmMinutes ?? 30) * 60_000,
    maxWarmClaude: raw.maxWarmClaude ?? 4,
    telemetry: { errors: raw.telemetry?.errors === true, traces: raw.telemetry?.traces === true },
  };
}

function unique(kind: string, ids: string[]): void {
  const seen = new Set<string>();
  for (const id of ids) {
    if (seen.has(id)) throw new Error(`duplicate ${kind} id ${id}`);
    seen.add(id);
  }
}

/** The profiles a connect's sessions can run on: every profile of its runtime (pool.ts picks one per session). */
export function profilesFor(config: Config, connect: Connect): Profile[] {
  return config.profiles.filter((p) => p.runtimes.includes(connect.bind.runtime));
}

/**
 * The runtimes an account runs, set up by the station for each: an OpenCode Go key both, an Anthropic key Claude Code;
 * a subscription (and custom variables) the runtime it was made for.
 */
export function runtimesOf(kind: AccessKind, runtime: RuntimeKind | undefined): RuntimeKind[] {
  if (kind === "opencode-go") return ["claude", "codex"];
  if (kind === "anthropic-api") return ["claude"];
  return runtime && RUNTIMES.includes(runtime) ? [runtime] : [];
}

export function expandRoute(env: Record<string, string>, route: string): Record<string, string> {
  return Object.fromEntries(Object.entries(env).map(([k, v]) => [k, v.replaceAll("{route}", route)]));
}
