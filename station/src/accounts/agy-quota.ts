// An Antigravity CLI subscription's allowance (what `agy -p /usage --output-format json` reports: Gemini Models and
// Claude and GPT models, 5-hour and weekly windows), asked of `agy` in the profile's own files
// (ANTIGRAVITY_GEMINI_DIR=<home>/agy/.gemini; HOME=<home>/agy when its token is in a file, or the user's HOME when
// kept in the macOS login keychain) without reading or embedding OAuth client credentials in the station.
import { spawn } from "node:child_process";
import { mkdir } from "node:fs/promises";
import { devNull } from "node:os";
import { AGY_FILE_TOKENS, agyHome, agyTakeBack, geminiDir } from "../agents/agy.ts";
import { type Env, platform } from "../platform/index.ts";
import { type Lang, Said, stationLang, tr } from "../ops/i18n.ts";
import { withShellCommand } from "../ops/shell-path.ts";
import { RenewRefused } from "./console.ts";
import type { ProfileQuota, QuotaWindow, Urls } from "./profiles.ts";
import { at, okOrUnavailable, percent, windowLabel } from "./quota.ts";

type Json = any;

const TIMEOUT_MS = 30_000;
const DAY_MINUTES = 24 * 60;
const WEEK_MINUTES = 7 * DAY_MINUTES;
const SCRUBBED = [
  "GEMINI_API_KEY",
  "GOOGLE_API_KEY",
  "GOOGLE_GENAI_USE_VERTEXAI",
  "GOOGLE_APPLICATION_CREDENTIALS",
  "GOOGLE_CLOUD_PROJECT",
  "GOOGLE_CLOUD_LOCATION",
  "AGY_ADC_AUTH",
  "AGY_ACCOUNT",
  "SSH_CONNECTION",
];

const isObject = (v: unknown): v is Record<string, any> => v !== null && typeof v === "object" && !Array.isArray(v);

function groupMeta(groupName: string, bucketId: string): { suffix: string; scope?: string } {
  const id = bucketId.toLowerCase();
  const g = groupName.toLowerCase();
  if (id.startsWith("gemini-") || g.includes("gemini")) return { suffix: "Gemini", scope: "gemini" };
  if (id.startsWith("3p-") || g.includes("claude") || g.includes("gpt")) return { suffix: "Claude / GPT", scope: "3p" };
  return { suffix: groupName.trim() };
}

function windowDuration(rawWindow: string, bucketId: string): [number | null, string] {
  const w = rawWindow.trim().toLowerCase();
  const id = bucketId.trim().toLowerCase();
  const hours = /^(\d+)\s*h$/.exec(w) ?? /-(\d+)h$/.exec(id);
  if (hours) {
    const mins = Number(hours[1]) * 60;
    return [mins, windowLabel(mins, `${hours[1]} 小时`)];
  }
  if (w === "weekly" || id.endsWith("-weekly")) return [WEEK_MINUTES, "每周"];
  if (w === "monthly" || id.endsWith("-monthly")) return [30 * DAY_MINUTES, "每月"];
  if (w === "daily" || id.endsWith("-daily")) return [DAY_MINUTES, "1 天"];
  return [null, rawWindow.trim() || "限额"];
}

export function agyWindows(body: Json): QuotaWindow[] {
  const groups = Array.isArray(body?.command?.data?.groups)
    ? body.command.data.groups
    : Array.isArray(body?.quotaSummary?.groups)
      ? body.quotaSummary.groups
      : Array.isArray(body?.groups)
        ? body.groups
        : [];
  const multiGroup = groups.length > 1;
  const out: QuotaWindow[] = [];
  for (const group of groups) {
    const groupName = typeof group?.displayName === "string" ? group.displayName : typeof group?.name === "string" ? group.name : "";
    const buckets = Array.isArray(group?.buckets) ? group.buckets : [];
    for (const b of buckets) {
      if (!isObject(b)) continue;
      const frac = typeof b.remainingFraction === "number" ? b.remainingFraction : typeof b.remaining_fraction === "number" ? b.remaining_fraction : null;
      if (frac === null && b.disabled !== true) continue;
      const used = b.disabled === true ? 100 : percent((1 - frac!) * 100);
      const bucketId = typeof b.bucketId === "string" ? b.bucketId : typeof b.id === "string" ? b.id : "";
      const rawWin = typeof b.refreshWindowLabel === "string" ? b.refreshWindowLabel : typeof b.window === "string" ? b.window : "";
      const [minutes, base] = windowDuration(rawWin, bucketId);
      const { suffix, scope } = groupMeta(groupName, bucketId);
      const label = (multiGroup || scope !== undefined) && suffix !== "" ? `${base} · ${suffix}` : base;
      const resetsAt = at(b.resetTime ?? b.reset_time);
      out.push({ label, usedPercent: used, resetsAt, minutes, ...(scope !== undefined ? { scope } : {}) });
    }
  }
  return out;
}

export function agyScopeForModel(model: string | null | undefined): "gemini" | "3p" {
  if (typeof model !== "string" || model.trim() === "") return "gemini";
  const bare = (model.trim().toLowerCase().split("[")[0]?.split("/").pop() ?? "").split("@")[0]!;
  const m = bare.replace(/^(?:[a-z]+\.)+/, "");
  if (m.startsWith("gemini") || m.startsWith("gemma")) return "gemini";
  return "3p";
}

function networkFailure(text: string): boolean {
  const lower = text.toLowerCase();
  if (/\beof\b/.test(lower)) return true;
  return [
    "connection refused",
    "connection reset",
    "no such host",
    "i/o timeout",
    "context deadline exceeded",
    "tls handshake timeout",
    "network is unreachable",
    "no route to host",
    "temporary failure in name resolution",
  ].some((w) => lower.includes(w));
}

function authFailure(text: string): boolean {
  const lower = text.toLowerCase();
  return ["authentication required", "not logged into antigravity", "authentication expired", "couldn't sign in", "invalid_grant", "unauthenticated"].some((w) =>
    lower.includes(w),
  );
}

function runAgyUsage(command: string, env: Env, cwd: string): Promise<{ code: number | null; stdout: string; stderr: string; authPrompted: boolean }> {
  return new Promise((resolve, reject) => {
    const r = platform.runnable(command, ["--log-file", devNull, "-p", "/usage", "--output-format", "json"], env as NodeJS.ProcessEnv);
    const child = spawn(r.file, r.args, {
      cwd,
      env: env as NodeJS.ProcessEnv,
      stdio: ["ignore", "pipe", "pipe"],
      windowsVerbatimArguments: r.windowsVerbatimArguments,
      windowsHide: true,
    });
    let stdout = "";
    let stderr = "";
    let authPrompted = false;
    let settled = false;
    const done = (err: Error | null, code: number | null = null) => {
      if (settled) return;
      settled = true;
      try {
        child.kill("SIGKILL");
      } catch {}
      if (err) reject(err);
      else resolve({ code, stdout, stderr, authPrompted });
    };
    const abort = AbortSignal.timeout(TIMEOUT_MS);
    const onAbort = () => {
      const e = new Error("agy /usage timed out");
      e.name = "TimeoutError";
      done(e);
    };
    abort.addEventListener("abort", onAbort, { once: true });
    child.once("error", (e) => {
      abort.removeEventListener("abort", onAbort);
      done(e);
    });
    const checkPrompt = (chunk: string) => {
      if (!authPrompted && (chunk.includes("Authentication required.") || chunk.includes("Waiting for authentication"))) {
        authPrompted = true;
        abort.removeEventListener("abort", onAbort);
        done(null, 1);
      }
    };
    child.stdout?.on("data", (d: Buffer) => {
      const s = d.toString("utf8");
      stdout += s;
      checkPrompt(stdout);
    });
    child.stderr?.on("data", (d: Buffer) => {
      const s = d.toString("utf8");
      stderr = (stderr + s).slice(-4000);
      checkPrompt(stderr);
    });
    child.once("close", (code) => {
      abort.removeEventListener("abort", onAbort);
      done(null, code);
    });
  });
}

function parseJsonLine(stdout: string): Json | null {
  for (const line of stdout.trim().split(/\r?\n/).reverse()) {
    const trimmed = line.trim();
    if (!trimmed.startsWith("{")) continue;
    try {
      return JSON.parse(trimmed);
    } catch {}
  }
  return null;
}


export async function agyQuota(home: string, sourceEnv: Env, urls: Urls, lang: Lang = stationLang(), command = "agy"): Promise<ProfileQuota> {
  // Before sign-in (no token file in the profile's, none to take back from the keychain: agents/agy.ts `agyTakeBack`),
  // return signed out immediately without spawning `agy`.
  if (!(await agyTakeBack(home))) {
    throw new Said(tr(lang, "station.quota.signInExpired"));
  }
  const baseEnv: Record<string, string> = {};
  for (const [k, v] of Object.entries(sourceEnv)) {
    if (v !== undefined && !SCRUBBED.includes(k)) baseEnv[k] = v;
  }
  // HOME isolated to `<home>/agy` and the sign-in kept in the file alone (`AGY_FILE_TOKENS`), so `agy` reads only the
  // profile's token file, never the login keychain's item, which is the machine's last account.
  baseEnv.HOME = agyHome(home);
  if (platform.hasKeychain) Object.assign(baseEnv, AGY_FILE_TOKENS);
  baseEnv.ANTIGRAVITY_GEMINI_DIR = geminiDir(home);
  baseEnv.AGY_CLI_DISABLE_AUTO_UPDATE = "1";
  if (urls.agyQuota) baseEnv.CLOUD_CODE_URL = urls.agyQuota;
  const runEnv = await withShellCommand(command, baseEnv, sourceEnv);
  await mkdir(home, { recursive: true });
  const { code, stdout, stderr, authPrompted } = await runAgyUsage(command, runEnv, home);
  if (authPrompted) {
    throw new RenewRefused(401, tr(lang, "station.quota.signInExpired"));
  }
  const parsed = parseJsonLine(stdout);
  if (parsed !== null && parsed.status === "SUCCESS") {
    return okOrUnavailable(agyWindows(parsed), tr(lang, "station.quota.agyNoWindows"));
  }
  const detail = (typeof parsed?.error === "string" && parsed.error.trim() !== "" ? parsed.error.trim() : stderr.trim() || stdout.trim()).slice(0, 300);
  if (authFailure(detail)) {
    throw new RenewRefused(401, tr(lang, "station.quota.signInExpired"));
  }
  if (networkFailure(detail)) {
    const err: NodeJS.ErrnoException = new Error(detail || "agy /usage network error");
    err.code = "ECONNREFUSED";
    throw err;
  }
  const statusMatch = /\bHTTP\s+(429|5\d\d)\b|\bstatus(?:\s+code)?[:=\s]+(429|5\d\d)\b/i.exec(detail);
  if (statusMatch) {
    const status = Number(statusMatch[1] ?? statusMatch[2]);
    return {
      state: "unavailable",
      windows: [],
      detail: tr(lang, "station.quota.providerStatus", { provider: "Antigravity ", status }),
      checkedAt: 0,
      unanswered: true,
    };
  }
  throw new Error(detail !== "" ? detail : `agy exited (${code})`);
}
