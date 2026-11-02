// How much of a profile's allowance is used, where the provider says (the Rust station's quota.rs):
// - OpenCode Go: GET /zen/go/v1/usage (rolling, weekly and monthly windows);
// - Kimi Code (its key, or a Kimi sign-in's current token): GET /coding/v1/usages (the week, and shorter windows), as
//   kimi-cli's /usage reads it;
// - ChatGPT subscription (Codex): the app-server's account/rateLimits/read;
// - Claude subscription: Claude Code's OAuth usage endpoint (what /usage shows), with the token Claude Code keeps in the
//   profile's home (renewed first when about to run out, and once more when the provider says it is not good: oauth.ts);
// - Anthropic API keys and other providers bill per use and have no allowance to show.
import { spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { platform } from "../platform/index.ts";
import { codexAuthFile, type Env } from "../agents/machine-logins.ts";
import type { Profile } from "../sessions/config.ts";
import { accessKind, KIMI_CODE, kimiSignedIn } from "../agents/profiles.ts";
import { readKimi } from "./kimi.ts";
import { type Lang, stationLang, tr } from "../ops/i18n.ts";
import { claudeOAuthToken } from "./oauth.ts";
import { RenewRefused } from "./console.ts";
import { type ProfileQuota, type QuotaWindow, URLS, type Urls } from "./profiles.ts";
import { profileFetch } from "../ops/agent-env.ts";

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

const get = (url: string, headers: Record<string, string>) => profileFetch(url, { headers, signal: AbortSignal.timeout(TIMEOUT_MS) });

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
  const q = withCodexCredits(okOrUnavailable(codexWindows(result), tr(lang, "station.quota.chatgptNoWindows")), limits, result?.rateLimitResetCredits);
  if (typeof limits?.planType === "string" && limits.planType.trim() !== "") q.plan = limits.planType.trim();
  return q;
}

/// Reaches a profile's codex app-server for its account/rateLimits/read.
export type CodexRateLimits = (profile: Profile) => Promise<Json>;

/// A socket's errors where the provider was not reached (through a proxy, https.request says them as they are).
const UNREACHED = new Set(["ECONNREFUSED", "ECONNRESET", "ECONNABORTED", "ENOTFOUND", "EAI_AGAIN", "ETIMEDOUT", "EHOSTUNREACH", "ENETUNREACH", "EPIPE"]);

/// Whether a request to the provider got no answer at all: no way there (fetch's "fetch failed", a socket's error)
/// or none in time.
function unanswered(error: unknown): boolean {
  if (!(error instanceof Error)) return false;
  return error.name === "TimeoutError" || (error instanceof TypeError && error.message === "fetch failed") || UNREACHED.has(String((error as NodeJS.ErrnoException).code));
}

function failed(error: unknown, lang: Lang): ProfileQuota {
  // One that never reached the provider said in words, not as Node says it.
  if (unanswered(error)) return quota("unavailable", [], tr(lang, "station.quota.unreachable"));
  const detail = error instanceof Error ? error.message : String(error);
  // Its login over: its profile is checked again, to say so (Accounts).
  if (error instanceof RenewRefused) return { ...quota("unavailable", [], detail), signedOut: true };
  return quota(blocked(detail) ? "blocked" : "unavailable", [], detail);
}

/// Asks the provider. `codexRateLimits` reaches the profile's codex app-server; `env` is the station's (for a machine
/// profile's login). Never throws: what went wrong is an unavailable (or blocked) allowance.
export async function checkQuota(profile: Profile, env: Env, codexRateLimits: CodexRateLimits | undefined, urls: Urls = URLS, lang: Lang = stationLang()): Promise<ProfileQuota> {
  try {
    const kind = accessKind(profile);
    if (kind === "opencode-go") return await opencode(urls, String((profile.access as Json)?.key ?? "").trim(), lang);
    if (kind === "api-provider" && (profile.access as Json)?.provider === KIMI_CODE) {
      const key = kimiSignedIn(profile) ? (readKimi(profile.home)?.access ?? "") : String((profile.access as Json)?.key ?? "").trim();
      return await kimiQuota(urls, key, lang);
    }
    if (kind === "anthropic-api" || kind === "api-provider") return quota("unsupported", [], tr(lang, "station.quota.payAsYouGo"));
    if (kind === "env") return quota("unsupported", [], tr(lang, "station.quota.envUnsupported"));
    if (profile.runtime === "grok") return await grokQuota(profile, env, lang);
    // Cursor's API says no allowance of an account's plan to a key.
    if (profile.runtime === "cursor") return quota("unsupported", [], tr(lang, "station.quota.cursorUnsupported"));
    // Nor does the Devin CLI say its account's quota to a program (only its own /usage shows it).
    if (profile.runtime === "devin") return quota("unsupported", [], tr(lang, "station.quota.devinUnsupported"));
    if (profile.runtime === "claude") return await claudeWithRefresh(env, profile.machine === true ? null : profile.home, urls, lang);
    if (!codexRateLimits) throw new Error("no codex app-server to ask");
    return codexQuota(await codexRateLimits(profile), lang);
  } catch (e) {
    return failed(e, lang);
  }
}

/// Kimi Code's allowance: its answer's `usage` (the week) and `limits` (each with its window, 5 hours say), each as a
/// limit and what is used or left of it.
async function kimiQuota(urls: Urls, key: string, lang: Lang): Promise<ProfileQuota> {
  const response = await profileFetch(`${urls.kimiApi ?? KIMI_API}/usages`, { headers: { authorization: `Bearer ${key}`, accept: "application/json" }, signal: AbortSignal.timeout(TIMEOUT_MS) });
  if (!response.ok) return refused("Kimi Code ", response, lang);
  let body: Json;
  try {
    body = JSON.parse(await response.text());
  } catch {
    return quota("unavailable", [], tr(lang, "station.quota.kimiNoWindows"));
  }
  // An answer with no allowance in it at all (`{}`, as Kimi gives an account it tells none of) has nothing to show, as
  // a key billed per use; one with some that could not be read is unavailable.
  if (isObject(body) && body.usage == null && !(Array.isArray(body.limits) && body.limits.length > 0)) return quota("unsupported", [], tr(lang, "station.quota.kimiNone"));
  return okOrUnavailable(kimiWindows(body), tr(lang, "station.quota.kimiNoWindows"));
}

const KIMI_API = "https://api.kimi.com/coding/v1";

/// The windows of a Kimi Code usage answer.
export function kimiWindows(body: Json): QuotaWindow[] {
  const num = (v: unknown): number | null => (typeof v === "number" ? v : typeof v === "string" && v.trim() !== "" && Number.isFinite(Number(v)) ? Number(v) : null);
  const one = (d: Json, minutes: number | null, fallback: string): QuotaWindow | null => {
    const limit = num(d?.limit);
    if (limit === null || limit <= 0) return null;
    const used = num(d?.used) ?? (num(d?.remaining) !== null ? limit - num(d?.remaining)! : null);
    if (used === null) return null;
    const resetsAt = at(d?.resetTime ?? d?.reset_time ?? d?.resetAt ?? d?.reset_at);
    return { label: windowLabel(minutes, fallback), usedPercent: percent((used / limit) * 100), resetsAt, minutes };
  };
  const out: QuotaWindow[] = [];
  for (const item of Array.isArray(body?.limits) ? body.limits : []) {
    const window = isObject(item?.window) ? item.window : item;
    const duration = num(window?.duration);
    const unit = String(window?.timeUnit ?? "");
    const minutes = duration === null ? null : unit.includes("MINUTE") ? duration : unit.includes("HOUR") ? duration * 60 : unit.includes("DAY") ? duration * DAY_MINUTES : duration / 60;
    const w = one(isObject(item?.detail) ? item.detail : item, minutes, "限额");
    if (w) out.push(w);
  }
  const week = one(body?.usage, WEEK_MINUTES, "每周");
  if (week) out.push(week);
  return out;
}

/// A SuperGrok subscription's allowance: what Grok Build's own pages show (its `x.ai/billing`: the included credits
/// used of the current period), asked of a `grok agent stdio` started for it in the profile's Grok home.
async function grokQuota(profile: Profile, env: Env, lang: Lang): Promise<ProfileQuota> {
  const said = await grokBilling({ ...env, GROK_HOME: join(profile.home, "grok"), GROK_DISABLE_AUTOUPDATER: "1", GROK_TELEMETRY_ENABLED: "0" });
  return grokQuotaOf(said, lang);
}

/// The allowance in Grok Build's billing answer.
export function grokQuotaOf(said: Json, lang: Lang = stationLang()): ProfileQuota {
  const config = said?.config;
  const period = config?.currentPeriod;
  const plan = typeof said?.subscription_tier === "string" ? said.subscription_tier.trim() : "";
  // Its answer leaves zero out (proto3 JSON): a period with no percentage is one nothing of was used yet.
  const used = typeof config?.creditUsagePercent === "number" ? config.creditUsagePercent : isObject(period) ? 0 : null;
  if (used === null) return { ...quota("unavailable", [], tr(lang, "station.quota.grokNoWindows")), ...(plan !== "" ? { plan } : {}) };
  const start = at(period?.start ?? config?.billingPeriodStart);
  const end = at(period?.end ?? config?.billingPeriodEnd);
  const type = String(period?.type ?? "");
  const minutes = start !== null && end !== null && end > start ? (end - start) / 60_000 : type.includes("WEEKLY") ? WEEK_MINUTES : type.includes("MONTHLY") ? 30 * DAY_MINUTES : null;
  const window: QuotaWindow = { label: windowLabel(minutes, type.includes("WEEKLY") ? "每周" : "每月"), usedPercent: percent(used), resetsAt: end, minutes };
  const q = quota("ok", [window], typeof said?.subscription_tier === "string" ? said.subscription_tier : null);
  if (plan !== "") q.plan = plan;
  return q;
}

/// Asks a Grok Build started for it (ACP over stdio) for its billing: initialize, then `x.ai/billing`.
function grokBilling(env: Env): Promise<Json> {
  return new Promise((resolve, reject) => {
    const r = platform.runnable("grok", ["agent", "--no-leader", "stdio"], env as NodeJS.ProcessEnv);
    const child = spawn(r.file, r.args, { env: env as NodeJS.ProcessEnv, stdio: ["pipe", "pipe", "pipe"], windowsVerbatimArguments: r.windowsVerbatimArguments, windowsHide: true });
    let buffer = "";
    let stderr = "";
    let over = false;
    const done = (error: Error | null, value?: Json) => {
      if (over) return;
      over = true;
      child.kill("SIGKILL");
      if (error) reject(error);
      else resolve(value);
    };
    AbortSignal.timeout(30_000).addEventListener("abort", () => done(new Error("grok did not say its billing in time")));
    child.once("error", (e) => done(e));
    child.once("close", (code) => done(new Error(`grok exited (${code})${stderr.trim() === "" ? "" : `: ${stderr.trim().slice(-300)}`}`)));
    child.stderr?.on("data", (d: Buffer) => (stderr = (stderr + d.toString("utf8")).slice(-2000)));
    child.stdout?.on("data", (d: Buffer) => {
      buffer += d.toString("utf8");
      let i;
      while ((i = buffer.indexOf("\n")) >= 0) {
        const line = buffer.slice(0, i);
        buffer = buffer.slice(i + 1);
        let m: Json;
        try {
          m = JSON.parse(line);
        } catch {
          continue;
        }
        if (m?.id === "init") child.stdin?.write(`${JSON.stringify({ jsonrpc: "2.0", id: "billing", method: "_x.ai/billing", params: {} })}\n`);
        else if (m?.id === "billing") done(m.error !== undefined ? new Error(String(m.error?.message ?? JSON.stringify(m.error))) : null, m.result);
      }
    });
    child.stdin?.on("error", () => {});
    child.stdin?.write(`${JSON.stringify({ jsonrpc: "2.0", id: "init", method: "initialize", params: { protocolVersion: 1, clientCapabilities: {} } })}\n`);
  });
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
  const q = withCodexCredits(okOrUnavailable(windows, tr(lang, "station.quota.chatgptNoWindows")), body, body?.rate_limit_reset_credits);
  if (typeof body?.plan_type === "string" && body.plan_type.trim() !== "") q.plan = body.plan_type.trim();
  return q;
}

/// A borrowed Codex subscription's allowance, read with the login its host lent (kept in its home's auth.json) while that
/// has not run out: the same account's as the host reads, asked now. Null when there is no such login to read it with.
export async function lentCodexUsage(home: string, now: number, urls: Urls = URLS, lang: Lang = stationLang()): Promise<ProfileQuota | null> {
  const file = join(home, "auth.json");
  let expires = 0;
  try {
    const token = JSON.parse(readFileSync(file, "utf8"))?.tokens?.access_token;
    const claims = JSON.parse(Buffer.from(String(token).split(".")[1] ?? "", "base64url").toString("utf8"));
    if (typeof claims?.exp === "number") expires = claims.exp * 1000;
  } catch {
    return null;
  }
  return expires > now ? codexUsage(file, urls, lang) : null;
}

/// The allowance of the machine's own login of a runtime, read without starting anything of the station's. Null when
/// there is nothing to read it with.
export async function machineUsage(runtime: "claude" | "codex", env: Env, urls: Urls = URLS, lang: Lang = stationLang()): Promise<ProfileQuota | null> {
  try {
    return runtime === "codex" ? await codexUsage(codexAuthFile(env), urls, lang) : await claudeWithRefresh(env, null, urls, lang);
  } catch (e) {
    return failed(e, lang);
  }
}
