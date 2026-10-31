// The workspace lock, checked on the device (the stations' rules, station/src/cloud/lock.ts `genesis`/`apply`): what the
// vault trusts to say which device a box key is and whose. The rest of the core shows the lock as the cloud keeps it
// (views/lock.ts `fold`, unchecked); before a vault's key is sealed to a device, every entry's signature and signer is
// checked here, so neither the cloud nor a station can put a device of their own in it.
import { sha256 } from "@noble/hashes/sha2.js";
import { CoreError } from "../error.ts";
import { type Entry, entryHash, signedBytes } from "../lock.ts";
import { utf8 } from "../util.ts";
import { fromB64url } from "./crypto.ts";
import { ed25519Ok, p256Ok } from "./verified.ts";

export type Device = { id: string; sub: string; kind: "app" | "web"; sign_key?: string; exp?: number };
/// `cloudKeys`: the keys the cloud signs member credentials with, as the lock names them (a JWKS).
export type Checked = { ws: string; head: string; genesis: string; members: Map<string, string>; devices: Map<string, Device>; passkeys: Map<string, string>; origins: string[]; rp_id: string; disabled: boolean; cloudKeys: unknown };

const ROLES = ["viewer", "member", "admin", "owner"];
const rank = (r: string) => ROLES.indexOf(r);
const HEX32 = /^[0-9a-f]{64}$/;
const unhex = (h: string) => Uint8Array.from(h.match(/../g) ?? [], (b) => parseInt(b, 16));
const arr = (v: unknown): any[] => (Array.isArray(v) ? v : []);
function refuse(why: string): never {
  throw new CoreError("vault_lock_invalid", `the workspace's lock does not check out: ${why}`);
}

function point(id: string): Uint8Array | null {
  if (!id.startsWith("p256:")) return null;
  const p = fromB64url(id.slice(5));
  return p !== null && p.length === 65 && p[0] === 4 ? p : null;
}

/// Whether `sig` is its key's over the entry `hash`; a passkey's on one of `origins` for `rp_id` (WebAuthn).
function sigValid(sig: any, hash: string, s: Checked, passkey: boolean): boolean {
  try {
    if (sig?.alg === "webauthn") {
      const pub = point(sig.key);
      if (!passkey || pub === null) return false;
      const client = fromB64url(sig.client_data), auth = fromB64url(sig.authenticator_data), der = fromB64url(sig.sig);
      if (client === null || auth === null || der === null) return false;
      const data = JSON.parse(new TextDecoder().decode(client));
      const challenge = fromB64url(String(data?.challenge ?? ""));
      if (data?.type !== "webauthn.get" || challenge === null || [...challenge].map((b) => b.toString(16).padStart(2, "0")).join("") !== hash || !s.origins.includes(data?.origin)) return false;
      const rp = sha256(utf8(s.rp_id));
      if (auth.length < 37 || rp.some((b, i) => auth[i] !== b) || (auth[32]! & 1) === 0) return false;
      const signed = new Uint8Array(auth.length + 32);
      signed.set(auth);
      signed.set(sha256(client), auth.length);
      return p256Ok(der, signed, pub, true);
    }
    if (passkey) return false;
    const bytes = signedBytes(hash);
    if (sig?.alg === "Ed25519" && /^ed25519:[0-9a-f]{64}$/.test(sig.key)) return ed25519Ok(unhex(sig.sig), bytes, unhex(sig.key.slice(8)));
    const pub = sig?.alg === "ES256" ? point(sig.key) : null;
    const raw = pub ? fromB64url(sig.sig) : null;
    return pub !== null && raw !== null && p256Ok(raw, bytes, pub);
  } catch {
    return false;
  }
}

/// Who signs with `key` in the lock (a member's passkey, or an app device of theirs not run out): what a station takes
/// an entry signed with it from; null for none.
export const signerIn = (s: Checked, key: string, now: number | null) => signer(s, { key }, now);

function signer(s: Checked, sig: any, now: number | null): { sub: string; role: string; passkey: boolean } | null {
  const key = sig?.key;
  for (const [k, sub] of s.passkeys) if (k === key && s.members.has(sub)) return { sub, role: s.members.get(sub)!, passkey: true };
  for (const d of s.devices.values()) {
    if (d.sign_key === key && d.kind === "app" && (d.exp === undefined || now === null || d.exp > now) && s.members.has(d.sub)) return { sub: d.sub, role: s.members.get(d.sub)!, passkey: false };
  }
  return null;
}

function device(v: any): Device {
  if (!HEX32.test(v?.id ?? "") || typeof v?.sub !== "string" || (v.kind !== "app" && v.kind !== "web")) refuse("a device is {id, sub, kind}");
  if (v.sign_key !== undefined && v.kind !== "app") refuse("only an app's device signs");
  return { id: v.id, sub: v.sub, kind: v.kind, ...(typeof v.sign_key === "string" ? { sign_key: v.sign_key } : {}), ...(Number.isSafeInteger(v.exp) ? { exp: v.exp } : {}) };
}

const addDevice = (s: Checked, d: Device) => {
  if (!s.members.has(d.sub)) refuse("a device is a member's");
  s.devices.set(d.id, d);
};

/// The lock its entries make, each checked as a station checks it; throws why not. `now` (unix seconds): signing
/// devices that ran out sign no more.
export function checkLock(entries: Entry[], now: number): Checked {
  const first = entries[0];
  if (!first || first.kind !== "genesis" || first.seq !== 0 || first.prev !== null) return refuse("it starts with its genesis");
  const b = (first.body ?? {}) as any;
  const head = entryHash(first);
  let s: Checked = { ws: first.ws, head, genesis: head, members: new Map(), devices: new Map(), passkeys: new Map(), origins: arr(b.origins).filter((o) => typeof o === "string"), rp_id: typeof b.rp_id === "string" ? b.rp_id : "", disabled: false, cloudKeys: b.cloud_keys ?? null };
  for (const m of arr(b.members)) if (typeof m?.sub === "string" && rank(m.role) >= 0) s.members.set(m.sub, m.role);
  for (const d of arr(b.devices)) addDevice(s, device(d));
  for (const p of arr(b.passkeys)) if (typeof p?.key === "string" && typeof p?.sub === "string") s.passkeys.set(p.key, p.sub);
  if (s.members.get(b.owner) !== "owner") refuse("the genesis names its owner");
  const by = signer(s, first.sig, first.at);
  if (by === null || by.sub !== b.owner || !sigValid(first.sig, head, s, by.passkey)) refuse("the genesis is not signed by its owner");
  for (const e of entries.slice(1)) s = apply(s, e, now);
  return s;
}

function apply(prev: Checked, e: Entry, now: number): Checked {
  if (prev.disabled) refuse("it was turned off");
  if (e.ws !== prev.ws || e.prev !== prev.head) refuse(`entry ${e.seq} does not follow`);
  const hash = entryHash(e);
  const by = signer(prev, e.sig, now);
  if (by === null || !sigValid(e.sig, hash, prev, by.passkey)) refuse(`entry ${e.seq} is not signed by a device or passkey in it`);
  const s: Checked = { ...prev, head: hash, members: new Map(prev.members), devices: new Map(prev.devices), passkeys: new Map(prev.passkeys) };
  const b = (e.body ?? {}) as any;
  const managing = rank(by.role) >= rank("admin");
  const owning = by.role === "owner";
  const need = (ok: boolean) => ok || refuse(`entry ${e.seq} (${e.kind}) is not its signer's to make`);
  const owners = () => [...s.members.values()].filter((r) => r === "owner").length > 0;
  switch (e.kind) {
    case "member":
      need(managing && rank(b.role) >= 0 && typeof b.sub === "string" && (owning || (b.role !== "owner" && s.members.get(b.sub) !== "owner")));
      s.members.set(b.sub, b.role);
      need(owners());
      break;
    case "member.remove":
      need(managing && s.members.has(b.sub) && (owning || s.members.get(b.sub) !== "owner"));
      s.members.delete(b.sub);
      need(owners());
      for (const [k, d] of s.devices) if (d.sub === b.sub) s.devices.delete(k);
      for (const [k, sub] of s.passkeys) if (sub === b.sub) s.passkeys.delete(k);
      break;
    case "device": {
      const d = device(b);
      need(managing || d.sub === by.sub);
      addDevice(s, d);
      break;
    }
    case "device.remove": {
      const d = s.devices.get(b.id);
      need(d !== undefined && (managing || d.sub === by.sub));
      s.devices.delete(b.id);
      break;
    }
    case "passkey":
      need(typeof b.key === "string" && s.members.has(b.sub) && (managing || b.sub === by.sub));
      s.passkeys.set(b.key, b.sub);
      break;
    case "passkey.remove": {
      const sub = s.passkeys.get(b.key);
      need(sub !== undefined && (managing || sub === by.sub));
      s.passkeys.delete(b.key);
      break;
    }
    case "station":
    case "station.remove":
    case "gateway":
    case "gateway.remove":
      need(managing);
      break;
    case "cloud_keys":
      need(owning);
      s.cloudKeys = b.keys ?? null;
      break;
    case "disable":
      need(owning);
      s.disabled = true;
      break;
    default:
      refuse(`entry ${e.seq} is of an unknown kind`);
  }
  return s;
}
