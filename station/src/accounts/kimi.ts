// A Kimi Code profile signed in with the person's Kimi account instead of a key: Kimi Code's device authorization grant
// (RFC 8628), the one its own CLI signs in with (kimi-cli `kimi login`, its KLIP-14). Its access token lasts minutes
// (15 when this was written) and is renewed with a refresh token that is spent when used. So, unlike OpenCode's
// (console.ts), the token is never the profile's key in config.json:
// - the tokens are in the profile's home (`KIMI_FILE`), the current access token alone in `KIMI_TOKEN_FILE`;
// - the station renews it while it has less than half its life left, looked at every minute (accounts/index.ts);
// - Claude Code reads that file for its key (its `apiKeyHelper`, agents/claude.ts), again every minute and after a 401;
// - every request of the sign-in carries the device it was made on (X-Msh-Device-Id): Kimi renews a token only for it.
// It stays on the station it was signed in on (share/index.ts does not lend it).
import { readFileSync } from "node:fs";
import { arch, hostname, release, type } from "node:os";
import { join } from "node:path";
import { randomUUID } from "node:crypto";
import { writePrivate } from "../ops/files.ts";
import { profileFetch } from "../ops/agent-env.ts";
import { type Device, type DeviceAnswer, RenewRefused } from "./console.ts";

type Json = any;

export const KIMI_AUTH = "https://auth.kimi.com";
/// The files in a signed-in profile's home: the sign-in, and the access token alone (what Claude Code reads).
export const KIMI_FILE = "kimi-code.json";
export const KIMI_TOKEN_FILE = "kimi-code.token";
/// Kimi Code's public client (kimi-cli's): its device grant is offered to no other.
const CLIENT_ID = "17e5f671-d194-4dfb-9706-5516cb48c098";
const PLATFORM = "still.fail";

/// What a sign-in leaves in the profile's home. `expiresAt`: when `access` runs out (ms since the epoch); `lifeMs`: how
/// long it was given for (half of it left: renewed).
export type KimiLogin = { access: string; refresh: string; expiresAt: number; lifeMs: number; deviceId: string };

export type KimiToken = { access: string; refresh: string; expiresInMs: number };

export const newDeviceId = () => randomUUID().replaceAll("-", "");

/// Kimi asks each request of a sign-in which device it is, as kimi-cli says (only ASCII in headers).
export function kimiHeaders(deviceId: string): Record<string, string> {
  const ascii = (v: string) => v.replace(/[^\x20-\x7e]/g, "").trim() || "unknown";
  return {
    "X-Msh-Platform": PLATFORM,
    "X-Msh-Version": "1",
    "X-Msh-Device-Name": ascii(hostname()),
    "X-Msh-Device-Model": ascii(`${type()} ${arch()}`),
    "X-Msh-Os-Version": ascii(release()),
    "X-Msh-Device-Id": deviceId,
  };
}

export function readKimi(home: string): KimiLogin | null {
  try {
    const j: Json = JSON.parse(readFileSync(join(home, KIMI_FILE), "utf8"));
    const ok = typeof j?.access === "string" && typeof j?.refresh === "string" && typeof j?.expiresAt === "number" && typeof j?.deviceId === "string";
    return ok ? { access: j.access, refresh: j.refresh, expiresAt: j.expiresAt, lifeMs: typeof j.lifeMs === "number" ? j.lifeMs : 0, deviceId: j.deviceId } : null;
  } catch {
    return null;
  }
}

/// The sign-in written, then its access token for Claude Code (a reader between the two gets the one before, still valid).
export function writeKimi(home: string, login: KimiLogin) {
  writePrivate(join(home, KIMI_FILE), `${JSON.stringify(login, null, 2)}\n`);
  writePrivate(join(home, KIMI_TOKEN_FILE), login.access);
}

/// Whether a sign-in's token is to be renewed now: less than half its life left (at least 5 minutes, as kimi-cli).
export const kimiDue = (login: KimiLogin, now: number) => login.expiresAt - now < Math.max(5 * 60_000, login.lifeMs / 2);

async function post(base: string, path: string, form: Record<string, string>, deviceId: string): Promise<{ status: number; body: Json }> {
  const response = await profileFetch(`${base}${path}`, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded", accept: "application/json", ...kimiHeaders(deviceId) },
    body: new URLSearchParams({ client_id: CLIENT_ID, ...form }).toString(),
    signal: AbortSignal.timeout(20_000),
  });
  const text = await response.text();
  let body: Json = null;
  try {
    body = JSON.parse(text);
  } catch {}
  return { status: response.status, body };
}

const tokenOf = (body: Json): KimiToken | null =>
  typeof body?.access_token === "string" && typeof body?.refresh_token === "string"
    ? { access: body.access_token, refresh: body.refresh_token, expiresInMs: (typeof body.expires_in === "number" && body.expires_in > 0 ? body.expires_in : 900) * 1000 }
    : null;

const errorOf = (status: number, body: Json): string =>
  typeof body?.error === "string" ? body.error : typeof body?.message === "string" ? body.message : `HTTP ${status}`;

/// A code to sign in with, for the device `deviceId`.
export async function startKimiDevice(base: string, deviceId: string): Promise<Device> {
  const { status, body } = await post(base, "/api/oauth/device_authorization", {}, deviceId);
  if (status !== 200 || typeof body?.device_code !== "string" || typeof body?.user_code !== "string") throw new Error(errorOf(status, body));
  const url = typeof body.verification_uri_complete === "string" ? body.verification_uri_complete : String(body.verification_uri ?? "");
  const seconds = (v: unknown, fallback: number) => (typeof v === "number" && v >= 0 ? v : fallback);
  return { deviceCode: body.device_code, userCode: body.user_code, url, expiresInMs: seconds(body.expires_in, 600) * 1000, intervalMs: seconds(body.interval, 5) * 1000 };
}

/// Asks whether the code was approved.
export async function kimiDeviceToken(base: string, deviceCode: string, deviceId: string): Promise<DeviceAnswer> {
  const { status, body } = await post(base, "/api/oauth/token", { device_code: deviceCode, grant_type: "urn:ietf:params:oauth:grant-type:device_code" }, deviceId);
  const token = status === 200 ? tokenOf(body) : null;
  if (token) return { token: { ...token, org: null } };
  const error = errorOf(status, body);
  if (error === "authorization_pending" || error === "slow_down") return { pending: true, slowDown: error === "slow_down" };
  return { error };
}

/// A new access token for a refresh token (which is spent: the one returned replaces it).
export async function renewKimiToken(base: string, refresh: string, deviceId: string): Promise<KimiToken> {
  const { status, body } = await post(base, "/api/oauth/token", { grant_type: "refresh_token", refresh_token: refresh }, deviceId);
  const token = status === 200 ? tokenOf(body) : null;
  if (token) return token;
  const error = errorOf(status, body);
  if (status === 400 || status === 401 || status === 403) throw new RenewRefused(status, error);
  throw new Error(error);
}
