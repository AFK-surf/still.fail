import { createRemoteJWKSet, EncryptJWT, jwtDecrypt, jwtVerify, SignJWT } from "jose";
import { adminOrigins, betaOrigin, publicOrigins } from "./compat";
import type { Env } from "./env";

export const ACCESS_TTL_SEC = 5 * 60;
export const SESSION_TTL_SEC = 30 * 24 * 60 * 60;
export const SESSION_IDLE_SEC = 7 * 24 * 60 * 60;
export const LOGIN_TTL_SEC = 10 * 60;
export const CODE_TTL_SEC = 60;
export const REFRESH_RETRY_SEC = 120;
const ISSUER = "stillfail-cloud";
const ACCEPTED_ISSUERS = [ISSUER];
const encoder = new TextEncoder();

/** Where signing in goes for an identity (login.ts google, googleIdentity): Google, or the OpenID provider OIDC_ISSUER
 * names (a self-hosted cloud's, cloud/selfhost/README.md), found by its discovery document. */
export type Provider = { issuer: string; issuers: string[]; authorization: string; token: string; keys: ReturnType<typeof createRemoteJWKSet> };
const GOOGLE: Provider = {
  issuer: "https://accounts.google.com",
  issuers: ["https://accounts.google.com", "accounts.google.com"],
  authorization: "https://accounts.google.com/o/oauth2/v2/auth",
  token: "https://oauth2.googleapis.com/token",
  keys: createRemoteJWKSet(new URL("https://www.googleapis.com/oauth2/v3/certs")),
};
const discovered = new Map<string, Promise<Provider>>();

/** The provider `env` signs in with: Google's endpoints as they are, another's as its discovery document says (read
 * once an isolate, again after it failed). */
export function provider(env: Env): Promise<Provider> {
  const issuer = (env.OIDC_ISSUER ?? "").replace(/\/+$/, "");
  if (!issuer || issuer === GOOGLE.issuer) return Promise.resolve(GOOGLE);
  let found = discovered.get(issuer);
  if (!found) {
    found = discover(issuer);
    discovered.set(issuer, found);
    found.catch(() => discovered.delete(issuer));
  }
  return found;
}

async function discover(issuer: string): Promise<Provider> {
  const response = await fetch(`${issuer}/.well-known/openid-configuration`, { redirect: "manual", signal: AbortSignal.timeout(10_000) });
  if (!response.ok) throw new Error("oidc_discovery_failed");
  const doc = (await response.json()) as { issuer?: unknown; authorization_endpoint?: unknown; token_endpoint?: unknown; jwks_uri?: unknown };
  const https = (value: unknown): value is string => typeof value === "string" && /^https:\/\//.test(value);
  if (doc.issuer !== issuer || !https(doc.authorization_endpoint) || !https(doc.token_endpoint) || !https(doc.jwks_uri)) throw new Error("oidc_discovery_invalid");
  return { issuer, issuers: [issuer], authorization: doc.authorization_endpoint, token: doc.token_endpoint, keys: createRemoteJWKSet(new URL(doc.jwks_uri)) };
}

/** Whether signing in through the provider is set up: a client, with its secret (a public client of another provider's, with PKCE alone, needs none). */
export const providerConfigured = (env: Env): boolean => Boolean(env.GOOGLE_CLIENT_ID && (env.GOOGLE_CLIENT_SECRET || env.OIDC_ISSUER));

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

/** still.fail cloud's time, in ms: the machine's, but in the tests one fixed moment (test/worker.ts), so a run is the
 * same at any hour. Station sockets' presence and alarms' scheduling keep the machine's: the runtime's ping times are. */
export const clock = { now: () => Date.now() };
export const nowSeconds = () => Math.floor(clock.now() / 1000);
export const randomSecret = () => b64url(crypto.getRandomValues(new Uint8Array(32)));
/**
 * A secret a person pastes after a command (an enrollment's token: `stillfail station enroll <origin> <token>`, the
 * installers' `sh -s -- <token>`, PowerShell's): never one beginning with `-`, which a command line or PowerShell takes
 * for an option (one token in 64 did, and its command failed saying nothing that helped, 2026-11-14). One beginning so
 * is drawn again: the same length, less than 0.03 bit of its 256 lost (log2 64/63). `draw` is a test's.
 */
export function pastedSecret(draw: () => string = randomSecret): string {
  for (;;) {
    const secret = draw();
    if (!secret.startsWith("-")) return secret;
  }
}
export const b64url = (value: Uint8Array) =>
  btoa(String.fromCharCode(...value))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
export const digest = async (value: string) => b64url(new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(value))));
export const validSecret = (value: unknown): value is string => typeof value === "string" && /^[A-Za-z0-9_-]{43}$/.test(value);
export const validId = (value: unknown): value is string => typeof value === "string" && /^[0-7][0-9A-HJKMNP-TV-Z]{25}$/.test(value);

/** The Android app's callbacks: the app registers this scheme and host for the Custom Tab to return to. */
// The beta apps (fail.still.android.beta, fail.still.desktop.beta: 「youdid.wtf」) come back on a scheme of their own.
export const APP_REDIRECTS = ["stillfail://auth/callback", "stillfail-beta://auth/callback"];
/**
 * The Android apps' own: each build comes back on its package (apps/mbui WebAuth, its manifest's
 * `${applicationId}://auth`), so the stable, beta and dev apps installed side by side never take each other's.
 */
const ANDROID_REDIRECT = /^(fail\.still\.android|build\.monoid\.android)(\.beta|\.dev)?:\/\/auth\/callback$/;

/**
 * Where a login may return: the web app's own callback on one of its origins
 * (the test channel's included), the admin console's on one of its, the native
 * app's callback, or a loopback listener of a command-line client.
 */
export function validRedirect(env: Env, value: string): boolean {
  const beta = betaOrigin(env);
  if ([...publicOrigins(env), ...adminOrigins(env), ...(beta ? [beta] : [])].some((origin) => value === `${origin}/auth/callback`) || APP_REDIRECTS.includes(value) || ANDROID_REDIRECT.test(value)) return true;
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

/** Whether anyone can sign in: through the provider, or with a code sent to an email (mail.ts), or both. */
export function authConfigured(env: Env): boolean {
  return Boolean((providerConfigured(env) || (env.EMAIL && env.EMAIL_FROM)) && env.AUTH_SIGNING_KEY?.length >= 43 && env.PUBLIC_ORIGIN);
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

export async function readJson(request: Request, maximum?: number): Promise<Record<string, unknown>> {
  if (request.headers.get("content-type")?.split(";")[0] !== "application/json") throw new Error("content_type");
  const body = JSON.parse(await readText(request, maximum));
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
      currentDate: new Date(clock.now()),
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
// secrets are hashed, with only the last rotation's answer retained, encrypted
// (until the session ends, or rotates again).
async function encryptionKey(env: Env) {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(`stillfail-refresh-retry\0${env.AUTH_SIGNING_KEY}`)));
}
export async function seal(env: Env, value: Tokens, expires: number): Promise<string> {
  return new EncryptJWT({ value })
    .setProtectedHeader({ alg: "dir", enc: "A256GCM" })
    .setExpirationTime(expires)
    .encrypt(await encryptionKey(env));
}
export async function unseal(env: Env, value: string): Promise<Tokens> {
  const { payload } = await jwtDecrypt(value, await encryptionKey(env), {
    keyManagementAlgorithms: ["dir"],
    contentEncryptionAlgorithms: ["A256GCM"],
    currentDate: new Date(clock.now()),
  });
  return payload.value as Tokens;
}

/** `origin`: the one Google called back to, whose callback the login gave Google (PUBLIC_ORIGIN's, or an old one's for a login started before the move). Another provider's account is named apart from Google's (`oi-…`, as an email's is `em-…`), as its `sub` is that provider's alone. */
export async function googleIdentity(env: Env, code: string, verifier: string, nonce: string, origin = env.PUBLIC_ORIGIN): Promise<Identity> {
  const from = await provider(env);
  const response = await fetch(from.token, {
    method: "POST",
    redirect: "manual",
    signal: AbortSignal.timeout(10_000),
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      code,
      client_id: env.GOOGLE_CLIENT_ID,
      ...(env.GOOGLE_CLIENT_SECRET ? { client_secret: env.GOOGLE_CLIENT_SECRET } : {}),
      redirect_uri: `${origin}/v1/auth/google/callback`,
      grant_type: "authorization_code",
      code_verifier: verifier,
    }),
  });
  if (!response.ok) throw new Error("google_exchange_failed");
  const tokens = (await response.json()) as { id_token?: string };
  if (!tokens.id_token) throw new Error("google_identity_missing");
  const { payload } = await jwtVerify(tokens.id_token, from.keys, {
    algorithms: from === GOOGLE ? ["RS256"] : ["RS256", "PS256", "ES256", "EdDSA"],
    issuer: from.issuers,
    audience: env.GOOGLE_CLIENT_ID,
    requiredClaims: ["sub", "exp", "iat", "nonce", "email", "email_verified"],
    currentDate: new Date(clock.now()),
  });
  if (
    payload.nonce !== nonce ||
    payload.email_verified !== true ||
    typeof payload.email !== "string" ||
    typeof payload.sub !== "string" ||
    !(from === GOOGLE ? /^[A-Za-z0-9_-]{1,128}$/ : /^[\x21-\x7e]{1,255}$/).test(payload.sub) ||
    typeof payload.iat !== "number" ||
    payload.iat > nowSeconds() + 30 ||
    (payload.azp !== undefined && payload.azp !== env.GOOGLE_CLIENT_ID)
  )
    throw new Error("google_identity_mismatch");
  const sub = from === GOOGLE ? payload.sub : `oi-${(await digest(`${from.issuer}\0${payload.sub}`)).slice(0, 32)}`;
  const text = (value: unknown, max: number) => (typeof value === "string" ? value.slice(0, max) : "");
  return { sub, email: payload.email, name: text(payload.name, 120), picture: /^https:\/\//.test(text(payload.picture, 1024)) ? text(payload.picture, 1024) : "" };
}
