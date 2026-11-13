// The workspace's lock: a hash-chained record of who belongs, each entry signed by a device or
// passkey the record itself names. Once a station pins it, the control plane only stores and carries it: who may
// connect, with what role, which stations are peers, which gateways and grant keys count, all come from here. Pure:
// what is kept and when it is told is cloud/state.ts's.
import { createHash, createPublicKey, verify } from "node:crypto";
import * as form from "../../../client/core-ts/src/lock-form.ts";
// @ts-ignore: the MoonBit build's JS, untyped
import * as rules from "../../../rules/js/rules.js";

export type Sig =
  | { key: string; alg: "Ed25519" | "ES256"; sig: string }
  | { key: string; alg: "webauthn"; authenticator_data: string; client_data: string; sig: string };

export type Entry = { v: 1; ws: string; seq: number; prev: string | null; at: number; kind: string; body: any; sig: Sig };

export type Role = "owner" | "admin" | "member" | "viewer";
export type Member = { sub: string; email: string; role: Role };
/// A device: its base iroh key (`id`), whose person, the client it is, the key it signs with (an app's only), the
/// endpoint ids an older client connects with (it proves none), until when (a web page's).
/// `by`: whose signature put it in the lock (the genesis's devices the owner's). `own`: the person's own, which alone
/// signs anything ( 本人的设备): named in the genesis, put in by an own device or passkey of the
/// same person, or put in by an owner or admin while the person had never had an own one that signs (their first,
/// approved face to face). An admin may put a device or passkey in under anyone's name: that one connects, but its
/// signature counts for nothing, in the lock or the vault, so it can neither act as the person nor be given their keys.
export type Device = { id: string; sub: string; kind: "app" | "web"; label: string; sign_key?: string; endpoints?: string[]; exp?: number; by?: string; own: boolean };
export type Passkey = { id: string; sub: string; key: string; label: string; own: boolean };
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
  /// The signing keys each device id has had in the lock, in order: a device back in the lock under a new one (an app
  /// installed anew) signed its box certificate with the old one, which a vault's keys may still carry (vault/crypto.ts
  /// `certOk` `ever`).
  signKeys: Map<string, string[]>;
  passkeys: Map<string, Passkey>;
  /// The members who have had an own device that signs, or an own passkey, since they were last made members: an owner
  /// or admin puts in only the first of a person's, which is then their own; any later one the person puts in.
  signed: Set<string>;
  stations: Map<string, Station>;
  gateways: Set<string>;
  /// The person's own lock each member bound themselves to (`person` entries): its genesis's hash.
  persons: Map<string, string>;
  disabled: boolean;
  /// Where the chain went (`moved {root}`, its owner's): the genesis hash of the person log the workspace is said in
  /// from then on (state4). Absent: it did not.
  moved?: string;
};

export const ROLES: Role[] = ["viewer", "member", "admin", "owner"];
export const rank = (role: string) => ROLES.indexOf(role as Role);
/// The lower of two roles: the control plane may take rights away, never give them (an unknown role is the lowest).
export const lowerRole = (a: string, b: string): Role => ROLES[Math.max(0, Math.min(rank(a), rank(b)))]!;

/// How long a device added from a web page lasts at most (30 days, a day's slack for clocks).
export const WEB_DEVICE_SECS = 31 * 86400;

const HEX32 = /^[0-9a-f]{64}$/;
const isId = (v: unknown): v is string => typeof v === "string" && HEX32.test(v);

/// JSON with object keys sorted, no space: what is hashed. Only integers, strings, booleans, null, arrays, objects.
export function canonical(v: unknown): string {
  return form.canonical(v);
}

const sha256 = (b: Uint8Array | string) => createHash("sha256").update(b).digest();

/// An entry's hash (hex): of everything but its signature.
export function entryHash(e: Entry): string {
  return sha256(form.entryText(e)).toString("hex");
}

/// What a device or app key signs for an entry: a tag, then the hash's bytes. (A passkey signs the hash as its
/// WebAuthn challenge.)
export const signedBytes = (hash: string) => Buffer.concat([Buffer.from("stillfail-lock/1 sig\0"), Buffer.from(hash, "hex")]);

/// What a device's base key signs to say an endpoint is its own, in a workspace (and what it shows the cloud when it
/// asks for a credential for that endpoint).
export const endpointBytes = (ws: string, endpoint: string) => Buffer.from(`stillfail-lock-endpoint/1\0${ws}\0${endpoint}`);

/// Keys already made, by id: a chain's few keys check every entry they signed (a lock folded again, each device's
/// hello), and making node's key object from its JWK costs more than the check itself. Bounded: cleared when full.
const made = new Map<string, ReturnType<typeof makePublicKey>>();
const MADE_MAX = 1024;

/// A signing key's public half by its id: `ed25519:<hex>` or `p256:<base64url of the uncompressed point>`.
export function publicKey(id: string) {
  const known = made.get(id);
  if (known !== undefined) return known;
  const key = makePublicKey(id);
  if (made.size >= MADE_MAX) made.clear();
  made.set(id, key);
  return key;
}

function makePublicKey(id: string) {
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

/// The station's own check of a signature, where it has one (native/mesh `verify`: libcrux, HACL*'s Ed25519 and P-256
/// proved in F*, as a native app's shell checks them), set as the station starts (services.ts); none (cloud, a test, a
/// mesh addon from before): node's.
export type Verify = (alg: "Ed25519" | "ES256" | "ES256-der", key: Buffer, signature: Buffer, message: Buffer) => boolean;
let native: Verify | null = null;
export function verifyWith(v: Verify | null): void {
  native = v;
}

/// Whether `signature` is the key `id`'s over `message` (`der`: a P-256 one DER-encoded, as WebAuthn gives it).
export function signatureOk(id: string, signature: Buffer, message: Buffer, der = false): boolean {
  const { alg, key } = publicKey(id);
  if (native !== null) return native(alg === "Ed25519" ? "Ed25519" : der ? "ES256-der" : "ES256", Buffer.from(alg === "Ed25519" ? id.slice(8) : id.slice(5), alg === "Ed25519" ? "hex" : "base64url"), signature, message);
  if (alg === "Ed25519") return verify(null, message, key, signature);
  return verify("sha256", message, { key, dsaEncoding: der ? "der" : "ieee-p1363" }, signature);
}

/// Whether `sig` is the key's over the entry `hash`; a passkey's also on one of `origins` for `rp_id`.
export function sigValid(sig: Sig, hash: string, origins: string[], rp_id: string, passkey: boolean): boolean {
  try {
    const { alg } = publicKey(sig.key);
    if (sig.alg === "webauthn") {
      if (!passkey || alg !== "ES256") return false;
      const client = Buffer.from(sig.client_data, "base64url");
      const data = JSON.parse(client.toString("utf8"));
      if (data?.type !== "webauthn.get" || data?.challenge !== Buffer.from(hash, "hex").toString("base64url") || !origins.includes(data?.origin)) return false;
      const auth = Buffer.from(sig.authenticator_data, "base64url");
      // rpIdHash, then flags: user present.
      if (auth.length < 37 || !auth.subarray(0, 32).equals(sha256(rp_id)) || (auth[32]! & 1) === 0) return false;
      return signatureOk(sig.key, Buffer.from(sig.sig, "base64url"), Buffer.concat([auth, sha256(client)]), true);
    }
    if (sig.alg !== alg || passkey) return false;
    return signatureOk(sig.key, Buffer.from(sig.sig, alg === "Ed25519" ? "hex" : "base64url"), signedBytes(hash));
  } catch {
    return false;
  }
}

/// Whether a device's base key says `endpoint` is its own in workspace `ws`.
export function endpointProof(ws: string, base: string, endpoint: string, proof: string): boolean {
  try {
    return isId(base) && signatureOk(`ed25519:${base}`, Buffer.from(proof, "hex"), endpointBytes(ws, endpoint));
  } catch {
    return false;
  }
}

// The rules themselves (who may sign what, what each entry does) are rules/'s, in MoonBit: what they
// hold for each state is theirs, given back to them for the next entry; the state here is a copy to read.
const crypto = { sha256Hex: (s: string) => sha256(s).toString("hex"), sigValid, validKeyId, endpointProof };
const held = new WeakMap<LockState, unknown>();
// A lock state is a snapshot: apply makes a new one. These groups are made as its maps are copied, not at a lookup.
const people = new WeakMap<LockState, { emails: Map<string, Member[]>; devices: Map<string, string[]> }>();

type Pairs<T> = [string, T][];
type Told = Omit<LockState, "members" | "devices" | "signKeys" | "passkeys" | "signed" | "stations" | "gateways" | "persons"> & {
  members: Pairs<Member>; devices: Pairs<Device>; signKeys: Pairs<string[]>; passkeys: Pairs<Passkey>; signed: string[]; stations: Pairs<Station>; gateways: string[]; persons: Pairs<string>;
};

function taken(out: { state: Told; rules: unknown } | { error: string }): LockState {
  if ("error" in out) throw new Error(out.error);
  const t = out.state;
  const members = new Map<string, Member>(), devices = new Map<string, Device>();
  const emails = new Map<string, Member[]>(), byPerson = new Map<string, string[]>();
  for (const [sub, member] of t.members) {
    members.set(sub, member);
    const email = member.email.toLowerCase();
    const group = emails.get(email) ?? [];
    group.push(member);
    emails.set(email, group);
  }
  for (const [id, device] of t.devices) {
    devices.set(id, device);
    const group = byPerson.get(device.sub) ?? [];
    group.push(id);
    byPerson.set(device.sub, group);
  }
  const s: LockState = {
    ...t, members, devices, signKeys: new Map(t.signKeys), passkeys: new Map(t.passkeys),
    signed: new Set(t.signed), stations: new Map(t.stations), gateways: new Set(t.gateways), persons: new Map(t.persons),
  };
  held.set(s, out.rules);
  people.set(s, { emails, devices: byPerson });
  return s;
}

/// The first member with this lower-case email, in the lock's existing order.
export function memberWithEmail(s: LockState, email: string): Member | null {
  const index = people.get(s);
  if (index) return index.emails.get(email)?.[0] ?? null;
  // A caller may construct a lock view itself, rather than taking a rules snapshot.
  for (const member of s.members.values()) if (member.email.toLowerCase() === email) return member;
  return null;
}

/// Every member with this lower-case email, in the lock's existing order.
export function membersWithEmail(s: LockState, email: string): readonly Member[] {
  const index = people.get(s);
  if (index) return index.emails.get(email) ?? [];
  return [...s.members.values()].filter((member) => member.email.toLowerCase() === email);
}

/// Device ids of a person in this lock snapshot.
export function devicesFor(s: LockState, sub: string): readonly string[] {
  const index = people.get(s);
  if (index) return index.devices.get(sub) ?? [];
  return [...s.devices].flatMap(([id, device]) => device.sub === sub ? [id] : []);
}

function rulesOf(s: LockState): unknown {
  const r = held.get(s);
  if (r === undefined) throw new Error("not a lock state the rules made");
  return r;
}

/// Who signed: the member whose app device or passkey holds the key, with their role now, and whether it is their own
/// (an own one first: a key put in again under another device, someone else's, does not take its signatures away).
export function signer(s: LockState, sig: Pick<Sig, "key">, now: number | null): { sub: string; role: Role; passkey: boolean; own: boolean } | null {
  return rules.signer_js(rulesOf(s), String(sig.key), now);
}

/// The lock its first entry starts. Throws why it is not one.
export function genesis(e: Entry): LockState {
  return taken(rules.genesis_js(e, crypto));
}

/// The lock with one more entry; throws why the entry does not follow. `now`: the station's time (unix seconds), for
/// signing devices that ran out; null for entries taken before (kept in lock.json).
export function apply(prev: LockState, e: Entry, now: number | null): LockState {
  return taken(rules.apply_js(rulesOf(prev), e, now, crypto));
}

/// A whole chain, from its genesis. Throws at the first entry that does not follow.
export function fold(entries: Entry[], now: number | null): LockState {
  return taken(rules.fold_held_js(entries, now, crypto));
}

/// The device a connection is, by the base key's proof for its endpoint or (an older client) the endpoint itself, and
/// that device's member's role in the lock. Throws why it may not connect.
export function admit(s: LockState, who: { sub: string; endpoint: string; base?: string; proof?: string }, now: number): { device: Device; role: Role } {
  const out = rules.admit_one_js(rulesOf(s), who, now, crypto);
  if ("refusal" in out) throw new LockRefusal(out.refusal);
  return { device: s.devices.get(out.device)!, role: out.role };
}

/// A person's own lock as its chain says it (rules/src/lock/person.mbt).
export type PersonDevice = { key: string; id: string; label: string };
export type Person = { sub: string; genesis: string; head: string; seq: number; devices: PersonDevice[] };

/// What a person's chain says, each entry checked. Throws why it does not hold.
export function personFold(entries: unknown[], sub: string): Person {
  const out = rules.person_fold_js(entries, sub, crypto);
  if ("error" in out) throw new Error(out.error);
  return out;
}

/// Why an entry given is off a log's active chain, as the rules say it (rules/src/lock/chain.mbt `Off`; `at` its place
/// among those given): refused by the log's rules after its parent (`refusal` why); no parent among those that follow;
/// beaten at its parent by the child chosen (`winner` its hash, by `step`); below a child not chosen (`under` its hash);
/// the same entry again with another signature.
export type Off = {
  at: number;
  why: "refused" | "no parent" | "beaten" | "below" | "again";
  refusal?: string;
  winner?: string;
  step?: "weight" | "removal" | "tie" | "hash";
  under?: string;
};
/// A log's active chain among entries given in any order, branching: their places on it from the genesis, its hashes,
/// and why each other one is off it.
export type Chain = { at: number[]; hashes: string[]; off: Off[] };

function chainOf(out: any): Chain {
  if ("error" in out) throw new Error(out.error);
  return { at: out.at, hashes: out.hashes, off: out.off };
}

/// The workspace lock's active chain among `entries` from its genesis of hash `root`, by the fork choice with votes by
/// role (rules/src/lock/chain.mbt `lock_chain`), entries taken before (`now` null, as lock.json's are folded). Throws
/// why there is none.
export function lockChain(entries: Entry[], root: string): Chain {
  return chainOf(rules.lock_chain_js(entries, root, "roles", null, crypto));
}

/// A person log's active chain among `entries` from its genesis of hash `root` (rules/src/lock/chain.mbt
/// `person_chain`), by the same rules as `personFold`. Throws why there is none.
export function personChain(entries: unknown[], root: string): Chain {
  return chainOf(rules.person_chain_js(entries, root, crypto));
}

/// The device a connection is by a person's own lock (`entries`, the chain it brought), and that member's role in the
/// workspace's lock. Throws a LockRefusal why it may not connect.
export function admitPerson(s: LockState, who: { sub: string; endpoint: string; base?: string; proof?: string }, entries: unknown[]): { device: string; role: Role; person: Person } {
  const out = rules.admit_person_js(rulesOf(s), who, entries, crypto);
  if ("refusal" in out) throw new LockRefusal(out.refusal);
  return out;
}

/// A workspace said in its people's own logs (rules/src/lock/state4.mbt), once its chain moved there: `on` (the root's
/// newest of `open` and `off` in force is an `open`), `off`, `not on` (neither in force here yet), `no root` (the root's
/// log not among those given); `state` in the shape of a folded chain's, so that `admit` and `admitPerson` take it.
/// `genesis`, `head` and `seq` are the root log's: no place in a workspace chain. `chains`: each person log's active
/// chain, genesis first; `bodies`: the statements' bodies kept; `now`: this station's clock (web devices).
export function state4(ws: string, root: string, chains: unknown[][], bodies: unknown[], now: number): { on: "on" | "off" | "not on" | "no root"; state: LockState } {
  const out = rules.state4_js(ws, root, chains, bodies, now, crypto);
  return { on: out.on, state: taken(out) };
}

/// Workspace `ws`'s list as the rules work it out of the same (rules/src/lock/roster.mbt): what is in force (`in_force`,
/// each `{entry, body}` hash), the entries of its tag whose body is not kept (`lacking`), and the rest `roster_js` says.
/// `without`: bodies' hashes whose statements are left out of those in force once that is decided (whom a removal took
/// out: the list as it would be without it).
export function roster4(ws: string, root: string, chains: unknown[][], bodies: unknown[], without: string[] = []): { rooted: boolean; in_force: { entry: string; body: string }[]; lacking: string[]; members: { sub: string; lock: string; keys: string[] | null }[]; stations: string[] } {
  const out = rules.roster_js(ws, root, chains, bodies, without, crypto);
  if ("error" in out) throw new Error(out.error);
  return out;
}

/// Workspace `ws`'s tag in the person log of genesis hash `genesis` (what its commitments there carry as `t`).
export const wsTag = (ws: string, genesis: string): string => rules.ws_tag_js(ws, genesis, crypto);

/// A statement's body's hash (what its commitment carries as `h`); null where it has none.
export function bodyHash(body: unknown): string | null {
  const h: string = rules.body_hash_js(body, crypto);
  return h.startsWith("!") ? null : h;
}

/// Why a keeper of workspace `ws` does not take `body`, or null: `commits` every `ws` entry it keeps that commits to the
/// body's hash, each with its log from the genesis to that entry (rules/src/lock/body.mbt `body_refusal`).
export function bodyRefusal(ws: string, body: unknown, commits: { genesis: string; chain: Entry[] }[]): string | null {
  return rules.body_refusal_js(ws, body, commits, crypto);
}

/// What changes whenever what a state says may have: a folded chain's head, or the word a state in force was made
/// with (`stateWord`), whose root log's head does not move with the bodies or the other logs.
const words = new WeakMap<LockState, string>();
export const stateWord = (s: LockState): string => words.get(s) ?? s.head;
export const sayWord = (s: LockState, word: string): void => void words.set(s, word);

/// A refusal by the lock (the client asks to be confirmed), not a bad credential.
export class LockRefusal extends Error {
  readonly code = "lock_unconfirmed";
}

/// A short code for a device, both sides work it out from its base key: what a person compares before confirming it.
export function shortCode(base: string): string {
  return form.shortCodeOf(sha256(form.codeText(base)));
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
