// What the hub reads of config.json (the Rust station's config.rs `Config`, as parse_config fills it in): profiles, connects,
// and the numbers that govern turns, warm processes and archiving. Read on every use (the hub is given a function), so
// edits apply to the next decision. A profile stays config.json's object (the drivers read its access, env, model…),
// its home made absolute and what parse_config derives added: name, runtimes, models, backgroundOnMessage.
import { isAbsolute, join } from "node:path";
import { afreshThreshold } from "../../../client/core-ts/src/cache-policy.ts";
import { runtimeKind, runtimeLabel, type Profile as RuntimeProfile } from "../agents/runtime.ts";
import { profileRuntimes, type Runtime } from "../agents/profiles.ts";
import { modelKey } from "../read/usage.ts";

export type { Runtime };

export type Profile = RuntimeProfile & {
  /// Shown instead of the id.
  name: string;
  /// The runtimes it can run.
  runtimes: Runtime[];
  /// Models it runs: those named by hand (`named`), then the rest its check found (each once, in either spelling).
  models: string[];
  /// Models named in config.json (trimmed, each once): by hand where its provider lists none, or ticked on before every
  /// model its check found ran.
  named: string[];
  model?: string;
  /// A message that reaches a running Claude Code turn first moves what it waits on to the background (absent: on).
  backgroundOnMessage: boolean;
  /// The joined workspaces kept from it (docs/multi-workspace.md): every workspace the station is in runs on it but these.
  withheld?: string[];
};

export type ConnectMode = "multi-session" | "single-session";

/// What a connect's bot is on: Slack, or Feishu (src/feishu; Lark too).
export type ConnectKind = "slack" | "feishu";

export type Connect = {
  id: string;
  kind: ConnectKind;
  enabled: boolean;
  mode: ConnectMode;
  /// single-session only: whether starting on a new thread needs an @mention (multi-session: always).
  requireMention: boolean;
  slack: { botName?: string; [key: string]: unknown };
  bind: { runtime: Runtime; profile?: string; model?: string; effort?: string };
  /// The workspace it was added in, whose chats its sessions are (docs/multi-workspace.md); absent: the home one.
  workspace?: string;
};

/// decision.rs `DecisionRule`: the completion review after all_done, and the model it asks.
export type DecisionRule = { enabled: boolean; model: string | null };

export type HubConfig = {
  dataDir: string;
  /// The home workspace's MEMORY.md and skills/, a joined workspace's in workspaces/<ws> (sessions/agent-home.ts).
  agentHome: string;
  connects: Connect[];
  profiles: Profile[];
  /// How many times a turn that ended without a state is nudged before giving up.
  maxNudges: number;
  automaticDecisions: { completion: DecisionRule };
  /// Idle claude processes kept alive at most this long before they may be evicted.
  warmMs: number;
  /// Idle claude processes beyond this count are evicted, oldest first, once past warmMs.
  maxWarmClaude: number;
  /// Chats idle this long, and done (auto archive), are archived by the station; 0: never.
  autoArchiveMs: number;
  /// Sessions heard only in Slack idle this long are archived even when stopped at a block for someone (nobody sees
  /// those in the station's lists); 0: never.
  slackArchiveMs: number;
  /// Only chats the archive review recommended are archived on their own (none while the review is off); Slack sessions
  /// stopped at a block go after slackArchiveMs all the same.
  autoArchiveReviewed: boolean;
  /// Sessions archived this long keep only the files sent in their chat, their history and transcripts: the rest of
  /// their workspace is removed (cold.ts `expire`); 0: never.
  archivedWorkspaceMs: number;
  /// A message or notice to an agent whose prompt cache is over starts it afresh when its estimated reread cost reaches
  /// the threshold, unless its chat chose otherwise (routes/context.ts).
  afreshWhenCold: boolean;
  /// Estimated USD to reread a cold cache at which the station defaults to starting afresh.
  afreshAbove: number;
};

const str = (v: unknown): string | undefined => (typeof v === "string" ? v : undefined);
const nonEmpty = (v: unknown): string | undefined => (typeof v === "string" && v !== "" ? v : undefined);
const under = (dataDir: string, path: string) => (isAbsolute(path) ? path : join(dataDir, path));

/// A profile on the machine's login as it was named before (「b@x.com（本机）」, "Local Codex"), without the "this machine"
/// it was said with: read from another machine, that was the other machine.
const machineName = (name: string | undefined) => name?.replace(/（本机）$| \(local\)$/, "").replace(/^本机 |^Local /, "");

/// config.json (parsed) as the hub reads it: parse_config's defaults and derivations, without its checks (the config
/// module refuses a config that does not pass them before anything reads it). `found`: the models a profile's last check
/// found (accounts/index.ts), which it runs besides those config.json names; none for one that runs no runtime (a
/// provider of the automatic decisions alone: its models are not chat models).
export function hubConfig(raw: any, dataDir: string, found: (id: string) => readonly string[] | null = () => null): HubConfig {
  const profiles: Profile[] = (Array.isArray(raw?.profiles) ? raw.profiles : []).map((p: any): Profile => {
    const seen = new Set<string>();
    const models = (Array.isArray(p.models) ? p.models : [])
      .map((m: unknown) => String(m).trim())
      .filter((m: string) => m !== "" && !seen.has(m) && (seen.add(m), true));
    const base: RuntimeProfile = { ...p, home: under(dataDir, String(p.home ?? "")) };
    const runtimes = profileRuntimes(base);
    const runs = [...models];
    if (runtimes.length > 0) {
      const has = new Set(models.map(modelKey));
      for (const m of found(String(p.id)) ?? []) {
        if (m === "" || has.has(modelKey(m))) continue;
        has.add(modelKey(m));
        runs.push(m);
      }
    }
    return {
      ...base,
      id: p.id,
      name: (p.machine === true ? machineName(str(p.name)) : str(p.name))?.trim() || p.id,
      // One that runs neither runtime (a provider of chat completions only) is Claude's in name.
      runtime: runtimes[0] ?? "claude",
      runtimes,
      models: runs,
      named: models,
      model: nonEmpty(p.model),
      backgroundOnMessage: p.backgroundOnMessage !== false,
      ...(Array.isArray(p.withheld) ? { withheld: p.withheld.filter((w: unknown): w is string => typeof w === "string" && w !== "") } : {}),
    };
  });
  const connects: Connect[] = (Array.isArray(raw?.connects) ? raw.connects : []).map((c: any): Connect => {
    const mode: ConnectMode = c.mode === "single-session" ? "single-session" : "multi-session";
    const bind = c.bind ?? {};
    return {
      id: c.id,
      kind: c.kind === "feishu" ? "feishu" : "slack",
      enabled: c.enabled !== false,
      mode,
      requireMention: mode === "multi-session" ? true : c.requireMention !== false,
      slack: { ...(c.slack ?? {}), botName: nonEmpty(c.slack?.botName) },
      bind: { runtime: runtimeKind(bind.runtime) ?? "claude", profile: nonEmpty(bind.profile), model: nonEmpty(bind.model), effort: nonEmpty(bind.effort) },
      ...(nonEmpty(c.workspace) !== undefined ? { workspace: nonEmpty(c.workspace) } : {}),
    };
  });
  const completion = raw?.automaticDecisions?.completion ?? {};
  return {
    dataDir,
    agentHome: under(dataDir, str(raw?.agentHome) ?? "agent"),
    connects,
    profiles,
    maxNudges: typeof raw?.maxNudges === "number" ? raw.maxNudges : 2,
    automaticDecisions: { completion: { enabled: completion.enabled === true, model: str(completion.model) ?? null } },
    warmMs: Math.trunc((typeof raw?.warmMinutes === "number" ? raw.warmMinutes : 30) * 60_000),
    maxWarmClaude: typeof raw?.maxWarmClaude === "number" ? raw.maxWarmClaude : 4,
    autoArchiveMs: Math.trunc(Math.max(0, typeof raw?.autoArchiveDays === "number" ? raw.autoArchiveDays : 1) * 86_400_000),
    slackArchiveMs: Math.trunc(Math.max(0, typeof raw?.slackArchiveDays === "number" ? raw.slackArchiveDays : 3) * 86_400_000),
    autoArchiveReviewed: raw?.autoArchiveReviewed === true,
    archivedWorkspaceMs: Math.trunc(Math.max(0, typeof raw?.archivedWorkspaceDays === "number" ? raw.archivedWorkspaceDays : 7) * 86_400_000),
    afreshWhenCold: raw?.afreshWhenCold === true,
    afreshAbove: afreshThreshold(raw?.afreshAbove),
  };
}

/// Its own spelling of a model it runs, however the model is spelled (gpt-6-astra here may be
/// openai/gpt-6-astra there).
export function spelling(profile: Profile, model: string): string | null {
  return profile.models.find((m) => m === model) ?? profile.models.find((m) => sameModel(m, model)) ?? null;
}

/// Whether it runs a model, in any spelling.
export const runs = (profile: Profile, model: string): boolean => spelling(profile, model) !== null;

/// shapes model.rs `same`: two spellings are one model.
export const sameModel = (a: string, b: string): boolean => a === b || modelKey(a) === modelKey(b);

/// Whether sessions of workspace `ws` (null: the home one's) may run on a profile (docs/multi-workspace.md): those of
/// the home workspace (`home`; null outside any, when there is no telling) on every profile, those of a joined one on
/// every profile not withheld from it. A copy of another station's profile (share/index.ts) only in the workspaces that
/// station shares it in, as it says (`share.workspaces`): its account is for those workspaces' people alone.
export const allowedIn = (profile: Profile, ws: string | null, home: string | null): boolean => {
  const share = profile.share as { borrowed?: unknown; workspaces?: unknown } | undefined;
  const only = share?.borrowed === true && Array.isArray(share.workspaces) ? share.workspaces : null;
  const at = ws ?? home;
  if (only !== null && at !== null && !only.includes(at)) return false;
  return ws === null || home === null || ws === home || !(profile.withheld ?? []).includes(ws);
};

/// The profiles a connect's sessions can run on: every profile of its runtime allowed in its workspace.
export const profilesFor = (config: HubConfig, connect: Connect, home: string | null = null): Profile[] =>
  config.profiles.filter((p) => p.runtimes.includes(connect.bind.runtime) && allowedIn(p, connect.workspace ?? null, home));

export const runtimeName = (r: Runtime) => r;
export const runtimeNamed = (name: string): Runtime | null => runtimeKind(name) ?? null;
/// How people call a runtime.
export const runtimeTitle = (r: Runtime) => runtimeLabel(r);
