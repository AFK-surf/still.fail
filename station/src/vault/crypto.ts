// The vault's formats (实现约定): what is signed and by whom, the seal a key or secret is sent in, and
// whether a vault or item version may follow the one kept. The station holds only ciphertext and signatures; what it
// checks here is who may write what, so a station or cloud taken over cannot add itself to a vault. Pure; the same
// formats as client/core-ts/src/vault/crypto.ts, tested on the same values (test/fixtures/vault-vectors.json).
import { createCipheriv, createDecipheriv, createHash, createPrivateKey, createPublicKey, diffieHellman, hkdfSync, randomBytes } from "node:crypto";
import { canonical, publicKey, signatureOk, type LockState } from "../cloud/lock.ts";
// @ts-ignore: the MoonBit build's JS, untyped
import * as rules from "../../../rules/js/rules.js";

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
/// How agents may ask for an item; `lasts`: the longest grant its owner gives (absent: as its vault says); `about`: what
/// it is and how it is used, in its owner's words (the item's notes, shown to agents with its name; never a secret).
export type Listing = { name: string; kind: Kind; modes: Mode[]; hosts: string[]; env?: string; lasts?: Scope; about?: string };
/// The most an item's `about` may be (its characters).
export const ABOUT_MOST = 2000;
export type Item = {
  v: 1; ws: string; vault: string; id: string; version: number; epoch: number; deleted?: true; ct: string;
  listing?: Listing; at: number; sig: Sig;
};
export type Kind = "token" | "ssh_key" | "login" | "file" | "browser";
export type Mode = "proxy" | "ssh" | "env" | "file" | "browser";
/// How long a grant lasts: one use, an hour, or the chat until it is archived.
export type Scope = "once" | "hour" | "chat";
export type Timeout = { kind: "idle" | "fixed"; seconds: number };
/// The scopes, shortest first.
export const SCOPES: Scope[] = ["once", "hour", "chat"];
/// Whether a grant may last as long as `scope` for an item that allows `lasts` at most (none: any).
export const allows = (lasts: Scope | null | undefined, scope: Scope): boolean => SCOPES.indexOf(scope) >= 0 && SCOPES.indexOf(scope) <= SCOPES.indexOf(lasts ?? "chat");
export type Request = {
  id: string; ws: string; vault: string; item: string; session: string; chat: string; mode: Mode; reason: string;
  timeout?: Timeout;
  command?: string; hosts?: string[]; box: string; at: number;
  /// `withdrawn`: taken back by the agent that asked (secret_cancel) before anyone decided it.
  status: "pending" | "granted" | "denied" | "expired" | "withdrawn";
  /// A request for an item of the plain library (`vault` is `plain`, no box): its owner's email, who decides it. A
  /// request to keep a secret (`save`): whose it is to be (whoever started the chat), who decides it.
  owner?: string;
  /// An agent asking to keep a secret in its owner's vault (secret_save agent 存入): the item as it is to
  /// be listed; `item` is the id it is written under, `vault` the one it is meant for (`plain` without security mode;
  /// empty while its owner has none). No box: nothing is granted to the station.
  save?: Save;
  /// A request to keep a secret in a vault: the secret's fields, sealed to each of its owner's devices set up (their
  /// box keys), when it was asked or since (`saveContext`). The device that approves it opens its own.
  sealed?: Sealed[];
  /// Another station of the workspace its commands run on (secret_use `station` 在另一台 station 上用):
  /// its id and name, said on the card; the secret is sent there for each command and kept there only while it runs.
  runOn?: { id: string; name: string };
  /// A sign-in's newer cookies, taken out of a chat's browser as an earlier grant of it ended ( 登录态
  /// 写回), sealed to each of its vault's members' devices set up (`saveContext` under its id): the app that grants this
  /// request writes them as the item's next version and grants those.
  renewal?: { id: string; sealed: Sealed[] };
  /// An agent asking to rename an item or to say what it is (secret_describe 改名和说明): its name and about as they
  /// are to be, and as they were when asked. Granted, the item's next version says so: written by the app that approves
  /// it (a vault's), or here as its owner approves it (the plain library's). Never a grant of the item.
  describe?: Describe;
  /// An agent asking to delete an item (secret_delete 删除): its name when asked. Granted, the item is deleted: by the
  /// app that approves it (a vault's, its device signing the deleted version), or here as its owner approves it (the
  /// plain library's). Never a grant of the item.
  remove?: { name: string };
};
export type Describe = { name: string; about: string; was: { name: string; about: string } };
/// What an agent asks to keep: the item's listing, and the fields of it that are not secret (a login's account name, an
/// SSH key's public half, a file's name), said on its card. `typed`: the secret is none the agent holds, but what the
/// person types in (a file: picks) on the card (nothing of it here until then, nothing sealed); with `oauth`, a token the
/// person signs in to that service for on the card instead (client/core-ts/src/vault/oauth.ts: `slack`).
export type Save = { kind: Kind; name: string; modes: Mode[]; hosts: string[]; env?: string; username?: string; public_key?: string; filename?: string; typed?: true; oauth?: string; about?: string };
export type Sealed = { device: string; box: string; secret: string };
export type Grant = {
  v: 1; ws: string; request: string; vault: string; item: string; mode: Mode; hosts: string[]; scope: Scope; exp: number; timeout?: Timeout;
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
    return sigOver(o.sig, signedBytes(o, tag));
  } catch {
    return false;
  }
}

/// Whether `sig` is its key's over `bytes`.
function sigOver(sig: Sig, bytes: Uint8Array): boolean {
  try {
    if (sig === null || typeof sig !== "object" || typeof sig.sig !== "string") return false;
    const { alg } = publicKey(sig.key);
    if (sig.alg !== alg) return false;
    return signatureOk(sig.key, Buffer.from(sig.sig, alg === "Ed25519" ? "hex" : "base64url"), Buffer.from(bytes));
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

// The rules themselves (who may write which vault or item version, which box certificates count) are rules/'s, in
// MoonBit: station and devices check by the same.
const rulesCrypto = {
  recordSigValid: (sig: Sig, tag: string, text: string) => sigOver(sig, Buffer.concat([Buffer.from(`${tag}\0`), sha256(text)])),
};

/// The member and lock device whose app `sign_key` is `keyId`; null when no app device in the lock signs with it, or
/// the one that does is not its person's own (one an admin put in under their name: cloud/lock.ts Device `own`).
export function signerOf(lock: LockState, keyId: string): { sub: string; device: string } | null {
  return rules.signer_of_js(lock, keyId);
}

const ULID = "[0-9A-HJKMNP-TV-Z]{26}";
export const VAULT_ID = new RegExp(`^v_${ULID}$`);
export const ITEM_ID = new RegExp(`^i_${ULID}$`);

/// Why a box certificate is not a lock app device's for `ws`, or null when it is: one of its person's own (an admin's
/// put in under their name is sealed nothing). `ever`: a vault's keys, signed by any signing key that device has had
/// in the lock, not only its current one (a device back in the lock under a new key, the app installed anew, keeps the
/// key sealed to it under its certificate from before; 2026-11-03); and a device that is no longer its person's own
/// keeps the key it was given, which the owner's own device signed into the vault (its new versions keep it).
export function certOk(lock: LockState, cert: BoxCert, ever = false): string | null {
  // The certificate rule reads only this device, its member and its own signing-key history. Give the rules bridge
  // just those entries; otherwise it copies every member and device before checking each individual certificate.
  const id = typeof cert?.device === "string" ? cert.device : null;
  const device = id === null ? undefined : lock.devices.get(id);
  const member = device === undefined ? undefined : lock.members.get(device.sub);
  // A newly published certificate must use the current key; historical keys matter only for `ever`.
  const keys = !ever || id === null ? undefined : lock.signKeys.get(id);
  return rules.cert_ok_js({
    ws: lock.ws,
    devices: new Map(id !== null && device !== undefined ? [[id, device]] : []),
    members: new Map(device !== undefined && lock.members.has(device.sub) ? [[device.sub, member]] : []),
    signKeys: new Map(id !== null && keys !== undefined ? [[id, keys]] : []),
  }, cert, ever, rulesCrypto);
}

/// Why `next` may not follow `prev` (null: it is the vault's first version), or null when it may. `copy`: a later
/// version brought from another station keeping the vault ( 副本), not necessarily the one right after:
/// checked the same, but for its seq only being later than the one held (any, where none is).
export function vaultOk(lock: LockState, prev: Vault | null, next: Vault, copy = false): string | null {
  return rules.vault_ok_js(lock, prev, next, copy, rulesCrypto);
}

/// Why a listing is not one as a sign-in (kind and mode browser) must be, or null: a sign-in is given only into a
/// chat's browser, and only a sign-in is; its hosts are the sites it is for (each with its subdomains: no *.), one at least.
export function browserListingOk(l: { kind: Kind; modes: Mode[]; hosts: string[] }): string | null {
  return rules.browser_listing_ok_js(l);
}

/// Why `next` may not follow `prev` (null: the item's first version) in `vault`, or null when it may. `copy`: a later
/// version brought from another station (as `vaultOk`'s), which may be one written under an earlier epoch of the vault.
export function itemOk(lock: LockState, vault: Vault, prev: Item | null, next: Item, copy = false): string | null {
  return rules.item_ok_js(lock, vault, prev, next, copy, rulesCrypto);
}

/// Which of two versions of a vault every station and device keeps (two written on two stations at once): the later; of
/// one seq, the one that deletes it, then the one under the later key, then the greater text (rules/src/history
/// `supersedes`, proved). `itemSupersedes`: an item's, by its version.
export const vaultSupersedes = (a: Vault, b: Vault): boolean => rules.vault_supersedes_js(a, b);
export const itemSupersedes = (a: Item, b: Item): boolean => rules.item_supersedes_js(a, b);
