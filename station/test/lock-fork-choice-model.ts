// A model of the workspace lock kept by many keepers that choose between branches by the fork-choice rule of Tailscale's
// Tailnet Lock (tailscale/tka, `computeActiveAncestor`/`pickNextAUM`; its white paper), run on the lock's real entries
// and the product's real rules (`genesis`, `apply`, `entryHash`, the signature checks of src/cloud/lock.ts). Only which
// entries a keeper stores and which chain it goes by is modelled; nothing here is the product's code. Run by
// lock-fork-choice.test.ts, which prints what it measured; it decides nothing about the rule.
//
// The rule as modelled: every keeper (a station, a device) checks each entry itself and stores every one whose parent
// it has and that `apply` takes in the parent's state, also those off its active chain. Its active chain goes from the
// genesis hop by hop: among the children of the head, the one with the highest weight (its signer's votes in the
// parent's state; our entries carry one signature), then, equal, the one that is a removal, then the lowest hash.
// Length is never compared. A keeper goes by its active chain again whenever it stores something. Two keepers sync by
// giving each other the entries of their active chain (or, in the `all` variant, every one they store) that the other
// lacks. Whether an entry follows its parent is the rules' alone, so it is worked out once for the world and kept by
// the entry's hash and signature (`Rules`): every keeper would work it out the same.
//
// The faults are those of rules/protocol/lock.spthy: what is between keepers (the cloud, other stations) drops, delays,
// reorders and replays messages and never makes a valid signature; a device whose trust was revoked has its key in other
// hands, which sign entries valid after any parent they know (one from before the revocation) and bring them to whichever
// keepers they reach.
//
// The product does not do this yet (2026-11-12): its stations keep the first entry they take at a place and nothing
// brings two that took different ones back to one chain (lock-world-sim.ts, its known table). This model is what the
// sync replacing that is built against. Tailscale's is the rule above (weight, then removal, then hash; the variants
// `votes`, `removal`, `offers`, `hashfield` are readings of it). Ours: `tie=signer` (the third step compares the
// parent's hash and the signer's key, which the signer cannot vary) and `resign` (a device signs its entry again after
// the head when it lost its place). Two more were measured in the second round and not adopted: `recovery` (a recovery
// key's checkpoint, the lead's reading of Tailscale's retroactive revocation) made 3 to 9 honest entries of other devices
// inactive at each use, up to 24 with resign, and still failed case c in every world with resign; `retain` (compaction)
// left a keeper away for longer than it retains on a chain of its own (one chain in 57.5% of worlds with retain=16, 100%
// without).
import { createHash } from "node:crypto";
import { isMainThread, parentPort, workerData } from "node:worker_threads";
import { type Entry, type LockState, apply, canonical, entryHash, genesis, signedBytes, signer } from "../src/cloud/lock.ts";
import { type Key, Rng, START, WS, after, eve, eveKey, genesisOf, key, mal, said, signers, spare, stationKeys } from "./lock-world-sim.ts";

export type Variant = {
  /// What a signature weighs: `flat` 1 for every device; `roles` an owner's 3, an admin's 2, a member's (and a viewer's) 1.
  votes: "flat" | "roles";
  /// What is a removal for the rule's second step: `device` a `device.remove` of a device that signs; `any` also
  /// `member.remove`, `station.remove`, `disable`.
  removal: "device" | "any";
  /// What a keeper gives in a sync: its active chain, or everything it stores.
  offers: "active" | "all";
  /// Whether a device whose entry is no longer on its active chain signs the same kind and body again after its head.
  resign: "off" | "on";
  /// `varied`: a revoked key's entry is made with GRIND values of `at`, the lowest hash taken.
  hashfield: "as-is" | "varied";
  // What follows is NOT part of Tailscale's fork-choice rule as modelled above (the second round, 2026-11-12): `tie` is
  // ours; `recovery` and `retain` are the lead's reading of Tailscale's retroactive revocation and of its compaction.
  // Left out, each is as the rule has it.
  /// What rule 3 compares: the entry's hash (`hash`), or sha256 of the parent's hash and the signing key's id
  /// (`signer`): one value a signer and parent, nothing in the entry its signer can vary.
  tie?: "hash" | "signer";
  /// A recovery key on no device, named in the genesis, whose entry outweighs every device together; it signs a
  /// checkpoint (see `World.recover`).
  recovery?: "off" | "on";
  /// A keeper stores no entry (but a checkpoint) whose parent is more than this many entries behind its active head.
  retain?: number;
};

export const VARIANTS: Variant[] = (["flat", "roles"] as const).flatMap((votes) =>
  (["device", "any"] as const).flatMap((removal) =>
    (["active", "all"] as const).flatMap((offers) =>
      (["off", "on"] as const).flatMap((resign) => (["as-is", "varied"] as const).map((hashfield) => ({ votes, removal, offers, resign, hashfield }))))));

export const variantName = (v: Variant) =>
  `${v.votes} ${v.removal} ${v.offers} resign=${v.resign} ${v.hashfield}${v.tie === "signer" ? " tie=signer" : ""}${v.recovery === "on" ? " recovery" : ""}${v.retain !== undefined ? ` retain=${v.retain}` : ""}`;

/// How many values of `at` a revoked key tries in `varied`.
export const GRIND = 16;

const VOTES: Record<string, number> = { owner: 3, admin: 2, member: 1, viewer: 1 };
const REMOVALS = new Set(["device.remove", "member.remove", "station.remove", "disable"]);

// ── the rules, worked out once a world ──────────────────────────────────────────────────────────────────────────────

const hashes = new WeakMap<Entry, string>();
export const hashOf = (e: Entry): string => {
  let h = hashes.get(e);
  if (h === undefined) {
    h = entryHash(e);
    hashes.set(e, h);
  }
  return h;
};

/// An entry signed by `by` (lock-world-sim.ts `signed`). The same entry is signed in every variant of a seed: its
/// signature is kept by key and hash (Ed25519 signs the same bytes the same), and the entry is born with its hash known.
const sigs = new Map<string, string>();
export function signed(e: Omit<Entry, "sig">, by: Key): Entry {
  const h = entryHash(e as Entry);
  const id = `${by.id}|${h}`;
  let sig = sigs.get(id);
  if (sig === undefined) {
    if (sigs.size > 400_000) sigs.clear();
    sig = by.sign(signedBytes(h));
    sigs.set(id, sig);
  }
  const out: Entry = { ...e, sig: { key: by.id, alg: "Ed25519", sig } };
  hashes.set(out, h);
  return out;
}

/// The genesis every keeper pins (the home workspace's of lock-world-sim.ts, its three stations).
export const G = genesisOf(WS, [0, 1, 2]);
export const GH = hashOf(G);

/// The recovery key (`recovery=on`; not Tailscale's rule as modelled, see Variant): on no device. Our entries have no
/// kind that names such a key, so the model names it as a device of the owner's that no device holds (`RKDEV`), in a
/// genesis of its own (GR: G with it); the product would need the genesis to name a recovery key, and a kind of entry
/// it alone signs. A checkpoint it signs is a genesis-shaped entry (the whole state, signed as the rules check a
/// genesis: by a signing key of the owner's that it names) hung below a parent beside the entry (`Rules.ckParent`):
/// the rules take what follows it as they take what follows a genesis.
export const RK = key(990);
const RKDEV = { id: key(991).hex, sub: "alice", kind: "app" as const, label: "recovery key", sign_key: RK.id };
const GR = (() => {
  const { sig: _, ...g } = G;
  const body = G.body as { devices: unknown[] };
  return signed({ ...g, body: { ...body, devices: [...body.devices, RKDEV] } }, signers[0].signer);
})();
/// What a recovery key's entry weighs: more than every device together.
const RECOVERY_VOTES = 1000;

/// What the rules said of an entry (by its hash and signature), whatever world it came up in: the state after it, or
/// null where it does not follow its parent. An entry names its parent by hash, so the answer is the same in every
/// world; the variants of a seed make the same entries, and it is worked out once for all of them. Bounded: cleared
/// when full.
const ruled = new Map<string, LockState | null>();

/// What a keeper needs of a log's rules: its genesis, what follows what, and what the fork-choice rule weighs (the
/// workspace lock's `Rules` here; a person's own lock in lock-roster-model.ts).
export interface LogRules<S> {
  readonly g: Entry;
  readonly gh: string;
  parentOf(e: Entry): string | null;
  isCheckpoint(e: Entry): boolean;
  depth(h: string): number;
  valid(e: Entry): boolean;
  state(h: string): S;
  /// The rule's first step (the signer's votes in the parent's state) and its second (whether it is a removal).
  weight(ps: S, e: Entry): number;
  removal(ps: S, e: Entry): boolean;
}

/// What follows what, by the product's rules: each entry's state after it, by its hash, and whether an entry (by its
/// hash and signature) follows its parent.
class Rules implements LogRules<LockState> {
  readonly v: Variant;
  /// The genesis every keeper pins, and its hash.
  readonly g: Entry;
  readonly gh: string;
  states: Map<string, LockState>;
  verdicts = new Map<string, boolean>();
  /// A checkpoint's parent, by its hash (it names none itself).
  ckParent = new Map<string, string>();
  /// How many entries each is below the genesis, by its hash (its `seq`, but below a checkpoint).
  depths: Map<string, number>;
  constructor(v: Variant) {
    this.v = v;
    this.g = v.recovery === "on" ? GR : G;
    this.gh = hashOf(this.g);
    this.states = new Map([[this.gh, genesis(this.g)]]);
    this.depths = new Map([[this.gh, 0]]);
  }
  /// The entry an entry hangs below: its `prev`, a checkpoint's parent.
  parentOf(e: Entry): string | null {
    return e.prev ?? this.ckParent.get(hashOf(e)) ?? null;
  }
  isCheckpoint(e: Entry): boolean {
    return e.prev === null && this.ckParent.has(hashOf(e));
  }
  depth(h: string): number {
    return this.depths.get(h)!;
  }
  valid(e: Entry): boolean {
    const h = hashOf(e);
    const id = `${h}|${e.sig.sig}`;
    const known = this.verdicts.get(id);
    if (known !== undefined) return known;
    const parent = this.parentOf(e);
    const ps = parent === null ? undefined : this.states.get(parent);
    // (a second genesis, or one whose parent nobody took: no keeper that stores it is possible)
    if (ps === undefined || parent === null) return false;
    // A checkpoint: only with a recovery key, signed by it, checked as the rules check a genesis.
    const checkpoint = e.prev === null;
    if (checkpoint && (this.v.recovery !== "on" || e.sig.key !== RK.id)) return false;
    let s = ruled.get(id);
    if (s === undefined) {
      try {
        s = checkpoint ? genesis(e) : apply(ps, e, null);
      } catch {
        s = null;
      }
      if (ruled.size > 100_000) ruled.clear();
      ruled.set(id, s);
    }
    if (s !== null && !this.states.has(h)) this.states.set(h, s);
    if (s !== null && !this.depths.has(h)) this.depths.set(h, this.depth(parent) + 1);
    this.verdicts.set(id, s !== null);
    return s !== null;
  }
  state(h: string): LockState {
    return this.states.get(h)!;
  }
  weight(ps: LockState, e: Entry): number {
    return weight(ps, e, this.v);
  }
  removal(ps: LockState, e: Entry): boolean {
    return isRemoval(ps, e, this.v);
  }
}

// ── a keeper ────────────────────────────────────────────────────────────────────────────────────────────────────────

export class Keeper<S = LockState> {
  store: Map<string, Entry>;
  kids = new Map<string, string[]>();
  active: string[];
  on: Set<string>;
  /// Moves on whenever what it stores or goes by changes (a sync between two keepers neither of which moved on since
  /// the last gives nothing).
  ver = 0;
  /// The earliest place on its active chain at which an entry stored since it last chose hangs (Infinity: none): the
  /// chain before it cannot change, as the rule goes hop by hop from the genesis.
  from = Infinity;
  readonly name: string;
  readonly v: Variant;
  readonly rules: LogRules<S>;
  constructor(name: string, v: Variant, rules: LogRules<S>) {
    this.name = name;
    this.v = v;
    this.rules = rules;
    this.store = new Map([[rules.gh, rules.g]]);
    this.active = [rules.gh];
    this.on = new Set([rules.gh]);
  }

  /// `retain`: whether it stores an entry below `parent` (a checkpoint at any depth).
  retains(e: Entry, parent: string): boolean {
    if (this.v.retain === undefined || this.rules.isCheckpoint(e)) return true;
    return this.rules.depth(parent) >= this.active.length - 1 - this.v.retain;
  }

  head(): string {
    return this.active[this.active.length - 1];
  }
  headState(): S {
    return this.rules.state(this.head());
  }

  /// Stores each entry whose parent it has (or gets in the same batch) and that follows it; whether any was new.
  take(es: Entry[]): boolean {
    let left = es.filter((e) => !this.store.has(hashOf(e)));
    let changed = false;
    for (let progress = true; progress && left.length > 0; ) {
      progress = false;
      const rest: Entry[] = [];
      for (const e of left) {
        const h = hashOf(e);
        if (this.store.has(h)) continue;
        const parent = this.rules.parentOf(e);
        if (parent !== null && this.store.has(parent) && this.rules.valid(e) && this.retains(e, parent)) {
          this.store.set(h, e);
          if (this.on.has(parent)) this.from = Math.min(this.from, this.active.indexOf(parent));
          const k = this.kids.get(parent) ?? [];
          k.push(h);
          this.kids.set(parent, k);
          progress = changed = true;
        } else rest.push(e);
      }
      left = rest;
    }
    if (changed) this.ver++;
    return changed;
  }

  /// Whether `a` is chosen over `b`, both children of `parent`, whose state is `ps`.
  over(ps: S, parent: string, a: Entry, b: Entry): boolean {
    const wa = this.rules.weight(ps, a), wb = this.rules.weight(ps, b);
    if (wa !== wb) return wa > wb;
    const ra = this.rules.removal(ps, a), rb = this.rules.removal(ps, b);
    if (ra !== rb) return ra;
    if (this.v.tie === "signer" && a.sig.key !== b.sig.key) return tieOf(parent, a) < tieOf(parent, b);
    // (`tie=signer` between two entries of one signer after one parent: their hashes, as nothing else tells them apart)
    return hashOf(a) < hashOf(b);
  }

  /// The active chain, from the genesis, hop by hop (the part before the earliest entry stored since it last chose, as
  /// it was).
  choose(): string[] {
    const at = this.from;
    this.from = Infinity;
    if (at === Infinity) return this.active;
    const out = this.active.slice(0, at + 1);
    for (let h = out[out.length - 1]; ; ) {
      const ks = this.kids.get(h);
      if (ks === undefined || ks.length === 0) break;
      const ps = this.rules.state(h);
      let best = ks[0];
      for (const k of ks.slice(1)) if (this.over(ps, h, this.store.get(k)!, this.store.get(best)!)) best = k;
      out.push(best);
      h = best;
    }
    return out;
  }

  /// What it gives in a sync, parents first.
  offered(): Entry[] {
    if (this.v.offers === "active") return this.active.map((h) => this.store.get(h)!);
    return [...this.store.values()].sort((x, y) => this.rules.depth(hashOf(x)) - this.rules.depth(hashOf(y)));
  }
}

/// `tie=signer`: sha256 of the parent's hash and the signing key's id.
export function tieOf(parent: string, e: Entry): string {
  return createHash("sha256").update(`${parent}\0${e.sig.key}`).digest("hex");
}

export function weight(ps: LockState, e: Entry, v: Variant): number {
  if (v.recovery === "on" && e.sig.key === RK.id) return RECOVERY_VOTES;
  if (v.votes === "flat") return 1;
  const who = signer(ps, e.sig, null);
  return who === null ? 0 : VOTES[who.role] ?? 0;
}

export function isRemoval(ps: LockState, e: Entry, v: Variant): boolean {
  if (v.removal === "any") return REMOVALS.has(e.kind);
  return e.kind === "device.remove" && ps.devices.get((e.body as { id?: string })?.id ?? "")?.sign_key !== undefined;
}

// ── the world ───────────────────────────────────────────────────────────────────────────────────────────────────────

/// A device that keeps the lock and signs: the three apps, then the six spares.
export type Dev = { i: number; name: string; sub: string; base: Key; signer: Key; k: Keeper; compromised: boolean; mine: string[]; superseded: Set<string> };

type Msg = { to: Keeper; entries: Entry[] };

/// `free`: no message lost, nothing forged, no revoked key used (messages still delayed and reordered); `faults`: all
/// of the fault model.
export type Family = "free" | "faults";

/// One step of a drawn world: its kind and three numbers it picks with.
export type Step = { k: number; a: number; b: number; c: number };
const KINDS = ["deliver", "deliver", "deliver", "deliver", "deliver", "deliver", "sign", "sign", "sign", "sync", "sync", "sync", "drop", "replay", "forge", "stale"] as const;
export const drawSteps = (seed: number, n: number): Step[] => {
  const r = new Rng(seed);
  return Array.from({ length: n }, () => ({ k: r.int(KINDS.length), a: r.int(1 << 16), b: r.int(1 << 16), c: r.int(1 << 16) }));
};

/// The people's devices a station may let in, by base key: the apps and the spares.
const WATCH = [
  ...signers.map((s) => ({ hex: s.app.hex, name: `${s.sub}'s app` })),
  ...spare.map((d) => ({ hex: d.base.hex, name: d.name })),
];
const watchName = new Map([...WATCH, ...mal.map((m) => ({ hex: m.base.hex, name: m.name }))].map((w) => [w.hex, w.name]));

export class World {
  rules: Rules;
  rng: Rng;
  t = START / 1000;
  step = 0;
  stations: Keeper[];
  devs: Dev[];
  keepers: Keeper[];
  devOf = new Map<Keeper, Dev>();
  queue: Msg[] = [];
  sent: Msg[] = [];
  /// For each pair, the versions at which the first last gave the second all it offers (`level`).
  levelled = new Map<string, string>();
  /// Every entry made in the world, by its hash.
  all: Map<string, Entry>;
  /// What has gone over a line (the relays have it): what a revoked key may sign after, beside its own device's store.
  known: Map<string, Entry>;
  /// Entries honest devices signed: who, what for (`intent`: the signer, kind and body), at which step.
  honest = new Map<string, { dev: Dev; intent: string; step: number; probe: boolean }>();
  intents = new Map<string, { dev: Dev; hashes: string[]; void: boolean; probe: boolean }>();
  /// Devices an honest entry took out (or whose person it took out): at which step, by whose device.
  removed = new Map<string, { step: number; by: string }>();
  /// Spares never put in again once taken out (a world's draws).
  everRemoved = new Set<string>();
  /// What a revoked key signed: by which device.
  attack = new Map<string, Dev>();
  forged = new Set<string>();
  /// Where each entry was ever active.
  activeAt = new Map<string, Set<string>>();
  /// Honest entries that were active at a keeper and then were not.
  inactivated = new Set<string>();
  /// Honest entries made inactive at any keeper since `roundDrops` was last cleared.
  roundDrops = new Set<string>();
  /// How many entries each change of a keeper's active chain made inactive (only changes that made some).
  rollbacks: number[] = [];
  trusted = new Map<Keeper, Set<string>>();
  away = new Map<Keeper, Set<string>>();
  /// A device let in at a station, then turned away there with no honest entry taking it out; and let in again after.
  spurious: string[] = [];
  back = 0;
  resigned = 0;
  resigning = false;
  /// Scripted worlds: no lock turned off, no member taken out or changed, these spares left to the script.
  calm = false;
  reserved = new Set<string>();
  /// Scripted worlds: the devices the honest side means to trust once the revocation is signed (`trustedSet`).
  intended = "";
  family: Family;
  log: string[] = [];

  readonly v: Variant;

  constructor(seed: number, v: Variant, family: Family = "free") {
    this.v = v;
    this.rules = new Rules(v);
    this.all = new Map([[this.rules.gh, this.rules.g]]);
    this.known = new Map([[this.rules.gh, this.rules.g]]);
    this.rng = new Rng(seed ^ 0xf0c5);
    this.family = family;
    this.stations = [0, 1, 2].map((i) => new Keeper(`s${i}`, v, this.rules));
    this.devs = [
      ...signers.map((s, i) => ({ i, name: `${s.sub}'s app`, sub: s.sub as string, base: s.app, signer: s.signer })),
      ...spare.map((d, j) => ({ i: signers.length + j, name: d.name, sub: d.sub, base: d.base, signer: d.signer })),
    ].map((d) => ({ ...d, k: new Keeper(d.name, v, this.rules), compromised: false, mine: [], superseded: new Set<string>() }));
    for (const d of this.devs) this.devOf.set(d.k, d);
    this.keepers = [...this.stations, ...this.devs.map((d) => d.k)];
    const g = this.rules.state(this.rules.gh);
    for (const k of this.keepers) this.trusted.set(k, new Set(WATCH.filter((w) => g.devices.has(w.hex)).map((w) => w.hex))), this.away.set(k, new Set());
  }

  note(line: string) {
    this.log.push(line);
  }
  dev(name: string): Dev {
    return this.devs.find((d) => d.name === name)!;
  }
  keeper(name: string): Keeper {
    return this.keepers.find((k) => k.name === name)!;
  }
  entryAt(h: string): Entry {
    return this.all.get(h)!;
  }
  told(h: string): string {
    if (h === this.rules.gh) return "the genesis";
    if (this.rules.ckParent.has(h)) return `the recovery key's checkpoint #${h.slice(0, 6)}`;
    return said(this.entryAt(h));
  }

  // ── keepers taking and choosing ───────────────────────────────────────────────────────────────────────────────

  receive(k: Keeper, es: Entry[]) {
    if (k.take(es)) this.refresh(k);
  }

  /// A keeper goes by its active chain again: what that made inactive, who it lets in now, a device's own entries lost.
  refresh(k: Keeper) {
    const old = k.active;
    const now = k.choose();
    let p = 0;
    while (p < old.length && p < now.length && old[p] === now[p]) p++;
    if (p === old.length && p === now.length) return;
    const dropped = old.slice(p);
    if (dropped.length > 0) {
      this.rollbacks.push(dropped.length);
      for (const h of dropped) {
        if (this.honest.has(h)) this.inactivated.add(h), this.roundDrops.add(h);
      }
      this.note(`  ${k.name} goes by another branch from ${this.told(old[p - 1])}: ${dropped.length} entr${dropped.length === 1 ? "y" : "ies"} no longer active (${dropped.map((h) => this.told(h)).join("; ")})`);
    }
    k.active = now;
    k.on = new Set(now);
    k.ver++;
    for (const h of now.slice(p)) {
      const at = this.activeAt.get(h) ?? new Set<string>();
      at.add(k.name);
      this.activeAt.set(h, at);
    }
    const d = this.devOf.get(k);
    if (d) {
      this.resign(d);
      return;
    }
    // Who a station lets in: what a person notices (an accomplice turned away is no one's loss).
    const s = k.headState();
    const was = this.trusted.get(k)!, away = this.away.get(k)!;
    const is = new Set(WATCH.filter((w) => s.devices.has(w.hex)).map((w) => w.hex));
    for (const hex of was) {
      if (!is.has(hex) && !this.removed.has(hex)) {
        this.spurious.push(`${k.name} turns ${watchName.get(hex)} away`);
        this.note(`  ${k.name} turns ${watchName.get(hex)} away, which no honest entry took out`);
        away.add(hex);
      }
    }
    for (const hex of is) {
      if (!was.has(hex) && away.has(hex)) {
        this.back++;
        away.delete(hex);
        this.note(`  ${k.name} lets ${watchName.get(hex)} in again`);
      }
    }
    this.trusted.set(k, is);
  }

  /// `resign=on`: each of the device's own entries no longer active (its intent on the chain by no other of its entries)
  /// is signed again after its head, where the rules still take it.
  resign(d: Dev) {
    if (this.v.resign === "off" || d.compromised || this.resigning) return;
    this.resigning = true;
    try {
      for (const h of [...d.mine]) {
        if (d.superseded.has(h) || d.k.on.has(h)) continue;
        const what = this.honest.get(h)!;
        const intent = this.intents.get(what.intent)!;
        d.superseded.add(h);
        if (intent.hashes.some((x) => d.k.on.has(x))) continue;
        const e = this.entryAt(h);
        const again = this.sign(d, e.kind, e.body, { probe: what.probe });
        if (again === null) {
          intent.void = true;
          this.note(`  ${d.name} cannot sign ${said(e)} again after its head: the rules refuse it there`);
        } else this.resigned++;
      }
    } finally {
      this.resigning = false;
    }
  }

  // ── lines ─────────────────────────────────────────────────────────────────────────────────────────────────────────

  /// A sync from `from` to `to`, on its way: what `from` offers that `to` lacks.
  send(from: Keeper, to: Keeper) {
    const es = from.offered().filter((e) => !to.store.has(hashOf(e)));
    if (es.length === 0) return;
    const m = { to, entries: es };
    this.queue.push(m);
    this.sent.push(m);
    for (const e of es) this.known.set(hashOf(e), e);
  }

  land(i: number) {
    const [m] = this.queue.splice(i, 1);
    this.receive(m.to, m.entries);
  }

  /// Every keeper syncs with every other, delivered at once, until none stores anything new (`skip`: cut off). Whether
  /// it came to rest within `rounds`.
  level(skip: Set<Keeper> = new Set(), rounds = 200): boolean {
    for (let r = 0; r < rounds; r++) {
      let any = false;
      for (const a of this.keepers) {
        if (skip.has(a)) continue;
        for (const b of this.keepers) {
          if (a === b || skip.has(b)) continue;
          // Neither moved on since `a` last gave `b` all it offers: nothing to give.
          const pair = `${a.name}>${b.name}`, now = `${a.ver}|${b.ver}`;
          if (this.levelled.get(pair) === now) continue;
          const es = a.offered().filter((e) => !b.store.has(hashOf(e)));
          if (es.length > 0) {
            for (const e of es) this.known.set(hashOf(e), e);
            if (b.take(es)) {
              this.refresh(b);
              any = true;
            }
          }
          this.levelled.set(pair, `${a.ver}|${b.ver}`);
        }
      }
      if (!any) return true;
    }
    return false;
  }

  /// The chain from the genesis to `h`, as made.
  chainTo(h: string): Entry[] {
    const out: Entry[] = [];
    for (let x: string | null = h; x !== null; ) {
      const e = this.entryAt(x);
      out.push(e);
      x = this.rules.parentOf(e);
    }
    return out.reverse();
  }

  // ── honest devices ───────────────────────────────────────────────────────────────────────────────────────────────

  /// A device signs an entry after `parent` (its head by default) and, with `bring`, syncs with every station; null
  /// where the rules refuse it there.
  sign(d: Dev, kind: string, body: unknown, o: { parent?: string; bring?: boolean; probe?: boolean } = {}): Entry | null {
    const parent = o.parent ?? d.k.head();
    this.t += 1;
    const e = signed(after([this.entryAt(parent)], this.t, kind, body), d.signer);
    if (!this.rules.valid(e)) return null;
    const h = hashOf(e);
    this.all.set(h, e);
    const intent = `${d.name}|${kind}|${canonical(body ?? null)}`;
    this.honest.set(h, { dev: d, intent, step: this.step, probe: o.probe === true });
    const it = this.intents.get(intent) ?? { dev: d, hashes: [], void: false, probe: o.probe === true };
    it.hashes.push(h);
    this.intents.set(intent, it);
    d.mine.push(h);
    const ps = this.rules.state(parent);
    const out = kind === "device.remove" ? [(body as { id: string }).id] : kind === "member.remove" ? [...ps.devices.values()].filter((x) => x.sub === (body as { sub: string }).sub).map((x) => x.id) : [];
    for (const hex of out) {
      if (!this.removed.has(hex)) this.removed.set(hex, { step: this.step, by: d.base.hex });
      this.everRemoved.add(hex);
      const taken = this.devs.find((x) => x.base.hex === hex && x.i >= signers.length);
      if (taken && this.family === "faults") taken.compromised = true;
    }
    this.note(`  ${d.name} signs ${said(e)} after ${this.told(parent)}`);
    this.receive(d.k, [e]);
    if (o.bring !== false) for (const s of this.stations) this.send(d.k, s);
    return e;
  }

  /// What a device of the world signs next, as drawn (`b`, `c`); null where there is nothing it may sign.
  honestOp(d: Dev, b: number, c: number): { kind: string; body: unknown } | null {
    const s = d.k.headState();
    const me = signer(s, { key: d.signer.id }, null);
    if (me === null || !me.own || s.disabled || !s.devices.has(d.base.hex)) return null;
    const managing = me.role === "owner" || me.role === "admin";
    const free = (x: { base: Key }) => !this.reserved.has(x.base.hex);
    switch (b % 10) {
      case 0: case 1: case 2: case 3: {
        const out = spare.filter((x) => x.sub === d.sub && free(x) && !s.devices.has(x.base.hex) && !this.everRemoved.has(x.base.hex));
        const x = out[c % Math.max(1, out.length)];
        return x ? { kind: "device", body: { id: x.base.hex, sub: x.sub, kind: "app", label: x.name, sign_key: x.signer.id } } : null;
      }
      case 4: case 5: case 6: {
        const inLock = spare.filter((x) => free(x) && s.devices.has(x.base.hex) && x.base.hex !== d.base.hex && (x.sub === d.sub || managing));
        const x = inLock[c % Math.max(1, inLock.length)];
        return x ? { kind: "device.remove", body: { id: x.base.hex } } : null;
      }
      case 7: {
        const sub = c % 2 === 0 ? "bob" : "carol";
        const m = s.members.get(sub);
        if (this.calm || !managing || sub === d.sub || !m || m.role === "owner") return null;
        return { kind: "member", body: { sub, email: `${sub}@x`, role: m.role === "admin" ? "member" : "admin" } };
      }
      case 8: {
        if (!managing) return null;
        const st = stationKeys[2];
        return s.stations.has(st.hex) ? { kind: "station.remove", body: { key: st.hex } } : { kind: "station", body: { key: st.hex, name: "s2" } };
      }
      default: {
        if (this.calm) return null;
        if (c % 8 === 0 && d.i === 0) return { kind: "disable", body: {} };
        if (c % 8 === 1 && managing && d.sub !== "carol" && s.members.has("carol")) return { kind: "member.remove", body: { sub: "carol" } };
        return null;
      }
    }
  }

  // ── a revoked key ──────────────────────────────────────────────────────────────────────────────────────────────

  /// The parents a revoked device's key may sign after: every entry it knows (its device's store, what went over a
  /// line) in whose state it is an own device that signs. Oldest first.
  attackParents(d: Dev): string[] {
    const hs = new Set([...this.known.keys(), ...d.k.store.keys()]);
    return [...hs].filter((h) => {
      const s = this.rules.states.get(h);
      return s !== undefined && !s.disabled && s.devices.get(d.base.hex)?.sign_key === d.signer.id && signer(s, { key: d.signer.id }, null)?.own === true;
    }).sort((x, y) => this.rules.depth(x) - this.rules.depth(y) || (x < y ? -1 : 1));
  }

  /// The revoked key of `d` signs after `parent`: an approval of its accomplice, or the removal of `target`; in
  /// `varied` the lowest-hash of GRIND values of `at`. Null where the rules refuse it.
  attackSign(d: Dev, parent: string, type: "approve" | "remove", target?: string): Entry | null {
    const pe = this.entryAt(parent);
    const ps = this.rules.state(parent);
    const j = d.i - signers.length;
    let kind: string, body: unknown;
    if (type === "approve") {
      kind = "device";
      body = { id: mal[j].base.hex, sub: d.sub, kind: "app", label: mal[j].name };
    } else {
      if (target === undefined || !ps.devices.has(target)) return null;
      kind = "device.remove";
      body = { id: target };
    }
    const tries = this.v.hashfield === "varied" ? GRIND : 1;
    let best: Entry | null = null;
    for (let i = 0; i < tries; i++) {
      const e = signed(after([pe], this.t + 1 + i, kind, body), d.signer);
      if (this.rules.valid(e) && (best === null || hashOf(e) < hashOf(best))) best = e;
    }
    this.t += tries;
    if (best === null) return null;
    const h = hashOf(best);
    this.all.set(h, best);
    this.attack.set(h, d);
    this.note(`  ${d.name}'s key, revoked, signs ${said(best)} after ${this.told(parent)}${tries > 1 ? ` (lowest hash of ${tries} values of at)` : ""}`);
    return best;
  }

  /// What a revoked key signed, brought straight to `to` with the chain before it.
  reach(e: Entry, to: Keeper[]) {
    const chain = this.chainTo(hashOf(e));
    for (const x of chain) this.known.set(hashOf(x), x);
    for (const k of to) {
      this.note(`  it reaches ${k.name}`);
      this.receive(k, chain);
    }
  }

  // ── a recovery key (`recovery=on`; not Tailscale's rule as modelled, see Variant) ─────────────────────────────────

  /// The recovery key's checkpoint against `T` (MakeRetroactiveRevocation as the lead reads it): hung below the parent of
  /// the entry that first put `T` in, the whole state `from` goes by without `T` and without every device an entry of
  /// `T`'s key put in.
  recover(T: Dev, from: Keeper): Entry {
    const adds = [...this.all.entries()].filter(([h, e]) => e.kind === "device" && (e.body as { id?: string }).id === T.base.hex && this.rules.depths.has(h) && !this.attack.has(h));
    const [, first] = adds.sort(([x], [y]) => this.rules.depth(x) - this.rules.depth(y))[0];
    const byT = new Set([...this.all.values()].filter((e) => e.sig.key === T.signer.id && e.kind === "device").map((e) => (e.body as { id: string }).id));
    const s = from.headState();
    const devices = [...s.devices.values()].filter((d) => d.id !== T.base.hex && !byT.has(d.id)).map((d) => ({
      id: d.id, sub: d.sub, kind: d.kind, label: d.label, ...(d.sign_key !== undefined ? { sign_key: d.sign_key } : {}),
      ...(d.endpoints !== undefined ? { endpoints: d.endpoints } : {}), ...(d.exp !== undefined ? { exp: d.exp } : {}),
    }));
    if (!devices.some((d) => d.id === RKDEV.id)) devices.push(RKDEV);
    const g = this.rules.g.body as Record<string, unknown>;
    this.t += 1;
    const ck = signed({
      v: 1, ws: WS, seq: 0, prev: null, at: this.t, kind: "genesis", body: {
        owner: g.owner, origins: g.origins, rp_id: g.rp_id, cloud_keys: g.cloud_keys, members: [...s.members.values()], devices, passkeys: [],
        stations: [...s.stations.values()], gateways: [],
      },
    }, RK);
    const h = hashOf(ck);
    this.rules.ckParent.set(h, first.prev!);
    this.all.set(h, ck);
    this.note(`  the recovery key signs a checkpoint #${h.slice(0, 6)} after ${this.told(first.prev!)} (the parent of ${said(first)}): the state ${from.name} goes by, without ${T.name}${byT.size > 0 ? ` and the ${byT.size} device(s) its key put in` : ""}`);
    return ck;
  }

  /// The honest side uses the recovery key once, everything delivered; then the revoked key signs after each parent
  /// `parents` gives (`y` as before), brought to one station, every keeper syncing. What the checkpoint made inactive,
  /// whether the revoked key's tries are active anywhere, how many parents it can still sign after.
  recoverAndRetry(T: Dev, R: Dev, parents: () => string[], y: "approve" | "remove"): NonNullable<CaseOutcome["ck"]> {
    this.roundDrops = new Set();
    const ck = this.recover(T, this.stations[0]);
    this.reach(ck, this.keepers);
    this.level();
    const drops = [...this.roundDrops].filter((h) => this.honest.get(h)?.dev !== T).length;
    const tries: Entry[] = [];
    for (const p of parents()) {
      const e = this.attackSign(T, p, y, R.base.hex);
      if (e === null) continue;
      tries.push(e);
      this.reach(e, [this.stations[this.rng.int(3)]]);
      this.level();
    }
    return { drops, retryActive: tries.some((e) => this.keepers.some((k) => k.on.has(hashOf(e)))), parentsLeft: this.attackParents(T).length };
  }

  // ── a drawn world ────────────────────────────────────────────────────────────────────────────────────────────────

  run(steps: Step[]) {
    for (const [n, st] of steps.entries()) {
      this.step = n;
      const kind = KINDS[st.k];
      const fault = kind === "drop" || kind === "replay" || kind === "forge" || kind === "stale";
      if (fault && this.family === "free") continue;
      this.note(`${n}: ${kind}`);
      switch (kind) {
        case "deliver":
          if (this.queue.length > 0) this.land(st.a % this.queue.length);
          break;
        case "sign": {
          const d = this.devs[st.a % this.devs.length];
          if (d.compromised) break;
          const op = this.honestOp(d, st.b, st.c);
          if (op) this.sign(d, op.kind, op.body);
          break;
        }
        case "sync": {
          const a = this.keepers[st.a % this.keepers.length], b = this.keepers[st.b % this.keepers.length];
          if (a !== b) this.send(a, b), this.send(b, a);
          break;
        }
        case "drop":
          if (this.queue.length > 0) this.queue.splice(st.a % this.queue.length, 1);
          break;
        case "replay":
          if (this.sent.length > 0) this.queue.push({ ...this.sent[st.a % this.sent.length] });
          break;
        case "forge": {
          const k = this.keepers[st.a % this.keepers.length];
          const head = this.entryAt(k.head());
          const eveBody = { id: eve.base.hex, sub: eve.sub, kind: "app", label: "eve" };
          this.t += 1;
          const f = st.b % 2 === 0
            ? signed(after([head], this.t, "device", eveBody), eveKey)
            : { ...signed(after([head], this.t, "device", { ...eveBody, label: "x" }), signers[0].signer), body: eveBody };
          this.forged.add(hashOf(f));
          this.all.set(hashOf(f), f);
          this.queue.push({ to: k, entries: [f] });
          this.note(`  a relay forges an entry for ${k.name}`);
          break;
        }
        case "stale": {
          const taken = this.devs.filter((d) => d.compromised);
          if (taken.length === 0) break;
          const d = taken[st.a % taken.length];
          const ps = this.attackParents(d);
          if (ps.length === 0) break;
          const by = this.removed.get(d.base.hex)?.by;
          const e = this.attackSign(d, ps[st.c % ps.length], st.b % 2 === 0 || by === undefined ? "approve" : "remove", by);
          if (e === null) break;
          const to = this.keepers[(st.a >> 4) % this.keepers.length];
          const chain = this.chainTo(hashOf(e)).filter((x) => !to.store.has(hashOf(x)));
          for (const x of chain) this.known.set(hashOf(x), x);
          this.queue.push({ to, entries: chain });
          this.note(`  on its way to ${to.name}`);
          break;
        }
      }
    }
    this.step = steps.length;
  }

  /// Everything on its way delivered (in an order the seed draws), then every keeper synced with every other until
  /// nothing new is stored.
  finish(): boolean {
    this.note("end: everything on its way lands, every keeper syncs with every other");
    while (this.queue.length > 0) this.land(this.rng.int(this.queue.length));
    return this.level();
  }

  agree(): boolean {
    return new Set(this.keepers.map((k) => k.head())).size === 1;
  }

  /// What a revoked device kept at each keeper in the end: still trusted, its accomplice trusted, what its key signed
  /// active, what its device signed after it was taken out active.
  revocation(): { trusted: string[]; accomplice: string[]; attack: string[]; stale: string[] } {
    const out = { trusted: [] as string[], accomplice: [] as string[], attack: [] as string[], stale: [] as string[] };
    for (const [hex, r] of this.removed) {
      const name = watchName.get(hex) ?? hex.slice(0, 8);
      const j = spare.findIndex((x) => x.base.hex === hex);
      for (const k of this.keepers) {
        const s = k.headState();
        if (s.devices.has(hex)) out.trusted.push(`${k.name} trusts ${name}`);
        if (j >= 0 && s.devices.has(mal[j].base.hex)) out.accomplice.push(`${k.name} trusts ${mal[j].name}`);
        for (const h of k.active) {
          const a = this.attack.get(h);
          if (a?.base.hex === hex) out.attack.push(`${k.name}: ${this.told(h)}`);
          const o = this.honest.get(h);
          if (o && o.dev.base.hex === hex && o.step > r.step && !o.probe) out.stale.push(`${k.name}: ${this.told(h)}`);
        }
      }
    }
    return out;
  }
}

// ── what a drawn world measured ─────────────────────────────────────────────────────────────────────────────────────

export type Measured = {
  rested: boolean;
  agree: boolean;
  /// Trusted devices whose no-op entry, signed after their head once everything landed, is not active at every keeper.
  probeFail: number;
  probes: number;
  revocation: ReturnType<World["revocation"]>;
  honest: number;
  inactivated: number;
  /// Honest intents (not probes) on no keeper's final chain, of which the rules refused to sign again (`void`).
  lost: number;
  void: number;
  spurious: number;
  back: number;
  awayAtEnd: number;
  rollbacks: number[];
  /// The most keepers at which a revoked key's entry was ever active; how many such entries were made.
  attackActiveMax: number;
  attacks: number;
  forgedStored: boolean;
};

export function drawn(seed: number, v: Variant, family: Family, steps: Step[]): { w: World; m: Measured } {
  const w = new World(seed, v, family);
  w.run(steps);
  const rested = w.finish();
  const agree = w.agree();
  const final = w.keepers[0];
  const honest = [...w.honest.values()].filter((x) => !x.probe).length;
  let lost = 0, voided = 0;
  for (const it of w.intents.values()) {
    if (it.probe || it.hashes.some((h) => final.on.has(h))) continue;
    if (it.void) voided++;
    else lost++;
  }
  const revocation = w.revocation();
  const m: Measured = {
    rested, agree, probeFail: 0, probes: 0, revocation, honest, inactivated: [...w.inactivated].filter((h) => !w.honest.get(h)!.probe).length,
    lost, void: voided, spurious: w.spurious.length, back: w.back, awayAtEnd: [...w.away.values()].reduce((n, s) => n + s.size, 0),
    rollbacks: [...w.rollbacks], attackActiveMax: Math.max(0, ...[...w.attack.keys()].map((h) => w.activeAt.get(h)?.size ?? 0)),
    attacks: w.attack.size,
    forgedStored: w.keepers.some((k) => [...w.forged].some((h) => k.store.has(h))),
  };
  // Each trusted honest device signs a no-op after its head (itself put in again as it is), everything lands.
  for (const d of w.devs) {
    if (d.compromised) continue;
    const s = d.k.headState();
    const me = signer(s, { key: d.signer.id }, null);
    const it = s.devices.get(d.base.hex);
    if (me === null || !me.own || it === undefined || s.disabled) continue;
    const e = w.sign(d, "device", { id: it.id, sub: it.sub, kind: it.kind, label: it.label, sign_key: it.sign_key }, { probe: true });
    if (e === null) continue;
    m.probes++;
    w.level();
    if (!w.keepers.every((k) => k.on.has(hashOf(e)))) m.probeFail++;
  }
  return { w, m };
}

/// The fewest steps that still have `bad`: chunks taken out, halving.
export function shrink(seed: number, v: Variant, family: Family, steps: Step[], bad: (m: Measured, w: World) => boolean): Step[] {
  let now = steps;
  let tries = 0;
  for (let size = Math.floor(now.length / 2); size >= 1; size = Math.floor(size / 2)) {
    for (let at = 0; at + size <= now.length && tries < 300; tries++) {
      const less = [...now.slice(0, at), ...now.slice(at + size)];
      const r = drawn(seed, v, family, less);
      if (bad(r.m, r.w)) now = less;
      else at += size;
    }
  }
  return now;
}

// ── scripted worlds ─────────────────────────────────────────────────────────────────────────────────────────────────

/// `n` honest entries one after another, each by an app the seed picks, everyone level after each.
export function prefix(w: World, n: number) {
  for (let i = 0, guard = 0; i < n && guard < 20 * n + 20; guard++) {
    const d = w.devs[w.rng.int(3)];
    const op = w.honestOp(d, w.rng.int(1 << 16), w.rng.int(1 << 16));
    if (op === null) continue;
    if (w.sign(d, op.kind, op.body, { bring: false }) === null) continue;
    w.level();
    i++;
  }
}

export type CaseOutcome = {
  fail: boolean;
  why: string[];
  /// Keepers at which the revoked key's entry was active before the revoking side's reached them.
  activeBefore: number;
  /// The most entries a keeper stopped going by at once when the branches met.
  rollback: number;
  entries: number;
  /// Whether every keeper trusts in the end exactly the devices the honest side meant (its chain once the revocation
  /// was signed, before the revoked key signed anything; the recovery key's own name aside).
  exact: boolean;
  /// `recovery=on`: the honest entries its checkpoint made inactive (at any keeper); whether the revoked key's next
  /// entry, signed after it, was active anywhere in the end; how many parents it could still sign after.
  ck?: { drops: number; retryActive: boolean; parentsLeft: number };
  w: World;
};

/// The devices a keeper trusts, the recovery key's own name aside.
const trustedSet = (k: Keeper) => [...k.headState().devices.keys()].filter((id) => id !== RKDEV.id).sort().join(",");

/// A revoked key's competing entry: `revoker` takes `target` out after the head everyone holds but one station (cut
/// off); `second`, if given, signs the same removal after the same parent; then the target's key signs `y` (an approval
/// of its accomplice, or the removal of the revoker) after the revocation's parent (`same`) or after any parent it is
/// trusted in (`any`, drawn), and brings it to the station that missed the revocation (and, on odd seeds, to one device).
/// Then every keeper syncs with every other. With a recovery key, its checkpoint then, and the revoked key's one try
/// more (after a parent as before), brought to one station, every keeper syncing. Fails where, at any keeper, the target
/// is trusted, its accomplice is, or what its key signed is active.
export function revokeCase(seed: number, v: Variant, o: { revoker: string; target: string; y: "approve" | "remove"; parent: "same" | "any"; second?: string; before?: number; between?: number; cut?: number; later?: boolean }): CaseOutcome {
  const w = new World(seed, v, "free");
  w.calm = true;
  const T = w.dev(o.target), R = w.dev(o.revoker), S = o.second ? w.dev(o.second) : undefined;
  for (const d of [T, S]) if (d) w.reserved.add(d.base.hex);
  prefix(w, o.before ?? w.rng.int(5));
  const appOf = (d: Dev) => w.devs.find((x) => x.sub === d.sub && x.i < signers.length)!;
  for (const d of [T, S]) {
    if (!d) continue;
    const by = appOf(d);
    w.sign(by, "device", { id: d.base.hex, sub: d.sub, kind: "app", label: d.name, sign_key: d.signer.id }, { bring: false });
    w.level();
  }
  prefix(w, o.between ?? w.rng.int(8));
  const cut = w.stations[o.cut ?? w.rng.int(3)];
  w.note(`${cut.name} is cut off`);
  const r = w.sign(R, "device.remove", { id: T.base.hex }, { bring: false });
  if (r === null) throw new Error(`${R.name} cannot take ${T.name} out`);
  const X = r.prev!;
  if (S) w.sign(S, "device.remove", { id: T.base.hex }, { parent: X, bring: false });
  w.level(new Set([cut]));
  const intended = trustedSet(R.k);
  w.intended = intended;
  T.compromised = true;
  const pick = () => {
    const parents = w.attackParents(T).filter((h) => w.rules.depth(h) <= w.rules.depth(X));
    return o.parent === "same" ? X : parents[w.rng.int(parents.length)];
  };
  const parent = pick();
  const y = w.attackSign(T, parent, o.y, R.base.hex);
  if (y === null) throw new Error(`${T.name}'s key cannot sign after ${w.told(parent)}`);
  const reached = [cut, ...(seed % 2 === 1 ? [w.devs[w.rng.int(3)].k] : [])];
  w.reach(y, reached);
  const activeBefore = w.keepers.filter((k) => k.on.has(hashOf(y))).length;
  w.note(`${cut.name} is back: every keeper syncs with every other`);
  const from = w.rollbacks.length;
  w.level();
  const rolled = w.rollbacks.slice(from);
  // (`later`: the repeated contest uses the recovery key once its own rounds are over)
  const ck = w.v.recovery === "on" && o.later !== true ? w.recoverAndRetry(T, R, () => [pick()], o.y) : undefined;
  return outcome(w, T, activeBefore, rolled, intended, ck);
}

function outcome(w: World, T: Dev, activeBefore: number, rolled: number[], intended: string, ck?: CaseOutcome["ck"]): CaseOutcome {
  const j = T.i - signers.length;
  const why: string[] = [];
  const at = (f: (k: Keeper) => boolean) => w.keepers.filter(f).map((k) => k.name);
  const trusted = at((k) => k.headState().devices.has(T.base.hex));
  const accomplice = at((k) => k.headState().devices.has(mal[j].base.hex));
  const attack = at((k) => k.active.some((h) => w.attack.has(h)));
  const gone = w.devs.filter((d) => !d.compromised && d.i < signers.length && w.keepers.some((k) => !k.headState().devices.has(d.base.hex)));
  const exact = w.keepers.every((k) => trustedSet(k) === intended);
  if (trusted.length) why.push(`${T.name} trusted at ${trusted.length} keepers`);
  if (accomplice.length) why.push(`${mal[j].name} trusted at ${accomplice.length}`);
  if (attack.length) why.push(`its key's entry active at ${attack.length}`);
  if (gone.length) why.push(`${gone.map((d) => d.name).join(", ")} turned away`);
  if (!exact) why.push("the trusted set is not the one meant");
  return { fail: trusted.length + accomplice.length + attack.length > 0, why, activeBefore, rollback: Math.max(0, ...rolled), entries: w.all.size, exact, ck, w };
}

/// The repeated contest: as `revokeCase`, then, as long as the revoked key is not trusted once everything landed, it
/// signs again after the nearest parent earlier than its last one in which it is trusted, brings it to one station, and
/// every keeper syncs. Rounds until it is trusted, or no earlier parent is left (or `cap`). With a recovery key, its
/// checkpoint then, and as many tries more as the revoked key had (each after the latest parent it is trusted in that it
/// did not sign after yet).
export function contest(seed: number, v: Variant, y: "approve" | "remove", cap = 64) {
  const first = revokeCase(seed, v, { revoker: "alice's app", target: "alice's phone", y, parent: "same", later: true });
  const w = first.w;
  const T = w.dev("alice's phone"), R = w.dev("alice's app");
  const perRound: number[] = [];
  // How deep the parent its last entry was signed after is.
  let last = w.rules.depth(w.entryAt([...w.attack.keys()][0]).prev!);
  let end: "trusted" | "no earlier parent" | "cap" = "cap";
  for (let round = 0; round < cap; round++) {
    if (w.keepers.every((k) => k.headState().devices.has(T.base.hex))) {
      end = "trusted";
      break;
    }
    const earlier = w.attackParents(T).filter((h) => w.rules.depth(h) < last && !w.rules.ckParent.has(h));
    const e = earlier.length === 0 ? null : w.attackSign(T, earlier[earlier.length - 1], y, R.base.hex);
    if (e === null) {
      end = "no earlier parent";
      break;
    }
    last = w.rules.depth(e.prev!);
    w.roundDrops = new Set();
    w.reach(e, [w.stations[w.rng.int(3)]]);
    w.level();
    perRound.push(w.roundDrops.size);
  }
  const tries = 1 + perRound.length;
  const ck = w.v.recovery === "on"
    ? w.recoverAndRetry(T, R, () => {
      const used = new Set([...w.attack.keys()].map((h) => w.entryAt(h).prev));
      return w.attackParents(T).filter((h) => !used.has(h)).reverse().slice(0, tries);
    }, y)
    : undefined;
  return { first, rounds: perRound.length, perRound, end, w, final: outcome(w, T, 0, [], w.intended, ck) };
}

/// A key revoked long ago: alice's phone put in, `r` entries, its removal, then `depth` entries more, everyone level;
/// its key signs after the removal's parent (`same`) or after any parent it is trusted in (`any`), brought to one
/// station, then every keeper syncs. With a recovery key, its checkpoint then, and one try more as before.
export function longAgo(seed: number, v: Variant, y: "approve" | "remove", parent: "same" | "any", depth = 50): CaseOutcome {
  const w = new World(seed, v, "free");
  w.calm = true;
  const T = w.dev("alice's phone"), A = w.dev("alice's app"), B = w.dev("bob's app");
  w.reserved.add(T.base.hex);
  w.sign(A, "device", { id: T.base.hex, sub: T.sub, kind: "app", label: T.name, sign_key: T.signer.id }, { bring: false });
  w.level();
  prefix(w, 2 + w.rng.int(5));
  const r = w.sign(A, "device.remove", { id: T.base.hex }, { bring: false })!;
  w.level();
  // The entries after: alice and bob changing carol's role and the third station, one after another.
  for (let i = 0; i < depth; i++) {
    const d = w.rng.int(2) === 0 ? A : B;
    const s = d.k.headState();
    const st = stationKeys[2];
    const op = w.rng.int(2) === 0
      ? { kind: "member", body: { sub: "carol", email: "carol@x", role: s.members.get("carol")?.role === "admin" ? "member" : "admin" } }
      : s.stations.has(st.hex) ? { kind: "station.remove", body: { key: st.hex } } : { kind: "station", body: { key: st.hex, name: "s2" } };
    w.sign(d, op.kind, op.body, { bring: false });
    w.level();
  }
  const intended = trustedSet(A.k);
  w.intended = intended;
  T.compromised = true;
  const pick = () => {
    const parents = w.attackParents(T);
    return parent === "same" ? r.prev! : parents[w.rng.int(parents.length)];
  };
  const p = pick();
  const e = w.attackSign(T, p, y, A.base.hex)!;
  w.note(`(${w.rules.depth(w.keepers[0].head()) - w.rules.depth(p)} entries after its parent are active everywhere)`);
  w.reach(e, [w.stations[w.rng.int(3)]]);
  const from = w.rollbacks.length;
  w.level();
  const rolled = w.rollbacks.slice(from);
  const ck = w.v.recovery === "on" ? w.recoverAndRetry(T, A, () => [pick()], y) : undefined;
  return outcome(w, T, 0, rolled, intended, ck);
}

/// `retain`: a keeper away while more entries than it retains were made. `device`: bob's app, cut off, signs after its
/// stale head and comes back. `approve`/`remove`: alice's phone taken out while s2 was away; the phone's key signs after
/// the chain from before its removal (an approval of its accomplice, or the removal of alice's app) and brings it to s2
/// alone, which comes back. Then every keeper syncs with every other.
export function offline(seed: number, v: Variant, who: "device" | "approve" | "remove", away: number): { agree: boolean; kept: boolean; storedElsewhere: boolean; fail: boolean; entries: number; w: World } {
  const w = new World(seed, v, "free");
  w.calm = true;
  const A = w.dev("alice's app"), P = w.dev("alice's phone");
  const others = [w.dev("alice's app"), w.dev("carol's app")];
  if (who !== "device") {
    w.reserved.add(P.base.hex);
    w.sign(A, "device", { id: P.base.hex, sub: P.sub, kind: "app", label: P.name, sign_key: P.signer.id }, { bring: false });
    w.level();
  }
  prefix(w, w.rng.int(4));
  const gone = who === "device" ? w.dev("bob's app").k : w.stations[2];
  w.note(`${gone.name} is away`);
  const skip = new Set([gone]);
  let r: Entry | null = null;
  if (who !== "device") {
    r = w.sign(A, "device.remove", { id: P.base.hex }, { bring: false });
    w.level(skip);
  }
  for (let i = 0, guard = 0; i < away && guard < 50 * away; guard++) {
    const d = others[w.rng.int(others.length)];
    const op = w.honestOp(d, w.rng.int(1 << 16), w.rng.int(1 << 16));
    if (op === null || w.sign(d, op.kind, op.body, { bring: false }) === null) continue;
    w.level(skip);
    i++;
  }
  let e: Entry | null = null;
  if (who === "device") {
    const B = w.dev("bob's app");
    for (let guard = 0; e === null && guard < 50; guard++) {
      const op = w.honestOp(B, w.rng.int(1 << 16), w.rng.int(1 << 16));
      if (op) e = w.sign(B, op.kind, op.body, { bring: false });
    }
  } else {
    P.compromised = true;
    e = w.attackSign(P, r!.prev!, who, A.base.hex);
    if (e) w.reach(e, [gone]);
  }
  w.note(`${gone.name} is back: every keeper syncs with every other`);
  w.level();
  const intent = e ? w.honest.get(hashOf(e))?.intent : undefined;
  const kept = e !== null && (intent ? w.intents.get(intent)!.hashes.some((h) => w.keepers.every((k) => k.on.has(h))) : w.keepers.every((k) => k.on.has(hashOf(e!))));
  const storedElsewhere = e !== null && w.keepers.some((k) => k !== gone && k.store.has(hashOf(e!)));
  const fail = who !== "device" && w.keepers.some((k) => k.headState().devices.has(P.base.hex) || k.headState().devices.has(mal[0].base.hex) || k.active.some((h) => w.attack.has(h)));
  return { agree: w.agree(), kept, storedElsewhere, fail, entries: w.all.size, w };
}

// ── the worlds that fail on this branch today (lock-world-sim.ts), under the rule ────────────────────────────────────

/// Two entries after the genesis, each reaching another station first, then every keeper syncs: one device signing
/// twice (alice's app approves her phone, then her laptop, before it holds the first), or two devices at once (alice
/// her phone, bob his laptop). What came of each.
export function twoAfterOne(v: Variant, two: boolean): { w: World; said: string } {
  const w = new World(0, v, "free");
  const A = w.dev("alice's app"), B = two ? w.dev("bob's app") : A;
  const phone = spare[0], laptop = two ? spare[3] : spare[1];
  const body = (x: (typeof spare)[number]) => ({ id: x.base.hex, sub: x.sub, kind: "app", label: x.name, sign_key: x.signer.id });
  const e1 = w.sign(A, "device", body(phone), { parent: GH, bring: false })!;
  w.receive(w.stations[0], [e1]);
  const e2 = w.sign(B, "device", body(laptop), { parent: GH, bring: false })!;
  w.receive(w.stations[1], [e2]);
  const before = [`s0 lets ${phone.name} in: ${w.stations[0].headState().devices.has(phone.base.hex)}`, `s1 lets ${laptop.name} in: ${w.stations[1].headState().devices.has(laptop.base.hex)}`];
  const rested = w.level();
  const where = (e: Entry) => w.keepers.filter((k) => k.on.has(hashOf(e))).length;
  const trusted = (x: { base: Key }) => w.keepers.filter((k) => k.headState().devices.has(x.base.hex)).length;
  const n = w.keepers.length;
  const text = [
    ...before,
    `then: ${phone.name}'s entry active at ${where(e1)}/${n}, ${laptop.name}'s at ${where(e2)}/${n}`,
    `${phone.name} trusted at ${trusted(phone)}/${n}, ${laptop.name} at ${trusted(laptop)}/${n}`,
    `signed again: ${w.resigned}; turned away unasked: ${w.spurious.length ? w.spurious.join(", ") : "none"}; let in again: ${w.back}`,
    `one chain: ${w.agree()}${rested ? "" : " (not at rest)"}`,
  ];
  return { w, said: text.join("; ") };
}

/// A station that never hears of a revocation: alice puts her phone in, s2 is cut off for good, alice takes the phone
/// out, everyone else syncs.
export function withheld(v: Variant): { w: World; trusts: boolean; others: boolean } {
  const w = new World(0, v, "free");
  const A = w.dev("alice's app"), P = w.dev("alice's phone");
  w.sign(A, "device", { id: P.base.hex, sub: P.sub, kind: "app", label: P.name, sign_key: P.signer.id }, { bring: false });
  w.level();
  w.note("s2 is cut off, for good");
  w.sign(A, "device.remove", { id: P.base.hex }, { bring: false });
  const s2 = w.stations[2];
  w.level(new Set([s2]));
  return { w, trusts: s2.headState().devices.has(P.base.hex), others: w.keepers.some((k) => k !== s2 && k.headState().devices.has(P.base.hex)) };
}

// ── what the runner asks, in worker threads ─────────────────────────────────────────────────────────────────────────
// Each job is one variant's share of one table, its worlds seeded as before: which thread runs it changes nothing of
// what it measures. What comes back is plain data (the counts, the smallest world's lines).

const revocationBad = (m: Measured) => m.revocation.trusted.length + m.revocation.accomplice.length + m.revocation.attack.length + m.revocation.stale.length > 0;
export const PROPS: { name: string; bad: (m: Measured) => boolean }[] = [
  { name: "keepers disagree in the end", bad: (m) => !m.agree },
  { name: "a trusted device's entry is not active everywhere", bad: (m) => m.probeFail > 0 },
  { name: "a revocation does not hold", bad: revocationBad },
  { name: "an honest entry made inactive", bad: (m) => m.inactivated > 0 },
  { name: "an honest intent lost in the end", bad: (m) => m.lost > 0 },
  { name: "a device let in, then turned away unasked", bad: (m) => m.spurious > 0 },
];

/// Upper ends of the rollback-depth histogram's buckets.
export const BUCKETS = [1, 2, 3, 5, 10, 20, 50, Infinity];
const q = (xs: number[], f: number) => {
  if (xs.length === 0) return 0;
  const s = [...xs].sort((a, b) => a - b);
  return s[Math.min(s.length - 1, Math.floor(f * s.length))];
};

/// What a scripted case does, by its table name.
export const CASES: Record<string, (seed: number, v: Variant) => CaseOutcome> = {};
for (const parent of ["same", "any"] as const) {
  CASES[`a ${parent}`] = (s, v) => revokeCase(s, v, { revoker: "alice's app", target: "alice's phone", y: "approve", parent });
  CASES[`b ${parent}`] = (s, v) => revokeCase(s, v, { revoker: "alice's app", target: "alice's phone", y: "remove", parent });
  CASES[`c ${parent}`] = (s, v) => revokeCase(s, v, { revoker: "alice's app", target: "bob's phone", y: "remove", parent });
  CASES[`c2 ${parent}`] = (s, v) => revokeCase(s, v, { revoker: "alice's app", target: "alice's phone", y: "remove", parent, second: "alice's laptop" });
}
export const CASE_NAMES = ["a same", "b same", "c same", "c2 same", "a any", "b any", "c any", "c2 any"];

export type Job =
  | { t: "drawn"; family: Family; v: Variant; runs: number; steps: number }
  | { t: "shrink"; family: Family; v: Variant; seed: number; steps: number; prop: string }
  | { t: "case"; name: string; v: Variant; n: number }
  | { t: "contest"; v: Variant; y: "approve" | "remove"; n: number }
  | { t: "contestLog"; v: Variant }
  | { t: "long"; v: Variant; y: "approve" | "remove"; parent: "same" | "any"; n: number }
  | { t: "offline"; v: Variant; who: "device" | "approve" | "remove"; away: number; n: number };

/// What a recovery key's checkpoint did over a case's seeds (`recovery=on`).
export type CkRow = { n: number; drops: number; dropsMax: number; retryActive: number; parentsLeft: number };
const ckRow = (): CkRow => ({ n: 0, drops: 0, dropsMax: 0, retryActive: 0, parentsLeft: 0 });
const ckAdd = (r: CkRow, c: CaseOutcome["ck"]) => {
  if (!c) return;
  r.n++;
  r.drops += c.drops;
  r.dropsMax = Math.max(r.dropsMax, c.drops);
  if (c.retryActive) r.retryActive++;
  r.parentsLeft += c.parentsLeft;
};

export type Smallest = { entries: number; why: string[]; log: string[] } | null;

export function runJob(j: Job): unknown {
  switch (j.t) {
    case "drawn": {
      let agree = 0, probe = 0, revoc = 0, honest = 0, inact = 0, lost = 0, voided = 0, turned = 0, awayEnd = 0, attackAt = 0, attacks = 0, rested = 0;
      let forged = false;
      const rb: number[] = [];
      const firstBad: Record<string, number> = {};
      for (let seed = 1; seed <= j.runs; seed++) {
        const { m } = drawn(seed, j.v, j.family, drawSteps(seed, j.steps));
        if (m.forgedStored) forged = true;
        if (m.rested) rested++;
        if (m.agree) agree++;
        if (m.probeFail > 0) probe++;
        if (revocationBad(m)) revoc++;
        honest += m.honest;
        inact += m.inactivated;
        lost += m.lost;
        voided += m.void;
        if (m.spurious > 0) turned++;
        if (m.awayAtEnd > 0) awayEnd++;
        attackAt += m.attackActiveMax;
        attacks += m.attacks;
        rb.push(...m.rollbacks);
        for (const p of PROPS) if (p.bad(m) && firstBad[p.name] === undefined) firstBad[p.name] = seed;
      }
      const hist = BUCKETS.map((b, i) => rb.filter((x) => x <= b && x > (i === 0 ? 0 : BUCKETS[i - 1])).length);
      return { agree, probe, revoc, honest, inact, lost, voided, turned, awayEnd, attackAt, attacks, rested, forged, p50: q(rb, 0.5), p90: q(rb, 0.9), max: Math.max(0, ...rb), hist, firstBad };
    }
    case "shrink": {
      const p = PROPS.find((x) => x.name === j.prop)!;
      const fewest = shrink(j.seed, j.v, j.family, drawSteps(j.seed, j.steps), (m) => p.bad(m));
      const again = drawn(j.seed, j.v, j.family, fewest);
      return { len: fewest.length, revocation: again.m.revocation, log: again.w.log };
    }
    case "case": {
      let fail = 0, before = 0, rb = 0, exact = 0;
      let smallest: Smallest = null;
      const ck = ckRow();
      for (let seed = 1; seed <= j.n; seed++) {
        const o = CASES[j.name](seed, j.v);
        if (o.fail) {
          fail++;
          if (smallest === null || o.entries < smallest.entries) smallest = { entries: o.entries, why: o.why, log: o.w.log };
        }
        if (o.exact) exact++;
        ckAdd(ck, o.ck);
        before += o.activeBefore;
        rb = Math.max(rb, o.rollback);
      }
      return { fail, before, rb, smallest, exact, ck };
    }
    case "contest": {
      const rounds: number[] = [], drops: number[] = [];
      const ends: Record<string, number> = {};
      let failed = 0, exact = 0;
      const ck = ckRow();
      let smallest: Smallest = null;
      for (let seed = 1; seed <= j.n; seed++) {
        const c = contest(seed, j.v, j.y);
        if (c.final.fail) {
          failed++;
          if (smallest === null || c.final.entries < smallest.entries) smallest = { entries: c.final.entries, why: c.final.why, log: c.w.log };
        }
        if (c.final.exact) exact++;
        ckAdd(ck, c.final.ck);
        rounds.push(c.rounds);
        drops.push(...c.perRound);
        ends[c.end] = (ends[c.end] ?? 0) + 1;
      }
      return { rounds, drops, ends, failed, exact, ck, smallest };
    }
    case "contestLog": {
      const c = contest(1, j.v, "approve");
      return { rounds: c.rounds, end: c.end, perRound: c.perRound, why: c.final.why, log: c.w.log };
    }
    case "long": {
      let fail = 0, rb = 0, exact = 0;
      let smallest: Smallest = null;
      const ck = ckRow();
      for (let seed = 1; seed <= j.n; seed++) {
        const o = longAgo(seed, j.v, j.y, j.parent);
        if (o.fail) {
          fail++;
          if (smallest === null || o.entries < smallest.entries) smallest = { entries: o.entries, why: o.why, log: o.w.log };
        }
        if (o.exact) exact++;
        ckAdd(ck, o.ck);
        rb = Math.max(rb, o.rollback);
      }
      return { fail, rb, smallest, exact, ck };
    }
    case "offline": {
      let agree = 0, kept = 0, stored = 0, fail = 0;
      let disagree: Smallest = null, failed: Smallest = null;
      for (let seed = 1; seed <= j.n; seed++) {
        const o = offline(seed, j.v, j.who, j.away);
        if (o.agree) agree++;
        else if (disagree === null || o.entries < disagree.entries) disagree = { entries: o.entries, why: [], log: o.w.log };
        if (o.kept) kept++;
        if (o.storedElsewhere) stored++;
        if (o.fail) {
          fail++;
          if (failed === null || o.entries < failed.entries) failed = { entries: o.entries, why: [], log: o.w.log };
        }
      }
      return { agree, kept, stored, fail, disagree, failed };
    }
  }
}

// A worker thread of the runner's: it answers jobs until it is let go.
if (!isMainThread && (workerData as { lockForkChoice?: boolean } | null)?.lockForkChoice === true) {
  parentPort!.on("message", (m: { id: number; job: Job }) => {
    parentPort!.postMessage({ id: m.id, out: runJob(m.job) });
  });
}
