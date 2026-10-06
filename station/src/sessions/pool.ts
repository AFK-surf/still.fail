// The account pool (the Rust station's pool.rs): which of a station's profiles a session runs on. Only profiles with the
// chosen model enabled qualify; of those, one whose check says it cannot sign in or was rejected, or whose allowance is
// used up, is passed over. Of the rest: one whose short window (5 hours) is nearly full goes last; one whose long
// window (a week) refills within a day, with some left, goes first, as what is left then is lost; then the one that has
// to spend fastest not to lose any (left × window length ÷ time to refill); then the one running fewer sessions; then
// the one picked least recently. A session keeps its profile while it is usable (its runtime's cache is that
// account's); its transcripts are shared by all, so when it is not, another takes it on.
// Also the reasoning levels a model offers (shapes reasoning.rs), which the pool's accounts decide.
import { type Profile, runs, sameModel } from "./config.ts";

type Json = any;

/// How a profile is doing: its last check and allowance (profiles.rs ProfileCheck / ProfileQuota, camelCase JSON), and
/// whether a turn on it ran into its allowance since the allowance was last read (Hub `spend`).
export type ProfileHealth = { check?: Json | null; quota?: Json | null; spent?: boolean };

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
/// A short window this full puts its profile last: a session sent there would soon run into it.
const CROWDED_PERCENT = 80;

const windowsOf = (quota: Json | null | undefined): Json[] => (quota && quota.state === "ok" && Array.isArray(quota.windows) ? quota.windows : []);

/// How much of its tightest window a profile has used, 0–100; unknown counts as half.
function used(quota: Json | null | undefined): number {
  const windows = windowsOf(quota);
  if (windows.length > 0) return windows.reduce((max: number, w: Json) => Math.max(max, Number(w.usedPercent)), -Number.MAX_VALUE);
  return 50;
}

/// How a profile's allowance ranks: whether its short windows are nearly full; whether a long window refills within a
/// day with some left; how fast it has to be spent not to lose any (1: evenly over the window; a window of unknown
/// length or refill counts as what it has left, evenly).
export type Urgency = { crowded: boolean; soon: boolean; pace: number };

/// The long windows (over a day) are what can be lost: the short ones refill again and again inside them, and only
/// keep a profile from taking more now. A profile with no long window is weighed by the ones it has. Of several, the
/// slowest counts: the others cannot be spent faster than it lets.
export function urgency(quota: Json | null | undefined, now: number): Urgency {
  const windows = windowsOf(quota).filter((w) => typeof w.minutes === "number" && w.minutes > 0);
  const long = windows.filter((w) => w.minutes * 60_000 > DAY_MS);
  const short = windows.filter((w) => w.minutes * 60_000 <= DAY_MS);
  const crowded = long.length > 0 && short.some((w) => Number(w.usedPercent) >= CROWDED_PERCENT);
  const weighed = (long.length > 0 ? long : short).filter((w) => typeof w.resetsAt === "number");
  if (weighed.length === 0) return { crowded, soon: false, pace: (100 - used(quota)) / 100 };
  const paces = weighed.map((w) => {
    const left = Math.max(0, 100 - Number(w.usedPercent)) / 100;
    const length = w.minutes * 60_000;
    // A refill already due (an allowance read before it): the whole window is ahead.
    const remaining = Math.min(length, Math.max(w.resetsAt - now, 0) || length);
    return { pace: (left * length) / remaining, soon: long.length > 0 && left > 0 && w.resetsAt > now && w.resetsAt - now <= DAY_MS };
  });
  const slowest = paces.reduce((a, b) => (b.pace < a.pace ? b : a));
  return { crowded, soon: slowest.soon, pace: slowest.pace };
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
  // Nothing healthy serves it: still pick one that has it enabled, so the failure shows in the session.
  const pool = fit.length === 0 ? serving : fit;
  const now = signals.now();
  const urgencies = new Map(pool.map((i) => [i, urgency(rank[i]![1].quota, now)]));
  // A stable sort, as Rust's sort_by.
  pool.sort((a, b) => {
    const [pa, pb] = [rank[a]!, rank[b]!];
    const [ua, ub] = [urgencies.get(a)!, urgencies.get(b)!];
    return (
      Number(ua.crowded) - Number(ub.crowded) ||
      Number(ub.soon) - Number(ua.soon) ||
      ub.pace - ua.pace ||
      signals.load(pa[0].id) - signals.load(pb[0].id) ||
      signals.lastPicked(pa[0].id) - signals.lastPicked(pb[0].id)
    );
  });
  return rank[pool[0]!]![0];
}

// ── reasoning levels (client/core-ts/src/shapes/reasoning.ts) ──

/// Runtime-reported model capabilities: runtime → model → levels.
export type Catalog = Record<string, Record<string, string[]>>;

export function fallbackEfforts(runtime: string): string[] {
  return runtime === "codex" ? ["minimal", "low", "medium", "high", "xhigh"] : ["low", "medium", "high", "xhigh", "max"];
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
