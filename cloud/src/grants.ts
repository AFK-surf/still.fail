// Grants: what lets a client into a station. An Ed25519-signed JWT naming the
// account, the workspace, its role there, the station and the client's device
// key. Stations verify it offline with the public key they pinned when they
// enrolled, and check the device against the iroh connection's peer.
import { importJWK, SignJWT, type JWK } from "jose";
import { nowSeconds } from "./auth";
import type { Env } from "./env";

export const GRANT_TTL_SEC = 10 * 60;
export const GRANT_ISSUER = "ember-cloud";

export interface GrantClaims {
  sub: string;
  email: string;
  name: string;
  ws: string;
  role: string;
  /** Target station's iroh public key (hex). */
  aud: string;
  /** The client's iroh public key (hex). */
  device: string;
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

export async function signGrant(env: Env, claims: GrantClaims): Promise<{ grant: string; expires_at: number }> {
  const jwk = privateJwk(env);
  const key = await importJWK(jwk, "EdDSA");
  const now = nowSeconds();
  const expires = now + GRANT_TTL_SEC;
  const { aud, sub, ...rest } = claims;
  const grant = await new SignJWT(rest)
    .setProtectedHeader({ alg: "EdDSA", typ: "ember-grant+jwt", kid: jwk.kid })
    .setIssuer(GRANT_ISSUER)
    .setSubject(sub)
    .setAudience(aud)
    .setIssuedAt(now)
    .setExpirationTime(expires)
    .sign(key);
  return { grant, expires_at: expires };
}

const hexBytes = (hex: string) => Uint8Array.from(hex.match(/../g)!, (b) => parseInt(b, 16));
export const validKeyHex = (value: unknown): value is string => typeof value === "string" && /^[0-9a-f]{64}$/.test(value);

/** Checks an Ed25519 signature made with an iroh key over `message`. */
export async function verifyKeySignature(publicHex: string, signatureHex: string, message: string): Promise<boolean> {
  if (!validKeyHex(publicHex) || !/^[0-9a-f]{128}$/.test(signatureHex)) return false;
  const key = await crypto.subtle.importKey("raw", hexBytes(publicHex), { name: "Ed25519" }, false, ["verify"]);
  return crypto.subtle.verify("Ed25519", key, hexBytes(signatureHex), new TextEncoder().encode(message));
}
