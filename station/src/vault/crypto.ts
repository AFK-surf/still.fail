// The vault's formats (docs/vault.md, 实现约定): what is signed and by whom, the seal a key or secret is sent in, and
// whether a vault or item version may follow the one kept. The station holds only ciphertext and signatures; what it
// checks here is who may write what, so a station or cloud taken over cannot add itself to a vault. Pure; the same
// formats as client/core-ts/src/vault/crypto.ts, tested on the same values (test/fixtures/vault-vectors.json).
import { createCipheriv, createDecipheriv, createHash, createPrivateKey, createPublicKey, diffieHellman, hkdfSync, randomBytes, verify } from "node:crypto";
import { canonical, publicKey, type LockState } from "../cloud/lock.ts";

/// A signature as the lock's (no passkeys here): Ed25519 in hex, ES256 as base64url P1363.
export type Sig = { key: string; alg: "Ed25519" | "ES256"; sig: string };

/// A device's box key, signed by that device's lock `sign_key`.
export type BoxCert = { v: 1; ws: string; device: string; box: string; at: number; sig: Sig };
export type Vault = {
  v: 1; ws: string; id: string; seq: number; owner: string; name: string; members: string[]; epoch: number;
  keys: { cert: BoxCert; wrapped: string }[]; recovery?: string; at: number; sig: Sig;
  /// The longest grant its items are given for, where an item's listing says none (absent: any).
  lasts?: Scope;
  /// Deleted by its owner: its key sealed to no one (a new epoch), its items let go; it stays deleted. Kept as its
  /// last version so the stations that hold an older one are brought this one, not the older one back.
  deleted?: true;
};
/// How agents may ask for an item; `lasts`: the longest grant its owner gives (absent: as its vault says).
export type Listing = { name: string; kind: Kind; modes: Mode[]; hosts: string[]; env?: string; lasts?: Scope };
export type Item = {
  v: 1; ws: string; vault: string; id: string; version: number; epoch: number; deleted?: true; ct: string;
  listing?: Listing; at: number; sig: Sig;
};
export type Kind = "token" | "ssh_key" | "login" | "file" | "browser";
export type Mode = "proxy" | "ssh" | "env" | "file" | "browser";
/// How long a grant lasts: one use, an hour, or the chat until it is archived.
export type Scope = "once" | "hour" | "chat";
/// The scopes, shortest first.
export const SCOPES: Scope[] = ["once", "hour", "chat"];
/// Whether a grant may last as long as `scope` for an item that allows `lasts` at most (none: any).
export const allows = (lasts: Scope | null | undefined, scope: Scope): boolean => SCOPES.indexOf(scope) >= 0 && SCOPES.indexOf(scope) <= SCOPES.indexOf(lasts ?? "chat");
export type Request = {
  id: string; ws: string; vault: string; item: string; session: string; chat: string; mode: Mode; reason: string;
  command?: string; hosts?: string[]; box: string; at: number; status: "pending" | "granted" | "denied" | "expired";
  /// A request for an item of the plain library (`vault` is `plain`, no box): its owner's email, who decides it. A
  /// request to keep a secret (`save`): whose it is to be (whoever started the chat), who decides it.
  owner?: string;
  /// An agent asking to keep a secret in its owner's vault (secret_save, docs/vault.md agent 存入): the item as it is to
  /// be listed; `item` is the id it is written under, `vault` the one it is meant for (`plain` without security mode;
  /// empty while its owner has none). No box: nothing is granted to the station.
  save?: Save;
  /// A request to keep a secret in a vault: the secret's fields, sealed to each of its owner's devices set up (their
  /// box keys), when it was asked or since (`saveContext`). The device that approves it opens its own.
  sealed?: Sealed[];
  /// Another station of the workspace its commands run on (secret_use `station`, docs/vault.md 在另一台 station 上用):
  /// its id and name, said on the card; the secret is sent there for each command and kept there only while it runs.
  runOn?: { id: string; name: string };
  /// A sign-in's newer cookies, taken out of a chat's browser as an earlier grant of it ended (docs/vault.md 登录态
  /// 写回), sealed to each of its vault's members' devices set up (`saveContext` under its id): the app that grants this
  /// request writes them as the item's next version and grants those.
  renewal?: { id: string; sealed: Sealed[] };
};
/// What an agent asks to keep: the item's listing, and the fields of it that are not secret (a login's account name, an
/// SSH key's public half, a file's name), said on its card. `typed`: the secret is none the agent holds, but what the
/// person types in (a file: picks) on the card (nothing of it here until then, nothing sealed).
export type Save = { kind: Kind; name: string; modes: Mode[]; hosts: string[]; env?: string; username?: string; public_key?: string; filename?: string; typed?: true };
export type Sealed = { device: string; box: string; secret: string };
export type Grant = {
  v: 1; ws: string; request: string; vault: string; item: string; mode: Mode; hosts: string[]; scope: Scope; exp: number;
  secret: string; at: number; sig: Sig;
};
export type Deny = { v: 1; ws: string; request: string; at: number; sig: Sig };

/// What each kind of record is signed under.
export const TAG = {
  box: "stillfail-vault-box/1",
  vault: "stillfail-vault/1",
  item: "stillfail-vault-item/1",
  grant: "stillfail-vault-grant/1",
  deny: "stillfail-vault-deny/1",
} as const;

/// The seal's context for a vault key, wrapped to a device or to the recovery key.
export const keyContext = (ws: string, vault: string, epoch: number) => `stillfail-vault-key/1\0${ws}\0${vault}\0${epoch}`;
/// An item's ciphertext's additional data.
export const itemContext = (ws: string, vault: string, id: string, version: number, epoch: number) => `stillfail-vault-item/1\0${ws}\0${vault}\0${id}\0${version}\0${epoch}`;
/// The seal's context for a secret granted to one request.
export const grantContext = (ws: string, request: string) => `stillfail-vault-grant/1\0${ws}\0${request}`;
/// The seal's context for a secret an agent asks to keep, sealed to one of its owner's devices.
export const saveContext = (ws: string, request: string) => `stillfail-vault-save/1\0${ws}\0${request}`;

const sha256 = (b: Uint8Array | string) => createHash("sha256").update(b).digest();

/// The bytes a record's signature is over: its tag, a NUL, then the sha256 (32 raw bytes) of the record without `sig`.
export function signedBytes(o: Record<string, unknown>, tag: string): Buffer {
  const { sig: _, ...rest } = o;
  return Buffer.concat([Buffer.from(`${tag}\0`), sha256(canonical(rest))]);
}

/// Whether `o.sig` is its key's signature over `o` under `tag` (which key may sign is the caller's to check).
export function signedOk(o: { sig: Sig } & Record<string, unknown>, tag: string): boolean {
  try {
    const sig = o.sig;
    if (sig === null || typeof sig !== "object" || typeof sig.sig !== "string") return false;
    const { alg, key } = publicKey(sig.key);
    if (sig.alg !== alg) return false;
    const bytes = signedBytes(o, tag);
    if (alg === "Ed25519") return verify(null, bytes, key, Buffer.from(sig.sig, "hex"));
    return verify("sha256", bytes, { key, dsaEncoding: "ieee-p1363" }, Buffer.from(sig.sig, "base64url"));
  } catch {
    return false;
  }
}

// X25519 keys as raw 32 bytes, wrapped in the DER node:crypto takes.
const PKCS8_X25519 = Buffer.from("302e020100300506032b656e04220420", "hex");
const SPKI_X25519 = Buffer.from("302a300506032b656e032100", "hex");
const privateX25519 = (raw: Uint8Array) => createPrivateKey({ key: Buffer.concat([PKCS8_X25519, raw]), format: "der", type: "pkcs8" });
const publicX25519 = (raw: Uint8Array) => createPublicKey({ key: Buffer.concat([SPKI_X25519, raw]), format: "der", type: "spki" });
const rawPublic = (priv: Uint8Array) => Buffer.from(createPublicKey(privateX25519(priv)).export({ format: "jwk" }).x!, "base64url");

const BOX = /^x25519:[0-9a-f]{64}$/;
/// A box key's raw bytes from `x25519:<hex>`; throws when it is not one.
export function boxBytes(pub: string): Buffer {
  if (!BOX.test(pub)) throw new Error("not an x25519 key");
  return Buffer.from(pub.slice(7), "hex");
}

/// The public half of a raw X25519 private key, as `x25519:<hex>`.
export const boxPublic = (priv: Uint8Array) => `x25519:${rawPublic(priv).toString("hex")}`;

/// A fresh box key pair.
export function newBoxPair(): { pub: string; priv: Uint8Array } {
  const priv = new Uint8Array(randomBytes(32));
  return { pub: boxPublic(priv), priv };
}

const SEAL_INFO = "stillfail-vault-seal/1";
const NONCE0 = Buffer.alloc(12);

function sealKey(shared: Uint8Array, eph: Uint8Array, to: Uint8Array): Buffer {
  return Buffer.from(hkdfSync("sha256", shared, Buffer.concat([eph, to]), SEAL_INFO, 32));
}

/// `plain` sealed to the box key `pub` under `context`, with this ephemeral private key (tests pin it; else random).
export function sealWith(pub: string, plain: Uint8Array, context: string, eph: Uint8Array): string {
  const to = boxBytes(pub);
  const ephPub = rawPublic(eph);
  const shared = diffieHellman({ privateKey: privateX25519(eph), publicKey: publicX25519(to) });
  const c = createCipheriv("chacha20-poly1305", sealKey(shared, ephPub, to), NONCE0, { authTagLength: 16 });
  c.setAAD(Buffer.from(context), { plaintextLength: plain.length });
  return Buffer.concat([ephPub, c.update(plain), c.final(), c.getAuthTag()]).toString("base64url");
}

/// `plain` sealed to the box key `pub` under `context`: only that key's holder opens it, and only under that context.
export const seal = (pub: string, plain: Uint8Array, context: string): string => sealWith(pub, plain, context, randomBytes(32));

/// What `seal` sealed to `priv`'s public half under `context`; throws when it is not.
export function openSeal(priv: Uint8Array, sealed: string, context: string): Uint8Array {
  const b = Buffer.from(sealed, "base64url");
  if (b.length < 48) throw new Error("not a seal");
  const ephPub = b.subarray(0, 32), ct = b.subarray(32, b.length - 16), tag = b.subarray(b.length - 16);
  const shared = diffieHellman({ privateKey: privateX25519(priv), publicKey: publicX25519(ephPub) });
  const d = createDecipheriv("chacha20-poly1305", sealKey(shared, ephPub, rawPublic(priv)), NONCE0, { authTagLength: 16 });
  d.setAAD(Buffer.from(context), { plaintextLength: ct.length });
  d.setAuthTag(tag);
  return new Uint8Array(Buffer.concat([d.update(ct), d.final()]));
}

/// An item's ciphertext: a 12-byte nonce, then ChaCha20-Poly1305 under the vault key with `context` as additional data.
export function encryptWith(key: Uint8Array, plain: Uint8Array, context: string, nonce: Uint8Array): string {
  const c = createCipheriv("chacha20-poly1305", key, nonce, { authTagLength: 16 });
  c.setAAD(Buffer.from(context), { plaintextLength: plain.length });
  return Buffer.concat([nonce, c.update(plain), c.final(), c.getAuthTag()]).toString("base64url");
}

/// What `encryptWith` made; throws when the key or context is not its.
export function decrypt(key: Uint8Array, ct: string, context: string): Uint8Array {
  const b = Buffer.from(ct, "base64url");
  if (b.length < 28) throw new Error("not an item's ciphertext");
  const d = createDecipheriv("chacha20-poly1305", key, b.subarray(0, 12), { authTagLength: 16 });
  const body = b.subarray(12, b.length - 16);
  d.setAAD(Buffer.from(context), { plaintextLength: body.length });
  d.setAuthTag(b.subarray(b.length - 16));
  return new Uint8Array(Buffer.concat([d.update(body), d.final()]));
}

/// The recovery key pair from the 32 bytes the 24 recovery words hold.
export function recoveryPair(entropy: Uint8Array): { pub: string; priv: Uint8Array } {
  const priv = new Uint8Array(hkdfSync("sha256", entropy, Buffer.alloc(0), "stillfail-vault-recovery/1", 32));
  return { pub: boxPublic(priv), priv };
}

/// The member and lock device whose app `sign_key` is `keyId`; null when no app device in the lock signs with it.
export function signerOf(lock: LockState, keyId: string): { sub: string; device: string } | null {
  for (const d of lock.devices.values()) {
    if (d.kind === "app" && d.sign_key === keyId && lock.members.has(d.sub)) return { sub: d.sub, device: d.id };
  }
  return null;
}

const HEX32 = /^[0-9a-f]{64}$/;
const B64URL = /^[A-Za-z0-9_-]*$/;
const ULID = "[0-9A-HJKMNP-TV-Z]{26}";
export const VAULT_ID = new RegExp(`^v_${ULID}$`);
export const ITEM_ID = new RegExp(`^i_${ULID}$`);
const HOST = /^(\*\.)?[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*$/;
const ENV = /^[A-Za-z_][A-Za-z0-9_]*$/;
const KINDS: Kind[] = ["token", "ssh_key", "login", "file", "browser"];
const MODES: Mode[] = ["proxy", "ssh", "env", "file", "browser"];
const int = (v: unknown): v is number => Number.isSafeInteger(v) && (v as number) >= 0;
const text = (v: unknown, max = 200): v is string => typeof v === "string" && v.length <= max;
const b64 = (v: unknown, max: number): v is string => typeof v === "string" && v.length <= max && B64URL.test(v);
const sigShape = (s: any): s is Sig => s !== null && typeof s === "object" && typeof s.key === "string" && typeof s.sig === "string" && (s.alg === "Ed25519" || s.alg === "ES256");
const unique = (a: string[]) => new Set(a).size === a.length;

/// Why a box certificate is not a lock app device's for `ws`, or null when it is.
export function certOk(lock: LockState, cert: BoxCert): string | null {
  if (cert === null || typeof cert !== "object" || cert.v !== 1 || cert.ws !== lock.ws) return "a box certificate is {v: 1, ws, device, box, at, sig} of this workspace";
  if (!HEX32.test(cert.device) || !BOX.test(cert.box) || !int(cert.at) || !sigShape(cert.sig)) return "a box certificate is {v: 1, ws, device, box, at, sig} of this workspace";
  const d = lock.devices.get(cert.device);
  if (d === undefined || d.kind !== "app" || !lock.members.has(d.sub)) return "the box certificate's device is not an app device in the lock";
  if (d.sign_key !== cert.sig.key) return "a box certificate is signed by its own device's key";
  if (!signedOk(cert, TAG.box)) return "the box certificate's signature is invalid";
  return null;
}

/// Why `next` may not follow `prev` (null: it is the vault's first version), or null when it may. `copy`: a later
/// version brought from another station keeping the vault (docs/vault.md 副本), not necessarily the one right after:
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
  for (const k of v.keys) {
    if (k === null || typeof k !== "object" || !b64(k.wrapped, 200)) return "a key is {cert, wrapped}";
    const why = certOk(lock, k.cert);
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
