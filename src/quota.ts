// How much of a profile's allowance is used, where the provider says:
// - OpenCode Go: GET /zen/go/v1/usage (rolling, weekly and monthly windows);
// - ChatGPT subscription (Codex): the app-server's account/rateLimits/read;
// - Claude subscription: Claude Code's OAuth usage endpoint (what /usage shows),
//   with the token Claude Code keeps for that config directory;
// - Anthropic API keys bill per use and have no allowance to show.
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { codexAuthFile, machineClaudeToken } from "./machine-logins.ts";
import type { Profile } from "./config.ts";

export interface QuotaWindow {
  label: string;
  /** 0–100. */
  usedPercent: number;
  /** Epoch ms; null when the provider does not say. */
  resetsAt: number | null;
}

export interface ProfileQuota {
  /**
   * ok: windows filled; unsupported: nothing to show for this kind; unavailable: could not ask; blocked: the provider
   * refuses the account (suspended, on hold, deactivated).
   */
  state: "ok" | "unsupported" | "unavailable" | "blocked";
  windows: QuotaWindow[];
  detail: string | null;
  checkedAt: number;
}

const OPENCODE = "https://opencode.ai/zen/go";

const at = (value: unknown): number | null => {
  if (typeof value === "number") return value > 1e12 ? value : value * 1000;
  if (typeof value === "string" && value) {
    const ms = Date.parse(value);
    return Number.isNaN(ms) ? null : ms;
  }
  return null;
};
const percent = (value: unknown): number => Math.max(0, Math.min(100, Math.round(Number(value) || 0)));

function windowLabel(minutes: number | undefined, fallback: string): string {
  if (!minutes) return fallback;
  if (minutes <= 60 * 6) return `${Math.round(minutes / 60)} 小时`;
  if (minutes >= 60 * 24 * 6 && minutes <= 60 * 24 * 8) return "每周";
  if (minutes >= 60 * 24 * 27) return "每月";
  return `${Math.round(minutes / 60 / 24)} 天`;
}

async function opencode(key: string): Promise<ProfileQuota> {
  const response = await fetch(`${OPENCODE}/v1/usage`, { headers: { authorization: `Bearer ${key}` }, signal: AbortSignal.timeout(15_000) });
  if (!response.ok) throw new Error(`OpenCode Go 返回 ${response.status}`);
  const usage = ((await response.json()) as { usage?: Record<string, { percent?: number; resetsAt?: string }> }).usage ?? {};
  const labels: Record<string, string> = { rolling: "5 小时", weekly: "每周", monthly: "每月" };
  const windows = Object.entries(usage).map(([k, w]) => ({ label: labels[k] ?? k, usedPercent: percent(w.percent), resetsAt: at(w.resetsAt) }));
  return { state: "ok", windows, detail: null, checkedAt: Date.now() };
}

/** The OAuth token Claude Code keeps for this config directory, in its credentials file (no-keychain.ts). */
export async function claudeToken(home: string): Promise<string | null> {
  try {
    const text = await readFile(join(home, ".credentials.json"), "utf8");
    return (JSON.parse(text) as { claudeAiOauth?: { accessToken?: string } }).claudeAiOauth?.accessToken ?? null;
  } catch {
    return null;
  }
}

/** What a provider says when it refuses an account itself, not a token or a request. */
export const BLOCKED = /on hold|restricted|suspend|disabled|deactivat|banned|terminated|violat/i;

/** A provider's refusal as a quota: the account refused (blocked), or its sign-in no longer good. */
async function refused(provider: string, response: Response): Promise<ProfileQuota> {
  const text = (await response.text().catch(() => "")).slice(0, 500);
  const now = Date.now();
  if (BLOCKED.test(text) || response.status === 403) return { state: "blocked", windows: [], detail: `${provider}拒绝了这个账号（${response.status}）${message(text)}`, checkedAt: now };
  if (response.status === 401) return { state: "unavailable", windows: [], detail: "登录过期或失效了", checkedAt: now };
  return { state: "unavailable", windows: [], detail: `${provider}返回 ${response.status}`, checkedAt: now };
}

/** A provider's error body, in a line when it has one. */
function message(text: string): string {
  try {
    const body = JSON.parse(text) as { error?: { message?: string } | string; detail?: string; message?: string };
    const said = typeof body.error === "string" ? body.error : body.error?.message ?? body.detail ?? body.message;
    return said ? `：${String(said).slice(0, 200)}` : "";
  } catch {
    return "";
  }
}

async function claude(profile: Profile): Promise<ProfileQuota> {
  const token = profile.machine ? (await machineClaudeToken()).token : await claudeToken(profile.home);
  if (!token) return { state: "unavailable", windows: [], detail: "没找到这个账号的登录凭据，登录后才能查额度", checkedAt: Date.now() };
  return claudeUsage(token);
}

/** A Claude subscription's allowance, by its access token: what /usage shows. */
export async function claudeUsage(token: string): Promise<ProfileQuota> {
  const response = await fetch("https://api.anthropic.com/api/oauth/usage", {
    headers: { authorization: `Bearer ${token}`, "anthropic-beta": "oauth-2025-04-20" },
    signal: AbortSignal.timeout(15_000),
  });
  if (!response.ok) return refused("Anthropic ", response);
  const data = (await response.json()) as Record<string, { utilization?: number; resets_at?: string } | null>;
  const labels: Record<string, string> = { five_hour: "5 小时", seven_day: "每周", seven_day_opus: "每周 · Opus", seven_day_sonnet: "每周 · Sonnet" };
  const windows = Object.entries(data)
    .filter(([k, w]) => w && typeof w === "object" && k in labels)
    .map(([k, w]) => ({ label: labels[k]!, usedPercent: percent(w!.utilization), resetsAt: at(w!.resets_at) }));
  return { state: "ok", windows, detail: null, checkedAt: Date.now() };
}

function codexWindows(result: unknown): QuotaWindow[] {
  const limits = (result as { rateLimits?: Record<string, unknown> } | null)?.rateLimits ?? (result as Record<string, unknown> | null) ?? {};
  const windows: QuotaWindow[] = [];
  for (const [key, fallback] of [["primary", "5 小时"], ["secondary", "每周"]] as const) {
    const w = limits[key] as { usedPercent?: number; windowDurationMins?: number; resetsAt?: number | string } | null | undefined;
    if (w && typeof w === "object") windows.push({ label: windowLabel(w.windowDurationMins, fallback), usedPercent: percent(w.usedPercent), resetsAt: at(w.resetsAt) });
  }
  return windows;
}

/** Asks the provider. `codexRateLimits` reaches the profile's codex app-server. */
export async function checkQuota(profile: Profile, codexRateLimits: (profile: Profile) => Promise<unknown>): Promise<ProfileQuota> {
  const unsupported = (detail: string): ProfileQuota => ({ state: "unsupported", windows: [], detail, checkedAt: Date.now() });
  try {
    switch (profile.access.kind) {
      case "opencode-go":
        return await opencode(profile.access.key);
      case "anthropic-api":
        return unsupported("按量计费，没有额度上限");
      case "env":
        return unsupported("自定义环境变量的账号查不了额度");
      case "subscription":
        if (profile.runtime === "claude") return await claude(profile);
        {
          const windows = codexWindows(await codexRateLimits(profile));
          return windows.length
            ? { state: "ok", windows, detail: null, checkedAt: Date.now() }
            : { state: "unavailable", windows: [], detail: "ChatGPT 没有返回额度信息", checkedAt: Date.now() };
        }
    }
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    return { state: BLOCKED.test(detail) ? "blocked" : "unavailable", windows: [], detail, checkedAt: Date.now() };
  }
}

/**
 * A ChatGPT subscription's allowance read with the tokens of a Codex auth.json (the machine's own login, which no
 * app-server of ember's runs on until a profile uses it): what Codex's /status shows, from the same endpoint.
 */
export async function codexUsage(authFile: string): Promise<ProfileQuota | null> {
  let tokens: { access_token?: string; account_id?: string } | undefined;
  try {
    tokens = (JSON.parse(await readFile(authFile, "utf8")) as { tokens?: typeof tokens }).tokens;
  } catch {
    return null;
  }
  if (!tokens?.access_token) return null;
  const response = await fetch("https://chatgpt.com/backend-api/wham/usage", {
    headers: { authorization: `Bearer ${tokens.access_token}`, ...(tokens.account_id ? { "chatgpt-account-id": tokens.account_id } : {}), "user-agent": "codex_cli_rs" },
    signal: AbortSignal.timeout(15_000),
  });
  if (!response.ok) return refused("ChatGPT ", response);
  const body = (await response.json()) as { rate_limit?: Record<string, { used_percent?: number; limit_window_seconds?: number; reset_at?: number } | null> | null };
  const windows: QuotaWindow[] = [];
  for (const [key, fallback] of [["primary_window", "5 小时"], ["secondary_window", "每周"]] as const) {
    const w = body.rate_limit?.[key];
    if (w) windows.push({ label: windowLabel(w.limit_window_seconds ? w.limit_window_seconds / 60 : undefined, fallback), usedPercent: percent(w.used_percent), resetsAt: at(w.reset_at) });
  }
  return windows.length
    ? { state: "ok", windows, detail: null, checkedAt: Date.now() }
    : { state: "unavailable", windows: [], detail: "ChatGPT 没有返回额度信息", checkedAt: Date.now() };
}

/** The allowance of the machine's own login of a runtime (machine-logins.ts), read without starting anything of ember's. */
export async function machineUsage(runtime: "claude" | "codex", env: NodeJS.ProcessEnv = process.env): Promise<ProfileQuota | null> {
  try {
    if (runtime === "codex") return await codexUsage(codexAuthFile(env));
    return await claudeUsage((await machineClaudeToken(env)).token);
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    return { state: BLOCKED.test(detail) ? "blocked" : "unavailable", windows: [], detail, checkedAt: Date.now() };
  }
}
