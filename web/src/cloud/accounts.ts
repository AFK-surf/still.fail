// The Google accounts signed in on this browser. The core keeps them, with
// their ember cloud sessions (docs/client-core.md): the page sees who is
// signed in, starts and finishes a sign-in, and signs out; tokens never reach it.
import { core, useTopic } from "../core/react.ts";
import { signedOut, telemetrySettled, track } from "../telemetry.ts";

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

/**
 * Sends the browser to Google (via ember cloud); it comes back to /auth/callback.
 * The desktop app opens it in the system browser, which comes back to the app
 * through ember://auth/callback and on to the page's /auth/callback. It signs in by the name the core gives the device.
 */
export async function signIn(returnTo = location.pathname + location.search + location.hash): Promise<void> {
  const { url } = await core().call("auth.begin", {
    redirect_uri: window.stillfailDesktop ? `${window.stillfailDesktop.scheme ?? "stillfail"}://auth/callback` : `${location.origin}/auth/callback`, return_to: returnTo,
  }) as { url: string };
  location.assign(url);
}

/** Finishes a sign-in on /auth/callback. Returns where to go next. */
export async function completeSignIn(): Promise<string> {
  const { return_to } = await core().call("auth.complete", { query: location.search }) as { return_to: string };
  track("sign_in");
  // The page goes on to return_to at once: the event must be with posthog-js by then.
  await telemetrySettled();
  return return_to;
}

export async function signOut(sub: string): Promise<void> {
  await core().call("auth.signOut", { account: sub });
  signedOut(sub);
}
