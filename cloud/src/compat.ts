// still.fail was called ember (docs/rename-still-fail.md), and stations, apps and pages from before the rename keep
// running for a long time. So the cloud answers both names: its old hosts (the *_ORIGIN_ALIASES, bound to the same
// Workers, kept for good and never redirected wholesale: only the web app's pages move to the new host, src/web.ts), the old request headers (x-ember-*, read when the
// x-stillfail-* one is missing), the old names inside signed messages and subprotocols, and the preview host's old
// /_ember/ paths. What it says itself (links, headers it sets) uses the new names.

/** The prefixes of the names on the wire, the new one first. */
export const PREFIXES = ["stillfail", "ember"] as const;

/** `primary` and its aliases (a comma-separated list of origins), primary first, no empties. */
export function originList(primary: string, aliases?: string): string[] {
  const list = [primary, ...(aliases ?? "").split(",").map((o) => o.trim())].filter(Boolean);
  return [...new Set(list)];
}

/** The web app's and the API's origins: PUBLIC_ORIGIN (links are made with it) and its old ones. */
export const publicOrigins = (env: { PUBLIC_ORIGIN: string; PUBLIC_ORIGIN_ALIASES?: string }) => originList(env.PUBLIC_ORIGIN, env.PUBLIC_ORIGIN_ALIASES);

/** The admin console's origins: ADMIN_ORIGIN and its old ones. */
export const adminOrigins = (env: { ADMIN_ORIGIN: string; ADMIN_ORIGIN_ALIASES?: string }) => originList(env.ADMIN_ORIGIN, env.ADMIN_ORIGIN_ALIASES);

/** A still.fail request header by its name after the prefix (`station` for x-stillfail-station), or its x-ember- one. */
export function header(from: Request | Headers, name: string): string | null {
  const headers = from instanceof Headers ? from : from.headers;
  for (const prefix of PREFIXES) {
    const value = headers.get(`x-${prefix}-${name}`);
    if (value !== null) return value;
  }
  return null;
}

/** The ways a signed station message may read: `<prefix>-<tag>:<origin>:<rest>`, for each prefix and origin. */
export function signedMessages(tag: string, origins: string[], rest: string): string[] {
  return PREFIXES.flatMap((prefix) => origins.map((origin) => `${prefix}-${tag}:${origin}:${rest}`));
}
