// A Claude subscription's limit resets (what Claude Code's /limit-reset uses), read and used as the installed Claude
// Code does. Its OAuth usage endpoint says them only to Claude Code's own CLI, of a version that has them (its
// User-Agent: another surface or an older version is "ineligible"), in two programs:
// - `juniper_tide`: the 5-hour limit reset now, once a week, available only at the 5-hour limit; used with
//   `{program}` alone;
// - `cedar_ember`: resets granted to the account (a model's launch, say), each grant some resets until a date, usable
//   now or once at a limit (`usable_now`); used with `{program, grant_id, request_id}`, the request id making a
//   retry after a lost reply harmless.
// Both are used at POST /api/organizations/<organization>/reset_rate_limits, its organization as /api/oauth/profile
// says. The one used is the weekly 5-hour reset when it is there (it comes back each week), else the grant the
// provider names next.
import { createHash } from "node:crypto";
import { profileFetch } from "../ops/agent-env.ts";

type Json = any;

const TIMEOUT_MS = 25_000;

/// The usage read that says the resets as well (the windows as /api/oauth/usage says them; no spend, which is not read).
export const USAGE_PATH = "/api/oauth/usage?at_wall=1&skip_spend=1";

/// Claude Code's own headers for its OAuth endpoints: the resets are offered only to it, by its version.
export function claudeHeaders(token: string, version: string | null): Record<string, string> {
  return {
    authorization: `Bearer ${token}`,
    "anthropic-beta": "oauth-2025-04-20",
    ...(version !== null ? { "user-agent": `claude-cli/${version} (external, cli)` } : {}),
  };
}

const isObject = (v: unknown): v is Record<string, any> => v !== null && typeof v === "object" && !Array.isArray(v);
const count = (v: unknown): number => (Number.isInteger(v) && (v as number) > 0 ? (v as number) : 0);

function time(v: unknown): number | null {
  if (typeof v !== "string" || !/^\d{4}-\d{2}-\d{2}T/.test(v)) return null;
  const ms = Date.parse(v);
  return Number.isNaN(ms) ? null : ms;
}

/// A grant still holding resets.
/// The weekly 5-hour reset there to use (as Claude Code reads it: in the experiment's reset arm, and available).
const tideReady = (tide: Json) => isObject(tide) && tide.eligible === true && tide.arm === "reset" && tide.available === true;

const live = (g: Json) => isObject(g) && typeof g.id === "string" && count(g.resets_left) > 0 && g.paused !== true;

/// The resets a usage answer says the account holds, and when the granted ones end (one date per reset), or null when
/// it holds none to show (none offered: another surface, an older Claude Code, a plan without them; or all used).
export function claudeResets(body: Json): { count: number; expiries: number[] } | null {
  const tide = body?.juniper_tide;
  const ember = body?.cedar_ember;
  const tideOffered = isObject(tide) && tide.eligible === true;
  const emberOffered = isObject(ember) && ember.eligible === true;
  if (!tideOffered && !emberOffered) return null;
  let n = tideReady(tide) ? 1 : 0;
  const expiries: number[] = [];
  for (const g of emberOffered && Array.isArray(ember.grants) ? ember.grants : []) {
    if (!live(g)) continue;
    n += count(g.resets_left);
    const ends = time(g.ends_at);
    if (ends !== null) for (let i = 0; i < count(g.resets_left); i++) expiries.push(ends);
  }
  return n === 0 ? null : { count: n, expiries: expiries.sort((a, b) => a - b) };
}

/// The claim a usage answer allows now: the weekly 5-hour reset, else the grant named next (or the first usable one);
/// "none" when it holds resets that cannot be used now, "noCredit" when it holds none.
export function claudeClaim(body: Json, key: string): { program: string; grant_id?: string; request_id?: string } | "none" | "noCredit" {
  const tide = body?.juniper_tide;
  if (tideReady(tide)) return { program: "juniper_tide" };
  const ember = body?.cedar_ember;
  const grants: Json[] = isObject(ember) && ember.eligible === true && Array.isArray(ember.grants) ? ember.grants.filter(live) : [];
  const usable = grants.filter((g) => g.usable_now === true);
  const grant = usable.find((g) => g.id === ember?.next_grant_id) ?? usable[0];
  // Claude Code's request id: [A-Za-z0-9_-]{1,64}; the station's idempotency key, made to fit and the same each retry.
  if (grant) return { program: "cedar_ember", grant_id: grant.id, request_id: createHash("sha256").update(key).digest("hex") };
  return grants.length > 0 || (isObject(tide) && tide.eligible === true) ? "none" : "noCredit";
}

/// What a claim's answer means to the station (the outcomes of Accounts.resetQuota, Codex's words).
export function claimOutcome(result: unknown): string {
  switch (result) {
    case "reset":
      return "reset";
    // A retried request after its reset went through, or a reset spent since: the allowance read again says which.
    case "already_used":
      return "alreadyRedeemed";
    case "not_limited":
      return "nothingToReset";
    case "cooldown":
    case "ineligible":
      return "unavailable";
    default:
      return "unconfirmed";
  }
}

const json = async (response: Response): Promise<Json> => {
  try {
    return await response.json();
  } catch {
    return null;
  }
};

/// Uses one of the account's resets with `token`. `{outcome}`, or `{unauthorized: true}` when the provider said the
/// token is not good (it is renewed and asked again by the caller).
export async function claudeResetWith(base: string, token: string, version: string, key: string): Promise<Json> {
  const headers = claudeHeaders(token, version);
  const ask = (path: string, body?: Json) =>
    profileFetch(`${base}${path}`, {
      ...(body !== undefined ? { method: "POST", body: JSON.stringify(body) } : {}),
      headers: { ...headers, ...(body !== undefined ? { "content-type": "application/json" } : {}) },
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
  const usage = await ask(USAGE_PATH);
  if (usage.status === 401) return { unauthorized: true };
  if (!usage.ok) throw new Error(`Anthropic ${usage.status}`);
  const claim = claudeClaim(await json(usage), key);
  if (claim === "none") return { outcome: "nothingToReset" };
  if (claim === "noCredit") return { outcome: "noCredit" };
  const profile = await ask("/api/oauth/profile");
  if (profile.status === 401) return { unauthorized: true };
  const organization = (await json(profile))?.organization?.uuid;
  if (!profile.ok || typeof organization !== "string" || !/^[A-Za-z0-9-]{1,64}$/.test(organization)) throw new Error(`Anthropic did not say the account's organization (${profile.status})`);
  const answer = await ask(`/api/organizations/${organization}/reset_rate_limits`, claim);
  if (answer.status === 401) return { unauthorized: true };
  if (answer.status === 429) return { outcome: "unavailable" };
  if (!answer.ok) throw new Error(`Anthropic ${answer.status}`);
  return { outcome: claimOutcome((await json(answer))?.result) };
}
