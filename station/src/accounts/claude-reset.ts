// A Claude subscription's limit resets (what Claude Code's /limit-reset uses), read and used as the installed Claude
// Code does. Its OAuth usage endpoint says them only to Claude Code's own CLI, of a version that has them (its
// User-Agent: another surface or an older version is "ineligible"), in two programs:
// - `juniper_tide`: the 5-hour limit reset now, once a week, available only at the 5-hour limit; used with
//   `{program}` alone;
// - `cedar_ember`: resets granted to the account (a model's launch, say), each grant some resets until a date, usable
//   now or once at a limit (`usable_now`); used with `{program, grant_id, request_id}`, the request id making a
//   retry after a lost reply harmless.
// Both are used at POST /api/organizations/<organization>/reset_rate_limits, its organization as /api/oauth/profile
// says. They differ by what they give back (Claude Code's kinds: the 5-hour limit, the week, all, or what Fable used
// of the week): the station lists them a kind each and a person picks which kind to use.
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

/// The weekly 5-hour reset there to use (as Claude Code reads it: in the experiment's reset arm, and available).
const tideReady = (tide: Json) => isObject(tide) && tide.eligible === true && tide.arm === "reset" && tide.available === true;

/// A grant still holding resets.
const live = (g: Json) => isObject(g) && typeof g.id === "string" && count(g.resets_left) > 0 && g.paused !== true;

/// A grant's kind, as Claude Code names it: one that gives back to the week what a model used (Fable's launch) is that
/// model's; else the kind the provider says; else by the limits it clears.
export function grantKind(g: Json): ResetKind {
  if (g?.gives_back_weekly === true || g?.type === "fable") return "model";
  if (g?.type === "session" || g?.type === "weekly" || g?.type === "full") return g.type;
  const clears: unknown[] = Array.isArray(g?.clears) ? g.clears : [];
  const session = clears.includes("five_hour");
  const other = clears.some((c) => c !== "five_hour");
  return session && !other ? "session" : other && !session ? "weekly" : "full";
}

/// The kinds of a subscription's resets, by what one gives back: the 5-hour limit, the week's, all of them, what one
/// model used of the week (`model` says which), or a provider's own reset that says no more (a ChatGPT one: `credit`).
export type ResetKind = "session" | "weekly" | "full" | "model" | "credit";

/// One kind of reset an account holds, as the station tells it (ProfileQuota.resets): `id` what a reset of it is asked
/// by, how many are left, when each ends, and whether one can be used now (else only once at a limit it refills).
export type QuotaReset = { id: string; kind: ResetKind; model?: string; left: number; expiries?: number[]; usable: boolean };

const ORDER: ResetKind[] = ["session", "weekly", "model", "full", "credit"];

/// The resets a usage answer says the account holds, one entry a kind (its weekly 5-hour reset among the 5-hour ones),
/// in Claude Code's order. `model`: the one model a model's reset gives back to (the account's own week of it; Fable
/// when it says none, as Claude Code does).
export function claudeResets(body: Json, model: string | null = null): QuotaReset[] {
  const tide = body?.juniper_tide;
  const ember = body?.cedar_ember;
  const kinds = new Map<ResetKind, QuotaReset>();
  const add = (kind: ResetKind, left: number, usable: boolean, ends: number | null) => {
    const r = kinds.get(kind) ?? { id: kind, kind, ...(kind === "model" ? { model: model ?? "Fable" } : {}), left: 0, usable: false };
    r.left += left;
    r.usable ||= usable;
    if (ends !== null) r.expiries = [...(r.expiries ?? []), ...Array.from({ length: left }, () => ends)].sort((a, b) => a - b);
    kinds.set(kind, r);
  };
  if (tideReady(tide)) add("session", 1, true, null);
  for (const g of isObject(ember) && ember.eligible === true && Array.isArray(ember.grants) ? ember.grants : []) {
    if (live(g)) add(grantKind(g), count(g.resets_left), g.usable_now === true, time(g.ends_at));
  }
  return ORDER.flatMap((k) => (kinds.has(k) ? [kinds.get(k)!] : []));
}

/// The claim a usage answer allows now for a reset of `kind` (none: any, the weekly 5-hour reset first, as before
/// there were kinds): the weekly 5-hour reset for the 5-hour kind when it is there (it comes back each week), else of
/// that kind's grants the one the provider names next, else the one that ends first. "none" when resets of it are
/// held that cannot be used now, "noCredit" when none are.
export function claudeClaim(body: Json, key: string, kind: string | null = null): { program: string; grant_id?: string; request_id?: string } | "none" | "noCredit" {
  const tide = body?.juniper_tide;
  if ((kind === null || kind === "session") && tideReady(tide)) return { program: "juniper_tide" };
  const ember = body?.cedar_ember;
  const grants: Json[] = (isObject(ember) && ember.eligible === true && Array.isArray(ember.grants) ? ember.grants.filter(live) : []).filter((g: Json) => kind === null || grantKind(g) === kind);
  const usable = grants.filter((g) => g.usable_now === true).sort((a, b) => (time(a.ends_at) ?? Infinity) - (time(b.ends_at) ?? Infinity));
  const grant = usable.find((g) => g.id === ember?.next_grant_id) ?? usable[0];
  // Claude Code's request id: [A-Za-z0-9_-]{1,64}; the station's idempotency key, made to fit and the same each retry.
  if (grant) return { program: "cedar_ember", grant_id: grant.id, request_id: createHash("sha256").update(key).digest("hex") };
  return grants.length > 0 || ((kind === null || kind === "session") && isObject(tide) && tide.eligible === true) ? "none" : "noCredit";
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
/// `kind`: of the resets the allowance listed (none: any).
export async function claudeResetWith(base: string, token: string, version: string, key: string, kind: string | null = null): Promise<Json> {
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
  const claim = claudeClaim(await json(usage), key, kind);
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
