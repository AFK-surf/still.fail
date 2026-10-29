// Apple Push Notification service (docs/notifications.md), for the iOS app: APNs' HTTP/2 API, straight from the
// worker, as the team's APNs key (APNS_KEY, its JSON: { keyId, teamId, key: the .p8's PEM, topic? the app's bundle id }).
// The key signs an ES256 JWT, which APNs takes for 20 to 60 minutes: kept for 40.
import { importPKCS8, SignJWT } from "jose";
import type { Outcome } from "./webpush";

export interface ApnsKey {
  keyId: string;
  teamId: string;
  key: string;
  /** The app the pushes are for (its bundle id). */
  topic: string;
}

const TOPIC = "fail.still.iphone";
const KEEP_S = 40 * 60;

let cached: { keyId: string; token: Promise<string>; until: number } | null = null;

/** The key in APNS_KEY, or null when it is not one. */
export function apnsKey(json: string | undefined): ApnsKey | null {
  if (!json) return null;
  try {
    const value = JSON.parse(json) as Partial<ApnsKey>;
    if (typeof value.keyId !== "string" || typeof value.teamId !== "string" || typeof value.key !== "string") return null;
    return { keyId: value.keyId, teamId: value.teamId, key: value.key, topic: typeof value.topic === "string" && value.topic ? value.topic : TOPIC };
  } catch {
    return null;
  }
}

/** The provider token, made once however many pushes want it at the same time. */
function providerToken(key: ApnsKey): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cached && cached.keyId === key.keyId && cached.until > now) return cached.token;
  const token = importPKCS8(key.key, "ES256").then((pk) =>
    new SignJWT({}).setProtectedHeader({ alg: "ES256", kid: key.keyId }).setIssuer(key.teamId).setIssuedAt(now).sign(pk),
  );
  cached = { keyId: key.keyId, token, until: now + KEEP_S };
  token.catch(() => {
    if (cached?.token === token) cached = null;
  });
  return token;
}

/** APNs' collapse id (at most 64 bytes) for a notice's tag: a newer push of the same chat replaces the one shown. */
async function collapseId(tag: string): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(tag)));
  return Array.from(digest.subarray(0, 24), (b) => b.toString(16).padStart(2, "0")).join("");
}

/**
 * An alert to a device's token (`sandbox`: one of a development build's), its `data` (the notice, every value a
 * string) beside `aps`, where the app reads what a tap opens. The token is gone when APNs says so (410, or a token it
 * does not know).
 */
export async function apnsPush(key: ApnsKey, token: string, sandbox: boolean, data: Record<string, string>): Promise<Outcome> {
  const jwt = await providerToken(key);
  const tag = data.tag ?? "";
  const host = sandbox ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  const response = await fetch(`https://${host}/3/device/${token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": key.topic,
      "apns-push-type": "alert",
      "apns-priority": "10",
      ...(tag ? { "apns-collapse-id": await collapseId(tag) } : {}),
      "content-type": "application/json",
    },
    body: JSON.stringify({ aps: { alert: { title: data.title ?? "", body: data.body ?? "" }, sound: "default", ...(tag ? { "thread-id": tag } : {}) }, ...data }),
  });
  if (response.ok) {
    await response.body?.cancel();
    return "sent";
  }
  const text = await response.text().catch(() => "");
  if (text.includes("ExpiredProviderToken") || text.includes("InvalidProviderToken")) cached = null;
  if (response.status === 410 || text.includes("BadDeviceToken")) return "gone";
  console.warn(`apns push: ${response.status} ${text.slice(0, 200)}`);
  return "failed";
}
