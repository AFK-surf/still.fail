// A Cursor profile signed in with the person's Cursor account: the browser login Cursor's CLI and SDK use (a page at
// cursor.com/loginDeepControl given a one-time challenge, the station asking Cursor's backend until the page is
// confirmed), then, once, the login's session token mints a user API key and is dropped. The key is what the SDK runs on
// (agents/cursor.ts), kept in the profile's home (cursor/auth.json); the person sees it, named for the station, in their
// Cursor dashboard's API keys and can revoke it there. Unlike the SDK's own login (90 days), it is minted without an
// end: signed in once, the station stays signed in.
import { createHash, randomBytes, randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { writePrivate } from "../ops/files.ts";
import { profileFetch } from "../ops/agent-env.ts";
import { cursorHome } from "../agents/cursor.ts";

type Json = any;

/// Where Cursor is: its site (the login page) and its backends (the login's poll and the dashboard's calls; the API a key
/// is asked about). Tests give fake ones.
export type CursorUrls = { website: string; backend: string; api: string };
export const CURSOR: CursorUrls = { website: "https://cursor.com", backend: "https://api2.cursor.sh", api: "https://api.cursor.com" };

/// What a sign-in leaves in the profile's home.
export type CursorLogin = { apiKey: string; email: string | null; keyName: string; createdAt: number };

export const authFile = (home: string) => join(cursorHome(home), "auth.json");

export function readCursor(home: string): CursorLogin | null {
  try {
    return cursorIn(readFileSync(authFile(home), "utf8"));
  } catch {
    return null;
  }
}

/// What a sign-in's file says (`readCursor`).
export function cursorIn(text: string): CursorLogin | null {
  const j: Json = JSON.parse(text);
  if (typeof j?.apiKey !== "string" || j.apiKey === "") return null;
  return { apiKey: j.apiKey, email: typeof j.email === "string" && j.email !== "" ? j.email : null, keyName: typeof j.keyName === "string" ? j.keyName : "", createdAt: typeof j.createdAt === "number" ? j.createdAt : 0 };
}

export const writeCursor = (home: string, login: CursorLogin) => writePrivate(authFile(home), `${JSON.stringify(login, null, 2)}\n`);

const base64url = (b: Buffer) => b.toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

/// A sign-in to make: the page to confirm it on, and what only this station holds to redeem it (`verifier`).
export type CursorHandshake = { uuid: string; verifier: string; url: string };

export function cursorHandshake(urls: CursorUrls = CURSOR): CursorHandshake {
  const verifier = base64url(randomBytes(32));
  const challenge = base64url(createHash("sha256").update(verifier).digest());
  const uuid = randomUUID();
  return { uuid, verifier, url: `${urls.website}/loginDeepControl?challenge=${challenge}&uuid=${uuid}&mode=login&redirectTarget=cli` };
}

/// Whether the page was confirmed: the login's tokens, or still waiting (`pending`).
export async function pollCursor(urls: CursorUrls, handshake: CursorHandshake): Promise<{ accessToken: string } | { pending: true }> {
  // The verifier in the body, not the address (it would redeem the login from a log).
  const response = await profileFetch(`${urls.backend}/auth/poll`, {
    method: "POST",
    headers: { accept: "application/json", "content-type": "application/json" },
    body: JSON.stringify({ uuid: handshake.uuid, verifier: handshake.verifier }),
    signal: AbortSignal.timeout(20_000),
  });
  if (response.status === 404) return { pending: true };
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  const body: Json = await response.json();
  if (typeof body?.accessToken !== "string") throw new Error("Cursor gave no login");
  return { accessToken: body.accessToken };
}

/// One of Cursor's dashboard calls (Connect, its JSON form) with the login's session token.
async function dashboard(urls: CursorUrls, method: string, accessToken: string, body: Json): Promise<Json> {
  const response = await profileFetch(`${urls.backend}/aiserver.v1.DashboardService/${method}`, {
    method: "POST",
    headers: { authorization: `Bearer ${accessToken}`, "content-type": "application/json", "connect-protocol-version": "1" },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(20_000),
  });
  const text = await response.text();
  if (!response.ok) {
    let said = text;
    try {
      said = JSON.parse(text)?.message ?? text;
    } catch {}
    throw new Error(`${method}: HTTP ${response.status}${said ? `: ${String(said).slice(0, 300)}` : ""}`);
  }
  return JSON.parse(text);
}

/// The key the login mints (no end set: it lasts until revoked), and whose account it is.
export async function mintCursorKey(urls: CursorUrls, accessToken: string, name: string): Promise<{ apiKey: string; email: string | null }> {
  const made = await dashboard(urls, "CreateUserApiKey", accessToken, { name });
  if (typeof made?.apiKey !== "string" || made.apiKey === "") throw new Error("Cursor minted no key");
  const me: Json = await dashboard(urls, "GetMe", accessToken, {}).catch(() => null);
  const email = typeof me?.email === "string" && me.email !== "" ? me.email : null;
  return { apiKey: made.apiKey, email };
}

/// Whose a key is, as Cursor's API says (null: it refused the key; an error: it could not be asked).
export async function cursorMe(urls: CursorUrls, apiKey: string): Promise<{ email: string | null; keyName: string } | null> {
  const response = await profileFetch(`${urls.api}/v1/me`, { headers: { authorization: `Basic ${Buffer.from(`${apiKey}:`).toString("base64")}`, accept: "application/json" }, signal: AbortSignal.timeout(15_000) });
  if (response.status === 401 || response.status === 403) return null;
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  const body: Json = await response.json();
  return { email: typeof body?.userEmail === "string" && body.userEmail !== "" ? body.userEmail : null, keyName: typeof body?.apiKeyName === "string" ? body.apiKeyName : "" };
}

/// The models a key may run, as Cursor's API lists them (null where it does not say).
export async function cursorModels(urls: CursorUrls, apiKey: string): Promise<string[] | null> {
  try {
    const response = await profileFetch(`${urls.api}/v1/models`, { headers: { authorization: `Basic ${Buffer.from(`${apiKey}:`).toString("base64")}`, accept: "application/json" }, signal: AbortSignal.timeout(20_000) });
    if (!response.ok) return null;
    const body: Json = await response.json();
    const list: Json[] = Array.isArray(body) ? body : Array.isArray(body?.models) ? body.models : Array.isArray(body?.items) ? body.items : [];
    const ids = list.map((m) => (typeof m === "string" ? m : m?.id)).filter((id): id is string => typeof id === "string" && id !== "");
    return ids.length > 0 ? ids : null;
  } catch {
    return null;
  }
}
