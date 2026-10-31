// The vault's formats on the device (docs/vault.md, 实现约定): what is signed and how, the seal a key or secret is sent
// in, an item's ciphertext, the recovery words. The stations check the same (station/src/vault/crypto.ts, on node's
// crypto); both are tested on the same values (station/test/fixtures/vault-vectors.json).
import { chacha20poly1305 } from "@noble/ciphers/chacha.js";
import { x25519 } from "@noble/curves/ed25519.js";
import { hkdf } from "@noble/hashes/hkdf.js";
import { sha256 } from "@noble/hashes/sha2.js";
import { wordlist } from "@scure/bip39/wordlists/english.js";
import { CoreError } from "../error.ts";
import { canonical } from "../lock.ts";
import { ed25519Ok, p256Ok } from "./verified.ts";
import { base64url, hex, utf8 } from "../util.ts";

export type Sig = { key: string; alg: "Ed25519" | "ES256"; sig: string };
/// A device's box key, signed by that device's lock `sign_key`; `recovery`: its person's recovery key (what any of
/// their devices seals a new vault's key to).
export type BoxCert = { v: 1; ws: string; device: string; box: string; recovery?: string; at: number; sig: Sig };
export type Vault = {
  v: 1; ws: string; id: string; seq: number; owner: string; name: string; members: string[]; epoch: number;
  keys: { cert: BoxCert; wrapped: string }[]; recovery?: string; at: number; sig: Sig;
  /// The longest grant its items are given for, where an item's listing says none (absent: any).
  lasts?: Scope;
  /// Deleted by its owner (`vault.delete`): sealed to no one under a new epoch, its items gone; it stays deleted.
  deleted?: true;
};
export type Kind = "token" | "ssh_key" | "login" | "file";
export type Mode = "proxy" | "ssh" | "env" | "file";
/// How long a grant lasts: one use, an hour, or the chat until it is archived.
export type Scope = "once" | "hour" | "chat";
/// The scopes, shortest first.
export const SCOPES: Scope[] = ["once", "hour", "chat"];
/// How agents may ask for an item; `lasts`: the longest grant its owner gives (absent: as its vault says).
export type Listing = { name: string; kind: Kind; modes: Mode[]; hosts: string[]; env?: string; lasts?: Scope };
/// Whether a grant may last as long as `scope` for an item that allows `lasts` at most (none: any).
export const allows = (lasts: Scope | null | undefined, scope: Scope): boolean =>
  SCOPES.indexOf(scope) >= 0 && SCOPES.indexOf(scope) <= SCOPES.indexOf(lasts ?? "chat");
export type Item = {
  v: 1; ws: string; vault: string; id: string; version: number; epoch: number; deleted?: true; ct: string; listing?: Listing; at: number; sig: Sig;
};
/// What an item holds, sealed: `fields` by kind (token `{value}`, ssh_key `{private_key, public_key}`, login
/// `{username, password, totp?}`, file `{content (its bytes in base64), filename?}`).
export type Plain = { kind: Kind; name: string; fields: Record<string, string>; domains: string[]; notes: string };
export type Request = {
  id: string; ws: string; vault: string; item: string; session: string; chat: string; mode: Mode; reason: string;
  command?: string; hosts?: string[]; box: string; at: number; status: "pending" | "granted" | "denied" | "expired";
  /// The plain library's item's owner, or whom a secret to keep is for (their email).
  owner?: string;
  /// An agent asking to keep a secret (secret_save, docs/vault.md agent 存入): the item as it is to be listed, written
  /// under `item` into `vault` (empty: one of the person's own, made when they have none).
  save?: Save;
  /// Its fields, sealed by the station that asked to each of the person's devices set up (`saveContext`).
  sealed?: { device: string; box: string; secret: string }[];
};
/// `typed`: its secret is what the person types in on its card (nothing sealed: the app writes what was typed).
export type Save = { kind: Kind; name: string; modes: Mode[]; hosts: string[]; env?: string; username?: string; public_key?: string; filename?: string; typed?: true };
export type Grant = { v: 1; ws: string; request: string; vault: string; item: string; mode: Mode; hosts: string[]; scope: Scope; exp: number; secret: string; at: number; sig: Sig };
export type Deny = { v: 1; ws: string; request: string; at: number; sig: Sig };

export const TAG = {
  box: "stillfail-vault-box/1",
  vault: "stillfail-vault/1",
  item: "stillfail-vault-item/1",
  grant: "stillfail-vault-grant/1",
  deny: "stillfail-vault-deny/1",
} as const;

export const keyContext = (ws: string, vault: string, epoch: number) => `stillfail-vault-key/1\0${ws}\0${vault}\0${epoch}`;
export const itemContext = (ws: string, vault: string, id: string, version: number, epoch: number) => `stillfail-vault-item/1\0${ws}\0${vault}\0${id}\0${version}\0${epoch}`;
export const grantContext = (ws: string, request: string) => `stillfail-vault-grant/1\0${ws}\0${request}`;
/// The seal's context for a secret an agent asks to keep, sealed to one of its owner's devices.
export const saveContext = (ws: string, request: string) => `stillfail-vault-save/1\0${ws}\0${request}`;

const concat = (...parts: Uint8Array[]) => {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let at = 0;
  for (const p of parts) {
    out.set(p, at);
    at += p.length;
  }
  return out;
};
const unhex = (h: string) => Uint8Array.from(h.match(/../g) ?? [], (b) => parseInt(b, 16));

/// base64url without padding, as the formats write bytes; null when it is not.
export function fromB64url(text: string): Uint8Array | null {
  if (!/^[A-Za-z0-9_-]*$/.test(text) || text.length % 4 === 1) return null;
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
  const out = new Uint8Array(Math.floor((text.length * 3) / 4));
  let bits = 0, value = 0, o = 0;
  for (let i = 0; i < text.length; i++) {
    value = (value << 6) | alphabet.indexOf(text[i]!);
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      out[o++] = (value >> bits) & 255;
    }
  }
  return out;
}

const b64 = (text: string, what: string): Uint8Array => {
  const b = fromB64url(text);
  if (b === null) throw new CoreError("vault_invalid", `${what} is not base64url`);
  return b;
};

/// The bytes a record's signature is over: its tag, a NUL, then the sha256 (32 raw bytes) of the record without `sig`.
export function signedBytes(o: Record<string, unknown>, tag: string): Uint8Array {
  const { sig: _, ...rest } = o;
  return concat(utf8(`${tag}\0`), sha256(utf8(canonical(rest))));
}

/// Whether `o.sig` is its key's signature over `o` under `tag` (which key may sign is the caller's to check): checked once
/// on this device for those bytes (verified.ts).
export function signedOk(o: { sig: Sig } & Record<string, unknown>, tag: string): boolean {
  try {
    const sig = o.sig;
    if (sig === null || typeof sig !== "object" || typeof sig.key !== "string" || typeof sig.sig !== "string") return false;
    const bytes = signedBytes(o, tag);
    if (sig.alg === "Ed25519" && /^ed25519:[0-9a-f]{64}$/.test(sig.key) && /^[0-9a-f]{128}$/.test(sig.sig)) return ed25519Ok(unhex(sig.sig), bytes, unhex(sig.key.slice(8)));
    if (sig.alg === "ES256" && sig.key.startsWith("p256:")) {
      const point = fromB64url(sig.key.slice(5)), s = fromB64url(sig.sig);
      return point !== null && s !== null && point.length === 65 && p256Ok(s, bytes, point);
    }
    return false;
  } catch {
    return false;
  }
}

export { verifies } from "./verified.ts";

/// A record signed under `tag` by an Ed25519 key, signing the bytes it is given (the lock's `Signer`).
export function sign<T extends Record<string, unknown>>(o: T, tag: string, signer: { id: string; signBytes(bytes: Uint8Array): string }): T & { sig: Sig } {
  return { ...o, sig: { key: signer.id, alg: "Ed25519", sig: signer.signBytes(signedBytes(o, tag)) } };
}

const BOX = /^x25519:[0-9a-f]{64}$/;
export function boxBytes(pub: string): Uint8Array {
  if (!BOX.test(pub)) throw new CoreError("vault_invalid", "not an x25519 key");
  return unhex(pub.slice(7));
}

/// The public half of a raw X25519 private key, as `x25519:<hex>`.
export const boxPublic = (priv: Uint8Array) => `x25519:${hex(x25519.getPublicKey(priv))}`;

const SEAL_INFO = utf8("stillfail-vault-seal/1");
const NONCE0 = new Uint8Array(12);

/// `plain` sealed to the box key `pub` under `context`, with this ephemeral private key (32 random bytes).
export function sealWith(pub: string, plain: Uint8Array, context: string, eph: Uint8Array): string {
  const to = boxBytes(pub);
  const ephPub = x25519.getPublicKey(eph);
  const key = hkdf(sha256, x25519.getSharedSecret(eph, to), concat(ephPub, to), SEAL_INFO, 32);
  return base64url(concat(ephPub, chacha20poly1305(key, NONCE0, utf8(context)).encrypt(plain)));
}

/// What `sealWith` sealed to `priv`'s public half under `context`; throws when it is not.
export function openSeal(priv: Uint8Array, sealed: string, context: string): Uint8Array {
  const b = b64(sealed, "a seal");
  if (b.length < 48) throw new CoreError("vault_invalid", "not a seal");
  const ephPub = b.subarray(0, 32);
  const key = hkdf(sha256, x25519.getSharedSecret(priv, ephPub), concat(ephPub, x25519.getPublicKey(priv)), SEAL_INFO, 32);
  try {
    return chacha20poly1305(key, NONCE0, utf8(context)).decrypt(b.subarray(32));
  } catch {
    throw new CoreError("vault_unsealed", "this key does not open it");
  }
}

/// An item's ciphertext: a 12-byte nonce, then ChaCha20-Poly1305 under the vault key with `context` as additional data.
export function encryptWith(key: Uint8Array, plain: Uint8Array, context: string, nonce: Uint8Array): string {
  return base64url(concat(nonce, chacha20poly1305(key, nonce, utf8(context)).encrypt(plain)));
}

export function decrypt(key: Uint8Array, ct: string, context: string): Uint8Array {
  const b = b64(ct, "an item's ciphertext");
  if (b.length < 28) throw new CoreError("vault_invalid", "not an item's ciphertext");
  try {
    return chacha20poly1305(key, b.subarray(0, 12), utf8(context)).decrypt(b.subarray(12));
  } catch {
    throw new CoreError("vault_unsealed", "the vault's key does not open this item");
  }
}

/// The recovery key pair from the 32 bytes the recovery words hold.
export function recoveryPair(entropy: Uint8Array): { pub: string; priv: Uint8Array } {
  const priv = hkdf(sha256, entropy, new Uint8Array(0), utf8("stillfail-vault-recovery/1"), 32);
  return { pub: boxPublic(priv), priv };
}

/// 32 bytes as BIP-39's 24 English words (the last carries 8 bits of their sha256).
export function toWords(entropy: Uint8Array): string {
  if (entropy.length !== 32) throw new CoreError("vault_invalid", "recovery words hold 32 bytes");
  const bits = concat(entropy, sha256(entropy).subarray(0, 1));
  const out: string[] = [];
  for (let i = 0; i < 24; i++) {
    let n = 0;
    for (let b = i * 11; b < i * 11 + 11; b++) n = (n << 1) | ((bits[b >> 3]! >> (7 - (b & 7))) & 1);
    out.push(wordlist[n]!);
  }
  return out.join(" ");
}

/// The 32 bytes 24 recovery words hold; throws when a word is not one, or they do not add up (their checksum).
export function fromWords(words: string): Uint8Array {
  const list = words.trim().split(/\s+/).map((w) => w.replace(/[A-Z]/g, (c) => String.fromCharCode(c.charCodeAt(0) + 32)));
  if (list.length !== 24) throw new CoreError("vault_words", "the recovery words are 24");
  const bits = new Uint8Array(33);
  list.forEach((w, i) => {
    const n = wordlist.indexOf(w);
    if (n < 0) throw new CoreError("vault_words", `“${w}” is not one of the recovery words`);
    for (let b = 0; b < 11; b++) {
      const at = i * 11 + b;
      if ((n >> (10 - b)) & 1) bits[at >> 3] = bits[at >> 3]! | (1 << (7 - (at & 7)));
    }
  });
  const entropy = bits.subarray(0, 32);
  if (sha256(entropy)[0] !== bits[32]) throw new CoreError("vault_words", "the recovery words do not add up: one is wrong or out of place");
  return entropy.slice();
}
