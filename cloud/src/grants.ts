// A mstill.fail's credential: what lets a device into its workspace's stations. An Ed25519-signed JWT naming the account,
// the workspace, its role there, the device's key and the sign-in session it was asked for with. Stations verify it
// offline with the public key they pinned when they enrolled (and check the device against the iroh connection's
// peer), so once a device has one it reaches its stations without still.fail cloud — on a LAN, or with the cloud down —
// until it runs out. It lasts MEMBER_TTL_SEC and a device asks for a new one each day it can; what is revoked
// meanwhile (a member removed, a role changed, a session signed out) stations learn from still.fail cloud (directory.ts).
// The issuer ("ember-cloud") and the token type ("ember-member+jwt") are what stations check, old ones included:
// they keep their names.
import { importJWK, SignJWT, type JWK } from "jose";
import { nowSeconds } from "./auth";
import type { Env } from "./env";

export const MEMBER_TTL_SEC = 30 * 24 * 60 * 60;
export const CREDENTIAL_ISSUER = "ember-cloud";

export interface MemberClaims {
  sub: string;
  email: string;
  name: string;
  ws: string;
  role: string;
  /** The client's iroh public key (hex). */
  device: string;
  /** The sign-in session it was asked for with: signing that session out revokes it. */
  sid: string;
}

function privateJwk(env: Env): JWK & { kid: string } {
  const jwk = JSON.parse(env.GRANT_SIGNING_JWK) as JWK & { kid?: string };
  if (jwk.kty !== "OKP" || jwk.crv !== "Ed25519" || !jwk.d || !jwk.x) throw new Error("grant key misconfigured");
  return { ...jwk, kid: jwk.kid ?? "grant-1" };
}

/** The public half, as stations fetch it. */
export function grantKeys(env: Env): { keys: JWK[] } {
  const { d: _secret, ...rest } = privateJwk(env);
  return { keys: [{ ...rest, alg: "EdDSA", use: "sig" }] };
}

export async function signCredential(env: Env, claims: MemberClaims): Promise<{ credential: string; issued_at: number; expires_at: number }> {
  const jwk = privateJwk(env);
  const key = await importJWK(jwk, "EdDSA");
  const now = nowSeconds();
  const expires = now + MEMBER_TTL_SEC;
  const { sub, ...rest } = claims;
  const credential = await new SignJWT(rest)
    .setProtectedHeader({ alg: "EdDSA", typ: "ember-member+jwt", kid: jwk.kid })
    .setIssuer(CREDENTIAL_ISSUER)
    .setSubject(sub)
    .setIssuedAt(now)
    .setExpirationTime(expires)
    .sign(key);
  return { credential, issued_at: now, expires_at: expires };
}

const hexBytes = (hex: string) => Uint8Array.from(hex.match(/../g)!, (b) => parseInt(b, 16));
export const validKeyHex = (value: unknown): value is string => typeof value === "string" && /^[0-9a-f]{64}$/.test(value);

/** Whether the signature is over any of `messages` (the ways one may read: compat.ts signedMessages). */
export async function verifyAnySignature(publicHex: string, signatureHex: string, messages: string[]): Promise<boolean> {
  for (const message of messages) if (await verifyKeySignature(publicHex, signatureHex, message)) return true;
  return false;
}

/** Checks an Ed25519 signature made with an iroh key over `message`. */
export async function verifyKeySignature(publicHex: string, signatureHex: string, message: string): Promise<boolean> {
  if (!validKeyHex(publicHex) || !/^[0-9a-f]{128}$/.test(signatureHex)) return false;
  const key = await crypto.subtle.importKey("raw", hexBytes(publicHex), { name: "Ed25519" }, false, ["verify"]);
  return crypto.subtle.verify("Ed25519", key, hexBytes(signatureHex), new TextEncoder().encode(message));
}
