// The account pool: which of a station's profiles a new session runs on.
// A profile is out if its check says it cannot sign in or was rejected, if
// its allowance is used up, or if its checked model list lacks the model
// asked for. Of the rest, the one with the most allowance left wins; then the
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

function serves(check: ProfileCheck | null, model: string | null): boolean {
  return !model || !check?.models?.length || check.models.includes(model);
}

export function pickProfile(candidates: Profile[], model: string | null, signals: PoolSignals): Profile {
  if (candidates.length === 0) throw new Error("no profile to run on");
  const rank = candidates.map((p) => ({ p, h: signals.health(p.id) }));
  const healthy = rank.filter(({ h }) => h.check?.state !== "login" && h.check?.state !== "failed" && used(h.quota) < 100);
  const fit = healthy.filter(({ h }) => serves(h.check, model));
  // Nothing healthy fits: fall back to any that serves the model, then to any at all, so the failure shows in the session.
  const pool = fit.length ? fit : rank.filter(({ h }) => serves(h.check, model)).length ? rank.filter(({ h }) => serves(h.check, model)) : rank;
  pool.sort((a, b) =>
    used(a.h.quota) - used(b.h.quota)
    || signals.load(a.p.id) - signals.load(b.p.id)
    || signals.lastPicked(a.p.id) - signals.lastPicked(b.p.id));
  return pool[0]!.p;
}
