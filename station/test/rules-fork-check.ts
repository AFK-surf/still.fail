// What rules-fork.test.ts runs in its worker threads: the rules' fork choice, a person's log, a workspace's bodies,
// list and state (rules/src/lock/chain.mbt, person.mbt, body.mbt, roster.mbt, state4.mbt, lock.mbt's `moved`, as
// rules/js/rules.js exports them) against the models' keepers (lock-fork-choice-model.ts `Keeper`,
// lock-roster4-model.ts `World4` under its defaults, its list round three's `roster`, `grounded`), on the worlds the
// models draw. The workspace lock: at each quarter of a world and at its end, for every keeper, the rules' active chain
// of what it stores (shuffled, with every entry a relay forged beside it) is its own. Person logs and a workspace (the
// fourth round): at each quarter of a drawn world and at its end, and at the points the scripted worlds name
// (`look4`), for every keeper: each log's chain and what it says (devices, web devices); for every body made or
// offered, whether it takes it and why not (`bodyRefusal`); for each workspace it keeps, the statements in force, what
// it lacks, the list label for label with each statement's reason for having no effect (`effect`), and the state (D4)
// field for field; of the old chain (M7), its active chain and where it moved, and that nothing follows a `moved`. A
// difference is told with the seed, the place and the keeper.
import { createHash } from "node:crypto";
import { isMainThread, parentPort, workerData } from "node:worker_threads";
import { type Entry, canonical, endpointProof, sigValid, validKeyId } from "../src/cloud/lock.ts";
import { type Family, type Keeper, type Variant, World, drawSteps, hashOf, signed, variantName } from "./lock-fork-choice-model.ts";
import { type Holder, V3, type V3v, drawSteps3, effect, spec, stationKeys3, v3Name } from "./lock-roster-model.ts";
import { type Body, type D4, type D4Member, type W4Options, WS2, World4, bodyHash, tagOf, d4Diff, d4Said, look4, m2, m5Clock, m6, m7, revoked } from "./lock-roster4-model.ts";
import { Rng, WS } from "./lock-world-sim.ts";
// @ts-ignore: the MoonBit build's JS, untyped
import * as rules from "../../rules/js/rules.js";

/// The stations' own cryptography, a signature's check kept by what it checked (a world checks the same ones again and
/// again; Ed25519 says the same of the same bytes).
const checked = new Map<string, boolean>();
export const crypto = {
  sha256Hex: (s: string) => createHash("sha256").update(s).digest("hex"),
  sigValid: (sig: any, hash: string, origins: string[], rp: string, passkey: boolean) => {
    const id = `${JSON.stringify(sig)}|${hash}|${origins.join(",")}|${rp}|${passkey}`;
    let ok = checked.get(id);
    if (ok === undefined) {
      if (checked.size > 300_000) checked.clear();
      ok = sigValid(sig, hash, origins, rp, passkey);
      checked.set(id, ok);
    }
    return ok;
  },
  validKeyId, endpointProof,
};

type Off = { at: number; why: string; refusal?: string; winner?: string; step?: string; under?: string };
type Chain = { hashes: string[]; off: Off[]; at: number[] } | { error: string };

function shuffled<T>(xs: T[], r: Rng): T[] {
  const out = [...xs];
  for (let i = out.length - 1; i > 0; i--) {
    const j = r.int(i + 1);
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

export type Out = { worlds: number; checks: number; branched: number; refusedSeen: number; statements: number; differ: string[]; more: More };
const fresh = (): Out => ({ worlds: 0, checks: 0, branched: 0, refusedSeen: 0, statements: 0, differ: [], more: more0() });

/// The rules' chain of `given` from `genesis`, against `active`; what it said of what is not on it, counted.
function sameChain(o: Out, where: string, got: Chain, given: Entry[], active: string[], forged: Set<string>) {
  o.checks++;
  if ("error" in got) return void o.differ.push(`${where}: the rules found no chain (${got.error})`);
  if (got.hashes.join() !== active.join()) {
    const p = got.hashes.findIndex((h, i) => h !== active[i]);
    return void o.differ.push(`${where}: the rules' chain leaves the keeper's at ${p} (${got.hashes.length} entries, the keeper's ${active.length})`);
  }
  for (const x of got.off) {
    const h = hashOf(given[x.at]);
    if (x.why === "beaten") o.branched++;
    if (x.why === "refused") o.refusedSeen++;
    // (what a relay forged is refused, or hangs below a parent the keeper never had; what the keeper stores and does not
    // go by lost to a sibling, or hangs below one that did)
    if (forged.has(h) ? x.why !== "refused" && x.why !== "no parent" : x.why !== "beaten" && x.why !== "below") o.differ.push(`${where}: ${h.slice(0, 8)} is off the chain as ${x.why}${x.refusal ? ` (${x.refusal})` : ""}`);
  }
}

// ── the workspace lock (the first rounds) ───────────────────────────────────────────────────────────────────────────

/// Every keeper of `w`: the rules' chain of what it stores is the one it goes by.
function lockKeepers(o: Out, w: World, at: string, r: Rng) {
  const forged = [...w.forged].map((h) => w.all.get(h)!).filter((e) => e !== undefined);
  const fs = new Set(w.forged);
  for (const k of w.keepers) {
    const given = shuffled([...k.store.values(), ...forged.filter((e) => !k.store.has(hashOf(e)))], r);
    const got = rules.lock_chain_js(given, w.rules.gh, w.v.votes, null, crypto) as Chain;
    sameChain(o, `${at}, ${k.name}`, got, given, k.active, fs);
  }
}

export function lockWorlds(v: Variant, family: Family, from: number, to: number, steps: number): Out {
  const o = fresh();
  for (let seed = from; seed <= to; seed++) {
    const w = new World(seed, v, family);
    const r = new Rng(seed ^ 0x7e57);
    const st = drawSteps(seed, steps);
    const at = (q: string) => `seed ${seed} ${variantName(v)} ${family} ${q}`;
    for (let q = 0; q < 4; q++) {
      w.run(st.slice(Math.floor((q * st.length) / 4), Math.floor(((q + 1) * st.length) / 4)));
      lockKeepers(o, w, at(`quarter ${q + 1}`), r);
    }
    w.finish();
    lockKeepers(o, w, at("end"), r);
    o.worlds++;
  }
  return o;
}

// ── person logs, a workspace's bodies, its list and its state (the fourth round) ────────────────────────────────────

const sorted = (xs: string[]) => [...xs].sort().join("; ");

/// What the fourth round's comparison counted beside the chains: bodies offered and refused (by why), statements in
/// force, entries lacking their bodies, lists and states compared, states off and not on, web devices counted, old
/// chains compared, moved seen, entries after a moved refused, chains where votes by role would choose otherwise,
/// devices of a state let in by `admit`.
export type More = {
  bodies: number; refused: Record<string, number>; inForce: number; lacking: number; lists: number; states: number; off: number; notOn: number;
  webs: number; old: number; moved: number; afterMoved: number; rolesOther: number; admitted: number;
  /// Removals in force compared (whom each took out, `without`), and (keeper, holder) pairs told by one.
  removals: number; toldOut: number;
};
const more0 = (): More => ({ bodies: 0, refused: {}, inForce: 0, lacking: 0, lists: 0, states: 0, off: 0, notOn: 0, webs: 0, old: 0, moved: 0, afterMoved: 0, rolesOther: 0, admitted: 0, removals: 0, toldOut: 0 });

/// The web devices on a log's active chain by id (the model's `websAt` before the clock).
function websOn(k: Keeper<any>): string[] {
  const exp = new Map<string, [number, number]>();
  for (const x of k.active) {
    const e = k.store.get(x)!;
    if (e.kind === "web") exp.set(e.body.id, [e.at, e.body.exp]);
    else if (e.kind === "web.remove") exp.delete(e.body.id);
  }
  return [...exp].map(([id, [at, t]]) => `${id} ${at} ${t}`);
}

/// Every keeper of `w`, as the module's head says.
function keepers4(o: Out, w: World4, at: string, r: Rng, offered: Body[] = []) {
  const forged = [...w.forged].map((h) => w.all.get(h)!).filter((e) => e !== undefined);
  const fs = new Set(w.forged);
  const made = [...w.x.bodies.values(), ...offered];
  // (changed after committed: a body whose hash no entry holds, and a body naming another workspace)
  const changed = made.filter((b) => b.kind === "member").slice(0, 3).map((b) => ({ ...b, role: b.role === "owner" ? "admin" : "owner" }));
  const candidates = [...made, ...changed, ...made.filter((b) => b.ws === WS).slice(0, 2).map((b) => ({ ...b, ws: WS2 }))];
  for (const h of w.holders) {
    const where = `${at}, ${h.name}`;
    // each log's chain, and what it says
    for (const [g, k] of h.logs) {
      const extra = g === w.root ? forged.filter((e) => !k.store.has(hashOf(e))) : [];
      const given = shuffled([...k.store.values(), ...extra], r);
      const log = `${where}, ${k.rules.state(g).sub}'s log #${g.slice(0, 6)}`;
      sameChain(o, log, rules.person_chain_js(given, g, crypto) as Chain, given, k.active, fs);
      const p = rules.person_fold_js(k.active.map((x) => k.store.get(x)!), k.rules.state(g).sub, crypto) as any;
      if ("error" in p) o.differ.push(`${log}: the rules' fold refuses the keeper's chain (${p.error})`);
      else {
        if (sorted(p.devices.map((d: any) => d.key)) !== sorted([...k.headState().devices.keys()])) o.differ.push(`${log}: devices differ`);
        const webs = p.webs.map((x: any) => `${x.id} ${x.at} ${x.exp}`);
        o.more.webs += webs.length;
        if (sorted(webs) !== sorted(websOn(k))) o.differ.push(`${log}: web devices: the rules ${sorted(webs) || "none"}, the model ${sorted(websOn(k)) || "none"}`);
      }
    }
    // bodies: taken or refused, and why
    const pins = w.pinsOf(h);
    const stored = h.stored().filter((e) => e.kind === "ws");
    for (const b of candidates) {
      o.more.bodies++;
      const want = w.bodyRefusal(h, b);
      let hb = "";
      try {
        hb = bodyHash(b);
      } catch {}
      const commits = stored.filter((e) => e.body.h === hb).map((e) => ({ genesis: w.logOf.get(hashOf(e))!, chain: w.chainTo(hashOf(e)) }));
      const got = rules.body_refusal_js(typeof b.ws === "string" && pins.has(b.ws) ? b.ws : "\u0000", b, commits, crypto) as string | null;
      if (want !== null) o.more.refused[want] = (o.more.refused[want] ?? 0) + 1;
      if (got !== want) o.differ.push(`${where}: body ${hb.slice(0, 8)} (${b.kind}): the rules ${got ?? "take it"}, the model ${want ?? "takes it"}`);
    }
    // each workspace it keeps: in force, lacking, the list, the state
    const chains = () => shuffled([...h.logs.values()].map((k: Keeper<any>) => k.active.map((x) => k.store.get(x)!)), r);
    const kept = () => shuffled([...w.keptOf(h).values()], r);
    for (const [ws, root] of pins) {
      if (!root) continue;
      const here = `${where}, ${ws === WS ? "W1" : "W2"}`;
      const f = w.inForce(h, ws);
      const got = rules.roster_js(ws, root, chains(), kept(), [], crypto) as any;
      if ("error" in got) {
        o.differ.push(`${here}: the rules' list: ${got.error}`);
        continue;
      }
      o.more.inForce += f.stmts.size;
      o.more.lacking += f.lacking.length;
      const say = (what: string, a: string, b: string) => {
        if (a !== b) o.differ.push(`${here}: ${what}: the rules ${a || "none"}, the model ${b || "none"}`);
      };
      if (got.refused.length > 0) o.differ.push(`${here}: the rules refused chains a keeper goes by: ${JSON.stringify(got.refused)}`);
      say("in force", sorted(got.in_force.map((x: any) => `${x.entry} ${x.body}`)), sorted([...f.stmts].map(([x, b]) => `${x} ${bodyHash(b)}`)));
      say("lacking", sorted(got.lacking), sorted(f.lacking));
      const want = w.rosterIn(h, root, ws, f);
      say("rooted", String(got.rooted), String(want.rooted));
      if (want.rooted) {
        o.more.lists++;
        say("members", sorted(got.members.map((m: any) => `${m.sub} ${m.role} ${m.lock} ${m.admit ?? ""}`)), sorted([...want.members].map(([sub, m]) => `${sub} ${m.role} ${m.lock} ${m.admit}`)));
        say("keys let in", sorted(got.members.flatMap((m: any) => (m.keys ?? []).map((k: string) => `${k} ${m.sub}`))), sorted([...want.letIn].map(([k, sub]) => `${k} ${sub}`)));
        say("stations", sorted(got.stations), sorted([...want.stations]));
        say("pairs", sorted(got.pairs.map((p: any) => `${p.sub}|${p.lock} ${p.role}`)), sorted([...want.pairs].map(([k, role]) => `${k} ${role}`)));
        say("undecided", sorted(got.undecided.map((p: any) => `${p.sub}|${p.lock}`)), sorted([...want.undecided]));
        say("cancelled", sorted(got.cancelled), sorted([...want.cancelled]));
        say("labels", sorted(got.labels.map(([id, l]: [string, string]) => `${id} ${l}`)), sorted([...want.labels].map(([id, l]) => `${id} ${l}`)));
        // each statement's reason for having no effect, its body given to `effect` as the model gives it to `roster`
        const byBody = new Map<string, string[]>();
        for (const [x, b] of f.stmts) byBody.set(bodyHash(b), [...(byBody.get(bodyHash(b)) ?? []), x]);
        for (const st of got.statements) {
          o.statements++;
          const b = f.stmts.get(st.hash);
          if (b === undefined) {
            o.differ.push(`${here}: the rules list ${st.hash.slice(0, 8)}, which is not in force at the model`);
            continue;
          }
          const { kind, salt: _, ws: __, ...rest } = b;
          if (Array.isArray(rest.cancels)) rest.cancels = rest.cancels.flatMap((c: string) => byBody.get(c) ?? []);
          const theirs = effect(want, { kind: `ws.${kind}`, body: rest, log: st.log, dev: { sub: w.rulesOf(st.hash).sub } }, st.hash);
          if (st.kind === "ws.member" || st.kind === "ws.member.remove") say(`why ${st.kind} #${st.hash.slice(0, 6)} has no effect`, st.why ?? "", theirs ?? "");
          else if (theirs !== null) say(`why ${st.kind} #${st.hash.slice(0, 6)} has no effect`, st.why ?? "", theirs);
        }
      }
      sameState(o, here, w, h, ws, root, chains(), kept());
      takenOut(o, here, w, h, ws, root, chains(), kept(), f.stmts);
    }
    oldChain(o, where, w, h, r);
  }
}

/// Whom each removal in force at `h` took out: the keys the rules' list names with every statement in force of that
/// subject's removals left out (`without`), against the model's `admitsBefore` for every holder of the world.
function takenOut(o: Out, here: string, w: World4, h: Holder, ws: string, root: string, chains: Entry[][], kept: Body[], stmts: Map<string, Body>) {
  const subjectOf = (b: Body) => (b.kind === "member.remove" ? `m|${b.sub}` : b.kind === "station.remove" ? `s|${b.key}` : null);
  const seen = new Set<string>();
  for (const b of stmts.values()) {
    const subject = subjectOf(b);
    if (subject === null || seen.has(subject)) continue;
    seen.add(subject);
    o.more.removals++;
    const without = [...new Set([...stmts.values()].filter((x) => subjectOf(x) === subject).map((x) => bodyHash(x)))];
    const r = rules.roster_js(ws, root, chains, kept, without, crypto) as any;
    if ("error" in r) return void o.differ.push(`${here}: the rules' list without ${subject}: ${r.error}`);
    const keys = new Set<string>([...r.stations, ...r.members.flatMap((m: any) => m.keys ?? [])]);
    for (const to of w.holders) {
      const want = w.admitsBefore(h, to, b);
      const got = keys.has(w.keyOfHolder(to));
      if (want) o.more.toldOut++;
      if (want !== got) o.differ.push(`${here}: ${to.name} named without ${subject}: the rules ${got}, the model ${want}`);
    }
  }
}

/// The state (D4) at `h` for `ws`, field for field, by the keeper's clock.
function sameState(o: Out, here: string, w: World4, h: Holder, ws: string, root: string, chains: Entry[][], kept: Body[]) {
  o.more.states++;
  const want = w.d4(h, ws);
  const now = w.clock(h);
  const got = rules.state4_js(ws, root, chains, kept, now, crypto) as any;
  if ("error" in got) return void o.differ.push(`${here}: the rules' state: ${got.error}`);
  if (want === "off") o.more.off++;
  if (typeof want === "string") {
    const as = got.on === "no root" ? "no root" : got.on === "off" ? "off" : got.on;
    if (as !== want) o.differ.push(`${here}: state: the rules ${as}, the model ${want}`);
    if (want === "off" && !got.state.disabled) o.differ.push(`${here}: off, and the rules' state is not disabled`);
    return;
  }
  if (want.on === "not on") o.more.notOn++;
  const s = got.state;
  const r = rules.roster_js(ws, root, chains, kept, [], crypto) as any;
  const settings = r.settings === null ? "-" : canonical({ origins: s.origins, rp_id: s.rp_id, cloud_keys: s.cloud_keys });
  const devs = (sub: string, kind: string) => s.devices.map(([, d]: [string, any]) => d).filter((d: any) => d.sub === sub && d.kind === kind);
  const members = new Map<string, D4Member>((s.members as [string, any][]).map(([sub, m]) => [sub, {
    role: m.role, email: m.email === "" ? "-" : m.email, lock: new Map(s.persons as [string, string][]).get(sub) ?? "none",
    apps: devs(sub, "app").map((d: any) => d.sign_key).sort(), webs: devs(sub, "web").map((d: any) => d.id).sort(),
  }]));
  const mine: D4 = { on: got.on, settings, members, stations: (s.stations as [string, any][]).map(([k]) => k).sort() };
  const diff = d4Diff(mine, want);
  if (diff.length > 0) o.differ.push(`${here}: state differs in ${diff.join(", ")}: the rules ${d4Said(mine)}; the model ${d4Said(want)}`);
  if (s.disabled !== false || s.genesis !== root || s.passkeys.length > 0 || s.gateways.length > 0) o.differ.push(`${here}: the state's own fields: disabled ${s.disabled}, genesis ${s.genesis.slice(0, 8)}`);
  // Admission on it as on a folded chain (`admit`, by the device's id as an older client connects): each device of a
  // member lets that member in with their role; under another's name, no one.
  for (const [id, d] of s.devices as [string, any][]) {
    o.more.admitted++;
    const role = new Map(s.members as [string, any][]).get(d.sub)?.role;
    const mine = rules.admit_one_js(got.rules, { sub: d.sub, endpoint: id }, now, crypto) as any;
    if (mine.device !== id || mine.role !== role) o.differ.push(`${here}: ${d.sub}'s ${d.kind} device ${id.slice(0, 8)} is not let in on the state: ${JSON.stringify(mine)}`);
    const other = rules.admit_one_js(got.rules, { sub: `${d.sub}-not`, endpoint: id }, now, crypto) as any;
    if (!("refusal" in other)) o.differ.push(`${here}: ${d.sub}'s device ${id.slice(0, 8)} lets in another`);
  }
}

/// The old chain at `h` (M7): its active chain by the rules (one vote a device, as the model's `OLD_V`), where it moved
/// (reading B: the `moved` on the active chain), and that the rules take nothing after a `moved`.
function oldChain(o: Out, where: string, w: World4, h: Holder, r: Rng) {
  const k = w.x.old.get(h), rs = w.x.oldRules;
  if (k === undefined || rs === null) return;
  o.more.old++;
  const given = shuffled([...k.store.values()], r);
  sameChain(o, `${where}, the old chain`, rules.lock_chain_js(given, rs.gh, "flat", null, crypto) as Chain, given, k.active, new Set());
  const roles = rules.lock_chain_js(given, rs.gh, "roles", null, crypto) as Chain;
  if (!("error" in roles) && roles.hashes.join() !== k.active.join()) o.more.rolesOther++;
  const chain = k.active.map((x) => k.store.get(x)!);
  const folded = rules.fold_held_js(chain, null, crypto) as any;
  if ("error" in folded) return void o.differ.push(`${where}: the rules' fold refuses the old chain (${folded.error})`);
  const root = w.x.reading === "B" ? (k.active.map((y) => rs.moved.get(y)).find((x) => x !== undefined) ?? null) : null;
  if ((folded.state.moved ?? null) !== root) o.differ.push(`${where}: the old chain moved to ${folded.state.moved ?? "none"} by the rules, ${root ?? "none"} by the model`);
  if (root === null || w.x.reading !== "B") return;
  o.more.moved++;
  if (w.pinsOf(h).get(WS) !== root) o.differ.push(`${where}: the keeper goes by ${w.pinsOf(h).get(WS) ?? "none"}, its chain moved to ${root}`);
  // (an owner's own device signing after it: refused)
  const last = chain[chain.length - 1];
  const after = signed({ v: 1, ws: last.ws, seq: last.seq + 1, prev: hashOf(last), at: last.at + 1, kind: "station.remove", body: { key: stationKeys3[0].hex } }, spec("alice's app").signer);
  const more = rules.fold_held_js([...chain, after], null, crypto) as any;
  if ("error" in more) o.more.afterMoved++;
  else o.differ.push(`${where}: the rules take an entry after the moved`);
}

/// The fourth round's options a drawn world is made with, by its seed: as it is; one body held back for good (M1); a
/// second workspace (M3).
const drawnOptions = (seed: number): W4Options => (seed % 3 === 1 ? { holdBack: { station: seed % 3, nth: 1 + ((seed * 7) % 5) } } : seed % 3 === 2 ? { two: true } : {});

export function personWorlds(v: V3v, family: Family, from: number, to: number, steps: number): Out {
  const o = fresh();
  for (let seed = from; seed <= to; seed++) {
    const w = new World4(seed, v, family, drawnOptions(seed));
    const r = new Rng(seed ^ 0x7e58);
    const st = drawSteps3(seed, steps);
    const at = (q: string) => `seed ${seed} ${v3Name(v)} ${family} ${JSON.stringify(drawnOptions(seed))} ${q}`;
    for (let q = 0; q < 4; q++) {
      w.run(st.slice(Math.floor((q * st.length) / 4), Math.floor(((q + 1) * st.length) / 4)));
      keepers4(o, w, at(`quarter ${q + 1}`), r);
    }
    w.finish();
    keepers4(o, w, at("end"), r);
    o.worlds++;
  }
  return o;
}

/// Bodies whose shape is no statement's, each committed to by alice's app under the workspace's tag in her log (M2
/// offers none such: a body a commitment holds is refused for its shape alone here).
function misshapen(o: Out, seed: number, r: Rng) {
  const w = new World4(seed, V3[1], "free");
  const A = w.dev("alice's app");
  w.level();
  const salt = createHash("sha256").update(`misshapen ${seed}`).digest("hex").slice(0, 32);
  const admit = { ws: WS, kind: "member", sub: "xena", email: "xena@x", lock: w.home.get("xena")!, role: "member", prev: null, salt };
  const bad: Body[] = [
    { ...admit, role: "boss" },
    { ...admit, salt: "short" },
    { ...admit, email: undefined as unknown as string, extra: 1 },
    { ws: WS, kind: "nonsense", prev: null, salt },
    { ws: WS, kind: "off", prev: null, salt, why: "more" },
  ].map((b) => JSON.parse(JSON.stringify(b)));
  for (const b of bad) {
    const k = A.h.logs.get(A.log)!;
    const e = w.make(w.entry(k.head()), "ws", { t: tagOf(WS, w.root), h: bodyHash(b) }, A.signer);
    w.receive(A.h, [e]);
  }
  w.level();
  keepers4(o, w, `misshapen seed ${seed}`, r, bad);
}

/// The fourth round's scripted worlds (M2, M5, the revoked key's web device and off, M6, M7 with each of its rows),
/// `from` to `to` each, compared at every point they name.
export function scriptedWorlds(from: number, to: number): Out {
  const o = fresh();
  const r = new Rng(from ^ 0x7e59);
  look4.at = (w, where, offered) => keepers4(o, w, where, r, offered ?? []);
  try {
    for (let seed = from; seed <= to; seed++) {
      m2(seed);
      if (seed === from) for (const skew of [0, 300, 3600]) m5Clock(seed, skew, false);
      for (const kind of ["web", "off"] as const) for (const parent of ["same", "any"] as const) revoked(seed, kind, parent);
      m6(seed);
      for (const m of [{}, { away: true }, { attack: "same" as const }, { attack: "any" as const }]) m7(seed, m);
      misshapen(o, seed, r);
      o.worlds += 1;
    }
  } finally {
    look4.at = null;
  }
  return o;
}

export type Job =
  | { t: "lock"; v: Variant; family: Family; from: number; to: number; steps: number }
  | { t: "person"; v: V3v; family: Family; from: number; to: number; steps: number }
  | { t: "scripted"; from: number; to: number };

export const runJob = (j: Job): Out =>
  j.t === "lock" ? lockWorlds(j.v, j.family, j.from, j.to, j.steps) : j.t === "person" ? personWorlds(j.v, j.family, j.from, j.to, j.steps) : scriptedWorlds(j.from, j.to);

if (!isMainThread && (workerData as { rulesFork?: boolean } | null)?.rulesFork === true) {
  parentPort!.on("message", (m: { id: number; job: Job }) => {
    parentPort!.postMessage({ id: m.id, out: runJob(m.job) });
  });
}
