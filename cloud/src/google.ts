// A Google service account's access token: the account signs an RS256 JWT, Google's token endpoint trades it for an
// access token, kept in memory until a few minutes before it ends. Used by FCM (fcm.ts) and the traces and logs sent
// to Google Cloud (tracing.ts).
import { importPKCS8, SignJWT } from "jose";

export interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
  token_uri?: string;
}

const TOKEN_URI = "https://oauth2.googleapis.com/token";

/** Each account's access token for a scope, by its client_email and the scope. */
const cached = new Map<string, { token: Promise<string | null>; until: number }>();

/** The service account in `json`, or null when it is not one. */
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

/** The access token for `scope`, asked for once however many calls want it at the same time; null when Google refused. */
export function accessToken(account: ServiceAccount, scope: string): Promise<string | null> {
  const key = `${account.client_email} ${scope}`;
  const now = Math.floor(Date.now() / 1000);
  const kept = cached.get(key);
  if (kept && kept.until > now) return kept.token;
  const token = newToken(account, scope, key, now).catch((error) => {
    console.warn(`google token: ${error}`);
    return null;
  });
  cached.set(key, { token, until: now + 60 });
  token.then((value) => {
    if (cached.get(key)?.token === token && !value) cached.delete(key);
  });
  return token;
}

/** Forget the account's token for `scope` (Google answered 401 with it). */
export function dropToken(account: ServiceAccount, scope: string): void {
  cached.delete(`${account.client_email} ${scope}`);
}

async function newToken(account: ServiceAccount, scope: string, key: string, now: number): Promise<string | null> {
  const audience = account.token_uri ?? TOKEN_URI;
  const assertion = await new SignJWT({ scope })
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
    console.warn(`google token: ${response.status}`);
    return null;
  }
  const kept = cached.get(key);
  if (kept) kept.until = now + Math.max(60, (body.expires_in ?? 3600) - 300);
  return body.access_token;
}
