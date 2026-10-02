import { createRemoteJWKSet, EncryptJWT, jwtDecrypt, jwtVerify, SignJWT } from "jose";
import { adminOrigins, betaOrigin, publicOrigins } from "./compat";
import type { Env } from "./env";

export const ACCESS_TTL_SEC = 5 * 60;
export const SESSION_TTL_SEC = 30 * 24 * 60 * 60;
export const SESSION_IDLE_SEC = 7 * 24 * 60 * 60;
export const LOGIN_TTL_SEC = 10 * 60;
export const CODE_TTL_SEC = 60;
export const REFRESH_RETRY_SEC = 120;
// Existing sessions' tokens name it: it keeps its old name.
const ISSUER = "stillfail-cloud";
const ACCEPTED_ISSUERS = [ISSUER, "ember-cloud"];
const encoder = new TextEncoder();
const googleKeys = createRemoteJWKSet(new URL("https://www.googleapis.com/oauth2/v3/certs"));

/** A Google account. name and picture come from the profile scope and may be empty. */
export type Identity = { sub: string; email: string; name: string; picture: string };
export type Claims = { sub: string; email: string; name?: string; sid: string; exp: number; iat: number; gen?: number };
export type Tokens = {
  access_token: string;
  refresh_token: string;
  token_type: "Bearer";
  subject: string;
  email: string;
  name: string;
  session_id: string;
  expires_at: number;
  session_expires_at: number;
  refresh_expires_at: number;
};

export const nowSeconds = () => Math.floor(Date.now() / 1000);
export const randomSecret = () => b64url(crypto.getRandomValues(new Uint8Array(32)));
export const b64url = (value: Uint8Array) =>
  btoa(String.fromCharCode(...value))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
export const digest = async (value: string) => b64url(new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(value))));
export const validSecret = (value: unknown): value is string => typeof value === "string" && /^[A-Za-z0-9_-]{43}$/.test(value);
export const validId = (value: unknown): value is string => typeof value === "string" && /^[0-7][0-9A-HJKMNP-TV-Z]{25}$/.test(value);

/** The Android app's callbacks: the app registers this scheme and host for the Custom Tab to return to (apps from before the rename, ember://). */
// The beta apps (fail.still.android.beta, fail.still.desktop.beta: 「youdid.wtf」) come back on a scheme of their own.
export const APP_REDIRECTS = ["stillfail://auth/callback", "ember://auth/callback", "stillfail-beta://auth/callback"];

/**
 * Where a login may return: the web app's own callback on one of its origins
 * (the test channel's included), the admin console's on one of its, the native
 * app's callback, or a loopback listener of a command-line client.
 */
export function validRedirect(env: Env, value: string): boolean {
  const beta = betaOrigin(env);
  if ([...publicOrigins(env), ...adminOrigins(env), ...(beta ? [beta] : [])].some((origin) => value === `${origin}/auth/callback`) || APP_REDIRECTS.includes(value)) return true;
  try {
    const url = new URL(value);
    return url.protocol === "http:" && url.hostname === "127.0.0.1" && Number(url.port) > 0 && url.pathname === "/oauth/callback" && !url.username && !url.password && !url.search && !url.hash;
  } catch {
    return false;
  }
}

export function bearerToken(request: Request): string | null {
  const match = /^Bearer ([A-Za-z0-9._-]{1,4096})$/i.exec(request.headers.get("authorization") ?? "");
  return match?.[1] ?? null;
}

export function authConfigured(env: Env): boolean {
  return Boolean(env.GOOGLE_CLIENT_ID && env.GOOGLE_CLIENT_SECRET && env.AUTH_SIGNING_KEY?.length >= 43 && env.PUBLIC_ORIGIN);
}

export function reply(body: unknown, status = 200, headers: HeadersInit = {}): Response {
  return Response.json(body, {
    status,
    headers: { "cache-control": "no-store", "referrer-policy": "no-referrer", ...headers },
  });
}
export const denied = () => reply({ error: "invalid_session" }, 401);
export const limited = (seconds = 60) => reply({ error: "rate_limited" }, 429, { "retry-after": String(seconds) });

export async function readText(request: Request, maximum = 8192): Promise<string> {
  const reader = request.body?.getReader();
  if (!reader) throw new Error("body_required");
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > maximum) {
        await reader.cancel();
        throw new Error("body_too_large");
      }
      chunks.push(value);
    }
    const bytes = new Uint8Array(length);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.byteLength;
    }
    return new TextDecoder().decode(bytes);
  } finally {
    reader.releaseLock();
  }
}

export async function readJson(request: Request): Promise<Record<string, unknown>> {
  if (request.headers.get("content-type")?.split(";")[0] !== "application/json") throw new Error("content_type");
  const body = JSON.parse(await readText(request));
  if (!body || typeof body !== "object" || Array.isArray(body)) throw new Error("invalid_body");
  return body;
}

export async function signToken(env: Env, type: "access" | "refresh", claims: Record<string, unknown>, expires: number, issued = nowSeconds()): Promise<string> {
  return new SignJWT({ ...claims, type }).setProtectedHeader({ alg: "HS256", typ: "JWT" }).setIssuer(ISSUER).setAudience(env.PUBLIC_ORIGIN).setIssuedAt(issued).setExpirationTime(expires).sign(encoder.encode(env.AUTH_SIGNING_KEY));
}

export async function verifyToken(env: Env, token: string, type: "access" | "refresh"): Promise<Claims | null> {
  try {
    if (!env.AUTH_SIGNING_KEY || token.length > 4096) return null;
    const { payload } = await jwtVerify(token, encoder.encode(env.AUTH_SIGNING_KEY), {
      algorithms: ["HS256"],
      typ: "JWT",
      issuer: ACCEPTED_ISSUERS,
      // Tokens signed before the move name the old origin.
      audience: publicOrigins(env),
      requiredClaims: ["sub", "sid", "iat", "exp", "type"],
    });
    if (
      payload.type !== type ||
      typeof payload.sub !== "string" ||
      !/^[A-Za-z0-9_-]{1,128}$/.test(payload.sub) ||
      !validId(payload.sid) ||
      typeof payload.iat !== "number" ||
      payload.iat > nowSeconds() ||
      typeof payload.exp !== "number" ||
      typeof payload.email !== "string" ||
      (payload.name !== undefined && typeof payload.name !== "string") ||
      (type === "access" && payload.exp - payload.iat > ACCESS_TTL_SEC) ||
      (type === "refresh" && (!Number.isSafeInteger(payload.gen) || !validSecret(payload.nonce)))
    )
      return null;
    return payload as Claims;
  } catch {
    return null;
  }
}

// An interrupted rotation can return exactly the same credentials; refresh
// secrets are hashed, with only a short-lived encrypted retry response retained.
// (The key's label keeps its old name: a retry sealed before a deploy still opens after it.)
async function encryptionKey(env: Env) {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(`ember-refresh-retry\0${env.AUTH_SIGNING_KEY}`)));
}
export async function seal(env: Env, value: Tokens): Promise<string> {
  return new EncryptJWT({ value })
    .setProtectedHeader({ alg: "dir", enc: "A256GCM" })
    .setExpirationTime(nowSeconds() + REFRESH_RETRY_SEC)
    .encrypt(await encryptionKey(env));
}
export async function unseal(env: Env, value: string): Promise<Tokens> {
  const { payload } = await jwtDecrypt(value, await encryptionKey(env), {
    keyManagementAlgorithms: ["dir"],
    contentEncryptionAlgorithms: ["A256GCM"],
  });
  return payload.value as Tokens;
}

/** `origin`: the one Google called back to, whose callback the login gave Google (PUBLIC_ORIGIN's, or an old one's for a login started before the move). */
export async function googleIdentity(env: Env, code: string, verifier: string, nonce: string, origin = env.PUBLIC_ORIGIN): Promise<Identity> {
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    redirect: "manual",
    signal: AbortSignal.timeout(10_000),
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      code,
      client_id: env.GOOGLE_CLIENT_ID,
      client_secret: env.GOOGLE_CLIENT_SECRET,
      redirect_uri: `${origin}/v1/auth/google/callback`,
      grant_type: "authorization_code",
      code_verifier: verifier,
    }),
  });
  if (!response.ok) throw new Error("google_exchange_failed");
  const tokens = (await response.json()) as { id_token?: string };
  if (!tokens.id_token) throw new Error("google_identity_missing");
  const { payload } = await jwtVerify(tokens.id_token, googleKeys, {
    algorithms: ["RS256"],
    issuer: ["https://accounts.google.com", "accounts.google.com"],
    audience: env.GOOGLE_CLIENT_ID,
    requiredClaims: ["sub", "exp", "iat", "nonce", "email", "email_verified"],
  });
  if (
    payload.nonce !== nonce ||
    payload.email_verified !== true ||
    typeof payload.email !== "string" ||
    typeof payload.sub !== "string" ||
    !/^[A-Za-z0-9_-]{1,128}$/.test(payload.sub) ||
    typeof payload.iat !== "number" ||
    payload.iat > nowSeconds() + 30 ||
    (payload.azp !== undefined && payload.azp !== env.GOOGLE_CLIENT_ID)
  )
    throw new Error("google_identity_mismatch");
  const text = (value: unknown, max: number) => (typeof value === "string" ? value.slice(0, max) : "");
  return { sub: payload.sub, email: payload.email, name: text(payload.name, 120), picture: /^https:\/\//.test(text(payload.picture, 1024)) ? text(payload.picture, 1024) : "" };
}
