// What rules-fork.test.ts runs in its worker threads: the rules' fork choice and list (rules/src/lock/chain.mbt,
// roster.mbt, as rules/js/rules.js exports them) against the models' keepers (lock-fork-choice-model.ts `Keeper`,
// lock-roster-model.ts `roster`, `grounded`), on the worlds the models' own generators draw. At each quarter of a world
// and at its end, for every keeper: the rules' active chain of what it stores (shuffled, with every entry a relay forged
// beside it) is its own; for every holder of person logs, each log's chain, then the rules' list from those chains (in
// a shuffled order) is the model's, label for label, and each statement's reason for having no effect is the model's
// (`effect`). A difference is told with the seed, the variant, the place and the keeper.
import { createHash } from "node:crypto";
import { isMainThread, parentPort, workerData } from "node:worker_threads";
import { type Entry, sigValid, validKeyId, endpointProof } from "../src/cloud/lock.ts";
import { type Family, type Keeper, type Variant, World, drawSteps, hashOf, variantName } from "./lock-fork-choice-model.ts";
import { type Holder, type V3v, World3, drawSteps3, effect, roster, v3Name } from "./lock-roster-model.ts";
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

export type Out = { worlds: number; checks: number; branched: number; refusedSeen: number; statements: number; differ: string[] };
const fresh = (): Out => ({ worlds: 0, checks: 0, branched: 0, refusedSeen: 0, statements: 0, differ: [] });

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

// ── person logs and the list (the third round) ──────────────────────────────────────────────────────────────────────

const sorted = (xs: string[]) => [...xs].sort().join("; ");

/// Every holder of `w`: each person log's chain, then the list from those chains with its labels and reasons.
function holders(o: Out, w: World3, at: string, r: Rng) {
  const forged = [...w.forged].map((h) => w.all.get(h)!).filter((e) => e !== undefined);
  const fs = new Set(w.forged);
  for (const h of w.holders) {
    const where = `${at}, ${h.name}`;
    for (const [g, k] of h.logs) {
      const extra = g === w.root ? forged.filter((e) => !k.store.has(hashOf(e))) : [];
      const given = shuffled([...k.store.values(), ...extra], r);
      sameChain(o, `${where}, ${k.rules.state(g).sub}'s log #${g.slice(0, 6)}`, rules.person_chain_js(given, g, crypto) as Chain, given, k.active, fs);
    }
    sameList(o, where, h, w, r);
  }
}

function sameList(o: Out, where: string, h: Holder, w: World3, r: Rng) {
  const chains = shuffled([...h.logs.values()].map((k: Keeper<any>) => k.active.map((x) => k.store.get(x)!)), r);
  const got = rules.roster_js(WS, w.root, chains, crypto) as any;
  const want = roster(h, w.root, "grounded");
  const say = (what: string, a: string, b: string) => {
    if (a !== b) o.differ.push(`${where}: ${what}: the rules ${a || "none"}, the model ${b || "none"}`);
  };
  if ("error" in got) return void o.differ.push(`${where}: the rules' list: ${got.error}`);
  if (got.refused.length > 0) o.differ.push(`${where}: the rules refused chains a keeper goes by: ${JSON.stringify(got.refused)}`);
  say("rooted", String(got.rooted), String(want.rooted));
  if (!want.rooted) return;
  say("members", sorted(got.members.map((m: any) => `${m.sub} ${m.role} ${m.lock} ${m.admit ?? ""}`)), sorted([...want.members].map(([sub, m]) => `${sub} ${m.role} ${m.lock} ${m.admit}`)));
  say("keys let in", sorted(got.members.flatMap((m: any) => (m.keys ?? []).map((k: string) => `${k} ${m.sub}`))), sorted([...want.letIn].map(([k, sub]) => `${k} ${sub}`)));
  say("stations", sorted(got.stations), sorted([...want.stations]));
  say("pairs", sorted(got.pairs.map((p: any) => `${p.sub}|${p.lock} ${p.role}`)), sorted([...want.pairs].map(([k, role]) => `${k} ${role}`)));
  say("undecided", sorted(got.undecided.map((p: any) => `${p.sub}|${p.lock}`)), sorted([...want.undecided]));
  say("cancelled", sorted(got.cancelled), sorted([...want.cancelled]));
  say("labels", sorted(got.labels.map(([id, l]: [string, string]) => `${id} ${l}`)), sorted([...want.labels].map(([id, l]) => `${id} ${l}`)));
  // Each statement's reason for having no effect, as the model's B1 has it (`effect`): admits and removals of people;
  // a station's statement whose signer is not in the list.
  for (const s of got.statements) {
    o.statements++;
    const e = w.entry(s.hash);
    const sub = w.rulesOf(s.hash).sub;
    const theirs = effect(want, { kind: e.kind, body: e.body, log: s.log, dev: { sub } }, s.hash);
    if (s.kind === "ws.member" || s.kind === "ws.member.remove") say(`why ${s.kind} #${s.hash.slice(0, 6)} has no effect`, s.why ?? "", theirs ?? "");
    else if (theirs !== null) say(`why ${s.kind} #${s.hash.slice(0, 6)} has no effect`, s.why ?? "", theirs);
  }
}

export function personWorlds(v: V3v, family: Family, from: number, to: number, steps: number): Out {
  const o = fresh();
  for (let seed = from; seed <= to; seed++) {
    const w = new World3(seed, v, family);
    const r = new Rng(seed ^ 0x7e58);
    const st = drawSteps3(seed, steps);
    const at = (q: string) => `seed ${seed} ${v3Name(v)} ${family} ${q}`;
    for (let q = 0; q < 4; q++) {
      w.run(st.slice(Math.floor((q * st.length) / 4), Math.floor(((q + 1) * st.length) / 4)));
      holders(o, w, at(`quarter ${q + 1}`), r);
    }
    w.finish();
    holders(o, w, at("end"), r);
    o.worlds++;
  }
  return o;
}

export type Job = { t: "lock"; v: Variant; family: Family; from: number; to: number; steps: number } | { t: "person"; v: V3v; family: Family; from: number; to: number; steps: number };

export const runJob = (j: Job): Out => (j.t === "lock" ? lockWorlds(j.v, j.family, j.from, j.to, j.steps) : personWorlds(j.v, j.family, j.from, j.to, j.steps));

if (!isMainThread && (workerData as { rulesFork?: boolean } | null)?.rulesFork === true) {
  parentPort!.on("message", (m: { id: number; job: Job }) => {
    parentPort!.postMessage({ id: m.id, out: runJob(m.job) });
  });
}
