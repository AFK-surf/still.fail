// A person's own lock (docs/personal-lock.md): a chain, kept by the cloud and carried to their devices, of the keys that
// person's app devices sign with. Only a device on it adds or removes one; a new device joins face to face
// (views/pair.ts). What they sign with it means more than a login does: their phone lends itself to a chat only on a
// grant signed so, which it checks itself against the lock it pinned, whatever a station or the cloud says.
//
// The key is sealed so that each use asks the person (`user: true`: biometrics or the screen lock). Web pages have none:
// their code is the cloud's.
import { ed25519 } from "@noble/curves/ed25519.js";
import { Effect, Semaphore } from "effect";
// @ts-ignore: the MoonBit build's JS, untyped
import * as rules from "../../../rules/js/rules.js";
import { CoreError, asCoreError } from "./error.ts";
import type { Host } from "./host.ts";
import { t } from "./i18n.ts";
import { type Entry, canonical, entryHash, signedBytes } from "./lock.ts";
import type { Runner } from "./runtime.ts";
import { fromUtf8, hex, parseJson, sha256, toJsonBytes, utf8 } from "./util.ts";

// deno-lint-ignore no-explicit-any
type J = any;

/// A lock's name in its entries (and among what a new device asks to be let into).
export const personOf = (sub: string) => `person:${sub}`;
export const isPerson = (where: string) => where.startsWith("person:");

const KEY = "personal-signer";
/// The key's public half, read without asking anyone.
const KEY_ID = "personal-signer-id";
const keptAs = (sub: string) => `personal-lock-${hex(utf8(sub))}`;
// Kept separately so an older client can still read the pinned chain's existing array format.
const replacedAs = (sub: string) => `personal-replaced-${hex(utf8(sub))}`;
// A first genesis signed here but not yet known to have reached the cloud.
const firstAs = (sub: string) => `personal-first-${hex(utf8(sub))}`;
// A confirmed join or restart whose new pin and replacement cleanup have not both finished.
const acceptingAs = (sub: string) => `personal-accepting-${hex(utf8(sub))}`;
const unhex = (h: string) => (/^([0-9a-f]{2})*$/.test(h) ? Uint8Array.from(h.match(/../g) ?? [], (b) => parseInt(b, 16)) : new Uint8Array());
const asKey = (id: string) => (id.startsWith("ed25519:") ? unhex(id.slice(8)) : new Uint8Array());

const verifies = (id: string, sig: string, bytes: Uint8Array) => {
  try {
    return ed25519.verify(unhex(sig), bytes, asKey(id));
  } catch {
    return false;
  }
};

export type Device = { key: string; id: string; label: string };
export type Chain = { devices: Map<string, Device>; hash: string | null };

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
  try {
    const out = rules.person_fold_js(entries, sub, crypto) as J;
    return "error" in out ? null : { devices: new Map((out.devices as Device[]).map((d) => [d.key, d])), hash: out.head };
  } catch {
    return null;
  }
}

/// Both sides are already checked or locally signed; compare the entries as the hash chain does.
function prefixOf(prefix: readonly Entry[], entries: readonly Entry[]): boolean {
  return prefix.length <= entries.length && prefix.every((e, i) => entryHash(e) === entryHash(entries[i]!));
}

type ChainPlace = { length: number; head: string | null };
type Acceptance = { v: 1; kind: "join" | "restart"; observed: string | null; base: ChainPlace; target: Entry[] };
type Forgetting = { v: 1; kind: "forget" };
type PendingChoice = Acceptance | Forgetting;
const placeOf = (entries: readonly Entry[]): ChainPlace => ({ length: entries.length, head: entries.length === 0 ? null : entryHash(entries[entries.length - 1]!) });
const isPlace = (value: J): value is ChainPlace => Number.isSafeInteger(value?.length) && value.length >= 0 &&
  (value.length === 0 ? value.head === null : typeof value.head === "string" && /^[0-9a-f]{64}$/.test(value.head));

/// What a person's device signs for a chat's grant of their phone.
export type GrantBody = { v: 1; sub: string; station: string; request: string; session: string; chat: string; scope: "hour" | "chat"; exp: number };
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
  /// The device host before per-core wrappers: overlapping cores on it share signer creation.
  signerHost?: Host;
  runner: Runner;
  /// A request to the cloud as this person.
  cloud: (sub: string, method: string, path: string, body: unknown) => Effect.Effect<unknown, CoreError>;
  /// This device's base key (as a pairing dials it), and its name.
  device: () => Effect.Effect<string, CoreError>;
  label: () => string;
  changed: () => void;
};

const PATH = "/v1/me/personal-lock";
// Older clouds ignore an unknown `expect` field on PATH. This distinct route guarantees a guarded restore is never
// treated as an unconditional reset during a rolling cloud update.
const RESTORE_PATH = `${PATH}/append`;
/// The guarded restore route's UTF-8 request limit (cloud/src/api.ts).
const POST_BYTES = 256 * 1024;
/// The cloud's account quota reports Retry-After: 60 seconds; a later refresh can resume if it remains busy.
const RATE_RETRY_MS = 60_000;

// Cores can overlap while an earlier one is closing. When they use the same host, they must not each create a signer.
const keyWriters = new WeakMap<Host, ReturnType<typeof Semaphore.makeUnsafe>>();
function keyWriter(host: Host): ReturnType<typeof Semaphore.makeUnsafe> {
  let writer = keyWriters.get(host);
  if (!writer) keyWriters.set(host, writer = Semaphore.makeUnsafe(1));
  return writer;
}

export class PersonalLock {
  readonly #env: PersonalEnv;
  /// The chain pinned here, each person's; what the cloud has where this is not it.
  readonly #pinned = new Map<string, Entry[]>();
  readonly #seen = new Map<string, Entry[]>();
  /// A verified chain observed without pinning, kept until the person accepts or forgets it.
  readonly #seenKept = new Set<string>();
  readonly #seenDirty = new Set<string>();
  readonly #accepting = new Map<string, PendingChoice>();
  readonly #acceptSaved = new Set<string>();
  readonly #first = new Map<string, Entry>();
  readonly #loaded = new Set<string>();
  /// Forgetting or replacing a lock invalidates reads and pairing attempts started against its earlier state.
  readonly #generations = new Map<string, number>();
  /// A device's storage writes may complete out of order; serialize each account's pin and forget.
  readonly #writing = new Map<string, ReturnType<typeof Semaphore.makeUnsafe>>();
  /// A pin that reached memory but whose storage write failed must be tried again even if the cloud says it unchanged.
  readonly #dirty = new Set<string>();
  /// The signer is shared by every account on the device, so its creation is serialized across accounts.
  readonly #keyWriter: ReturnType<typeof Semaphore.makeUnsafe>;
  #myKey: string | null = null;

  constructor(env: PersonalEnv) {
    this.#env = env;
    this.#keyWriter = keyWriter(env.signerHost ?? env.host);
  }

  /// The chain pinned here as read so far, what it says.
  chain(sub: string): Chain | null {
    return checkChain(this.#pinned.get(sub) ?? [], sub);
  }

  /// A newer verified chain must be saved before this account can sign or lend on it.
  ready(sub: string): boolean { return !this.#dirty.has(sub) && !this.#seenDirty.has(sub) && !this.#accepting.has(sub); }

  /// Load the pinned chain and public key without waiting for the cloud, including when pairing arrives at startup.
  loaded(sub: string): boolean { return this.#loaded.has(sub); }

  load(sub: string): Effect.Effect<void, CoreError> {
    const env = this.#env;
    return Effect.gen({ self: this }, function* () {
      if (!this.#loaded.has(sub)) {
        const generation = this.#generation(sub);
        const kept = yield* Effect.mapError(env.host.storageGet(keptAs(sub)), asCoreError);
        const said = kept === null ? null : (parseJson(kept) as Entry[] | null);
        if (kept !== null && (!Array.isArray(said) || said.length === 0 || checkChain(said, sub) === null)) {
          return yield* Effect.fail(new CoreError("personal_lock_corrupt", t("core-misc.personal.unreadable")));
        }
        const id = yield* Effect.mapError(env.host.storageGet(KEY_ID), asCoreError);
        if (id !== null && !crypto.validKeyId(fromUtf8(id))) {
          return yield* Effect.fail(new CoreError("personal_key_mismatch", t("core-misc.personal.keyMismatch")));
        }
        const replacement = yield* Effect.mapError(env.host.storageGet(replacedAs(sub)), asCoreError);
        const other = replacement === null ? null : (parseJson(replacement) as Entry[] | null);
        if (replacement !== null && (!Array.isArray(other) || other.length === 0 || checkChain(other, sub) === null)) {
          return yield* Effect.fail(new CoreError("personal_lock_corrupt", t("core-misc.personal.unreadable")));
        }
        const pending = yield* Effect.mapError(env.host.storageGet(firstAs(sub)), asCoreError);
        const first = pending === null ? null : (parseJson(pending) as Entry[] | null);
        if (pending !== null && (!Array.isArray(first) || first.length !== 1 || checkChain(first, sub) === null || id === null || first[0]?.sig?.key !== fromUtf8(id))) {
          return yield* Effect.fail(new CoreError("personal_lock_corrupt", t("core-misc.personal.unreadable")));
        }
        const acceptingRaw = yield* Effect.mapError(env.host.storageGet(acceptingAs(sub)), asCoreError);
        const accepting = acceptingRaw === null ? null : ((parseJson(acceptingRaw) as PendingChoice | null | undefined) ?? null);
        if (acceptingRaw !== null && (accepting === null || accepting.v !== 1 || (accepting.kind !== "join" && accepting.kind !== "restart" && accepting.kind !== "forget") ||
          (accepting.kind !== "forget" && (
          (accepting.observed !== null && (typeof accepting.observed !== "string" || !/^[0-9a-f]{64}$/.test(accepting.observed))) ||
          !isPlace(accepting.base) || !Array.isArray(accepting.target) || accepting.target.length === 0 || id === null ||
          !checkChain(accepting.target, sub)?.devices.has(fromUtf8(id)) ||
          (accepting.kind === "restart" && (accepting.target.length !== 1 || accepting.target[0]?.sig?.key !== fromUtf8(id))))))) {
          return yield* Effect.fail(new CoreError("personal_lock_corrupt", t("core-misc.personal.unreadable")));
        }
        // The key is common to accounts and can still be used when this account's old read became stale.
        yield* this.#keyWriter.withPermits(1)(Effect.sync(() => {
          const key = id === null ? null : fromUtf8(id);
          if (key !== null && crypto.validKeyId(key) && this.#myKey === null) this.#myKey = key;
        }));
        yield* this.#writer(sub).withPermits(1)(Effect.sync(() => {
          if (this.#loaded.has(sub)) return;
          // A forget or a join can finish while the host is reading. Neither may be undone by that earlier read.
          const current = generation === this.#generation(sub);
          if (current && !this.#pinned.has(sub) && Array.isArray(said)) {
            this.#pinned.set(sub, said);
            if (said.length > 0) this.#generations.set(sub, generation + 1);
          }
          if (current && Array.isArray(other)) {
            this.#seen.set(sub, other);
            this.#seenKept.add(sub);
          }
          if (current && Array.isArray(first)) this.#first.set(sub, first[0]!);
          if (current && accepting !== null) {
            this.#accepting.set(sub, accepting);
            this.#acceptSaved.add(sub);
          }
          this.#loaded.add(sub);
          env.changed();
        }));
      }
    });
  }

  /// Read from the device once, then from the cloud: what extends the pinned one is taken, anything else only noted.
  refresh(sub: string): Effect.Effect<void, CoreError> {
    const env = this.#env;
    return Effect.gen({ self: this }, function* () {
      yield* this.load(sub);
      // A previous write can have failed after the cloud accepted the entry. Retry the local save even offline.
      const unsaved = this.#pinned.get(sub);
      if (unsaved && this.#dirty.has(sub)) yield* this.#pin(sub, unsaved, { base: unsaved });
      const replacement = this.#seen.get(sub);
      if (replacement && this.#seenDirty.has(sub)) yield* this.#rememberReplacement(sub, replacement);
      if (this.#accepting.has(sub)) yield* this.#recoverAcceptance(sub);
      const generation = this.#generation(sub);
      const said = (yield* env.cloud(sub, "GET", PATH, null)) as { entries?: Entry[] } | null;
      if (generation !== this.#generation(sub)) return;
      yield* this.#heard(sub, Array.isArray(said?.entries) ? said.entries : []);
    });
  }

  #heard(sub: string, entries: Entry[]): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const pinned = this.#pinned.get(sub) ?? [];
      const generation = this.#generation(sub);
      const holds = checkChain(entries, sub) !== null;
      const first = this.#first.get(sub);
      // Only our exact pending genesis, not a chain that merely includes our key, can be recovered without pairing.
      if (pinned.length === 0 && first && !this.#seenKept.has(sub) && holds && entries.length > 0 && prefixOf([first], entries)) {
        yield* this.#pin(sub, entries, { base: pinned, generation });
        yield* Effect.result(this.#clearFirst(sub, first));
        return;
      }
      const grows = pinned.length > 0 && holds && entries.length >= pinned.length && pinned.every((e, i) => entryHash(e) === entryHash(entries[i]!));
      if (grows) {
        if (!this.#seenKept.has(sub)) this.#seen.delete(sub);
        if (entries.length > pinned.length || this.#dirty.has(sub)) yield* this.#pin(sub, entries, { base: pinned });
      } else if (pinned.length > entries.length && holds && entries.every((e, i) => entryHash(e) === entryHash(pinned[i]!))) {
        // An earlier response, or a temporarily empty cloud, cannot erase or restore over a known replacement.
        if (this.#seenKept.has(sub)) return;
        // The cloud lost all or part of it. Restore in bounded requests, continuing after an interrupted upload.
        let batch: Entry[] = [];
        let start = entries.length;
        const payload = (part: Entry[]) => ({ entries: part, expect: { length: start, head: start === 0 ? null : entryHash(pinned[start - 1]!) } });
        let bytes = toJsonBytes(payload([])).length;
        for (const entry of pinned.slice(entries.length)) {
          const size = toJsonBytes(entry).length;
          if (bytes + (batch.length > 0 ? 1 : 0) + size > POST_BYTES) {
            if (batch.length === 0) return yield* Effect.fail(new CoreError("personal_entry_too_large", "a personal lock entry is too large to restore"));
            yield* this.#restoreBatch(sub, payload(batch), generation);
            if (generation !== this.#generation(sub)) return;
            start += batch.length;
            batch = [];
            bytes = toJsonBytes(payload([])).length;
          }
          if (bytes + size > POST_BYTES) return yield* Effect.fail(new CoreError("personal_entry_too_large", "a personal lock entry is too large to restore"));
          bytes += (batch.length > 0 ? 1 : 0) + size;
          batch.push(entry);
        }
        if (batch.length > 0) yield* this.#restoreBatch(sub, payload(batch), generation);
        if (generation !== this.#generation(sub) || this.#seenKept.has(sub)) return;
        this.#seen.delete(sub);
      } else if (holds && entries.length > 0) yield* this.#rememberReplacement(sub, entries);
      else if (!this.#seenKept.has(sub)) this.#seen.delete(sub);
      this.#env.changed();
    });
  }

  /// Block signing as soon as an unpinned chain is heard; save the observation before allowing another operation.
  #rememberReplacement(sub: string, entries: Entry[]): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const before = this.#seen.get(sub);
      // An older copy of the same replacement cannot erase later signed changes, including a device removal.
      if (before && entries.length < before.length && prefixOf(entries, before)) return;
      const same = before !== undefined && this.#seenKept.has(sub) && before.length === entries.length && prefixOf(before, entries);
      if (same && !this.#seenDirty.has(sub)) return;
      // A pairing or write begun before this observation cannot accept or sign past it.
      if (!same) this.#generations.set(sub, this.#generation(sub) + 1);
      this.#seen.set(sub, entries);
      this.#seenKept.add(sub);
      this.#seenDirty.add(sub);
      this.#env.changed();
      yield* this.#writer(sub).withPermits(1)(Effect.uninterruptible(Effect.gen({ self: this }, function* () {
        if (this.#seen.get(sub) !== entries || !this.#seenKept.has(sub)) return;
        yield* Effect.mapError(this.#env.host.storageSet(replacedAs(sub), utf8(JSON.stringify(entries))), asCoreError);
        if (this.#seen.get(sub) === entries) this.#seenDirty.delete(sub);
        this.#env.changed();
      })));
    });
  }

  /// Record the person's choice before changing the pin. A crash can then distinguish an unfinished confirmation
  /// from an ordinary observation of a different lock, for which the old pin remains valid for existing grants.
  #prepareAcceptance(sub: string, kind: Acceptance["kind"], seen: Entry[] | undefined, target: Entry[], generation: number): Effect.Effect<Acceptance, CoreError> {
    return this.#writer(sub).withPermits(1)(Effect.uninterruptible(Effect.gen({ self: this }, function* () {
      if (generation !== this.#generation(sub) || this.#seen.get(sub) !== seen) {
        return yield* Effect.fail(new CoreError("personal_changed", t("core-misc.personal.changed")));
      }
      if (this.#accepting.get(sub)?.kind === "forget") return yield* Effect.fail(new CoreError("personal_unsaved", t("core-misc.personal.unsaved")));
      if (this.#dirty.has(sub) || this.#seenDirty.has(sub)) return yield* Effect.fail(new CoreError("personal_unsaved", t("core-misc.personal.unsaved")));
      const acceptance: Acceptance = { v: 1, kind, observed: seen ? placeOf(seen).head : null, base: placeOf(seen ?? this.#pinned.get(sub) ?? []), target };
      this.#accepting.set(sub, acceptance);
      this.#acceptSaved.delete(sub);
      this.#env.changed();
      yield* Effect.mapError(this.#env.host.storageSet(acceptingAs(sub), utf8(JSON.stringify(acceptance))), asCoreError);
      this.#acceptSaved.add(sub);
      if (generation !== this.#generation(sub) || this.#seen.get(sub) !== seen) {
        return yield* Effect.fail(new CoreError("personal_changed", t("core-misc.personal.changed")));
      }
      return acceptance;
    })));
  }

  #finishAcceptance(sub: string, acceptance: Acceptance): Effect.Effect<void, CoreError> {
    return this.#writer(sub).withPermits(1)(Effect.uninterruptible(Effect.gen({ self: this }, function* () {
      if (this.#accepting.get(sub) !== acceptance) return yield* Effect.fail(new CoreError("personal_changed", t("core-misc.personal.changed")));
      if (!prefixOf(acceptance.target, this.#pinned.get(sub) ?? []) || this.#dirty.has(sub) || this.#seenDirty.has(sub)) {
        return yield* Effect.fail(new CoreError("personal_unsaved", t("core-misc.personal.unsaved")));
      }
      const seen = this.#seen.get(sub);
      // A newer observation belongs to a different decision and must remain recorded.
      if (seen && placeOf(seen).head === acceptance.observed) {
        yield* Effect.mapError(this.#env.host.storageDelete(replacedAs(sub)), asCoreError);
        if (this.#seen.get(sub) === seen) {
          this.#seen.delete(sub);
          this.#seenKept.delete(sub);
        }
      }
      if (this.#seenDirty.has(sub)) return yield* Effect.fail(new CoreError("personal_unsaved", t("core-misc.personal.unsaved")));
      yield* Effect.mapError(this.#env.host.storageDelete(acceptingAs(sub)), asCoreError);
      this.#accepting.delete(sub);
      this.#acceptSaved.delete(sub);
      this.#env.changed();
    })));
  }

  #abandonAcceptance(sub: string, acceptance: Acceptance): Effect.Effect<void, CoreError> {
    return this.#writer(sub).withPermits(1)(Effect.uninterruptible(Effect.gen({ self: this }, function* () {
      if (this.#accepting.get(sub) !== acceptance || this.#seenDirty.has(sub)) return yield* Effect.fail(new CoreError("personal_changed", t("core-misc.personal.changed")));
      yield* Effect.mapError(this.#env.host.storageDelete(acceptingAs(sub)), asCoreError);
      this.#accepting.delete(sub);
      this.#acceptSaved.delete(sub);
      this.#env.changed();
    })));
  }

  /// Finish an interrupted confirmation. A join carries its verified proof; a restart is retried only if the cloud
  /// still has the same chain the person saw, using its guarded route so another device cannot be overwritten.
  #recoverAcceptance(sub: string): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const acceptance = this.#accepting.get(sub);
      if (!acceptance) return;
      if (!this.#acceptSaved.has(sub)) {
        yield* this.#writer(sub).withPermits(1)(Effect.uninterruptible(Effect.gen({ self: this }, function* () {
          if (this.#accepting.get(sub) !== acceptance) return yield* Effect.fail(new CoreError("personal_changed", t("core-misc.personal.changed")));
          yield* Effect.mapError(this.#env.host.storageSet(acceptingAs(sub), utf8(JSON.stringify(acceptance))), asCoreError);
          this.#acceptSaved.add(sub);
        })));
      }
      if (acceptance.kind === "forget") {
        yield* this.#finishForget(sub, acceptance);
        return;
      }
      const pinned = this.#pinned.get(sub) ?? [];
      if (!prefixOf(acceptance.target, pinned)) {
        const seen = this.#seen.get(sub);
        if ((seen ? placeOf(seen).head : null) !== acceptance.observed) {
          yield* this.#abandonAcceptance(sub, acceptance);
          return yield* Effect.fail(new CoreError("personal_changed", t("core-misc.personal.changed")));
        }
        const generation = this.#generation(sub);
        let target = acceptance.target;
        if (acceptance.kind === "restart") {
          const said = (yield* this.#env.cloud(sub, "GET", PATH, null)) as { entries?: Entry[] } | null;
          if (generation !== this.#generation(sub)) return yield* Effect.fail(new CoreError("personal_changed", t("core-misc.personal.changed")));
          const entries = Array.isArray(said?.entries) ? said.entries : [];
          if (checkChain(entries, sub) === null) return yield* Effect.fail(new CoreError("personal_changed", t("core-misc.personal.changed")));
          if (prefixOf(target, entries)) target = entries;
          else {
            const current = placeOf(entries);
            if (current.length !== acceptance.base.length || current.head !== acceptance.base.head) {
              if (entries.length > 0 && !prefixOf(entries, pinned)) yield* this.#rememberReplacement(sub, entries);
              yield* this.#abandonAcceptance(sub, acceptance);
              return yield* Effect.fail(new CoreError("personal_changed", t("core-misc.personal.changed")));
            }
            yield* this.#env.cloud(sub, "POST", RESTORE_PATH, { entries: target, expect: acceptance.base });
          }
        }
        yield* this.#pin(sub, target, { replace: true, base: pinned, generation, ...(acceptance.kind === "join" ? { memberKey: this.#myKey ?? "" } : {}) });
      }
      yield* this.#finishAcceptance(sub, acceptance);
    });
  }

  /// Save a first genesis before sending it, reusing the same one after a lost response.
  #prepareFirst(sub: string, entry: Entry, generation: number): Effect.Effect<Entry, CoreError> {
    return this.#writer(sub).withPermits(1)(Effect.uninterruptible(Effect.gen({ self: this }, function* () {
      if (generation !== this.#generation(sub) || !this.ready(sub) || this.standing(sub) !== "none") {
        return yield* Effect.fail(new CoreError("personal_changed", t("core-misc.personal.changed")));
      }
      const first = this.#first.get(sub);
      if (first !== undefined) return first;
      yield* Effect.mapError(this.#env.host.storageSet(firstAs(sub), utf8(JSON.stringify([entry]))), asCoreError);
      this.#first.set(sub, entry);
      if (generation !== this.#generation(sub) || !this.ready(sub) || this.standing(sub) !== "none") {
        return yield* Effect.fail(new CoreError("personal_changed", t("core-misc.personal.changed")));
      }
      return entry;
    })));
  }

  #clearFirst(sub: string, first: Entry): Effect.Effect<void, CoreError> {
    return this.#writer(sub).withPermits(1)(Effect.uninterruptible(Effect.gen({ self: this }, function* () {
      if (this.#first.get(sub) !== first) return;
      yield* Effect.mapError(this.#env.host.storageDelete(firstAs(sub)), asCoreError);
      if (this.#first.get(sub) === first) this.#first.delete(sub);
    })));
  }

  #restoreBatch(sub: string, body: { entries: Entry[]; expect: { length: number; head: string | null } }, generation: number): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      for (let attempt = 0; ; attempt++) {
        if (generation !== this.#generation(sub)) return;
        const result = yield* Effect.result(this.#env.cloud(sub, "POST", RESTORE_PATH, body));
        if (generation !== this.#generation(sub)) return;
        if (result._tag === "Success") return;
        if (result.failure.status !== 429 || attempt >= 2) return yield* Effect.fail(result.failure);
        yield* Effect.sleep(RATE_RETRY_MS);
      }
    });
  }

  #generation(sub: string): number { return this.#generations.get(sub) ?? 0; }

  /// A pairing attempt may complete only while the lock it started from has not been forgotten or replaced.
  joinGeneration(sub: string): number { return this.#generation(sub); }

  #writer(sub: string): ReturnType<typeof Semaphore.makeUnsafe> {
    let writer = this.#writing.get(sub);
    if (!writer) this.#writing.set(sub, writer = Semaphore.makeUnsafe(1));
    return writer;
  }

  #pin(sub: string, entries: Entry[], options: { base?: Entry[]; replace?: boolean; generation?: number; memberKey?: string } = {}): Effect.Effect<void, CoreError> {
    return this.#writer(sub).withPermits(1)(Effect.uninterruptible(Effect.gen({ self: this }, function* () {
      const current = this.#pinned.get(sub) ?? [];
      // A concurrent forget or join must not be undone by an earlier cloud response.
      if (options.generation !== undefined && options.generation !== this.#generation(sub)) return yield* Effect.fail(new CoreError("personal_changed", t("core-misc.personal.changed")));
      if (options.base && !prefixOf(options.base, current)) return yield* Effect.fail(new CoreError("personal_changed", t("core-misc.personal.changed")));
      if (options.replace && options.base?.length === 0 && current.length > 0 && !prefixOf(entries, current)) {
        return yield* Effect.fail(new CoreError("personal_changed", t("core-misc.personal.changed")));
      }
      // Even an explicit join or restart must keep a longer copy of that same chain heard in the meantime.
      let next = prefixOf(entries, current) ? current : entries;
      if (!options.replace && current.length > 0) {
        if (next !== current && !prefixOf(current, entries)) return yield* Effect.fail(new CoreError("personal_changed", t("core-misc.personal.changed")));
      }
      // The accepted proof may be an older prefix of a chain that removed this device in the meantime.
      if (options.memberKey && !checkChain(next, sub)?.devices.has(options.memberKey)) return yield* Effect.fail(new CoreError("personal_outside", t("core-misc.personal.outside")));
      if (next === current && !this.#dirty.has(sub)) return;
      if ((current[0] ? entryHash(current[0]) : null) !== (next[0] ? entryHash(next[0]) : null)) {
        this.#generations.set(sub, this.#generation(sub) + 1);
      }
      this.#pinned.set(sub, next);
      this.#loaded.add(sub);
      this.#dirty.add(sub);
      // Stop lending immediately, including while the write is still outstanding.
      this.#env.changed();
      yield* Effect.mapError(this.#env.host.storageSet(keptAs(sub), utf8(JSON.stringify(next))), asCoreError);
      this.#dirty.delete(sub);
      this.#env.changed();
    })));
  }

  standing(sub: string): Standing {
    const pinned = this.chain(sub);
    if (this.#seen.has(sub) && (this.#pinned.get(sub)?.length ?? 0) > 0) return "replaced";
    if (pinned !== null && (this.#pinned.get(sub)?.length ?? 0) > 0) return this.#myKey !== null && pinned.devices.has(this.#myKey) ? "member" : "outside";
    return this.#seen.has(sub) ? "outside" : "none";
  }

  /// This device's key's id, made the first time. Recovering an already sealed key with no saved id asks its person.
  makeKey(): Effect.Effect<string, CoreError> {
    return Effect.map(this.#madeKey(null), (k) => k.id);
  }

  /// This device's key's id; made just now, its seed too: the person was asked once for that, and is not asked again to
  /// read what is in hand.
  #madeKey(reason: string | null): Effect.Effect<{ id: string; seed: Uint8Array | null }, CoreError> {
    const { host } = this.#env;
    return this.#keyWriter.withPermits(1)(Effect.gen({ self: this }, function* () {
      if (this.#myKey !== null) return { id: this.#myKey, seed: null };
      // Another load may not have completed yet. Never overwrite an existing seed merely because its public id has
      // not reached memory; nor create a new one when the host could not read the saved id.
      const stored = yield* Effect.mapError(host.storageGet(KEY_ID), asCoreError);
      if (stored !== null) {
        const id = fromUtf8(stored);
        if (!crypto.validKeyId(id)) {
          return yield* Effect.fail(new CoreError("personal_key_mismatch", t("core-misc.personal.keyMismatch")));
        }
        this.#myKey = id;
        return { id, seed: null };
      }
      if (!host.appKeys || !host.secureSet || !host.secureGet) return yield* Effect.fail(new CoreError("personal_no_key", t("core-misc.personal.noKey")));
      // A process may have stopped after sealing the seed but before saving its public id. Recover that seed rather
      // than replacing an identity that might already be in a lock. The host asks only if the sealed seed exists.
      const recovered = yield* Effect.mapError(host.secureGet(KEY, { user: true, reason: reason ?? t("core-misc.personal.reason.open") }), asCoreError);
      if (recovered !== null && recovered.length !== 32) return yield* Effect.fail(new CoreError("personal_key_mismatch", t("core-misc.personal.keyMismatch")));
      if (reason !== null && recovered === null && host.secureAsk) yield* Effect.mapError(host.secureAsk(reason), asCoreError);
      return yield* Effect.uninterruptible(Effect.gen({ self: this }, function* () {
        let seed = recovered;
        if (seed === null) {
          seed = new Uint8Array(32);
          host.randomBytes(seed);
          yield* Effect.mapError(host.secureSet!(KEY, seed, { user: true }), asCoreError);
        }
        const id = `ed25519:${hex(ed25519.getPublicKey(seed))}`;
        yield* Effect.mapError(host.storageSet(KEY_ID, utf8(id)), asCoreError);
        this.#myKey = id;
        return { id, seed };
      }));
    }));
  }

  /// The key's seed: the person asked, as reading it takes.
  #unseal(reason: string): Effect.Effect<Uint8Array, CoreError> {
    const { host } = this.#env;
    return Effect.gen({ self: this }, function* () {
      if (!host.secureGet) return yield* Effect.fail(new CoreError("personal_no_key", t("core-misc.personal.noKey")));
      const seed = yield* Effect.mapError(host.secureGet(KEY, { user: true, reason }), asCoreError);
      if (seed === null || seed.length !== 32) return yield* Effect.fail(new CoreError("personal_no_key", t("core-misc.personal.noKey")));
      if (this.#myKey === null || `ed25519:${hex(ed25519.getPublicKey(seed))}` !== this.#myKey) {
        return yield* Effect.fail(new CoreError("personal_key_mismatch", t("core-misc.personal.keyMismatch")));
      }
      return seed;
    });
  }

  #entry(sub: string, seed: Uint8Array, key: string, kind: string, body: unknown, before: Entry[]): Entry {
    const last = before[before.length - 1];
    const e = { v: 1 as const, ws: personOf(sub), seq: before.length, prev: last ? entryHash(last) : null, at: Math.floor(this.#env.host.nowMs() / 1000), kind, body };
    return { ...e, sig: { key, alg: "Ed25519", sig: hex(ed25519.sign(signedBytes(entryHash(e)), seed)) } };
  }

  /// One entry more, signed here, told to the cloud and pinned once it took it.
  #append(sub: string, seed: Uint8Array, kind: string, body: unknown, options: { restart?: boolean; generation?: number; onlyEmpty?: boolean } = {}): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      if (kind !== "genesis" && !this.ready(sub)) return yield* Effect.fail(new CoreError("personal_unsaved", t("core-misc.personal.unsaved")));
      if (kind !== "genesis" && this.standing(sub) !== "member") return yield* Effect.fail(new CoreError("personal_outside", t("core-misc.personal.outside")));
      if (options.generation !== undefined && options.generation !== this.#generation(sub)) return yield* Effect.fail(new CoreError("personal_changed", t("core-misc.personal.changed")));
      if (options.onlyEmpty && (!this.ready(sub) || this.standing(sub) !== "none")) return yield* Effect.fail(new CoreError("personal_changed", t("core-misc.personal.changed")));
      const base = this.#pinned.get(sub) ?? [];
      const generation = this.#generation(sub);
      const seen = this.#seen.get(sub);
      const before = options.restart ? [] : base;
      let e = this.#entry(sub, seed, this.#myKey!, kind, body, before);
      if (options.onlyEmpty) {
        e = yield* this.#prepareFirst(sub, e, generation);
        if (generation !== this.#generation(sub) || !this.ready(sub) || this.standing(sub) !== "none") {
          return yield* Effect.fail(new CoreError("personal_changed", t("core-misc.personal.changed")));
        }
      }
      const acceptance = options.restart && !options.onlyEmpty
        ? yield* this.#prepareAcceptance(sub, "restart", seen, [e], generation)
        : null;
      const write = options.onlyEmpty || acceptance
        ? this.#env.cloud(sub, "POST", RESTORE_PATH, { entries: [e], expect: acceptance?.base ?? { length: 0, head: null } })
        : this.#env.cloud(sub, "POST", PATH, { entries: [e] });
      const result = yield* Effect.result(write);
      if (result._tag === "Failure") {
        if (options.onlyEmpty && result.failure.status === 409) {
          // Show the lock that won, if reachable. A failed refresh must not turn this into an unguarded reset.
          yield* Effect.result(this.refresh(sub));
          return yield* Effect.fail(new CoreError("personal_changed", t("core-misc.personal.changed")));
        }
        return yield* Effect.fail(result.failure);
      }
      yield* this.#pin(sub, [...before, e], { base, replace: options.restart === true, generation });
      if (acceptance) yield* this.#finishAcceptance(sub, acceptance);
      const first = this.#first.get(sub);
      if (options.restart && first) yield* Effect.result(this.#clearFirst(sub, first));
      this.#env.changed();
    });
  }

  /// A lock begun here only if none exists; only an explicit restart may replace one already there.
  begin(sub: string, reason: string, replace = false): Effect.Effect<Uint8Array, CoreError> {
    return Effect.gen({ self: this }, function* () {
      yield* this.load(sub);
      const generation = this.#generation(sub);
      if (!replace && (!this.ready(sub) || this.standing(sub) !== "none")) return yield* Effect.fail(new CoreError("personal_changed", t("core-misc.personal.changed")));
      const { id: key, seed: made } = yield* this.#madeKey(reason);
      const id = yield* this.#env.device();
      const seed = made ?? (yield* this.#unseal(reason));
      yield* this.#append(sub, seed, "genesis", { sub, device: { key, id, label: this.#env.label() } }, { restart: true, generation, onlyEmpty: !replace });
      return seed;
    });
  }

  /// Turned on here, where the person has no lock yet (the cloud heard from: not knowing is not none).
  open(sub: string, reason: string): Effect.Effect<null, CoreError> {
    return Effect.gen({ self: this }, function* () {
      yield* this.load(sub);
      // The retry offered for a failed local save does not need the cloud, nor does it begin another lock.
      const unsaved = this.#pinned.get(sub);
      let retried = false;
      if (unsaved && this.#dirty.has(sub)) {
        yield* this.#pin(sub, unsaved, { base: unsaved });
        retried = true;
      }
      const replacement = this.#seen.get(sub);
      if (replacement && this.#seenDirty.has(sub)) {
        yield* this.#rememberReplacement(sub, replacement);
        retried = true;
      }
      if (this.#accepting.has(sub)) {
        yield* this.#recoverAcceptance(sub);
        retried = true;
      }
      if (retried) return null;
      if (!this.ready(sub)) return yield* Effect.fail(new CoreError("personal_unsaved", t("core-misc.personal.unsaved")));
      yield* this.refresh(sub);
      if (this.standing(sub) === "none") yield* this.begin(sub, reason);
      return null;
    });
  }

  /// A chat's grant signed: the lock begun first where there is none, refused on a device outside it.
  signGrant(sub: string, body: Omit<GrantBody, "v" | "sub">, reason: string): Effect.Effect<SignedGrant, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const read = yield* Effect.result(this.refresh(sub));
      const standing = this.standing(sub);
      if (!this.ready(sub)) return yield* Effect.fail(new CoreError("personal_unsaved", t("core-misc.personal.unsaved")));
      // Not heard from the cloud, no lock known here is not no lock: one begun now would take its place.
      if (read._tag === "Failure" && standing === "none") return yield* Effect.fail(read.failure);
      if (standing === "outside") return yield* Effect.fail(new CoreError("personal_outside", t("core-misc.personal.outside")));
      if (standing === "replaced") return yield* Effect.fail(new CoreError("personal_replaced", t("core-misc.personal.replaced")));
      const seed = standing === "none" ? yield* this.begin(sub, reason) : yield* this.#unseal(reason);
      if (!this.ready(sub)) return yield* Effect.fail(new CoreError("personal_unsaved", t("core-misc.personal.unsaved")));
      if (this.standing(sub) !== "member") return yield* Effect.fail(new CoreError("personal_outside", t("core-misc.personal.outside")));
      const whole: GrantBody = { v: 1, sub, ...body };
      return { body: whole, sig: { key: this.#myKey!, sig: hex(ed25519.sign(grantBytes(whole), seed)) } };
    });
  }

  /// Grants signed at one go, the person asked once; refused on a device not on the lock.
  signGrants(sub: string, bodies: Omit<GrantBody, "v" | "sub">[], reason: string): Effect.Effect<SignedGrant[], CoreError> {
    return Effect.gen({ self: this }, function* () {
      if (!this.ready(sub)) return yield* Effect.fail(new CoreError("personal_unsaved", t("core-misc.personal.unsaved")));
      if (this.standing(sub) !== "member") return yield* Effect.fail(new CoreError("personal_outside", t("core-misc.personal.outside")));
      const valid = (now: number) => bodies.every((b) => (b.scope === "hour" || b.scope === "chat") && Number.isSafeInteger(b.exp) && b.exp > now);
      if (!valid(Math.floor(this.#env.host.nowMs() / 1000))) return yield* Effect.fail(CoreError.invalid(t("core-misc.personal.noRequest")));
      const seed = yield* this.#unseal(reason);
      if (!this.ready(sub)) return yield* Effect.fail(new CoreError("personal_unsaved", t("core-misc.personal.unsaved")));
      if (this.standing(sub) !== "member") return yield* Effect.fail(new CoreError("personal_outside", t("core-misc.personal.outside")));
      const now = Math.floor(this.#env.host.nowMs() / 1000);
      if (!valid(now)) return yield* Effect.fail(CoreError.invalid(t("core-misc.personal.noRequest")));
      return bodies.map((body) => {
        const exp = Math.min(body.exp, now + (body.scope === "hour" ? 3600 : 30 * 86400));
        const whole: GrantBody = { v: 1, sub, ...body, exp };
        return { body: whole, sig: { key: this.#myKey!, sig: hex(ed25519.sign(grantBytes(whole), seed)) } };
      });
    });
  }

  /// The key's seed, the person asked, ahead of a code shown here: letting the new device in then asks nothing more.
  unseal(reason: string): Effect.Effect<Uint8Array, CoreError> {
    return this.#unseal(reason);
  }

  /// A new device let in here, face to face, signed with `seed` (else the person is asked now): the whole lock then, for
  /// it to pin.
  addDevice(sub: string, device: Device, reason: string, seed: Uint8Array | null = null): Effect.Effect<Entry[], CoreError> {
    return Effect.gen({ self: this }, function* () {
      if (!this.ready(sub)) return yield* Effect.fail(new CoreError("personal_unsaved", t("core-misc.personal.unsaved")));
      if (this.standing(sub) !== "member") return yield* Effect.fail(new CoreError("personal_outside", t("core-misc.personal.outside")));
      yield* this.#append(sub, seed ?? (yield* this.#unseal(reason)), "device", device);
      return this.#pinned.get(sub) ?? [];
    });
  }

  removeDevice(sub: string, key: string, reason: string): Effect.Effect<null, CoreError> {
    return Effect.gen({ self: this }, function* () {
      if (!this.ready(sub)) return yield* Effect.fail(new CoreError("personal_unsaved", t("core-misc.personal.unsaved")));
      if (this.standing(sub) !== "member") return yield* Effect.fail(new CoreError("personal_outside", t("core-misc.personal.outside")));
      yield* this.#append(sub, yield* this.#unseal(reason), "device.remove", { key });
      return null;
    });
  }

  /// The lock a device that let this one in brought (the connection proved by the code shown there): pinned.
  joined(sub: string, entries: Entry[], generation: number): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const seen = this.#seen.get(sub);
      if (checkChain(entries, sub) === null) return yield* Effect.fail(new CoreError("personal_outside", t("core-misc.personal.outside")));
      if (seen && !prefixOf(seen, entries) && !prefixOf(entries, seen)) {
        return yield* Effect.fail(new CoreError("personal_changed", t("core-misc.personal.changed")));
      }
      // The proof can be an earlier prefix of a replacement already heard from the cloud.
      const target = seen && prefixOf(entries, seen) ? seen : entries;
      const chain = checkChain(target, sub);
      const key = this.#myKey;
      if (chain === null || key === null || !chain.devices.has(key)) return yield* Effect.fail(new CoreError("personal_outside", t("core-misc.personal.outside")));
      const acceptance = yield* this.#prepareAcceptance(sub, "join", seen, target, generation);
      yield* this.#pin(sub, target, { replace: true, generation, memberKey: key });
      yield* this.#finishAcceptance(sub, acceptance);
      const first = this.#first.get(sub);
      if (first) yield* Effect.result(this.#clearFirst(sub, first));
      this.#env.changed();
    });
  }

  #finishForget(sub: string, forgetting: Forgetting): Effect.Effect<void, CoreError> {
    return this.#writer(sub).withPermits(1)(Effect.uninterruptible(Effect.gen({ self: this }, function* () {
      if (this.#accepting.get(sub) !== forgetting) return yield* Effect.fail(new CoreError("personal_changed", t("core-misc.personal.changed")));
      // Keep the intent until every part is gone, so an interrupted forget cannot resume an earlier confirmation.
      yield* Effect.mapError(this.#env.host.storageDelete(firstAs(sub)), asCoreError);
      this.#first.delete(sub);
      yield* Effect.mapError(this.#env.host.storageDelete(keptAs(sub)), asCoreError);
      this.#pinned.delete(sub);
      this.#dirty.delete(sub);
      if (this.#myKey !== null) this.#loaded.add(sub);
      const seen = this.#seen.get(sub);
      yield* Effect.mapError(this.#env.host.storageDelete(replacedAs(sub)), asCoreError);
      if (this.#seen.get(sub) !== seen) return yield* Effect.fail(new CoreError("personal_unsaved", t("core-misc.personal.unsaved")));
      this.#seen.delete(sub);
      this.#seenKept.delete(sub);
      this.#seenDirty.delete(sub);
      yield* Effect.mapError(this.#env.host.storageDelete(acceptingAs(sub)), asCoreError);
      this.#accepting.delete(sub);
      this.#acceptSaved.delete(sub);
      this.#env.changed();
    })));
  }

  /// A lock the person says they began anew elsewhere: this device leaves the one pinned, and joins it or begins again.
  forget(sub: string, reason: string): Effect.Effect<null, CoreError> {
    return Effect.gen({ self: this }, function* () {
      if (this.#env.host.secureAsk) yield* Effect.mapError(this.#env.host.secureAsk(reason), asCoreError);
      const forgetting: Forgetting = { v: 1, kind: "forget" };
      yield* this.#writer(sub).withPermits(1)(Effect.uninterruptible(Effect.gen({ self: this }, function* () {
        this.#generations.set(sub, this.#generation(sub) + 1);
        this.#accepting.set(sub, forgetting);
        this.#acceptSaved.delete(sub);
        this.#env.changed();
        yield* Effect.mapError(this.#env.host.storageSet(acceptingAs(sub), utf8(JSON.stringify(forgetting))), asCoreError);
        this.#acceptSaved.add(sub);
      })));
      yield* this.#finishForget(sub, forgetting);
      return null;
    });
  }

  /// All this person's devices lost but this one or a new one: a new lock, in the place of the one the cloud has. The
  /// devices that pinned that one do not follow it by themselves (`replaced`).
  restart(sub: string, reason: string): Effect.Effect<null, CoreError> {
    return Effect.map(this.begin(sub, reason, true), () => null);
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

  /// What `adbShare` says of it.
  view(sub: string): J {
    const pinned = this.chain(sub);
    return {
      standing: this.standing(sub),
      sub,
      pending: !this.ready(sub),
      devices: [...(pinned?.devices.values() ?? [])].map((d) => ({ key: d.key, label: d.label, me: d.key === this.#myKey })),
    };
  }
}
