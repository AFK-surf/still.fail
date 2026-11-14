// Firebase Cloud Messaging, for the Android apps: the HTTP v1 API, as the Firebase project's
// service account (FCM_SERVICE_ACCOUNT, its JSON). The account signs an RS256 JWT, Google's token endpoint trades it
// for an access token (google.ts).
//
// One cloud serves both products' apps (still.fail's and monoid's), each app in a Firebase project of its own, and a
// token is sent to only by its own project's account (another's is answered SENDER_ID_MISMATCH). The other projects'
// accounts are FCM_SERVICE_ACCOUNT_MORE (one, or a list): a token is tried with the project it was last sent by, then
// with the others, and the project that took it is kept with its registration (push.ts).
import { accessToken, dropToken, serviceAccount, type ServiceAccount } from "./google";
import type { Outcome } from "./webpush";

const SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

/** FCM_SERVICE_ACCOUNT, then each of FCM_SERVICE_ACCOUNT_MORE (one account's JSON, or a list of them): those that are one. */
export function serviceAccounts(json: string | undefined, more: string | undefined): ServiceAccount[] {
  const all: (ServiceAccount | null)[] = [serviceAccount(json)];
  if (more) {
    try {
      const value = JSON.parse(more) as unknown;
      for (const one of Array.isArray(value) ? value : [value]) all.push(serviceAccount(JSON.stringify(one)));
    } catch {
      // (not JSON: none more)
    }
  }
  const seen = new Set<string>();
  return all.filter((a): a is ServiceAccount => a !== null && !seen.has(a.project_id) && !!seen.add(a.project_id));
}

/**
 * A high-priority data message to a device's token, every value of `data` a string, as FCM wants (the app replaces a
 * chat's notification itself, by its tag). The token is gone when FCM says so (404, UNREGISTERED); "other" when it is
 * another project's app's (SENDER_ID_MISMATCH).
 */
export async function fcmPush(account: ServiceAccount, token: string, data: Record<string, string>): Promise<Outcome | "other"> {
  const access = await accessToken(account, SCOPE);
  if (!access) return "failed";
  const response = await fetch(`https://fcm.googleapis.com/v1/projects/${encodeURIComponent(account.project_id)}/messages:send`, {
    method: "POST",
    headers: { authorization: `Bearer ${access}`, "content-type": "application/json" },
    body: JSON.stringify({ message: { token, data, android: { priority: "HIGH" } } }),
  });
  if (response.ok) {
    await response.body?.cancel();
    return "sent";
  }
  const text = await response.text().catch(() => "");
  if (response.status === 401) dropToken(account, SCOPE);
  if (text.includes("SENDER_ID_MISMATCH")) return "other";
  if (response.status === 404 || text.includes("UNREGISTERED")) return "gone";
  console.warn(`fcm push: ${response.status} ${text.slice(0, 200)}`);
  return "failed";
}

/**
 * `fcmPush` with each of `accounts` in turn, the project it was last sent by (`known`) first, till one takes it: what
 * came of it, and the project that took it. Gone only when none took it and one said gone; one project's "gone" for a
 * token of another's moves on to the next.
 */
export async function fcmPushAny(accounts: ServiceAccount[], token: string, known: string | undefined, data: Record<string, string>): Promise<{ outcome: Outcome; app?: string }> {
  const order = [...accounts.filter((a) => a.project_id === known), ...accounts.filter((a) => a.project_id !== known)];
  let failed = false, gone = false;
  for (const account of order) {
    const outcome = await fcmPush(account, token, data);
    if (outcome === "sent") return { outcome, app: account.project_id };
    if (outcome === "failed") failed = true;
    if (outcome === "gone") gone = true;
  }
  if (!failed && !gone && order.length) console.warn("fcm push: no project of ours has this token");
  return { outcome: failed ? "failed" : gone ? "gone" : "failed" };
}
