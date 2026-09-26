// The account pool: which of a station's profiles a new session runs on.
// Only profiles with the chosen model enabled qualify; of those, one whose
// check says it cannot sign in or was rejected, or whose allowance is used
// up, is passed over. Of the rest, the one with the most allowance left wins; then the
// one running fewer sessions; then the one picked least recently. A session
// keeps its profile afterwards, since resuming needs that account's home.
import type { Profile } from "./config.ts";
import type { ProfileCheck } from "./profiles.ts";
import type { ProfileQuota } from "./quota.ts";

export interface ProfileHealth { check: ProfileCheck | null; quota: ProfileQuota | null }

export interface PoolSignals {
  health(id: string): ProfileHealth;
  /** Sessions with a live process on this profile. */
  load(id: string): number;
  /** When the pool last chose this profile (0 if never). */
  lastPicked(id: string): number;
}

/** How much of its tightest window a profile has used, 0–100; unknown counts as half. */
function used(quota: ProfileQuota | null): number {
  if (quota?.state !== "ok" || quota.windows.length === 0) return 50;
  return Math.max(...quota.windows.map((w) => w.usedPercent));
}

/** A chosen model needs the profile to have it enabled; no model means the profile's own default. */
export function serves(profile: Profile, model: string | null): boolean {
  return !model || profile.models.includes(model);
}

/**
 * `strict` (a chat started by hand): the model must be enabled on a profile.
 * Otherwise (a connect's binding, set up before models were enabled) profiles
 * with it enabled are preferred, and without any the bound ones still serve.
 */
export function pickProfile(candidates: Profile[], model: string | null, signals: PoolSignals, strict = true): Profile {
  if (candidates.length === 0) throw new Error("no profile to run on");
  const rank = candidates.map((p) => ({ p, h: signals.health(p.id) }));
  const healthy = rank.filter(({ h }) => h.check?.state !== "login" && h.check?.state !== "failed" && used(h.quota) < 100);
  let serving = rank.filter(({ p }) => serves(p, model));
  if (serving.length === 0) {
    if (strict) throw new Error(`no profile has ${model} enabled; enable it on a profile first`);
    serving = rank;
  }
  const fit = healthy.filter((r) => serving.includes(r));
  // Nothing healthy serves it: still pick one that has it enabled, so the failure shows in the session.
  const pool = fit.length ? fit : serving;
  pool.sort((a, b) =>
    used(a.h.quota) - used(b.h.quota)
    || signals.load(a.p.id) - signals.load(b.p.id)
    || signals.lastPicked(a.p.id) - signals.lastPicked(b.p.id));
  return pool[0]!.p;
}
