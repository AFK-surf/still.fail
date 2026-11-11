// A person's own lock: a chain, kept by the cloud and carried to their devices, of the keys that
// person's app devices sign with. Only a device on it adds or removes one; a new device joins face to face
// (views/pair.ts). What they sign with it means more than a login does: their phone lends itself to a chat only on a
// grant signed so, which it checks itself against the lock it pinned, whatever a station or the cloud says.
//
// The key is sealed so that each use asks the person (`user: true`: biometrics or the screen lock). Web pages have none:
// their code is the cloud's.
import { ed25519 } from "@noble/curves/ed25519.js";
import { Deferred, Effect, Schedule } from "effect";
// @ts-ignore: the MoonBit build's JS, untyped
import * as rules from "../../../rules/js/rules.js";
import { CoreError, asCoreError } from "./error.ts";
import type { Host } from "./host.ts";
import { t } from "./i18n.ts";
import { type Entry, canonical, entryHash, signedBytes } from "./lock.ts";
import { type Kind as RigKind, type Signed as RigSigned, signedBytes as rigBytes } from "./rig-form.ts";
import type { Runner } from "./runtime.ts";
import { fromUtf8, hex, parseJson, sha256, utf8 } from "./util.ts";
import { ed25519Ok } from "./vault/verified.ts";
import type { Asked } from "./views/lock.ts";

// deno-lint-ignore no-explicit-any
type J = any;

/// A lock's name in its entries (and among what a new device asks to be let into).
export const personOf = (sub: string) => `person:${sub}`;
export const isPerson = (where: string) => where.startsWith("person:");

const KEY = "personal-signer";
/// What a person does here (an entry they sign) waits out the cloud's "too many requests": the account's devices share
/// one budget a minute, which their reads as a lock moves can use up (as views/lock.ts `Lock` waits, by hand).
const LIMITED_TRIES = 6;
const LIMITED_WAIT = "10 seconds";
/// How many devices approved in workspaces' locks are put on the lock at one time the seed is in hand (`#addApproved`).
const APPROVED_AT_ONCE = 16;
/// The key's public half, read without asking anyone.
const KEY_ID = "personal-signer-id";
const keptAs = (sub: string) => `personal-lock-${hex(utf8(sub))}`;
/// The roots (genesis hashes) of the chains this device left behind when it began the lock anew, kept beside it.
const leftAs = (sub: string) => `personal-lock-left-${hex(utf8(sub))}`;
/// The form of the key a device signs workspaces' locks with (its signer, views/lock.ts `signerOf`).
const SIGN_KEY = /^ed25519:[0-9a-f]{64}$/;
const unhex = (h: string) => (/^([0-9a-f]{2})*$/.test(h) ? Uint8Array.from(h.match(/../g) ?? [], (b) => parseInt(b, 16)) : new Uint8Array());
const asKey = (id: string) => (id.startsWith("ed25519:") ? unhex(id.slice(8)) : new Uint8Array());

/// Whether `id` signed `bytes` with `sig`: by the host's own check and kept on the device (vault/verified.ts), as the
/// same chain and grants are asked of at every grant a station tells of, each view of the lock and each start, and one
/// check in Hermes takes milliseconds.
const verifies = (id: string, sig: string, bytes: Uint8Array) => {
  try {
    return ed25519Ok(unhex(sig), bytes, asKey(id));
  } catch {
    return false;
  }
};

/// `sign_key`: the key the device signs workspaces' locks with, as its entry on the chain says it (the rules' fold reads
/// only key, id and label: `signKeys` reads it of the entries).
export type Device = { key: string; id: string; label: string; sign_key?: string };
export type Chain = { readonly devices: ReadonlyMap<string, Device>; readonly hash: string | null };

const crypto = {
  sha256Hex: (text: string) => hex(sha256(utf8(text))),
  sigValid: (sig: J, hash: string) => sig?.alg === "Ed25519" && typeof sig.key === "string" && typeof sig.sig === "string" && verifies(sig.key, sig.sig, signedBytes(hash)),
  validKeyId: (id: string) => /^ed25519:[0-9a-f]{64}$/.test(id),
  endpointProof: () => false,
};

/// What a chain says, by the rules every side goes by (rules/src/lock/person.mbt); no chain says none. Null when it does
/// not hold.
export function checkChain(entries: readonly Entry[], sub: string): Chain | null {
  if (entries.length === 0) return { devices: new Map(), hash: null };
  // (a chain kept is replaced whole, never changed in place: what it said once it says until then, the same Chain to
  // each who asks, read only)
  const was = folded.get(entries);
  if (was !== undefined && was.sub === sub) return was.chain;
  const out = rules.person_fold_js(entries, sub, crypto) as J;
  const chain = "error" in out ? null : { devices: new Map((out.devices as Device[]).map((d) => [d.key, d])), hash: out.head };
  folded.set(entries, { sub, chain });
  return chain;
}
const folded = new WeakMap<readonly Entry[], { sub: string; chain: Chain | null }>();

/// What a person's device signs for a chat's grant of their phone.
export type GrantBody = { v: 1; sub: string; station: string; request: string; session: string; chat: string; scope: "hour" | "idle" | "eight" | "chat"; exp: number };
export type SignedGrant = { body: GrantBody; sig: { key: string; sig: string } };
const grantBytes = (body: unknown) => {
  const tag = utf8("stillfail-phone-grant/1\0");
  const digest = sha256(utf8(canonical(body)));
  const out = new Uint8Array(tag.length + digest.length);
  out.set(tag, 0);
  out.set(digest, tag.length);
  return out;
};

/// Until when a grant as a station says it holds (unix seconds), by what was signed for it and the lock this device
/// pinned; null when it does not: no signature, another's, a key not on the lock, or for something else than it says.
export function grantHolds(g: J, station: string, sub: string, devices: ReadonlyMap<string, Device>, now: number): number | null {
  const s = g?.signed as SignedGrant | undefined;
  const b = s?.body;
  if (b == null || typeof s?.sig?.key !== "string" || typeof s.sig.sig !== "string" || !devices.has(s.sig.key)) return null;
  if (b.v !== 1 || b.sub !== sub || b.station !== station || b.request !== g.id || b.session !== g.session || b.chat !== g.chat || b.scope !== g.scope) return null;
  if (!Number.isSafeInteger(b.exp) || b.exp <= now) return null;
  try {
    return verifies(s.sig.key, s.sig.sig, grantBytes(b)) ? b.exp : null;
  } catch {
    return null;
  }
}

/// This device's standing: `none` (no lock yet: its first signature begins it), `member`, `outside` (a lock it has not
/// joined, or that removed it), `replaced` (the cloud has another than the one pinned here: all devices lost, or forged).
export type Standing = "none" | "member" | "outside" | "replaced";

export type PersonalEnv = {
  host: Host;
  runner: Runner;
  /// A request to the cloud as this person.
  cloud: (sub: string, method: string, path: string, body: unknown) => Effect.Effect<unknown, CoreError>;
  /// This device's base key (as a pairing dials it), and its name.
  device: () => Effect.Effect<string, CoreError>;
  label: () => string;
  changed: () => void;
  /// The key this device signs workspaces' locks with (its signer), none while it has none: its entry on the chain
  /// says it, so any device of the person's that signs in a workspace can put the others in there (`signKeys`).
  signKey?: () => string | null;
  /// A device taken off: the stations where this lock is bound told, so an older chain brought there counts for nothing.
  told?: (sub: string, chain: Entry[]) => void;
  /// The person's devices to put on their lock as it stands (`chain`), of what workspaces' locks in safe mode say
  /// (views/lock.ts `ownLockEnv`, `approvedIn`): each said there the key it would be on it with, was put in there by a
  /// device signing with one of the keys a device on the chain signs workspaces' locks with (`signers`, as the chain
  /// records them: a device id is anyone's to write), and will take the chain once on it (put in under this device, or
  /// under one whose said key signed an entry of it, `signed`). None whose id or key was `ever` on it.
  approved?: (sub: string, chain: { signers: ReadonlySet<string>; signed: ReadonlySet<string>; ever: { ids: ReadonlySet<string>; keys: ReadonlySet<string> } }) => Device[];
  /// The keys said in workspaces' locks by the devices that put this device in there, and those that put them in, up
  /// to the first, each the person's own (views/lock.ts `vouchersIn`, which says what taking them so costs): a chain one
  /// of those keys signed an entry of is its person's lock (`#putOnBy`).
  vouchers?: (sub: string) => ReadonlySet<string>;
  /// The person's stations, where the lock is read and brought (the root AGENTS.md, The cloud is the account system):
  /// `read` the chains they keep of it (null when none this device reaches keeps any: older, offline or refusing it),
  /// `bring` the chain as it is now, how many took it (null: none could be asked; a refusal fails), `answered` whether
  /// every station of theirs that may keep it answered a read of it this run (what alone lets a lock be begun with no
  /// one asked, `beginQuietly`: a lock not known here is no lock not yet). `bring`'s `within`: a call's wait, past
  /// which, the stations not having answered for it, the way to hear them still (`later`), the cloud asked meanwhile.
  stations?: {
    read: (sub: string, at?: string) => Effect.Effect<Entry[][] | null>;
    bring: (sub: string, chain: Entry[], within?: Asked) => Effect.Effect<number | null | { later: Effect.Effect<number | null, CoreError> }, CoreError>;
    answered?: (sub: string) => boolean;
  };
  /// A wait of ASKED_MS for a call a person waits on (views/lock.ts `asked`); none, the calls wait as long as the
  /// stations and the cloud take.
  asked?: () => Asked;
};

/// The cloud's taking of an entry (`cloud`, waited on) or a station's (`stations`, whether one took it; failing, one
/// refused it), whichever comes first, the other going on behind (views/lock.ts ASKED_MS: past a call's wait the cloud
/// is asked too, and the stations still listened to). Only once the stations are over with none taking it is the
/// cloud's failure the call's; their answers are not cut short by it.
export function eitherTakes(runner: Runner, cloud: Effect.Effect<unknown, CoreError>, stations: Effect.Effect<boolean, CoreError>): Effect.Effect<void, CoreError> {
  return Effect.gen(function* () {
    const said = Deferred.makeUnsafe<CoreError | null>();
    runner.fork(Effect.flatMap(Effect.result(cloud), (r) => Effect.sync(() => void Deferred.doneUnsafe(said, Effect.succeed(r._tag === "Success" ? null : r.failure)))));
    const byStations = Effect.flatMap(stations, (took): Effect.Effect<CoreError | null> => (took ? Effect.succeed(null) : Deferred.await(said)));
    const byCloud = Effect.flatMap(Deferred.await(said), (e): Effect.Effect<CoreError | null, CoreError> => (e === null ? Effect.succeed(null) : Effect.map(stations, (took) => (took ? null : e))));
    const failed = yield* Effect.raceFirst(byStations, byCloud);
    if (failed !== null) return yield* Effect.fail(failed);
  });
}

/// What a read made within a call's wait brings past it (`refresh`): nothing yet.
const LATE = Symbol("late");

const PATH = "/v1/me/personal-lock";

export class PersonalLock {
  readonly #env: PersonalEnv;
  /// The chain pinned here, each person's; what the cloud has where this is not it.
  readonly #pinned = new Map<string, Entry[]>();
  readonly #seen = new Map<string, Entry[]>();
  readonly #loaded = new Set<string>();
  /// The roots of the chains this device left behind as it began anew, each person's: the stations may keep one still
  /// (they refused this device then, so the new chain reached only the cloud), and it is no lock begun elsewhere.
  readonly #left = new Map<string, Set<string>>();
  #myKey: string | null = null;

  constructor(env: PersonalEnv) {
    this.#env = env;
  }

  /// The chain pinned here as read so far, what it says.
  chain(sub: string): Chain | null {
    return checkChain(this.#pinned.get(sub) ?? [], sub);
  }

  /// Read from the device once, then from the person's stations (the cloud only when none of them keeps it: older,
  /// offline, or refusing this device): what extends the pinned one is taken, anything else only noted.
  /// `at`: a station just reached (its address): read of that one alone. `within`: a call a person waits on, which
  /// waits on each read only within it where a chain is pinned here; past it, that chain is what the call goes by, and
  /// the read goes on behind and is taken as it lands (2026-11-12: with the person's one station asleep, opening their
  /// lock, joining it, 允许 on a phone's request and a rig's calls waited 15 to 30 s; with the cloud's reads unanswered
  /// too, none answered). With none pinned the read is waited for whole: no lock known here is not no lock, and the
  /// callers begin one where they find none.
  refresh(sub: string, at?: string, within?: Asked): Effect.Effect<void, CoreError> {
    const env = this.#env;
    return Effect.gen({ self: this }, function* () {
      if (!this.#loaded.has(sub)) {
        const kept = yield* Effect.orElseSucceed(env.host.storageGet(keptAs(sub)), () => null);
        const said = kept === null ? null : (parseJson(kept) as Entry[] | null);
        if (Array.isArray(said) && checkChain(said, sub) !== null) this.#pinned.set(sub, said);
        this.#left.set(sub, yield* this.#leftKept(sub));
        const id = yield* Effect.orElseSucceed(env.host.storageGet(KEY_ID), () => null);
        if (id !== null) this.#myKey = fromUtf8(id);
        this.#loaded.add(sub);
        env.changed();
      }
      const bound = (this.#pinned.get(sub)?.length ?? 0) > 0 ? within : undefined;
      // (a read and what is done with what it brings are one work, so that one past the wait is taken all the same)
      const step = <A>(work: Effect.Effect<A, CoreError>): Effect.Effect<A | typeof LATE, CoreError> =>
        bound === undefined ? work : Effect.flatMap(bound.wait(Effect.result(work)), (r): Effect.Effect<A | typeof LATE, CoreError> => (r === undefined ? Effect.succeed(LATE) : r._tag === "Success" ? Effect.succeed(r.success) : Effect.fail(r.failure)));
      const stations = env.stations;
      const kept = stations === undefined ? false : yield* step(Effect.gen({ self: this }, function* () {
        const chains = yield* stations.read(sub, at);
        if (chains !== null) yield* this.#heard(sub, this.#best(sub, chains), true);
        return chains !== null;
      }));
      if (kept !== false) return;
      yield* step(Effect.gen({ self: this }, function* () {
        const said = (yield* env.cloud(sub, "GET", PATH, null)) as { entries?: Entry[] } | null;
        yield* this.#heard(sub, Array.isArray(said?.entries) ? said.entries : []);
      }));
    });
  }

  /// A wait for a call a person waits on, one for each of its phases (what is done between two asks of the person):
  /// its time begins with its first wait, so one made before the person is asked is not spent on them.
  asked(): Asked | undefined {
    return this.#env.asked?.();
  }

  /// The chains a station told (refusing this device): taken as a read of them is, once what is pinned here was read
  /// (before, the next read takes them: the stations' refusals are what it reads then).
  heardFrom(sub: string, chains: Entry[][]): Effect.Effect<void, CoreError> {
    return chains.length === 0 || !this.#loaded.has(sub) ? Effect.void : this.#heard(sub, this.#best(sub, chains), true);
  }

  /// The roots of the chains this device left behind, as kept on it (none kept, or unreadable: none).
  #leftKept(sub: string): Effect.Effect<Set<string>> {
    return Effect.map(Effect.orElseSucceed(this.#env.host.storageGet(leftAs(sub)), () => null), (kept) => {
      const said = parseJson(kept) as unknown;
      return new Set(Array.isArray(said) ? said.filter((r): r is string => typeof r === "string") : []);
    });
  }

  /// Whether `chain` is one this device left behind as it began anew: it counts for nothing here.
  #isLeft(sub: string, chain: readonly Entry[]): boolean {
    const left = this.#left.get(sub);
    return left !== undefined && left.size > 0 && chain[0] !== undefined && left.has(entryHash(chain[0]));
  }

  /// Of the chains the stations keep (each one a person's lock begun anew): the longest that goes on from the one pinned
  /// here; none such, the one a station kept last (its latest), as the cloud's would be. One this device left behind as
  /// it began anew is none of them.
  #best(sub: string, chains: Entry[][]): Entry[] {
    const pinned = this.#pinned.get(sub) ?? [];
    const root = pinned[0] === undefined ? null : entryHash(pinned[0]);
    let best: Entry[] | null = null;
    for (const c of chains) {
      if (root === null || c[0] === undefined || entryHash(c[0]) !== root || this.#isLeft(sub, c) || checkChain(c, sub) === null) continue;
      if (best === null || c.length > best.length) best = c;
    }
    if (best !== null) return best;
    for (const c of chains) if (c.length > 0 && !this.#isLeft(sub, c) && checkChain(c, sub) !== null) best = c;
    return best ?? [];
  }

  #heard(sub: string, heard: Entry[], stations = false): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      // (a chain this device left behind as it began anew: none heard, so the one pinned is brought where it is not)
      const entries = this.#isLeft(sub, heard) ? [] : heard;
      const was = this.#stands(sub);
      const pinned = this.#pinned.get(sub) ?? [];
      const holds = checkChain(entries, sub) !== null;
      const grows = pinned.length > 0 && holds && entries.length >= pinned.length && pinned.every((e, i) => entryHash(e) === entryHash(entries[i]!));
      // The one pinned as far as it went some entries ago: who was read is behind on it (a station away while a device
      // was let in, read alone as its link opened; the cloud, told each entry and never waited on). It is no lock begun
      // elsewhere: taken for one, the person was warned their devices had been set anew, by one station's being late.
      const behind = entries.length > 0 && entries.length < pinned.length && entries.every((e, i) => entryHash(e) === entryHash(pinned[i]!));
      if (grows) {
        this.#seen.delete(sub);
        if (entries.length > pinned.length) yield* this.#pin(sub, entries);
      } else if (pinned.length > 0 && (entries.length === 0 || behind)) {
        // (the cloud, or the stations, lost it, never had it, or are behind on it: brought back)
        if (stations) yield* Effect.ignore(this.#env.stations!.bring(sub, pinned));
        else yield* this.#env.cloud(sub, "POST", PATH, { entries: pinned });
      } else if (holds && entries.length > 0 && stations && pinned.length === 0 && (yield* this.#putOnBy(sub, entries))) {
        yield* this.#pin(sub, entries);
        this.#seen.delete(sub);
      } else if (holds && entries.length > 0) this.#seen.set(sub, entries);
      else this.#seen.delete(sub);
      // Told only when it changed: what is told retries the stations that refused this device, and each refusal brings
      // this same chain again (views/lock.ts heardRefused), so telling it unchanged would ask them again at once, endlessly.
      if (this.#stands(sub) !== was) this.#env.changed();
    });
  }

  /// Whether `entries` (a chain that holds, heard of the stations by a device with none pinned) is its person's lock as
  /// joining would have it: this device's key stands on it under this device's id, and some entry of it is signed by a
  /// key a device that vouches for this one said in a workspace's lock (`vouchers`: those of the person's own up its
  /// lineage there). That suffices: an entry signed by a device one trusts as its person's
  /// shows that device took this chain as their lock, and only devices on a chain add to it. Not the entry that put this
  /// device on: a sibling on the chain may have been the one to add it. A chain's ids are only what its entries say (this
  /// device's key is no secret, anyone could make a chain naming it); the key that signed is what is checked. One pinned
  /// already is never left this way.
  #putOnBy(sub: string, entries: readonly Entry[]): Effect.Effect<boolean> {
    const env = this.#env;
    return Effect.gen({ self: this }, function* () {
      const vouchers = env.vouchers?.(sub);
      const mine = this.#myKey === null ? undefined : checkChain(entries, sub)?.devices.get(this.#myKey);
      if (vouchers === undefined || vouchers.size === 0 || mine === undefined) return false;
      const id = yield* Effect.orElseSucceed(env.device(), () => null);
      if (mine.id !== id) return false;
      return entries.some((e) => typeof e.sig?.key === "string" && vouchers.has(e.sig.key));
    });
  }

  /// What is held of `sub`'s lock: the chain pinned and one seen that does not go on from it, by their last entries.
  #stands(sub: string): string {
    const last = (c: Entry[] | undefined) => (c === undefined || c.length === 0 ? "" : `${c.length}:${entryHash(c[c.length - 1]!)}`);
    return `${last(this.#pinned.get(sub))}|${last(this.#seen.get(sub))}`;
  }

  #pin(sub: string, entries: Entry[]): Effect.Effect<void, CoreError> {
    this.#pinned.set(sub, entries);
    return Effect.mapError(this.#env.host.storageSet(keptAs(sub), utf8(JSON.stringify(entries))), asCoreError);
  }

  /// `roots` kept as left behind (beside the pinned chain, its write failing as the pin's does), never the root of the
  /// chain pinned now: one begun again in the same second, by the same device, is the same.
  #leave(sub: string, roots: string[]): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const now = this.root(sub);
      const had = this.#left.get(sub) ?? (this.#loaded.has(sub) ? new Set<string>() : yield* this.#leftKept(sub));
      const left = new Set([...had, ...roots].filter((r) => r !== now));
      this.#left.set(sub, left);
      if (left.size === had.size && [...left].every((r) => had.has(r))) return;
      yield* Effect.mapError(this.#env.host.storageSet(leftAs(sub), utf8(JSON.stringify([...left]))), asCoreError);
    });
  }

  /// This device's signer, where it has one of the form a chain keeps.
  #mySignKey(): string | null {
    const k = this.#env.signKey?.() ?? null;
    return k !== null && SIGN_KEY.test(k) ? k : null;
  }

  /// What the chain pinned here last said of each device still on it, by its key: the last entry naming the key (the
  /// genesis's `device`, or a `device` entry).
  #lastSaid(sub: string): Map<string, { device: Device; said: J }> {
    const entries = this.#pinned.get(sub) ?? [];
    const chain = checkChain(entries, sub);
    const out = new Map<string, { device: Device; said: J }>();
    if (chain === null) return out;
    for (const e of entries) {
      const said = e.kind === "genesis" ? (e.body as J)?.device : e.kind === "device" ? e.body : null;
      const d = typeof said?.key === "string" ? chain.devices.get(said.key) : undefined;
      if (d !== undefined) out.set(d.key, { device: d, said });
    }
    return out;
  }

  /// The keys the person's devices on the chain pinned here sign workspaces' locks with, as each one's last entry says
  /// it, by the device's id (its base key, what a workspace's lock goes by); a device whose last entry says none, or one
  /// not of the form, has none.
  signKeys(sub: string): Map<string, { sign_key: string; label: string }> {
    const out = new Map<string, { sign_key: string; label: string }>();
    for (const { device, said } of this.#lastSaid(sub).values()) {
      const k = said?.sign_key;
      if (typeof k === "string" && SIGN_KEY.test(k)) out.set(device.id, { sign_key: k, label: device.label });
    }
    return out;
  }

  /// With the seed in hand for something else: this device said again on the chain with the key it signs workspaces'
  /// locks with, where its entry lacks it or names another (the rules take a device entry for a key on the chain as that
  /// device said again). Nothing more is asked of the person; a failure only leaves it unsaid until the next time.
  #restate(sub: string, seed: Uint8Array, within?: Asked): Effect.Effect<void> {
    const signKey = this.#mySignKey();
    const mine = this.#myKey === null ? undefined : this.#lastSaid(sub).get(this.#myKey);
    if (signKey === null || mine === undefined || mine.said?.sign_key === signKey) return Effect.void;
    const { key, id, label } = mine.device;
    return Effect.ignore(this.#append(sub, seed, "device", { key, id, label, sign_key: signKey }, true, within), { log: "Unhandled", message: "personal lock: this device said again" });
  }

  /// With the seed in hand for something else: the person's devices that a device on the lock approved face to face in a
  /// workspace's lock, and that said there the key they would be on it with (`approved`), put on it, each as it comes
  /// (one put on, a device it approved comes next), at most APPROVED_AT_ONCE at a time. Nothing more is asked of the
  /// person; a failure only leaves the rest for the next time. Only downward, and only by the key that signed: the device
  /// that put one in is matched by its signing key, which only its holder signs with, against those the chain records
  /// (`signers`), never by its id, which a workspace's manager may write under a key of their own: a device of theirs
  /// carried onto the person's own lock would be trusted in the person's other workspaces and for their phone. Only one
  /// that will take the lock once on it (`signed`: the keys that signed it, this device's too): put on and not taking it,
  /// the stations would let it in once the lock is bound while it held itself as not let in. One whose id or key was
  /// ever on the lock is not put back this way: taken off, it stays off.
  #addApproved(sub: string, seed: Uint8Array, within?: Asked): Effect.Effect<void> {
    const approved = this.#env.approved;
    if (approved === undefined) return Effect.void;
    return Effect.gen({ self: this }, function* () {
      for (let n = 0; n < APPROVED_AT_ONCE; n++) {
        const entries = this.#pinned.get(sub) ?? [];
        const chain = checkChain(entries, sub);
        if (chain === null) return;
        const ever = { ids: new Set<string>(), keys: new Set<string>() };
        const signed = new Set<string>(this.#myKey === null ? [] : [this.#myKey]);
        for (const e of entries) {
          const said = e.kind === "genesis" ? (e.body as J)?.device : e.kind === "device" ? e.body : null;
          if (typeof said?.id === "string") ever.ids.add(said.id);
          if (typeof said?.key === "string") ever.keys.add(said.key);
          if (typeof e.sig?.key === "string") signed.add(e.sig.key);
        }
        const signers = new Set([...this.signKeys(sub).values()].map((d) => d.sign_key));
        const d = approved(sub, { signers, signed, ever }).find((x) => !ever.ids.has(x.id) && !ever.keys.has(x.key) && SIGN_KEY.test(x.key));
        if (d === undefined) return;
        const { key, id, label, sign_key } = d;
        let failed = false;
        const put = this.#append(sub, seed, "device", { key, id, label, ...(sign_key !== undefined && SIGN_KEY.test(sign_key) ? { sign_key } : {}) }, true, within);
        yield* Effect.ignore(Effect.tapError(put, () => Effect.sync(() => void (failed = true))), { log: "Unhandled", message: "personal lock: a device approved in a workspace put on" });
        if (failed) return;
      }
    });
  }

  standing(sub: string): Standing {
    const pinned = this.chain(sub);
    if (this.#seen.has(sub) && (this.#pinned.get(sub)?.length ?? 0) > 0) return "replaced";
    if (pinned !== null && (this.#pinned.get(sub)?.length ?? 0) > 0) return this.#myKey !== null && pinned.devices.has(this.#myKey) ? "member" : "outside";
    return this.#seen.has(sub) ? "outside" : "none";
  }

  /// This device's key's id, made the first time, no one asked: keeping it takes no check, using it does.
  makeKey(): Effect.Effect<string, CoreError> {
    return Effect.map(this.#madeKey(null), (k) => k.id);
  }

  /// This device's key's id; made just now, its seed too: the person was asked once for that, and is not asked again to
  /// read what is in hand.
  #madeKey(reason: string | null): Effect.Effect<{ id: string; seed: Uint8Array | null }, CoreError> {
    const { host } = this.#env;
    return Effect.gen({ self: this }, function* () {
      if (this.#myKey !== null) return { id: this.#myKey, seed: null };
      if (!host.appKeys || !host.secureSet) return yield* Effect.fail(new CoreError("personal_no_key", t("core-misc.personal.noKey")));
      if (reason !== null && host.secureAsk) yield* Effect.mapError(host.secureAsk(reason), asCoreError);
      const seed = new Uint8Array(32);
      host.randomBytes(seed);
      yield* Effect.mapError(host.secureSet(KEY, seed, { user: true }), asCoreError);
      const id = `ed25519:${hex(ed25519.getPublicKey(seed))}`;
      yield* Effect.mapError(host.storageSet(KEY_ID, utf8(id)), asCoreError);
      this.#myKey = id;
      return { id, seed };
    });
  }

  /// The key's seed: the person asked, as reading it takes.
  #unseal(reason: string): Effect.Effect<Uint8Array, CoreError> {
    const { host } = this.#env;
    return Effect.gen(function* () {
      if (!host.secureGet) return yield* Effect.fail(new CoreError("personal_no_key", t("core-misc.personal.noKey")));
      const seed = yield* Effect.mapError(host.secureGet(KEY, { user: true, reason }), asCoreError);
      if (seed === null || seed.length !== 32) return yield* Effect.fail(new CoreError("personal_no_key", t("core-misc.personal.noKey")));
      return seed;
    });
  }

  #entry(sub: string, seed: Uint8Array, key: string, kind: string, body: unknown): Entry {
    const before = this.#pinned.get(sub) ?? [];
    const last = before[before.length - 1];
    const e = { v: 1 as const, ws: personOf(sub), seq: before.length, prev: last ? entryHash(last) : null, at: Math.floor(this.#env.host.nowMs() / 1000), kind, body };
    return { ...e, sig: { key, alg: "Ed25519", sig: hex(ed25519.sign(signedBytes(entryHash(e)), seed)) } };
  }

  /// One entry more, signed here, brought to the person's stations and pinned once one took it; to the cloud too, for
  /// the stations and devices from before that read it there, not waited on. Only when no station could be asked
  /// (older ones, offline), or none took it by TAKEN_MS, the cloud is what takes it; past a call's wait (`within`) with
  /// none having taken it, the cloud is asked too and whichever takes it first is done (`eitherTakes`; views/lock.ts
  /// ASKED_MS).
  /// `once`: the cloud, where it is what takes it, asked once and not again when it limits (an entry that rides on
  /// another act, which is not to wait a minute for it: `#restate`).
  #append(sub: string, seed: Uint8Array, kind: string, body: unknown, once = false, within?: Asked): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const e = this.#entry(sub, seed, this.#myKey!, kind, body);
      const toCloud = this.#env.cloud(sub, "POST", PATH, { entries: [e] });
      const taken = this.#env.stations ? yield* this.#env.stations.bring(sub, [...(e.seq === 0 ? [] : (this.#pinned.get(sub) ?? [])), e], within) : null;
      const cloudTakes = once ? toCloud : Effect.retry(toCloud, { times: LIMITED_TRIES, schedule: Schedule.spaced(LIMITED_WAIT), while: (e) => e.code === "rate_limited" }); // timer: a retry after a failure (429)
      if (typeof taken === "number" && taken > 0) this.#env.runner.fork(Effect.ignore(toCloud));
      else if (taken !== null && typeof taken === "object") yield* eitherTakes(this.#env.runner, cloudTakes, Effect.map(taken.later, (n) => n !== null && n > 0));
      else yield* cloudTakes;
      yield* this.#pin(sub, [...(this.#pinned.get(sub) ?? []), e]);
      this.#seen.delete(sub);
      this.#env.changed();
    });
  }

  /// A lock begun here, this device its first (one the cloud has already gives way to it: `restart`).
  begin(sub: string, reason: string): Effect.Effect<Uint8Array, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const { id: key, seed: made } = yield* this.#madeKey(reason);
      const id = yield* this.#env.device();
      const seed = made ?? (yield* this.#unseal(reason));
      // The chains it leaves behind: the one pinned, and one seen where this device was outside it (a station that
      // refused this device keeps it still, and is to be brought the new one, not taken for a lock begun elsewhere).
      const leaving = [this.#pinned.get(sub), this.#seen.get(sub)].flatMap((c) => (c?.[0] === undefined ? [] : [entryHash(c[0])]));
      this.#pinned.delete(sub);
      const signKey = this.#mySignKey();
      // (its wait made after the key's prompt: its time begins at the stations)
      yield* this.#append(sub, seed, "genesis", { sub, device: { key, id, label: this.#env.label(), ...(signKey !== null ? { sign_key: signKey } : {}) } }, false, this.asked());
      yield* this.#leave(sub, leaving);
      return seed;
    });
  }

  /// Whether this device could begin its person's lock with no one asked: it seals what it keeps, has made no key of its
  /// own yet (made now, its seed is in hand once; made before, reading it asks the person), and knows of no lock of
  /// theirs. What it read of the stations is `beginQuietly`'s to say.
  mayBeginQuietly(sub: string): boolean {
    const { host } = this.#env;
    return host.appKeys === true && host.secureSet !== undefined && this.#loaded.has(sub) && this.#myKey === null && this.standing(sub) === "none";
  }

  /// The person's lock begun here with no one asked, where the caller found this device the one to (views/lock.ts
  /// `ownLockFor`): only as `mayBeginQuietly` says, and once every station of theirs that may keep it answered a read
  /// of it this run (`stations.answered`; one begun before they answered could be a second lock for someone who has
  /// one). The key is made now and its seed, in hand, also puts on the devices approved in workspaces' locks
  /// (`#addApproved`). Whether it began.
  beginQuietly(sub: string): Effect.Effect<boolean, CoreError> {
    return Effect.gen({ self: this }, function* () {
      if (!this.mayBeginQuietly(sub) || this.#env.stations?.answered?.(sub) !== true) return false;
      const { id: key, seed } = yield* this.#madeKey(null);
      if (seed === null) return false;
      const id = yield* this.#env.device();
      const signKey = this.#mySignKey();
      const begun = this.#append(sub, seed, "genesis", { sub, device: { key, id, label: this.#env.label(), ...(signKey !== null ? { sign_key: signKey } : {}) } });
      // Not begun (no station nor the cloud took it): the key just made is forgotten, being on no chain and said
      // nowhere, so the next try makes one and has its seed in hand; kept, this device could begin only by asking.
      yield* Effect.tapError(begun, () => Effect.andThen(Effect.ignore(this.#env.host.storageDelete(KEY_ID)), Effect.sync(() => void (this.#myKey = null))));
      yield* this.#addApproved(sub, seed);
      return true;
    });
  }

  /// Turned on here, where the person has no lock yet (the cloud heard from: not knowing is not none).
  open(sub: string, reason: string): Effect.Effect<null, CoreError> {
    return Effect.gen({ self: this }, function* () {
      yield* this.refresh(sub, undefined, this.asked());
      if (this.standing(sub) === "none") yield* this.begin(sub, reason);
      return null;
    });
  }

  /// A chat's grant signed: the lock begun first where there is none, refused on a device outside it.
  signGrant(sub: string, body: Omit<GrantBody, "v" | "sub">, reason: string): Effect.Effect<SignedGrant, CoreError> {
    return Effect.gen({ self: this }, function* () {
      // (read of the grant's own station alone: every station of the person's asked, one offline held the person's
      // fingerprint back until it timed out, 2026-11-09)
      // Two waits: one for the read before the person is asked, one for what is signed after. One begun at the read
      // would be over once they answered, and stations that answer would not be waited on for what is signed: the
      // cloud alone would take it (the root AGENTS.md, The cloud is the account system).
      const read = yield* Effect.result(this.refresh(sub, body.station, this.asked()));
      const standing = this.standing(sub);
      // Not heard from the cloud, no lock known here is not no lock: one begun now would take its place.
      if (read._tag === "Failure" && standing === "none") return yield* Effect.fail(read.failure);
      if (standing === "outside") return yield* Effect.fail(new CoreError("personal_outside", t("core-misc.personal.outside")));
      if (standing === "replaced") return yield* Effect.fail(new CoreError("personal_replaced", t("core-misc.personal.replaced")));
      const seed = standing === "none" ? yield* this.begin(sub, reason) : yield* this.#unseal(reason);
      const within = this.asked();
      yield* this.#restate(sub, seed, within);
      yield* this.#addApproved(sub, seed, within);
      const whole: GrantBody = { v: 1, sub, ...body };
      return { body: whole, sig: { key: this.#myKey!, sig: hex(ed25519.sign(grantBytes(whole), seed)) } };
    });
  }

  /// What the person says of a rig of theirs, signed (rig-form.ts: a chat's grant, one taken back, its settings, the
  /// rig taken into a workspace): refused on a device outside their lock, which a rig is added with (`root`), so there
  /// is one. `station`: the station it goes through, read of alone.
  signRig<B>(sub: string, kind: RigKind, body: B, reason: string, station?: string): Effect.Effect<RigSigned<B>, CoreError> {
    return Effect.gen({ self: this }, function* () {
      yield* Effect.result(this.refresh(sub, station, this.asked()));
      const standing = this.standing(sub);
      // (a rig pinned its person's lock as it was added: with none known here, this device is not on the one it pinned)
      if (standing === "none" || standing === "outside") return yield* Effect.fail(new CoreError("personal_outside", t("core-misc.personal.outside")));
      if (standing === "replaced") return yield* Effect.fail(new CoreError("personal_replaced", t("core-misc.personal.replaced")));
      const seed = yield* this.#unseal(reason);
      return { body, sig: { key: this.#myKey!, sig: hex(ed25519.sign(rigBytes(kind, body, sha256), seed)) } };
    });
  }

  /// Grants signed at one go, the person asked once; refused on a device not on the lock.
  signGrants(sub: string, bodies: Omit<GrantBody, "v" | "sub">[], reason: string): Effect.Effect<SignedGrant[], CoreError> {
    return Effect.gen({ self: this }, function* () {
      if (this.standing(sub) !== "member") return yield* Effect.fail(new CoreError("personal_outside", t("core-misc.personal.outside")));
      const seed = yield* this.#unseal(reason);
      const within = this.asked();
      yield* this.#restate(sub, seed, within);
      yield* this.#addApproved(sub, seed, within);
      return bodies.map((body) => {
        const whole: GrantBody = { v: 1, sub, ...body };
        return { body: whole, sig: { key: this.#myKey!, sig: hex(ed25519.sign(grantBytes(whole), seed)) } };
      });
    });
  }

  /// The key's seed, the person asked, ahead of a code shown here: letting the new device in then asks nothing more.
  unseal(reason: string): Effect.Effect<Uint8Array, CoreError> {
    return this.#unseal(reason);
  }

  /// A new device let in here, face to face, signed with `seed` (else the person is asked now): the whole lock then, for
  /// it to pin. `device.sign_key`, the key it signs workspaces' locks with as its hello said, goes into its entry.
  addDevice(sub: string, device: Device, reason: string, seed: Uint8Array | null = null): Effect.Effect<Entry[], CoreError> {
    return Effect.gen({ self: this }, function* () {
      if (this.standing(sub) !== "member") return yield* Effect.fail(new CoreError("personal_outside", t("core-misc.personal.outside")));
      const signed = seed ?? (yield* this.#unseal(reason));
      // (one wait for all it signs, made after the person was asked)
      const within = this.asked();
      yield* this.#restate(sub, signed, within);
      const { key, id, label, sign_key } = device;
      // (a key not of the form is not written: nothing would read it, `signKeys`)
      yield* this.#append(sub, signed, "device", { key, id, label, ...(sign_key !== undefined && SIGN_KEY.test(sign_key) ? { sign_key } : {}) }, false, within);
      yield* this.#addApproved(sub, signed, within);
      return this.#pinned.get(sub) ?? [];
    });
  }

  removeDevice(sub: string, key: string, reason: string): Effect.Effect<null, CoreError> {
    return Effect.gen({ self: this }, function* () {
      if (this.standing(sub) !== "member") return yield* Effect.fail(new CoreError("personal_outside", t("core-misc.personal.outside")));
      const seed = yield* this.#unseal(reason);
      const within = this.asked();
      // (not said again where it takes itself off)
      if (key !== this.#myKey) yield* this.#restate(sub, seed, within);
      yield* this.#append(sub, seed, "device.remove", { key }, false, within);
      if (key !== this.#myKey) yield* this.#addApproved(sub, seed, within);
      this.#env.told?.(sub, this.#pinned.get(sub) ?? []);
      return null;
    });
  }

  /// The lock a device that let this one in brought (the connection proved by the code shown there): pinned.
  joined(sub: string, entries: Entry[]): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const chain = checkChain(entries, sub);
      if (chain === null || this.#myKey === null || !chain.devices.has(this.#myKey)) return yield* Effect.fail(new CoreError("personal_outside", t("core-misc.personal.outside")));
      yield* this.#pin(sub, entries);
      this.#seen.delete(sub);
      this.#env.changed();
    });
  }

  /// A lock the person says they began anew elsewhere: this device leaves the one pinned, and joins it or begins again.
  forget(sub: string, reason: string): Effect.Effect<null, CoreError> {
    return Effect.gen({ self: this }, function* () {
      if (this.#env.host.secureAsk) yield* Effect.mapError(this.#env.host.secureAsk(reason), asCoreError);
      this.#pinned.delete(sub);
      yield* Effect.mapError(this.#env.host.storageDelete(keptAs(sub)), asCoreError);
      this.#env.changed();
      return null;
    });
  }

  /// All this person's devices lost but this one or a new one: a new lock, in the place of the one the cloud has. The
  /// devices that pinned that one do not follow it by themselves (`replaced`).
  restart(sub: string, reason: string): Effect.Effect<null, CoreError> {
    return Effect.map(this.begin(sub, reason), () => null);
  }

  /// The accounts here this device is not on the lock of, of those signed in (`subs`), one asked first.
  outside(subs: string[]): string[] {
    return subs.filter((s) => this.standing(s) === "outside");
  }

  /// Who may let this device in: the devices on the lock the cloud has, as it says.
  approvers(sub: string): Device[] {
    const entries = this.#seen.get(sub) ?? this.#pinned.get(sub) ?? [];
    return [...(checkChain(entries, sub)?.devices.values() ?? [])].filter((d) => d.key !== this.#myKey);
  }

  /// The chain pinned here, and the hash its lock goes by (what a `person` entry names): none without one.
  entries(sub: string): Entry[] {
    return this.#pinned.get(sub) ?? [];
  }
  root(sub: string): string | null {
    const first = this.#pinned.get(sub)?.[0];
    return first === undefined ? null : entryHash(first);
  }

  /// What `adbShare` says of it.
  view(sub: string): J {
    const pinned = this.chain(sub);
    return {
      standing: this.standing(sub),
      sub,
      devices: [...(pinned?.devices.values() ?? [])].map((d) => ({ key: d.key, label: d.label, me: d.key === this.#myKey })),
    };
  }
}
