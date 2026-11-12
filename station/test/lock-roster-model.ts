// The third round of lock-fork-choice-model.ts (2026-11-12): a workspace with no log of its own. What is said of a
// workspace (who belongs to it, in which role, by which of their person logs; its stations) is entries in the person
// log of whoever signs it, the same hash chain as that person's devices, each log chosen between branches by the first
// rounds' rule (lock-fork-choice-model.ts `Keeper`) with `tie=signer`. This is the lead's design, NOT the product's: the
// product's person-log rules (rules/src/lock/person.mbt, `personFold`) take only `genesis`, `device` and
// `device.remove`; the model checks the `ws.*` kinds itself and follows `personFold` on everything else
// (`foldCheck` says where it was compared). Run by lock-roster.test.ts, which prints what it measured.
//
// The kinds, each naming the workspace `ws`: `ws.member {ws, sub, lock, role}` admits `sub` by its person log of genesis
// hash `lock` as owner, admin or member; `ws.member.remove {ws, sub, cancels}` cancels the `ws.member` entries about
// `sub` it names (those its signer had stored: an observed-remove set); `ws.station {ws, key}` and
// `ws.station.remove {ws, key, cancels}` the same for a station. The workspace is rooted in alice's person log, whose
// genesis every keeper pins. A statement is in force at a keeper when it is on the active chain of its log there; the
// list is `roster`'s, steps 1-4 of the design with the choices it names.
//
// The faults are the first rounds': what is between keepers drops, delays, reorders and replays messages and never makes
// a valid signature; a device taken out of its person log has its key in other hands, which sign entries valid after
// any parent they know in that log and bring them to whichever keepers they reach.
//
// The product does not do this yet (2026-11-12): its workspace lock is a log of its own and its person logs take only
// `genesis`, `device` and `device.remove`. Tailscale's is the fork-choice rule of each log (lock-fork-choice-model.ts);
// ours are `tie=signer`, `resign`, the `ws.*` kinds and the list (`roster`: the coordinator's grounded labelling of
// 2026-11-12, the lead's first steps kept as `rule=steps` to compare). The second round's `recovery` and `retain` are not
// used here: they were measured there and not adopted (lock-fork-choice-model.ts says why).
import { isMainThread, parentPort, workerData } from "node:worker_threads";
import { type Entry, canonical, personFold, rank, sigValid } from "../src/cloud/lock.ts";
import { Keeper, type LogRules, type Variant, hashOf, signed } from "./lock-fork-choice-model.ts";
import { type Key, Rng, START, WS, eveKey, key } from "./lock-world-sim.ts";

/// The fork-choice rule on every person log: one vote a device (a person log has no roles), a `device.remove` the
/// removal, the active chain offered, `tie=signer`. `resign` as the first rounds have it.
/// `rule`: how the list is worked out from the statements in force (`roster`): `grounded`, the coordinator's correction
/// of 2026-11-12 (the default), or `steps`, the lead's steps 1-3 as first given.
export type V3v = Variant & { rule?: "steps" | "grounded" };
export const V3: V3v[] = (["off", "on"] as const).map((resign) => ({ votes: "flat", removal: "device", offers: "active", resign, hashfield: "as-is", tie: "signer" }));
export const STEPS_RULE: V3v = { ...V3[1], rule: "steps" };
export const v3Name = (v: V3v) => `tie=signer resign=${v.resign}${v.rule === "steps" ? " rule=steps" : ""}`;

const HEX32 = /^[0-9a-f]{64}$/;
export type Role3 = "owner" | "admin" | "member";
const ROLES3 = new Set(["owner", "admin", "member"]);
/// Who may give a role: an owner any, an admin admin or member.
export const mayGive = (giver: string, role: string) => giver === "owner" || (giver === "admin" && role !== "owner");
export const manages = (role: string | undefined) => role === "owner" || role === "admin";

// ── the people ──────────────────────────────────────────────────────────────────────────────────────────────────────

/// alice owns the workspace (its root), bob and dan are admins, carol a member, xena not in it yet; mallory is an
/// outsider whom only a revoked key admits. Each has an app, a phone and a laptop, a base key and a signing key each.
export const PEOPLE3 = ["alice", "bob", "dan", "carol", "xena", "mallory"] as const;
const DEVICE_KINDS = ["app", "phone", "laptop"] as const;
export type DevSpec = { name: string; sub: string; base: Key; signer: Key; kind: (typeof DEVICE_KINDS)[number] };
export const SPECS: DevSpec[] = PEOPLE3.flatMap((sub, i) => DEVICE_KINDS.map((kind, j) => ({ name: `${sub}'s ${kind}`, sub, kind, base: key(3000 + 10 * i + 2 * j), signer: key(3001 + 10 * i + 2 * j) })));
export const spec = (name: string) => SPECS.find((s) => s.name === name)!;
/// What a revoked key puts in its log beside itself: one accomplice device a person.
export const ACCOMPLICE = PEOPLE3.map((sub, i) => ({ name: `${sub}'s accomplice`, sub, base: key(3700 + 2 * i), signer: key(3701 + 2 * i) }));
export const stationKeys3 = [0, 1, 2].map((i) => key(3900 + i));
const keyName = new Map<string, string>([
  ...SPECS.map((s) => [s.signer.id, s.name] as [string, string]),
  ...ACCOMPLICE.map((s) => [s.signer.id, s.name] as [string, string]),
  [eveKey.id, "a forger"],
]);
/// Keys only the attacker's side holds: what a station turns away of these is no one's loss.
export const THEIRS = new Set([...SPECS.filter((s) => s.sub === "mallory").map((s) => s.signer.id), ...ACCOMPLICE.map((a) => a.signer.id)]);
export const nameOfKey = (k: string) => keyName.get(k) ?? `key ${k.slice(8, 14)}`;
export const stationName = (hex: unknown) => `s${stationKeys3.findIndex((k) => k.hex === hex)}`;
export const personDevice = (s: { base: Key; signer: Key; name: string }) => ({ key: s.signer.id, id: s.base.hex, label: s.name });

// ── a person log, by the rules ──────────────────────────────────────────────────────────────────────────────────────

export type PDev = { key: string; id: string; label: string };
export type PersonState = { sub: string; seq: number; devices: Map<string, PDev> };

/// Why an entry does not follow a person log's state `ps` (the product's words where person.mbt has them), or null.
/// `genesis`, `device`, `device.remove` as `fold_person`; the `ws.*` kinds the model's: signed by a device on it, the
/// body's shape.
function refusal(ps: PersonState, e: Entry, h: string): string | null {
  if (e.v !== 1 || e.ws !== `person:${ps.sub}`) return "an entry of another lock";
  if (!Number.isSafeInteger(e.at)) return "at is unix seconds";
  if (e.seq !== ps.seq + 1) return "the entry does not follow this lock's head";
  const b = e.body as Record<string, unknown> | null;
  const held = ps.devices.has(String(e.sig?.key));
  switch (e.kind) {
    case "device": {
      if (!held) return "not signed by a device on the lock";
      if (typeof b?.key !== "string" || typeof b?.id !== "string" || typeof b?.label !== "string") return "a person's device is {key, id, label}";
      if (!b.key.startsWith("ed25519:") || !HEX32.test(b.id)) return "a person's device signs with an ed25519 key, and goes by its base key";
      break;
    }
    case "device.remove": {
      if (typeof b?.key !== "string" || !ps.devices.has(b.key)) return "no such device";
      if (!held || ps.devices.size === 1) return "not signed by a device on the lock, or its last";
      break;
    }
    case "ws.member":
    case "ws.member.remove":
    case "ws.station":
    case "ws.station.remove": {
      if (!held) return "not signed by a device on the lock";
      if (typeof b?.ws !== "string") return "a statement names its workspace";
      const named = e.kind.startsWith("ws.member") ? typeof b.sub === "string" : typeof b.key === "string" && HEX32.test(b.key);
      if (!named) return "a statement names whom it is about";
      if (e.kind === "ws.member" && (typeof b.lock !== "string" || !HEX32.test(b.lock) || !ROLES3.has(String(b.role)))) return "an admit names a lock and a role";
      if (e.kind.endsWith(".remove") && !(Array.isArray(b.cancels) && b.cancels.every((x) => typeof x === "string" && HEX32.test(x)))) return "a removal names what it cancels";
      break;
    }
    default:
      return `unknown entry kind ${e.kind}`;
  }
  if (!sigValid(e.sig, h, [], "", false)) return "signature invalid";
  return null;
}

function after3(ps: PersonState, e: Entry): PersonState {
  const b = e.body as { key: string; id: string; label: string };
  if (e.kind === "device") return { sub: ps.sub, seq: e.seq, devices: new Map([...ps.devices, [b.key, { key: b.key, id: b.id, label: b.label }]]) };
  if (e.kind === "device.remove") {
    const devices = new Map(ps.devices);
    devices.delete(b.key);
    return { sub: ps.sub, seq: e.seq, devices };
  }
  return { sub: ps.sub, seq: e.seq, devices: ps.devices };
}

/// One person log's rules, worked out once a world (its genesis is valid: the world makes no other).
export class PersonRules implements LogRules<PersonState> {
  readonly g: Entry;
  readonly gh: string;
  readonly sub: string;
  states = new Map<string, PersonState>();
  depths = new Map<string, number>();
  verdicts = new Map<string, string | null>();
  constructor(g: Entry) {
    this.g = g;
    this.gh = hashOf(g);
    const b = g.body as { sub: string; device: PDev };
    this.sub = b.sub;
    if (g.kind !== "genesis" || g.seq !== 0 || g.prev !== null || g.ws !== `person:${b.sub}` || g.sig.key !== b.device.key || !sigValid(g.sig, this.gh, [], "", false)) throw new Error("the world made a genesis the rules refuse");
    this.states.set(this.gh, { sub: b.sub, seq: 0, devices: new Map([[b.device.key, b.device]]) });
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
  /// Why `e` does not follow its parent, or null.
  why(e: Entry): string | null {
    const h = hashOf(e);
    const id = `${h}|${e.sig.key}|${e.sig.sig}`;
    if (this.verdicts.has(id)) return this.verdicts.get(id)!;
    const ps = e.prev === null ? undefined : this.states.get(e.prev);
    const out = ps === undefined ? "the entry does not follow this lock's head" : refusal(ps, e, h);
    if (out === null && !this.states.has(h)) {
      this.states.set(h, after3(ps!, e));
      this.depths.set(h, this.depth(e.prev!) + 1);
    }
    this.verdicts.set(id, out);
    return out;
  }
  valid(e: Entry) {
    return this.why(e) === null;
  }
  state(h: string) {
    return this.states.get(h)!;
  }
  weight() {
    return 1;
  }
  removal(_: PersonState, e: Entry) {
    return e.kind === "device.remove";
  }
}

// ── a keeper of person logs ─────────────────────────────────────────────────────────────────────────────────────────

/// A station or a device: every person log it holds, each a first-round `Keeper`.
export class Holder {
  logs = new Map<string, Keeper<PersonState>>();
  ver = 0;
  readonly name: string;
  readonly w: World3;
  constructor(name: string, w: World3) {
    this.name = name;
    this.w = w;
  }
  has(h: string): boolean {
    const g = this.w.logOf.get(h);
    return g !== undefined && (this.logs.get(g)?.store.has(h) ?? false);
  }
  /// Stores what follows (geneses first, then each log's entries); the logs that stored something new.
  take(es: Entry[]): { changed: Set<Keeper<PersonState>>; any: boolean } {
    const changed = new Set<Keeper<PersonState>>();
    let any = false;
    const byLog = new Map<string, Entry[]>();
    for (const e of es) {
      const h = hashOf(e), g = this.w.logOf.get(h);
      if (g === undefined) continue;
      if (h === g) {
        if (!this.logs.has(g)) {
          this.logs.set(g, new Keeper(this.name, this.w.v, this.w.logs.get(g)!));
          any = true;
        }
        continue;
      }
      byLog.set(g, [...(byLog.get(g) ?? []), e]);
    }
    for (const [g, list] of byLog) {
      const k = this.logs.get(g);
      if (k && k.take(list)) changed.add(k), (any = true);
    }
    if (any) this.ver++;
    return { changed, any };
  }
  /// What it gives in a sync: each log's active chain.
  offered(): Entry[] {
    return [...this.logs.values()].flatMap((k) => k.active.map((h) => k.store.get(h)!));
  }
  stored(): Entry[] {
    return [...this.logs.values()].flatMap((k) => [...k.store.values()]);
  }
}

// ── the workspace's list at a keeper (steps 1-4) ────────────────────────────────────────────────────────────────────

export type Stmt = { h: string; e: Entry; body: any; log: string; by: string };
export type Member = { lock: string; role: Role3; admit: string };
export type Roster = {
  /// Whether it holds the root's log at all (else it cannot tell anything).
  rooted: boolean;
  members: Map<string, Member>;
  stations: Set<string>;
  /// The keys it lets in, by whose they are.
  letIn: Map<string, string>;
  /// Step 1's candidates and their roles, by `sub|lock`; the admits step 2 cancelled.
  step1: Map<string, Role3>;
  cancelled: Set<string>;
  /// Step 3's: every person log that counts as someone's in the list, with its highest role.
  pairs: Map<string, Role3>;
  admits: Stmt[];
  removes: Stmt[];
  /// The rule it was worked out by.
  rule: "steps" | "grounded";
  /// `grounded`: each argument's label (`a:<admit>`, `n:<pair>|<role>`, `c:<removal>|<admit>`), and the pairs left
  /// undecided (a circle of removals nothing outside decides).
  labels: Map<string, Label>;
  undecided: Set<string>;
};
export type Label = "in" | "out" | "undec";

/// Every (sub, lock) admitted, with the highest role given it, from the root on: an admit counts where its log is
/// such a pair's that may give its role. (Each admitted log counts as its person's, all at once: see `roster`.)
function pairsOf(root: string, admits: Stmt[]): Map<string, Role3> {
  const out = new Map<string, Role3>([[`alice|${root}`, "owner"]]);
  for (let changed = true; changed; ) {
    changed = false;
    for (const a of admits) {
      const giver = out.get(`${a.by}|${a.log}`);
      if (giver === undefined || !mayGive(giver, a.body.role)) continue;
      const k = `${a.body.sub}|${a.body.lock}`, was = out.get(k);
      if (was === undefined || rank(a.body.role) > rank(was)) out.set(k, a.body.role), (changed = true);
    }
  }
  return out;
}

/// The list at `h`, from the statements in force there.
///
/// Choices the design leaves open, made here (each said in the report): (a) a person with admits naming different
/// locks: every admitted (sub, lock) counts as that person's for what they sign (steps 1 and 3), and the one bound for
/// letting devices in is the admit giving the higher role, then the smaller entry hash; the root is an owner's admit of
/// the pinned genesis that wins every tie, so its binding never moves. (b) An admit counts as a candidate's where its
/// log's genesis names the signer: the statements of log L are `L.sub`'s, and an admit binds `sub` to `lock` only where
/// the keeper holds `lock` and its genesis names `sub`. (c) A cancellation counts only from a step-1 owner or admin,
/// naming a `ws.member` about the same `sub` whose role is not above the canceller's; the admit need not be in force.
/// (d) Stations: admitted by an owner or admin in the list, cancelled by a step-1 owner or admin, no roles among them.
export function roster(h: Holder, root: string, rule: "steps" | "grounded" = "grounded"): Roster {
  const stmts: Stmt[] = [];
  for (const [g, k] of h.logs) {
    for (const x of k.active) {
      const e = k.store.get(x)!;
      if (e.kind.startsWith("ws.") && (e.body as { ws?: string }).ws === WS) stmts.push({ h: x, e, body: e.body, log: g, by: k.rules.state(g).sub });
    }
  }
  const admits = stmts.filter((s) => s.e.kind === "ws.member"), removes = stmts.filter((s) => s.e.kind === "ws.member.remove");
  const out: Roster = { rooted: h.logs.has(root), members: new Map(), stations: new Set(), letIn: new Map(), step1: new Map(), cancelled: new Set(), pairs: new Map(), admits, removes, rule, labels: new Map(), undecided: new Set() };
  if (!out.rooted) return out;
  if (rule === "grounded") return grounded(h, root, stmts, out);
  // 1. candidates, cancellations aside
  out.step1 = pairsOf(root, admits);
  // 2. cancellations by step-1 owners and admins, each counting even where its signer is cancelled in this same step
  const byHash = new Map(admits.map((a) => [a.h, a]));
  for (const r of removes) {
    const role = out.step1.get(`${r.by}|${r.log}`);
    if (!manages(role)) continue;
    for (const c of r.body.cancels as string[]) {
      const a = byHash.get(c);
      if (a && a.body.sub === r.body.sub && rank(a.body.role) <= rank(role!)) out.cancelled.add(c);
    }
  }
  // 3. the list from the admits left
  const left = admits.filter((a) => !out.cancelled.has(a.h));
  out.pairs = pairsOf(root, left);
  const best = new Map<string, Member>([["alice", { lock: root, role: "owner", admit: "" }]]);
  for (const a of left) {
    const giver = out.pairs.get(`${a.by}|${a.log}`);
    if (giver === undefined || !mayGive(giver, a.body.role) || a.body.sub === "alice") continue;
    const was = best.get(a.body.sub);
    if (!was || rank(a.body.role) > rank(was.role) || (a.body.role === was.role && a.h < was.admit)) best.set(a.body.sub, { lock: a.body.lock, role: a.body.role, admit: a.h });
  }
  out.members = best;
  // 4. stations
  const stCancelled = new Set<string>();
  for (const r of stmts.filter((s) => s.e.kind === "ws.station.remove")) {
    if (!manages(out.step1.get(`${r.by}|${r.log}`))) continue;
    for (const c of r.body.cancels as string[]) stCancelled.add(`${c}|${r.body.key}`);
  }
  for (const s of stmts.filter((x) => x.e.kind === "ws.station")) {
    if (manages(out.pairs.get(`${s.by}|${s.log}`)) && !stCancelled.has(`${s.h}|${s.body.key}`)) out.stations.add(s.body.key);
  }
  // who is let in: a key on the active head of the log the list binds a member to
  for (const [sub, m] of best) {
    const k = h.logs.get(m.lock);
    if (!k || k.rules.state(m.lock).sub !== sub) continue;
    for (const key of k.headState().devices.keys()) out.letIn.set(key, sub);
  }
  return out;
}

/// The coordinator's correction (2026-11-12) of steps 1-3, as a Dung argumentation framework under the grounded
/// semantics (its least fixed point), the textbook definition where the correction's words and it differ:
///
/// - arguments: each `ws.member` in force (`a:`), standing for "this admit holds"; for every (sub, lock) pair that
///   signs or is admitted and each of admin and owner, `n:<pair>|<role>`, "the pair holds no standing of that role or
///   above"; for each removal and each admit it names about the same sub, `c:`, "this cancellation counts";
/// - attacks: every admit of a pair giving a role at least ρ attacks `n:<pair>|ρ` (so `n` is IN exactly when all of
///   them are OUT: a standing holds by any one of its admits); `n:<signer>|<the role needed to give it>` attacks each
///   admit the pair signed and `n:<signer>|<the role needed to cancel it>` each of its cancellations (an admit, or a
///   cancellation, counts only where its signer stands); a cancellation attacks the admit it names. The root's pair has
///   no `n`: it always stands, as owner.
/// - IN: every attacker OUT; OUT: some attacker IN; repeated until nothing changes; the rest UNDECIDED, taken as out.
///
/// Where the correction's words and the textbook differ, the textbook is followed: an UNDECIDED pair's cancellation is
/// UNDECIDED, not nothing, so what it names is UNDECIDED too (out of the list) rather than standing. The needed role:
/// owner to give owner, admin to give admin or member; owner to cancel an owner's admit, admin to cancel the others
/// (the canceller's role "not below" the admit's). Choices (a), (b) and the admit naming the same sub stay as in steps
/// 1-3; stations: admitted by an IN owner or admin, cancelled by one.
function grounded(h: Holder, root: string, stmts: Stmt[], out: Roster): Roster {
  const rootPair = `alice|${root}`;
  const { admits, removes } = out;
  out.step1 = pairsOf(root, admits);
  const attackers = new Map<string, string[]>();
  const arg = (id: string) => {
    if (!attackers.has(id)) attackers.set(id, []);
    return attackers.get(id)!;
  };
  const need = (role: string) => (role === "owner" ? "owner" : "admin");
  const lack = (pair: string, role: string) => {
    const id = `n:${pair}|${need(role)}`;
    arg(id);
    return id;
  };
  const pairOf = (s: Stmt) => `${s.by}|${s.log}`;
  for (const a of admits) {
    const id = `a:${a.h}`;
    arg(id);
    if (pairOf(a) !== rootPair) arg(id).push(lack(pairOf(a), a.body.role));
  }
  const byHash = new Map(admits.map((a) => [a.h, a]));
  for (const r of removes) {
    for (const c of r.body.cancels as string[]) {
      const a = byHash.get(c);
      if (!a || a.body.sub !== r.body.sub) continue;
      const id = `c:${r.h}|${a.h}`;
      arg(id);
      if (pairOf(r) !== rootPair) arg(id).push(lack(pairOf(r), a.body.role));
      arg(`a:${a.h}`).push(id);
    }
  }
  // every admit giving a role at least ρ attacks "lacks ρ"
  for (const id of [...attackers.keys()].filter((x) => x.startsWith("n:"))) {
    const cut = id.lastIndexOf("|"), pair = id.slice(2, cut), role = id.slice(cut + 1);
    for (const a of admits) if (`${a.body.sub}|${a.body.lock}` === pair && rank(a.body.role) >= rank(role)) attackers.get(id)!.push(`a:${a.h}`);
  }
  const label = out.labels;
  for (let changed = true; changed; ) {
    changed = false;
    for (const [id, by] of attackers) {
      if (label.has(id)) continue;
      if (by.some((x) => label.get(x) === "in")) label.set(id, "out"), (changed = true);
      else if (by.every((x) => label.get(x) === "out")) label.set(id, "in"), (changed = true);
    }
  }
  for (const id of attackers.keys()) if (!label.has(id)) label.set(id, "undec");
  // the pairs that stand, with their role (that of an admit of theirs in force, as `n:` has it; read off `pairs`, as a
  // pair that signed no admit and no cancellation has no `n:`, and was taken as standing nowhere until 2026-11-12, when
  // the rules written from this model (rules/src/lock/roster.mbt) found an admin's cancellation of a station ignored);
  // those left undecided
  const stands = (pair: string): Role3 | undefined => (pair === rootPair ? "owner" : out.pairs.get(pair));
  for (const a of admits) {
    const l = label.get(`a:${a.h}`)!;
    const k = `${a.body.sub}|${a.body.lock}`;
    if (l === "in") {
      const was = out.pairs.get(k);
      if (was === undefined || rank(a.body.role) > rank(was)) out.pairs.set(k, a.body.role);
    } else if (l === "undec" && manages(a.body.role)) out.undecided.add(k);
    if (l === "out" && removes.some((r) => label.get(`c:${r.h}|${a.h}`) === "in")) out.cancelled.add(a.h);
  }
  out.pairs.set(rootPair, "owner");
  for (const k of out.pairs.keys()) out.undecided.delete(k);
  const best = new Map<string, Member>([["alice", { lock: root, role: "owner", admit: "" }]]);
  for (const a of admits) {
    if (label.get(`a:${a.h}`) !== "in" || a.body.sub === "alice") continue;
    const was = best.get(a.body.sub);
    if (!was || rank(a.body.role) > rank(was.role) || (a.body.role === was.role && a.h < was.admit)) best.set(a.body.sub, { lock: a.body.lock, role: a.body.role, admit: a.h });
  }
  out.members = best;
  const stCancelled = new Set<string>();
  for (const r of stmts.filter((s) => s.e.kind === "ws.station.remove")) {
    if (!manages(stands(pairOf(r)))) continue;
    for (const c of r.body.cancels as string[]) stCancelled.add(`${c}|${r.body.key}`);
  }
  for (const s of stmts.filter((x) => x.e.kind === "ws.station")) {
    if (manages(stands(pairOf(s))) && !stCancelled.has(`${s.h}|${s.body.key}`)) out.stations.add(s.body.key);
  }
  for (const [sub, m] of best) {
    const k = h.logs.get(m.lock);
    if (!k || k.rules.state(m.lock).sub !== sub) continue;
    for (const key of k.headState().devices.keys()) out.letIn.set(key, sub);
  }
  return out;
}

export const rosterSaid = (r: Roster): string => {
  if (!r.rooted) return "no root";
  const ms = [...r.members].sort(([a], [b]) => (a < b ? -1 : 1)).map(([sub, m]) => `${sub} ${m.role} #${m.lock.slice(0, 6)}`).join(", ");
  const st = [...r.stations].map(stationName).sort().join(",");
  const keys = [...r.letIn.keys()].map(nameOfKey).sort().join(", ");
  return `[${ms}] stations ${st} let in: ${keys}`;
};

// ── the world ───────────────────────────────────────────────────────────────────────────────────────────────────────

export type Dev3 = DevSpec & { h: Holder; log: string; compromised: boolean; mine: string[]; superseded: Set<string> };
export type Msg = { to: Holder; entries: Entry[]; bodies?: unknown[] };
export type Family = "free" | "faults";
export type Intent = { dev: Dev3; hashes: string[]; void: string | null; kind: string; body: any; log: string; step: number };

export type World3Options = { laptops?: boolean; carol?: Role3; bare?: boolean };
/// What makes a world: round three's, or another round's built on it (lock-roster4-model.ts).
export type Make3 = (seed: number, v: V3v, family: Family, o?: World3Options) => World3;
export const make3: Make3 = (seed, v, family, o) => new World3(seed, v, family, o);

export class World3 {
  readonly v: V3v;
  rng: Rng;
  family: Family;
  t = START / 1000;
  step = 0;
  logs = new Map<string, PersonRules>();
  logOf = new Map<string, string>();
  all = new Map<string, Entry>();
  /// What went over a line, beside a holder's store: what a revoked key may sign after.
  known = new Set<string>();
  home = new Map<string, string>();
  root: string;
  stations: Holder[];
  devs: Dev3[];
  holders: Holder[];
  devOf = new Map<Holder, Dev3>();
  queue: Msg[] = [];
  sent: Msg[] = [];
  levelled = new Map<string, string>();
  /// Honest entries by hash (setup aside), the intents they carry.
  honest = new Map<string, string>();
  intents = new Map<string, Intent>();
  /// Keys an honest `device.remove` took out (by key: at which step); people an honest `ws.member.remove` named.
  removedKeys = new Map<string, number>();
  removedSubs = new Set<string>();
  attack = new Map<string, Dev3>();
  forged = new Set<string>();
  activeAt = new Map<string, Set<string>>();
  inactivated = new Set<string>();
  rollbacks: number[] = [];
  /// What each station lets in, and what it turned away: by key, at which step, whether an honest entry asked for it.
  letIn = new Map<Holder, Map<string, string>>();
  turned: { at: string; key: string; step: number; asked: boolean }[] = [];
  back = 0;
  awayNow = new Map<Holder, Set<string>>();
  resigned = 0;
  resigning = false;
  /// What a statement's own device would say of it right after signing (from the logs it holds then): why it has no
  /// effect, or null. (B1: whether the information was there to tell its person at once.)
  atSigning = new Map<string, string | null>();
  /// Called after each station chose again (scripted worlds watch what it lets in).
  watch: ((h: Holder, r: Roster) => void) | null = null;
  log: string[] = [];

  constructor(seed: number, v: V3v, family: Family = "free", o: World3Options = {}) {
    this.v = v;
    this.family = family;
    this.rng = new Rng(seed ^ 0x5157);
    this.stations = [0, 1, 2].map((i) => new Holder(`s${i}`, this));
    const kinds = o.laptops ? DEVICE_KINDS : DEVICE_KINDS.slice(0, 2);
    this.devs = SPECS.filter((s) => s.sub !== "mallory" && kinds.includes(s.kind)).map((s) => ({ ...s, h: new Holder(s.name, this), log: "", compromised: false, mine: [], superseded: new Set<string>() }));
    for (const d of this.devs) this.devOf.set(d.h, d);
    this.holders = [...this.stations, ...this.devs.map((d) => d.h)];
    for (const h of this.stations) this.letIn.set(h, new Map()), this.awayNow.set(h, new Set());
    // Each person's log, begun by their app; mallory's known only to whoever brings it.
    const setup: Entry[] = [];
    for (const sub of PEOPLE3) {
      const g = this.genesis(spec(`${sub}'s app`));
      this.home.set(sub, hashOf(g));
      if (sub !== "mallory") setup.push(g);
    }
    this.root = this.home.get("alice")!;
    for (const d of this.devs) d.log = this.home.get(d.sub)!;
    // alice's app admits bob and dan as admins, carol (as `o.carol`, a member by default), and the three stations.
    let head = this.all.get(this.root)!;
    const say = (kind: string, body: unknown) => {
      head = this.make(head, kind, body, spec("alice's app").signer);
      setup.push(head);
    };
    // (`bare`: none of it, for a world whose workspace begins elsewhere: lock-roster4-model.ts's handover)
    if (!o.bare) for (const [sub, role] of [["bob", "admin"], ["dan", "admin"], ["carol", o.carol ?? "member"]] as const) say("ws.member", { ws: WS, sub, lock: this.home.get(sub), role });
    if (!o.bare) for (const s of stationKeys3) say("ws.station", { ws: WS, key: s.hex });
    for (const x of setup) this.known.add(hashOf(x));
    for (const h of this.holders) this.receive(h, setup);
  }

  note(line: string) {
    this.log.push(line);
  }
  /// The list at `h` by this world's rule.
  ros(h: Holder): Roster {
    return roster(h, this.root, this.v.rule ?? "grounded");
  }
  dev(name: string): Dev3 {
    return this.devs.find((d) => d.name === name)!;
  }
  entry(h: string): Entry {
    return this.all.get(h)!;
  }
  said(e: Entry): string {
    const b = e.body as any;
    const h = hashOf(e).slice(0, 6);
    if (e.kind === "genesis") return `${b.sub}'s genesis naming ${b.device.label} #${h}`;
    const what = e.kind === "device" || e.kind === "device.remove" ? `${e.kind} ${nameOfKey(b.key)}`
      : e.kind === "ws.member" ? `ws.member ${b.sub} ${b.role} by #${String(b.lock).slice(0, 6)}`
      : e.kind === "ws.member.remove" ? `ws.member.remove ${b.sub} cancelling ${(b.cancels as string[]).map((c) => `#${c.slice(0, 6)}`).join(",") || "nothing"}`
      : e.kind.startsWith("ws.station") ? `${e.kind} ${stationName(b.key)}` : e.kind;
    return `${e.ws.slice(7)}'s log ${e.seq} ${nameOfKey(e.sig.key)}: ${what} #${h}`;
  }
  told(h: string): string {
    return this.said(this.entry(h));
  }

  // ── entries ───────────────────────────────────────────────────────────────────────────────────────────────────

  genesis(s: { base: Key; signer: Key; name: string; sub: string }): Entry {
    this.t += 1;
    const g = signed({ v: 1, ws: `person:${s.sub}`, seq: 0, prev: null, at: this.t, kind: "genesis", body: { sub: s.sub, device: personDevice(s) } }, s.signer);
    const h = hashOf(g);
    this.all.set(h, g);
    this.logOf.set(h, h);
    if (!this.logs.has(h)) this.logs.set(h, this.rulesFor(g));
    return g;
  }
  /// A person log's rules (lock-roster4-model.ts takes more kinds).
  rulesFor(g: Entry): PersonRules {
    return new PersonRules(g);
  }
  /// An entry after `parent` in its log, signed by `by` (not checked).
  make(parent: Entry, kind: string, body: unknown, by: Key, at?: number): Entry {
    if (at === undefined) this.t += 1;
    const e = signed({ v: 1, ws: parent.ws, seq: parent.seq + 1, prev: hashOf(parent), at: at ?? this.t, kind, body }, by);
    const h = hashOf(e);
    this.all.set(h, e);
    this.logOf.set(h, this.logOf.get(hashOf(parent))!);
    return e;
  }
  rulesOf(h: string): PersonRules {
    return this.logs.get(this.logOf.get(h)!)!;
  }
  chainTo(h: string): Entry[] {
    const out: Entry[] = [];
    for (let x: string | null = h; x !== null; ) {
      const e = this.entry(x);
      out.push(e);
      x = e.prev;
    }
    return out.reverse();
  }

  // ── keepers taking and choosing ──────────────────────────────────────────────────────────────────────────────

  receive(h: Holder, es: Entry[]) {
    const { changed, any } = h.take(es);
    if (any) this.refresh(h, changed);
  }

  refresh(h: Holder, changed: Set<Keeper<PersonState>>) {
    let moved = false;
    for (const k of changed) {
      const old = k.active, now = k.choose();
      let p = 0;
      while (p < old.length && p < now.length && old[p] === now[p]) p++;
      if (p === old.length && p === now.length) continue;
      moved = true;
      const dropped = old.slice(p);
      if (dropped.length > 0) {
        this.rollbacks.push(dropped.length);
        for (const x of dropped) if (this.honest.has(x)) this.inactivated.add(x);
        this.note(`  ${h.name} goes by another branch of ${k.rules.state(k.rules.gh).sub}'s log from ${this.told(old[p - 1])}: ${dropped.map((x) => this.told(x)).join("; ")} no longer active`);
      }
      k.active = now;
      k.on = new Set(now);
      k.ver++;
      for (const x of now.slice(p)) {
        const at = this.activeAt.get(x) ?? new Set<string>();
        at.add(h.name);
        this.activeAt.set(x, at);
      }
    }
    h.ver++;
    const d = this.devOf.get(h);
    if (d) {
      if (moved) this.resign(d);
      return;
    }
    const r = this.ros(h);
    const was = this.letIn.get(h)!, away = this.awayNow.get(h)!;
    for (const [k, sub] of was) {
      if (r.letIn.has(k) || THEIRS.has(k)) continue;
      const asked = this.removedKeys.has(k) || this.removedSubs.has(sub);
      this.turned.push({ at: h.name, key: k, step: this.step, asked });
      away.add(k);
      this.note(`  ${h.name} turns ${nameOfKey(k)} away${asked ? "" : ", which no honest entry took out"}`);
    }
    for (const k of r.letIn.keys()) {
      if (was.has(k)) continue;
      if (away.delete(k)) this.back++, this.note(`  ${h.name} lets ${nameOfKey(k)} in again`);
      else this.note(`  ${h.name} lets ${nameOfKey(k)} in`);
    }
    this.letIn.set(h, r.letIn);
    this.watch?.(h, r);
  }

  /// `resign=on`: each of the device's own entries no longer active, whose intent no other of its entries carries on
  /// its log's active chain, signed again after the head; where the rules refuse it there, marked void with why.
  resign(d: Dev3) {
    if (this.v.resign === "off" || d.compromised || this.resigning) return;
    this.resigning = true;
    try {
      for (const h of [...d.mine]) {
        const k = d.h.logs.get(this.logOf.get(h)!)!;
        if (d.superseded.has(h) || k.on.has(h)) continue;
        const it = this.intents.get(this.honest.get(h)!)!;
        d.superseded.add(h);
        if (it.hashes.some((x) => k.on.has(x)) || it.void !== null) continue;
        const again = this.sign(d, it.kind, it.body, { log: it.log, bring: true });
        if (typeof again === "string") {
          it.void = again;
          this.note(`  ${d.name} cannot sign ${this.told(h)} again after its head (${again}): marked not in effect`);
        } else this.resigned++;
      }
    } finally {
      this.resigning = false;
    }
  }

  // ── lines ────────────────────────────────────────────────────────────────────────────────────────────────────

  /// What `from` gives `to` in a sync: its active chains, less what `to` has.
  offer(from: Holder, to: Holder): Entry[] {
    return from.offered().filter((e) => !to.has(hashOf(e)));
  }
  send(from: Holder, to: Holder) {
    const es = this.offer(from, to);
    if (es.length === 0) return;
    const m = { to, entries: es };
    this.queue.push(m);
    this.sent.push(m);
    for (const e of es) this.known.add(hashOf(e));
  }
  land(i: number) {
    const [m] = this.queue.splice(i, 1);
    this.receive(m.to, m.entries);
  }
  /// Every holder syncs with every other at once until none stores anything new (`skip`: cut off).
  level(skip: Set<Holder> = new Set(), rounds = 200): boolean {
    for (let r = 0; r < rounds; r++) {
      let any = false;
      for (const a of this.holders) {
        if (skip.has(a)) continue;
        for (const b of this.holders) {
          if (a === b || skip.has(b)) continue;
          const pair = `${a.name}>${b.name}`, now = `${a.ver}|${b.ver}`;
          if (this.levelled.get(pair) === now) continue;
          const es = this.offer(a, b);
          if (es.length > 0) {
            for (const e of es) this.known.add(hashOf(e));
            const { changed, any: got } = b.take(es);
            if (got) this.refresh(b, changed), (any = true);
          }
          this.levelled.set(pair, `${a.ver}|${b.ver}`);
        }
      }
      if (!any) return true;
    }
    return false;
  }
  finish(): boolean {
    this.note("end: everything on its way lands, every keeper syncs with every other");
    while (this.queue.length > 0) this.land(this.rng.int(this.queue.length));
    return this.level();
  }

  // ── honest devices ───────────────────────────────────────────────────────────────────────────────────────────

  /// A device signs after its log's head (or `parent`) and, with `bring`, sends it to every station; why the rules
  /// refuse it there instead.
  sign(d: Dev3, kind: string, body: unknown, o: { parent?: string; bring?: boolean; log?: string } = {}): Entry | string {
    const log = o.log ?? d.log;
    const k = d.h.logs.get(log);
    if (!k) return "its device holds no such lock";
    const parent = o.parent ?? k.head();
    const e = this.make(this.entry(parent), kind, body, d.signer);
    const why = this.rulesOf(parent).why(e);
    if (why !== null) return why;
    const h = hashOf(e);
    const intent = `${d.name}|${log}|${kind}|${canonical(body ?? null)}`;
    this.honest.set(h, intent);
    const it = this.intents.get(intent) ?? { dev: d, hashes: [], void: null, kind, body, log, step: this.step };
    it.hashes.push(h);
    this.intents.set(intent, it);
    d.mine.push(h);
    if (kind === "device.remove") {
      const gone = (body as { key: string }).key;
      if (!this.removedKeys.has(gone)) this.removedKeys.set(gone, this.step);
      const taken = this.devs.find((x) => x.signer.id === gone && x.kind === "phone");
      if (taken && this.family === "faults") taken.compromised = true;
    }
    if (kind === "ws.member.remove") this.removedSubs.add((body as { sub: string }).sub);
    this.note(`  ${d.name} signs ${this.said(e)}`);
    this.receive(d.h, [e]);
    if (kind.startsWith("ws.")) this.atSigning.set(h, effect(this.ros(d.h), it, h));
    if (o.bring !== false) for (const s of this.stations) this.send(d.h, s);
    return e;
  }

  /// The `ws.member` entries about `sub` that `h` stores: what a removal by its device names.
  seen(h: Holder, sub: string): string[] {
    return h.stored().filter((e) => e.kind === "ws.member" && e.body.sub === sub && e.body.ws === WS).map(hashOf).sort();
  }
  seenStations(h: Holder, key: string): string[] {
    return h.stored().filter((e) => e.kind === "ws.station" && e.body.key === key && e.body.ws === WS).map(hashOf).sort();
  }

  /// What a device signs next, as drawn; null where there is nothing it would sign.
  honestOp(d: Dev3, b: number, c: number): { kind: string; body: unknown } | null {
    const k = d.h.logs.get(d.log);
    if (!k) return null;
    const s = k.headState();
    if (!s.devices.has(d.signer.id)) return null;
    const r = this.ros(d.h);
    const mine = r.pairs.get(`${d.sub}|${d.log}`);
    const phone = this.devs.find((x) => x.sub === d.sub && x.kind === "phone");
    switch (b % 12) {
      case 0: case 1: case 2:
        return phone && !s.devices.has(phone.signer.id) && !this.removedKeys.has(phone.signer.id) ? { kind: "device", body: personDevice(phone) } : null;
      case 3: case 4:
        return phone && phone !== d && s.devices.has(phone.signer.id) ? { kind: "device.remove", body: { key: phone.signer.id } } : null;
      case 5: case 6: {
        if (!manages(mine)) return null;
        const sub = (["bob", "dan", "carol", "xena"] as const)[c % 4];
        if (sub === d.sub) return null;
        const m = r.members.get(sub);
        const role: Role3 = m === undefined ? "member" : m.role === "admin" ? "member" : "admin";
        return { kind: "ws.member", body: { ws: WS, sub, lock: this.home.get(sub), role } };
      }
      case 7: {
        if (!manages(mine)) return null;
        const sub = (["bob", "dan", "carol", "xena"] as const)[c % 4];
        if (sub === d.sub || !r.members.has(sub)) return null;
        return { kind: "ws.member.remove", body: { ws: WS, sub, cancels: this.seen(d.h, sub) } };
      }
      case 8: {
        if (!manages(mine)) return null;
        const st = stationKeys3[2].hex;
        return r.stations.has(st) ? { kind: "ws.station.remove", body: { ws: WS, key: st, cancels: this.seenStations(d.h, st) } } : { kind: "ws.station", body: { ws: WS, key: st } };
      }
      default:
        return null;
    }
  }

  // ── a revoked key ────────────────────────────────────────────────────────────────────────────────────────────

  /// The parents in `d`'s log a revoked key may sign after: what it knows in which it is a device of that log.
  attackParents(d: Dev3, log = d.log): string[] {
    const rules = this.logs.get(log)!;
    const hs = new Set([...this.known, ...(d.h.logs.get(log)?.store.keys() ?? [])]);
    return [...hs].filter((h) => this.logOf.get(h) === log && rules.states.get(h)?.devices.has(d.signer.id) === true)
      .sort((x, y) => rules.depth(x) - rules.depth(y) || (x < y ? -1 : 1));
  }

  /// The revoked key of `d` signs after `parent`: its accomplice put in (`device`), mallory admitted as an admin
  /// (`admit`), or `sub` removed naming `cancels` (`cancel`). Null where the rules refuse it.
  attackSign(d: Dev3, parent: string, y: "device" | "admit" | "cancel", o: { sub?: string; cancels?: string[] } = {}): Entry | null {
    const acc = ACCOMPLICE[PEOPLE3.indexOf(d.sub as never)];
    const body = y === "device" ? personDevice(acc)
      : y === "admit" ? { ws: WS, sub: "mallory", lock: this.home.get("mallory"), role: "admin" }
      : { ws: WS, sub: o.sub, cancels: o.cancels ?? [] };
    const kind = y === "device" ? "device" : y === "admit" ? "ws.member" : "ws.member.remove";
    const e = this.make(this.entry(parent), kind, body, d.signer);
    if (!this.rulesOf(parent).valid(e)) return null;
    this.attack.set(hashOf(e), d);
    this.note(`  ${d.name}'s key, revoked, signs ${this.said(e)} after ${this.told(parent)}`);
    return e;
  }

  /// What a revoked key signed, with its chain and mallory's genesis (who else would bring it), straight to `to`.
  reach(e: Entry, to: Holder[]) {
    const chain = [...this.chainTo(hashOf(e)), this.entry(this.home.get("mallory")!)];
    for (const x of chain) this.known.add(hashOf(x));
    for (const h of to) {
      this.note(`  it reaches ${h.name}`);
      this.receive(h, chain);
    }
  }

  /// The admits about `sub` a revoked key of `d` can name: every one that went over a line.
  knownAdmits(_d: Dev3, sub: string): string[] {
    return [...this.known].filter((h) => this.entry(h).kind === "ws.member" && this.entry(h).body.sub === sub).sort();
  }
  /// What a keeper's list is, in words: what two keepers compare.
  stateSaid(h: Holder): string {
    return rosterSaid(this.ros(h));
  }
  /// The keepers whose lists are compared for agreement: every holder (lock-roster4-model.ts: those the workspace has).
  comparable(): Holder[] {
    return this.holders;
  }
  /// Whether statement `x` is in force at `h`: on its log's active chain (lock-roster4-model.ts: and its body there).
  stands(h: Holder, x: string): boolean {
    return h.logs.get(this.logOf.get(x)!)?.on.has(x) === true;
  }
  /// The list at every holder compared with a fresh holder's given the same entries, shuffled (A1).
  sameEntries(): { checks: number; mismatch: number } {
    return sameEntries(this);
  }

  // ── a drawn world ────────────────────────────────────────────────────────────────────────────────────────────

  run(steps: Step[]) {
    for (const [n, st] of steps.entries()) {
      this.step = n;
      const kind = KINDS3[st.k];
      const fault = kind === "drop" || kind === "replay" || kind === "forge" || kind === "stale";
      if (fault && this.family === "free") continue;
      this.note(`${n}: ${kind}`);
      switch (kind) {
        case "deliver":
          if (this.queue.length > 0) this.land(st.a % this.queue.length);
          break;
        case "sign": case "pend": {
          const d = this.devs[st.a % this.devs.length];
          if (d.compromised) break;
          const op = this.honestOp(d, st.b, st.c);
          if (op) this.sign(d, op.kind, op.body, { bring: kind === "sign" });
          break;
        }
        case "sync": {
          const a = this.holders[st.a % this.holders.length], b = this.holders[st.b % this.holders.length];
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
          // A relay's entry after a holder's head of alice's log: mallory admitted as an owner, signed by a key not on
          // the log, or by none (alice's app's key named over another entry's signature).
          const to = this.holders[st.a % this.holders.length];
          const k = to.logs.get(this.root)!;
          const head = this.entry(k.head());
          const body = { ws: WS, sub: "mallory", lock: this.home.get("mallory"), role: "owner" };
          let f = this.make(head, "ws.member", body, eveKey);
          if (st.b % 2 === 1) {
            const other = this.make(head, "ws.member", { ...body, role: "member" }, spec("alice's app").signer);
            f = { ...f, sig: other.sig };
            this.all.set(hashOf(f), f);
          }
          this.forged.add(hashOf(f));
          this.queue.push({ to, entries: [f, this.entry(this.home.get("mallory")!)] });
          this.note(`  a relay forges an entry for ${to.name}`);
          break;
        }
        case "stale": {
          const taken = this.devs.filter((d) => d.compromised);
          if (taken.length === 0) break;
          const d = taken[st.a % taken.length];
          const ps = this.attackParents(d);
          if (ps.length === 0) break;
          const y = (["device", "admit", "cancel"] as const)[st.b % 3];
          const sub = (["bob", "dan", "carol"] as const)[(st.b >> 2) % 3];
          const known = this.knownAdmits(d, sub);
          const e = this.attackSign(d, ps[st.c % ps.length], y, { sub, cancels: known });
          if (e === null) break;
          const to = this.holders[(st.a >> 4) % this.holders.length];
          const chain = [...this.chainTo(hashOf(e)), this.entry(this.home.get("mallory")!)].filter((x) => !to.has(hashOf(x)));
          for (const x of chain) this.known.add(hashOf(x));
          this.queue.push({ to, entries: chain });
          this.note(`  on its way to ${to.name}`);
          break;
        }
      }
    }
    this.step = steps.length;
  }
}

/// One step of a drawn world: its kind and three numbers it picks with. `pend`: a device signs and holds it, bringing
/// it only when it next syncs.
export type Step = { k: number; a: number; b: number; c: number };
const KINDS3 = ["deliver", "deliver", "deliver", "deliver", "deliver", "deliver", "sign", "sign", "pend", "pend", "sync", "sync", "sync", "drop", "replay", "forge", "stale"] as const;
export const drawSteps3 = (seed: number, n: number): Step[] => {
  const r = new Rng(seed * 7919 + 13);
  return Array.from({ length: n }, () => ({ k: r.int(KINDS3.length), a: r.int(1 << 16), b: r.int(1 << 16), c: r.int(1 << 16) }));
};

// ── what a drawn world measured ─────────────────────────────────────────────────────────────────────────────────────

/// How each honest intent ended (B1): in force at every keeper (and, for a statement, whether the list took it), marked
/// to its signer as not in effect (why), its device taken out of its log (by its person: they know), or none of these.
export type Outcomes = { inForce: number; noEffect: Record<string, number>; void: Record<string, number>; removedDev: number; lost: number; toldAtSigning: Record<string, number> };

export type Measured3 = {
  rested: boolean;
  /// Every holder computes the same list (members, stations, keys let in) in the end; every log one head.
  agree: boolean;
  heads: boolean;
  /// Holders whose list differs from a fresh holder's given the same entries in another order (A1), checked at four
  /// points of the world and at its end; how many such checks.
  sameMismatch: number;
  sameChecks: number;
  /// A revoked key's: statement in force at a holder in the end; accomplice let in; mallory in a list; a removed key
  /// let in. The most holders one of its entries was ever active at.
  attackInForce: boolean;
  accomplice: boolean;
  mallory: boolean;
  removedIn: boolean;
  attackAtMax: number;
  attacks: number;
  outcomes: Outcomes;
  intents: number;
  inactivated: number;
  honest: number;
  turnedUnasked: number;
  turnedAsked: number;
  back: number;
  forgedStored: boolean;
  rollbacks: number[];
};

/// What a statement in force did to the list at `r`: null where it took effect, else why not.
export function effect(r: Roster, it: Pick<Intent, "kind" | "body" | "log"> & { dev: { sub: string } }, h: string): string | null {
  const sub = it.dev.sub, pair = r.pairs.get(`${sub}|${it.log}`), p1 = r.step1.get(`${sub}|${it.log}`);
  // (by the rule the list was worked out by: until 2026-11-13 by whether it had labels, and a grounded list with no admit
  // and no cancellation, which a keeper of the fourth round lacking the bodies of every admit has, was told by steps
  // 1-4's reasons, "its signer is no candidate" for a removal that names nothing in force; rules-fork.test.ts found it)
  if (r.rule === "grounded") {
    const mine = `${sub}|${it.log}`;
    if (it.kind === "ws.member") {
      const l = r.labels.get(`a:${h}`);
      if (l === "undec") return r.undecided.has(mine) ? "its signer is undecided (a circle of removals)" : "the admit is undecided (named by an undecided removal)";
      if (l === "out") {
        if (r.cancelled.has(h)) return "admit cancelled";
        if (pair === undefined || !manages(pair)) return r.undecided.has(mine) ? "its signer is undecided (a circle of removals)" : "its signer is not in the list";
        return "its signer may not give that role";
      }
      const bound = r.members.get(it.body.sub);
      if (bound && (bound.role !== it.body.role || bound.lock !== it.body.lock)) return "another admit of the person outranks it (a lower role given later changes nothing)";
      return null;
    }
    if (it.kind === "ws.member.remove") {
      const cs = [...r.labels].filter(([id]) => id.startsWith(`c:${h}|`));
      if (cs.some(([, l]) => l === "in")) return null;
      if (cs.some(([, l]) => l === "undec")) return "its cancellations are undecided (a circle of removals)";
      if (cs.length > 0) return manages(pair) ? "it may cancel none of what it names" : r.undecided.has(mine) ? "its signer is undecided (a circle of removals)" : "its signer is not in the list";
      return null;
    }
    // (a station's statement whose signer a circle of removals leaves undecided is said so, as an admit's is: told
    // "not in the list" until 2026-11-12, when the rules written from this model said otherwise)
    if (it.kind.startsWith("ws.station") && !manages(pair)) return r.undecided.has(mine) ? "its signer is undecided (a circle of removals)" : "its signer is not in the list";
    return null;
  }
  if (it.kind === "ws.member") {
    if (r.cancelled.has(h)) return "admit cancelled";
    if (pair === undefined) return "its signer is not in the list";
    if (!mayGive(pair, it.body.role)) return "its signer may not give that role";
    const bound = r.members.get(it.body.sub);
    if (bound && (bound.role !== it.body.role || bound.lock !== it.body.lock)) return "another admit of the person outranks it (a lower role given later changes nothing)";
    return null;
  }
  if (it.kind === "ws.member.remove") {
    if (!manages(p1)) return "its signer is no candidate";
    const named = (it.body.cancels as string[]).filter((c) => r.admits.some((a) => a.h === c));
    if (named.length > 0 && !named.some((c) => r.cancelled.has(c))) return "it may cancel none of what it names";
    return null;
  }
  if (it.kind.startsWith("ws.station") && !manages(it.kind === "ws.station" ? pair : p1)) return "its signer is not in the list";
  return null;
}

/// The world's list at every holder compared with a fresh holder's given the same entries, shuffled.
function sameEntries(w: World3): { checks: number; mismatch: number } {
  let mismatch = 0;
  for (const h of w.holders) {
    const fresh = new Holder(`${h.name}'`, w);
    const es = h.stored();
    for (let i = es.length - 1; i > 0; i--) {
      const j = w.rng.int(i + 1);
      [es[i], es[j]] = [es[j], es[i]];
    }
    // (as delivered: one batch at a time, in that order)
    for (let i = 0; i < es.length; i += 7) {
      const { changed } = fresh.take(es.slice(i, i + 7));
      for (const k of changed) (k.active = k.choose()), (k.on = new Set(k.active));
    }
    // (what was not taken for want of its parent, once more: a holder takes the rest as its parents come)
    for (let again = 0; again < 30; again++) {
      const { changed, any } = fresh.take(es);
      for (const k of changed) (k.active = k.choose()), (k.on = new Set(k.active));
      if (!any) break;
    }
    if (w.stateSaid(fresh) !== w.stateSaid(h)) mismatch++;
  }
  return { checks: w.holders.length, mismatch };
}

export function drawn3(seed: number, v: V3v, family: Family, steps: Step[], mk: Make3 = make3): { w: World3; m: Measured3 } {
  const w = mk(seed, v, family);
  let checks = 0, mismatch = 0;
  for (let q = 0; q < 4; q++) {
    w.run(steps.slice(Math.floor((q * steps.length) / 4), Math.floor(((q + 1) * steps.length) / 4)));
    const s = w.sameEntries();
    checks += s.checks;
    mismatch += s.mismatch;
  }
  const rested = w.finish();
  const s = w.sameEntries();
  checks += s.checks;
  mismatch += s.mismatch;
  const rosters = w.holders.map((h) => w.ros(h));
  const agree = new Set(w.comparable().map((h) => w.stateSaid(h))).size === 1;
  const heads = [...w.logs.keys()].every((g) => new Set(w.holders.filter((h) => h.logs.has(g)).map((h) => h.logs.get(g)!.head())).size <= 1);
  const accKeys = new Set(ACCOMPLICE.map((a) => a.signer.id));
  const removedIn = rosters.some((r) => [...r.letIn.keys()].some((k) => w.removedKeys.has(k)));
  const out: Outcomes = { inForce: 0, noEffect: {}, void: {}, removedDev: 0, lost: 0, toldAtSigning: {} };
  const r0 = rosters[0];
  for (const it of w.intents.values()) {
    const everywhere = it.hashes.find((h) => w.holders.every((x) => x.logs.get(it.log)?.on.has(h) === true));
    if (everywhere !== undefined) {
      const why = effect(r0, it, everywhere);
      if (why === null) out.inForce++;
      else {
        out.noEffect[why] = (out.noEffect[why] ?? 0) + 1;
        if (it.hashes.some((x) => typeof w.atSigning.get(x) === "string")) out.toldAtSigning[why] = (out.toldAtSigning[why] ?? 0) + 1;
      }
    } else if (it.void !== null) out.void[it.void] = (out.void[it.void] ?? 0) + 1;
    else if (w.removedKeys.has(it.dev.signer.id)) out.removedDev++;
    else out.lost++;
  }
  const m: Measured3 = {
    rested, agree, heads, sameMismatch: mismatch, sameChecks: checks,
    attackInForce: w.holders.some((h) => [...w.attack.keys()].some((x) => h.logs.get(w.logOf.get(x)!)?.on.has(x) === true)),
    accomplice: rosters.some((r) => [...r.letIn.keys()].some((k) => accKeys.has(k))),
    mallory: rosters.some((r) => r.members.has("mallory")),
    removedIn,
    attackAtMax: Math.max(0, ...[...w.attack.keys()].map((h) => w.activeAt.get(h)?.size ?? 0)),
    attacks: w.attack.size,
    outcomes: out,
    intents: w.intents.size,
    inactivated: w.inactivated.size,
    honest: w.honest.size,
    turnedUnasked: w.turned.filter((t) => !t.asked).length,
    turnedAsked: w.turned.filter((t) => t.asked).length,
    back: w.back,
    forgedStored: w.holders.some((h) => [...w.forged].some((x) => h.has(x))),
    rollbacks: [...w.rollbacks],
  };
  return { w, m };
}

export const PROPS3: { name: string; bad: (m: Measured3) => boolean }[] = [
  { name: "keepers' lists differ in the end", bad: (m) => !m.agree || !m.heads },
  { name: "the same entries give another list", bad: (m) => m.sameMismatch > 0 },
  { name: "a revoked key's statement or accomplice holds in the end", bad: (m) => m.attackInForce || m.accomplice || m.mallory || m.removedIn },
  { name: "an honest intent silently lost", bad: (m) => m.outcomes.lost > 0 },
  { name: "a statement in force everywhere without effect", bad: (m) => Object.keys(m.outcomes.noEffect).length > 0 },
  { name: "a device let in, then turned away unasked", bad: (m) => m.turnedUnasked > 0 },
];

export function shrink3(seed: number, v: V3v, family: Family, steps: Step[], bad: (m: Measured3) => boolean, mk: Make3 = make3): Step[] {
  let now = steps;
  let tries = 0;
  for (let size = Math.floor(now.length / 2); size >= 1; size = Math.floor(size / 2)) {
    for (let at = 0; at + size <= now.length && tries < 250; tries++) {
      const less = [...now.slice(0, at), ...now.slice(at + size)];
      if (bad(drawn3(seed, v, family, less, mk).m)) now = less;
      else at += size;
    }
  }
  return now;
}

// ── the agreement with the product's rules (`personFold`) ───────────────────────────────────────────────────────────

/// For every entry a world made whose chain has only the product's kinds (and for three changed copies of each: signed
/// by a key not on the log, one place too far, its signer removing itself): whether the model's rules and `personFold`
/// say the same (taken or not, and the devices after). Chains with a `ws.*` entry: whether `personFold` refuses them.
/// The kinds the product's person logs take (`personFold`): every other is the model's.
const PRODUCT_KINDS = new Set(["genesis", "device", "device.remove"]);

export function foldCheck(seeds: number, steps: number, mk: Make3 = make3): { compared: number; differ: string[]; wsChains: number; wsRefused: number; wsWhy: string[] } {
  const out = { compared: 0, differ: [] as string[], wsChains: 0, wsRefused: 0, wsWhy: [] as string[] };
  for (let seed = 1; seed <= seeds; seed++) {
    const { w } = drawn3(seed, V3[1], "faults", drawSteps3(seed, steps), mk);
    const entries = [...w.all.values()].filter((e) => e.prev !== null);
    for (const e of entries) {
      const parent = e.prev!;
      const rules = w.rulesOf(parent);
      if (!rules.states.has(parent)) continue;
      const chain = w.chainTo(parent);
      const sub = rules.sub;
      if (chain.some((x) => !PRODUCT_KINDS.has(x.kind))) continue;
      if (!PRODUCT_KINDS.has(e.kind)) {
        if (out.wsChains < 400) {
          out.wsChains++;
          try {
            personFold([...chain, e], sub);
          } catch (err) {
            out.wsRefused++;
            const why = (err as Error).message;
            if (!out.wsWhy.includes(why)) out.wsWhy.push(why);
          }
        }
        continue;
      }
      const ps = rules.state(parent);
      const signerKey = SPECS.find((s) => s.signer.id === e.sig.key)?.signer ?? ACCOMPLICE.find((s) => s.signer.id === e.sig.key)?.signer;
      // (the copies at another `at`, so that each has a hash of its own)
      const mutants = [e, w.make(w.entry(parent), e.kind, e.body, eveKey, e.at + 1000)];
      if (signerKey) {
        const { sig: _, ...bare } = e;
        const far = signed({ ...bare, seq: e.seq + 1, at: e.at + 2000 }, signerKey);
        w.all.set(hashOf(far), far), w.logOf.set(hashOf(far), rules.gh);
        mutants.push(far);
        if (ps.devices.has(signerKey.id)) mutants.push(w.make(w.entry(parent), "device.remove", { key: signerKey.id }, signerKey, e.at + 3000));
      }
      for (const x of mutants) {
        out.compared++;
        const mine = rules.why(x);
        let theirs: string | null = null, devices: string[] = [];
        try {
          devices = personFold([...chain, x], sub).devices.map((d) => d.key).sort();
        } catch (err) {
          theirs = (err as Error).message;
        }
        const same = (mine === null) === (theirs === null) && (mine !== null || [...rules.state(hashOf(x)).devices.keys()].sort().join() === devices.join());
        if (!same && out.differ.length < 10) out.differ.push(`seed ${seed}: ${w.said(x)}: model ${mine ?? "takes it"}, personFold ${theirs ?? `takes it (${devices.length} devices)`}`);
      }
    }
  }
  return out;
}

// ── A2: a revoked key of an admin's log signing statements ──────────────────────────────────────────────────────────

/// `n` honest entries of bob's app on bob's log, everyone level after each: its laptop put in or taken out, the third
/// station admitted or cancelled, xena admitted or her role changed. (The first rounds' prefix, in one person's log.)
function prefix3(w: World3, d: Dev3, n: number) {
  const laptop = spec(`${d.sub}'s laptop`);
  for (let i = 0, guard = 0; i < n && guard < 20 * n + 20; guard++) {
    const k = d.h.logs.get(d.log)!;
    const s = k.headState(), r = w.ros(d.h);
    const x = w.rng.int(10);
    const st = stationKeys3[2].hex;
    const op = x < 4 ? (s.devices.has(laptop.signer.id) ? null : { kind: "device", body: personDevice(laptop) })
      : x < 7 ? (s.devices.has(laptop.signer.id) ? { kind: "device.remove", body: { key: laptop.signer.id } } : null)
      : x < 8 ? (r.stations.has(st) ? { kind: "ws.station.remove", body: { ws: WS, key: st, cancels: w.seenStations(d.h, st) } } : { kind: "ws.station", body: { ws: WS, key: st } })
      : { kind: "ws.member", body: { ws: WS, sub: "xena", lock: w.home.get("xena"), role: r.members.get("xena")?.role === "member" ? "admin" : "member" } };
    if (op === null || typeof w.sign(d, op.kind, op.body, { bring: false }) === "string") continue;
    w.level();
    i++;
  }
}

export type A2Out = { inForceEnd: boolean; changedEnd: boolean; phoneEnd: boolean; before: number; changedBefore: number; ever: number; entries: number; log: string[] };

/// bob's app takes bob's phone out of bob's log while one station is cut off; the phone's key signs `y` (mallory
/// admitted as an admin; carol removed, naming alice's admit of her; or, the first round's case a, its accomplice put
/// in) after the removal's parent (`same`) or a parent it was trusted in (`any`), and brings it to the cut station (and,
/// on odd seeds, one device); then every keeper syncs.
export function a2(seed: number, v: V3v, y: "admit" | "cancel" | "device", parent: "same" | "any", mk: Make3 = make3): A2Out {
  const w = mk(seed, v, "free");
  const B = w.dev("bob's app"), P = w.dev("bob's phone");
  prefix3(w, B, w.rng.int(5));
  w.sign(B, "device", personDevice(P), { bring: false });
  w.level();
  prefix3(w, B, w.rng.int(8));
  const cut = w.stations[w.rng.int(3)];
  w.note(`${cut.name} is cut off`);
  const r = w.sign(B, "device.remove", { key: P.signer.id }, { bring: false }) as Entry;
  w.level(new Set([cut]));
  P.compromised = true;
  const X = r.prev!;
  const parents = w.attackParents(P).filter((h) => w.logs.get(B.log)!.depth(h) <= w.logs.get(B.log)!.depth(X));
  const p = parent === "same" ? X : parents[w.rng.int(parents.length)];
  const e = w.attackSign(P, p, y, { sub: "carol", cancels: w.seen(cut, "carol") })!;
  const changed = (h: Holder) => {
    const ro = w.ros(h);
    return y === "admit" ? ro.members.has("mallory") : y === "cancel" ? !ro.members.has("carol") : ro.letIn.has(ACCOMPLICE[1].signer.id);
  };
  w.reach(e, [cut, ...(seed % 2 === 1 ? [w.devs[w.rng.int(w.devs.length)].h] : [])]);
  const at = (h: Holder) => h.logs.get(B.log)?.on.has(hashOf(e)) === true;
  const before = w.holders.filter(at).length, changedBefore = w.holders.filter((h) => at(h) && changed(h)).length;
  w.note(`${cut.name} is back: every keeper syncs with every other`);
  w.level();
  return { inForceEnd: w.holders.some(at), changedEnd: w.comparable().some(changed), phoneEnd: w.stations.some((h) => w.ros(h).letIn.has(P.signer.id)), before, changedBefore, ever: w.activeAt.get(hashOf(e))?.size ?? 0, entries: w.all.size, log: w.log };
}

// ── A3: concurrent statements by different people, fault-free ──────────────────────────────────────────────────────

export const A3_NAMES = ["i: bob admits xena, dan removes her", "ii: bob makes xena admin, dan makes her member", "iii: bob removes dan, dan removes bob", "iv: alice removes bob, bob admits xena", "v: bob admits xena; later alice removes bob", "v+adopt: as v, alice first admits whom bob admitted", "vi: bob removes dan; dan, having seen it, removes bob", "vii: bob, dan and carol (admins) each remove the next at once"] as const;
export type A3Out = { end: string[]; agree: boolean; xenaFlap: boolean; xenaBack: boolean; xenaInEnd: boolean; otherFlap: string[]; log: string[] };

/// Statements signed at once by different devices, each brought first to a station the seed draws, then deliveries and
/// syncs the seed draws, then every keeper syncs. What each station let in and turned away on the way, the lists in
/// the end.
export function a3(seed: number, v: V3v, which: (typeof A3_NAMES)[number], mk: Make3 = make3): A3Out {
  const w = mk(seed, v, "free", which.startsWith("vii:") ? { carol: "admin" } : {});
  const A = w.dev("alice's app"), B = w.dev("bob's app"), D = w.dev("dan's app"), C = w.dev("carol's app");
  const X = w.home.get("xena")!;
  const admit = (by: Dev3, sub: string, role: Role3) => w.sign(by, "ws.member", { ws: WS, sub, lock: w.home.get(sub), role }, { bring: false }) as Entry;
  const remove = (by: Dev3, sub: string) => w.sign(by, "ws.member.remove", { ws: WS, sub, cancels: w.seen(by.h, sub) }, { bring: false }) as Entry;
  const spread = (es: Entry[]) => {
    for (const e of es) w.queue.push({ to: w.stations[w.rng.int(3)], entries: [e] });
    for (let i = 0; i < 40; i++) {
      if (w.rng.int(3) === 0 && w.queue.length > 0) w.land(w.rng.int(w.queue.length));
      else {
        const a = w.holders[w.rng.int(w.holders.length)], b = w.holders[w.rng.int(w.holders.length)];
        if (a !== b) w.send(a, b), w.send(b, a);
      }
    }
    w.finish();
  };
  w.note(`xena's lock is #${X.slice(0, 6)}`);
  if (which.startsWith("i:")) {
    admit(A, "xena", "member");
    w.level();
    spread([admit(B, "xena", "member"), remove(D, "xena")]);
  } else if (which.startsWith("ii:")) {
    spread([admit(B, "xena", "admin"), admit(D, "xena", "member")]);
  } else if (which.startsWith("iii:")) {
    spread([remove(B, "dan"), remove(D, "bob")]);
  } else if (which.startsWith("vi:")) {
    w.sign(B, "ws.member.remove", { ws: WS, sub: "dan", cancels: w.seen(B.h, "dan") });
    w.finish();
    spread([remove(D, "bob")]);
  } else if (which.startsWith("vii:")) {
    spread([remove(B, "dan"), remove(D, "carol"), remove(C, "bob")]);
  } else if (which.startsWith("iv:")) {
    spread([remove(A, "bob"), admit(B, "xena", "member")]);
  } else {
    w.sign(B, "ws.member", { ws: WS, sub: "xena", lock: X, role: "member" });
    w.finish();
    const out: Entry[] = [];
    if (which.startsWith("v+adopt")) out.push(admit(A, "xena", "member"));
    out.push(remove(A, "bob"));
    spread(out);
  }
  const xk = spec("xena's app").signer.id;
  const end = w.holders.map((h) => `${h.name}: ${rosterSaid(w.ros(h))}`);
  return {
    end, agree: new Set(w.comparable().map((h) => w.stateSaid(h))).size === 1,
    xenaFlap: w.turned.some((t) => t.key === xk), xenaBack: w.log.some((l) => l.includes("lets xena's app in again")),
    xenaInEnd: w.stations.every((s) => w.ros(s).letIn.has(xk)),
    otherFlap: [...new Set(w.turned.filter((t) => t.key !== xk).map((t) => nameOfKey(t.key)))],
    log: w.log,
  };
}

// ── A4: re-binding a person to a new log ────────────────────────────────────────────────────────────────────────────

export type A4Y = "none" | "device" | "admit" | "cancel new" | "cancel adopt";
export type A4Out = {
  /// An old-log device let in at a holder where both statements were in force, ever (the property's first half).
  oldWhileBoth: boolean;
  /// In the end: an old-log device (or its accomplice) let in anywhere; the new device O let in at every station; mallory
  /// in a list; xena (whom carol's old log admitted) in every list.
  oldEnd: boolean;
  newEnd: boolean;
  malloryEnd: boolean;
  xenaEnd: boolean | null;
  /// The cut station, just before it was back: lets an old device in, lets O in.
  cutOld: boolean;
  cutNew: boolean;
  /// What the revoked key's entry changed in the end, in words.
  end: string;
  log: string[];
};

/// carol was admitted by alice as `role`, her old log holding her app and her phone (as an admin she admitted xena from
/// it). Her laptop O begins a new log; one station is cut off; (`adopt`: bob first admits again whom carol admitted);
/// bob, an admin, signs `ws.member.remove` naming the admits of carol he stored and `ws.member` binding carol to the new
/// log. Then carol's phone's key, revoked by that, signs `y` on the old log after its head (its accomplice; mallory as
/// an admin; carol's removal cancelling bob's new admit; xena's removal cancelling the adopt) and brings it to the cut
/// station and one other keeper; the cut station comes back.
export function a4(seed: number, v: V3v, role: "member" | "admin", y: A4Y, adopt: boolean, mk: Make3 = make3): A4Out {
  const w = mk(seed, v, "free", { laptops: true, carol: role });
  const C = w.dev("carol's app"), P = w.dev("carol's phone"), O = w.dev("carol's laptop"), B = w.dev("bob's app");
  w.sign(C, "device", personDevice(P));
  w.level();
  if (role === "admin") w.sign(C, "ws.member", { ws: WS, sub: "xena", lock: w.home.get("xena"), role: "member" }), w.level();
  const old = C.log;
  const oldKeys = new Set([C.signer.id, P.signer.id, ACCOMPLICE[3].signer.id]);
  const cut = w.stations[w.rng.int(3)];
  const skip = new Set([cut]);
  w.note(`${cut.name} is cut off`);
  const g2 = w.genesis(O);
  O.log = hashOf(g2);
  w.receive(O.h, [g2]);
  w.level(skip);
  let adoptE: Entry | null = null;
  if (adopt && role === "admin") adoptE = w.sign(B, "ws.member", { ws: WS, sub: "xena", lock: w.home.get("xena"), role: "member" }, { bring: false }) as Entry;
  const rm = w.sign(B, "ws.member.remove", { ws: WS, sub: "carol", cancels: w.seen(B.h, "carol") }, { bring: false }) as Entry;
  const nw = w.sign(B, "ws.member", { ws: WS, sub: "carol", lock: O.log, role }, { bring: false }) as Entry;
  let oldWhileBoth = false;
  w.watch = (h, r) => {
    const k = h.logs.get(B.log);
    if (k && w.stands(h, hashOf(rm)) && w.stands(h, hashOf(nw)) && [...r.letIn.keys()].some((x) => oldKeys.has(x))) oldWhileBoth = true;
  };
  w.level(skip);
  P.compromised = true;
  if (y !== "none") {
    const head = w.attackParents(P, old).at(-1)!;
    const e = y === "cancel new" ? w.attackSign(P, head, "cancel", { sub: "carol", cancels: [hashOf(nw)] })
      : y === "cancel adopt" ? w.attackSign(P, head, "cancel", { sub: "xena", cancels: adoptE ? [hashOf(adoptE)] : w.seen(P.h, "xena") })
      : w.attackSign(P, head, y);
    if (e) w.reach(e, [cut, w.holders.filter((h) => h !== cut && h !== P.h)[w.rng.int(w.holders.length - 2)]]);
  }
  const cr = w.ros(cut);
  const cutOld = [...cr.letIn.keys()].some((x) => oldKeys.has(x)), cutNew = cr.letIn.has(O.signer.id);
  w.note(`${cut.name} is back: every keeper syncs with every other`);
  w.level();
  const rs = w.comparable().map((h) => w.ros(h));
  const st = w.stations.map((h) => w.ros(h));
  return {
    oldWhileBoth, oldEnd: rs.some((r) => [...r.letIn.keys()].some((x) => oldKeys.has(x))), newEnd: st.every((r) => r.letIn.has(O.signer.id)),
    malloryEnd: rs.some((r) => r.members.has("mallory")), xenaEnd: role === "admin" ? rs.every((r) => r.members.has("xena")) : null,
    cutOld, cutNew, end: rosterSaid(st[0]), log: w.log,
  };
}

/// M is the root: alice's app and phone are in someone else's hands (why she begins a new log), so no device of hers
/// that she holds is on the root log to take them out. Her laptop begins a new log; bob (an admin, who may not give
/// owner) tries to remove her (no admit names the root) and binds her to the new log as an admin, the most he may; the
/// new log admits xena; the phone's key signs mallory in as an admin on the root log. What every keeper holds.
export function a4Root(v: V3v): string[] {
  const w = new World3(1, v, "free", { laptops: true });
  const A = w.dev("alice's app"), P = w.dev("alice's phone"), O = w.dev("alice's laptop"), B = w.dev("bob's app");
  w.sign(A, "device", personDevice(P));
  w.level();
  const g2 = w.genesis(O);
  O.log = hashOf(g2);
  w.receive(O.h, [g2]);
  w.level();
  const tried = w.sign(B, "ws.member.remove", { ws: WS, sub: "alice", cancels: w.seen(B.h, "alice") });
  w.sign(B, "ws.member", { ws: WS, sub: "alice", lock: O.log, role: "admin" });
  w.sign(O, "ws.member", { ws: WS, sub: "xena", lock: w.home.get("xena"), role: "member" });
  w.level();
  P.compromised = true;
  const e = w.attackSign(P, w.attackParents(P).at(-1)!, "admit");
  if (e) w.reach(e, [w.stations[0]]);
  w.level();
  const r = w.ros(w.stations[0]);
  const out = [
    `bob's removal of alice names ${typeof tried === "string" ? "(refused)" : (tried.body.cancels as string[]).length} admit(s): the root has none, nothing to cancel`,
    `every keeper, one list: ${new Set(w.holders.map((h) => rosterSaid(w.ros(h)))).size === 1}; s0: ${rosterSaid(r)}`,
    `alice bound to #${r.members.get("alice")!.lock.slice(0, 6)} (the pinned root #${w.root.slice(0, 6)}; the new log #${O.log.slice(0, 6)}); the pair (alice, new log) counts as an admin's for what it signs: ${r.pairs.get(`alice|${O.log}`) ?? "no"}`,
    `alice's laptop (on the new log only) let in: ${r.letIn.has(O.signer.id)}; xena (admitted from the new log) in the list: ${r.members.has("xena")}; alice's phone (revoked by no one) let in: ${r.letIn.has(P.signer.id)}; mallory (its key's admit) in: ${r.members.has("mallory")}`,
  ];
  return [...out, ...w.log.map((l) => `  ${l}`)];
}

// ── B1 is the drawn worlds' outcomes. B2: a second log for someone bound already ────────────────────────────────────

/// What a device can tell of itself from what it holds.
function selfView(w: World3, d: Dev3): string {
  const r = w.ros(d.h);
  if (!r.rooted) return "it holds no workspace's root: it cannot tell";
  const m = r.members.get(d.sub);
  if (!m) return "its person is in no list it holds";
  if (r.letIn.get(d.signer.id) === d.sub) return `let in, by #${m.lock.slice(0, 6)}`;
  if (m.lock !== d.log && !d.h.logs.has(m.lock)) return `its person is bound to #${m.lock.slice(0, 6)}, a log it does not hold`;
  if (m.lock !== d.log) return `its person is bound to #${m.lock.slice(0, 6)}, not to its own log #${d.log.slice(0, 6)}: not let in`;
  return "on its person's bound log, not on its head";
}

export type B2Out = { before: string[]; view: string; approvedView: string; after: string[]; log: string[] };

/// carol is bound by her app's log. Her laptop, which reached no keeper holding that log, begins a log of its own
/// (`reach`: it then syncs with every keeper, or with none). Then carol's app approves the laptop on the bound log and
/// it is brought to the stations.
export function b2(seed: number, v: V3v, reach: boolean, mk: Make3 = make3): B2Out {
  const w = mk(seed, v, "free", { laptops: true });
  const C = w.dev("carol's app"), L = w.dev("carol's laptop");
  // (the laptop holds nothing yet: it never reached a keeper)
  L.h.logs.clear();
  const g2 = w.genesis(L);
  L.log = hashOf(g2);
  w.receive(L.h, [g2]);
  if (reach) w.level();
  else w.level(new Set([L.h]));
  const lets = () => w.stations.map((s) => `${s.name} ${w.ros(s).letIn.has(L.signer.id) ? "lets it in" : "does not"}`);
  const before = lets();
  const view = selfView(w, L);
  w.sign(C, "device", personDevice(L), { log: C.log });
  if (!reach) while (w.queue.length > 0) w.land(w.rng.int(w.queue.length));
  w.level(reach ? new Set() : new Set([L.h]));
  const after = lets();
  const approvedView = selfView(w, { ...L, log: C.log });
  return { before, view, approvedView, after, log: w.log };
}

// ── jobs, in worker threads ─────────────────────────────────────────────────────────────────────────────────────────

export type Job3 =
  | { t: "drawn"; family: Family; v: V3v; runs: number; steps: number }
  | { t: "shrink"; family: Family; v: V3v; seed: number; steps: number; prop: string }
  | { t: "fold"; seeds: number; steps: number }
  | { t: "a2"; v: V3v; y: "admit" | "cancel" | "device"; parent: "same" | "any"; n: number }
  | { t: "a3"; v: V3v; which: (typeof A3_NAMES)[number]; n: number }
  | { t: "a4"; v: V3v; role: "member" | "admin"; y: A4Y; adopt: boolean; n: number }
  | { t: "a4root"; v: V3v }
  | { t: "b2"; v: V3v; reach: boolean; n: number };

const add = (into: Record<string, number>, from: Record<string, number>) => {
  for (const [k, n] of Object.entries(from)) into[k] = (into[k] ?? 0) + n;
};

/// A job; `mk` the world it is run in (round three's, or lock-roster4-model.ts's).
export function runJob3(j: Job3, mk: Make3 = make3): unknown {
  switch (j.t) {
    case "drawn": {
      const c = { rested: 0, agree: 0, same: 0, sameChecks: 0, sameWorlds: 0, attackInForce: 0, accomplice: 0, mallory: 0, removedIn: 0, attackAt: 0, attacks: 0, intents: 0, inact: 0, honest: 0, unasked: 0, asked: 0, turnedWorlds: 0, back: 0, forged: false, rb: [] as number[], lostWorlds: 0, noEffectWorlds: 0 };
      const o: Outcomes = { inForce: 0, noEffect: {}, void: {}, removedDev: 0, lost: 0, toldAtSigning: {} };
      const firstBad: Record<string, number> = {};
      for (let seed = 1; seed <= j.runs; seed++) {
        const { m } = drawn3(seed, j.v, j.family, drawSteps3(seed, j.steps), mk);
        if (m.rested) c.rested++;
        if (m.agree && m.heads) c.agree++;
        c.same += m.sameMismatch;
        c.sameChecks += m.sameChecks;
        if (m.sameMismatch > 0) c.sameWorlds++;
        if (m.attackInForce) c.attackInForce++;
        if (m.accomplice) c.accomplice++;
        if (m.mallory) c.mallory++;
        if (m.removedIn) c.removedIn++;
        c.attackAt += m.attackAtMax;
        c.attacks += m.attacks;
        c.intents += m.intents;
        c.inact += m.inactivated;
        c.honest += m.honest;
        c.unasked += m.turnedUnasked;
        c.asked += m.turnedAsked;
        if (m.turnedUnasked > 0) c.turnedWorlds++;
        c.back += m.back;
        if (m.forgedStored) c.forged = true;
        c.rb.push(...m.rollbacks);
        o.inForce += m.outcomes.inForce;
        add(o.noEffect, m.outcomes.noEffect);
        add(o.toldAtSigning, m.outcomes.toldAtSigning);
        add(o.void, m.outcomes.void);
        o.removedDev += m.outcomes.removedDev;
        o.lost += m.outcomes.lost;
        if (m.outcomes.lost > 0) c.lostWorlds++;
        if (Object.keys(m.outcomes.noEffect).length > 0) c.noEffectWorlds++;
        for (const p of PROPS3) if (p.bad(m) && firstBad[p.name] === undefined) firstBad[p.name] = seed;
      }
      const rb = c.rb.sort((a, b) => a - b);
      return { ...c, rb: undefined, rbMax: rb.at(-1) ?? 0, rb90: rb[Math.floor(0.9 * rb.length)] ?? 0, o, firstBad };
    }
    case "shrink": {
      const p = PROPS3.find((x) => x.name === j.prop)!;
      const fewest = shrink3(j.seed, j.v, j.family, drawSteps3(j.seed, j.steps), p.bad, mk);
      const again = drawn3(j.seed, j.v, j.family, fewest, mk);
      return { len: fewest.length, log: again.w.log, outcomes: again.m.outcomes };
    }
    case "fold":
      return foldCheck(j.seeds, j.steps, mk);
    case "a2": {
      let inForce = 0, changed = 0, phone = 0, before = 0, changedBefore = 0, ever = 0;
      let smallest: { entries: number; log: string[] } | null = null;
      for (let seed = 1; seed <= j.n; seed++) {
        const o = a2(seed, j.v, j.y, j.parent, mk);
        if (o.inForceEnd) inForce++;
        if (o.changedEnd) changed++;
        if (o.phoneEnd) phone++;
        before += o.before;
        changedBefore += o.changedBefore;
        ever += o.ever;
        if ((o.inForceEnd || o.changedEnd) && (smallest === null || o.entries < smallest.entries)) smallest = { entries: o.entries, log: o.log };
      }
      return { inForce, changed, phone, before, changedBefore, ever, smallest };
    }
    case "a3": {
      const ends = new Map<string, number>();
      let agree = 0, flap = 0, back = 0, inEnd = 0;
      const others = new Set<string>();
      let flapLog: string[] | null = null;
      for (let seed = 1; seed <= j.n; seed++) {
        const o = a3(seed, j.v, j.which, mk);
        const s0 = o.end[0].replace(/^s0: /, "");
        ends.set(s0, (ends.get(s0) ?? 0) + 1);
        if (o.agree) agree++;
        if (o.xenaFlap) flap++, (flapLog ??= o.log);
        if (o.xenaBack) back++;
        if (o.xenaInEnd) inEnd++;
        for (const x of o.otherFlap) others.add(x);
      }
      return { ends: [...ends], agree, flap, back, inEnd, others: [...others], flapLog, log: a3(1, j.v, j.which, mk).log };
    }
    case "a4": {
      const c = { oldWhileBoth: 0, oldEnd: 0, newEnd: 0, malloryEnd: 0, xenaEnd: 0, cutOld: 0, cutNew: 0 };
      const ends = new Map<string, number>();
      let bad: string[] | null = null;
      for (let seed = 1; seed <= j.n; seed++) {
        const o = a4(seed, j.v, j.role, j.y, j.adopt, mk);
        for (const k of Object.keys(c) as (keyof typeof c)[]) if (o[k] === true) c[k]++;
        ends.set(o.end, (ends.get(o.end) ?? 0) + 1);
        if ((o.oldEnd || !o.newEnd || o.malloryEnd || (j.adopt && o.xenaEnd === false)) && bad === null) bad = o.log;
      }
      return { ...c, ends: [...ends], bad };
    }
    case "a4root":
      return a4Root(j.v);
    case "b2": {
      const views = new Map<string, number>(), approved = new Map<string, number>(), before = new Map<string, number>(), after = new Map<string, number>();
      const bump = (m: Map<string, number>, k: string) => m.set(k, (m.get(k) ?? 0) + 1);
      for (let seed = 1; seed <= j.n; seed++) {
        const o = b2(seed, j.v, j.reach, mk);
        bump(views, o.view);
        bump(approved, o.approvedView);
        bump(before, o.before.join(", "));
        bump(after, o.after.join(", "));
      }
      return { views: [...views], approved: [...approved], before: [...before], after: [...after], log: b2(1, j.v, j.reach, mk).log };
    }
  }
}

if (!isMainThread && (workerData as { lockRoster?: boolean } | null)?.lockRoster === true) {
  parentPort!.on("message", (m: { id: number; job: Job3 }) => {
    parentPort!.postMessage({ id: m.id, out: runJob3(m.job) });
  });
}
