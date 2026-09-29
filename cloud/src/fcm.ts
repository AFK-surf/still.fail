// Firebase Cloud Messaging (docs/notifications.md), for the Android app: the HTTP v1 API, as the Firebase project's
// service account (FCM_SERVICE_ACCOUNT, its JSON). The account signs an RS256 JWT, Google's token endpoint trades it
// for an access token, kept in memory until a few minutes before it ends.
import { importPKCS8, SignJWT } from "jose";
import type { Outcome } from "./webpush";

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
  token_uri?: string;
}

const SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
const TOKEN_URI = "https://oauth2.googleapis.com/token";

let cached: { account: string; token: Promise<string | null>; until: number } | null = null;

/** The service account in FCM_SERVICE_ACCOUNT, or null when it is not one. */
export function serviceAccount(json: string | undefined): ServiceAccount | null {
  if (!json) return null;
  try {
    const value = JSON.parse(json) as Partial<ServiceAccount>;
    if (typeof value.project_id !== "string" || typeof value.client_email !== "string" || typeof value.private_key !== "string") return null;
    return value as ServiceAccount;
  } catch {
    return null;
  }
}

/** The access token, asked for once however many pushes want it at the same time. */
function accessToken(account: ServiceAccount): Promise<string | null> {
  const now = Math.floor(Date.now() / 1000);
  if (cached && cached.account === account.client_email && cached.until > now) return cached.token;
  const token = newToken(account, now).catch((error) => {
    console.warn(`fcm token: ${error}`);
    return null;
  });
  cached = { account: account.client_email, token, until: now + 60 };
  token.then((value) => {
    if (cached?.token === token && !value) cached = null;
  });
  return token;
}

async function newToken(account: ServiceAccount, now: number): Promise<string | null> {
  const audience = account.token_uri ?? TOKEN_URI;
  const assertion = await new SignJWT({ scope: SCOPE })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(account.client_email)
    .setAudience(audience)
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(await importPKCS8(account.private_key, "RS256"));
  const response = await fetch(audience, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  const body = (await response.json().catch(() => null)) as { access_token?: string; expires_in?: number } | null;
  if (!response.ok || typeof body?.access_token !== "string") {
    console.warn(`fcm token: ${response.status}`);
    return null;
  }
  if (cached?.account === account.client_email) cached.until = now + Math.max(60, (body.expires_in ?? 3600) - 300);
  return body.access_token;
}

/**
 * A high-priority data message to a device's token, every value of `data` a string, as FCM wants (the app replaces a
 * chat's notification itself, by its tag). The token is gone when FCM says so (404, UNREGISTERED).
 */
export async function fcmPush(account: ServiceAccount, token: string, data: Record<string, string>): Promise<Outcome> {
  const access = await accessToken(account);
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
  if (response.status === 401) cached = null;
  if (response.status === 404 || text.includes("UNREGISTERED")) return "gone";
  console.warn(`fcm push: ${response.status} ${text.slice(0, 200)}`);
  return "failed";
}
