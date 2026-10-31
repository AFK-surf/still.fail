// The account pool (the Rust station's pool.rs): which of a station's profiles a session runs on. Only profiles with the
// chosen model enabled qualify; of those, one whose check says it cannot sign in or was rejected, or whose allowance is
// used up, is passed over. Accounts paid for already (subscriptions, memberships) go first: one billed per use (an API
// key, a gateway) runs a session only when none of them can, and its sessions move back before a turn when one can again
// and that loses little. Of the rest: one whose short window (5 hours) is nearly full goes last. The others share the
// sessions by weight, each new one going where (sessions + 1) ÷ weight is least: the weight is how fast a profile has
// to spend not to lose any of its long window (a week; left × window length ÷ time to refill), times what is left of
// its short one. So what would be lost is spent first without all sessions crowding onto one account and running its
// five hours out together (2026-10-19: a dozen sessions moved from one account to the next, emptying each in turn).
// Even, the one picked least recently. A session keeps its profile while it is usable (on another it starts afresh and
// reads back what it needs: afresh.ts); on one nearly full it moves before a turn only when that loses little: its
// runtime has just compacted its context, or is about to (`cheapToLeave`).
// Also the reasoning levels a model offers (shapes reasoning.rs), which the pool's accounts decide.
import { type Profile, runs, sameModel } from "./config.ts";
import { billedPerUse } from "../agents/profiles.ts";
import { COMPACTED_FROM } from "../store/rows.ts";

type Json = any;

/// How a profile is doing: its last check and allowance (profiles.rs ProfileCheck / ProfileQuota, camelCase JSON), the
/// account whose allowance it uses when known, and whether a turn ran into that allowance since it was last read.
export type ProfileHealth = { check?: Json | null; quota?: Json | null; account?: string | null; spent?: boolean };

export type PoolSignals = {
  health(id: string): ProfileHealth;
  /// Sessions with a live process on this profile.
  load(id: string): number;
  /// When the pool last chose this profile (0 if never).
  lastPicked(id: string): number;
  /// Now, in milliseconds (allowances refill at times in milliseconds).
  now(): number;
};

const DAY_MS = 24 * 60 * 60 * 1000;
/// A short window this full puts its profile last, and its sessions move off it before their next turn when another
/// has room: a session sent or kept there would soon run into it.
const CROWDED_PERCENT = 80;
/// The least weight: a profile with nothing to lose still takes a session when every other is busier.
const MIN_WEIGHT = 0.01;

export const windowsOf = (quota: Json | null | undefined): Json[] => (quota && quota.state === "ok" && Array.isArray(quota.windows) ? quota.windows : []);

/// How much of its tightest window a profile has used, 0–100; unknown counts as half.
function used(quota: Json | null | undefined): number {
  const windows = windowsOf(quota);
  if (windows.length > 0) return windows.reduce((max: number, w: Json) => Math.max(max, Number(w.usedPercent)), -Number.MAX_VALUE);
  return 50;
}

/// How a profile's allowance ranks: whether its short windows are nearly full; how fast it has to be spent not to lose
/// any (1: evenly over the window; a window of unknown length or refill counts as what it has left, evenly); and its
/// share of the sessions (`weight`: the pace, times what its short windows have left when it has a long one).
export type Urgency = { crowded: boolean; pace: number; weight: number };

/// The long windows (over a day) are what can be lost: the short ones refill again and again inside them, and only
/// keep a profile from taking more now. A profile with no long window is weighed by the ones it has. Of several, the
/// slowest counts: the others cannot be spent faster than it lets. A long window refilling within a day counts as a
/// day away: what is left of it can only be spent five hours at a time, so a few minutes to go does not make it take
/// every session.
export function urgency(quota: Json | null | undefined, now: number): Urgency {
  const windows = windowsOf(quota).filter((w) => typeof w.minutes === "number" && w.minutes > 0);
  const long = windows.filter((w) => w.minutes * 60_000 > DAY_MS);
  const short = windows.filter((w) => w.minutes * 60_000 <= DAY_MS);
  const crowded = long.length > 0 && short.some((w) => Number(w.usedPercent) >= CROWDED_PERCENT);
  // What the short windows leave of it now (with no long window they are what the pace is of).
  const room = long.length > 0 ? short.reduce((min, w) => Math.min(min, Math.max(0, 100 - Number(w.usedPercent)) / 100), 1) : 1;
  const weighted = (u: Omit<Urgency, "weight">): Urgency => ({ ...u, weight: Math.max(u.pace * room, MIN_WEIGHT) });
  const weighed = (long.length > 0 ? long : short).filter((w) => typeof w.resetsAt === "number");
  if (weighed.length === 0) return weighted({ crowded, pace: (100 - used(quota)) / 100 });
  const paces = weighed.map((w) => {
    const left = Math.max(0, 100 - Number(w.usedPercent)) / 100;
    const length = w.minutes * 60_000;
    // A refill already due (an allowance read before it): the whole window is ahead.
    const remaining = Math.min(length, Math.max(w.resetsAt - now, 0) || length);
    return (left * length) / (length > DAY_MS ? Math.max(remaining, DAY_MS) : remaining);
  });
  return weighted({ crowded, pace: Math.min(...paces) });
}

/// A context falling under half of what the call before sent (at least this much), on the same account and model, was
/// compacted (store/rows.ts, where the database keeps where it was: schema.ts USAGE_COMPACTIONS).
export { COMPACTED_FROM };
/// How near a session's context is to where its model is compacted (compactionPoints) to be about to be.
const NEAR_COMPACTION = 0.75;

type ContextCall = { turn: string | null; profile: string | null; model: string | null; context: number | null };

/// Whether a session loses little by going on afresh on another account, by its last main-thread calls (oldest first)
/// and where each model is compacted on this station: its runtime compacted its context in its last two turns (what
/// it carries on with is a summary already), or its context is three quarters of the way to that (it is about to be).
export function cheapToLeave(calls: ContextCall[], points: Map<string, number>): boolean {
  const last = calls.at(-1);
  if (!last) return false;
  const point = last.model === null ? undefined : points.get(last.model);
  if (point !== undefined && last.context !== null && last.context >= point * NEAR_COMPACTION) return true;
  const turns = [...new Set(calls.map((c) => c.turn))].slice(-2);
  return calls.some((c, i) => {
    const before = calls[i - 1];
    if (before === undefined || before.context === null || c.context === null) return false;
    return turns.includes(c.turn) && before.context >= COMPACTED_FROM && c.context * 2 < before.context && c.profile === before.profile && c.model === before.model;
  });
}

/// Whether a profile can run now: it signs in, its key was not rejected, none of its windows is used up, and no turn
/// ran into its allowance since.
export function usable(health: ProfileHealth): boolean {
  const state = health.check?.state;
  return !health.spent && state !== "login" && state !== "failed" && used(health.quota) < 100;
}

/// A chosen model needs the profile to have it enabled; no model means the profile's own default.
export const serves = (profile: Profile, model: string | null | undefined): boolean => model === null || model === undefined || runs(profile, model);

/// `strict` (a chat started by hand): the model must be enabled on a profile. Otherwise (a connect's binding, set up
/// before models were enabled) profiles with it enabled are preferred, and without any the bound ones still serve.
export function pickProfile(candidates: Profile[], model: string | null | undefined, signals: PoolSignals, strict: boolean): Profile {
  if (candidates.length === 0) throw new Error("no profile to run on");
  const rank = candidates.map((p) => [p, signals.health(p.id)] as const);
  let serving = rank.map((_, i) => i).filter((i) => serves(rank[i]![0], model));
  if (serving.length === 0) {
    if (strict) throw new Error(`no profile has ${model ?? ""} enabled; enable it on a profile first`);
    serving = rank.map((_, i) => i);
  }
  const fit = serving.filter((i) => usable(rank[i]![1]));
  // What is paid for already is spent first, however full: one billed per use only when none of those can run now.
  const paid = fit.filter((i) => !billedPerUse(rank[i]![0]));
  // Nothing healthy serves it: still pick one that has it enabled, so the failure shows in the session.
  const pool = paid.length > 0 ? paid : fit.length > 0 ? fit : serving;
  const now = signals.now();
  const urgencies = new Map(pool.map((i) => [i, urgency(rank[i]![1].quota, now)]));
  // Each profile's sessions over its weight, with the new one: the least is where it adds the least crowding.
  const share = (i: number) => (signals.load(rank[i]![0].id) + 1) / urgencies.get(i)!.weight;
  // A stable sort, as Rust's sort_by.
  pool.sort((a, b) => {
    const [ua, ub] = [urgencies.get(a)!, urgencies.get(b)!];
    return Number(ua.crowded) - Number(ub.crowded) || share(a) - share(b) || signals.lastPicked(rank[a]![0].id) - signals.lastPicked(rank[b]![0].id);
  });
  return rank[pool[0]!]![0];
}

// ── reasoning levels (client/core-ts/src/shapes/reasoning.ts) ──

/// Runtime-reported model capabilities: runtime → model → levels.
export type Catalog = Record<string, Record<string, string[]>>;

export function fallbackEfforts(runtime: string): string[] {
  if (runtime === "codex") return ["minimal", "low", "medium", "high", "xhigh"];
  // DeepSeek Harness's, as dsh.ts gives each route them.
  if (runtime === "dsh") return ["low", "medium", "high", "max"];
  // Grok Build's models offer these (grok.ts); a model's own list comes with it.
  if (runtime === "grok") return ["low", "medium", "high", "xhigh"];
  // Cursor's models say their effort in the model's own name (id[reasoning=…], agents/cursor.ts): none apart.
  if (runtime === "cursor" || runtime === "hermes") return [];
  // Devin's are its models' thinking levels (agents/devin.ts); a model's own list comes with it.
  if (runtime === "devin") return ["low", "medium", "high", "xhigh", "max"];
  return ["low", "medium", "high", "xhigh", "max"];
}

/// The levels a model offers: as its runtime reported them (an empty list: none), else the runtime's usual ones.
export function availableEfforts(runtime: string, model: string | null | undefined, catalog: Catalog | null | undefined): string[] {
  const models = catalog?.[runtime];
  if (model !== null && model !== undefined && models) {
    const levels = models[model] ?? Object.entries(models).find(([id]) => sameModel(id, model))?.[1];
    if (levels) return [...levels];
  }
  return fallbackEfforts(runtime);
}

/// The levels every one of these offers.
export function commonEfforts(profiles: string[][], runtime: string): string[] {
  const [first, ...others] = profiles;
  if (!first) return availableEfforts(runtime, null, null);
  return first.filter((level) => others.every((o) => o.includes(level)));
}
