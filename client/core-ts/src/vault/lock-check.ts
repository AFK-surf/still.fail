// The workspace lock, checked on the device by the stations' own rules (rules/, MoonBit): what the
// vault trusts to say which device a box key is and whose. The rest of the core shows the lock as the cloud keeps it
// (views/lock.ts `fold`, unchecked); before a vault's key is sealed to a device, every entry's signature and signer is
// checked here, so neither the cloud nor a station can put a device of their own in it.
import { p256 } from "@noble/curves/nist.js";
import { sha256 } from "@noble/hashes/sha2.js";
// @ts-ignore: the MoonBit build's JS, untyped
import * as rules from "../../../../rules/js/rules.js";
import { CoreError } from "../error.ts";
import { type Entry, signedBytes } from "../lock.ts";
import type { Chain } from "../lock-keep.ts";
import { hex, utf8 } from "../util.ts";
import { fromB64url } from "./crypto.ts";
import { ed25519Ok, p256Ok } from "./verified.ts";

/// `by`: whose signature put it in the lock (the entry's signer, a passkey's or a device's; the genesis's devices the
/// owner's). `own`: the person's own, which alone signs anything (station/src/cloud/lock.ts Device `own`): named in the
/// genesis, put in by an own device or passkey of theirs (face to face, views/pair.ts), or by an owner or admin while
/// they had never had an own one that signs (their first). An admin may put a device in under any member's name: it
/// connects, and its signature counts for nothing, in the lock or a vault (views/vault.ts `certs`).
export type Device = { id: string; sub: string; kind: "app" | "web"; sign_key?: string; exp?: number; by?: string; own: boolean };
/// `cloudKeys`: the keys the cloud signs member credentials with, as the lock names them (a JWKS). `passkeys`: whose
/// each is, by its key, and whether their own. `signed`: the members who have had an own device that signs or an own
/// passkey since they were last made members. `signKeys`: the signing keys each device has had in it (a vault's keys may
/// be sealed under a certificate an earlier one signed).
export type Checked = { ws: string; head: string; genesis: string; members: Map<string, string>; devices: Map<string, Device>; passkeys: Map<string, { sub: string; own: boolean }>; signed: Set<string>; signKeys: Map<string, string[]>; origins: string[]; rp_id: string; disabled: boolean; cloudKeys: unknown };

const unhex = (h: string) => Uint8Array.from(h.match(/../g) ?? [], (b) => parseInt(b, 16));
function refuse(why: string): never {
  throw new CoreError("vault_lock_invalid", `the workspace's lock does not check out: ${why}`);
}

function point(id: string): Uint8Array | null {
  if (!id.startsWith("p256:")) return null;
  const p = fromB64url(id.slice(5));
  return p !== null && p.length === 65 && p[0] === 4 ? p : null;
}

/// Whether `sig` is its key's over the entry `hash`; a passkey's on one of `origins` for `rp_id` (WebAuthn).
function sigValid(sig: any, hash: string, origins: string[], rp_id: string, passkey: boolean): boolean {
  try {
    if (sig?.alg === "webauthn") {
      const pub = point(sig.key);
      if (!passkey || pub === null) return false;
      const client = fromB64url(sig.client_data), auth = fromB64url(sig.authenticator_data), der = fromB64url(sig.sig);
      if (client === null || auth === null || der === null) return false;
      const data = JSON.parse(new TextDecoder().decode(client));
      const challenge = fromB64url(String(data?.challenge ?? ""));
      if (data?.type !== "webauthn.get" || challenge === null || hex(challenge) !== hash || !origins.includes(data?.origin)) return false;
      const rp = sha256(utf8(rp_id));
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

/// A signing key's id the lock takes (station/src/cloud/lock.ts `validKeyId`): `ed25519:<hex>`, or `p256:` and a point
/// on the curve.
function validKeyId(id: string): boolean {
  if (id.length > 200) return false;
  if (/^ed25519:[0-9a-f]{64}$/.test(id)) return true;
  const p = point(id);
  if (p === null) return false;
  try {
    p256.Point.fromBytes(p).assertValidity();
    return true;
  } catch {
    return false;
  }
}

const crypto = { sha256Hex: (s: string) => hex(sha256(utf8(s))), sigValid, validKeyId, endpointProof: () => false };
const held = new WeakMap<Checked, unknown>();

/// Who signs with `key` in the lock (a member's passkey, or an app device of theirs not run out): what a station takes
/// an entry signed with it from (one that changes something only where `own`); null for none.
export function signerIn(s: Checked, key: string, now: number | null): { sub: string; role: string; passkey: boolean; own: boolean } | null {
  const r = held.get(s);
  if (r === undefined) throw new Error("not a lock the rules checked");
  return rules.signer_js(r, key, now);
}

/// The lock's chain among `entries` (any order, branching) from its genesis of hash `root`, by the rules' fork choice
/// with votes by role, each entry checked as a station checks it (rules/src/lock/chain.mbt `lock_chain`; the station's
/// `lockChain`, station/src/cloud/lock.ts). Throws why there is none.
export function lockChain(entries: Entry[], root: string): Chain {
  const out = rules.lock_chain_js(entries, root, "roles", null, crypto);
  if ("error" in out) throw new Error(out.error);
  return { at: out.at, hashes: out.hashes, off: out.off };
}

/// The lock its entries make, each checked as a station checks it; throws why not. `now` (unix seconds): signing
/// devices that ran out sign no more.
export function checkLock(entries: Entry[], now: number): Checked {
  return checkedOf(rules.fold_held_js(entries, now, crypto));
}

/// A lock as the rules give it (`{state, rules}`: a chain folded, `fold_held_js`, or the state a moved workspace's
/// people's logs make, `state4_js`, src/lock-moved.ts `inForce`, which is in the shape of a folded chain's), the rules'
/// own object kept for it (`signerIn`), as station/src/cloud/lock.ts `taken` makes a station's of either; throws why
/// there is none.
export function checkedOf(out: any): Checked {
  if ("error" in out) return refuse(out.error);
  const t = out.state;
  const s: Checked = {
    ws: t.ws, head: t.head, genesis: t.genesis, origins: t.origins, rp_id: t.rp_id, disabled: t.disabled, cloudKeys: t.cloud_keys,
    members: new Map(t.members.map(([sub, m]: [string, { role: string }]) => [sub, m.role])),
    devices: new Map(t.devices.map(([id, d]: [string, any]) => [id, {
      id: d.id, sub: d.sub, kind: d.kind, ...(d.sign_key !== undefined ? { sign_key: d.sign_key } : {}), ...(d.exp !== undefined ? { exp: d.exp } : {}), ...(d.by !== undefined ? { by: d.by } : {}), own: d.own,
    }])),
    passkeys: new Map(t.passkeys.map(([key, p]: [string, { sub: string; own: boolean }]) => [key, { sub: p.sub, own: p.own }])),
    signed: new Set(t.signed), signKeys: new Map(t.signKeys),
  };
  held.set(s, out.rules);
  return s;
}
