// Approving a new device face to face (docs/workspace-lock.md 新设备): a code shown on a trusted device, typed on the
// new one, proved over the connection between them without being sent. The two run CPace (draft-irtf-cfrg-cpace) on
// ristretto255: each picks a secret, sends its share of a generator made from the code and from who the two are as
// each sees the connection; the same code and the same two ends give the same key, which each proves with a MAC.
// Someone between them (a cloud handing out a false lock, a relay) learns nothing of the code from what goes by and
// gets one guess per try; a device that dialled someone else binds the key to that one, and it does not match.
import { ristretto255, ristretto255_hasher } from "@noble/curves/ed25519.js";
import { hmac } from "@noble/hashes/hmac.js";
import { sha512 } from "@noble/hashes/sha2.js";
import { utf8 } from "./util.ts";

/// The protocol a trusted device takes a new one's connection on.
export const PAIR_ALPN = utf8("stillfail/pair/1");
/// How many wrong codes one connection is allowed.
export const PAIR_TRIES = 3;

/// A fresh code: six digits, as a phone's keypad types them (20 bits: each try is one of PAIR_TRIES, each connection
/// put up on the trusted device), drawn without favouring any.
export function pairCode(randomBytes: (into: Uint8Array) => void): string {
  const b = new Uint8Array(4);
  for (;;) {
    randomBytes(b);
    const n = ((b[0]! << 24) | (b[1]! << 16) | (b[2]! << 8) | b[3]!) >>> 0;
    // Below the largest multiple of a million under 2^32: each code as likely as the next.
    if (n < 4294000000) return String(n % 1_000_000).padStart(6, "0");
  }
}

/// A code as typed (spaces and dashes are the person's): its six digits, or null when it is not one.
export function typedCode(typed: string): string | null {
  const digits = typed.replace(/[\s\-–—]/g, "");
  return /^[0-9]{6}$/.test(digits) ? digits : null;
}

const join = (...parts: Uint8Array[]) => {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let at = 0;
  for (const p of parts) {
    out.set(p, at);
    at += p.length;
  }
  return out;
};

/// What both ends bind the exchange to, each as it sees the connection: the new device's key, the trusted one's
/// (iroh ids, hex), the workspaces asked for.
export function pairSession(newId: string, trustedId: string, workspaces: string[]): Uint8Array {
  return sha512(utf8(`stillfail-pair/1 session\0${newId}\0${trustedId}\0${[...workspaces].sort().join(",")}`));
}

/// ristretto255's group order (BigInt by call, not literal: as noble writes it, for every engine the core runs on).
const ORDER = BigInt("7237005577332262213973186563042994240857116359379907606001950938285454250989");

/// One try's secret and the share it sends.
export type Pake = { secret: bigint; share: Uint8Array; session: Uint8Array; generator: ReturnType<typeof ristretto255_hasher.hashToCurve> };

export function pakeStart(code: string, session: Uint8Array, randomBytes: (into: Uint8Array) => void): Pake {
  const generator = ristretto255_hasher.hashToCurve(join(utf8("stillfail-pair/1 generator\0"), utf8(code), session), { DST: "stillfail-pair/1" });
  const zero = BigInt(0);
  let secret = zero;
  while (secret === zero) {
    const b = new Uint8Array(64);
    randomBytes(b);
    secret = [...b].reverse().reduce((n, x) => n * BigInt(256) + BigInt(x), zero) % ORDER;
  }
  return { secret, share: generator.multiply(secret).toBytes(), session, generator };
}

/// The MAC this end sends and the one it expects, from the other's share; null when that share is no point (or the
/// identity: someone forcing the key).
export function pakeKeys(p: Pake, theirs: Uint8Array, role: "new" | "trusted"): { mine: Uint8Array; theirs: Uint8Array } | null {
  let shared;
  try {
    shared = ristretto255.Point.fromBytes(theirs).multiply(p.secret);
  } catch {
    return null;
  }
  if (shared.equals(ristretto255.Point.ZERO)) return null;
  const [ofNew, ofTrusted] = role === "new" ? [p.share, theirs] : [theirs, p.share];
  const key = sha512(join(utf8("stillfail-pair/1 key\0"), p.session, ofNew, ofTrusted, shared.toBytes()));
  const macNew = hmac(sha512, key, utf8("new"));
  const macTrusted = hmac(sha512, key, utf8("trusted"));
  return role === "new" ? { mine: macNew, theirs: macTrusted } : { mine: macTrusted, theirs: macNew };
}

/// Whether two MACs are the same, in time that does not tell where they differ.
export function sameMac(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a[i]! ^ b[i]!;
  return d === 0;
}
