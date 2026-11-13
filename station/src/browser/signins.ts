// Sign-ins in a chat's browser ( 登录态): a site's sign-in is its cookies (and its passkeys: passkeys.ts),
// kept in the vault as an item of kind browser and put into a chat's browser while a grant for it lasts. Here: which cookies are a site's, the cookies
// of a browser as they are set again (DevTools' Storage.getCookies gives more than Storage.setCookies takes).
import { type Passkey, passkeyOf } from "./passkeys.ts";

/// A cookie as DevTools sets it (Network.CookieParam): what of a cookie it read is kept.
export type CookieParam = {
  name: string; value: string; domain: string; path: string; secure?: boolean; httpOnly?: boolean; sameSite?: string; expires?: number;
  priority?: string; sourceScheme?: string; sourcePort?: number; partitionKey?: unknown;
};

/// Whether a cookie of `domain` is one of `sites`' (each with its subdomains: github.com takes .github.com and
/// api.github.com, not notgithub.com).
export function ofSites(domain: string, sites: string[]): boolean {
  const d = domain.toLowerCase().replace(/^\./, "");
  return sites.some((s) => d === s || d.endsWith(`.${s}`));
}

/// The cookies among those DevTools read, as they are set again: a session cookie without its expiry.
function cookiesIn(read: unknown, keep?: (domain: string) => boolean): CookieParam[] {
  if (!Array.isArray(read)) return [];
  const out: CookieParam[] = [];
  for (const c of read) {
    if (c === null || typeof c !== "object" || typeof c.name !== "string" || typeof c.value !== "string" || typeof c.domain !== "string") continue;
    if (keep && !keep(c.domain)) continue;
    out.push({
      name: c.name, value: c.value, domain: c.domain, path: typeof c.path === "string" ? c.path : "/",
      ...(typeof c.secure === "boolean" ? { secure: c.secure } : {}), ...(typeof c.httpOnly === "boolean" ? { httpOnly: c.httpOnly } : {}),
      ...(typeof c.sameSite === "string" ? { sameSite: c.sameSite } : {}),
      ...(c.session !== true && typeof c.expires === "number" && c.expires > 0 ? { expires: c.expires } : {}),
      ...(typeof c.priority === "string" ? { priority: c.priority } : {}), ...(typeof c.sourceScheme === "string" ? { sourceScheme: c.sourceScheme } : {}),
      ...(typeof c.sourcePort === "number" ? { sourcePort: c.sourcePort } : {}), ...(c.partitionKey !== undefined ? { partitionKey: c.partitionKey } : {}),
    });
  }
  return out;
}

/// All cookies among those DevTools read, as they are set again (a profile sign-in's isolated context: browser.ts).
export function allCookies(read: unknown): CookieParam[] {
  return cookiesIn(read);
}

/// The cookies of `sites` among those DevTools read, as they are set again: a session cookie without its expiry.
export function siteCookies(read: unknown, sites: string[]): CookieParam[] {
  return cookiesIn(read, (domain) => ofSites(domain, sites));
}

/// A sign-in as the vault keeps it (the item's `cookies` field): its cookies, as JSON; with its sites' passkeys too
/// (passkeys.ts), an object of both. One without passkeys stays the cookies alone, as every sign-in was before.
export type SignInState = { cookies: CookieParam[]; passkeys: Passkey[] };

/// A sign-in's state read from what the vault keeps: the cookies alone (a list), or both.
export function stateOf(kept: string): SignInState {
  let v: any = null;
  try {
    v = JSON.parse(kept);
  } catch {}
  if (Array.isArray(v)) return { cookies: v, passkeys: [] };
  const passkeys = Array.isArray(v?.passkeys) ? v.passkeys.map(passkeyOf).filter((p: Passkey | null): p is Passkey => p !== null) : [];
  return { cookies: Array.isArray(v?.cookies) ? v.cookies : [], passkeys };
}

/// What the vault keeps of a sign-in's state: the cookies alone where it has no passkeys.
export function keptOf(s: SignInState): string {
  return JSON.stringify(s.passkeys.length === 0 ? s.cookies : { cookies: s.cookies, passkeys: s.passkeys });
}

/// The same cookies set to have expired: setting them so takes them out of the browser.
export function expired(cookies: CookieParam[]): CookieParam[] {
  return cookies.map((c) => ({ ...c, value: "", expires: 1 }));
}

/// A sign-in put into a chat's browser: its request and workspace, sites, and end (unix seconds). Older kept contexts
/// do not have the workspace.
export type SignedIn = { request: string; workspace?: string; sites: string[]; until: number };
