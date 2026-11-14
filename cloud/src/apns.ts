// Apple Push Notification service, for the iOS app: APNs' HTTP/2 API, straight from the
// worker, as the team's APNs key (APNS_KEY, its JSON: { keyId, teamId, key: the .p8's PEM, topic? the app's bundle id }).
// The key signs an ES256 JWT, which APNs takes for 20 to 60 minutes: kept for 40.
//
// One cloud serves both products' iOS apps (still.fail's and monoid's), each its own bundle id and maybe its own
// team's key: the others are APNS_KEY_MORE (one key's JSON, or a list), each with its topic. A token is tried with
// the topic it was last sent to, then the others (another app's token is answered DeviceTokenNotForTopic), and the
// topic that took it is kept with its registration (push.ts).
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

/** Each key's provider token, by its key id. */
const cached = new Map<string, { token: Promise<string>; until: number }>();

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

/** APNS_KEY, then each of APNS_KEY_MORE (one key's JSON, or a list of them): those that are one, a topic once. */
export function apnsKeys(json: string | undefined, more: string | undefined): ApnsKey[] {
  const all: (ApnsKey | null)[] = [apnsKey(json)];
  if (more) {
    try {
      const value = JSON.parse(more) as unknown;
      for (const one of Array.isArray(value) ? value : [value]) all.push(apnsKey(JSON.stringify(one)));
    } catch {
      // (not JSON: none more)
    }
  }
  const seen = new Set<string>();
  return all.filter((k): k is ApnsKey => k !== null && !seen.has(k.topic) && !!seen.add(k.topic));
}

/** The provider token, made once however many pushes want it at the same time. */
function providerToken(key: ApnsKey): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const kept = cached.get(key.keyId);
  if (kept && kept.until > now) return kept.token;
  const token = importPKCS8(key.key, "ES256").then((pk) =>
    new SignJWT({}).setProtectedHeader({ alg: "ES256", kid: key.keyId }).setIssuer(key.teamId).setIssuedAt(now).sign(pk),
  );
  cached.set(key.keyId, { token, until: now + KEEP_S });
  token.catch(() => {
    if (cached.get(key.keyId)?.token === token) cached.delete(key.keyId);
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
 * does not know); "other" when it is another app's (DeviceTokenNotForTopic).
 */
export async function apnsPush(key: ApnsKey, token: string, sandbox: boolean, data: Record<string, string>): Promise<Outcome | "other"> {
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
  if (text.includes("ExpiredProviderToken") || text.includes("InvalidProviderToken")) cached.delete(key.keyId);
  if (text.includes("DeviceTokenNotForTopic")) return "other";
  if (response.status === 410 || text.includes("BadDeviceToken")) return "gone";
  console.warn(`apns push: ${response.status} ${text.slice(0, 200)}`);
  return "failed";
}

/**
 * `apnsPush` with each of `keys` in turn, the topic it was last sent to (`known`) first, till one takes it: what came
 * of it, and the topic that took it. Gone only when none took it and one said gone.
 */
export async function apnsPushAny(keys: ApnsKey[], token: string, sandbox: boolean, known: string | undefined, data: Record<string, string>): Promise<{ outcome: Outcome; app?: string }> {
  const order = [...keys.filter((k) => k.topic === known), ...keys.filter((k) => k.topic !== known)];
  let failed = false, gone = false;
  for (const key of order) {
    const outcome = await apnsPush(key, token, sandbox, data);
    if (outcome === "sent") return { outcome, app: key.topic };
    if (outcome === "failed") failed = true;
    if (outcome === "gone") gone = true;
  }
  if (!failed && !gone && order.length) console.warn("apns push: no app of ours has this token");
  return { outcome: failed ? "failed" : gone ? "gone" : "failed" };
}
