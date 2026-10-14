// The workspace's lock (docs/workspace-lock.md): a hash-chained record of who belongs, each entry signed by a device or
// passkey the record itself names. Once a station pins it, the control plane only stores and carries it: who may
// connect, with what role, which stations are peers, which gateways and grant keys count, all come from here. Pure:
// what is kept and when it is told is cloud/state.ts's.
import { createHash, createPublicKey, verify } from "node:crypto";

export type Sig =
  | { key: string; alg: "Ed25519" | "ES256"; sig: string }
  | { key: string; alg: "webauthn"; authenticator_data: string; client_data: string; sig: string };

export type Entry = { v: 1; ws: string; seq: number; prev: string | null; at: number; kind: string; body: any; sig: Sig };

export type Role = "owner" | "admin" | "member" | "viewer";
export type Member = { sub: string; email: string; role: Role };
/// A device: its base iroh key (`id`), whose person, the client it is, the key it signs with (an app's only), the
/// endpoint ids an older client connects with (it proves none), until when (a web page's).
export type Device = { id: string; sub: string; kind: "app" | "web"; label: string; sign_key?: string; endpoints?: string[]; exp?: number };
export type Passkey = { id: string; sub: string; key: string; label: string };
export type Station = { key: string; name: string };

export type LockState = {
  ws: string;
  seq: number;
  /// The last entry's hash.
  head: string;
  /// Genesis's hash: which lock this is.
  genesis: string;
  /// The pages passkeys sign on (WebAuthn `origin`) and their relying party id.
  origins: string[];
  rp_id: string;
  /// The control plane's credential keys (a JWKS) that count.
  cloud_keys: any;
  members: Map<string, Member>;
  devices: Map<string, Device>;
  passkeys: Map<string, Passkey>;
  stations: Map<string, Station>;
  gateways: Set<string>;
  disabled: boolean;
};

export const ROLES: Role[] = ["viewer", "member", "admin", "owner"];
export const rank = (role: string) => ROLES.indexOf(role as Role);
const manager = (role: Role) => rank(role) >= rank("admin");
/// The lower of two roles: the control plane may take rights away, never give them (an unknown role is the lowest).
export const lowerRole = (a: string, b: string): Role => ROLES[Math.max(0, Math.min(rank(a), rank(b)))]!;

/// How long a device added from a web page lasts at most (30 days, a day's slack for clocks).
export const WEB_DEVICE_SECS = 31 * 86400;

const HEX32 = /^[0-9a-f]{64}$/;
const isId = (v: unknown): v is string => typeof v === "string" && HEX32.test(v);
const str = (v: unknown, max = 200) => (typeof v === "string" && v.length <= max ? v : null);

/// JSON with object keys sorted, no space: what is hashed. Only integers, strings, booleans, null, arrays, objects.
export function canonical(v: unknown): string {
  if (v === null || typeof v === "boolean" || typeof v === "string") return JSON.stringify(v);
  if (typeof v === "number") {
    if (!Number.isSafeInteger(v)) throw new Error("lock entries hold integers only");
    return String(v);
  }
  if (Array.isArray(v)) return `[${v.map(canonical).join(",")}]`;
  if (typeof v === "object") {
    const keys = Object.keys(v as object).filter((k) => (v as any)[k] !== undefined).sort();
    return `{${keys.map((k) => `${JSON.stringify(k)}:${canonical((v as any)[k])}`).join(",")}}`;
  }
  throw new Error("not a lock value");
}

const sha256 = (b: Uint8Array | string) => createHash("sha256").update(b).digest();

/// An entry's hash (hex): of everything but its signature.
export function entryHash(e: Entry): string {
  const { v, ws, seq, prev, at, kind, body } = e;
  return sha256(`stillfail-lock/1\n${canonical({ v, ws, seq, prev, at, kind, body })}`).toString("hex");
}

/// What a device or app key signs for an entry: a tag, then the hash's bytes. (A passkey signs the hash as its
/// WebAuthn challenge.)
export const signedBytes = (hash: string) => Buffer.concat([Buffer.from("stillfail-lock/1 sig\0"), Buffer.from(hash, "hex")]);

/// What a device's base key signs to say an endpoint is its own, in a workspace (and what it shows the cloud when it
/// asks for a credential for that endpoint).
export const endpointBytes = (ws: string, endpoint: string) => Buffer.from(`stillfail-lock-endpoint/1\0${ws}\0${endpoint}`);

/// A signing key's public half by its id: `ed25519:<hex>` or `p256:<base64url of the uncompressed point>`.
function publicKey(id: string) {
  if (id.startsWith("ed25519:") && isId(id.slice(8))) {
    return { alg: "Ed25519" as const, key: createPublicKey({ key: { kty: "OKP", crv: "Ed25519", x: Buffer.from(id.slice(8), "hex").toString("base64url") }, format: "jwk" }) };
  }
  if (id.startsWith("p256:")) {
    const point = Buffer.from(id.slice(5), "base64url");
    if (point.length !== 65 || point[0] !== 4) throw new Error("not a P-256 key");
    return { alg: "ES256" as const, key: createPublicKey({ key: { kty: "EC", crv: "P-256", x: point.subarray(1, 33).toString("base64url"), y: point.subarray(33).toString("base64url") }, format: "jwk" }) };
  }
  throw new Error("unknown key kind");
}

export const validKeyId = (id: unknown): id is string => {
  if (typeof id !== "string" || id.length > 200) return false;
  try {
    publicKey(id);
    return true;
  } catch {
    return false;
  }
};

/// Whether `sig` is the key's over the entry `hash`; a passkey's also on one of `origins` for `rp_id`.
export function sigValid(sig: Sig, hash: string, origins: string[], rp_id: string, passkey: boolean): boolean {
  try {
    const { alg, key } = publicKey(sig.key);
    if (sig.alg === "webauthn") {
      if (!passkey || alg !== "ES256") return false;
      const client = Buffer.from(sig.client_data, "base64url");
      const data = JSON.parse(client.toString("utf8"));
      if (data?.type !== "webauthn.get" || data?.challenge !== Buffer.from(hash, "hex").toString("base64url") || !origins.includes(data?.origin)) return false;
      const auth = Buffer.from(sig.authenticator_data, "base64url");
      // rpIdHash, then flags: user present.
      if (auth.length < 37 || !auth.subarray(0, 32).equals(sha256(rp_id)) || (auth[32]! & 1) === 0) return false;
      return verify("sha256", Buffer.concat([auth, sha256(client)]), { key, dsaEncoding: "der" }, Buffer.from(sig.sig, "base64url"));
    }
    if (sig.alg !== alg || passkey) return false;
    if (alg === "Ed25519") return verify(null, signedBytes(hash), key, Buffer.from(sig.sig, "hex"));
    return verify("sha256", signedBytes(hash), { key, dsaEncoding: "ieee-p1363" }, Buffer.from(sig.sig, "base64url"));
  } catch {
    return false;
  }
}

/// Whether a device's base key says `endpoint` is its own in workspace `ws`.
export function endpointProof(ws: string, base: string, endpoint: string, proof: string): boolean {
  try {
    return isId(base) && verify(null, endpointBytes(ws, endpoint), publicKey(`ed25519:${base}`).key, Buffer.from(proof, "hex"));
  } catch {
    return false;
  }
}

function member(v: any): Member {
  const sub = str(v?.sub), email = str(v?.email, 320), role = v?.role;
  if (!sub || email === null || rank(role) < 0) throw new Error("a member is {sub, email, role}");
  return { sub, email, role };
}

function device(v: any, at: number): Device {
  const id = v?.id, sub = str(v?.sub), label = str(v?.label) ?? "", kind = v?.kind;
  if (!isId(id) || !sub || (kind !== "app" && kind !== "web")) throw new Error("a device is {id, sub, kind, label}");
  const d: Device = { id, sub, kind, label };
  if (v.sign_key !== undefined) {
    if (kind !== "app" || !validKeyId(v.sign_key)) throw new Error("only an app's device signs, with an ed25519 or p256 key");
    d.sign_key = v.sign_key;
  }
  if (v.endpoints !== undefined) {
    if (!Array.isArray(v.endpoints) || v.endpoints.length > 64 || !v.endpoints.every(isId)) throw new Error("endpoints are iroh ids");
    d.endpoints = v.endpoints;
  }
  if (v.exp !== undefined) {
    if (!Number.isSafeInteger(v.exp)) throw new Error("exp is unix seconds");
    d.exp = v.exp;
  }
  if (kind === "web" && at > 0 && (d.exp === undefined || d.exp > at + WEB_DEVICE_SECS)) throw new Error("a web page's device lasts 30 days at most");
  return d;
}

function passkey(v: any): Passkey {
  const id = str(v?.id, 1400), sub = str(v?.sub), key = v?.key, label = str(v?.label) ?? "";
  if (!id || !sub || typeof key !== "string" || !key.startsWith("p256:") || !validKeyId(key)) throw new Error("a passkey is {id, sub, key: p256:…}");
  return { id, sub, key, label };
}

function station(v: any): Station {
  if (!isId(v?.key)) throw new Error("a station is {key, name}");
  return { key: v.key, name: str(v?.name) ?? "" };
}

/// Who signed: the member whose app device or passkey holds the key, with their role now.
function signer(s: LockState, sig: Sig, now: number | null): { sub: string; role: Role; passkey: boolean } | null {
  for (const p of s.passkeys.values()) if (p.key === sig.key) return withRole(s, p.sub, true);
  for (const d of s.devices.values()) {
    if (d.sign_key === sig.key && d.kind === "app" && (d.exp === undefined || now === null || d.exp > now)) return withRole(s, d.sub, false);
  }
  return null;
}

function withRole(s: LockState, sub: string, passkey: boolean) {
  const m = s.members.get(sub);
  return m ? { sub, role: m.role, passkey } : null;
}

const owners = (s: LockState) => [...s.members.values()].filter((m) => m.role === "owner").length;

/// The lock its first entry starts. Throws why it is not one.
export function genesis(e: Entry): LockState {
  if (e.kind !== "genesis" || e.seq !== 0 || e.prev !== null || e.v !== 1 || typeof e.ws !== "string" || !e.ws) throw new Error("a lock starts with its genesis");
  const b = e.body ?? {};
  const origins = Array.isArray(b.origins) ? b.origins.filter((o: unknown) => typeof o === "string") : [];
  const s: LockState = {
    ws: e.ws, seq: 0, head: entryHash(e), genesis: entryHash(e), origins, rp_id: str(b.rp_id) ?? "", cloud_keys: b.cloud_keys ?? null,
    members: new Map(), devices: new Map(), passkeys: new Map(), stations: new Map(), gateways: new Set(), disabled: false,
  };
  for (const m of arr(b.members)) s.members.set(member(m).sub, member(m));
  for (const d of arr(b.devices)) add(s, device(d, 0));
  for (const p of arr(b.passkeys)) s.passkeys.set(passkey(p).key, passkey(p));
  for (const st of arr(b.stations)) s.stations.set(station(st).key, station(st));
  for (const g of arr(b.gateways)) if (isId(g)) s.gateways.add(g);
  if (s.members.get(b.owner)?.role !== "owner") throw new Error("the genesis names its owner among its members");
  const by = signer(s, e.sig, e.at);
  if (by === null || by.sub !== b.owner || !sigValid(e.sig, s.head, s.origins, s.rp_id, by.passkey)) throw new Error("the genesis is not signed by its owner");
  return s;
}

const arr = (v: unknown): any[] => (Array.isArray(v) ? v : []);

function add(s: LockState, d: Device) {
  if (!s.members.has(d.sub)) throw new Error("a device is a member's");
  s.devices.set(d.id, d);
}

/// The lock with one more entry; throws why the entry does not follow. `now`: the station's time (unix seconds), for
/// signing devices that ran out; null for entries taken before (kept in lock.json).
export function apply(prev: LockState, e: Entry, now: number | null): LockState {
  if (prev.disabled) throw new Error("the lock is turned off");
  if (e.v !== 1 || e.ws !== prev.ws) throw new Error("an entry of another lock");
  if (e.seq !== prev.seq + 1 || e.prev !== prev.head) throw new Error("the entry does not follow this lock's head");
  if (!Number.isSafeInteger(e.at)) throw new Error("at is unix seconds");
  const hash = entryHash(e);
  const by = signer(prev, e.sig, now);
  if (by === null) throw new Error("not signed by a device or passkey in the lock");
  if (!sigValid(e.sig, hash, prev.origins, prev.rp_id, by.passkey)) throw new Error("signature invalid");
  const s: LockState = { ...prev, seq: e.seq, head: hash, members: new Map(prev.members), devices: new Map(prev.devices), passkeys: new Map(prev.passkeys), stations: new Map(prev.stations), gateways: new Set(prev.gateways) };
  const b = e.body ?? {};
  const managing = manager(by.role);
  const owning = by.role === "owner";
  const need = (ok: boolean, why: string) => {
    if (!ok) throw new Error(why);
  };
  switch (e.kind) {
    case "member": {
      const m = member(b);
      const was = s.members.get(m.sub);
      need(managing, "only owners and admins change members");
      need(owning || (m.role !== "owner" && was?.role !== "owner"), "only owners make or change owners");
      s.members.set(m.sub, m);
      need(owners(s) > 0, "a lock keeps an owner");
      break;
    }
    case "member.remove": {
      const sub = str(b.sub);
      need(sub !== null && s.members.has(sub), "no such member");
      need(managing && (owning || s.members.get(sub!)!.role !== "owner"), "only owners and admins remove members, owners owners");
      s.members.delete(sub!);
      need(owners(s) > 0, "a lock keeps an owner");
      for (const [k, d] of s.devices) if (d.sub === sub) s.devices.delete(k);
      for (const [k, p] of s.passkeys) if (p.sub === sub) s.passkeys.delete(k);
      break;
    }
    case "device": {
      const d = device(b, e.at);
      need(managing || d.sub === by.sub, "members add only their own devices");
      add(s, d);
      break;
    }
    case "device.remove": {
      const d = s.devices.get(b.id);
      need(d !== undefined, "no such device");
      need(managing || d!.sub === by.sub, "members remove only their own devices");
      s.devices.delete(b.id);
      break;
    }
    case "passkey": {
      const p = passkey(b);
      need(s.members.has(p.sub), "a passkey is a member's");
      need(managing || p.sub === by.sub, "members add only their own passkeys");
      s.passkeys.set(p.key, p);
      break;
    }
    case "passkey.remove": {
      const p = s.passkeys.get(b.key);
      need(p !== undefined, "no such passkey");
      need(managing || p!.sub === by.sub, "members remove only their own passkeys");
      s.passkeys.delete(b.key);
      break;
    }
    case "station":
      need(managing, "only owners and admins add stations");
      s.stations.set(station(b).key, station(b));
      break;
    case "station.remove":
      need(managing, "only owners and admins remove stations");
      s.stations.delete(b.key);
      break;
    case "gateway":
      need(managing && isId(b.key), "only owners and admins add gateways, by iroh id");
      s.gateways.add(b.key);
      break;
    case "gateway.remove":
      need(managing, "only owners and admins remove gateways");
      s.gateways.delete(b.key);
      break;
    case "cloud_keys":
      need(owning && b.keys !== undefined, "only owners change the control plane's keys");
      s.cloud_keys = b.keys;
      break;
    case "disable":
      need(owning, "only owners turn the lock off");
      s.disabled = true;
      break;
    default:
      throw new Error(`unknown entry kind ${String(e.kind)}`);
  }
  return s;
}

/// A whole chain, from its genesis. Throws at the first entry that does not follow.
export function fold(entries: Entry[], now: number | null): LockState {
  if (entries.length === 0) throw new Error("no lock");
  let s = genesis(entries[0]!);
  for (const e of entries.slice(1)) s = apply(s, e, now);
  return s;
}

/// The device a connection is, by the base key's proof for its endpoint or (an older client) the endpoint itself, and
/// that device's member's role in the lock. Throws why it may not connect.
export function admit(s: LockState, who: { sub: string; endpoint: string; base?: string; proof?: string }, now: number): { device: Device; role: Role } {
  let d: Device | undefined;
  if (who.base && who.proof && endpointProof(s.ws, who.base, who.endpoint, who.proof)) d = s.devices.get(who.base);
  d ??= s.devices.get(who.endpoint) ?? [...s.devices.values()].find((x) => x.endpoints?.includes(who.endpoint));
  if (d === undefined) throw new LockRefusal("this device is not confirmed in the workspace's lock");
  if (d.sub !== who.sub) throw new LockRefusal("this device is someone else's in the workspace's lock");
  if (d.exp !== undefined && d.exp <= now) throw new LockRefusal("this device's confirmation ran out");
  const m = s.members.get(d.sub);
  if (!m) throw new LockRefusal("not a member in the workspace's lock");
  return { device: d, role: m.role };
}

/// A refusal by the lock (the client asks to be confirmed), not a bad credential.
export class LockRefusal extends Error {
  readonly code = "lock_unconfirmed";
}

/// A short code for a device, both sides work it out from its base key: what a person compares before confirming it.
export function shortCode(base: string): string {
  const alphabet = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
  const h = sha256(`stillfail-lock-code/1\0${base}`);
  let out = "";
  for (let i = 0; i < 6; i++) out += alphabet[h[i]! % 32];
  return `${out.slice(0, 3)}-${out.slice(3)}`;
}

/// An entry as it may have come over the wire: its shape checked (not its signature).
export function asEntry(v: any): Entry | null {
  if (v === null || typeof v !== "object" || v.v !== 1 || typeof v.ws !== "string" || !Number.isSafeInteger(v.seq) || v.seq < 0) return null;
  if (!(v.prev === null || (typeof v.prev === "string" && HEX32.test(v.prev))) || !Number.isSafeInteger(v.at) || typeof v.kind !== "string") return null;
  const s = v.sig;
  if (s === null || typeof s !== "object" || typeof s.key !== "string" || typeof s.sig !== "string") return null;
  if (s.alg === "webauthn" ? typeof s.authenticator_data !== "string" || typeof s.client_data !== "string" : s.alg !== "Ed25519" && s.alg !== "ES256") return null;
  try {
    canonical(v.body ?? null);
  } catch {
    return null;
  }
  return v as Entry;
}
