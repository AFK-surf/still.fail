// The fourth round of the lock's model (2026-11-13), built on the third (lock-roster-model.ts) as that one is on the
// first two: what a workspace is when its statements are commitments in its people's logs with bodies kept apart (D1),
// web devices in a person's own log (D2), the settings and turning off said by the root alone (D3), one state out of it
// (D4), the handover from a workspace's own chain (D5), and, once it moved, the chain as it moved still saying what the
// logs have not said yet of those it named (D6, the lead's, 2026-11-14: `carriedOf`, M8), so the handover waits for nobody. This is the lead's design, NOT the product's: the product's
// person logs take `genesis`, `device`, `device.remove` (rules/src/lock/person.mbt `fold_person`) and round three's
// statements in the clear (`fold_person_ws`, rules/src/lock/roster.mbt); the model checks the kinds `ws`, `web`,
// `web.remove` and the old chain's `moved` itself. Run by lock-roster4.test.ts, which prints what it measured.
//
// D1 as modelled: a statement is an entry `ws {t, h}` in its signer's log, `t` sha256 of the workspace and the log's
// genesis, `h` sha256 of the body's canonical form; the body `{ws, kind, …, salt}` travels apart from the entry, in
// messages of its own that are dropped, delayed, reordered and replayed as entries are. Who keeps a workspace (its
// keepers, `pins`) is given by the world, not worked out: the stations and the devices of its people (round three's
// holders, xena's too). A keeper takes a body only where it keeps a `ws` entry of that hash whose tag is the body's
// workspace's in that log, and the body's shape is one D1 names (the log cannot check it: it sees only the hash). A
// statement is in force where its entry is on the active chain and its body is kept; `roster` (round three's grounded
// labelling) is given exactly those, as round three's plaintext entries, so the list is round three's code.
//
// Faults: round three's, and bodies on their own (`holdBack`: one body never given to one keeper by anyone).
import { createHash } from "node:crypto";
import { isMainThread, parentPort, workerData } from "node:worker_threads";
import { type Entry, type LockState, WEB_DEVICE_SECS, apply, canonical, fold, genesis as lockGenesis, sigValid, signatureOk, signer as lockSigner } from "../src/cloud/lock.ts";
import { Keeper, type LogRules, type Variant, hashOf, isRemoval, signed, weight } from "./lock-fork-choice-model.ts";
import {
  ACCOMPLICE, type Dev3, type Family, Holder, type Job3, type Make3, type PersonState, PersonRules, type Roster, type Step, V3, type V3v, World3, type World3Options,
  drawSteps3, nameOfKey, personDevice, roster, runJob3, spec, stationKeys3,
} from "./lock-roster-model.ts";
import { type Key, Rng, WS, key } from "./lock-world-sim.ts";

const HEX32 = /^[0-9a-f]{64}$/;
const SALT = /^[0-9a-f]{32}$/;
/// D1 as revised (2026-11-13): the product's four roles; a viewer is given and taken out as a member is, managing nothing.
const ROLES = new Set(["owner", "admin", "member", "viewer"]);
/// D2 as revised: how far ahead of a keeper's clock a web device's `at` may be and still count.
export const SKEW = 600;
/// The second workspace (M3): alice owns it too; mallory is its member; its own two stations.
export const WS2 = "01HWORLDWORLDWORLDWORLDWO2";
const w2Keys = [0, 1].map((i) => key(3950 + i));
/// A web device's base key a person (D2), and one a revoked key puts on.
const webKey = (sub: string) => key(4200 + ["alice", "bob", "dan", "carol", "xena", "mallory"].indexOf(sub));
const ROGUE_WEB = key(4300);
export const SETTINGS = { origins: ["https://app.still.fail"], rp_id: "app.still.fail", cloud_keys: { keys: [] } };
/// What the root's `open` says: the settings and the root's person's email (D3 as revised: no admit names the root).
export const OPEN = { ...SETTINGS, email: "alice@x" };
/// How a log's statements of a workspace count (D1): `whole` (the default, the lead's choice of 2026-11-13, below);
/// `prev`, the revised rule as first said (a statement stands on the chain of
/// bodies its signer held, named by `prev`); `all`, the first revision (every earlier statement of the tag in the log);
/// `off`, the first reading (each by itself); `whole`, `prev` with the signer naming the latest statement whose body
/// and whole `prev` chain it holds (the model's: with `prev` as said, a device that got a body signed knowing a lost one
/// points through the loss).
export type Order = "prev" | "whole" | "all" | "off";
const byPrev = (o: Order | undefined) => o === undefined || o === "prev" || o === "whole";
const DAY = 86400;

const sha = (s: string) => createHash("sha256").update(s).digest("hex");
const tags = new Map<string, string>();
/// D1's tag: the same for every statement of `ws` in the log of genesis `g`.
export const tagOf = (ws: string, g: string): string => {
  const k = `${ws}|${g}`;
  let t = tags.get(k);
  if (t === undefined) tags.set(k, (t = sha(`stillfail/ws-tag/1\n${ws}\n${g}`)));
  return t;
};
export const bodyHash = (b: unknown): string => sha(canonical(b));
export type Body = { ws: string; kind: string; salt: string; [k: string]: any };
const stName = (hex: unknown) => {
  const i = stationKeys3.findIndex((k) => k.hex === hex);
  return i >= 0 ? `s${i}` : `w${w2Keys.findIndex((k) => k.hex === hex)}`;
};

/// Why a body is not one D1 names, or null. Every body names the statement of its workspace before it in its log
/// (`prev`: that one's `h`, null for the first: D1 as revised).
export function bodyWhy(b: any): string | null {
  if (b === null || typeof b !== "object" || typeof b.ws !== "string" || typeof b.salt !== "string" || !SALT.test(b.salt)) return "a body is {ws, kind, …, salt}";
  if (!("prev" in b) || !(b.prev === null || (typeof b.prev === "string" && HEX32.test(b.prev)))) return "a body names the statement before it";
  const keys = Object.keys(b).filter((k) => k !== "prev").sort().join(",");
  const hexes = (x: unknown) => Array.isArray(x) && x.every((c) => typeof c === "string" && HEX32.test(c));
  switch (b.kind) {
    case "member": return keys === "email,kind,lock,role,salt,sub,ws" && typeof b.sub === "string" && typeof b.email === "string" && HEX32.test(b.lock) && ROLES.has(b.role) ? null : "an admit names a person, their email, a lock and a role";
    case "member.remove": return keys === "cancels,kind,salt,sub,ws" && typeof b.sub === "string" && hexes(b.cancels) ? null : "a removal names whom and what it cancels";
    case "station": return keys === "key,kind,salt,ws" && HEX32.test(b.key) ? null : "a station is named by its key";
    case "station.remove": return keys === "cancels,key,kind,salt,ws" && HEX32.test(b.key) && hexes(b.cancels) ? null : "a removal names whom and what it cancels";
    case "open": return keys === "cloud_keys,email,kind,origins,rp_id,salt,ws" && typeof b.email === "string" && Array.isArray(b.origins) && b.origins.every((o: unknown) => typeof o === "string") && typeof b.rp_id === "string" ? null : "open names the settings";
    case "off": return keys === "kind,salt,ws" ? null : "off says nothing more";
    case "bind": return keys === "key,kind,salt,sig,ws" && typeof b.key === "string" && b.key !== "" && typeof b.sig === "string" && /^[0-9a-f]{128}$/.test(b.sig) ? null : "a binding names the signer that proves it and its signature";
    default: return "no such statement";
  }
}

// ── D6's binding (the lead's, 2026-11-14) ──────────────────────────────────────────────────────────────────────────

/// What signs a binding: a tag no other form a device's signer signs shares (rules/src/lock/roster.mbt `bind_tag`).
export const BIND_TAG = "stillfail-lock-bind/1";
/// What a binding's signer signs after the tag and a NUL: the SHA-256 of this form's canonical text.
export const bindForm = (ws: string, sub: string, log: string, moved: string) => ({ kind: "bind", log, moved, sub, ws });
export const bindBytes = (ws: string, sub: string, log: string, moved: string): Buffer =>
  Buffer.concat([Buffer.from(`${BIND_TAG}\0`), createHash("sha256").update(canonical(bindForm(ws, sub, log, moved))).digest()]);
/// Whether `sig` (hex) is `key`'s proof that log `log` is `sub`'s in `ws` after the move `moved`.
export const bindValid = (key: string, sig: string, ws: string, sub: string, log: string, moved: string): boolean => {
  try {
    return signatureOk(key, Buffer.from(sig, "hex"), bindBytes(ws, sub, log, moved));
  } catch {
    return false;
  }
};

// ── a person log with D1's and D2's kinds ───────────────────────────────────────────────────────────────────────────

/// Why one of the model's new kinds does not follow `ps`; the round-three checks of place, time and signer, then the
/// body's shape and the signature.
function refusal4(ps: PersonState, e: Entry, h: string): string | null {
  if (e.v !== 1 || e.ws !== `person:${ps.sub}`) return "an entry of another lock";
  if (!Number.isSafeInteger(e.at)) return "at is unix seconds";
  if (e.seq !== ps.seq + 1) return "the entry does not follow this lock's head";
  if (!ps.devices.has(String(e.sig?.key))) return "not signed by a device on the lock";
  const b = e.body as Record<string, unknown> | null;
  const keys = b && typeof b === "object" ? Object.keys(b).sort().join(",") : "";
  if (e.kind === "ws" && !(keys === "h,t" && HEX32.test(String(b!.t)) && HEX32.test(String(b!.h)))) return "a statement is {t, h}";
  if (e.kind === "web") {
    if (!(keys === "exp,id,label" && HEX32.test(String(b!.id)) && typeof b!.label === "string" && Number.isSafeInteger(b!.exp))) return "a web device is {id, label, exp}";
    // (the only bound is the entry's own `at`: what the signer says the time is)
    if ((b!.exp as number) > e.at + WEB_DEVICE_SECS) return "a web device lasts 31 days at most";
  }
  if (e.kind === "web.remove" && !(keys === "id" && HEX32.test(String(b!.id)))) return "a web device is taken off by its id";
  if (!sigValid(e.sig, h, [], "", false)) return "signature invalid";
  return null;
}

/// Round three's person-log rules with `ws`, `web` and `web.remove`; round three's statements in the clear refused.
export class PersonRules4 extends PersonRules {
  why(e: Entry): string | null {
    if (e.kind.startsWith("ws.")) return "a statement of a workspace is a commitment (D1)";
    if (e.kind !== "ws" && e.kind !== "web" && e.kind !== "web.remove") return super.why(e);
    const h = hashOf(e);
    const id = `${h}|${e.sig.key}|${e.sig.sig}`;
    if (this.verdicts.has(id)) return this.verdicts.get(id)!;
    const ps = e.prev === null ? undefined : this.states.get(e.prev);
    const out = ps === undefined ? "the entry does not follow this lock's head" : refusal4(ps, e, h);
    if (out === null && !this.states.has(h)) {
      this.states.set(h, { sub: ps!.sub, seq: e.seq, devices: ps!.devices });
      this.depths.set(h, this.depth(e.prev!) + 1);
    }
    this.verdicts.set(id, out);
    return out;
  }
}

// ── the old chain (D5): the product's rules, and `moved` ────────────────────────────────────────────────────────────

/// The first rounds' fork choice as the product now goes by it (log-keep.ts): one vote a device, a device's removal.
export const OLD_V: Variant = { votes: "flat", removal: "device", offers: "active", resign: "off", hashfield: "as-is", tie: "signer" };

/// A workspace's own chain by the product's `apply`, and `moved {root}`, the model's: signed by an own app device of an
/// owner, as the chain's rules let an owner sign; nothing follows it.
export class OldRules implements LogRules<LockState> {
  readonly g: Entry;
  readonly gh: string;
  states = new Map<string, LockState>();
  depths = new Map<string, number>();
  verdicts = new Map<string, boolean>();
  /// Each `moved`, by its hash: the root it names.
  moved = new Map<string, string>();
  constructor(g: Entry) {
    this.g = g;
    this.gh = hashOf(g);
    this.states.set(this.gh, lockGenesis(g));
    this.depths.set(this.gh, 0);
  }
  parentOf(e: Entry) {
    return e.prev;
  }
  isCheckpoint() {
    return false;
  }
  depth(h: string) {
    return this.depths.get(h)!;
  }
  valid(e: Entry): boolean {
    const h = hashOf(e), id = `${h}|${e.sig.sig}`;
    const known = this.verdicts.get(id);
    if (known !== undefined) return known;
    const ps = e.prev === null ? undefined : this.states.get(e.prev);
    let ok = false;
    if (ps !== undefined && !this.moved.has(e.prev!)) {
      if (e.kind === "moved") {
        const by = lockSigner(ps, e.sig, null);
        const b = e.body as Record<string, unknown> | null;
        ok = e.v === 1 && e.ws === ps.ws && e.seq === ps.seq + 1 && e.prev === ps.head && Number.isSafeInteger(e.at) && !ps.disabled && by !== null && by.role === "owner" && by.own && !by.passkey &&
          b !== null && Object.keys(b).join() === "root" && HEX32.test(String(b.root)) && sigValid(e.sig, h, ps.origins, ps.rp_id, false);
        if (ok) this.states.set(h, ps), this.moved.set(h, String(b!.root));
      } else {
        try {
          this.states.set(h, apply(ps, e, null));
          ok = true;
        } catch {
          ok = false;
        }
      }
      if (ok) this.depths.set(h, this.depth(e.prev!) + 1);
    }
    this.verdicts.set(id, ok);
    return ok;
  }
  state(h: string) {
    return this.states.get(h)!;
  }
  weight(ps: LockState, e: Entry) {
    return weight(ps, e, OLD_V);
  }
  removal(ps: LockState, e: Entry) {
    return isRemoval(ps, e, OLD_V);
  }
}

/// D6: the chain a workspace that had none of its own moved from in this model's worlds without an old chain (the
/// station's and the core's checks pin it): a genesis whose owner is alice with her app and no settings, and its
/// `moved {root}`, signed by her app.
const bare = new Map<string, Entry[]>();
export function bareChain(ws: string, root: string): Entry[] {
  const id = `${ws}|${root}`;
  const had = bare.get(id);
  if (had) return had;
  const app = spec("alice's app");
  const g = signed({ v: 1, ws, seq: 0, prev: null, at: 1000, kind: "genesis", body: {
    owner: "alice", origins: [], rp_id: "", cloud_keys: { keys: [] }, members: [{ sub: "alice", email: "alice@x", role: "owner" }],
    devices: [{ id: app.base.hex, sub: "alice", kind: "app", label: app.name, sign_key: app.signer.id }], passkeys: [], stations: [], gateways: [],
  } }, app.signer);
  const out = [g, signed({ v: 1, ws, seq: 1, prev: hashOf(g), at: 1000, kind: "moved", body: { root } }, app.signer)];
  bare.set(id, out);
  return out;
}

// ── D4: one state ───────────────────────────────────────────────────────────────────────────────────────────────────

export type D4Member = { role: string; email: string; lock: string; apps: string[]; webs: string[] };
export type D4 = { on: string; settings: string; members: Map<string, D4Member>; stations: string[] };
export const d4Said = (d: D4 | string): string => {
  if (typeof d === "string") return d;
  const ms = [...d.members].sort(([a], [b]) => (a < b ? -1 : 1)).map(([sub, m]) => `${sub} ${m.role} #${m.lock.slice(0, 6)} {${m.apps.map(nameOfKey).join(",")}} web{${m.webs.map((x) => x.slice(0, 4)).join(",")}}`);
  return `${d.on} ${d.settings} [${ms.join("; ")}] stations ${d.stations.map(stName).join(",")}`;
};
/// What differs between two states, field by field.
export function d4Diff(a: D4 | string, b: D4 | string): string[] {
  if (typeof a === "string" || typeof b === "string") return d4Said(a) === d4Said(b) ? [] : [`state: ${typeof a === "string" ? a : "on"} / ${typeof b === "string" ? b : "on"}`];
  const out: string[] = [];
  if (a.on !== b.on) out.push("on");
  if (a.settings !== b.settings) out.push("settings");
  if (a.stations.join() !== b.stations.join()) out.push("stations");
  for (const sub of new Set([...a.members.keys(), ...b.members.keys()])) {
    const x = a.members.get(sub), y = b.members.get(sub);
    if (!x || !y) out.push(`member ${sub}`);
    else {
      if (x.role !== y.role) out.push(`role ${sub}`);
      if (x.email !== y.email) out.push(`email ${sub}`);
      if (x.lock !== y.lock) out.push(`log ${sub}`);
      if (x.apps.join() !== y.apps.join()) out.push(`apps ${sub}`);
      if (x.webs.join() !== y.webs.join()) out.push(`web ${sub}`);
    }
  }
  return out;
}

/// The old chain's state as D4 has it (members by the person log each bound, the root's owner by the root).
export function d4Old(s: LockState, root: string, now: number): D4 {
  const members = new Map<string, D4Member>();
  for (const [sub, m] of s.members) {
    const devs = [...s.devices.values()].filter((d) => d.sub === sub);
    members.set(sub, {
      role: m.role, email: m.email, lock: sub === "alice" ? root : s.persons.get(sub) ?? "none",
      apps: devs.filter((d) => d.kind === "app" && d.sign_key).map((d) => d.sign_key!).sort(),
      webs: devs.filter((d) => d.kind === "web" && (d.exp ?? 0) > now).map((d) => d.id).sort(),
    });
  }
  return { on: s.disabled ? "off" : "on", settings: canonical({ origins: s.origins, rp_id: s.rp_id, cloud_keys: s.cloud_keys }), members, stations: [...s.stations.keys()].sort() };
}

// ── the world ───────────────────────────────────────────────────────────────────────────────────────────────────────

export type W4Options = World3Options & {
  /// M3: a second workspace (alice's, with mallory and two stations of its own); whether each workspace's statements
  /// are made at all (the runs the other is compared with).
  two?: boolean;
  w1?: boolean;
  w2?: boolean;
  /// M1: the `nth` body made after the setup is never given to station `station` (by anyone).
  holdBack?: { station: number; nth: number };
  /// The first readings, kept beside the revised design (2026-11-13) to compare: `order` (`Order`); `gate: false`, every keeper of the world is given every body; `offFinal`, a
  /// keeper that sees the workspace off lets it go for good; `webAt`, a web device counts by its `at` alone.
  order?: Order;
  gate?: boolean;
  offFinal?: boolean;
  webAt?: boolean;
  /// Defaults (2026-11-13, after M6 was chased): `cancels=h`, `again=batch`; round three's readings beside them.
  /// `tellOut` (default on, the lead's of 2026-11-13): the body of a statement that takes someone out is given also to
  /// those the giver's state listed before it counted (off: nobody is told). `cancels`: what a removal names, the log
  /// entries' hashes (`entry`, round three's) or the statements' bodies' (`h`), which signing again does not change.
  tellOut?: boolean;
  cancels?: "entry" | "h";
  /// When a device signs again an entry of its that lost its place: `since` (the default), the product's `againOf`
  /// (client/core-ts/src/lock-keep.ts: not where the chain since the place it hung already says it, or says otherwise
  /// about the same subject); `any`, round three's model (not where any entry of the same kind and body is on the chain,
  /// so a statement made again after its opposite, lost, is not signed again).
  /// `batch`: as `since`, each lost entry decided against the chain as it was before the device signed any of them again
  /// (with `since`, its own signing again of a removal makes the add it had signed after it read as said otherwise).
  again?: "since" | "any" | "batch";
  /// M1: when each statement first was ready at a keeper (on the active chain, its body kept) and first in force.
  track?: boolean;
  /// D6 (the lead's, 2026-11-14; on by default): once a chain moved, what the logs have not said yet of someone the
  /// chain named, the chain as it moved still says (`carriedOf`). Off: the state is the logs' alone, as D5 had it.
  carry?: boolean;
};

/// What a world of this round keeps beside round three's (made when first asked: round three's constructor already
/// calls the methods this round overrides).
type X = {
  o: W4Options;
  /// Every body made, by its hash; their hashes in the order made; how many the setup made.
  bodies: Map<string, Body>;
  order: string[];
  base: number;
  kept: Map<Holder, Map<string, Body>>;
  /// The workspaces each keeper keeps, and the root it goes by (null: none yet, a chain not moved).
  pins: Map<Holder, Map<string, string | null>>;
  /// The person logs a keeper keeps, where not every one (the second workspace's stations).
  allowed: Map<Holder, Set<string>>;
  /// `<body hash>><keeper>`: never given to it.
  withheld: Set<string>;
  skew: Map<Holder, number>;
  /// Bodies a keeper did not take, by why (from messages and M2's offers, not from levelling).
  refused: Record<string, number>;
  commits: Map<Holder, { ver: number; by: Map<string, Entry[]> }>;
  gates: Map<Holder, { ver: number; ws: string; keys: Set<string> }>;
  before: Map<string, Set<string>>;
  ready: Map<string, number>;
  inAt: Map<string, number>;
  letGo: { at: string; ws: string; step: number }[];
  /// D5: each keeper's copy of the old chain, its rules, the reading of "takes nothing more" (B: the root follows the
  /// fork choice; A: the first `moved` a keeper had on its active chain is kept for good) and what A froze.
  old: Map<Holder, Keeper<LockState>>;
  oldRules: OldRules | null;
  reading: "A" | "B";
  frozen: Map<Holder, string>;
  /// The bodies each key signed: its device holds them from the signing on (a body is the signer's before any keeper's).
  mine: Map<string, Set<string>>;
  /// The next statement made names this `prev`, whatever its signer holds (a signer leaving its own out on purpose).
  forcePrev: string | null | undefined;
  /// The body a device signs again: the same, where its `prev` is still a statement before it in the log (D1: a body
  /// does not change when its entry is signed again).
  reuse: Body | undefined;
};
const XS = new WeakMap<World3, X>();
/// What holds the rules to this model (rules-fork-check.ts) looks at: where set, called with the world at the points
/// of the scripted worlds below that it names, and the bodies offered there that no keeper keeps (M2). Unset, nothing.
export const look4: { at: ((w: World4, where: string, offered?: Body[]) => void) | null } = { at: null };
/// The options of the world being made: round three's constructor makes the setup before a subclass's constructor can
/// keep them.
let making: W4Options = {};

export class World4 extends World3 {
  get x(): X {
    let x = XS.get(this);
    if (x === undefined) {
      x = { o: making, mine: new Map(), bodies: new Map(), order: [], base: -1, kept: new Map(), pins: new Map(), allowed: new Map(), withheld: new Set(), skew: new Map(), refused: {}, commits: new Map(), gates: new Map(), before: new Map(), ready: new Map(), inAt: new Map(), letGo: [], old: new Map(), oldRules: null, reading: "B", frozen: new Map(), forcePrev: undefined, reuse: undefined };
      XS.set(this, x);
    }
    return x;
  }

  constructor(seed: number, v: V3v, family: Family = "free", o: W4Options = {}) {
    making = o;
    super(seed, v, family, { ...o, bare: o.bare || o.w1 === false });
    making = {};
    const x = this.x;
    x.o = o;
    if (o.bare) {
      for (const h of this.holders) x.pins.set(h, new Map<string, string | null>([[WS, null]]));
    } else if (o.w1 !== false) {
      // Round three gave its setup to everyone: the bodies too, to those alice's app's state lets in (D1 as revised).
      // Then alice's app opens the workspace (D3).
      const A = this.dev("alice's app");
      for (const h of this.holders) if (this.admits(A.h, h, WS)) this.giveBodies(h, [...x.bodies.values()]);
      this.setup(A, [["ws.open", { ws: WS, ...OPEN }]], this.holders);
    }
    if (o.two) this.second();
    x.base = x.order.length;
  }

  /// Statements of the setup: made after the head of `d`'s log and given, with their bodies, to `to` (no intent: what
  /// the drawn worlds count is what happens after).
  setup(d: Dev3, says: [string, unknown][], to: Holder[]) {
    const out: Entry[] = [];
    for (const [kind, body] of says) {
      const e = this.make(this.entry(d.h.logs.get(d.log)!.head()), kind, body, d.signer);
      out.push(e);
      this.known.add(hashOf(e));
      this.receive(d.h, [e]);
    }
    for (const h of to) {
      this.receive(h, out);
      for (const ws of new Set(out.filter((e) => e.kind === "ws").map((e) => this.x.bodies.get(e.body.h)!.ws))) {
        if (this.admits(d.h, h, ws)) this.giveBodies(h, [...this.keptOf(d.h).values()].filter((b) => b.ws === ws));
      }
    }
  }

  /// M3's second workspace: its stations keep alice's and mallory's logs only; alice's devices keep both workspaces.
  second() {
    const x = this.x;
    const ws2 = w2Keys.map((_, i) => new Holder(`w${i}`, this));
    const mal = this.entry(this.home.get("mallory")!);
    const logs = new Set([this.root, this.home.get("mallory")!]);
    for (const h of ws2) {
      this.stations.push(h), this.holders.push(h);
      this.letIn.set(h, new Map()), this.awayNow.set(h, new Set());
      x.allowed.set(h, logs);
      x.pins.set(h, new Map<string, string | null>([[WS2, this.root]]));
      this.receive(h, this.chainTo(this.dev("alice's app").h.logs.get(this.root)!.head()));
      this.receive(h, [mal]);
    }
    const alices = this.devs.filter((d) => d.sub === "alice");
    for (const d of alices) this.pinsOf(d.h).set(WS2, this.root), this.receive(d.h, [mal]);
    if (x.o.w2 === false) return;
    this.setup(this.dev("alice's app"), [
      ["ws.open", { ws: WS2, ...OPEN }],
      ["ws.member", { ws: WS2, sub: "mallory", lock: this.home.get("mallory"), role: "member" }],
      ...w2Keys.map((k) => ["ws.station", { ws: WS2, key: k.hex }] as [string, unknown]),
    ], [...ws2, ...alices.map((d) => d.h)]);
  }

  rulesFor(g: Entry): PersonRules {
    return new PersonRules4(g);
  }

  /// Round three's statements are made as D1's: the entry `ws {t, h}`, the body kept by the world (and by the device,
  /// which brings them together). The salt is drawn from what the entry is made of (the model needs no secrecy from
  /// itself, only bodies that differ).
  make(parent: Entry, kind: string, body: unknown, by: Key, at?: number): Entry {
    if (!kind.startsWith("ws.")) return super.make(parent, kind, body, by, at);
    const g = this.logOf.get(hashOf(parent))!;
    const { ws, ...rest } = body as { ws: string; sub?: string; email?: string };
    const salt = sha(`salt\n${hashOf(parent)}\n${by.id}\n${kind}\n${canonical(body)}`).slice(0, 32);
    const t = tagOf(ws, g);
    // `prev`: the latest statement of the tag before it in the log, under `prev` the latest whose body the signing
    // device holds (a key no device of the world holds, a forger's, names the latest)
    const holder = byPrev(this.x.o.order) ? this.devs?.find((d) => d.signer.id === by.id)?.h : undefined;
    const kept = holder ? this.keptOf(holder) : undefined, mine = this.x.mine.get(by.id);
    const held = kept && { has: (hb: string) => kept.has(hb) || mine?.has(hb) === true, get: (hb: string) => kept.get(hb) ?? (mine?.has(hb) ? this.x.bodies.get(hb) : undefined) };
    const whole = (hb: string) => {
      for (let p: string | null = hb, n = 0; p !== null && n < 10_000; n++) {
        const q = held!.get(p);
        if (q === undefined) return false;
        p = q.prev;
      }
      return true;
    };
    let prev: string | null = null;
    for (let y: Entry = parent; y.prev !== null; y = this.entry(y.prev)) {
      if (y.kind === "ws" && y.body.t === t && (held === undefined || ((this.x.o.order ?? "whole") === "whole" ? whole(y.body.h) : held.has(y.body.h)))) {
        prev = y.body.h;
        break;
      }
    }
    if (this.x.forcePrev !== undefined) (prev = this.x.forcePrev), (this.x.forcePrev = undefined);
    const reuse = this.x.reuse;
    this.x.reuse = undefined;
    if (reuse && reuse.ws === ws && reuse.kind === kind.slice(3)) {
      let ok = reuse.prev === null;
      for (let y: Entry = parent; !ok && y.prev !== null; y = this.entry(y.prev)) ok = y.kind === "ws" && y.body.t === t && y.body.h === reuse.prev;
      if (ok) return super.make(parent, "ws", { t, h: bodyHash(reuse) }, by, at);
    }
    if (kind === "ws.member" && rest.email === undefined) rest.email = `${rest.sub}@x`;
    // (`cancels=h`: a removal names the statements' bodies, whatever entry its signer saw them in)
    const rc = rest as { cancels?: string[] };
    if ((this.x.o.cancels ?? "h") === "h" && Array.isArray(rc.cancels)) rc.cancels = [...new Set(rc.cancels.map((c) => (this.all.get(c)?.kind === "ws" ? (this.all.get(c)!.body.h as string) : c)))].sort();
    const b: Body = { ws, kind: kind.slice(3), ...rest, prev, salt };
    const hb = bodyHash(b);
    const x = this.x;
    if (!x.mine.has(by.id)) x.mine.set(by.id, new Set());
    x.mine.get(by.id)!.add(hb);
    if (!x.bodies.has(hb)) {
      x.bodies.set(hb, b);
      x.order.push(hb);
      const hold = x.o.holdBack;
      if (hold && x.base >= 0 && x.order.length === x.base + hold.nth) x.withheld.add(`${hb}>s${hold.station}`);
    }
    return super.make(parent, "ws", { t, h: hb }, by, at);
  }

  said(e: Entry): string {
    if (e.kind !== "ws" && e.kind !== "web" && e.kind !== "web.remove") return super.said(e);
    const b = e.kind === "ws" ? this.x.bodies.get(e.body.h) : e.body;
    const what = e.kind === "web" ? `web ${String(b.id).slice(0, 4)} for ${Math.round((b.exp - e.at) / DAY)} days`
      : e.kind === "web.remove" ? `web.remove ${String(b.id).slice(0, 4)}`
      : b === undefined ? "a statement no one has the body of"
      : `${b.ws === WS2 ? "W2 " : ""}${b.kind === "member" ? `member ${b.sub} ${b.role} by #${String(b.lock).slice(0, 6)}` : b.kind === "member.remove" ? `member.remove ${b.sub} cancelling ${b.cancels.length}` : b.kind.startsWith("station") ? `${b.kind} ${stName(b.key)}` : b.kind}`;
    return `${e.ws.slice(7)}'s log ${e.seq} ${nameOfKey(e.sig.key)}: ${what} #${hashOf(e).slice(0, 6)}`;
  }

  // ── keepers and bodies ─────────────────────────────────────────────────────────────────────────────────────────

  pinsOf(h: Holder): Map<string, string | null> {
    let p = this.x.pins.get(h);
    if (p === undefined) this.x.pins.set(h, (p = new Map<string, string | null>([[WS, this.root]])));
    return p;
  }
  keptOf(h: Holder): Map<string, Body> {
    let k = this.x.kept.get(h);
    if (k === undefined) this.x.kept.set(h, (k = new Map()));
    return k;
  }
  clock(h: Holder): number {
    return this.t + (this.x.skew.get(h) ?? 0);
  }
  private allowedFor(h: Holder, e: Entry): boolean {
    const a = this.x.allowed.get(h);
    return a === undefined || a.has(this.logOf.get(hashOf(e)) ?? "");
  }
  /// The `ws` entries a keeper stores, by their `h`.
  private commitsOf(h: Holder): Map<string, Entry[]> {
    const c = this.x.commits.get(h);
    if (c && c.ver === h.ver) return c.by;
    const by = new Map<string, Entry[]>();
    for (const e of h.stored()) if (e.kind === "ws") by.set(e.body.h, [...(by.get(e.body.h) ?? []), e]);
    this.x.commits.set(h, { ver: h.ver, by });
    return by;
  }
  /// The `h` of every statement of the same tag before `e` in its log.
  earlier(e: Entry): Set<string> {
    const out = new Set<string>();
    for (let y = e.prev; y !== null; ) {
      const p = this.entry(y);
      if (p.kind === "ws" && p.body.t === e.body.t) out.add(p.body.h);
      y = p.prev;
    }
    return out;
  }
  /// The `h` of the statement of the same tag before `e` in its log (null: none).
  prevOf(e: Entry): string | null {
    for (let y = e.prev; y !== null; ) {
      const p = this.entry(y);
      if (p.kind === "ws" && p.body.t === e.body.t) return p.body.h;
      y = p.prev;
    }
    return null;
  }
  /// Whether `from`'s own state lets `to` be given the bodies of `ws` (D1 as revised): a station of it, or a device on
  /// the log a member is bound by. Before a chain moved (D5: no root yet), every keeper of the old chain.
  admits(from: Holder, to: Holder, ws: string): boolean {
    if (this.x.o.gate === false) return true;
    const root = this.pinsOf(from).get(ws);
    if (root === null) return true;
    if (root === undefined) return false;
    let g = this.x.gates.get(from);
    if (!g || g.ver !== from.ver || g.ws !== ws) {
      const r = this.rosterOf(from, ws);
      g = { ver: from.ver, ws, keys: new Set([...r.stations, ...r.letIn.keys()]) };
      this.x.gates.set(from, g);
    }
    return g.keys.has(this.keyOfHolder(to));
  }
  /// Whether `from`'s state lists `to` with statement `b` left out (whom a removal takes out learns of it).
  admitsBefore(from: Holder, to: Holder, b: Body): boolean {
    const root = this.pinsOf(from).get(b.ws);
    if (!root) return false;
    // (every removal of the same one left out: told of a second removal too)
    const subject = b.kind === "member.remove" ? `m|${b.sub}` : `s|${b.key}`;
    const id = `${from.name}|${from.ver}|${b.ws}|${subject}`;
    const same = (x: Body) => (x.kind === "member.remove" && `m|${x.sub}` === subject) || (x.kind === "station.remove" && `s|${x.key}` === subject);
    let keys = this.x.before.get(id);
    if (keys === undefined) {
      const f = this.inForce(from, b.ws);
      const left = new Map([...f.stmts].filter(([, x]) => !same(x)));
      keys = new Set<string>();
      if (left.size < f.stmts.size) {
        const r = this.rosterIn(from, root, b.ws, { stmts: left });
        keys = new Set([...r.stations, ...r.letIn.keys()]);
      }
      if (this.x.before.size > 5000) this.x.before.clear();
      this.x.before.set(id, keys);
    }
    return keys.has(this.keyOfHolder(to));
  }
  keyOfHolder(h: Holder): string {
    const d = this.devOf.get(h);
    if (d) return d.signer.id;
    const i = Number(h.name.slice(1));
    return (h.name.startsWith("w") ? w2Keys : stationKeys3)[i]?.hex ?? "";
  }
  /// Why `h` does not take body `b` (D1), or null.
  bodyRefusal(h: Holder, b: Body): string | null {
    if (typeof b?.ws !== "string" || !this.pinsOf(h).has(b.ws)) return "it names no workspace this keeper keeps";
    const es = this.commitsOf(h).get(bodyHash(b));
    if (es === undefined) return "no entry it keeps commits to it";
    const mine = es.filter((e) => e.body.t === tagOf(b.ws, this.logOf.get(hashOf(e))!));
    if (mine.length === 0) return "its entry's tag is not its workspace's in that log";
    const shape = bodyWhy(b);
    if (shape !== null) return `its shape: ${shape}`;
    // (under `prev` any earlier statement of the tag in the entry's log, or none; its body need not be here yet)
    const prevOk = byPrev(this.x.o.order) ? (e: Entry) => b.prev === null || this.earlier(e).has(b.prev) : (e: Entry) => this.prevOf(e) === b.prev;
    if (!mine.some(prevOk)) return "its prev is not a statement before it in that log";
    return null;
  }
  takeBody(h: Holder, b: Body, count: boolean): boolean {
    const hb = bodyHash(b), kept = this.keptOf(h);
    if (kept.has(hb)) return false;
    const why = this.bodyRefusal(h, b);
    if (why !== null) {
      if (count) this.x.refused[why] = (this.x.refused[why] ?? 0) + 1;
      return false;
    }
    kept.set(hb, b);
    return true;
  }
  giveBodies(h: Holder, bs: Body[], count = false): boolean {
    let any = false;
    for (const b of bs) if (this.takeBody(h, b, count)) any = true;
    if (any) h.ver++, this.refresh(h, new Set());
    return any;
  }
  /// What `from` gives `to` of the bodies of the workspaces both keep.
  bodiesFor(from: Holder, to: Holder): Body[] {
    const pf = this.pinsOf(from), pt = this.pinsOf(to), have = this.keptOf(to), out: Body[] = [];
    const ok = new Map<string, boolean>();
    for (const [hb, b] of this.keptOf(from)) {
      if (!pf.has(b.ws) || !pt.has(b.ws) || have.has(hb) || this.x.withheld.has(`${hb}>${to.name}`)) continue;
      if (!ok.has(b.ws)) ok.set(b.ws, this.admits(from, to, b.ws));
      if (ok.get(b.ws)) out.push(b);
      else if (this.x.o.tellOut !== false && (b.kind === "member.remove" || b.kind === "station.remove") && this.admitsBefore(from, to, b)) {
        // the removal, and the bodies its `prev` chain names (without them it is not in force there)
        out.push(b);
        for (let p = b.prev, n = 0; p !== null && n < 10_000; n++) {
          const q = this.keptOf(from).get(p);
          if (q === undefined) break;
          if (!have.has(p)) out.push(q);
          p = q.prev;
        }
      }
    }
    return out;
  }

  /// A keeper takes entries (of the logs it keeps); a device the bodies of what it signed, and whoever a revoked key
  /// reaches the bodies it brings.
  receive(h: Holder, es: Entry[]) {
    const ok = es.filter((e) => this.allowedFor(h, e));
    const { changed, any } = h.take(ok);
    const own = this.devOf.get(h)?.signer.id;
    let got = false;
    for (const e of ok) {
      if (e.kind !== "ws" || !(e.sig.key === own || this.attack.has(hashOf(e)))) continue;
      const b = this.x.bodies.get(e.body.h);
      if (b && this.takeBody(h, b, true)) got = true;
    }
    if (got) h.ver++;
    if (any || got) this.refresh(h, changed);
  }
  offer(from: Holder, to: Holder): Entry[] {
    return super.offer(from, to).filter((e) => this.allowedFor(to, e));
  }
  send(from: Holder, to: Holder) {
    super.send(from, to);
    const bodies = this.bodiesFor(from, to);
    if (bodies.length === 0) return;
    const m = { to, entries: [], bodies };
    this.queue.push(m);
    this.sent.push(m);
  }
  land(i: number) {
    const m = this.queue[i];
    if (m.bodies === undefined) return super.land(i);
    this.queue.splice(i, 1);
    this.giveBodies(m.to, m.bodies as Body[], true);
  }
  level(skip: Set<Holder> = new Set(), rounds = 200): boolean {
    for (let i = 0; i < 40; i++) {
      if (!super.level(skip, rounds)) return false;
      let moved = false;
      for (const a of this.holders) {
        if (skip.has(a)) continue;
        for (const b of this.holders) {
          if (a === b || skip.has(b)) continue;
          const bs = this.bodiesFor(a, b);
          if (bs.length > 0 && this.giveBodies(b, bs)) moved = true;
        }
      }
      if (!moved) return true;
    }
    return false;
  }

  /// What a statement or a device entry is about (the product's `subjectOf`), by its intent's kind and body.
  private about(kind: string, b: any): string | null {
    if (kind === "device" || kind === "device.remove") return `device ${b.key}`;
    if (kind.endsWith("member") || kind.endsWith("member.remove")) return `member ${b.ws}|${b.sub}`;
    if (kind.endsWith("station") || kind.endsWith("station.remove")) return `station ${b.ws}|${b.key}`;
    if (kind.endsWith("open") || kind.endsWith("off")) return `open ${b.ws}`;
    return null;
  }
  private aboutEntry(x: string): string | null {
    const e = this.entry(x);
    if (e.kind !== "ws") return this.about(e.kind, e.body);
    const b = this.x.bodies.get(e.body.h);
    return b ? this.about(b.kind, b) : null;
  }
  resign(d: Dev3) {
    if (this.x.o.again === "any") return super.resign(d);
    if (this.v.resign === "off" || d.compromised || this.resigning) return;
    this.resigning = true;
    try {
      const batch = (this.x.o.again ?? "batch") === "batch";
      const before = new Map([...d.h.logs].map(([g, k]) => [g, [...k.active]]));
      for (const h of [...d.mine]) {
        const k = d.h.logs.get(this.logOf.get(h)!)!;
        if (d.superseded.has(h) || k.on.has(h)) continue;
        const key = this.honest.get(h)!, it = this.intents.get(key)!;
        d.superseded.add(h);
        if (it.void !== null) continue;
        const chain = batch ? before.get(this.logOf.get(h)!)! : k.active, on = new Set(chain);
        let p = this.entry(h).prev;
        while (p !== null && !on.has(p)) p = this.entry(p).prev;
        if (p === null || p === chain.at(-1)) continue;
        const since = chain.slice(chain.indexOf(p) + 1);
        if (since.some((x) => this.honest.get(x) === key)) continue;
        const about = this.about(it.kind, it.body);
        if (about !== null && since.some((x) => this.aboutEntry(x) === about)) {
          it.void = "said otherwise since";
          this.note(`  ${d.name} does not sign ${this.told(h)} again: the chain says otherwise of it since`);
          continue;
        }
        const lostE = this.entry(h);
        if (lostE.kind === "ws") this.x.reuse = this.x.bodies.get(lostE.body.h);
        const again = this.sign(d, it.kind, it.body, { log: it.log, bring: true });
        this.x.reuse = undefined;
        if (typeof again === "string") {
          it.void = again;
          this.note(`  ${d.name} cannot sign ${this.told(h)} again after its head (${again}): marked not in effect`);
        } else this.resigned++;
      }
    } finally {
      this.resigning = false;
    }
  }

  /// D3 as revised: off is a state (`d4`), nothing is let go. `offFinal`, the first reading: a keeper that sees its
  /// workspace off lets go of it, its pin and every body of it. `track`: when each statement was first ready, first in force.
  refresh(h: Holder, changed: Set<Keeper<PersonState>>) {
    super.refresh(h, changed);
    const x = this.x;
    for (const [ws, root] of [...this.pinsOf(h)]) {
      if (root === null || !h.logs.has(root)) continue;
      const f = this.inForce(h, ws);
      if (x.o.track) {
        for (const y of f.ready) if (!x.ready.has(`${h.name}|${y}`)) x.ready.set(`${h.name}|${y}`, this.step);
        for (const y of f.stmts.keys()) if (!x.inAt.has(`${h.name}|${y}`)) x.inAt.set(`${h.name}|${y}`, this.step);
      }
      // (stations only: a device that let go of its own `off` as it signed it would never give it to anyone)
      if (x.o.offFinal && !this.devOf.has(h) && this.openOff(h, root, f).newest === "off") this.letGo(h, ws);
    }
  }
  letGo(h: Holder, ws: string) {
    this.pinsOf(h).delete(ws);
    const kept = this.keptOf(h);
    for (const [hb, b] of [...kept]) if (b.ws === ws) kept.delete(hb);
    this.x.letGo.push({ at: h.name, ws, step: this.step });
    h.ver++;
    this.note(`  ${h.name} sees ${ws === WS ? "the workspace" : "W2"} off and lets it go`);
  }
  /// The root's device gives a keeper the root again, as a station is first given a lock: its logs and its bodies.
  regive(from: Dev3, to: Holder, ws = WS) {
    this.pinsOf(to).set(ws, this.root);
    this.note(`  ${from.name} gives ${to.name} the root again`);
    this.receive(to, from.h.stored());
    this.giveBodies(to, [...this.keptOf(from.h).values()].filter((b) => b.ws === ws));
  }

  // ── the state ──────────────────────────────────────────────────────────────────────────────────────────────────

  /// The statements of `ws` in force at `h` (D1), by their entry's hash, and the entries of its tag whose body is not
  /// kept there (`lacking`). `all`: as if it kept every body the world made (the model's own check).
  /// D1 as revised: a statement counts where its body and every body along its `prev` chain are kept (`order`: `all`,
  /// only after every one of its tag before it on the active chain has its body kept; `off`, each by itself). `ready`:
  /// those on the active chain with their body.
  inForce(h: Holder, ws: string, all = false): { stmts: Map<string, Body>; lacking: string[]; ready: string[] } {
    const kept = this.keptOf(h), stmts = new Map<string, Body>(), lacking: string[] = [], ready: string[] = [];
    const order = this.x.o.order ?? "whole";
    const src = all ? this.x.bodies : kept;
    const whole = (b: Body): boolean => {
      for (let p = b.prev, n = 0; p !== null && n < 10_000; n++) {
        const q = src.get(p);
        if (q === undefined) return false;
        p = q.prev;
      }
      return true;
    };
    for (const [g, k] of h.logs) {
      const t = tagOf(ws, g);
      let stopped = false;
      for (const x of k.active) {
        const e = k.store.get(x)!;
        if (e.kind !== "ws" || e.body.t !== t) continue;
        const b = all ? this.x.bodies.get(e.body.h) : kept.get(e.body.h);
        const has = b !== undefined && b.ws === ws && (!all || bodyWhy(b) === null);
        if (!has) lacking.push(x), (stopped ||= order === "all");
        else {
          ready.push(x);
          if (!stopped && (!byPrev(order) || whole(b!))) stmts.set(x, b!);
        }
      }
    }
    return { stmts, lacking, ready };
  }
  /// The newest of `open`/`off` in force on the root's active chain, and the newest `open`'s settings (D3).
  openOff(h: Holder, root: string, f: { stmts: Map<string, Body> }): { newest: "open" | "off" | null; settings: Body | null } {
    let newest: "open" | "off" | null = null, settings: Body | null = null;
    for (const x of h.logs.get(root)?.active ?? []) {
      const b = f.stmts.get(x);
      if (b?.kind === "open") (newest = "open"), (settings = b);
      else if (b?.kind === "off") newest = "off";
    }
    return { newest, settings };
  }
  /// D6: the chain as it moved at `h`, for `ws`: the `moved` on its active old chain that names the root `h` goes by,
  /// and the chain's state at it (frozen: nothing follows a `moved`). Null where no chain moved there, or `carry` is off.
  /// A world with no old chain (D5's drawn worlds, M1-M6) stands for one that moved from the bare chain `bareChain`
  /// (alice its owner with her app, nothing else), as the station's and the core's checks give it them.
  carriedOf(h: Holder, ws = WS): { moved: string; s: LockState; chain: Entry[] } | null {
    const x = this.x;
    const root = this.pinsOf(h).get(ws);
    if (x.o.carry === false || !root) return null;
    if (ws !== WS || x.oldRules === null) {
      const chain = bareChain(ws, root);
      return { moved: hashOf(chain[1]), s: fold(chain, null), chain };
    }
    const k = x.old.get(h);
    if (k === undefined) return null;
    const at = k.active.findIndex((y) => x.oldRules!.moved.get(y) === root);
    return at < 0 ? null : { moved: k.active[at], s: x.oldRules.state(k.active[at]), chain: k.active.slice(0, at + 1).map((y) => k.store.get(y)!) };
  }
  /// D6's statements of the chain as it moved: one admit by the root's person of each member it names but the root's
  /// person (`~<moved>/m/<sub>`: their role and email there, the log it bound them to, "" where none), one statement
  /// of each station (`~<moved>/s/<key>`). A removal cancels the one of its subject, named or not (it may name them
  /// all by the `moved` entry's hash): so one said before the chain was read so takes out whom it took out then. (`~` sorts after every hex hash: an admit of the same role
  /// said in a log binds before the chain's.)
  carriedStatements(c: { moved: string; s: LockState }, rootSub: string, binds: Map<string, string> = new Map()): Map<string, Entry> {
    const out = new Map<string, Entry>();
    const base = { v: 1, ws: `person:${rootSub}`, seq: 0, prev: null, at: 0, sig: { key: "", alg: "Ed25519", sig: "" } };
    for (const [sub, m] of [...c.s.members].sort(([a], [b]) => (a < b ? -1 : 1))) {
      if (sub === rootSub || !ROLES.has(m.role)) continue;
      // (one it bound to no log, bound by their own `bind`: `bindsIn`)
      out.set(`~${c.moved}/m/${sub}`, { ...base, kind: "ws.member", body: { ws: WS, sub, email: m.email, lock: c.s.persons.get(sub) ?? binds.get(sub) ?? "", role: m.role } } as unknown as Entry);
    }
    for (const key of [...c.s.stations.keys()].sort()) out.set(`~${c.moved}/s/${key}`, { ...base, kind: "ws.station", body: { ws: WS, key } } as unknown as Entry);
    return out;
  }
  /// D6: of a member the chain as it moved names, bound as it bound them or bound by it to none (`lock`: the log of
  /// their binding in the list, "" for none), the devices it still says: an own app device whose log never put its id (by `device`, ever), each
  /// by the key it signs with there; a web page (whoever approved it) whose id their log never said (`web`,
  /// `web.remove`) until its `exp` there, by this keeper's clock. None where their binding is not the chain's, or the
  /// log that binds them is not held (what it said is not known). The model's keys are its devices' signers.
  carriedDevices(h: Holder, c: { moved: string; s: LockState }, sub: string, lock: string): { apps: string[]; webs: string[]; sayless: Map<string, string> } {
    const none = { apps: [], webs: [], sayless: new Map<string, string>() };
    const was = c.s.persons.get(sub) ?? "";
    if ((was !== lock && was !== "") || !c.s.members.has(sub)) return none;
    const putIds = new Set<string>(), webIds = new Set<string>();
    if (lock !== "") {
      const k = h.logs.get(lock);
      if (!k || k.rules.state(lock).sub !== sub) return none;
      for (const x of k.active) {
        const e = k.store.get(x)!;
        if (e.kind === "genesis") putIds.add(e.body.device.id);
        else if (e.kind === "device") putIds.add(e.body.id);
        else if (e.kind === "web" || e.kind === "web.remove") webIds.add(e.body.id);
      }
    }
    const now = this.clock(h);
    const apps: string[] = [], webs: string[] = [], sayless = new Map<string, string>();
    for (const d of c.s.devices.values()) {
      if (d.sub !== sub) continue;
      if (d.kind === "app" && d.own && d.sign_key !== undefined) {
        if (!putIds.has(d.id)) apps.push(d.sign_key);
        else sayless.set(d.id, d.sign_key);
      } else if (d.kind === "web" && !webIds.has(d.id) && (d.exp ?? 0) > now) webs.push(d.id);
    }
    return { apps, webs, sayless };
  }
  /// Round three's list over the statements in force: each given to `roster` as its plaintext entry would have been.
  /// D6: with the chain's statements as the root's where a chain moved here, and the keys of the devices it carries.
  rosterIn(h: Holder, root: string, ws: string, f: { stmts: Map<string, Body> }): Roster {
    const logs = new Map<string, unknown>();
    // (`cancels=h`: what a removal names is every statement in force of that body)
    const byBody = new Map<string, string[]>();
    if ((this.x.o.cancels ?? "h") === "h") for (const x of f.stmts.keys()) byBody.set(this.entry(x).body.h, [...(byBody.get(this.entry(x).body.h) ?? []), x]);
    const c = this.carriedOf(h, ws);
    const rootSub = h.logs.get(root)?.rules.state(root).sub ?? "alice";
    const carried = c === null ? new Map<string, Entry>() : this.carriedStatements(c, rootSub, this.bindsIn(h, c, rootSub, ws, f));
    const named = (cs: string[]) => cs.flatMap((x: string) => (c !== null && x === c.moved ? [...carried.keys()] : byBody.size > 0 ? (byBody.get(x) ?? []) : [x]));
    for (const [g, k] of h.logs) {
      logs.set(g, {
        active: g === root ? [...carried.keys(), ...k.active] : k.active, rules: k.rules, headState: () => k.headState(),
        store: {
          get: (x: string) => {
            const v = carried.get(x);
            if (v !== undefined) return v;
            const e = k.store.get(x)!, b = f.stmts.get(x);
            if (b === undefined || b.kind === "open" || b.kind === "off") return e;
            const { kind, salt: _, ws: __, ...rest } = b;
            if (Array.isArray(rest.cancels)) {
              // (a removal takes back the chain's statement of its subject too, named or not)
              const own = c === null ? undefined : `~${c.moved}/${kind === "member.remove" ? `m/${rest.sub}` : `s/${rest.key}`}`;
              rest.cancels = [...new Set([...named(rest.cancels), ...(own !== undefined && carried.has(own) ? [own] : [])])];
            }
            return { ...e, kind: `ws.${kind}`, body: { ...rest, ws: WS } };
          },
        },
      });
    }
    const r = roster({ logs } as unknown as Holder, root, this.v.rule ?? "grounded");
    if (c !== null) for (const [sub, m] of r.members) for (const k of this.carriedDevices(h, c, sub, m.lock).apps) r.letIn.set(k, sub);
    return r;
  }
  /// D6's bindings in force at `h` (the lead's, 2026-11-14), by member: of each member the chain as it moved bound to no
  /// log (not the root's person), the log of the smallest entry hash among their logs' `bind` statements in force that
  /// the signer the chain names for an own, signing app device of theirs proves (`bindValid`).
  bindsIn(h: Holder, c: { moved: string; s: LockState }, rootSub: string, ws: string, f: { stmts: Map<string, Body> }): Map<string, string> {
    const best = new Map<string, [string, string]>();
    for (const [g, k] of h.logs) {
      const sub = k.rules.state(g).sub;
      if (sub === rootSub || !c.s.members.has(sub) || c.s.persons.has(sub)) continue;
      for (const x of k.active) {
        const b = f.stmts.get(x);
        if (b?.kind !== "bind") continue;
        const named = [...c.s.devices.values()].some((d) => d.sub === sub && d.kind === "app" && d.own && d.sign_key === b.key);
        if (!named || !bindValid(b.key, b.sig, ws, sub, g, c.moved)) continue;
        const was = best.get(sub);
        if (was === undefined || x < was[0]) best.set(sub, [x, g]);
      }
    }
    return new Map([...best].map(([sub, [, g]]) => [sub, g]));
  }
  rosterOf(h: Holder, ws = WS, all = false): Roster {
    const root = this.pinsOf(h).get(ws);
    if (!root) return roster({ logs: new Map() } as unknown as Holder, "", "grounded");
    return this.rosterIn(h, root, ws, this.inForce(h, ws, all));
  }
  ros(h: Holder): Roster {
    return this.rosterOf(h, WS);
  }
  /// The web devices on log `lock`'s active chain at `h` that have not run out by its clock (D2).
  websAt(h: Holder, lock: string): string[] {
    const k = h.logs.get(lock);
    if (!k) return [];
    const exp = new Map<string, [number, number]>();
    for (const x of k.active) {
      const e = k.store.get(x)!;
      if (e.kind === "web") exp.set(e.body.id, [e.at, e.body.exp]);
      else if (e.kind === "web.remove") exp.delete(e.body.id);
    }
    // D2 as revised: dated no further ahead of this keeper's clock than SKEW, not run out by it (`exp <= at + 31 days`
    // the log's rules hold); `webAt`, the first reading: by `exp` alone
    const now = this.clock(h), atOnly = this.x.o.webAt === true;
    return [...exp].filter(([, [at, t]]) => t > now && (atOnly || at <= now + SKEW)).map(([id]) => id).sort();
  }
  /// D4 at `h` for `ws`: off (or let go), not rooted, or the state.
  d4(h: Holder, ws = WS, all = false): D4 | string {
    const root = this.pinsOf(h).get(ws);
    if (root === undefined) return "off";
    if (root === null) return "not rooted";
    if (!h.logs.has(root)) return "no root";
    const f = this.inForce(h, ws, all);
    const oo = this.openOff(h, root, f);
    if (oo.newest === "off") return "off";
    const r = this.rosterIn(h, root, ws, f);
    const c = this.carriedOf(h, ws);
    // (the root's member: its email is the `open` in force's)
    const members = new Map<string, D4Member>();
    for (const [sub, m] of r.members) {
      const k = h.logs.get(m.lock);
      const cd = c === null ? null : this.carriedDevices(h, c, sub, m.lock);
      // (each app by the signer its log says, as the product's state names it: rules/src/lock/state4.mbt; D6: one whose
      // log never said a signer by the one the chain as it moved named it with, as its person's own)
      const said = (d: { id: string; sign_key?: string }) => d.sign_key ?? cd?.sayless.get(d.id);
      const bound = k !== undefined && k.rules.state(m.lock).sub === sub;
      const apps = bound ? [...k.headState().devices.values()].flatMap((d) => (said(d) === undefined ? [] : [said(d)!])) : [];
      // (the root has no admit: no statement says its person's email)
      // (their web pages where the log that binds them has any device, one saying no signer too, as the rules list them)
      const devices = bound ? k.headState().devices.size : 0;
      const webs = devices > 0 ? this.websAt(h, m.lock) : [];
      const email = m.admit === "" ? (oo.settings?.email ?? c?.s.members.get(sub)?.email) : m.admit.startsWith("~") ? c?.s.members.get(sub)?.email : f.stmts.get(m.admit)?.email;
      members.set(sub, { role: m.role, email: email ?? "-", lock: m.lock === "" ? "none" : m.lock, apps: [...new Set([...apps, ...(cd?.apps ?? [])])].sort(), webs: [...new Set([...webs, ...(cd?.webs ?? [])])].sort() });
    }
    // (D6: where the root's log says neither `open` nor `off`, the chain as it moved says the settings, on)
    const s = oo.settings ?? (c === null ? null : c.s);
    return { on: oo.newest === "open" || (oo.newest === null && c !== null) ? "on" : "not on", settings: s ? canonical({ origins: s.origins, rp_id: s.rp_id, cloud_keys: s.cloud_keys }) : "-", members, stations: [...r.stations].sort() };
  }
  stateSaid(h: Holder): string {
    return d4Said(this.d4(h));
  }
  /// The keepers the workspace has, as any of its stations' state says them (its stations, the devices on its members'
  /// bound logs): those given its bodies, and so those whose states are compared.
  comparable(ws = WS, without?: Holder): Holder[] {
    // the stations another station lists (one taken out is told nothing more and keeps what it had: its own list,
    // naming itself and whom it had, does not count), then everyone those list
    const lists = new Map(this.stations.filter((s) => s !== without && this.pinsOf(s).get(ws)).map((s) => {
      const r = this.rosterOf(s, ws);
      return [s, new Set([...r.stations, ...r.letIn.keys()])] as const;
    }));
    const listed = [...lists.keys()].filter((s) => [...lists].some(([t, l]) => t !== s && l.has(this.keyOfHolder(s))));
    const keys = new Set(listed.flatMap((s) => [...lists.get(s)!]));
    return this.holders.filter((h) => keys.has(this.keyOfHolder(h)));
  }
  stands(h: Holder, x: string): boolean {
    return this.inForce(h, WS).stmts.has(x);
  }
  lacking(h: Holder, ws = WS): string[] {
    return this.pinsOf(h).has(ws) ? this.inForce(h, ws).lacking : [];
  }

  // ── what round three's code asks of a world, by bodies ────────────────────────────────────────────────────────

  /// The statements `h` has the bodies of, with their entry's hash.
  keptStatements(h: Holder): [string, Body][] {
    const kept = this.keptOf(h);
    return h.stored().filter((e) => e.kind === "ws" && kept.has(e.body.h)).map((e) => [hashOf(e), kept.get(e.body.h)!]);
  }
  seen(h: Holder, sub: string): string[] {
    return this.keptStatements(h).filter(([, b]) => b.kind === "member" && b.sub === sub && b.ws === WS).map(([x]) => x).sort();
  }
  seenStations(h: Holder, k: string, ws = WS): string[] {
    return this.keptStatements(h).filter(([, b]) => b.kind === "station" && b.key === k && b.ws === ws).map(([x]) => x).sort();
  }
  knownAdmits(d: Dev3, sub: string): string[] {
    const kept = this.keptOf(d.h);
    return [...this.known].filter((x) => {
      const e = this.entry(x), b = e.kind === "ws" ? kept.get(e.body.h) : undefined;
      return b?.kind === "member" && b.sub === sub && b.ws === WS;
    }).sort();
  }
  honestOp(d: Dev3, b: number, c: number): { kind: string; body: unknown } | null {
    const o = this.x.o;
    if (o.two && d.sub === "alice" && (b % 12 === 9 || b % 12 === 10)) {
      if (o.w2 === false || !this.pinsOf(d.h).has(WS2)) return null;
      const r = this.rosterOf(d.h, WS2);
      if (c % 3 === 0) return { kind: "ws.member", body: { ws: WS2, sub: "mallory", lock: this.home.get("mallory"), role: r.members.get("mallory")?.role === "member" ? "admin" : "member" } };
      const st = w2Keys[1].hex;
      if (c % 3 === 1) return r.stations.has(st) ? { kind: "ws.station.remove", body: { ws: WS2, key: st, cancels: this.seenStations(d.h, st, WS2) } } : { kind: "ws.station", body: { ws: WS2, key: st } };
      return { kind: "ws.open", body: { ws: WS2, ...OPEN, rp_id: `w2-${c % 7}.still.fail` } };
    }
    const op = super.honestOp(d, b, c);
    if (op && o.w1 === false && op.kind.startsWith("ws.")) return null;
    return op;
  }

  /// A revoked key of `d` signs `kind` after `parent` (null where the rules refuse it).
  attack4(d: Dev3, parent: string, kind: string, body: unknown, at?: number): Entry | null {
    const e = this.make(this.entry(parent), kind, body, d.signer, at);
    if (!this.rulesOf(parent).valid(e)) return null;
    this.attack.set(hashOf(e), d);
    this.note(`  ${d.name}'s key, revoked, signs ${this.said(e)} after ${this.told(parent)}`);
    return e;
  }

  /// A1 with bodies: a fresh keeper given the same entries and bodies, shuffled and interleaved in batches (a body
  /// before its entry is not taken, and is given again after), works out the same state.
  sameEntries(): { checks: number; mismatch: number } {
    let mismatch = 0;
    const shuffle = <T>(xs: T[]) => {
      for (let i = xs.length - 1; i > 0; i--) {
        const j = this.rng.int(i + 1);
        [xs[i], xs[j]] = [xs[j], xs[i]];
      }
      return xs;
    };
    for (const h of this.holders) {
      const fresh = new Holder(`${h.name}'`, this);
      this.x.pins.set(fresh, new Map(this.pinsOf(h)));
      const al = this.x.allowed.get(h);
      if (al) this.x.allowed.set(fresh, al);
      this.x.skew.set(fresh, this.x.skew.get(h) ?? 0);
      const es = shuffle(h.stored()), bs = shuffle([...this.keptOf(h).values()]);
      const choose = (changed: Set<Keeper<PersonState>>) => {
        for (const k of changed) (k.active = k.choose()), (k.on = new Set(k.active));
      };
      for (let i = 0; i < Math.max(es.length, bs.length); i += 7) {
        choose(fresh.take(es.slice(i, i + 7)).changed);
        for (const b of bs.slice(i, i + 7)) this.takeBody(fresh, b, false);
      }
      for (let again = 0; again < 30; again++) {
        const { changed, any } = fresh.take(es);
        choose(changed);
        let got = false;
        for (const b of bs) if (this.takeBody(fresh, b, false)) got = true;
        if (!any && !got) break;
      }
      if (d4Said(this.d4(fresh)) !== d4Said(this.d4(h))) mismatch++;
      this.x.kept.delete(fresh), this.x.pins.delete(fresh), this.x.commits.delete(fresh);
    }
    return { checks: this.holders.length, mismatch };
  }

  // ── D5: the old chain ─────────────────────────────────────────────────────────────────────────────────────────

  /// Every keeper's chain at genesis `g`.
  pinOld(g: Entry, reading: "A" | "B") {
    const x = this.x;
    x.oldRules = new OldRules(g);
    x.reading = reading;
    for (const h of this.holders) x.old.set(h, new Keeper(h.name, OLD_V, x.oldRules));
  }
  /// `h` takes old-chain entries, chooses, and goes by the root a `moved` on its active chain names (D5).
  takeOld(h: Holder, es: Entry[]) {
    const x = this.x, k = x.old.get(h)!;
    if (!k.take(es)) return;
    k.active = k.choose();
    k.on = new Set(k.active);
    const moved = k.active.map((y) => x.oldRules!.moved.get(y)).find((r) => r !== undefined) ?? null;
    let root = moved;
    if (x.reading === "A") {
      if (moved !== null && !x.frozen.has(h)) x.frozen.set(h, moved);
      root = x.frozen.get(h) ?? null;
    }
    const pins = this.pinsOf(h);
    if (pins.get(WS) !== root) {
      pins.set(WS, root);
      h.ver++;
      this.note(`  ${h.name} goes by ${root === null ? "no root" : `the root #${root.slice(0, 6)}`}`);
      this.refresh(h, new Set());
    }
  }
  levelOld(skip: Set<Holder> = new Set()) {
    const x = this.x;
    for (let changed = true; changed; ) {
      changed = false;
      for (const a of this.holders) {
        if (skip.has(a)) continue;
        for (const b of this.holders) {
          if (a === b || skip.has(b)) continue;
          const ka = x.old.get(a)!, kb = x.old.get(b)!;
          const es = ka.active.filter((y) => !kb.store.has(y)).map((y) => ka.store.get(y)!);
          if (es.length === 0) continue;
          const before = kb.store.size;
          this.takeOld(b, es);
          if (kb.store.size > before) changed = true;
        }
      }
    }
  }
  /// The model's own check of the old chain: the keeper's state at its head is the real `fold` of its active chain.
  oldFolds(h: Holder): boolean {
    const x = this.x, k = x.old.get(h)!;
    const chain = k.active.filter((y) => !x.oldRules!.moved.has(y)).map((y) => k.store.get(y)!);
    const b = k.rules.state(chain.length === k.active.length ? k.head() : k.active[k.active.length - 2]);
    const said = (s: LockState) => canonical({ m: [...s.members], d: [...s.devices.keys()].sort(), st: [...s.stations.keys()].sort(), p: [...s.persons], o: s.origins, c: s.cloud_keys, head: s.head });
    try {
      return said(fold(chain, null)) === said(b);
    } catch {
      return false;
    }
  }
}

export const make4 = (more: W4Options = {}): Make3 => (seed, v, family, o) => new World4(seed, v, family, { ...o, ...more });
const VON = V3[1];

// ── M1: agreement with bodies in the way, and one body held back for good ──────────────────────────────────────────

export type M1Out = {
  runs: number; rested: number; agree: number; same: number; sameChecks: number;
  /// Held back: the body was of a statement on K's active chain; K's state differed from another station's; K let in
  /// other keys; K listed it as lacking; how many statements of K the order rule held up behind it; K came level the
  /// moment it was given.
  heldOnChain: number; differ: number; letInDiff: number; listed: number; heldUp: number; level: number;
  /// What the order rule costs with nothing held back: (keeper, statement) pairs ready (on the active chain, body kept)
  /// before they were in force, and by how many steps; pairs ready and never in force at the end.
  readyPairs: number; delayed: number; delaySteps: number[]; neverIn: number;
  /// Gating (D1 as revised), at the end with every body given: lacking bodies at a keeper the workspace has, that some
  /// other keeper keeps (it could not be given them), and that no keeper keeps.
  stuckHeld: number; stuckNone: number; stuckLog: string[] | null;
  /// Keepers taken out (once given the workspace's bodies, no longer listed by its stations) and those of them whose own
  /// list says they are out; one that does not, told.
  out: number; outKnow: number; outLog: string[] | null;
  /// The model's check: where nothing is lacking, the state from the kept bodies is the state from every body made.
  oracle: number; oracleBad: number;
  refused: Record<string, number>; letGo: number;
  smallest: string[] | null; notLevel: string[] | null;
};
export function m1(family: Family, runs: number, steps: number, more: W4Options = {}): M1Out {
  const out: M1Out = { runs, rested: 0, agree: 0, same: 0, sameChecks: 0, heldOnChain: 0, differ: 0, letInDiff: 0, listed: 0, heldUp: 0, level: 0, readyPairs: 0, delayed: 0, delaySteps: [], neverIn: 0, stuckHeld: 0, stuckNone: 0, stuckLog: null, out: 0, outKnow: 0, outLog: null, oracle: 0, oracleBad: 0, refused: {}, letGo: 0, smallest: null, notLevel: null };
  for (let seed = 1; seed <= runs; seed++) {
    // the same world with nothing held back: what the order rule costs, what gating leaves out
    const free = new World4(seed, VON, family, { ...more, track: true });
    free.run(drawSteps3(seed, steps));
    free.finish();
    const x = free.x;
    for (const [k, at] of x.ready) {
      out.readyPairs++;
      const inAt = x.inAt.get(k);
      if (inAt === undefined) continue;
      if (inAt > at) out.delayed++, out.delaySteps.push(inAt - at);
    }
    const listed = free.comparable();
    for (const h of free.holders) {
      if (listed.includes(h) || !free.pinsOf(h).get(WS) || free.keptOf(h).size === 0) continue;
      out.out++;
      const r = free.ros(h), k = free.keyOfHolder(h);
      if (!r.stations.has(k) && !r.letIn.has(k)) out.outKnow++;
      else out.outLog ??= [`seed ${seed} (${family}): ${h.name} is out and its list still names it; it lacks ${free.lacking(h).map((y) => free.said(free.entry(y))).join("; ") || "nothing"}`];
    }
    for (const h of listed) {
      for (const y of free.lacking(h)) {
        const hb = free.entry(y).body.h;
        const who = free.holders.filter((o) => o !== h && free.keptOf(o).has(hb));
        if (who.length > 0) {
          out.stuckHeld++;
          out.stuckLog ??= [`seed ${seed} (${family}): ${h.name} lacks the body of ${free.said(free.entry(y))}, kept by ${who.map((o) => o.name).join(", ")}`, ...free.log.slice(-12)];
        } else out.stuckNone++;
      }
      const f = free.inForce(h, WS);
      out.neverIn += f.ready.filter((y) => !f.stmts.has(y)).length;
    }
    const station = seed % 3, nth = 1 + ((seed * 7) % 5);
    const w = new World4(seed, VON, family, { ...more, holdBack: { station, nth } });
    w.run(drawSteps3(seed, steps));
    if (w.finish()) out.rested++;
    const s = w.sameEntries();
    out.same += s.mismatch;
    out.sameChecks += s.checks;
    // (K's own list left out: it lacks a body, and names whom the others may not)
    const K = w.stations[station], others = w.comparable(WS, K).filter((h) => h !== K);
    if (new Set(others.map((h) => w.stateSaid(h))).size === 1) out.agree++;
    for (const h of w.holders) {
      if (w.lacking(h).length > 0) continue;
      out.oracle++;
      if (d4Said(w.d4(h)) !== d4Said(w.d4(h, WS, true))) out.oracleBad++;
    }
    for (const [k, n] of Object.entries(w.x.refused)) out.refused[k] = (out.refused[k] ?? 0) + n;
    out.letGo += w.x.letGo.length;
    const hb = w.x.order[w.x.base + nth - 1];
    if (hb === undefined) continue;
    const held = [...K.logs.values()].flatMap((k) => k.active.filter((y) => k.store.get(y)!.kind === "ws" && k.store.get(y)!.body.h === hb));
    // (only where it is still one of the workspace's stations: one taken out is given nothing more)
    if (held.length === 0 || !w.comparable().includes(K)) continue;
    out.heldOnChain++;
    const other = w.stations.find((h) => h !== K)!;
    const stateK = w.stateSaid(K), stateO = w.stateSaid(other);
    if (stateK !== stateO) out.differ++;
    const keys = (h: Holder) => [...w.ros(h).letIn.keys()].map(nameOfKey).sort().join(", ");
    const keysK = keys(K), keysO = keys(other);
    if (keysK !== keysO) out.letInDiff++;
    if (w.lacking(K).includes(held[0])) out.listed++;
    const f = w.inForce(K, WS);
    out.heldUp += f.ready.filter((y) => !f.stmts.has(y)).length;
    w.x.withheld.clear();
    w.giveBodies(K, [w.x.bodies.get(hb)!]);
    if (w.stateSaid(K) === stateO) out.level++;
    else out.notLevel ??= [`seed ${seed} (${family}): ${K.name} given the body of ${w.said(w.entry(held[0]))}: ${d4Diff(w.d4(K), w.d4(other)).join(", ")}; it lacks ${w.lacking(K).map((y) => w.said(w.entry(y))).join("; ") || "nothing"}`, `${K.name}: ${w.stateSaid(K)}`, `${other.name}: ${stateO}`];
    if (keysK !== keysO && out.smallest === null) out.smallest = [`seed ${seed} (${family}): the body of ${w.said(w.entry(held[0]))} never given to ${K.name}`, `${K.name} lets in: ${keysK}`, `${other.name} lets in: ${keysO}`];
  }
  return out;
}

/// A body lost with its device: alice's app signs xena's admit and gives the stations the entry, not the body (its
/// message dropped); then the app is lost. Her phone, on her log, goes on: admits xena as an admin and makes dan a
/// member. At how many stations each of the phone's statements is in force, and what each lists as lacking.
export function lostBody(seed: number, order: Order): { later: number; inForce: number; through: number; xena: number; lacking: number; log: string[] } {
  const w = new World4(seed, VON, "free", { order });
  const A = w.dev("alice's app"), P = w.dev("alice's phone");
  w.sign(A, "device", personDevice(P));
  w.level();
  const e = w.sign(A, "ws.member", { ws: WS, sub: "xena", lock: w.home.get("xena"), role: "member" }, { bring: false }) as Entry;
  // (and one more of the app's, signed knowing it: its body reaches the stations, the first's does not)
  const e2 = w.sign(A, "ws.station", { ws: WS, key: w2Keys[0].hex }, { bring: false }) as Entry;
  for (const st of w.stations) w.receive(st, [e, e2]), w.giveBodies(st, [w.x.bodies.get(e2.body.h)!]);
  w.note("alice's app is lost, with the body of its last statement");
  w.keptOf(A.h).delete(e.body.h);
  w.holders = w.holders.filter((h) => h !== A.h);
  w.level();
  const later = [
    w.sign(P, "ws.member", { ws: WS, sub: "xena", lock: w.home.get("xena"), role: "admin" }) as Entry,
    w.sign(P, "ws.member", { ws: WS, sub: "dan", lock: w.home.get("dan"), role: "member" }) as Entry,
  ];
  w.level();
  let inForce = 0, through = 0;
  for (const h of w.stations) {
    const f = w.inForce(h, WS);
    for (const x of later) if (f.stmts.has(hashOf(x))) inForce++;
    if (f.stmts.has(hashOf(e2))) through++;
  }
  return { later: later.length * w.stations.length, inForce, through, xena: w.stations.filter((h) => w.ros(h).members.has("xena")).length, lacking: w.stations.reduce((n, h) => n + w.lacking(h).length, 0), log: w.log };
}

/// A signer leaving its own statement out of the chain: bob's app removes carol (X), whose body s0 is never given;
/// then it admits xena (Y), naming as `prev` the statement before X (`skip`) or X (as it holds it). At s0 and s1: carol
/// in the list, Y in force. And the world where bob never signed X.
export function skipOwn(order: Order): Record<string, string> {
  const out: Record<string, string> = {};
  for (const how of ["honest", "skip", "no X"] as const) {
    const w = new World4(1, VON, "free", { order });
    const B = w.dev("bob's app");
    w.level();
    let before: string | null = null;
    if (how !== "no X") {
      const k = B.h.logs.get(B.log)!;
      before = k.active.map((y) => k.store.get(y)!).filter((e) => e.kind === "ws" && e.body.t === tagOf(WS, B.log)).at(-1)?.body.h ?? null;
      const x = w.sign(B, "ws.member.remove", { ws: WS, sub: "carol", cancels: w.seen(B.h, "carol") }, { bring: false }) as Entry;
      w.x.withheld.add(`${x.body.h}>s0`);
    }
    if (how === "skip") w.x.forcePrev = before;
    const y = w.sign(B, "ws.member", { ws: WS, sub: "xena", lock: w.home.get("xena"), role: "member" }, { bring: false }) as Entry;
    w.level();
    for (const st of w.stations.slice(0, 2)) out[`${how} ${st.name}`] = `carol ${w.ros(st).members.has("carol") ? "in" : "out"}, Y ${w.inForce(st, WS).stmts.has(hashOf(y)) ? "in force" : "not"}`;
  }
  return out;
}

/// A member newly let in whose only givers of an old body are away: bob's app makes carol an admin; that body goes to
/// s0 alone (every other keeper is never given it by anyone but s0 and bob's devices). s0 and bob's devices go away;
/// alice admits xena, everyone else syncs (`rounds` times). Then s0 is back, bob's devices still away.
export function newcomer(seed: number): { away: string[]; back: string[]; log: string[] } {
  const w = new World4(seed, VON, "free");
  const B = w.dev("bob's app"), A = w.dev("alice's app"), X = w.dev("xena's app");
  w.level();
  const e = w.sign(B, "ws.member", { ws: WS, sub: "carol", lock: w.home.get("carol"), role: "admin" }, { bring: false }) as Entry;
  const s0 = w.stations[0], gone = new Set([s0, B.h, w.dev("bob's phone").h]);
  for (const h of w.holders) if (!gone.has(h)) w.x.withheld.add(`${e.body.h}>${h.name}`);
  w.level();
  w.x.withheld.clear();
  w.note("s0 and bob's devices are away");
  w.sign(A, "ws.member", { ws: WS, sub: "xena", lock: w.home.get("xena"), role: "member" }, { bring: false });
  let rounds = 0;
  for (; rounds < 20; rounds++) w.level(gone);
  const said = (h: Holder) => `${h.name}: carol ${w.ros(h).members.get("carol")?.role ?? "out"}, xena ${w.ros(h).letIn.has(X.signer.id) ? "let in" : "not let in"}, lacking ${w.lacking(h).length}`;
  const away = [`after ${rounds} rounds of syncs among those up:`, said(X.h), said(w.stations[1]), said(s0)];
  w.note("s0 is back (bob's devices still away): every keeper up syncs");
  w.level(new Set([B.h, w.dev("bob's phone").h]));
  const back = [said(X.h), said(w.stations[1]), `one state at every keeper up: ${new Set(w.comparable().filter((h) => !gone.has(h) || h === s0).map((h) => w.stateSaid(h))).size === 1}`];
  return { away, back, log: w.log };
}

// ── M2: a body is only its commitment's ─────────────────────────────────────────────────────────────────────────────

export type M2Out = { offered: Record<string, number>; taken: number; control: number; controlTaken: number; why: Record<string, number> };
/// Every keeper of both workspaces offered: a body changed after it was committed to; a body whose hash a commitment
/// under the other workspace's tag holds; a body naming the other workspace committed under this one's tag; a copy of
/// a body of the other workspace with its `ws` changed; a body committed to under this one's tag whose `prev` is not
/// the statement before it. The commitments of the second, third and fifth are alice's app's.
export function m2(seed: number): M2Out {
  const w = new World4(seed, VON, "free", { two: true });
  const A = w.dev("alice's app");
  w.level();
  const out: M2Out = { offered: {}, taken: 0, control: 0, controlTaken: 0, why: {} };
  const salt = (n: number) => sha(`m2|${seed}|${n}`).slice(0, 32);
  const head = () => w.entry(A.h.logs.get(A.log)!.head());
  const commit = (t: string, b: Body) => {
    const e = w.make(head(), "ws", { t, h: bodyHash(b) }, A.signer);
    w.receive(A.h, [e]);
    w.level();
    return e;
  };
  const admit = (ws: string, n: number, prev: string | null): Body => ({ ws, kind: "member", sub: "xena", email: "xena@x", lock: w.home.get("xena")!, role: "member", prev, salt: salt(n) });
  const last = (ws: string) => {
    const k = A.h.logs.get(A.log)!;
    const e = k.active.map((y) => k.store.get(y)!).filter((y) => y.kind === "ws" && y.body.t === tagOf(ws, w.root)).at(-1);
    return e === undefined ? null : (e.body.h as string);
  };
  const crossed = admit(WS, 2, last(WS2));
  commit(tagOf(WS2, w.root), crossed);
  const inside = admit(WS2, 3, last(WS));
  commit(tagOf(WS, w.root), inside);
  const badPrev = admit(WS, 4, sha("not the one before"));
  commit(tagOf(WS, w.root), badPrev);
  const w2any = [...w.x.bodies.values()].find((b) => b.ws === WS2)!;
  const w1any = [...w.x.bodies.values()].find((b) => b.ws === WS && b.kind === "member")!;
  const offers: [string, Body][] = [
    ["changed after committed", { ...w1any, role: "owner" }],
    ["under the other workspace's tag", crossed],
    ["naming the other workspace inside", inside],
    ["the other workspace's, its ws changed", { ...w2any, ws: WS }],
    ["its prev not the statement before it", badPrev],
  ];
  const before = w.x.refused;
  w.x.refused = {};
  for (const h of w.holders) {
    for (const [what, b] of offers) {
      out.offered[what] = (out.offered[what] ?? 0) + 1;
      if (w.takeBody(h, b, true)) out.taken++;
    }
    // the control: a body it keeps, taken away and offered again
    const mine = [...w.keptOf(h).values()][0];
    if (mine) {
      out.control++;
      w.keptOf(h).delete(bodyHash(mine));
      if (w.takeBody(h, mine, false)) out.controlTaken++;
    }
  }
  out.why = w.x.refused;
  w.x.refused = before;
  look4.at?.(w, `m2 seed ${seed}`, offers.map(([, b]) => b));
  return out;
}

// ── M3: two workspaces, one person in both ──────────────────────────────────────────────────────────────────────────

export type M3Out = {
  runs: number;
  /// (a) at the second workspace's stations: bodies of the first kept; hits of the first's names in what they store
  /// (by what was looked for); what they can tell: commitments of other tags in alice's log, how many tags, the span.
  w1Bodies: number; hits: Record<string, number>; otherCommits: number; otherTags: number; spanSecs: number[];
  /// (b) each workspace's state compared with the run where the other's statements were never made.
  sameW1: number; sameW2: number; agreeW1: number; agreeW2: number;
  firstDiff: string[] | null;
  /// Worlds where alice's log forked at s0 in either run; for each world where W1 differs, what and the forks.
  forkWorlds: number; w1Diffs: string[][];
};
export function m3(family: Family, runs: number, steps: number): M3Out {
  const out: M3Out = { runs, w1Bodies: 0, hits: {}, otherCommits: 0, otherTags: 0, spanSecs: [], sameW1: 0, sameW2: 0, agreeW1: 0, agreeW2: 0, firstDiff: null, forkWorlds: 0, w1Diffs: [] };
  const run = (seed: number, o: W4Options) => {
    const w = new World4(seed, VON, family, { two: true, ...o });
    w.run(drawSteps3(seed, steps));
    w.finish();
    return w;
  };
  for (let seed = 1; seed <= runs; seed++) {
    const w = run(seed, {});
    const w2st = w.stations.filter((h) => h.name.startsWith("w"));
    const w1st = w.stations.filter((h) => h.name.startsWith("s"));
    // (a) everything they store, looked through
    const needles: [string, string[]][] = [
      ["the first workspace's id", [WS]],
      ["its members' subs", ["bob", "dan", "carol", "xena"].map((s) => `"${s}"`)],
      ["its members' logs", ["bob", "dan", "carol", "xena"].map((s) => w.home.get(s)!)],
      ["its stations' keys", stationKeys3.map((k) => k.hex)],
    ];
    for (const h of w2st) {
      const kept = [...w.keptOf(h).values()];
      out.w1Bodies += kept.filter((b) => b.ws !== WS2).length;
      const all = JSON.stringify([...h.stored(), ...kept, [...h.logs.keys()]]);
      for (const [what, ns] of needles) if (ns.some((n) => all.includes(n))) out.hits[what] = (out.hits[what] ?? 0) + 1;
      const k = h.logs.get(w.root)!;
      const others = k.active.map((y) => k.store.get(y)!).filter((e) => e.kind === "ws" && e.body.t !== tagOf(WS2, w.root));
      out.otherCommits += others.length;
      out.otherTags = Math.max(out.otherTags, new Set(others.map((e) => e.body.t)).size);
      if (others.length > 1) out.spanSecs.push(others.at(-1)!.at - others[0].at);
    }
    if (new Set(w.comparable().filter((h) => w1st.includes(h)).map((h) => w.stateSaid(h))).size === 1) out.agreeW1++;
    if (new Set(w.comparable(WS2).filter((h) => w2st.includes(h)).map((h) => d4Said(w.d4(h, WS2)))).size === 1) out.agreeW2++;
    // (b)
    const noW2 = run(seed, { w2: false }), noW1 = run(seed, { w1: false });
    const a1 = w.stateSaid(w1st[0]), b1 = noW2.stateSaid(noW2.stations[0]);
    const a2 = d4Said(w.d4(w2st[0], WS2)), b2 = d4Said(noW1.d4(noW1.stations.find((h) => h.name === "w0")!, WS2));
    if (a1 === b1) out.sameW1++;
    if (a2 === b2) out.sameW2++;
    // where W1 differs: the places in any log where two entries hang at s0, in each run, and which won
    const forks = (x: World4) => [...x.stations[0].logs.values()].flatMap((k) =>
      [...k.kids].filter(([, ks]) => ks.length > 1).map(([p, ks]) => `after ${x.said(x.entry(p))}: ${ks.map((c) => `${k.on.has(c) ? "WON" : "lost"} ${x.said(x.entry(c))}`).join(" | ")}`));
    if (a1 !== b1) out.w1Diffs.push([`seed ${seed}: ${d4Diff(w.d4(w1st[0]), noW2.d4(noW2.stations[0])).join(", ")}`, "forks with W2's statements:", ...forks(w), "forks without:", ...forks(noW2)]);
    if (forks(w).length > 0 || forks(noW2).length > 0) out.forkWorlds++;
    if ((a1 !== b1 || a2 !== b2) && out.firstDiff === null) out.firstDiff = [`seed ${seed}`, `W1 with W2's statements: ${a1}`, `W1 without:             ${b1}`, `W2 with W1's statements: ${a2}`, `W2 without:             ${b2}`];
  }
  return out;
}

// ── M5: web devices ─────────────────────────────────────────────────────────────────────────────────────────────────

export type M5Clock = {
  skew: number; webAt: boolean; at: [number, number][]; tooLong: string | null; removed: number; signerGone: number; lifeDays: number;
  /// An entry dated ten years ahead: taken by the rules; stations letting it in now; for how long of a keeper's own time
  /// it counts in all (in days).
  farTaken: boolean; farNow: number; farDays: number;
};
/// alice's app puts a web device on for 31 days; the stations' clocks are -skew, 0, +skew. How many stations let it in
/// at times around its `exp`; one of 31 days and a second refused; one taken off by `web.remove` (by her phone); one
/// put on by her phone, which her app then takes off the log; one put on with an `at` ten years ahead (a clock that
/// is wrong, or a key in other hands). `webAt`: the first reading of D2.
export function m5Clock(seed: number, skew: number, webAt: boolean): M5Clock {
  const w = new World4(seed, VON, "free", { webAt });
  const A = w.dev("alice's app"), P = w.dev("alice's phone");
  w.stations.forEach((h, i) => w.x.skew.set(h, (i - 1) * skew));
  w.sign(A, "device", personDevice(P));
  w.level();
  const k = A.h.logs.get(A.log)!;
  const tooLong = w.rulesOf(k.head()).why(w.make(w.entry(k.head()), "web", { id: webKey("alice").hex, label: "alice's browser", exp: w.t + 1 + WEB_DEVICE_SECS + 1 }, A.signer));
  const exp = w.t + 1 + WEB_DEVICE_SECS;
  w.sign(A, "web", { id: webKey("alice").hex, label: "alice's browser", exp });
  w.level();
  look4.at?.(w, `m5 skew ${skew}, a web device on`);
  const lets = (id: string) => w.stations.filter((h) => w.websAt(h, A.log).includes(id)).length;
  const now = w.t;
  const at: [number, number][] = [];
  for (const off of [-2 * skew - 1, -Math.ceil(skew / 2), Math.ceil(skew / 2), 2 * skew + 1]) {
    w.t = exp + off;
    at.push([off, lets(webKey("alice").hex)]);
    look4.at?.(w, `m5 skew ${skew}, at exp ${off >= 0 ? "+" : ""}${off} s`);
  }
  w.t = now;
  w.sign(P, "web.remove", { id: webKey("alice").hex });
  w.level();
  const removed = lets(webKey("alice").hex);
  const bob = webKey("bob").hex;
  const e = w.sign(P, "web", { id: bob, label: "a browser alice's phone let in", exp: w.t + 1 + WEB_DEVICE_SECS }) as Entry;
  w.level();
  w.sign(A, "device.remove", { key: P.signer.id });
  w.level();
  look4.at?.(w, `m5 skew ${skew}, taken off, and put on by a device taken off since`);
  const signerGone = lets(bob);
  const lifeDays = (e.body.exp - e.at) / DAY;
  const far = w.t + 10 * 365 * DAY;
  const fe = w.make(w.entry(k.head()), "web", { id: webKey("dan").hex, label: "a clock ten years ahead", exp: far + WEB_DEVICE_SECS }, A.signer, far);
  const farTaken = w.rulesOf(k.head()).why(fe) === null;
  if (farTaken) w.receive(A.h, [fe]), w.level();
  const start = w.t;
  const farNow = lets(webKey("dan").hex);
  look4.at?.(w, `m5 skew ${skew}, dated ten years ahead`);
  // a station at the middle clock, sampled every day from now until it ran out: the days it counted
  const mid = w.stations[1];
  let farDays = 0;
  for (let t = start; t <= far + WEB_DEVICE_SECS + DAY; t += DAY) {
    w.t = t;
    if (w.websAt(mid, A.log).includes(webKey("dan").hex)) farDays++;
  }
  w.t = start;
  return { skew, webAt, at, tooLong, removed, signerGone, lifeDays, farTaken, farNow, farDays };
}

/// A member whose only device's log entry says no signer (said again without one, as an entry from before signers were
/// said is), with a web page it let in: the member listed, their app signing nothing, the web page let in, as the
/// rules list them (rules/src/lock/state4.mbt: a member's web pages where the log that binds them has any device).
export function unsigned(seed: number): { listed: boolean; apps: number; webs: number } {
  const w = new World4(seed, VON, "free");
  const C = w.dev("carol's app");
  w.sign(C, "device", { key: C.signer.id, id: C.base.hex, label: C.name });
  w.level();
  w.sign(C, "web", { id: webKey("carol").hex, label: "carol's browser", exp: w.t + 1 + WEB_DEVICE_SECS });
  w.level();
  look4.at?.(w, `a member whose device says no signer, with a web page, seed ${seed}`);
  const d = w.d4(w.stations[0]);
  const m = typeof d === "string" ? undefined : d.members.get("carol");
  return { listed: m !== undefined, apps: m?.apps.length ?? -1, webs: m?.webs.length ?? -1 };
}

export type RevokedOut = {
  /// Stations (of 3) at which it was in force before every keeper synced, and at the end; whether keepers' states
  /// differ at the end; `off`: the stations that let go (`offFinal`); the root's person's steps to have it on again,
  /// and whether every keeper the workspace has is on with the list it had before after them.
  before: number; end: number; differ: boolean; letGo: number; steps: number; recovered: boolean; log: string[];
  /// Where it is not on with the list as before: what differs (devices aside: the phone was taken out).
  why: string[];
};
/// alice's app takes her phone off her log (the root's) while one station is cut off; the phone's key signs `kind` (a
/// web device for 31 days; `off`) after the removal's parent (`same`) or after a parent it was on the log at (`any`),
/// and brings it to the cut station (and, odd seeds, one device); every keeper syncs. For `off`, then, what alice's app
/// does to have the workspace on again: as revised, an `open` after its head where its own state is off; `offFinal`,
/// also pins it again itself, signs again each statement whose body went as it let go, gives the root to each keeper
/// that let go.
export function revoked(seed: number, kind: "web" | "off", parent: "same" | "any", offFinal = false, more: W4Options = {}): RevokedOut {
  const w = new World4(seed, VON, "free", { ...more, offFinal });
  const A = w.dev("alice's app"), P = w.dev("alice's phone");
  w.sign(A, "device", personDevice(P));
  w.level();
  for (let i = w.rng.int(5); i > 0; i--) {
    const st = stationKeys3[2].hex, r = w.ros(A.h);
    w.sign(A, r.stations.has(st) ? "ws.station.remove" : "ws.station", r.stations.has(st) ? { ws: WS, key: st, cancels: w.seenStations(A.h, st) } : { ws: WS, key: st }, { bring: false });
    w.level();
  }
  const baseList = w.ros(w.stations[0]), base4 = w.d4(w.stations[0]);
  // (the third station may have been taken out above)
  const cut = w.stations[w.rng.int(2)];
  w.note(`${cut.name} is cut off`);
  const r = w.sign(A, "device.remove", { key: P.signer.id }, { bring: false }) as Entry;
  w.level(new Set([cut]));
  P.compromised = true;
  const rules = w.logs.get(A.log)!;
  const parents = w.attackParents(P).filter((h) => rules.depth(h) <= rules.depth(r.prev!));
  const p = parent === "same" ? r.prev! : parents[w.rng.int(parents.length)];
  const e = kind === "web" ? w.attack4(P, p, "web", { id: ROGUE_WEB.hex, label: "a revoked key's", exp: w.t + 1 + WEB_DEVICE_SECS })
    : w.attack4(P, p, "ws.off", { ws: WS });
  const inForce = (h: Holder) => kind === "web" ? w.websAt(h, A.log).includes(ROGUE_WEB.hex) : w.d4(h) === "off";
  w.reach(e!, [cut, ...(seed % 2 === 1 ? [w.devs[w.rng.int(w.devs.length)].h] : [])]);
  const before = w.stations.filter(inForce).length;
  look4.at?.(w, `revoked ${kind} ${parent} seed ${seed}, before the sync`);
  w.note(`${cut.name} is back: every keeper syncs with every other`);
  w.level();
  look4.at?.(w, `revoked ${kind} ${parent} seed ${seed}, after it`);
  const end = w.stations.filter(inForce).length;
  const differ = new Set(w.comparable().map((h) => w.stateSaid(h))).size > 1;
  const letGo = w.stations.filter((h) => !w.pinsOf(h).has(WS)).length;
  let steps = 0;
  if (kind === "off" && !offFinal && w.d4(A.h) === "off") {
    w.note("alice's app has the workspace on again");
    w.sign(A, "ws.open", { ws: WS, ...OPEN }, { bring: false }), steps++;
    w.level();
  }
  if (kind === "off" && offFinal && w.holders.some((h) => !w.pinsOf(h).has(WS))) {
    w.note("alice's app has the workspace on again");
    if (!w.pinsOf(A.h).has(WS)) w.pinsOf(A.h).set(WS, w.root), steps++;
    if (w.d4(A.h) === "off" || w.openOff(A.h, w.root, w.inForce(A.h, WS)).newest !== "open") w.sign(A, "ws.open", { ws: WS, ...OPEN }, { bring: false }), steps++;
    // what its list had, said again where its bodies went
    const now = w.ros(A.h);
    for (const [sub, m] of baseList.members) if (sub !== "alice" && !now.members.has(sub)) w.sign(A, "ws.member", { ws: WS, sub, lock: m.lock, role: m.role }, { bring: false }), steps++;
    for (const k of baseList.stations) if (!now.stations.has(k)) w.sign(A, "ws.station", { ws: WS, key: k }, { bring: false }), steps++;
    for (const h of w.holders) if (h !== A.h && !w.pinsOf(h).has(WS)) w.regive(A, h), steps++;
    w.level();
  }
  // on again: every keeper the workspace has on, in one state, with the members and stations it had before
  const ks = w.comparable(), d0 = w.d4(ks[0] ?? w.stations[0]);
  const recovered = kind === "web" || (typeof d0 !== "string" && d0.on === "on" && new Set(ks.map((h) => w.stateSaid(h))).size === 1 &&
    [...d0.members.keys()].sort().join() === [...baseList.members.keys()].sort().join() && d0.stations.join() === [...baseList.stations].sort().join());
  const why = recovered ? [] : d4Diff(base4, d0);
  look4.at?.(w, `revoked ${kind} ${parent} seed ${seed}, at the end`);
  return { before, end, differ, letGo, steps, recovered, log: w.log, why };
}

// ── M6: on and off ──────────────────────────────────────────────────────────────────────────────────────────────────

export type M6Out = { keepers: number; offAt: number; letGo: number; steps: number; onAgain: number; sameList: boolean; notRootChanged: number; log: string[] };
/// bob's app (an admin, not the root) signs `open` with other settings and `off`: whose state changed. Then alice's app
/// signs `off`: who says off, who lets go (`offFinal`); then what her app does to have it on again: as revised, an
/// `open` after its head, then syncs alone; `offFinal`, pinning it again itself, the open, every admit and station
/// signed again, the root given to each keeper.
export function m6(seed: number, offFinal = false): M6Out {
  const w = new World4(seed, VON, "free", { offFinal });
  const A = w.dev("alice's app"), B = w.dev("bob's app");
  w.level();
  const base = w.stateSaid(w.stations[0]);
  const before = w.holders.map((h) => w.stateSaid(h));
  w.sign(B, "ws.open", { ws: WS, ...OPEN, email: "bob@x", rp_id: "evil.example" });
  w.sign(B, "ws.off", { ws: WS });
  w.level();
  const notRootChanged = w.holders.filter((h, i) => w.stateSaid(h) !== before[i]).length;
  look4.at?.(w, `m6 seed ${seed}, bob's open and off`);
  const keepers = w.comparable();
  w.sign(A, "ws.off", { ws: WS });
  w.level();
  const offAt = keepers.filter((h) => w.d4(h) === "off").length;
  look4.at?.(w, `m6 seed ${seed}, alice's off`);
  const letGo = keepers.filter((h) => !w.pinsOf(h).has(WS)).length;
  for (let i = 0; i < 20; i++) w.send(w.holders[w.rng.int(w.holders.length)], w.holders[w.rng.int(w.holders.length)]);
  w.finish();
  let steps = 0;
  w.note("alice's app has the workspace on again");
  if (offFinal) w.pinsOf(A.h).set(WS, w.root), steps++;
  w.sign(A, "ws.open", { ws: WS, ...OPEN }, { bring: false }), steps++;
  if (offFinal) {
    for (const [sub, role] of [["bob", "admin"], ["dan", "admin"], ["carol", "member"]]) w.sign(A, "ws.member", { ws: WS, sub, lock: w.home.get(sub), role }, { bring: false }), steps++;
    for (const k of stationKeys3) w.sign(A, "ws.station", { ws: WS, key: k.hex }, { bring: false }), steps++;
    for (const h of w.holders) if (h !== A.h) w.regive(A, h), steps++;
  }
  w.level();
  const onAgain = keepers.filter((h) => w.d4(h) !== "off" && (w.d4(h) as D4).on === "on").length;
  look4.at?.(w, `m6 seed ${seed}, on again`);
  return { keepers: keepers.length, offAt, letGo, steps, onAgain, sameList: keepers.every((h) => w.stateSaid(h) === base), notRootChanged, log: w.log };
}

// ── M7: the handover ────────────────────────────────────────────────────────────────────────────────────────────────

export type M7Out = {
  /// Keepers, how many end rooted in alice's log, in another, in none; all on one root; every keeper's state.
  keepers: number; compared: number; atAlice: number; atOther: number; atNone: number; oneRoot: boolean; behind: string[];
  /// The fields that differ between the old chain's state just before and each keeper's after, with the reasons the
  /// handover gave for leaving something out; those differences no reason covers.
  diffs: Record<string, number>; lost: string[]; unexplained: string[];
  /// The model's check: every keeper's old-chain state is the real `fold` of its active chain.
  folds: boolean;
  before: string; after: string; log: string[];
};
/// A workspace with a chain of its own (the product's rules): alice owner, bob admin, dan and carol drawn (owner,
/// admin, member; member, viewer), xena drawn in or not; phones, person logs bound, web devices, a station taken out,
/// new control-plane keys drawn. alice's app hands it over to her log (D5); each person's app writes their web devices
/// into their own log, unless drawn not to run. `away`: s2 is cut off through it and comes back holding only the old
/// chain. `attack`: alice's phone, on the old chain and taken off it, signs a second `moved` to a log of its own after
/// the removal's parent (`same`) or a parent it was on the chain at (`any`), brought to one station after the handover.
export function m7(seed: number, o: { away?: boolean; attack?: "same" | "any"; reading?: "A" | "B" }): M7Out {
  const w = new World4(seed, VON, "free", { bare: true });
  const r = new Rng(seed * 104729 + 7);
  const app = (sub: string) => w.dev(`${sub}'s app`), phone = (sub: string) => w.dev(`${sub}'s phone`);
  const dev = (s: { base: Key; signer: Key; name: string }, sub: string) => ({ id: s.base.hex, sub, kind: "app", label: s.name, sign_key: s.signer.id });
  const roles: [string, string][] = [["alice", "owner"], ["bob", "admin"], ["dan", ["owner", "admin", "member"][r.int(3)]], ["carol", ["member", "viewer"][r.int(2)]]];
  const g = signed({
    v: 1, ws: WS, seq: 0, prev: null, at: w.t, kind: "genesis", body: {
      owner: "alice", ...SETTINGS, members: roles.map(([sub, role]) => ({ sub, email: `${sub}@x`, role })),
      devices: roles.map(([sub]) => dev(spec(`${sub}'s app`), sub)), passkeys: [], stations: stationKeys3.map((k, i) => ({ key: k.hex, name: `s${i}` })), gateways: [],
    },
  }, spec("alice's app").signer);
  w.pinOld(g, o.reading ?? "B");
  const rules = w.x.oldRules!;
  let head = g;
  /// Every old-chain entry made, by its hash.
  const made = new Map<string, Entry>([[hashOf(g), g]]);
  const old = (by: Dev3, kind: string, body: (at: number) => unknown, parent = head): Entry | null => {
    const at = ++w.t;
    const e = signed({ v: 1, ws: WS, seq: parent.seq + 1, prev: hashOf(parent), at, kind, body: body(at) }, by.signer);
    if (!rules.valid(e)) return null;
    made.set(hashOf(e), e);
    w.note(`  ${by.name} signs on the old chain ${e.seq}: ${kind} #${hashOf(e).slice(0, 6)}`);
    if (parent === head) head = e;
    return e;
  };
  const subs = roles.map(([s]) => s);
  if (r.int(2) === 0) old(app("alice"), "member", () => ({ sub: "xena", email: "xena@x", role: "member" })), old(app("alice"), "device", () => dev(spec("xena's app"), "xena")), subs.push("xena");
  const ran = new Map<string, boolean>();
  for (const sub of subs) {
    if ((r.int(2) === 0 || (sub === "alice" && o.attack)) && old(app(sub), "device", () => dev(phone(sub), sub))) w.sign(app(sub), "device", personDevice(phone(sub)), { bring: false });
    if (r.int(4) !== 0) old(app(sub), "person", () => ({ sub, person: w.home.get(sub) }));
    if (r.int(2) === 0) old(app(sub), "device", (at) => ({ id: webKey(sub).hex, sub, kind: "web", label: `${sub}'s browser`, exp: at + (1 + r.int(31)) * DAY }));
    ran.set(sub, sub === "alice" || r.int(4) !== 0);
  }
  if (r.int(3) === 0) old(app("alice"), "station.remove", () => ({ key: stationKeys3[2].hex }));
  if (r.int(2) === 0) old(app("alice"), "cloud_keys", () => ({ keys: { keys: [{ kid: "k2" }] } }));
  let removal: Entry | null = null;
  if (o.attack) {
    removal = old(app("alice"), "device.remove", () => ({ id: phone("alice").base.hex }));
    w.sign(app("alice"), "device.remove", { key: phone("alice").signer.id }, { bring: false });
  }
  const upTo = (x: Entry): Entry[] => {
    const out: Entry[] = [];
    for (let y = x; ; y = made.get(y.prev!)!) {
      out.unshift(y);
      if (y.prev === null) return out;
    }
  };
  for (const h of w.holders) w.takeOld(h, upTo(head));
  w.level();
  const cut = w.stations[2];
  const skip = o.away ? new Set([cut]) : new Set<Holder>();
  if (o.away) {
    w.note(`${cut.name} is away through the handover`);
    cut.logs.clear();
    w.keptOf(cut).clear();
    cut.ver++;
  }
  // the handover
  const S = rules.state(hashOf(head));
  const A = app("alice");
  const lost: string[] = [];
  w.sign(A, "ws.open", { ws: WS, origins: S.origins, rp_id: S.rp_id, cloud_keys: S.cloud_keys, email: S.members.get("alice")!.email }, { bring: false });
  for (const [sub, m] of S.members) {
    if (sub === "alice") continue;
    const lock = S.persons.get(sub);
    if (lock === undefined) lost.push(`member ${sub}: bound no person log`);
    else if (!ROLES.has(m.role)) lost.push(`member ${sub}: ${m.role}, a role no admit gives`);
    else w.sign(A, "ws.member", { ws: WS, sub, lock, role: m.role, email: m.email }, { bring: false });
  }
  for (const k of S.stations.keys()) w.sign(A, "ws.station", { ws: WS, key: k }, { bring: false });
  for (const d of S.devices.values()) {
    if (d.kind !== "web" || (d.exp ?? 0) <= w.t) continue;
    if (!ran.get(d.sub)) lost.push(`web ${d.sub}: their device never ran`);
    else w.sign(app(d.sub), "web", { id: d.id, label: d.label, exp: d.exp }, { bring: false });
  }
  w.level(skip);
  const now = w.t;
  const before = d4Old(S, A.log, now + 1);
  look4.at?.(w, `m7 seed ${seed}, said again in alice's log`);
  const moved = old(A, "moved", () => ({ root: A.log }))!;
  for (const h of w.holders) if (!skip.has(h)) w.takeOld(h, [moved]);
  w.level(skip);
  look4.at?.(w, `m7 seed ${seed}, moved`);
  if (o.attack && removal) {
    const P = phone("alice");
    const fake = w.genesis({ ...ACCOMPLICE[0], sub: "alice", name: "a log of the revoked key's" });
    const fakeLog = hashOf(fake);
    const opened = w.make(fake, "ws.open", { ws: WS, ...OPEN, rp_id: "taken.example" }, ACCOMPLICE[0].signer);
    const at = [...rules.states.keys()].filter((h) => rules.states.get(h)!.devices.has(P.base.hex) && rules.depth(h) <= rules.depth(removal!.prev!) && !rules.moved.has(h));
    const p = o.attack === "same" ? removal.prev! : at.sort((a, b) => rules.depth(a) - rules.depth(b) || (a < b ? -1 : 1))[r.int(at.length)];
    const second = old(P, "moved", () => ({ root: fakeLog }), made.get(p)!)!;
    w.note(`  alice's phone's key, revoked, signs a second moved after old ${made.get(p)!.seq}`);
    const to = w.stations[r.int(skip.size ? 2 : 3)];
    const branch = upTo(second);
    w.attack.set(hashOf(opened), P);
    w.receive(to, [fake, opened]);
    w.takeOld(to, branch);
    w.levelOld(skip);
    w.level(skip);
    look4.at?.(w, `m7 seed ${seed}, a second moved`);
  }
  if (o.away) {
    w.note(`${cut.name} is back`);
    w.levelOld();
    w.level();
  }
  w.t = now + 2;
  look4.at?.(w, `m7 seed ${seed}, at the end`);
  const roots = w.holders.map((h) => w.pinsOf(h).get(WS) ?? null);
  // compared: the keepers the workspace has after it (its stations, its members' devices: who is given its bodies)
  const listed = new Set(w.comparable());
  const states = w.holders.map((h) => w.d4(h));
  const diffs: Record<string, number> = {};
  const unexplained: string[] = [];
  for (const [i, s] of states.entries()) {
    if (roots[i] !== A.log || !listed.has(w.holders[i])) continue;
    for (const d of d4Diff(before, s)) {
      const [kind, sub] = d.split(" ");
      diffs[kind] = (diffs[kind] ?? 0) + 1;
      if (!lost.some((l) => l.startsWith(`member ${sub}:`) || l.startsWith(`${kind} ${sub}:`)) && !unexplained.includes(d)) unexplained.push(d);
    }
  }
  // left behind on purpose (the lead, 2026-11-13): gateways and passkeys (nothing in the product writes either into a
  // lock today), the `own`/`signed` flags (devices put under another's name cannot be said in a person's own log)
  const behind = [`gateways ${S.gateways.size}`, `passkeys ${S.passkeys.size}`, `devices not their person's own ${[...S.devices.values()].filter((d) => !d.own).length}`];
  return {
    keepers: w.holders.length, compared: listed.size, atAlice: roots.filter((x) => x === A.log).length, atOther: roots.filter((x) => x !== null && x !== A.log).length, atNone: roots.filter((x) => x === null).length,
    oneRoot: new Set(roots).size === 1, diffs, lost, unexplained, behind, folds: w.holders.every((h) => w.oldFolds(h)),
    before: d4Said(before), after: d4Said(states[0]), log: w.log,
  };
}

// ── M8: the handover that waits for nobody (D6, the lead's, 2026-11-14) ────────────────────────────────────────────

export type M8Out = {
  /// Who was of which kind: (a) a device that signs and no log bound, (b1) bound with an app device on the chain not
  /// on their log, (b2) bound with their log's device saying no signer, (w) a web page alone, a manager's approval.
  kinds: Record<string, string>;
  /// Keepers, those compared (the workspace's after the move), rooted in alice's log; the entries alice's log said for
  /// the handover; app devices the chain let in that were not their person's own (left behind on purpose, 2026-11-13).
  keepers: number; compared: number; atAlice: number; said: number; behind: number;
  /// Right after the move: the keepers whose state is the chain's list at its head for every member and every own app
  /// device (by its signer) and web page; the fields differing, by kind, and the first few.
  same: number; diffs: Record<string, number>; first: string[];
  /// Each later change (`role` of (b1), `bind` of (a), `device` (b1)'s chain phone off by its log, `web` a carried page
  /// taken off by its person's log, `out` (w) and (b2) taken out, `exp` the chain's pages run out): the compared
  /// keepers where it holds at the end, of those compared.
  later: Record<string, [number, number]>;
  /// Through the drawn arrivals: a keeper's state naming something taken out again after it named it out.
  back: number; backLog: string | null;
  before: string; after: string; log: string[];
};
/// A workspace with a chain of its own (the product's rules): alice owner and bound to her log; bob, dan, carol, xena
/// each of one kind (`M8Out.kinds`), drawn; web pages approved by their person's own device and by alice; one app
/// device alice put in under a member who had one (not their own). alice's app signs `moved` and nothing else: no
/// `open`, no admit, no web page said again, nobody waited for. Then the changes, each delivered between keepers in a
/// drawn order (`away`: s2 cut off through them, back at the end). `carry: false`: the same with D6 off.
/// `self`: (a) binds themselves to their own log (`bind`, proved by their app's signer the chain names), after a
/// binding no signer of theirs proves (a signature by a key the chain names as nobody's own of theirs), in place of
/// alice's admit.
export function m8(seed: number, o: { carry?: boolean; away?: boolean; self?: boolean } = {}): M8Out {
  const w = new World4(seed, VON, "free", { bare: true, carry: o.carry !== false });
  const r = new Rng(seed * 15485863 + 3);
  const app = (sub: string) => w.dev(`${sub}'s app`), phone = (sub: string) => w.dev(`${sub}'s phone`);
  const dev = (s: { base: Key; signer: Key; name: string }, sub: string) => ({ id: s.base.hex, sub, kind: "app", label: s.name, sign_key: s.signer.id });
  const others = ["bob", "dan", "carol", "xena"];
  const order = ["a", "b1", "b2", "w"];
  for (let i = order.length - 1; i > 0; i--) {
    const j = r.int(i + 1);
    [order[i], order[j]] = [order[j], order[i]];
  }
  const kindOf = new Map(others.map((sub, i) => [sub, order[i]]));
  const who = (k: string) => others.find((s) => kindOf.get(s) === k)!;
  const roles: [string, string][] = [["alice", "owner"], ["bob", "admin"], ["dan", ["owner", "admin", "member"][r.int(3)]], ["carol", ["member", "viewer"][r.int(2)]], ["xena", ["admin", "member", "viewer"][r.int(3)]]];
  const g = signed({
    v: 1, ws: WS, seq: 0, prev: null, at: w.t, kind: "genesis", body: {
      owner: "alice", ...SETTINGS, members: roles.map(([sub, role]) => ({ sub, email: `${sub}@x`, role })),
      devices: roles.filter(([sub]) => kindOf.get(sub) !== "w").map(([sub]) => dev(spec(`${sub}'s app`), sub)), passkeys: [], stations: stationKeys3.map((k, i) => ({ key: k.hex, name: `s${i}` })), gateways: [],
    },
  }, spec("alice's app").signer);
  w.pinOld(g, "B");
  const rules = w.x.oldRules!;
  let head = g;
  const made = new Map<string, Entry>([[hashOf(g), g]]);
  const old = (by: Dev3, kind: string, body: (at: number) => unknown): Entry => {
    const at = ++w.t;
    const e = signed({ v: 1, ws: WS, seq: head.seq + 1, prev: hashOf(head), at, kind, body: body(at) }, by.signer);
    if (!rules.valid(e)) throw new Error(`m8 seed ${seed}: the chain refuses ${kind} by ${by.name}`);
    made.set(hashOf(e), e);
    w.note(`  ${by.name} signs on the old chain ${e.seq}: ${kind} #${hashOf(e).slice(0, 6)}`);
    return (head = e);
  };
  const web = (sub: string, id: Key, by: Dev3) => old(by, "device", (at) => ({ id: id.hex, sub, kind: "web", label: `${sub}'s page by ${by.name}`, exp: at + (1 + r.int(31)) * DAY }));
  old(app("alice"), "person", () => ({ sub: "alice", person: w.home.get("alice") }));
  if (r.int(2) === 0) old(app("alice"), "device", () => dev(phone("alice"), "alice")), w.sign(app("alice"), "device", personDevice(phone("alice")), { bring: false });
  for (const sub of others) {
    const k = kindOf.get(sub)!;
    if (k === "w") {
      web(sub, webKey(sub), app("alice"));
      continue;
    }
    if (k !== "a") old(app(sub), "person", () => ({ sub, person: w.home.get(sub) }));
    if (k === "b1" || (k === "a" && r.int(2) === 0)) old(app(sub), "device", () => dev(phone(sub), sub));
    if (k === "b2") w.sign(app(sub), "device", { key: app(sub).signer.id, id: app(sub).base.hex, label: app(sub).name }, { bring: false });
    if (k === "b2" || r.int(2) === 0) web(sub, webKey(sub), app(sub));
  }
  if (r.int(2) === 0) web(who("b1"), key(4400), app("alice"));
  // (alice puts in an app device under (a), who has one that signs: not theirs, so left behind)
  if (r.int(2) === 0) old(app("alice"), "device", () => dev(spec(`${who("a")}'s laptop`), who("a")));
  const upTo = (x: Entry): Entry[] => {
    const out: Entry[] = [];
    for (let y = x; ; y = made.get(y.prev!)!) {
      out.unshift(y);
      if (y.prev === null) return out;
    }
  };
  for (const h of w.holders) w.takeOld(h, upTo(head));
  w.level();
  const S = rules.state(hashOf(head));
  const A = app("alice");
  const root = A.log;
  // the chain's list at its head, as D4 says a state: every member, each own app device by its signer, each web page
  // not run out, alice by her log
  const want = (now: number): D4 => {
    const members = new Map<string, D4Member>();
    for (const [sub, m] of S.members) {
      const devs = [...S.devices.values()].filter((d) => d.sub === sub);
      members.set(sub, {
        role: m.role, email: m.email, lock: S.persons.get(sub) ?? "none",
        apps: devs.filter((d) => d.kind === "app" && d.own && d.sign_key).map((d) => d.sign_key!).sort(),
        webs: devs.filter((d) => d.kind === "web" && (d.exp ?? 0) > now).map((d) => d.id).sort(),
      });
    }
    return { on: "on", settings: canonical({ origins: S.origins, rp_id: S.rp_id, cloud_keys: S.cloud_keys }), members, stations: [...S.stations.keys()].sort() };
  };
  const logLength = () => A.h.logs.get(root)!.active.length;
  const before = logLength();
  // the handover: `moved`, and nothing else
  const moved = old(A, "moved", () => ({ root }));
  const said = logLength() - before;
  for (const h of w.holders) w.takeOld(h, [moved]);
  w.level();
  look4.at?.(w, `m8 seed ${seed}, moved`);
  const expected = want(w.t);
  const listed = () => new Set(w.comparable());
  const ours = () => w.holders.filter((h) => w.pinsOf(h).get(WS) === root && listed().has(h));
  let same = 0;
  const diffs: Record<string, number> = {}, first: string[] = [];
  // (compared: the chain's keepers, its stations and the app devices it lets in, rooted in alice's log)
  const chainKeys = new Set([...S.stations.keys(), ...[...S.devices.values()].flatMap((d) => (d.kind === "app" && d.sign_key ? [d.sign_key] : []))]);
  const compared = w.holders.filter((h) => w.pinsOf(h).get(WS) === root && chainKeys.has(w.keyOfHolder(h)));
  for (const h of compared) {
    const d = d4Diff(expected, w.d4(h));
    if (d.length === 0) same++;
    for (const x of d) {
      diffs[x.split(" ")[0]] = (diffs[x.split(" ")[0]] ?? 0) + 1;
      if (first.length < 4 && !first.includes(x)) first.push(x);
    }
  }
  const after = d4Said(compared.length > 0 ? w.d4(compared[0]) : "none");
  // ── later: the changes, each delivered in a drawn order ──
  const skip = o.away ? new Set([w.stations[2]]) : new Set<Holder>();
  if (o.away) w.note(`${w.stations[2].name} is away through the changes`);
  /// What has been taken out, as a test on a keeper's state: true where it names it in.
  const outs = new Map<string, (d: D4) => boolean>();
  const seenOut = new Set<string>();
  let back = 0, backLog: string | null = null;
  const watch = () => {
    for (const h of w.holders) {
      if (w.pinsOf(h).get(WS) !== root) continue;
      const d = w.d4(h);
      if (typeof d === "string") continue;
      for (const [fact, isIn] of outs) {
        const id = `${h.name}|${fact}`;
        if (!isIn(d)) seenOut.add(id);
        else if (seenOut.has(id)) back++, (backLog ??= `seed ${seed}: ${h.name} names ${fact} again`);
      }
    }
  };
  const deliver = () => {
    const live = w.holders.filter((h) => !skip.has(h));
    for (let i = 0; i < 6 * live.length; i++) {
      const a = live[r.int(live.length)], b = live[r.int(live.length)];
      if (a !== b) w.send(a, b);
      while (w.queue.length > 0 && r.int(3) !== 0) {
        w.land(r.int(w.queue.length));
        watch();
      }
    }
    while (w.queue.length > 0) w.land(r.int(w.queue.length)), watch();
    w.level(skip);
    watch();
  };
  const m = (d: D4, sub: string) => d.members.get(sub);
  const cancels = [hashOf(moved)];
  // role: (b1) remade with another role, by the root's person
  const b1 = who("b1"), newRole = m(expected, b1)!.role === "member" ? "admin" : "member";
  w.sign(A, "ws.member.remove", { ws: WS, sub: b1, cancels });
  w.sign(A, "ws.member", { ws: WS, sub: b1, lock: w.home.get(b1), role: newRole, email: `${b1}@x` });
  deliver();
  // bind: (a) admitted with their own log, or (`self`) bound to it by their own app's proof
  const a = who("a");
  if (o.self) {
    const L = app(a).log;
    // (a forger's: the right form, signed by a key the chain names as nobody's of (a)'s own: nothing)
    w.sign(app(a), "ws.bind", { ws: WS, key: spec("alice's app").signer.id, sig: spec("alice's app").signer.sign(bindBytes(WS, a, L, hashOf(moved))) });
    deliver();
    w.sign(app(a), "ws.bind", { ws: WS, key: app(a).signer.id, sig: app(a).signer.sign(bindBytes(WS, a, L, hashOf(moved))) });
  } else w.sign(A, "ws.member", { ws: WS, sub: a, lock: w.home.get(a), role: m(expected, a)!.role, email: `${a}@x` });
  deliver();
  // device: (b1)'s phone, carried, put on their log and taken off it
  const ph = phone(b1).signer.id;
  w.sign(app(b1), "device", personDevice(phone(b1)));
  w.sign(app(b1), "device.remove", { key: ph });
  outs.set(`${b1}'s phone`, (d) => m(d, b1)?.apps.includes(ph) === true);
  deliver();
  // web: a carried page of (b2)'s taken off by their log
  const b2 = who("b2"), page = webKey(b2).hex;
  const hadPage = m(expected, b2)!.webs.includes(page);
  if (hadPage) {
    w.sign(app(b2), "web.remove", { id: page });
    outs.set(`${b2}'s page`, (d) => m(d, b2)?.webs.includes(page) === true);
    deliver();
  }
  // out: (w) and (b2) taken out
  const wo = who("w");
  for (const sub of [wo, b2]) {
    w.sign(A, "ws.member.remove", { ws: WS, sub, cancels });
    outs.set(sub, (d) => d.members.has(sub));
  }
  deliver();
  if (o.away) {
    w.note(`${w.stations[2].name} is back`);
    skip.clear();
    w.levelOld();
    w.level();
    watch();
  }
  const ends = ours();
  const tally = (f: (d: D4, h: Holder) => boolean): [number, number] => [ends.filter((h) => {
    const d = w.d4(h);
    return typeof d !== "string" && f(d, h);
  }).length, ends.length];
  const later: Record<string, [number, number]> = {
    role: tally((d) => m(d, b1)?.role === newRole),
    // (bound by an admit to their log, their devices as the chain had them: those it put on by their signers there,
    // the others carried)
    bind: tally((d) => m(d, a)?.lock === app(a).log && m(d, a)!.apps.join() === m(expected, a)!.apps.join()),
    device: tally((d) => m(d, b1) !== undefined && !m(d, b1)!.apps.includes(ph) && m(d, b1)!.apps.includes(app(b1).signer.id)),
    ...(hadPage ? { web: tally((d) => m(d, b2) === undefined || !m(d, b2)!.webs.includes(page)) } : {}),
    out: tally((d, h) => !d.members.has(wo) && !d.members.has(b2) && !w.rosterOf(h).letIn.has(app(b2).signer.id)),
  };
  // exp: past every page's `exp` on the chain, none of them is in
  w.t = Math.max(w.t, ...[...S.devices.values()].map((d) => d.exp ?? 0)) + 1;
  later.exp = tally((d) => [...d.members.values()].every((x) => x.webs.length === 0));
  look4.at?.(w, `m8 seed ${seed}, at the end`);
  return {
    kinds: Object.fromEntries(others.map((s) => [s, kindOf.get(s)!])), keepers: w.holders.length, compared: compared.length,
    atAlice: w.holders.filter((h) => w.pinsOf(h).get(WS) === root).length, said, behind: [...S.devices.values()].filter((d) => !d.own).length,
    same, diffs, first, later, back, backLog, before: d4Said(expected), after, log: w.log,
  };
}

// ── jobs, in worker threads ─────────────────────────────────────────────────────────────────────────────────────────

export type Job4 =
  | { t: "m1"; family: Family; runs: number; steps: number; order: Order; more?: W4Options }
  | { t: "m2"; n: number }
  | { t: "m3"; family: Family; runs: number; steps: number }
  /// Round three's job, in its world (`round: 3`) or this one's.
  | { t: "r3"; job: Job3; round: 3 | 4; more?: W4Options }
  | { t: "m5clock"; skew: number; webAt: boolean }
  | { t: "revoked"; kind: "web" | "off"; parent: "same" | "any"; n: number; offFinal: boolean; more?: W4Options }
  | { t: "m6"; n: number; offFinal: boolean }
  | { t: "m7"; n: number; away?: boolean; attack?: "same" | "any"; reading?: "A" | "B" }
  | { t: "m8"; n: number; carry?: boolean; away?: boolean; self?: boolean }
  | { t: "again"; steps: number }
  | { t: "lost"; order: Order }
  | { t: "skip"; order: Order }
  | { t: "newcomer" };

const tally = (into: Record<string, number>, k: string, n = 1) => {
  into[k] = (into[k] ?? 0) + n;
};

export function runJob4(j: Job4): unknown {
  switch (j.t) {
    case "m1":
      return m1(j.family, j.runs, j.steps, { ...j.more, order: j.order });
    case "m2": {
      const out = { offered: {} as Record<string, number>, taken: 0, control: 0, controlTaken: 0, why: {} as Record<string, number> };
      for (let seed = 1; seed <= j.n; seed++) {
        const o = m2(seed);
        for (const [k, n] of Object.entries(o.offered)) tally(out.offered, k, n);
        for (const [k, n] of Object.entries(o.why)) tally(out.why, k, n);
        out.taken += o.taken, out.control += o.control, out.controlTaken += o.controlTaken;
      }
      return out;
    }
    case "m3":
      return m3(j.family, j.runs, j.steps);
    case "r3":
      return runJob3(j.job, j.round === 4 ? make4(j.more) : undefined);
    case "m5clock":
      return m5Clock(1, j.skew, j.webAt);
    case "revoked": {
      const out = { n: j.n, before: 0, anyEnd: 0, allEnd: 0, differ: 0, letGo: 0, steps: [] as number[], recovered: 0, smallest: null as string[] | null, whyNot: {} as Record<string, number>, notLog: null as string[] | null };
      for (let seed = 1; seed <= j.n; seed++) {
        const o = revoked(seed, j.kind, j.parent, j.offFinal, j.more);
        for (const d of o.why) tally(out.whyNot, d);
        if (o.why.length > 0 && (out.notLog === null || o.log.length < out.notLog.length - 1)) out.notLog = [`seed ${seed}: ${o.why.join(", ")}`, ...o.log];
        out.before += o.before;
        if (o.end > 0) out.anyEnd++;
        if (o.end === 3) out.allEnd++;
        if (o.differ) out.differ++;
        out.letGo += o.letGo;
        out.steps.push(o.steps);
        if (o.recovered) out.recovered++;
        if ((o.end > 0 || o.differ) && (out.smallest === null || o.log.length < out.smallest.length)) out.smallest = o.log;
      }
      return out;
    }
    case "m6": {
      const out = { n: j.n, keepers: 0, offAt: 0, letGo: 0, steps: 0, onAgain: 0, sameList: 0, notRootChanged: 0, log: [] as string[] };
      for (let seed = 1; seed <= j.n; seed++) {
        const o = m6(seed, j.offFinal);
        out.keepers += o.keepers, out.offAt += o.offAt, out.letGo += o.letGo, out.steps = Math.max(out.steps, o.steps), out.onAgain += o.onAgain, out.notRootChanged += o.notRootChanged;
        if (o.sameList) out.sameList++;
        if (seed === 1) out.log = o.log;
      }
      return out;
    }
    case "m7": {
      const out = { n: j.n, keepers: 0, compared: 0, behind: {} as Record<string, number>, atAlice: 0, atOther: 0, atNone: 0, oneRoot: 0, otherWorlds: 0, diffs: {} as Record<string, number>, lost: {} as Record<string, number>, unexplained: [] as string[], folds: true, example: null as string[] | null, otherLog: null as string[] | null };
      for (let seed = 1; seed <= j.n; seed++) {
        const o = m7(seed, j);
        for (const b of o.behind) tally(out.behind, b.replace(/ \d+$/, ""), Number(b.split(" ").at(-1)));
        out.keepers += o.keepers, out.compared += o.compared, out.atAlice += o.atAlice, out.atOther += o.atOther, out.atNone += o.atNone;
        if (o.oneRoot) out.oneRoot++;
        if (o.atOther > 0) out.otherWorlds++, (out.otherLog ??= o.log);
        for (const [k, n] of Object.entries(o.diffs)) tally(out.diffs, k, n);
        for (const l of o.lost) tally(out.lost, l.split(": ")[1]);
        for (const u of o.unexplained) if (out.unexplained.length < 6) out.unexplained.push(`seed ${seed}: ${u}`);
        if (!o.folds) out.folds = false;
        if (o.lost.length > 0 && out.example === null) out.example = [`seed ${seed}, left out: ${o.lost.join("; ")}`, `before: ${o.before}`, `after:  ${o.after}`];
      }
      return out;
    }
    case "m8": {
      const out = { n: j.n, keepers: 0, compared: 0, atAlice: 0, said: 0, behind: 0, same: 0, diffs: {} as Record<string, number>, first: [] as string[], later: {} as Record<string, [number, number]>, back: 0, backLog: null as string | null, example: null as string[] | null };
      for (let seed = 1; seed <= j.n; seed++) {
        const o = m8(seed, j);
        out.keepers += o.keepers, out.compared += o.compared, out.atAlice += o.atAlice, out.said += o.said, out.behind += o.behind, out.same += o.same, out.back += o.back;
        for (const [k, n] of Object.entries(o.diffs)) tally(out.diffs, k, n);
        for (const f of o.first) if (out.first.length < 4 && !out.first.includes(f)) out.first.push(`seed ${seed}: ${f}`);
        for (const [k, [a, b]] of Object.entries(o.later)) out.later[k] = [(out.later[k]?.[0] ?? 0) + a, (out.later[k]?.[1] ?? 0) + b];
        out.backLog ??= o.backLog;
        if (seed === 1) out.example = [`kinds ${JSON.stringify(o.kinds)}`, `the chain: ${o.before}`, `after:     ${o.after}`];
      }
      return out;
    }
    case "newcomer":
      return newcomer(1);
    case "skip":
      return skipOwn(j.order);
    case "lost":
      return lostBody(1, j.order);
    case "again": {
      // the same seed, the same world: twice, every line of what happened
      const one = () => {
        const w = new World4(3, VON, "faults", { holdBack: { station: 0, nth: 2 } });
        w.run(drawSteps3(3, j.steps));
        w.finish();
        return [...w.log, ...w.holders.map((h) => w.stateSaid(h))].join("\n");
      };
      const m = () => JSON.stringify(m7(2, { attack: "any" }).log);
      return one() === one() && m() === m();
    }
  }
}

if (!isMainThread && (workerData as { lockRoster4?: boolean } | null)?.lockRoster4 === true) {
  parentPort!.on("message", (m: { id: number; job: Job4 }) => {
    parentPort!.postMessage({ id: m.id, out: runJob4(m.job) });
  });
}
