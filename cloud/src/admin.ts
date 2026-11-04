// The operator's console: one Google account, the deployment's ADMIN_EMAIL, signs in to still.fail
// like anyone and may then list every user and workspace and hand out the
// invite codes that let new people create a workspace. Everyone else gets 404
// on these paths, so the console does not show that it exists. (The scripts'
// /v1/admin/accounts and /v1/admin/relay routes use ADMIN_TOKEN instead; see index.ts.)
// A cloud with Cloudflare Access in front of the console's host (ACCESS_TEAM_DOMAIN, ACCESS_AUD: monoid's) lets in
// its team instead, whoever Access's policy lets through, signed in to that cloud as themselves.
import { createRemoteJWKSet, jwtVerify } from "jose";
import { clock } from "./auth";
import type { Env } from "./env";

/** Whether this verified email is the admin's; without ADMIN_EMAIL, nobody is. */
export function isAdmin(env: Env, email: string): boolean {
  return !!env.ADMIN_EMAIL && email.toLowerCase() === env.ADMIN_EMAIL.toLowerCase();
}

const accessKeys = new Map<string, ReturnType<typeof createRemoteJWKSet>>();

/** Whether `request` came through the console's Cloudflare Access application: the token Access adds
 * (Cf-Access-Jwt-Assertion) signed by the team's keys, for that application, not expired. Without Access set up, never. */
export async function throughAccess(request: Request, env: Env): Promise<boolean> {
  const team = env.ACCESS_TEAM_DOMAIN?.replace(/\/+$/, ""), aud = env.ACCESS_AUD;
  const token = request.headers.get("cf-access-jwt-assertion");
  if (!team || !aud || !token) return false;
  let keys = accessKeys.get(team);
  if (!keys) accessKeys.set(team, (keys = createRemoteJWKSet(new URL(`${team}/cdn-cgi/access/certs`))));
  try {
    await jwtVerify(token, keys, { issuer: team, audience: aud, algorithms: ["RS256"], currentDate: new Date(clock.now()) });
    return true;
  } catch {
    return false;
  }
}

/** Whether the console answers this signed-in account: through Access where it is set up, else the admin's email. */
export async function consoleAdmin(request: Request, env: Env, email: string): Promise<boolean> {
  return env.ACCESS_TEAM_DOMAIN && env.ACCESS_AUD ? throughAccess(request, env) : isAdmin(env, email);
}

export const CODE_TTL_DAYS = 14;
// No 0/O, 1/I/L or U: codes are read aloud and typed by hand.
const ALPHABET = "ABCDEFGHJKMNPQRSTVWXYZ23456789";

/** A new code, XXXX-XXXX-XXXX: 12 characters of 30, about 59 bits. */
export function newCode(): string {
  const chars: string[] = [];
  while (chars.length < 12) {
    for (const byte of crypto.getRandomValues(new Uint8Array(16))) {
      // 240 = 8 × 30: rejecting the rest keeps every character equally likely.
      if (byte < 240 && chars.length < 12) chars.push(ALPHABET[byte % 30]!);
    }
  }
  return formatCode(chars.join(""));
}

/** A code as typed (any case, spaces or dashes) in its stored form, or null if it cannot be one. */
export function normalizeCode(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const bare = value.toUpperCase().replace(/[\s-]/g, "");
  return bare.length === 12 && [...bare].every((c) => ALPHABET.includes(c)) ? formatCode(bare) : null;
}

const formatCode = (bare: string) => `${bare.slice(0, 4)}-${bare.slice(4, 8)}-${bare.slice(8)}`;
