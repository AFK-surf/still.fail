// still.fail was called ember. No station, app or page from before the rename is left
// (2026-11-05: none in two weeks of telemetry), so the cloud answers only the new names, but for its old hosts (the
// *_ORIGIN_ALIASES, bound to the same Workers: stations enrolled then may still be told them in their own settings,
// which they move off themselves).
import { guestOrigins } from "./guests.ts";

/** The prefix of the names on the wire. */
const PREFIX = "stillfail";

/** `primary` and its aliases (a comma-separated list of origins), primary first, no empties. */
export function originList(primary: string, aliases?: string): string[] {
  const list = [primary, ...(aliases ?? "").split(",").map((o) => o.trim())].filter(Boolean);
  return [...new Set(list)];
}

/** The web app's and the API's origins: PUBLIC_ORIGIN (links are made with it), its old ones, and the guests' (guests.ts). */
export const publicOrigins = (env: { PUBLIC_ORIGIN: string; PUBLIC_ORIGIN_ALIASES?: string; GUESTS?: string }) =>
  originList(env.PUBLIC_ORIGIN, [env.PUBLIC_ORIGIN_ALIASES ?? "", ...guestOrigins(env)].join(","));

/** The admin console's origins: ADMIN_ORIGIN and its old ones. */
export const adminOrigins = (env: { ADMIN_ORIGIN: string; ADMIN_ORIGIN_ALIASES?: string }) => originList(env.ADMIN_ORIGIN, env.ADMIN_ORIGIN_ALIASES);

/** The test channel's origin (BETA_ORIGIN), or null when there is none. Not an alias: what it serves is gated (index.ts). */
export const betaOrigin = (env: { BETA_ORIGIN?: string }): string | null => env.BETA_ORIGIN?.trim() || null;

/** A still.fail request header by its name after the prefix (`station` for x-stillfail-station). */
export function header(from: Request | Headers, name: string): string | null {
  return (from instanceof Headers ? from : from.headers).get(`x-${PREFIX}-${name}`);
}

/** The ways a signed station message may read: `stillfail-<tag>:<origin>:<rest>` for each origin (and each of
 *  `former`'s prefixes). */
export function signedMessages(tag: string, origins: string[], rest: string, former: readonly string[] = []): string[] {
  return [PREFIX, ...former].flatMap((prefix) => origins.map((origin) => `${prefix}-${tag}:${origin}:${rest}`));
}
