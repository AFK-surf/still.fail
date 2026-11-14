// The workspace lock on this device: what the device signs and how it says which device it
// is. The stations decide (station/src/cloud/lock.ts); the cloud only keeps and carries the chain. The hashing is the
// same forms as the stations' and the cloud's (lock-form.ts), tested on the same values (test/lock.test.ts).
import { ed25519 } from "@noble/curves/ed25519.js";
import { Effect } from "effect";
import { CoreError, asCoreError } from "./error.ts";
import type { Host } from "./host.ts";
// (still.fail's words over the base's own, which error.ts says: scripts/base.ts; the vault's files, which load this
// one, have them by it)
import "./i18n.ts";
import * as form from "./lock-form.ts";
import { hex, sha256, utf8 } from "./util.ts";

export type Sig = { key: string; alg: "Ed25519"; sig: string };
export type Entry = { v: 1; ws: string; seq: number; prev: string | null; at: number; kind: string; body: unknown; sig: Sig };
/// How far a lock goes: its last entry's number and hash, and its genesis's hash (which lock it is).
export type Head = { seq: number; hash: string; genesis: string };
/// What a connection says of the device in its hello: its base key, and that key's signature for this endpoint;
/// `entries`, what put it in the lock lately, for a station that has not heard of it yet (views/lock.ts `carried`).
/// `person`: the chain of the person's own lock, where its member bound it in the workspace's (views/lock.ts
/// `carriedPerson`).
/// `kind`, `label`: what the device is, for the station to list it for a lock's owner (station/src/mesh/seen-devices.ts).
export type LockClaim = { device: string; proof: string; kind?: string; label?: string; entries?: Entry[]; person?: Entry[] };
/// How much of the locks a hello brings at most (a station reads its first line up to 16 KiB).
export const CARRY_BYTES = 12 * 1024;

/// JSON with object keys sorted, no space: what is hashed. Only integers, strings, booleans, null, arrays, objects.
export function canonical(v: unknown): string {
  return form.canonical(v, CoreError.invalid);
}

/// An entry's hash (hex): of everything but its signature.
export function entryHash(e: Omit<Entry, "sig">): string {
  return hex(sha256(utf8(form.entryText(e, CoreError.invalid))));
}

const concat = (a: Uint8Array, b: Uint8Array) => {
  const out = new Uint8Array(a.length + b.length);
  out.set(a, 0);
  out.set(b, a.length);
  return out;
};
const unhex = (h: string) => Uint8Array.from(h.match(/../g) ?? [], (b) => parseInt(b, 16));

/// What a signing key signs for an entry: a tag, then the hash's bytes.
export const signedBytes = (hash: string) => concat(utf8("stillfail-lock/1 sig\0"), unhex(hash));

/// What a device's base key signs to say an endpoint is its own, in a workspace.
export const endpointBytes = (ws: string, endpoint: string) => utf8(`stillfail-lock-endpoint/1\0${ws}\0${endpoint}`);

/// A device's short code: what a person compares, on the new device and where it is confirmed.
export function shortCode(base: string): string {
  return form.shortCodeOf(sha256(utf8(form.codeText(base))));
}

/// The device's claim for an endpoint, signed with its base key (the mesh's device key, an Ed25519 seed): by the host
/// where it signs (Host.ed25519Sign: a native app's shell), else here.
export function lockClaim(secret: Uint8Array, ws: string, endpoint: string, host?: Pick<Host, "ed25519Sign">): LockClaim {
  const message = endpointBytes(ws, endpoint);
  const signed = host?.ed25519Sign?.(secret, message);
  if (signed) return { device: hex(signed.publicKey), proof: hex(signed.signature) };
  return { device: hex(ed25519.getPublicKey(secret)), proof: hex(ed25519.sign(message, secret)) };
}

/// What signs with a device's base key and gives that key's public half: the mesh (mesh.ts `Mesh.sign`).
export type DeviceSigns = { sign(message: Uint8Array): { publicKey: Uint8Array; signature: Uint8Array } };

/// The device's claim for an endpoint (`lockClaim`), signed by what holds its base key.
export function claimBy(device: DeviceSigns, ws: string, endpoint: string): LockClaim {
  const signed = device.sign(endpointBytes(ws, endpoint));
  return { device: hex(signed.publicKey), proof: hex(signed.signature) };
}

/// This app's signing key (`lock-signer`): an Ed25519 seed kept by the app, apart from the device key. Only an app keeps
/// one (`Host.appKeys`): a web page's code is still.fail cloud's, so what it keeps signs nothing. A host that seals
/// values (`Host.secureSet`) keeps it so, read without asking the person (`user: false`); one kept as a plain file by
/// an app from before goes in there the first time it is read, and the file goes. A host without keeps the file.
export class Signer {
  static readonly KEY = "lock-signer";
  readonly #seed: Uint8Array;
  /// `ed25519:<hex>`, as lock entries name it.
  readonly id: string;

  private constructor(seed: Uint8Array) {
    this.#seed = seed;
    this.id = `ed25519:${hex(ed25519.getPublicKey(seed))}`;
  }

  /// The kept one; null when there is none (or this is no app).
  static load(host: Host): Effect.Effect<Signer | null, CoreError> {
    if (!host.appKeys) return Effect.succeed(null);
    const seedOf = (v: Uint8Array | null) => (v !== null && v.length === 32 ? v : null);
    const plain = Effect.map(Effect.mapError(host.storageGet(Signer.KEY), asCoreError), seedOf);
    const { secureGet, secureSet } = host;
    if (!secureGet || !secureSet) return Effect.map(plain, (seed) => (seed ? new Signer(seed) : null));
    const sealed = Effect.map(Effect.mapError(secureGet.call(host, Signer.KEY, { user: false }), asCoreError), seedOf);
    return Effect.gen(function* () {
      const kept = yield* sealed;
      if (kept) {
        // A move cut short after sealing leaves the file: it goes now.
        yield* Effect.mapError(host.storageDelete(Signer.KEY), asCoreError);
        return new Signer(kept);
      }
      const old = yield* plain;
      if (!old) return null;
      // Sealed, and read back the same, before the file goes: a failure on the way leaves the file as it was.
      yield* Effect.mapError(secureSet.call(host, Signer.KEY, old, { user: false }), asCoreError);
      const back = yield* sealed;
      if (!back || hex(back) !== hex(old)) return yield* Effect.fail(new CoreError("host", "the lock's signing key did not read back as it was sealed"));
      yield* Effect.mapError(host.storageDelete(Signer.KEY), asCoreError);
      return new Signer(old);
    });
  }

  /// The one an earlier install kept whose id is `id` (`Host.securePast`), kept again as this one: null when none is.
  static recover(host: Host, id: string): Effect.Effect<Signer | null, CoreError> {
    return Effect.gen(function* () {
      if (!host.appKeys || !host.securePast || !host.secureSet) return null;
      const past = yield* Effect.mapError(host.securePast(Signer.KEY), asCoreError);
      const seed = past.find((v) => v.length === 32 && new Signer(v).id === id);
      if (!seed) return null;
      yield* Effect.mapError(host.secureSet(Signer.KEY, seed, { user: false }), asCoreError);
      return new Signer(seed);
    });
  }

  /// The kept one, made the first time (sealed where the host seals).
  static make(host: Host): Effect.Effect<Signer, CoreError> {
    return Effect.gen(function* () {
      if (!host.appKeys) return yield* Effect.fail(new CoreError("lock_no_signer", "a web page signs nothing for the lock: use the desktop or Android app, or a passkey"));
      const had = yield* Signer.load(host);
      if (had) return had;
      const seed = new Uint8Array(32);
      host.randomBytes(seed);
      const kept = host.secureSet ? host.secureSet(Signer.KEY, seed, { user: false }) : host.storageSet(Signer.KEY, seed);
      yield* Effect.mapError(kept, asCoreError);
      return new Signer(seed);
    });
  }

  /// An entry, signed.
  sign(e: Omit<Entry, "sig">): Entry {
    const hash = entryHash(e);
    return { ...e, sig: { key: this.id, alg: "Ed25519", sig: hex(ed25519.sign(signedBytes(hash), this.#seed)) } };
  }

  /// Other bytes it vouches for (the vault's records, vault/crypto.ts `sign`): the signature in hex.
  signBytes(bytes: Uint8Array): string {
    return hex(ed25519.sign(bytes, this.#seed));
  }
}

/// The entry that follows `head` (the genesis when there is none), unsigned.
export function next(ws: string, head: Head | null, at: number, kind: string, body: unknown): Omit<Entry, "sig"> {
  return { v: 1, ws, seq: head === null ? 0 : head.seq + 1, prev: head === null ? null : head.hash, at: Math.floor(at), kind, body };
}

/// A head as a station or the cloud said it.
export function readHead(v: unknown): Head | null {
  const h = v as Head | null;
  return h !== null && typeof h === "object" && Number.isSafeInteger(h.seq) && typeof h.hash === "string" ? { seq: h.seq, hash: h.hash, genesis: typeof h.genesis === "string" ? h.genesis : "" } : null;
}

/// How long a device added from a web page lasts.
export const WEB_DEVICE_SECS = 30 * 86400;
