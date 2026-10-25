// An OpenCode Go profile signed in with the person's OpenCode Console account instead of a key: the Console's device
// authorization grant (RFC 8628), which OpenCode documents for other CLIs (opencode.ai/docs/console/api, "Device
// flow"). Its access token is taken by the Go gateway wherever a key is; it lasts 30 days, and is renewed with a
// refresh token that is spent when used (the access token before stops working at once). So:
// - the access token is the profile's key in config.json: the runtimes are given it as any OpenCode Go key, and a
//   station from before this reads it as one;
// - the refresh token, when the access token runs out and whose account it is are in the profile's home
//   (`CONSOLE_FILE`), never sent to another station but with the profile when it moves (share/index.ts);
// - only the station the profile is on renews it, days before it runs out (accounts/index.ts); copies of a shared one
//   get the new key as any edit.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { writePrivate } from "../ops/files.ts";
import { profileFetch } from "../ops/agent-env.ts";

type Json = any;

export const CONSOLE = "https://opencode.ai/console";
/// The file in a signed-in profile's home.
export const CONSOLE_FILE = "opencode-console.json";
/// The client the Console is told signs in (any id will do: it is shown on the page that approves it).
const CLIENT_ID = "still.fail";
const AGENT = "still.fail";

/// What a sign-in leaves in the profile's home. `expiresAt`: when `access` runs out (ms since the epoch).
export type ConsoleLogin = { access: string; refresh: string; expiresAt: number; org: string | null; email: string | null; workspace: string | null };

/// Where to sign in: the page with the code filled in, the code, how long it lasts and how often to ask.
export type Device = { deviceCode: string; userCode: string; url: string; expiresInMs: number; intervalMs: number };

/// The Console's answer for a device: still waiting (`slow_down`: asked too often), signed in, or refused.
export type DeviceAnswer = { pending: true; slowDown: boolean } | { token: Token } | { error: string };

export type Token = { access: string; refresh: string; expiresInMs: number; org: string | null };

/// The Console turned a refresh token down: the sign-in is over (signed out there, or spent elsewhere).
export class RenewRefused extends Error {
  readonly status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

export function readConsole(home: string): ConsoleLogin | null {
  try {
    return consoleIn(readFileSync(join(home, CONSOLE_FILE), "utf8"));
  } catch {
    return null;
  }
}

/// What a sign-in's file says (`readConsole`).
export function consoleIn(file: string): ConsoleLogin | null {
  try {
    const j: Json = JSON.parse(file);
    if (typeof j?.access !== "string" || typeof j?.refresh !== "string" || typeof j?.expiresAt !== "number") return null;
    const text = (v: unknown) => (typeof v === "string" && v !== "" ? v : null);
    return { access: j.access, refresh: j.refresh, expiresAt: j.expiresAt, org: text(j.org), email: text(j.email), workspace: text(j.workspace) };
  } catch {
    return null;
  }
}

export const writeConsole = (home: string, login: ConsoleLogin) => writePrivate(join(home, CONSOLE_FILE), `${JSON.stringify(login, null, 2)}\n`);

async function post(base: string, path: string, form: Record<string, string>): Promise<{ status: number; body: Json }> {
  const response = await profileFetch(`${base}${path}`, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded", accept: "application/json", "user-agent": AGENT },
    body: new URLSearchParams(form).toString(),
    signal: AbortSignal.timeout(20_000),
  });
  const text = await response.text();
  let body: Json = null;
  try {
    body = JSON.parse(text);
  } catch {}
  return { status: response.status, body };
}

const tokenOf = (body: Json): Token | null =>
  typeof body?.access_token === "string" && typeof body?.refresh_token === "string" && typeof body?.expires_in === "number"
    ? { access: body.access_token, refresh: body.refresh_token, expiresInMs: body.expires_in * 1000, org: typeof body.org_id === "string" ? body.org_id : null }
    : null;

/// What the Console says went wrong: its OAuth error, its tag, or the status.
const errorOf = (status: number, body: Json): string => (typeof body?.error === "string" ? body.error : typeof body?._tag === "string" ? body._tag : `HTTP ${status}`);

/// A code to sign in with, for one workspace (chosen on the Console's page).
export async function startDevice(base: string): Promise<Device> {
  const { status, body } = await post(base, "/auth/device/code", { client_id: CLIENT_ID, supports_org_scope: "true" });
  if (status !== 200 || typeof body?.device_code !== "string" || typeof body?.user_code !== "string" || typeof body?.verification_uri_complete !== "string") {
    throw new Error(errorOf(status, body));
  }
  // The page is given relative to the Console's site.
  const url = new URL(body.verification_uri_complete, new URL(base).origin).toString();
  const seconds = (v: unknown, fallback: number) => (typeof v === "number" && v >= 0 ? v : fallback);
  return { deviceCode: body.device_code, userCode: body.user_code, url, expiresInMs: seconds(body.expires_in, 600) * 1000, intervalMs: seconds(body.interval, 5) * 1000 };
}

/// Asks whether the code was approved.
export async function deviceToken(base: string, deviceCode: string): Promise<DeviceAnswer> {
  const { status, body } = await post(base, "/auth/device/token", { grant_type: "urn:ietf:params:oauth:grant-type:device_code", device_code: deviceCode, client_id: CLIENT_ID });
  const token = status === 200 ? tokenOf(body) : null;
  if (token) return { token };
  const error = errorOf(status, body);
  if (error === "authorization_pending" || error === "slow_down") return { pending: true, slowDown: error === "slow_down" };
  return { error };
}

/// A new access token for a refresh token (which is spent: the one returned replaces it).
export async function renewToken(base: string, refresh: string): Promise<Token> {
  const { status, body } = await post(base, "/auth/device/token", { grant_type: "refresh_token", refresh_token: refresh, client_id: CLIENT_ID });
  const token = status === 200 ? tokenOf(body) : null;
  if (token) return token;
  const error = errorOf(status, body);
  if (status === 400 || status === 401 || status === 403) throw new RenewRefused(status, error);
  throw new Error(error);
}

/// Whose account a token is and which workspace it is for, where the Console says (null where it does not).
export async function whoIs(base: string, access: string, org: string | null): Promise<{ email: string | null; workspace: string | null }> {
  const get = async (path: string): Promise<Json> => {
    try {
      const response = await profileFetch(`${base}${path}`, { headers: { authorization: `Bearer ${access}`, accept: "application/json", "user-agent": AGENT }, signal: AbortSignal.timeout(15_000) });
      return response.ok ? await response.json() : null;
    } catch {
      return null;
    }
  };
  const [user, orgs] = await Promise.all([get("/api/user"), get("/api/orgs")]);
  const found = Array.isArray(orgs) && org !== null ? orgs.find((o: Json) => o?.id === org) : undefined;
  return { email: typeof user?.email === "string" ? user.email : null, workspace: typeof found?.name === "string" ? found.name : null };
}
