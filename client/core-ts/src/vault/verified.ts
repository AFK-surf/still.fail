// Signatures checked once on this device: whether a key signed some bytes never changes, so what a check found is kept
// (in memory, and in the device's storage: `keepVerified`) by the key, the signature and the bytes, and asked again
// is answered as it was. A P-256 signature checked in JS takes a phone hundreds of ms in Hermes: the lock's entries and a
// device's certificate checked again as each chat with vault cards was made, and again each time the app started, were
// 0.87 s of opening one (2026-10-31).
import { ed25519 } from "@noble/curves/ed25519.js";
import { p256 } from "@noble/curves/nist.js";
import { sha256 } from "@noble/hashes/sha2.js";
import { hex, utf8 } from "../util.ts";

/// Where what was found is kept past this run (the device's storage), set as the core starts.
export type Kept = { get(key: string): unknown; put(key: string, ok: boolean): void };
let kept: Kept | null = null;
const here = new Map<string, boolean>();
const HERE_MOST = 4096;

/// How many signatures were checked in fact (not answered as checked before).
export const verifies = { count: 0 };

export function keepVerified(k: Kept | null): void {
  kept = k;
}

/// What was found this run let go of, as a run anew has none (what is kept stays): tests'.
export function forgetVerifiedHere(): void {
  here.clear();
}

/// Whether `alg`'s signature `sig` by `pub` over `msg` is good, checked once (`check`) for that signature over those bytes.
function once(alg: string, pub: Uint8Array, sig: Uint8Array, msg: Uint8Array, check: () => boolean): boolean {
  const key = hex(sha256(utf8(`${alg}\u0000${hex(pub)}\u0000${hex(sig)}\u0000${hex(sha256(msg))}`)));
  const known = here.get(key) ?? kept?.get(key);
  if (typeof known === "boolean") {
    here.set(key, known);
    return known;
  }
  const ok = check();
  verifies.count++;
  if (here.size >= HERE_MOST) here.delete(here.keys().next().value!);
  here.set(key, ok);
  kept?.put(key, ok);
  return ok;
}

export function ed25519Ok(sig: Uint8Array, msg: Uint8Array, pub: Uint8Array): boolean {
  return once("Ed25519", pub, sig, msg, () => ed25519.verify(sig, msg, pub));
}

/// A P-256 signature (`der`: DER-encoded, as WebAuthn gives it; else raw r‖s) over `msg`, hashed as it is checked.
export function p256Ok(sig: Uint8Array, msg: Uint8Array, pub: Uint8Array, der = false): boolean {
  return once(der ? "ES256-der" : "ES256", pub, sig, msg, () => p256.verify(sig, msg, pub, der ? { prehash: true, lowS: false, format: "der" } : { prehash: true, lowS: false }));
}
