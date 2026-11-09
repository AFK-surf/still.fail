// The vault's rules as station/src/vault/crypto.ts had them in TypeScript, before rules/ (MoonBit) took them over:
// what station/test/rules-vault.test.ts checks the MoonBit against, until the proofs cover all of them.
import type { LockState } from "../src/cloud/lock.ts";
import { type BoxCert, type Item, type Kind, type Mode, type Sig, type Vault, SCOPES, TAG, ITEM_ID, VAULT_ID, signedOk } from "../src/vault/crypto.ts";

/// The member and lock device whose app `sign_key` is `keyId`; null when no app device in the lock signs with it, or
/// the one that does is not its person's own (one an admin put in under their name: cloud/lock.ts Device `own`).
export function signerOf(lock: LockState, keyId: string): { sub: string; device: string } | null {
  for (const d of lock.devices.values()) {
    if (d.kind === "app" && d.own && d.sign_key === keyId && lock.members.has(d.sub)) return { sub: d.sub, device: d.id };
  }
  return null;
}

const HEX32 = /^[0-9a-f]{64}$/;
const B64URL = /^[A-Za-z0-9_-]*$/;
const BOX = /^x25519:[0-9a-f]{64}$/;
const HOST = /^(\*\.)?[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$/;
const ENV = /^[A-Za-z_][A-Za-z0-9_]*$/;
const KINDS: Kind[] = ["token", "ssh_key", "login", "file", "browser"];
const MODES: Mode[] = ["proxy", "ssh", "env", "file", "browser"];
const int = (v: unknown): v is number => Number.isSafeInteger(v) && (v as number) >= 0;
const text = (v: unknown, max = 200): v is string => typeof v === "string" && v.length <= max;
const b64 = (v: unknown, max: number): v is string => typeof v === "string" && v.length <= max && B64URL.test(v);
const sigShape = (s: any): s is Sig => s !== null && typeof s === "object" && typeof s.key === "string" && typeof s.sig === "string" && (s.alg === "Ed25519" || s.alg === "ES256");
const unique = (a: string[]) => new Set(a).size === a.length;

/// Why a box certificate is not a lock app device's for `ws`, or null when it is: one of its person's own (an admin's
/// put in under their name is sealed nothing). `ever`: a vault's keys, signed by any signing key that device has had
/// in the lock, not only its current one (a device back in the lock under a new key, the app installed anew, keeps the
/// key sealed to it under its certificate from before; 2026-11-03); and a device that is no longer its person's own
/// keeps the key it was given, which the owner's own device signed into the vault (its new versions keep it).
export function certOk(lock: LockState, cert: BoxCert, ever = false): string | null {
  if (cert === null || typeof cert !== "object" || cert.v !== 1 || cert.ws !== lock.ws) return "a box certificate is {v: 1, ws, device, box, at, sig} of this workspace";
  if (!HEX32.test(cert.device) || !BOX.test(cert.box) || !int(cert.at) || !sigShape(cert.sig)) return "a box certificate is {v: 1, ws, device, box, at, sig} of this workspace";
  const d = lock.devices.get(cert.device);
  if (d === undefined || d.kind !== "app" || !lock.members.has(d.sub)) return "the box certificate's device is not an app device in the lock";
  if (!d.own && !ever) return "the box certificate's device was put in the lock by someone else, not its person";
  if (d.sign_key !== cert.sig.key && !(ever && (lock.signKeys.get(cert.device) ?? []).includes(cert.sig.key))) return "a box certificate is signed by its own device's key";
  if (!signedOk(cert, TAG.box)) return "the box certificate's signature is invalid";
  return null;
}

/// Why `next` may not follow `prev` (null: it is the vault's first version), or null when it may. `copy`: a later
/// version brought from another station keeping the vault ( 副本), not necessarily the one right after:
/// checked the same, but for its seq only being later than the one held (any, where none is).
export function vaultOk(lock: LockState, prev: Vault | null, next: Vault, copy = false): string | null {
  const v = next as any;
  if (v === null || typeof v !== "object" || v.v !== 1 || v.ws !== lock.ws) return "a vault is {v: 1, ws, …} of this workspace";
  if (typeof v.id !== "string" || !VAULT_ID.test(v.id)) return "a vault's id is v_<ULID>";
  if (!int(v.seq) || !int(v.epoch) || !int(v.at)) return "seq, epoch and at are whole numbers";
  if (!text(v.owner) || !v.owner || !text(v.name)) return "a vault has an owner and a name";
  if (!Array.isArray(v.members) || v.members.length > 256 || !v.members.every((m: unknown) => text(m) && m) || !unique(v.members)) return "members are distinct subs";
  if (!v.members.includes(v.owner)) return "the owner is a member";
  if (!Array.isArray(v.keys) || v.keys.length > 1024) return "keys is a list";
  if (v.recovery !== undefined && !b64(v.recovery, 200)) return "recovery is a seal";
  if (v.lasts !== undefined && !SCOPES.includes(v.lasts)) return "lasts is once, hour or chat";
  if (v.deleted !== undefined && (v.deleted !== true || v.keys.length > 0 || v.recovery !== undefined)) return "a deleted vault is sealed to no one";
  if (!sigShape(v.sig)) return "a vault is signed";
  if (prev === null) {
    if (v.seq !== 0 && !copy) return "a vault's first version is seq 0";
  } else {
    if (v.id !== prev.id) return "another vault";
    if (copy ? v.seq <= prev.seq : v.seq !== prev.seq + 1) return copy ? `a copy is later than seq ${prev.seq}` : `seq ${prev.seq + 1} follows ${prev.seq}`;
    if (v.owner !== prev.owner) return "a vault's owner does not change";
    if (prev.deleted && !v.deleted) return "a deleted vault stays deleted";
    if (v.epoch < prev.epoch) return "the epoch does not go back";
    const devices = new Set(v.keys.map((k: any) => k?.cert?.device));
    const gone = prev.members.some((m) => !v.members.includes(m)) || prev.keys.some((k) => !devices.has(k.cert.device));
    if (gone && v.epoch === prev.epoch) return "removing a member or device takes a new epoch (a new vault key)";
  }
  for (const m of v.members) if (!lock.members.has(m)) return `member ${m} is not in the lock`;
  const seen = new Set<string>();
  // (each key's certificate signed by a key its device has had in the lock, `ever`: the same on every station, whatever
  // version each held before, so a copy is taken wherever the version was)
  for (const k of v.keys) {
    if (k === null || typeof k !== "object" || !b64(k.wrapped, 200)) return "a key is {cert, wrapped}";
    const why = certOk(lock, k.cert, true);
    if (why) return why;
    if (seen.has(k.cert.device)) return "one key per device";
    seen.add(k.cert.device);
    if (!v.members.includes(lock.devices.get(k.cert.device)!.sub)) return "a key is for a member's device";
  }
  const by = signerOf(lock, v.sig.key);
  if (by === null || by.sub !== v.owner) return "a vault is signed by one of its owner's devices in the lock";
  if (!signedOk(v, TAG.vault)) return "the vault's signature is invalid";
  return null;
}

/// Why a listing is not one as a sign-in (kind and mode browser) must be, or null: a sign-in is given only into a
/// chat's browser, and only a sign-in is; its hosts are the sites it is for (each with its subdomains: no *.), one at least.
export function browserListingOk(l: { kind: Kind; modes: Mode[]; hosts: string[] }): string | null {
  const sign = l.kind === "browser";
  if (sign !== l.modes.includes("browser") || (sign && l.modes.length !== 1)) return "a sign-in (kind browser) is given into a chat's browser (modes: [\"browser\"]), and only a sign-in is";
  if (sign && (l.hosts.length === 0 || l.hosts.some((h) => h.startsWith("*.")))) return "a sign-in names the sites it is for (github.com: its subdomains with it)";
  return null;
}

/// Why a listing is not one, or null.
function listingOk(l: any): string | null {
  if (l === null || typeof l !== "object" || !text(l.name) || !KINDS.includes(l.kind)) return "a listing is {name, kind, modes, hosts, env?}";
  if (!Array.isArray(l.modes) || !l.modes.every((m: unknown) => MODES.includes(m as Mode)) || !unique(l.modes)) return "modes are proxy, ssh, env, file or browser";
  if (!Array.isArray(l.hosts) || l.hosts.length > 64 || !l.hosts.every((h: unknown) => text(h, 253) && HOST.test(h as string))) return "hosts are domain names (*.example.com allowed)";
  const why = browserListingOk(l);
  if (why) return why;
  if (l.env !== undefined && !(text(l.env, 100) && ENV.test(l.env))) return "env is a variable name";
  if (l.lasts !== undefined && !SCOPES.includes(l.lasts)) return "lasts is once, hour or chat";
  return null;
}

/// Why `next` may not follow `prev` (null: the item's first version) in `vault`, or null when it may. `copy`: a later
/// version brought from another station (as `vaultOk`'s), which may be one written under an earlier epoch of the vault.
export function itemOk(lock: LockState, vault: Vault, prev: Item | null, next: Item, copy = false): string | null {
  const i = next as any;
  if (i === null || typeof i !== "object" || i.v !== 1 || i.ws !== lock.ws || i.vault !== vault.id) return "an item is {v: 1, ws, vault, …} of this vault";
  if (typeof i.id !== "string" || !ITEM_ID.test(i.id)) return "an item's id is i_<ULID>";
  if (!int(i.version) || !int(i.epoch) || !int(i.at)) return "version, epoch and at are whole numbers";
  if (i.deleted !== undefined && i.deleted !== true) return "deleted is true or absent";
  if (!b64(i.ct, 1 << 20)) return "ct is base64url";
  if (i.deleted ? i.ct !== "" || i.listing !== undefined : i.ct.length < 38) return i.deleted ? "a deleted item has no ciphertext or listing" : "an item holds a ciphertext";
  if (i.listing !== undefined) {
    const why = listingOk(i.listing);
    if (why) return why;
  }
  if (!sigShape(i.sig)) return "an item is signed";
  if (i.epoch > vault.epoch || (!i.deleted && !copy && i.epoch !== vault.epoch)) return `an item is written under the vault's epoch ${vault.epoch}`;
  if (prev === null) {
    if (i.version !== 0 && !copy) return "an item's first version is 0";
  } else {
    if (i.id !== prev.id || i.vault !== prev.vault) return "another item";
    if (prev.deleted) return "the item was deleted";
    if (copy ? i.version <= prev.version : i.version !== prev.version + 1) return copy ? `a copy is later than version ${prev.version}` : `version ${prev.version + 1} follows ${prev.version}`;
  }
  const by = signerOf(lock, i.sig.key);
  if (by === null || !vault.members.includes(by.sub)) return "an item is signed by a vault member's device in the lock";
  if (!signedOk(i, TAG.item)) return "the item's signature is invalid";
  return null;
}
