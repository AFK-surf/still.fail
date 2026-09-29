// Web Push (docs/notifications.md): a browser's subscription is an endpoint of its push service and two keys; a
// message to it is encrypted for those keys (RFC 8291, `aes128gcm` of RFC 8188) and signed for with still.fail
// cloud's VAPID key (RFC 8292). WebCrypto only: ECDH P-256, HKDF-SHA-256, AES-128-GCM, ECDSA P-256.

const encoder = new TextEncoder();

export const fromB64url = (value: string): Uint8Array => {
  const base64 = value.replaceAll("-", "+").replaceAll("_", "/");
  return Uint8Array.from(atob(base64 + "=".repeat((4 - (base64.length % 4)) % 4)), (c) => c.charCodeAt(0));
};
export const toB64url = (value: Uint8Array): string => {
  let binary = "";
  for (const byte of value) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
};

const concat = (...parts: Uint8Array[]): Uint8Array => {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let offset = 0;
  for (const part of parts) {
    out.set(part, offset);
    offset += part.length;
  }
  return out;
};

/** Whether this is a P-256 public point as it travels: base64url of its 65 bytes, uncompressed. */
export function validPoint(value: unknown): value is string {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]{87}$/.test(value)) return false;
  const bytes = fromB64url(value);
  return bytes.length === 65 && bytes[0] === 4;
}
/** A subscription's auth secret (16 bytes). */
export const validAuthSecret = (value: unknown): value is string => typeof value === "string" && /^[A-Za-z0-9_-]{22}$/.test(value);

async function hkdf(salt: Uint8Array, ikm: Uint8Array | ArrayBuffer, info: Uint8Array, bytes: number): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey("raw", ikm, "HKDF", false, ["deriveBits"]);
  return new Uint8Array(await crypto.subtle.deriveBits({ name: "HKDF", hash: "SHA-256", salt, info }, key, bytes * 8));
}

/** The P-256 key `d` with its public point, as WebCrypto takes it. */
function jwk(publicPoint: Uint8Array, d?: Uint8Array): JsonWebKey {
  return { kty: "EC", crv: "P-256", x: toB64url(publicPoint.slice(1, 33)), y: toB64url(publicPoint.slice(33, 65)), ...(d ? { d: toB64url(d) } : {}) };
}

/** The sender's side of one message: its ECDH key pair and salt, fresh each time (fixed only by the tests). */
export interface Sender {
  keys: CryptoKeyPair;
  salt: Uint8Array;
}

/** A sender's key pair from a known private key (the RFC's test vector; VAPID keys are not used for this). */
export async function senderKeys(publicB64: string, privateB64: string): Promise<CryptoKeyPair> {
  const point = fromB64url(publicB64);
  return {
    publicKey: await crypto.subtle.importKey("jwk", jwk(point), { name: "ECDH", namedCurve: "P-256" }, true, []),
    privateKey: await crypto.subtle.importKey("jwk", jwk(point, fromB64url(privateB64)), { name: "ECDH", namedCurve: "P-256" }, false, ["deriveBits"]),
  };
}

/** Record size of the one record a message is: anything larger than the message does. */
const RECORD_SIZE = 4096;

/**
 * `payload` encrypted for a subscription's keys (RFC 8291): the body of a push with `Content-Encoding: aes128gcm`.
 * One record, the padding delimiter 0x02 and no padding.
 */
export async function encrypt(payload: Uint8Array, p256dh: string, authSecret: string, sender?: Sender): Promise<Uint8Array> {
  const uaPublic = fromB64url(p256dh);
  const { keys, salt } = sender ?? { keys: (await crypto.subtle.generateKey({ name: "ECDH", namedCurve: "P-256" }, true, ["deriveBits"])) as CryptoKeyPair, salt: crypto.getRandomValues(new Uint8Array(16)) };
  const asPublic = new Uint8Array((await crypto.subtle.exportKey("raw", keys.publicKey)) as ArrayBuffer);
  const uaKey = await crypto.subtle.importKey("raw", uaPublic, { name: "ECDH", namedCurve: "P-256" }, false, []);
  // Not a literal in the call: Workers' types name the key `$public`, which the runtime does not read.
  const ecdh = { name: "ECDH", public: uaKey };
  const ecdhSecret = await crypto.subtle.deriveBits(ecdh, keys.privateKey, 256);
  const ikm = await hkdf(fromB64url(authSecret), ecdhSecret, concat(encoder.encode("WebPush: info\0"), uaPublic, asPublic), 32);
  const cek = await hkdf(salt, ikm, encoder.encode("Content-Encoding: aes128gcm\0"), 16);
  const nonce = await hkdf(salt, ikm, encoder.encode("Content-Encoding: nonce\0"), 12);
  const key = await crypto.subtle.importKey("raw", cek, "AES-GCM", false, ["encrypt"]);
  const sealed = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv: nonce }, key, concat(payload, new Uint8Array([2]))));
  const header = new Uint8Array(21);
  header.set(salt);
  new DataView(header.buffer).setUint32(16, RECORD_SIZE);
  header[20] = asPublic.length;
  return concat(header, asPublic, sealed);
}

/** still.fail cloud's VAPID key: the P-256 public point and private scalar, base64url; and who to write to. */
export interface Vapid {
  publicKey: string;
  privateKey: string;
  subject: string;
}

const signingKeys = new Map<string, Promise<CryptoKey>>();
const tokens = new Map<string, { value: string; until: number }>();
/** A VAPID token lasts this long (at most 24 hours; push services take up to 12 from some senders). */
const VAPID_TTL_SEC = 12 * 60 * 60;

/** The `Authorization` of a push to `endpoint` (RFC 8292): an ES256 JWT for its origin, kept until an hour before it ends. */
export async function vapidAuthorization(vapid: Vapid, endpoint: string, now = Math.floor(Date.now() / 1000)): Promise<string> {
  const aud = new URL(endpoint).origin;
  const cacheKey = `${vapid.publicKey}|${aud}`;
  let token = tokens.get(cacheKey);
  if (!token || token.until <= now) {
    let key = signingKeys.get(vapid.publicKey);
    if (!key) {
      key = crypto.subtle.importKey("jwk", jwk(fromB64url(vapid.publicKey), fromB64url(vapid.privateKey)), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
      signingKeys.set(vapid.publicKey, key);
    }
    const exp = now + VAPID_TTL_SEC;
    const part = (value: unknown) => toB64url(encoder.encode(JSON.stringify(value)));
    const input = `${part({ typ: "JWT", alg: "ES256" })}.${part({ aud, exp, sub: vapid.subject })}`;
    // WebCrypto's ECDSA signature is r || s, which is what JWS wants.
    const signature = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, await key, encoder.encode(input)));
    token = { value: `${input}.${toB64url(signature)}`, until: exp - 60 * 60 };
    tokens.set(cacheKey, token);
  }
  return `vapid t=${token.value}, k=${vapid.publicKey}`;
}

export interface WebSubscription {
  endpoint: string;
  p256dh: string;
  auth: string;
}

/** What became of a push: taken, the subscription is gone for good (404/410), or it failed (worth nothing more). */
export type Outcome = "sent" | "gone" | "failed";

/**
 * Pushes `payload` to a browser's subscription. `topic` names what it replaces while undelivered (one per chat: a newer
 * notice of the chat takes the older's place); it is made to fit the header's 32 base64url characters.
 */
export async function webPush(vapid: Vapid, subscription: WebSubscription, payload: string, topic: string, ttl = 86400): Promise<Outcome> {
  const body = await encrypt(encoder.encode(payload), subscription.p256dh, subscription.auth);
  const topicHash = toB64url(new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(topic))).slice(0, 24));
  const response = await fetch(subscription.endpoint, {
    method: "POST",
    headers: {
      authorization: await vapidAuthorization(vapid, subscription.endpoint),
      "content-encoding": "aes128gcm",
      "content-type": "application/octet-stream",
      ttl: String(ttl),
      urgency: "high",
      topic: topicHash,
    },
    body,
  });
  await response.body?.cancel();
  if (response.status === 404 || response.status === 410) return "gone";
  if (response.ok) return "sent";
  console.warn(`web push to ${new URL(subscription.endpoint).origin}: ${response.status}`);
  return "failed";
}
