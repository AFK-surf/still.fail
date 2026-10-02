// The operator's console: one Google account, the deployment's ADMIN_EMAIL (wrangler.jsonc), signs in to still.fail
// like anyone and may then list every user and workspace and hand out the
// invite codes that let new people create a workspace. Everyone else gets 404
// on these paths, so the console does not show that it exists. (The scripts'
// /v1/admin/accounts and /v1/admin/relay routes use ADMIN_TOKEN instead; see index.ts.)
import type { Env } from "./env";

/** Whether this verified email is the admin's; without ADMIN_EMAIL, nobody is. */
export function isAdmin(env: Env, email: string): boolean {
  return !!env.ADMIN_EMAIL && email.toLowerCase() === env.ADMIN_EMAIL.toLowerCase();
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
