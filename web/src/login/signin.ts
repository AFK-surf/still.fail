// Signing in on the web without the core: this page goes to still.fail cloud's sign-in itself
// (PKCE: GET /v1/auth/google/start, then POST /v1/auth/token with the code it brings back) and leaves the account
// it got for the page that comes next, whose core takes it in as its own (`take`, the core's `migrate`), as a page
// before the core handed over the accounts it kept. The cloud is this page's own origin (its /v1 routes).
import { base64url } from "../../../client/core-ts/src/util.ts";

/** What a sign-in begun here keeps until it comes back (this tab's alone). */
const PENDING = "stillfail.login";
/** The accounts signed in here, for the next page's core to take. */
const HANDED = "stillfail.signedIn";

type Pending = { verifier: string; state: string; returnTo: string; redirectUri: string };
/** An account as the core's `migrate` takes it. */
export type Handed = { sub: string; email: string; name: string; picture: string; access: string; refresh: string; accessExpires: number };

/** Why a sign-in did not finish: its words' key (web-login.*), or what the cloud said. */
export class SignInError extends Error {
  constructor(readonly key: "cancelled" | "failed" | "expired" | "stateMismatch" | "wrongPassword", message = key) {
    super(message);
  }
}

const secret = () => base64url(crypto.getRandomValues(new Uint8Array(32)));

async function challenge(verifier: string): Promise<string> {
  return base64url(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier))));
}

/** What this browser signs in as: the app and the browser, as the core names a web device (core-misc.device.web). */
export function deviceName(words: (browser: string, os: string) => string): string {
  const agent = navigator.userAgent;
  const os = /iPhone|iPad/.test(agent) ? "iOS" : agent.includes("Mac OS X") ? "macOS" : agent.includes("Windows") ? "Windows" : agent.includes("Android") ? "Android" : agent.includes("Linux") ? "Linux" : "";
  const browser = agent.includes("Edg/") ? "Edge" : agent.includes("Chrome/") ? "Chrome" : agent.includes("Firefox/") ? "Firefox" : agent.includes("Safari/") ? "Safari" : "";
  return words(browser, os);
}

/** Where a page given `?return_to=` goes once signed in: a path of this origin, else its root. */
export function returnTo(query: string): string {
  const to = new URLSearchParams(query).get("return_to") ?? "/";
  return to.startsWith("/") && !to.startsWith("//") && !to.startsWith("/auth/") && !to.startsWith("/login") ? to : "/";
}

/** Sends the browser to still.fail cloud's sign-in, which brings it back to /auth/callback. */
export async function begin(to: string, name: string): Promise<void> {
  const pending: Pending = { verifier: secret(), state: secret(), returnTo: to, redirectUri: `${location.origin}/auth/callback` };
  sessionStorage.setItem(PENDING, JSON.stringify(pending));
  const query = new URLSearchParams({
    state: pending.state, code_challenge: await challenge(pending.verifier), code_challenge_method: "S256",
    redirect_uri: pending.redirectUri, name,
  });
  location.assign(`/v1/auth/google/start?${query}`);
}

/** Finishes a sign-in on /auth/callback (`query`, its search): the account handed on; where to go next. */
export async function complete(query: string): Promise<string> {
  const params = new URLSearchParams(query);
  const raw = sessionStorage.getItem(PENDING);
  // A sign-in is good for one try, whatever its outcome.
  sessionStorage.removeItem(PENDING);
  const error = params.get("error");
  if (error) throw new SignInError(error === "login_cancelled" ? "cancelled" : "failed");
  let pending: Pending | null = null;
  try { pending = raw ? JSON.parse(raw) as Pending : null; } catch { /* not ours */ }
  if (!pending || params.get("state") !== pending.state) throw new SignInError("stateMismatch");
  const answer = await fetch("/v1/auth/token", {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ code: params.get("code"), code_verifier: pending.verifier, redirect_uri: pending.redirectUri }),
  });
  if (!handTokens(answer.ok ? await answer.json() : null)) throw new SignInError("expired");
  return pending.returnTo;
}

/** Signs in with an email and a password (the accounts still.fail cloud set up for it), the account handed on. */
export async function password(email: string, password: string, name: string): Promise<void> {
  const answer = await fetch("/v1/auth/password", {
    method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ email, password, name }),
  });
  if (answer.status === 401) throw new SignInError("wrongPassword");
  if (!handTokens(answer.ok ? await answer.json() : null)) throw new SignInError("failed");
}

/** The account the cloud's tokens say, handed on; false when they are not tokens. */
function handTokens(tokens: unknown): boolean {
  const { access_token, refresh_token, subject, email, name, expires_at } = (tokens ?? {}) as Record<string, unknown>;
  if (typeof access_token !== "string" || typeof refresh_token !== "string" || typeof subject !== "string" || typeof email !== "string" || typeof expires_at !== "number") return false;
  hand({ sub: subject, email, name: typeof name === "string" ? name : "", picture: "", access: access_token, refresh: refresh_token, accessExpires: expires_at });
  return true;
}

function hand(account: Handed): void {
  const was = taken(localStorage.getItem(HANDED)).filter((a) => a.sub !== account.sub);
  localStorage.setItem(HANDED, JSON.stringify([...was, account]));
}

function taken(raw: string | null): Handed[] {
  try {
    const list = raw ? JSON.parse(raw) as unknown : [];
    return Array.isArray(list) ? list as Handed[] : [];
  } catch { return []; }
}

/** The accounts signed in here since the core last took them, taken (gone from here): for its `migrate`. */
export function take(): Handed[] {
  const list = taken(localStorage.getItem(HANDED));
  localStorage.removeItem(HANDED);
  return list;
}

/** Puts back accounts taken that the core did not keep (it failed): the next page's core takes them. */
export function putBack(list: Handed[]): void {
  for (const a of list) hand(a);
}
