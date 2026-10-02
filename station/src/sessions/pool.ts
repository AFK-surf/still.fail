// The account pool (mesh/app/src/pool.rs): which of a station's profiles a session runs on. Only profiles with the
// chosen model enabled qualify; of those, one whose check says it cannot sign in or was rejected, or whose allowance is
// used up, is passed over. Of the rest, the one with the most allowance left wins; then the one running fewer
// sessions; then the one picked least recently. A session keeps its profile while it is usable (its runtime's cache is
// that account's); its transcripts are shared by all, so when it is not, another takes it on.
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
};

/// How much of its tightest window a profile has used, 0–100; unknown counts as half.
function used(quota: Json | null | undefined): number {
  if (quota && quota.state === "ok" && Array.isArray(quota.windows) && quota.windows.length > 0) {
    return quota.windows.reduce((max: number, w: Json) => Math.max(max, Number(w.usedPercent)), -Number.MAX_VALUE);
  }
  return 50;
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
  // A stable sort, as Rust's sort_by.
  pool.sort((a, b) => {
    const [pa, pb] = [rank[a]!, rank[b]!];
    return used(pa[1].quota) - used(pb[1].quota) || signals.load(pa[0].id) - signals.load(pb[0].id) || signals.lastPicked(pa[0].id) - signals.lastPicked(pb[0].id);
  });
  return rank[pool[0]!]![0];
}

// ── reasoning levels (client/shapes/src/reasoning.rs) ──

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
