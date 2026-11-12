// A person's own lock: a chain, kept by the cloud and carried to their devices, of the keys that
// person's app devices sign with. Only a device on it adds or removes one; a new device joins face to face
// (views/pair.ts). What they sign with it means more than a login does: their phone lends itself to a chat only on a
// grant signed so, which it checks itself against the lock it pinned, whatever a station or the cloud says.
//
// The key is sealed so that each use asks the person (`user: true`: biometrics or the screen lock). Web pages have none:
// their code is the cloud's.
import { ed25519 } from "@noble/curves/ed25519.js";
import { Effect, Schedule, Semaphore } from "effect";
// @ts-ignore: the MoonBit build's JS, untyped
import * as rules from "../../../rules/js/rules.js";
import { CoreError, asCoreError } from "./error.ts";
import type { Host } from "./host.ts";
import { t } from "./i18n.ts";
import { type Entry, canonical, entryHash, signedBytes } from "./lock.ts";
import { AGAIN_MOST, type LogRules, againOf, hashOf, keep } from "./lock-keep.ts";
import { type Kind as RigKind, type Signed as RigSigned, signedBytes as rigBytes } from "./rig-form.ts";
import type { Runner } from "./runtime.ts";
import { fromUtf8, hex, parseJson, sha256, utf8 } from "./util.ts";
import { ed25519Ok } from "./vault/verified.ts";
import type { Asked } from "./views/lock.ts";
import { PENDING_MOST, type Pending, type PendingRow, bounded, pastBound, pendingFields, pendingRow, repeats } from "./lock-pending.ts";

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
/// The entries of the lock pinned a station showed that are off its chain (src/lock-keep.ts), kept beside it: the
/// chain stays where it was (`keptAs`, an array from the genesis, as a core from before reads it), and one from before
/// keeps none (it reads its chain as it did; this one reads a store without this as none aside).
const asideAs = (sub: string) => `personal-lock-aside-${hex(utf8(sub))}`;
/// What this device signed on the lock that no station took yet (src/lock-pending.ts), kept beside it: a core from
/// before never reads it (it knows none pending, and leaves them for this one).
const pendingAs = (sub: string) => `personal-lock-pending-${hex(utf8(sub))}`;
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

/// The kinds of a workspace's statements, which the rules' chain takes (`person_chain`) and their fold refuses until
/// every station takes them (station/src/mesh/person-chains.ts STATEMENTS): refused here as there.
const STATEMENTS = new Set(["ws.member", "ws.member.remove", "ws.station", "ws.station.remove"]);

/// A person log's rules for keeping (src/lock-keep.ts), of `sub`'s log of genesis hash `root`: its chain by the rules'
/// fork choice, one vote a device (rules/src/lock/chain.mbt `person_chain`).
function personRules(sub: string, root: string): LogRules {
  return {
    chain: (all) => {
      const out = rules.person_chain_js(all, root, crypto) as J;
      if ("error" in out) throw new Error(out.error);
      return { at: out.at, hashes: out.hashes, off: out.off };
    },
    pre: (e) => (e?.ws !== personOf(sub) ? "an entry of another lock" : STATEMENTS.has(e.kind) ? `unknown entry kind ${e.kind}` : null),
  };
}

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
  /// `carry`: after a read, the chain pinned (`chain`) brought to each station just read that lacks some of it and keeps
  /// what a device brings as another keeper's (views/lock.ts `personalStations`), forked.
  stations?: {
    read: (sub: string, at?: string) => Effect.Effect<Entry[][] | null>;
    bring: (sub: string, chain: Entry[], within?: Asked) => Effect.Effect<number | null | { later: Effect.Effect<number | null, CoreError> }, CoreError>;
    answered?: (sub: string) => boolean;
    carry?: (sub: string, chain: Entry[]) => void;
    /// The names of the person's stations, as their workspaces' views name them: what a pending entry waits for.
    names?: (sub: string) => string[];
  };
  /// A wait of ASKED_MS for a call a person waits on (views/lock.ts `asked`); none, the calls wait as long as the
  /// stations and the cloud take.
  asked?: () => Asked;
};

/// What a read made within a call's wait brings past it (`refresh`): nothing yet.
const LATE = Symbol("late");

/// What an entry of a person's own lock is about, for one that lost its place (src/lock-keep.ts `againOf`): the device
/// (its key) of `device` and `device.remove`; a genesis has none, and is never signed again.
function subjectOf(e: Entry): string | null {
  const key = (e.body as J)?.key;
  return (e.kind === "device" || e.kind === "device.remove") && typeof key === "string" ? `device ${key}` : null;
}

const PATH = "/v1/me/personal-lock";

export class PersonalLock {
  readonly #env: PersonalEnv;
  /// The chain pinned here, each person's; what the cloud has where this is not it.
  readonly #pinned = new Map<string, Entry[]>();
  /// The entries of the lock pinned a station showed that are off it (`asideAs`): the chain pinned is the rules'
  /// choice among them and it.
  readonly #aside = new Map<string, Entry[]>();
  readonly #seen = new Map<string, Entry[]>();
  readonly #loaded = new Set<string>();
  /// The roots of the chains this device left behind as it began anew, each person's: the stations may keep one still
  /// (they refused this device then, so the new chain reached only the cloud), and it is no lock begun elsewhere.
  readonly #left = new Map<string, Set<string>>();
  #myKey: string | null = null;
  /// This device's turn to sign each person's lock (`#append`): one entry at a time, each after the chain pinned as it
  /// begins.
  readonly #turns = new Map<string, ReturnType<typeof Semaphore.makeUnsafe>>();
  /// This device's entries that lost their place and were signed again or let be, by hash: once each (`#lost`,
  /// `#signAgain`).
  readonly #handled = new Set<string>();
  /// Of an entry signed again, how many signings it is from the one first signed (AGAIN_MOST at most).
  readonly #tries = new Map<string, number>();
  /// What this device signed that no station took yet, each person's (`pendingAs`): never on the chain pinned.
  readonly #pending = new Map<string, Pending[]>();
  /// Whether what is pending is being brought to the stations now (`#deliver`), and asked again meanwhile.
  readonly #delivering = new Map<string, { again: boolean }>();

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
        if (Array.isArray(said) && checkChain(said, sub) !== null) {
          this.#pinned.set(sub, said);
          const aside = parseJson(yield* Effect.orElseSucceed(env.host.storageGet(asideAs(sub)), () => null)) as unknown;
          // (one on the chain now, written before the chain was, is not aside)
          const on = new Set(said.map(hashOf));
          if (Array.isArray(aside)) this.#aside.set(sub, (aside as Entry[]).filter((e) => typeof e === "object" && e !== null && !on.has(hashOf(e))));
        }
        this.#left.set(sub, yield* this.#leftKept(sub));
        const pending = parseJson(yield* Effect.orElseSucceed(env.host.storageGet(pendingAs(sub)), () => null)) as unknown;
        if (Array.isArray(pending)) this.#pending.set(sub, (pending as Pending[]).filter((x) => typeof x === "object" && x !== null && typeof x.id === "string" && typeof x.entry === "object"));
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
        if (chains !== null) {
          const { chain, more } = this.#best(sub, chains);
          yield* this.#heard(sub, chain, true, more);
          stations.carry?.(sub, this.#pinned.get(sub) ?? []);
        }
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
    if (chains.length === 0 || !this.#loaded.has(sub)) return Effect.void;
    const { chain, more } = this.#best(sub, chains);
    return this.#heard(sub, chain, true, more);
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

  /// Of the chains the stations keep (each one a person's lock begun anew), those of the one pinned here (its genesis):
  /// the longest that holds (`chain`), and the entries of the others (`more`), kept with it, the rules choosing
  /// (`#heard`); none such, the one a station kept last (its latest), as the cloud's would be. One this device left
  /// behind as it began anew is none of them.
  #best(sub: string, chains: Entry[][]): { chain: Entry[]; more: Entry[] } {
    const pinned = this.#pinned.get(sub) ?? [];
    const root = pinned[0] === undefined ? null : entryHash(pinned[0]);
    const mine = root === null ? [] : chains.filter((c) => c[0] !== undefined && entryHash(c[0]) === root && !this.#isLeft(sub, c));
    let best: Entry[] | null = null;
    for (const c of mine) if (checkChain(c, sub) !== null && (best === null || c.length > best.length)) best = c;
    if (mine.length > 0) return { chain: best ?? [], more: mine.filter((c) => c !== best).flat() };
    for (const c of chains) if (c.length > 0 && !this.#isLeft(sub, c) && checkChain(c, sub) !== null) best = c;
    return { chain: best ?? [], more: [] };
  }

  /// A chain heard (of the stations, `stations`, or the cloud) and, of the stations, the entries of the others of the
  /// lock pinned (`more`, `#best`). Of the lock pinned: one that goes on from it is pinned; one behind on it is brought it;
  /// one that parts from it (another entry at a place pinned) is kept with it and what is aside, and the chain pinned is
  /// the rules' choice among them (src/lock-keep.ts): a branch of the same lock is no lock begun anew (`replaced`, which
  /// only a chain of another genesis is). Where this device's own entry lost its place, it is not on the chain pinned:
  /// `outside` until it is put on again.
  #heard(sub: string, heard: Entry[], stations = false, more: Entry[] = []): Effect.Effect<void, CoreError> {
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
      const ofPinned = pinned.length > 0 && entries.length > 0 && entryHash(entries[0]!) === entryHash(pinned[0]!);
      if ((ofPinned && !grows && !behind) || (pinned.length > 0 && more.length > 0)) {
        const t = this.#chosen(sub, [...(ofPinned ? entries : []), ...more]);
        if (t !== null && t.changed) yield* this.#pin(sub, t.kept.entries, t.kept.aside);
        this.#seen.delete(sub);
        // (who was read behind on the chain pinned, or keeping none of it: brought it, as below)
        if (behind || entries.length === 0) {
          const now = this.#pinned.get(sub) ?? [];
          if (stations) yield* Effect.ignore(this.#env.stations!.bring(sub, now));
          else this.#env.runner.fork(Effect.ignore(this.#env.cloud(sub, "POST", PATH, { entries: now })));
        }
      } else if (grows) {
        this.#seen.delete(sub);
        if (entries.length > pinned.length) yield* this.#pin(sub, entries);
      } else if (pinned.length > 0 && (entries.length === 0 || behind)) {
        // (the cloud, or the stations, lost it, never had it, or are behind on it: brought back)
        if (stations) yield* Effect.ignore(this.#env.stations!.bring(sub, pinned));
        // (forked, never waited on: what the cloud keeps is for the devices from before, and counts for nothing here)
        else this.#env.runner.fork(Effect.ignore(this.#env.cloud(sub, "POST", PATH, { entries: pinned })));
      } else if (holds && entries.length > 0 && stations && pinned.length === 0 && (yield* this.#putOnBy(sub, entries))) {
        yield* this.#pin(sub, entries);
        this.#seen.delete(sub);
      } else if (holds && entries.length > 0) this.#seen.set(sub, entries);
      else this.#seen.delete(sub);
      // Told only when it changed: what is told retries the stations that refused this device, and each refusal brings
      // this same chain again (views/lock.ts heardRefused), so telling it unchanged would ask them again at once, endlessly.
      if (this.#stands(sub) !== was) this.#env.changed();
      // A station of theirs answered: what is pending here is brought to them now.
      if (stations) this.#deliver(sub);
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

  /// The lock pinned with `brought` kept (src/lock-keep.ts): the chain the rules choose among it, what is aside and
  /// what was brought; null where they find none (the chain pinned does not hold by them).
  #chosen(sub: string, brought: Entry[]): ReturnType<typeof keep> | null {
    const pinned = this.#pinned.get(sub) ?? [];
    if (pinned.length === 0) return null;
    try {
      return keep({ entries: pinned, aside: this.#aside.get(sub) ?? [] }, brought, personRules(sub, entryHash(pinned[0]!)));
    } catch {
      return null;
    }
  }

  /// What is held of `sub`'s lock: the chain pinned and one seen that does not go on from it, by their last entries.
  #stands(sub: string): string {
    const last = (c: Entry[] | undefined) => (c === undefined || c.length === 0 ? "" : `${c.length}:${entryHash(c[c.length - 1]!)}`);
    return `${last(this.#pinned.get(sub))}|${last(this.#seen.get(sub))}`;
  }

  /// `entries` pinned, and `aside` kept beside them (by default what was aside, where it is of the same lock and off
  /// them): what is aside written first, so that a chain written is never without what it moved off (what is aside is
  /// read less what is on the chain).
  #pin(sub: string, entries: Entry[], aside?: Entry[]): Effect.Effect<void, CoreError> {
    const was = this.#pinned.get(sub) ?? [];
    const same = was[0] !== undefined && entries[0] !== undefined && entryHash(was[0]) === entryHash(entries[0]);
    const on = new Set(entries.map(hashOf));
    const had = this.#aside.get(sub) ?? [];
    const off = aside ?? (same ? had.filter((e) => !on.has(hashOf(e))) : []);
    this.#pinned.set(sub, entries);
    this.#aside.set(sub, off);
    // (what was pending and is on the chain now: a station took it; the cloud sent it then, never waited on)
    const pending = this.#pending.get(sub) ?? [];
    if (pending.some((x) => on.has(hashOf(x.entry)))) {
      this.#putPending(sub, pending.filter((x) => !on.has(hashOf(x.entry))));
      const taken = pending.filter((x) => on.has(hashOf(x.entry))).map((x) => x.entry);
      this.#env.runner.fork(Effect.ignore(this.#env.cloud(sub, "POST", PATH, { entries: taken })));
    }
    const keptAside = off.length === had.length && off.every((e, i) => e === had[i]) ? Effect.void : Effect.mapError(off.length === 0 ? this.#env.host.storageDelete(asideAs(sub)) : this.#env.host.storageSet(asideAs(sub), utf8(JSON.stringify(off))), asCoreError);
    return Effect.andThen(keptAside, Effect.mapError(this.#env.host.storageSet(keptAs(sub), utf8(JSON.stringify(entries))), asCoreError));
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

  /// One entry more, signed here, brought to the person's stations and pinned once one took it; to the cloud then too,
  /// for the stations and devices from before that read it there, not waited on. Taken by none and refused by none by a
  /// call's wait (`within`, views/lock.ts ASKED_MS) or TAKEN_MS, it is pending (`#pend`): the turn given up, the call
  /// answered at once (with the entry, `Pending`), and it is brought to the stations as one is next read (`#deliver`).
  /// The cloud's taking never counts but where no station could be asked at all (the person has none this device knows
  /// of), and for a genesis, which begins a lock no station keeps yet: those the cloud takes as before.
  /// `once`: the cloud, where it is what takes it, asked once and not again when it limits (an entry that rides on
  /// another act, which is not to wait a minute for it: `#restate`); such an entry is the core's own, not shown pending.
  ///
  /// One entry at a time (the person's `turn`, a Semaphore of one, as a workspace's lock has, views/lock.ts
  /// `Lock.append`, whose turn is never waited for inside this one nor this one inside it): signed after the chain pinned
  /// as the turn begins, brought, and the turn given up once it is pinned, refused, or pending. One that lost its place
  /// (a station's 409; a read that moved the chain pinned while it was brought) is the turn's still (`#lost`), with the
  /// seed in hand: done, refused, or signed again after the head. One that would only say again what a pending one says
  /// answers as that one; past PENDING_MOST pending, none more is signed.
  #append(sub: string, seed: Uint8Array, kind: string, body: unknown, once = false, within?: Asked): Effect.Effect<Pending | null, CoreError> {
    const ahead = Effect.suspend((): Effect.Effect<Effect.Effect<Pending | null, CoreError>, CoreError> => {
      const waiting = (this.#pending.get(sub) ?? []).filter((x) => x.state === "waiting");
      const same = kind === "genesis" ? undefined : waiting.find((x) => repeats(x, kind, body));
      if (same !== undefined) return Effect.succeed(Effect.succeed(same));
      if (kind !== "genesis" && waiting.length >= PENDING_MOST) return Effect.fail(new CoreError("lock_pending_full", pastBound(this.#env.stations?.names?.(sub) ?? [])));
      return this.#signHere(sub, seed, kind, body, once, within, 0, null);
    });
    return Effect.flatMap(this.#turn(sub).withPermits(1)(ahead), (rest) => rest);
  }

  #turn(sub: string): ReturnType<typeof Semaphore.makeUnsafe> {
    let turn = this.#turns.get(sub);
    if (turn === undefined) this.#turns.set(sub, (turn = Semaphore.makeUnsafe(1)));
    return turn;
  }

  /// What is pending of `sub`'s lock now, put: kept to the bound, written beside the lock (forked: a failure to write
  /// leaves it held this run), the pages told.
  #putPending(sub: string, items: readonly Pending[]): void {
    const kept = bounded(items);
    this.#pending.set(sub, kept);
    const host = this.#env.host;
    this.#env.runner.fork(Effect.ignore(kept.length === 0 ? host.storageDelete(pendingAs(sub)) : host.storageSet(pendingAs(sub), utf8(JSON.stringify(kept))), { log: "Unhandled", message: "personal lock: pending kept" }));
    this.#env.changed();
  }

  /// What is pending of `sub`'s lock, as rows of a topic (`AdbPersonal` `pending`): what a person did, not the core's own.
  pending(sub: string): PendingRow[] {
    return this.pendingShown(sub).map((x) => x.row);
  }

  /// The same, each with what it is (`item`): a workspace's `lock` topic says them beside its own (views/lock.ts
  /// `ownPendingRows`), one done in both once.
  pendingShown(sub: string): { item: Pending; row: PendingRow }[] {
    const names = this.#env.stations?.names?.(sub) ?? [];
    return (this.#pending.get(sub) ?? []).filter((x) => x.act !== null).map((item) => ({ item, row: pendingRow(item, names) }));
  }

  /// A failed one the person read (`adb.personalPendingDismiss`): dropped.
  dismissPending(sub: string, id: string): void {
    const items = this.#pending.get(sub) ?? [];
    if (items.some((x) => x.id === id && x.state === "failed")) this.#putPending(sub, items.filter((x) => x.id !== id));
  }

  /// In the turn: `e` kept pending, or, signed again (`of`, the id of the one first signed), in that one's place.
  #pend(sub: string, e: Entry, tries: number, of: string | null, shown: boolean): Pending {
    const items = this.#pending.get(sub) ?? [];
    const id = of ?? entryHash(e);
    const had = items.find((x) => x.id === id);
    const key = (e.body as J)?.key;
    const label = [...this.#lastSaid(sub).values()].find((d) => d.device.key === key)?.device.label ?? (e.body as J)?.label;
    const name = typeof label === "string" && label !== "" ? label : t("web-pages.security.appDevice");
    const act = !shown || key === this.#myKey ? null : e.kind === "device.remove" ? "removeDevice" : e.kind === "device" ? "approve" : null;
    const made: Pending = had !== undefined ? { ...had, entry: e, state: "waiting", ...(tries > 0 ? { tries } : {}) } : { id, entry: e, act, name, at: this.#env.host.nowMs(), state: "waiting", ...(tries > 0 ? { tries } : {}) };
    this.#putPending(sub, had !== undefined ? items.map((x) => (x.id === id ? made : x)) : [...items, made]);
    return made;
  }

  /// In a turn: `e` (of `chain`), pending, taken by a station past waiting: pinned where it goes on from the chain
  /// pinned (else the next read or delivery decides), pending no more and the cloud sent it as it is pinned (`#pin`).
  #tookLate(sub: string, e: Entry, chain: Entry[]): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const now = this.#pinned.get(sub) ?? [];
      if (now.length === e.seq && (e.seq === 0 || entryHash(now[e.seq - 1]!) === e.prev)) yield* this.#pin(sub, [...now, e]);
      else if (!now.some((x) => hashOf(x) === hashOf(e))) {
        const t = this.#chosen(sub, chain);
        if (t !== null && t.changed) yield* this.#pin(sub, t.kept.entries, t.kept.aside);
      }
      // (pending no more as it is pinned, and the cloud sent it then: `#pin`; not pinned, it stays pending, the next read
      // or delivery deciding)
      this.#seen.delete(sub);
      this.#env.changed();
    });
  }

  /// What is pending of `sub`'s lock brought to their stations, one of them having answered a read (`#heard`): in the
  /// turn, oldest first, one run at a time. One whose parent is the head pinned still is brought as it is: taken, pinned
  /// and pending no more; refused, the stations read again and it is decided as below. One whose parent is not the head
  /// any more needs the seed to be signed again, which only an act of the person's has in hand (`#signAgain`, which
  /// signs it again first where it comes first): `failed`, saying to look and do it again
  /// (`core-misc.lock.pending.failed`); done where the chain says it already (againOf). None answering: left waiting.
  #deliver(sub: string): void {
    if (!(this.#pending.get(sub) ?? []).some((x) => x.state === "waiting") || this.#env.stations === undefined) return;
    const d = this.#delivering.get(sub);
    if (d !== undefined) return void (d.again = true);
    const state = { again: true };
    this.#delivering.set(sub, state);
    const stations = this.#env.stations;
    const once = Effect.gen({ self: this }, function* () {
      const passes = new Map<string, number>();
      for (;;) {
        const pinned = this.#pinned.get(sub) ?? [];
        const item = (this.#pending.get(sub) ?? []).find((x) => x.state === "waiting" && (passes.get(x.id) ?? 0) < 2);
        if (item === undefined || pinned.length === 0) return;
        passes.set(item.id, (passes.get(item.id) ?? 0) + 1);
        const e = item.entry;
        const set = (how: Partial<Pending> | null) => this.#putPending(sub, (this.#pending.get(sub) ?? []).flatMap((x) => (x.id !== item.id ? [x] : how === null ? [] : [{ ...x, ...how }])));
        if (pinned.some((x) => hashOf(x) === hashOf(e))) {
          set(null);
          continue;
        }
        if (e.seq !== pinned.length || e.prev !== entryHash(pinned[pinned.length - 1]!)) {
          const how = againOf(pinned, this.#aside.get(sub) ?? [], e, subjectOf);
          if (how === "done") set(null);
          else set({ state: "failed", what: item.name });
          continue;
        }
        const chain = [...pinned, e];
        const r = yield* Effect.result(stations.bring(sub, chain));
        if (r._tag === "Success" && typeof r.success === "number" && r.success > 0) {
          yield* this.#tookLate(sub, e, chain);
          continue;
        }
        if (r._tag === "Failure" && r.failure.code === "lock_refused") {
          const refusal = r.failure;
          yield* Effect.ignore(this.refresh(sub), { log: "Unhandled", message: "personal lock read after a refusal" });
          const now = this.#pinned.get(sub) ?? [];
          if (now.length === e.seq && e.prev === entryHash(now[now.length - 1]!)) set({ state: "failed", why: refusal.message });
          continue;
        }
        return;
      }
    });
    this.#env.runner.fork(Effect.ensuring(
      Effect.gen({ self: this }, function* () {
        while (state.again) {
          state.again = false;
          yield* Effect.ignore(this.#turn(sub).withPermits(1)(once), { log: "Unhandled", message: "personal lock: pending brought" });
        }
      }),
      Effect.sync(() => void this.#delivering.delete(sub)),
    ));
  }

  /// In the turn: one entry signed after the chain pinned now (a genesis: none, the one pinned left), brought, and what
  /// is left of it once the turn is given up (the cloud's taking, then where it landed, `#landed`, in a turn again).
  /// `tries`: how many signings again of one that lost its place this is (0: the first signing); `of`: of a pending one,
  /// its id. Pending: the entry, which the caller answers with.
  #signHere(sub: string, seed: Uint8Array, kind: string, body: unknown, once: boolean, within: Asked | undefined, tries: number, of: string | null): Effect.Effect<Effect.Effect<Pending | null, CoreError>, CoreError> {
    return Effect.gen({ self: this }, function* () {
      if (kind === "genesis") this.#pinned.delete(sub);
      const e = this.#entry(sub, seed, this.#myKey!, kind, body);
      const chain = [...(e.seq === 0 ? [] : (this.#pinned.get(sub) ?? [])), e];
      // (signed again: only where the rules still take it after the head; else the lock changed meanwhile)
      if (tries > 0 && checkChain(chain, sub) === null) return yield* Effect.fail(this.#changed(sub, e));
      if (tries > 0) this.#tries.set(hashOf(e), tries);
      const toCloud = this.#env.cloud(sub, "POST", PATH, { entries: [e] });
      const cloudTakes = once ? toCloud : Effect.retry(toCloud, { times: LIMITED_TRIES, schedule: Schedule.spaced(LIMITED_WAIT), while: (e) => e.code === "rate_limited" }); // timer: a retry after a failure (429)
      const brought = this.#env.stations ? yield* Effect.result(this.#env.stations.bring(sub, chain, within)) : null;
      // (refused where it was heard: another device's entry at its place, at a station)
      if (brought !== null && brought._tag === "Failure") {
        if (brought.failure.code === "lock_refused") return yield* this.#lost(sub, seed, e, once, within, tries, brought.failure, true, of);
        return yield* Effect.fail(brought.failure);
      }
      const taken = brought === null ? null : brought.success;
      const landed = this.#landed(sub, seed, e, chain, once, within, tries);
      const inTurn = <A>(work: Effect.Effect<Effect.Effect<A, CoreError>, CoreError>) => Effect.flatMap(this.#turn(sub).withPermits(1)(work), (rest) => rest);
      if (typeof taken === "number" && taken > 0) {
        this.#env.runner.fork(Effect.ignore(toCloud));
        return yield* landed;
      }
      // No station to ask (none this device knows of), or a genesis: the cloud's, as before.
      if (taken === null || kind === "genesis") {
        if (typeof taken === "object" && taken !== null) this.#env.runner.fork(Effect.ignore(taken.later));
        return Effect.andThen(cloudTakes, inTurn(landed));
      }
      // Pending: none took it nor refused it by the call's wait (or TAKEN_MS). Those still answering are listened to: one
      // taking it then, it is pinned (`#tookLate`); one refusing it, decided as it is next delivered.
      const made = this.#pend(sub, e, tries, of, !once && within !== undefined);
      if (typeof taken === "object") {
        this.#env.runner.fork(Effect.ignore(Effect.flatMap(taken.later, (n) => (n !== null && n > 0 ? this.#turn(sub).withPermits(1)(this.#tookLate(sub, e, chain)) : Effect.void))));
      }
      return Effect.succeed(made);
    });
  }

  /// In a turn: `e` (of `chain`, as brought) taken by a station or the cloud, pinned as the chain stands now: a read
  /// answered while it was brought may have pinned it already (a station's, taken after the station took it: put on
  /// again, the chain held it twice, and a device let in face to face was brought a lock that does not hold and told it
  /// was not let in, 2026-11-12), or another entry in its place (two stations, each taking a different one), or a chain
  /// it does not follow. Never one the chain does not hold. Where the read moved the chain pinned to another branch, the
  /// entry is kept with it as the stations' entries are (it hangs below the one it was signed after): done where the
  /// rules' choice is a chain it is on, else it lost its place (`#lost`).
  #landed(sub: string, seed: Uint8Array, e: Entry, chain: Entry[], once: boolean, within: Asked | undefined, tries: number): Effect.Effect<Effect.Effect<Pending | null, CoreError>, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const now = this.#pinned.get(sub) ?? [];
      const there = now[e.seq];
      const follows = now.length === e.seq && (e.seq === 0 || entryHash(now[e.seq - 1]!) === e.prev);
      if (follows) yield* this.#pin(sub, [...now, e]);
      else if (there === undefined || entryHash(there) !== entryHash(e)) {
        const t = e.seq === 0 ? null : this.#chosen(sub, chain);
        if (t !== null && t.changed) yield* this.#pin(sub, t.kept.entries, t.kept.aside);
        if (!(this.#pinned.get(sub) ?? []).some((x) => hashOf(x) === hashOf(e))) return yield* this.#lost(sub, seed, e, once, within, tries, new CoreError("lock_refused", "another entry took its place", 409), false, null);
      }
      this.#seen.delete(sub);
      this.#env.changed();
      return Effect.succeed(null);
    });
  }

  /// In the turn, with the seed in hand: `e`, signed here, that lost its place (`refusal`: why, as a station or the chain
  /// pinned said it; `read`: the stations read first, a station having refused it). Decided by the chain pinned now
  /// (src/lock-keep.ts `againOf`, its subject the device it is about): done (on the chain, or the same said since its
  /// parent); refused in words that say what to do (`#changed`: someone did otherwise with that device since, or the
  /// rules take it no more after the head); refused as it was (its parent the head still, a genesis, or signed again
  /// AGAIN_MOST times); else signed again after the head, brought, in the same turn.
  #lost(sub: string, seed: Uint8Array, e: Entry, once: boolean, within: Asked | undefined, tries: number, refusal: CoreError, read: boolean, of: string | null): Effect.Effect<Effect.Effect<Pending | null, CoreError>, CoreError> {
    return Effect.gen({ self: this }, function* () {
      this.#handled.add(hashOf(e));
      if (e.seq === 0) return yield* Effect.fail(refusal);
      // (the stations as they stand, waited for: the one that refused answered just now)
      if (read) yield* Effect.ignore(this.refresh(sub), { log: "Unhandled", message: "personal lock read after a refusal" });
      const how = againOf(this.#pinned.get(sub) ?? [], this.#aside.get(sub) ?? [], e, subjectOf);
      if (how === "done") {
        this.#seen.delete(sub);
        this.#env.changed();
        return Effect.succeed(null);
      }
      if (how === "otherwise") return yield* Effect.fail(this.#changed(sub, e));
      if (how === "unmoved" || tries >= AGAIN_MOST) return yield* Effect.fail(refusal);
      return yield* this.#signHere(sub, seed, e.kind, e.body, once, within, tries + 1, of);
    });
  }

  /// An entry that lost its place not signed again, the lock having changed meanwhile: what the person is told, what to
  /// do (look how it stands, do it again if still wanted), as `lock_refused`; the device by its name.
  #changed(sub: string, e: Entry): CoreError {
    const key = (e.body as J)?.key;
    const said = [...this.#lastSaid(sub).values()].find((d) => d.device.key === key)?.device.label ?? (e.body as J)?.label;
    const what = typeof said === "string" && said !== "" ? said : t("web-pages.security.appDevice");
    return new CoreError("lock_refused", t("core-misc.lock.changedMeanwhile", { what }), 409);
  }

  /// With the seed in hand for something else (where `#restate` runs): this device's entries the chain pinned left (kept
  /// aside, a read having moved it to another branch while no seed was in hand), each signed again after the head once,
  /// where that still says what was meant (`#lost`'s rules); and those pending whose parent is not the head pinned any
  /// more, by the same rules, before a delivery finds them so (`#deliver`, which can only say they failed). Nothing more
  /// is asked of the person; one let be just stops.
  #signAgain(sub: string, seed: Uint8Array, within?: Asked): Effect.Effect<void> {
    return Effect.gen({ self: this }, function* () {
      const lost = [...(this.#aside.get(sub) ?? [])].sort((a, b) => a.seq - b.seq).filter((e) => e.seq > 0 && e.sig?.key === this.#myKey && !this.#handled.has(hashOf(e)));
      for (const e of lost) {
        this.#handled.add(hashOf(e));
        const tries = this.#tries.get(hashOf(e)) ?? 0;
        const inTurn = Effect.suspend((): Effect.Effect<Effect.Effect<Pending | null, CoreError>, CoreError> => {
          if (tries >= AGAIN_MOST || againOf(this.#pinned.get(sub) ?? [], this.#aside.get(sub) ?? [], e, subjectOf) !== "sign") return Effect.succeed(Effect.succeed(null));
          return this.#signHere(sub, seed, e.kind, e.body, true, within, tries + 1, null);
        });
        yield* Effect.ignore(Effect.flatMap(this.#turn(sub).withPermits(1)(inTurn), (rest) => rest), { log: "Unhandled", message: "personal lock: an entry that lost its place signed again" });
      }
      for (const item of [...(this.#pending.get(sub) ?? [])]) {
        if (item.state !== "waiting") continue;
        const inTurn = Effect.suspend((): Effect.Effect<Effect.Effect<Pending | null, CoreError>, CoreError> => {
          const pinned = this.#pinned.get(sub) ?? [];
          const now = (this.#pending.get(sub) ?? []).find((x) => x.id === item.id);
          const e = now?.entry;
          if (now === undefined || now.state !== "waiting" || e === undefined || pinned.length === 0 || (e.seq === pinned.length && e.prev === entryHash(pinned[pinned.length - 1]!))) return Effect.succeed(Effect.succeed(null));
          const how = againOf(pinned, this.#aside.get(sub) ?? [], e, subjectOf);
          const drop = (how: Partial<Pending> | null) => Effect.sync(() => this.#putPending(sub, (this.#pending.get(sub) ?? []).flatMap((x) => (x.id !== item.id ? [x] : how === null ? [] : [{ ...x, ...how }]))));
          if (how === "done") return Effect.as(drop(null), Effect.succeed(null));
          if (how !== "sign" || (now.tries ?? 0) >= AGAIN_MOST) return Effect.as(drop({ state: "failed", what: now.name }), Effect.succeed(null));
          return Effect.catch(this.#signHere(sub, seed, e.kind, e.body, false, within, (now.tries ?? 0) + 1, item.id), (err) => Effect.as(drop({ state: "failed", what: now.name, ...(err.code === "lock_refused" ? {} : { why: err.message }) }), Effect.succeed(null)));
        });
        yield* Effect.ignore(Effect.flatMap(this.#turn(sub).withPermits(1)(inTurn), (rest) => rest), { log: "Unhandled", message: "personal lock: a pending entry signed again" });
      }
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
      // (the one pinned let go of in the turn, as the genesis is signed: `#signHere`)
      const leaving = [this.#pinned.get(sub), this.#seen.get(sub)].flatMap((c) => (c?.[0] === undefined ? [] : [entryHash(c[0])]));
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
      yield* this.#signAgain(sub, seed, within);
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
      yield* this.#signAgain(sub, seed, within);
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
      yield* this.#signAgain(sub, signed, within);
      yield* this.#restate(sub, signed, within);
      const { key, id, label, sign_key } = device;
      // (a key not of the form is not written: nothing would read it, `signKeys`)
      const pending = yield* this.#append(sub, signed, "device", { key, id, label, ...(sign_key !== undefined && SIGN_KEY.test(sign_key) ? { sign_key } : {}) }, false, within);
      const pinned = this.#pinned.get(sub) ?? [];
      if (pending === null) {
        yield* this.#addApproved(sub, signed, within);
        return this.#pinned.get(sub) ?? [];
      }
      // Pending (no station of theirs up): the new device is given the chain with its entry on, which it pins and brings
      // to the stations itself as one is next up (it goes on from what they keep, signed by a device on the lock), as
      // this device does (`#deliver`). Given the chain without it, it was told it was not let in, face to face.
      const e = pending.entry;
      return e.seq === pinned.length && e.prev === (pinned.length === 0 ? null : entryHash(pinned[pinned.length - 1]!)) ? [...pinned, e] : pinned;
    });
  }

  /// A device taken off: null, or, no station of theirs up, `{pending}`, its row (as the topic shows it).
  removeDevice(sub: string, key: string, reason: string): Effect.Effect<{ pending: PendingRow } | null, CoreError> {
    return Effect.gen({ self: this }, function* () {
      if (this.standing(sub) !== "member") return yield* Effect.fail(new CoreError("personal_outside", t("core-misc.personal.outside")));
      const seed = yield* this.#unseal(reason);
      const within = this.asked();
      // (not said again where it takes itself off, nor what it lost signed again)
      if (key !== this.#myKey) yield* this.#signAgain(sub, seed, within);
      if (key !== this.#myKey) yield* this.#restate(sub, seed, within);
      const pending = yield* this.#append(sub, seed, "device.remove", { key }, false, within);
      if (key !== this.#myKey && pending === null) yield* this.#addApproved(sub, seed, within);
      this.#env.told?.(sub, this.#pinned.get(sub) ?? []);
      return pending === null ? null : { pending: pendingRow(pending, this.#env.stations?.names?.(sub) ?? []) };
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
      this.#aside.delete(sub);
      yield* Effect.mapError(this.#env.host.storageDelete(keptAs(sub)), asCoreError);
      yield* Effect.ignore(this.#env.host.storageDelete(asideAs(sub)));
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
      ...pendingFields(this.pending(sub)),
    };
  }
}
