import { createRemoteJWKSet, EncryptJWT, jwtDecrypt, jwtVerify } from "jose";
import type { Env } from "./env";
import { nowSeconds } from "./auth";

/** Optional operator bindings; never replace Google or the existing signing key. */
export interface AppleConfig {
  APPLE_CLIENT_ID?: string;
  /** Apple-issued ES256 client-secret JWT, provisioned/rotated by the operator. */
  APPLE_CLIENT_SECRET?: string;
  /** Independent high-entropy encryption key for retained revocable grants. */
  APPLE_GRANT_KEY?: string;
}
export type AppleEnv = Env & AppleConfig;
const keys = createRemoteJWKSet(new URL("https://appleid.apple.com/auth/keys"));
export function appleConfigured(env: AppleEnv): boolean {
  return Boolean(env.APPLE_CLIENT_ID && env.APPLE_CLIENT_SECRET && env.APPLE_GRANT_KEY && env.APPLE_GRANT_KEY.length >= 43 && env.AUTH_SIGNING_KEY?.length >= 43 && env.PUBLIC_ORIGIN);
}

export type AppleProfile = { providerSub: string; email: string; name: string; grant: string };
async function verified(env: AppleEnv, token: string, nonce: string) {
  const { payload } = await jwtVerify(token, keys, {
    algorithms: ["RS256"], issuer: "https://appleid.apple.com", audience: env.APPLE_CLIENT_ID,
    requiredClaims: ["sub", "exp", "iat", "nonce"],
  });
  if (payload.nonce !== nonce || typeof payload.sub !== "string" || !/^[A-Za-z0-9._-]{1,255}$/.test(payload.sub) ||
      typeof payload.iat !== "number" || payload.iat > nowSeconds() + 30 ||
      (payload.email !== undefined && (typeof payload.email !== "string" || payload.email.length > 254 || ![true, "true"].includes(payload.email_verified as any))))
    throw new Error("apple_identity_mismatch");
  return payload;
}
async function applePost(env: AppleEnv, endpoint: "token" | "revoke", values: Record<string, string>) {
  if (!appleConfigured(env)) throw new Error("apple_not_configured");
  return fetch(`https://appleid.apple.com/auth/${endpoint}`, {
    method: "POST", redirect: "manual", signal: AbortSignal.timeout(10_000),
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ ...values, client_id: env.APPLE_CLIENT_ID!, client_secret: env.APPLE_CLIENT_SECRET! }),
  });
}
/** Verify the native token AND exchange its one-use code; no local tokens before both succeed. */
export async function appleIdentity(env: AppleEnv, identityToken: string, code: string, nonce: string, name = ""): Promise<AppleProfile> {
  const native = await verified(env, identityToken, nonce);
  const response = await applePost(env, "token", { code, grant_type: "authorization_code" });
  if (!response.ok) throw new Error("apple_exchange_failed");
  const tokens = await response.json() as { id_token?: string; refresh_token?: string };
  if (!tokens.id_token || !tokens.refresh_token || tokens.refresh_token.length > 8192) throw new Error("apple_grant_missing");
  const exchanged = await verified(env, tokens.id_token, nonce);
  if (exchanged.sub !== native.sub || (native.email && exchanged.email && native.email !== exchanged.email)) throw new Error("apple_identity_mismatch");
  return { providerSub: native.sub!, email: (exchanged.email ?? native.email ?? "") as string, name: name.trim().slice(0, 120), grant: await encryptAppleGrant(env, tokens.refresh_token) };
}
async function grantKey(env: AppleEnv) {
  if (!env.APPLE_GRANT_KEY || env.APPLE_GRANT_KEY.length < 43) throw new Error("apple_not_configured");
  return new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`stillfail-apple-grant\0${env.APPLE_GRANT_KEY}`)));
}
export async function encryptAppleGrant(env: AppleEnv, token: string): Promise<string> {
  return new EncryptJWT({ token }).setProtectedHeader({ alg: "dir", enc: "A256GCM" }).encrypt(await grantKey(env));
}
/** Real provider revocation, not local logout. Keep encrypted grant until a successful provider acknowledgement. */
export async function revokeAppleGrant(env: AppleEnv, encrypted: string): Promise<void> {
  const { payload } = await jwtDecrypt(encrypted, await grantKey(env), { keyManagementAlgorithms: ["dir"], contentEncryptionAlgorithms: ["A256GCM"] });
  if (typeof payload.token !== "string") throw new Error("apple_grant_invalid");
  const response = await applePost(env, "revoke", { token: payload.token, token_type_hint: "refresh_token" });
  if (!response.ok) throw new Error("apple_revocation_failed");
}
