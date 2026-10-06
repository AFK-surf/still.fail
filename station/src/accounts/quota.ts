// How much of a profile's allowance is used, where the provider says (the Rust station's quota.rs):
// - OpenCode Go: GET /zen/go/v1/usage (rolling, weekly and monthly windows);
// - ChatGPT subscription (Codex): the app-server's account/rateLimits/read;
// - Claude subscription: Claude Code's OAuth usage endpoint (what /usage shows), with the token Claude Code keeps in the
//   profile's home (renewed first when about to run out, and once more when the provider says it is not good: oauth.ts);
// - Anthropic API keys and other providers bill per use and have no allowance to show.
import { readFileSync } from "node:fs";
import { codexAuthFile, type Env } from "../agents/machine-logins.ts";
import type { Profile } from "../sessions/config.ts";
import { accessKind } from "../agents/profiles.ts";
import { type Lang, stationLang, tr } from "../ops/i18n.ts";
import { claudeOAuthToken } from "./oauth.ts";
import { type ProfileQuota, type QuotaWindow, URLS, type Urls } from "./profiles.ts";

type Json = any;

const TIMEOUT_MS = 15_000;

/// `checkedAt`: stamped by whoever keeps it, on its clock (Accounts, MachineLogins).
const quota = (state: string, windows: QuotaWindow[], detail: string | null): ProfileQuota => ({ state, windows, detail, checkedAt: 0 });

const okOrUnavailable = (windows: QuotaWindow[], empty: string) => (windows.length === 0 ? quota("unavailable", [], empty) : quota("ok", windows, null));

/// transcript.rs parse_iso: an RFC 3339 time, as epoch ms.
function parseIso(text: string): number | null {
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/.test(text)) return null;
  const ms = Date.parse(text);
  return Number.isNaN(ms) ? null : ms;
}

/// A time as a provider gives it: epoch seconds or ms, or an ISO string.
export function at(value: unknown): number | null {
  if (typeof value === "number") return value > 1e12 ? Math.trunc(value) : Math.trunc(value * 1000);
  if (typeof value === "string" && value !== "") return parseIso(value);
  return null;
}

function percent(value: unknown): number {
  let n = 0;
  if (typeof value === "number") n = value;
  else if (typeof value === "string") {
    const parsed = Number(value.trim());
    n = value.trim() !== "" && Number.isFinite(parsed) ? parsed : 0;
  }
  // Rust's round: halves away from zero.
  const rounded = Math.sign(n) * Math.round(Math.abs(n));
  return Math.min(100, Math.max(0, rounded));
}

const DAY_MINUTES = 24 * 60;
const WEEK_MINUTES = 7 * DAY_MINUTES;

const roundHalfAway = (n: number) => Math.sign(n) * Math.round(Math.abs(n));

/// A window's label. Labels are not translated: cores read them (client/core-ts/src/format.ts `window_mark`).
export function windowLabel(minutes: number | null | undefined, fallback: string): string {
  if (typeof minutes !== "number" || !(minutes > 0)) return fallback;
  if (minutes <= 60 * 6) return `${roundHalfAway(minutes / 60)} 小时`;
  if (minutes >= 60 * 24 * 6 && minutes <= 60 * 24 * 8) return "每周";
  if (minutes >= 60 * 24 * 27) return "每月";
  return `${roundHalfAway(minutes / 60 / 24)} 天`;
}

/// Whether a provider's words refuse an account itself, not a token or a request.
export function blocked(text: string): boolean {
  const lower = text.toLowerCase();
  return ["on hold", "restricted", "suspend", "disabled", "deactivat", "banned", "terminated", "violat"].some((w) => lower.includes(w));
}

/// A provider's error body, in a line when it has one.
function message(text: string): string | undefined {
  let body: Json;
  try {
    body = JSON.parse(text);
  } catch {
    return undefined;
  }
  const error = body?.error;
  let said: unknown = typeof error === "string" ? error : error !== undefined && error !== null ? error?.message : undefined;
  if (typeof said !== "string") said = typeof body?.detail === "string" ? body.detail : typeof body?.message === "string" ? body.message : undefined;
  return typeof said === "string" ? [...said].slice(0, 200).join("") : undefined;
}

/// A provider's refusal as a quota: the account refused (blocked), or its sign-in no longer good.
async function refused(provider: string, response: Response, lang: Lang): Promise<ProfileQuota> {
  const status = response.status;
  let text = "";
  try {
    text = [...(await response.text())].slice(0, 500).join("");
  } catch {}
  if (blocked(text) || status === 403) {
    const said = message(text);
    const detail = said !== undefined ? tr(lang, "station.quota.refusedSaying", { provider, status, said }) : tr(lang, "station.quota.refused", { provider, status });
    return quota("blocked", [], detail);
  }
  if (status === 401) return quota("unavailable", [], tr(lang, "station.quota.signInExpired"));
  return quota("unavailable", [], tr(lang, "station.quota.providerStatus", { provider, status }));
}

const get = (url: string, headers: Record<string, string>) => fetch(url, { headers, signal: AbortSignal.timeout(TIMEOUT_MS) });

async function opencode(urls: Urls, key: string, lang: Lang): Promise<ProfileQuota> {
  const response = await get(`${urls.opencode}/v1/usage`, { authorization: `Bearer ${key}` });
  if (!response.ok) throw new Error(tr(lang, "station.quota.providerStatus", { provider: "OpenCode Go ", status: response.status }));
  const body: Json = await response.json();
  const usage = body?.usage;
  const labels: Record<string, string> = { rolling: "5 小时", weekly: "每周", monthly: "每月" };
  const lengths: Record<string, number> = { rolling: 300, weekly: WEEK_MINUTES, monthly: 30 * DAY_MINUTES };
  // In the order the provider gave them (serde_json keeps it).
  const windows: QuotaWindow[] =
    usage !== null && typeof usage === "object" && !Array.isArray(usage)
      ? Object.keys(usage).map((k) => ({ label: labels[k] ?? k, usedPercent: percent(usage[k]?.percent), resetsAt: at(usage[k]?.resetsAt), minutes: lengths[k] ?? null }))
      : [];
  return quota("ok", windows, null);
}

/// A Claude subscription's allowance with its token; asked again once with a renewed token when the provider says the
/// token is not good. `home`: the profile's (null: the machine's own login).
export async function claudeWithRefresh(env: Env, home: string | null, urls: Urls = URLS, lang: Lang = stationLang()): Promise<ProfileQuota> {
  const [token] = await claudeOAuthToken(env, home, null, urls.claudeToken, lang);
  const [first, unauthorized] = await claudeUsageResponse(urls.anthropic, token, lang);
  if (!unauthorized) return first;
  const [renewed] = await claudeOAuthToken(env, home, token, urls.claudeToken, lang);
  return (await claudeUsageResponse(urls.anthropic, renewed, lang))[0];
}

/// A Claude subscription's allowance, by its access token: what /usage shows.
export async function claudeUsage(base: string, token: string, lang: Lang = stationLang()): Promise<ProfileQuota> {
  return (await claudeUsageResponse(base, token, lang))[0];
}

async function claudeUsageResponse(base: string, token: string, lang: Lang): Promise<[ProfileQuota, boolean]> {
  const response = await get(`${base}/api/oauth/usage`, { authorization: `Bearer ${token}`, "anthropic-beta": "oauth-2025-04-20" });
  if (!response.ok) return [await refused("Anthropic ", response, lang), response.status === 401];
  const body: Json = await response.json();
  const labels: Record<string, string> = { five_hour: "5 小时", seven_day: "每周", seven_day_opus: "每周 · Opus", seven_day_sonnet: "每周 · Sonnet" };
  const windows: QuotaWindow[] =
    body !== null && typeof body === "object" && !Array.isArray(body)
      ? Object.keys(body)
          .filter((k) => body[k] !== null && typeof body[k] === "object" && !Array.isArray(body[k]) && labels[k] !== undefined)
          .map((k) => ({ label: labels[k]!, usedPercent: percent(body[k].utilization), resetsAt: at(body[k].resets_at), minutes: k === "five_hour" ? 300 : WEEK_MINUTES }))
      : [];
  return [quota("ok", windows, null), false];
}

const isObject = (v: unknown): v is Record<string, any> => v !== null && typeof v === "object" && !Array.isArray(v);

/// The windows of the app-server's account/rateLimits/read.
export function codexWindows(result: Json): QuotaWindow[] {
  const limits = isObject(result?.rateLimits) ? result.rateLimits : result;
  return (
    [
      ["primary", "5 小时"],
      ["secondary", "每周"],
    ] as const
  ).flatMap(([key, fallback]) => {
    const w = limits?.[key];
    if (!isObject(w)) return [];
    const minutes = typeof w.windowDurationMins === "number" && w.windowDurationMins > 0 ? w.windowDurationMins : key === "primary" ? 300 : WEEK_MINUTES;
    return [{ label: windowLabel(minutes, fallback), usedPercent: percent(w.usedPercent), resetsAt: at(w.resetsAt), minutes }];
  });
}

function withCodexCredits(q: ProfileQuota, limits: Json, resets: Json): ProfileQuota {
  const c = limits?.credits;
  if (isObject(c)) {
    const has = typeof c.hasCredits === "boolean" ? c.hasCredits : typeof c.has_credits === "boolean" ? c.has_credits : false;
    const balance = typeof c.balance === "string" ? c.balance : typeof c.balance === "number" ? String(c.balance) : null;
    q.credits = { hasCredits: has, unlimited: c.unlimited === true, balance };
  }
  const count = resets?.availableCount ?? resets?.available_count;
  if (Number.isInteger(count) && count >= 0) q.resetCount = count;
  if (q.credits !== undefined || q.resetCount !== undefined) {
    q.state = "ok";
    q.detail = null;
  }
  return q;
}

/// A ChatGPT subscription's allowance as the app-server reports it.
export function codexQuota(result: Json, lang: Lang = stationLang()): ProfileQuota {
  const limits = isObject(result?.rateLimits) ? result.rateLimits : result;
  return withCodexCredits(okOrUnavailable(codexWindows(result), tr(lang, "station.quota.chatgptNoWindows")), limits, result?.rateLimitResetCredits);
}

/// Reaches a profile's codex app-server for its account/rateLimits/read.
export type CodexRateLimits = (profile: Profile) => Promise<Json>;

function failed(error: unknown): ProfileQuota {
  const detail = error instanceof Error ? error.message : String(error);
  return quota(blocked(detail) ? "blocked" : "unavailable", [], detail);
}

/// Asks the provider. `codexRateLimits` reaches the profile's codex app-server; `env` is the station's (for a machine
/// profile's login). Never throws: what went wrong is an unavailable (or blocked) allowance.
export async function checkQuota(profile: Profile, env: Env, codexRateLimits: CodexRateLimits | undefined, urls: Urls = URLS, lang: Lang = stationLang()): Promise<ProfileQuota> {
  try {
    const kind = accessKind(profile);
    if (kind === "opencode-go") return await opencode(urls, String((profile.access as Json)?.key ?? "").trim(), lang);
    if (kind === "anthropic-api" || kind === "api-provider") return quota("unsupported", [], tr(lang, "station.quota.payAsYouGo"));
    if (kind === "env") return quota("unsupported", [], tr(lang, "station.quota.envUnsupported"));
    if (profile.runtime === "claude") return await claudeWithRefresh(env, profile.machine === true ? null : profile.home, urls, lang);
    if (!codexRateLimits) throw new Error("no codex app-server to ask");
    return codexQuota(await codexRateLimits(profile), lang);
  } catch (e) {
    return failed(e);
  }
}

/// A ChatGPT subscription's allowance read with the tokens of a Codex auth.json (the machine's own login, which no
/// app-server of the station's runs on): what Codex's /status shows. Null when there is no such file or token.
export async function codexUsage(authFile: string, urls: Urls = URLS, lang: Lang = stationLang()): Promise<ProfileQuota | null> {
  let tokens: Json;
  try {
    tokens = JSON.parse(readFileSync(authFile, "utf8"))?.tokens;
  } catch {
    return null;
  }
  const access = tokens?.access_token;
  if (typeof access !== "string" || access === "") return null;
  const headers: Record<string, string> = { authorization: `Bearer ${access}`, "user-agent": "codex_cli_rs" };
  if (typeof tokens.account_id === "string") headers["chatgpt-account-id"] = tokens.account_id;
  const response = await get(`${urls.chatgpt}/backend-api/wham/usage`, headers);
  if (!response.ok) return refused("ChatGPT ", response, lang);
  const body: Json = await response.json();
  const windows = (
    [
      ["primary_window", "5 小时"],
      ["secondary_window", "每周"],
    ] as const
  ).flatMap(([key, fallback]) => {
    const w = body?.rate_limit?.[key];
    if (!isObject(w)) return [];
    const seconds = typeof w.limit_window_seconds === "number" && w.limit_window_seconds > 0 ? w.limit_window_seconds : null;
    const minutes = seconds !== null ? seconds / 60 : key === "primary_window" ? 300 : WEEK_MINUTES;
    return [{ label: windowLabel(minutes, fallback), usedPercent: percent(w.used_percent), resetsAt: at(w.reset_at), minutes }];
  });
  return withCodexCredits(okOrUnavailable(windows, tr(lang, "station.quota.chatgptNoWindows")), body, body?.rate_limit_reset_credits);
}

/// The allowance of the machine's own login of a runtime, read without starting anything of the station's. Null when
/// there is nothing to read it with.
export async function machineUsage(runtime: "claude" | "codex", env: Env, urls: Urls = URLS, lang: Lang = stationLang()): Promise<ProfileQuota | null> {
  try {
    return runtime === "codex" ? await codexUsage(codexAuthFile(env), urls, lang) : await claudeWithRefresh(env, null, urls, lang);
  } catch (e) {
    return failed(e);
  }
}
