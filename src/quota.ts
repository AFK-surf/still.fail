// How much of a profile's allowance is used, where the provider says:
// - OpenCode Go: GET /zen/go/v1/usage (rolling, weekly and monthly windows);
// - ChatGPT subscription (Codex): the app-server's account/rateLimits/read;
// - Claude subscription: Claude Code's OAuth usage endpoint (what /usage shows),
//   with the token Claude Code keeps for that config directory;
// - Anthropic API keys bill per use and have no allowance to show.
import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { promisify } from "node:util";
import { machineClaudeToken } from "./machine-logins.ts";
import type { Profile } from "./config.ts";

export interface QuotaWindow {
  label: string;
  /** 0–100. */
  usedPercent: number;
  /** Epoch ms; null when the provider does not say. */
  resetsAt: number | null;
}

export interface ProfileQuota {
  /** ok: windows filled; unsupported: nothing to show for this kind; unavailable: could not ask. */
  state: "ok" | "unsupported" | "unavailable";
  windows: QuotaWindow[];
  detail: string | null;
  checkedAt: number;
}

const OPENCODE = "https://opencode.ai/zen/go";
const run = promisify(execFile);

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

/** The OAuth token Claude Code keeps for this config directory: a credentials file, or the macOS keychain. */
async function claudeToken(home: string): Promise<string | null> {
  const fromJson = (text: string) => (JSON.parse(text) as { claudeAiOauth?: { accessToken?: string } }).claudeAiOauth?.accessToken ?? null;
  try {
    return fromJson(await readFile(join(home, ".credentials.json"), "utf8"));
  } catch {
    // not stored in a file
  }
  if (process.platform !== "darwin") return null;
  const suffix = createHash("sha256").update(home).digest("hex").slice(0, 8);
  for (const service of [`Claude Code-credentials-${suffix}`, "Claude Code-credentials"]) {
    try {
      const { stdout } = await run("security", ["find-generic-password", "-s", service, "-w"], { timeout: 5000 });
      const token = fromJson(stdout.trim());
      if (token) return token;
    } catch {
      // not this one
    }
  }
  return null;
}

async function claude(profile: Profile): Promise<ProfileQuota> {
  const token = profile.machine ? (await machineClaudeToken()).token : await claudeToken(profile.home);
  if (!token) return { state: "unavailable", windows: [], detail: "没找到这个账号的登录凭据，登录后才能查额度", checkedAt: Date.now() };
  const response = await fetch("https://api.anthropic.com/api/oauth/usage", {
    headers: { authorization: `Bearer ${token}`, "anthropic-beta": "oauth-2025-04-20" },
    signal: AbortSignal.timeout(15_000),
  });
  if (!response.ok) throw new Error(`Anthropic 返回 ${response.status}`);
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
    return { state: "unavailable", windows: [], detail: error instanceof Error ? error.message : String(error), checkedAt: Date.now() };
  }
}
