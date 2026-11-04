// The workspace lock's rules as station/src/cloud/lock.ts had them in TypeScript, before rules/ (MoonBit) took them
// over: what station/test/rules-lock.test.ts checks the MoonBit against, until the proofs cover all of them.
import { type Device, type Entry, type LockState, type Member, type Passkey, type Role, type Sig, type Station, LockRefusal, WEB_DEVICE_SECS, endpointProof, entryHash, rank, sigValid, validKeyId } from "../src/cloud/lock.ts";

const HEX32 = /^[0-9a-f]{64}$/;
const isId = (v: unknown): v is string => typeof v === "string" && HEX32.test(v);
const str = (v: unknown, max = 200) => (typeof v === "string" && v.length <= max ? v : null);
const manager = (role: Role) => rank(role) >= rank("admin");

function member(v: any): Member {
  const sub = str(v?.sub), email = str(v?.email, 320), role = v?.role;
  if (!sub || email === null || rank(role) < 0) throw new Error("a member is {sub, email, role}");
  return { sub, email, role };
}

function device(v: any, at: number): Device {
  const id = v?.id, sub = str(v?.sub), label = str(v?.label) ?? "", kind = v?.kind;
  if (!isId(id) || !sub || (kind !== "app" && kind !== "web")) throw new Error("a device is {id, sub, kind, label}");
  const d: Device = { id, sub, kind, label, own: false };
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
  return { id, sub, key, label, own: false };
}

function station(v: any): Station {
  if (!isId(v?.key)) throw new Error("a station is {key, name}");
  return { key: v.key, name: str(v?.name) ?? "" };
}

/// Who signed: the member whose app device or passkey holds the key, with their role now, and whether it is their own
/// (an own one first: a key put in again under another device, someone else's, does not take its signatures away).
export function signer(s: LockState, sig: Pick<Sig, "key">, now: number | null): { sub: string; role: Role; passkey: boolean; own: boolean } | null {
  let found: { sub: string; role: Role; passkey: boolean; own: boolean } | null = null;
  for (const p of s.passkeys.values()) if (p.key === sig.key) found = withRole(s, p.sub, true, p.own) ?? found;
  for (const d of s.devices.values()) {
    if (d.sign_key === sig.key && d.kind === "app" && (d.exp === undefined || now === null || d.exp > now) && !found?.own) found = withRole(s, d.sub, false, d.own) ?? found;
  }
  return found;
}

function withRole(s: LockState, sub: string, passkey: boolean, own: boolean) {
  const m = s.members.get(sub);
  return m ? { sub, role: m.role, passkey, own } : null;
}

/// Whether a device or passkey of `sub` an entry signed by `by` puts in is the person's own: put in by an own one of
/// theirs, or by an owner or admin while they have had none that signs (`was`: the same device as it stood, which
/// stays own as long as it keeps its signing key, as a web page's renewed does).
function ownOf(s: LockState, sub: string, by: { sub: string; role: Role }, was?: { own: boolean; sign_key?: string }, key?: string): boolean {
  if (by.sub === sub) return true;
  if (was?.own && was.sign_key === key) return true;
  return manager(by.role) && !s.signed.has(sub);
}

const owners = (s: LockState) => [...s.members.values()].filter((m) => m.role === "owner").length;

/// The lock its first entry starts. Throws why it is not one.
export function genesis(e: Entry): LockState {
  if (e.kind !== "genesis" || e.seq !== 0 || e.prev !== null || e.v !== 1 || typeof e.ws !== "string" || !e.ws) throw new Error("a lock starts with its genesis");
  const b = e.body ?? {};
  const origins = Array.isArray(b.origins) ? b.origins.filter((o: unknown) => typeof o === "string") : [];
  const s: LockState = {
    ws: e.ws, seq: 0, head: entryHash(e), genesis: entryHash(e), origins, rp_id: str(b.rp_id) ?? "", cloud_keys: b.cloud_keys ?? null,
    members: new Map(), devices: new Map(), signKeys: new Map(), passkeys: new Map(), signed: new Set(), stations: new Map(), gateways: new Set(), disabled: false,
  };
  for (const m of arr(b.members)) s.members.set(member(m).sub, member(m));
  // (the genesis's devices and passkeys are the ones the owner found each person had: all their own)
  for (const d of arr(b.devices)) add(s, { ...device(d, 0), own: true, ...(str(b.owner) !== null ? { by: str(b.owner)! } : {}) });
  for (const p of arr(b.passkeys)) addPasskey(s, { ...passkey(p), own: true });
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
  if (d.sign_key !== undefined) {
    const had = s.signKeys.get(d.id) ?? [];
    if (!had.includes(d.sign_key)) s.signKeys.set(d.id, [...had, d.sign_key]);
    if (d.own) s.signed.add(d.sub);
  }
}

function addPasskey(s: LockState, p: Passkey) {
  s.passkeys.set(p.key, p);
  if (p.own) s.signed.add(p.sub);
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
  const s: LockState = { ...prev, seq: e.seq, head: hash, members: new Map(prev.members), devices: new Map(prev.devices), signKeys: new Map(prev.signKeys), passkeys: new Map(prev.passkeys), signed: new Set(prev.signed), stations: new Map(prev.stations), gateways: new Set(prev.gateways) };
  // Signed with a device or passkey someone else put in under the signer's name: it stays in the chain, as the rules
  // let its signer's role make it (so a lock with one from before keeps folding), and changes nothing.
  const followed = (): LockState => ({ ...prev, seq: e.seq, head: hash });
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
      // (made a member again, their first device is put in by an owner or admin as anyone's first is)
      s.signed.delete(sub!);
      break;
    }
    case "device": {
      const d = device(b, e.at);
      need(managing || d.sub === by.sub, "members add only their own devices");
      add(s, { ...d, by: by.sub, own: ownOf(prev, d.sub, by, prev.devices.get(d.id), d.sign_key) });
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
      addPasskey(s, { ...p, own: ownOf(prev, p.sub, by) });
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
  return by.own ? s : followed();
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

