// The Google accounts signed in on this browser. The core keeps them, with
// their ember cloud sessions (docs/client-core.md): the page sees who is
// signed in, starts and finishes a sign-in, and signs out; tokens never reach it.
import { core, useTopic } from "../core/react.ts";

/** A signed-in account, as the `accounts` topic lists it. */
export interface Account {
  sub: string;
  email: string;
  name: string;
  picture: string;
}

/** The signed-in accounts; undefined until the core has answered. */
export function useAccounts(): Account[] | undefined {
  return useTopic<Account[]>({ topic: "accounts" }).value;
}

function browserName(): string {
  const ua = navigator.userAgent;
  const browser = /Edg\//.test(ua) ? "Edge" : /Chrome\//.test(ua) ? "Chrome" : /Firefox\//.test(ua) ? "Firefox" : /Safari\//.test(ua) ? "Safari" : "浏览器";
  const os = /Mac OS X/.test(ua) ? "macOS" : /Windows/.test(ua) ? "Windows" : /Android/.test(ua) ? "Android" : /iPhone|iPad/.test(ua) ? "iOS" : /Linux/.test(ua) ? "Linux" : "";
  return `ember 网页版 · ${browser}${os ? ` · ${os}` : ""}`;
}

/** Sends the browser to Google (via ember cloud); it comes back to /auth/callback. */
export async function signIn(returnTo = location.pathname + location.search + location.hash): Promise<void> {
  const { url } = await core().call("auth.begin", {
    redirect_uri: `${location.origin}/auth/callback`, return_to: returnTo, device_name: browserName(),
  }) as { url: string };
  location.assign(url);
}

/** Finishes a sign-in on /auth/callback. Returns where to go next. */
export async function completeSignIn(): Promise<string> {
  const { return_to } = await core().call("auth.complete", { query: location.search }) as { return_to: string };
  return return_to;
}

export async function signOut(sub: string): Promise<void> {
  await core().call("auth.signOut", { account: sub });
}
