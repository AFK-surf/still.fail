// The Google accounts signed in on this browser. Each keeps its own ember
// cloud session (short access token, rotating refresh token), so one page can
// hold several accounts and switch between them without signing in again.

export interface Account {
  sub: string;
  email: string;
  name: string;
  picture: string;
  access: string;
  refresh: string;
  /** Epoch seconds. */
  accessExpires: number;
}

interface Tokens {
  access_token: string;
  refresh_token: string;
  subject: string;
  email: string;
  name?: string;
  expires_at: number;
}

const STORE = "ember.accounts";
const LOGIN = "ember.login";

export class SignedOut extends Error {}

export function accounts(): Account[] {
  try {
    return JSON.parse(localStorage.getItem(STORE) ?? "[]") as Account[];
  } catch {
    return [];
  }
}

function save(list: Account[]): void {
  localStorage.setItem(STORE, JSON.stringify(list));
  window.dispatchEvent(new Event("ember-accounts"));
}

function put(account: Account): void {
  save([...accounts().filter((a) => a.sub !== account.sub), account]);
}

export function forget(sub: string): void {
  save(accounts().filter((a) => a.sub !== sub));
}

const b64url = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
const secret = () => b64url(crypto.getRandomValues(new Uint8Array(32)));
const sha256 = async (text: string) => b64url(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text))));

/** A ULID, which ember cloud wants as the id of each refresh request. */
function ulid(): string {
  const alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
  let time = Date.now();
  let out = "";
  for (let i = 0; i < 10; i++) {
    out = alphabet[time % 32] + out;
    time = Math.floor(time / 32);
  }
  for (const byte of crypto.getRandomValues(new Uint8Array(16))) out += alphabet[byte % 32];
  return out;
}

function browserName(): string {
  const ua = navigator.userAgent;
  const browser = /Edg\//.test(ua) ? "Edge" : /Chrome\//.test(ua) ? "Chrome" : /Firefox\//.test(ua) ? "Firefox" : /Safari\//.test(ua) ? "Safari" : "浏览器";
  const os = /Mac OS X/.test(ua) ? "macOS" : /Windows/.test(ua) ? "Windows" : /Android/.test(ua) ? "Android" : /iPhone|iPad/.test(ua) ? "iOS" : /Linux/.test(ua) ? "Linux" : "";
  return `ember 网页版 · ${browser}${os ? ` · ${os}` : ""}`;
}

/** Sends the browser to Google (via ember cloud); it comes back to /auth/callback. */
export async function signIn(returnTo = location.pathname + location.hash): Promise<void> {
  const verifier = secret();
  const state = secret();
  sessionStorage.setItem(LOGIN, JSON.stringify({ verifier, state, returnTo }));
  const params = new URLSearchParams({
    state, code_challenge: await sha256(verifier), code_challenge_method: "S256",
    redirect_uri: `${location.origin}/auth/callback`, name: browserName(),
  });
  location.assign(`/v1/auth/google/start?${params}`);
}

/** Finishes a sign-in on /auth/callback. Returns where to go next. */
export async function completeSignIn(): Promise<string> {
  const params = new URLSearchParams(location.search);
  const pending = JSON.parse(sessionStorage.getItem(LOGIN) ?? "null") as { verifier: string; state: string; returnTo: string } | null;
  sessionStorage.removeItem(LOGIN);
  if (params.get("error")) throw new Error(params.get("error") === "login_cancelled" ? "登录已取消" : "Google 登录没有成功");
  if (!pending || params.get("state") !== pending.state) throw new Error("登录状态不匹配，请重新登录");
  const response = await fetch("/v1/auth/token", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ code: params.get("code"), code_verifier: pending.verifier, redirect_uri: `${location.origin}/auth/callback` }),
  });
  if (!response.ok) throw new Error("登录凭证已失效，请重新登录");
  const tokens = await response.json() as Tokens;
  const account: Account = {
    sub: tokens.subject, email: tokens.email, name: tokens.name ?? "", picture: "",
    access: tokens.access_token, refresh: tokens.refresh_token, accessExpires: tokens.expires_at,
  };
  put(account);
  // The picture comes with the profile; fetched once, best effort.
  const me = await fetch("/v1/me", { headers: { authorization: `Bearer ${account.access}` } }).then((r) => r.json()).catch(() => null) as { user?: { picture?: string } } | null;
  if (me?.user?.picture) put({ ...account, picture: me.user.picture });
  return pending.returnTo && !pending.returnTo.startsWith("/auth/") ? pending.returnTo : "/";
}

const refreshing = new Map<string, Promise<string>>();

/** A usable access token for `sub`, refreshing it when it is about to expire. */
export function accessToken(sub: string): Promise<string> {
  const account = accounts().find((a) => a.sub === sub);
  if (!account) return Promise.reject(new SignedOut("这个账号已退出"));
  if (account.accessExpires - 60 > Date.now() / 1000) return Promise.resolve(account.access);
  let pending = refreshing.get(sub);
  if (!pending) {
    pending = (async () => {
      const response = await fetch("/v1/auth/refresh", {
        method: "POST",
        headers: { authorization: `Bearer ${account.refresh}`, "content-type": "application/json" },
        body: JSON.stringify({ request_id: ulid() }),
      });
      if (response.status === 401) {
        forget(sub);
        throw new SignedOut(`${account.email} 的登录已过期，请重新登录`);
      }
      if (!response.ok) throw new Error(`刷新登录失败（${response.status}）`);
      const tokens = await response.json() as Tokens;
      put({ ...account, access: tokens.access_token, refresh: tokens.refresh_token, accessExpires: tokens.expires_at, name: tokens.name || account.name });
      return tokens.access_token;
    })().finally(() => refreshing.delete(sub));
    refreshing.set(sub, pending);
  }
  return pending;
}

export async function signOut(sub: string): Promise<void> {
  const account = accounts().find((a) => a.sub === sub);
  if (account) {
    await fetch("/v1/auth/logout", {
      method: "POST",
      headers: { authorization: `Bearer ${account.refresh}`, "content-type": "application/json" },
      body: JSON.stringify({ all: false }),
    }).catch(() => undefined);
  }
  forget(sub);
}
