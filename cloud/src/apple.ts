// Sign in with Apple: a second way to an account, beside Google (docs/cloud.md, 登录). The web app, the desktop and
// Android apps go through the browser (the Services ID, APPLE_CLIENT_ID): Apple posts its answer back cross-site
// (response_mode=form_post, which asking for the email requires), so the callback takes the post, keeps it in the
// login attempt, and sends the browser on to a GET of its own, where the login's cookie comes along (SameSite=Lax
// cookies do not on a cross-site POST). The iOS app signs in natively and hands its identity token over
// (APPLE_BUNDLE_IDS: the token's audience is the app). Either way the account is Apple's `sub` for the team, so the
// same person is the same account on every client; an Apple account is never the Google account of the same email.
import { createRemoteJWKSet, importPKCS8, jwtVerify, SignJWT } from "jose";
import type { Env } from "./env";
import type { Identity } from "./auth";

const ISSUER = "https://appleid.apple.com";
const appleKeys = createRemoteJWKSet(new URL(`${ISSUER}/auth/keys`));

/** Whether the browser sign-in is set up: the Services ID and the key that signs its client secret. */
export function appleConfigured(env: Env): boolean {
  return Boolean(env.APPLE_CLIENT_ID && env.APPLE_TEAM_ID && env.APPLE_KEY_ID && env.APPLE_PRIVATE_KEY);
}

/** The native apps' bundle IDs whose identity tokens are taken (the iOS app's, its test build's). */
export function appleBundleIds(env: Env): string[] {
  return (env.APPLE_BUNDLE_IDS ?? "").split(",").map((id) => id.trim()).filter(Boolean);
}

/**
 * The account an Apple subject is: Apple's are like `001234.0123abcd….1234`; accounts' are `[A-Za-z0-9_-]`, Google's
 * all digits. The prefix keeps the two apart, and the mapping is one-to-one (an Apple subject has no `_`).
 */
export function appleAccount(sub: string): string | null {
  return /^[A-Za-z0-9.]{1,100}$/.test(sub) ? `apple_${sub.replaceAll(".", "_")}` : null;
}

/** Where the browser goes to sign in with Apple; it comes back by a POST to the callback. */
export function appleAuthorizeUrl(env: Env, state: string, nonce: string): string {
  const url = new URL(`${ISSUER}/auth/authorize`);
  for (const [key, value] of Object.entries({
    client_id: env.APPLE_CLIENT_ID!,
    redirect_uri: `${env.PUBLIC_ORIGIN}/v1/auth/apple/callback`,
    response_type: "code",
    response_mode: "form_post",
    scope: "name email",
    state,
    nonce,
  }))
    url.searchParams.set(key, value);
  return url.toString();
}

/** The name Apple gives once, at the first sign-in: the `user` field of its post (JSON), or the iOS app's. */
export function appleName(user: unknown): string {
  if (!user || typeof user !== "object") return "";
  const name = (user as { name?: unknown }).name;
  if (!name || typeof name !== "object") return "";
  const part = (value: unknown) => (typeof value === "string" ? value.trim() : "");
  const { firstName, lastName } = name as { firstName?: unknown; lastName?: unknown };
  return [part(firstName), part(lastName)].filter(Boolean).join(" ").slice(0, 120);
}

/** Apple's client secret: a short ES256 JWT the team's key signs (Apple takes one of up to six months). */
async function clientSecret(env: Env): Promise<string> {
  const key = await importPKCS8(env.APPLE_PRIVATE_KEY!, "ES256");
  return new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: env.APPLE_KEY_ID! })
    .setIssuer(env.APPLE_TEAM_ID!)
    .setSubject(env.APPLE_CLIENT_ID!)
    .setAudience(ISSUER)
    .setIssuedAt()
    .setExpirationTime("5m")
    .sign(key);
}

/** The browser sign-in's identity: trades the code Apple posted for its identity token. */
export async function appleIdentity(env: Env, code: string, nonce: string, name: string): Promise<Identity> {
  const response = await fetch(`${ISSUER}/auth/token`, {
    method: "POST",
    redirect: "manual",
    signal: AbortSignal.timeout(10_000),
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: env.APPLE_CLIENT_ID!,
      client_secret: await clientSecret(env),
      code,
      grant_type: "authorization_code",
      redirect_uri: `${env.PUBLIC_ORIGIN}/v1/auth/apple/callback`,
    }),
  });
  if (!response.ok) throw new Error("apple_exchange_failed");
  const tokens = (await response.json()) as { id_token?: string };
  if (!tokens.id_token) throw new Error("apple_identity_missing");
  return verifyAppleToken(tokens.id_token, [env.APPLE_CLIENT_ID!], nonce, name);
}

/**
 * An Apple identity token, for one of `audiences`, whose nonce is `nonce`: the browser's carries it as given, the iOS
 * app's as its SHA-256 (hex), which is what the app hands Apple. The email must be there and verified (a relay
 * address, when the person hides theirs, is one).
 */
export async function verifyAppleToken(token: string, audiences: string[], nonce: string, name: string): Promise<Identity> {
  if (token.length > 4096 || audiences.length === 0) throw new Error("apple_identity_mismatch");
  const { payload } = await jwtVerify(token, appleKeys, {
    algorithms: ["RS256"],
    issuer: ISSUER,
    audience: audiences,
    requiredClaims: ["sub", "exp", "iat", "nonce"],
  });
  const sub = typeof payload.sub === "string" ? appleAccount(payload.sub) : null;
  if (
    !sub ||
    payload.nonce !== nonce ||
    // Apple has sent it as a string as well as a boolean.
    (payload.email_verified !== true && payload.email_verified !== "true") ||
    typeof payload.email !== "string" ||
    !/^[^\s@]{1,64}@[^\s@]{1,190}$/.test(payload.email) ||
    typeof payload.iat !== "number" ||
    payload.iat > Math.floor(Date.now() / 1000) + 30
  )
    throw new Error("apple_identity_mismatch");
  return { sub, email: payload.email, name, picture: "" };
}
