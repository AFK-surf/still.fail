// A person's own lock (docs/personal-lock.md): a chain, kept by the cloud and carried to their devices, of the keys that
// person's app devices sign with. Only a device on it adds or removes one; a new device joins face to face
// (views/pair.ts). What they sign with it means more than a login does: their phone lends itself to a chat only on a
// grant signed so, which it checks itself against the lock it pinned, whatever a station or the cloud says.
//
// The key is sealed so that each use asks the person (`user: true`: biometrics or the screen lock). Web pages have none:
// their code is the cloud's.
import { ed25519 } from "@noble/curves/ed25519.js";
import { Effect } from "effect";
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
  const out = rules.person_fold_js(entries, sub, crypto) as J;
  return "error" in out ? null : { devices: new Map((out.devices as Device[]).map((d) => [d.key, d])), hash: out.head };
}

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
/// The cloud reads at most this many UTF-8 bytes in one request (cloud/src/auth.ts).
const POST_BYTES = 8192;

export class PersonalLock {
  readonly #env: PersonalEnv;
  /// The chain pinned here, each person's; what the cloud has where this is not it.
  readonly #pinned = new Map<string, Entry[]>();
  readonly #seen = new Map<string, Entry[]>();
  readonly #loaded = new Set<string>();
  #myKey: string | null = null;

  constructor(env: PersonalEnv) {
    this.#env = env;
  }

  /// The chain pinned here as read so far, what it says.
  chain(sub: string): Chain | null {
    return checkChain(this.#pinned.get(sub) ?? [], sub);
  }

  /// Read from the device once, then from the cloud: what extends the pinned one is taken, anything else only noted.
  refresh(sub: string): Effect.Effect<void, CoreError> {
    const env = this.#env;
    return Effect.gen({ self: this }, function* () {
      if (!this.#loaded.has(sub)) {
        const kept = yield* Effect.orElseSucceed(env.host.storageGet(keptAs(sub)), () => null);
        const said = kept === null ? null : (parseJson(kept) as Entry[] | null);
        if (Array.isArray(said) && checkChain(said, sub) !== null) this.#pinned.set(sub, said);
        const id = yield* Effect.orElseSucceed(env.host.storageGet(KEY_ID), () => null);
        if (id !== null) this.#myKey = fromUtf8(id);
        this.#loaded.add(sub);
        env.changed();
      }
      const said = (yield* env.cloud(sub, "GET", PATH, null)) as { entries?: Entry[] } | null;
      yield* this.#heard(sub, Array.isArray(said?.entries) ? said.entries : []);
    });
  }

  #heard(sub: string, entries: Entry[]): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const pinned = this.#pinned.get(sub) ?? [];
      const holds = checkChain(entries, sub) !== null;
      const grows = pinned.length > 0 && holds && entries.length >= pinned.length && pinned.every((e, i) => entryHash(e) === entryHash(entries[i]!));
      if (grows) {
        this.#seen.delete(sub);
        if (entries.length > pinned.length) yield* this.#pin(sub, entries);
      } else if (pinned.length > entries.length && holds && entries.every((e, i) => entryHash(e) === entryHash(pinned[i]!))) {
        // The cloud lost all or part of it. Restore in bounded requests, continuing after an interrupted upload.
        let batch: Entry[] = [];
        let start = entries.length;
        const payload = (part: Entry[]) => ({ entries: part, expect: { length: start, head: start === 0 ? null : entryHash(pinned[start - 1]!) } });
        for (const entry of pinned.slice(entries.length)) {
          const together = [...batch, entry];
          if (toJsonBytes(payload(together)).length > POST_BYTES) {
            if (batch.length === 0) return yield* Effect.fail(new CoreError("personal_entry_too_large", "a personal lock entry is too large to restore"));
            yield* this.#env.cloud(sub, "POST", RESTORE_PATH, payload(batch));
            start += batch.length;
            batch = [entry];
            if (toJsonBytes(payload(batch)).length > POST_BYTES) return yield* Effect.fail(new CoreError("personal_entry_too_large", "a personal lock entry is too large to restore"));
          } else batch = together;
        }
        if (batch.length > 0) yield* this.#env.cloud(sub, "POST", RESTORE_PATH, payload(batch));
        this.#seen.delete(sub);
      } else if (holds && entries.length > 0) this.#seen.set(sub, entries);
      else this.#seen.delete(sub);
      this.#env.changed();
    });
  }

  #pin(sub: string, entries: Entry[]): Effect.Effect<void, CoreError> {
    this.#pinned.set(sub, entries);
    return Effect.mapError(this.#env.host.storageSet(keptAs(sub), utf8(JSON.stringify(entries))), asCoreError);
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

  /// One entry more, signed here, told to the cloud and pinned once it took it.
  #append(sub: string, seed: Uint8Array, kind: string, body: unknown): Effect.Effect<void, CoreError> {
    return Effect.gen({ self: this }, function* () {
      const e = this.#entry(sub, seed, this.#myKey!, kind, body);
      yield* this.#env.cloud(sub, "POST", PATH, { entries: [e] });
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
      this.#pinned.delete(sub);
      yield* this.#append(sub, seed, "genesis", { sub, device: { key, id, label: this.#env.label() } });
      return seed;
    });
  }

  /// Turned on here, where the person has no lock yet (the cloud heard from: not knowing is not none).
  open(sub: string, reason: string): Effect.Effect<null, CoreError> {
    return Effect.gen({ self: this }, function* () {
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
      // Not heard from the cloud, no lock known here is not no lock: one begun now would take its place.
      if (read._tag === "Failure" && standing === "none") return yield* Effect.fail(read.failure);
      if (standing === "outside") return yield* Effect.fail(new CoreError("personal_outside", t("core-misc.personal.outside")));
      if (standing === "replaced") return yield* Effect.fail(new CoreError("personal_replaced", t("core-misc.personal.replaced")));
      const seed = standing === "none" ? yield* this.begin(sub, reason) : yield* this.#unseal(reason);
      const whole: GrantBody = { v: 1, sub, ...body };
      return { body: whole, sig: { key: this.#myKey!, sig: hex(ed25519.sign(grantBytes(whole), seed)) } };
    });
  }

  /// Grants signed at one go, the person asked once; refused on a device not on the lock.
  signGrants(sub: string, bodies: Omit<GrantBody, "v" | "sub">[], reason: string): Effect.Effect<SignedGrant[], CoreError> {
    return Effect.gen({ self: this }, function* () {
      if (this.standing(sub) !== "member") return yield* Effect.fail(new CoreError("personal_outside", t("core-misc.personal.outside")));
      const seed = yield* this.#unseal(reason);
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
  /// it to pin.
  addDevice(sub: string, device: Device, reason: string, seed: Uint8Array | null = null): Effect.Effect<Entry[], CoreError> {
    return Effect.gen({ self: this }, function* () {
      if (this.standing(sub) !== "member") return yield* Effect.fail(new CoreError("personal_outside", t("core-misc.personal.outside")));
      yield* this.#append(sub, seed ?? (yield* this.#unseal(reason)), "device", device);
      return this.#pinned.get(sub) ?? [];
    });
  }

  removeDevice(sub: string, key: string, reason: string): Effect.Effect<null, CoreError> {
    return Effect.gen({ self: this }, function* () {
      if (this.standing(sub) !== "member") return yield* Effect.fail(new CoreError("personal_outside", t("core-misc.personal.outside")));
      yield* this.#append(sub, yield* this.#unseal(reason), "device.remove", { key });
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
