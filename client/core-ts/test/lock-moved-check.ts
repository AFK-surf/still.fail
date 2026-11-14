// The core held to the fourth round's model (station/test/lock-roster4-model.ts, its defaults), as
// station/test/lock-moved-model-check.ts holds a station to it: at each quarter of a drawn world and at its end, and at
// each look of the scripted ones (`look4.at`), every device keeper of the model's world (each device of a person,
// which keeps a workspace as a station does) is stood for by what the core keeps (src/lock-keep.ts with the person
// logs' rules, src/lock-moved.ts) given what the model's keeper stores then: every entry of every log it stores, as
// stations show them; the workspace chain with its `moved` (the model's old chain where the world has one, M7; else a
// genesis and a `moved {root}` by the root's own app); and the bodies the world offered it, in the order made and,
// at a drawn world's end, in a drawn other order. Its clock is the keeper's. Compared, field for field: each log's
// chain gone by; the bodies kept, and each refusal's reason; `lacking`; `inForce` against the model's `d4`.
//
// Offered as the station's check offers: the bodies the keeper keeps, and every body the world made that the model's
// keeper would refuse (a body it would take but was not given yet is not offered). Where the core is stricter on
// purpose, as the station is: "not on" and "no root" are `waiting`, naming nobody.
import { isMainThread, parentPort, workerData } from "node:worker_threads";
import { hashOf as modelHash } from "../../../station/test/lock-fork-choice-model.ts";
import { type Body, type D4, type D4Member, World4, bodyHash as modelBodyHash, d4Diff, d4Said, look4, m2, m5Clock, m6, m7, m8, revoked, bareChain } from "../../../station/test/lock-roster4-model.ts";
import { type Family, type Holder, V3, type V3v, drawSteps3 } from "../../../station/test/lock-roster-model.ts";
import { Rng, WS } from "../../../station/test/lock-world-sim.ts";
import { type Entry, canonical } from "../src/lock.ts";
import { type Kept, hashOf, keep } from "../src/lock-keep.ts";
import { type InForce, bodyRefused, inForce, lackingOf } from "../src/lock-moved.ts";
import { personRules } from "../src/personal-lock.ts";

export type Out = {
  worlds: number; keepers: number; differ: string[];
  logs: number; bodiesOffered: number; refused: Record<string, number>; lacking: number;
  on: number; off: number; waiting: number; webs: number; moved: number; stricter: number;
};
export const fresh = (): Out => ({ worlds: 0, keepers: 0, differ: [], logs: 0, bodiesOffered: 0, refused: {}, lacking: 0, on: 0, off: 0, waiting: 0, webs: 0, moved: 0, stricter: 0 });

function shuffled<T>(xs: T[], r: Rng): T[] {
  const out = [...xs];
  for (let i = out.length - 1; i > 0; i--) {
    const j = r.int(i + 1);
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}
const sorted = (xs: Iterable<string>) => [...xs].sort().join(",");

/// The workspace chain of `ws` the device under test holds: the model keeper's old chain where it keeps one (M7), else
/// a genesis whose owner is the root's person with the root's app, and its `moved {root}` (as the station's check).
function chainFor(w: World4, h: Holder, ws: string, root: string): Entry[] {
  const old = w.x.old.get(h);
  if (old !== undefined && ws === WS) return old.active.map((x) => old.store.get(x)!) as unknown as Entry[];
  return bareChain(ws, root) as unknown as Entry[];
}

/// What the core keeps standing for keeper `h` in `ws`: each person log (src/lock-keep.ts `keep` by the person logs'
/// rules, as personal-lock.ts keeps the person's own), the entries given it, and the bodies taken (src/lock-moved.ts).
type Stood = { logs: Map<string, Kept>; given: Set<string>; bodies: Map<string, unknown> };
function stand(w: World4, h: Holder, ws: string, offered: Body[], was?: Stood): Stood {
  const s: Stood = was ?? { logs: new Map(), given: new Set(), bodies: new Map() };
  for (const [g, k] of h.logs) {
    const fresh = [...k.store.values()].filter((e) => !s.given.has(modelHash(e))) as unknown as Entry[];
    if (fresh.length === 0) continue;
    const genesis = k.store.get(g)! as unknown as Entry;
    const sub = String((genesis.body as { sub?: unknown } | null)?.sub ?? "");
    const kept = s.logs.get(g) ?? { entries: [], aside: [] };
    try {
      const t = keep(kept, [genesis, ...fresh.filter((e) => hashOf(e) !== g)], personRules(sub, g));
      s.logs.set(g, t.kept);
    } catch {
      // (no chain of what was given: nothing kept, as personal-lock.ts keeps none)
    }
    for (const e of fresh) s.given.add(hashOf(e));
  }
  for (const b of offered) take(s, ws, b);
  return s;
}

/// Everything kept of each log (its chain and what is aside), as a body's commitments are looked for among.
const storedOf = (s: Stood): [string, Entry[]][] => [...s.logs].map(([g, k]) => [g, [...k.entries, ...k.aside]]);

function take(s: Stood, ws: string, b: unknown): string | null {
  const r = bodyRefused(ws, b, storedOf(s), hashOf);
  if (r.why !== null) return r.why;
  if (!s.bodies.has(r.hash!)) s.bodies.set(r.hash!, b);
  return null;
}

/// The core's state as the model's D4 has one.
function d4Of(f: InForce): D4 | string {
  if (f.said === "waiting") return "waiting";
  if (f.said === "off") return "off";
  if (f.said === "chain") return "chain";
  const devs = (sub: string, kind: string) => [...f.f.devices.values()].filter((d) => d.sub === sub && d.kind === kind);
  const members = new Map<string, D4Member>([...f.f.members].map(([sub, m]) => [sub, {
    role: m.role, email: m.email === "" ? "-" : m.email, lock: f.f.persons.get(sub) ?? "none",
    apps: devs(sub, "app").map((d) => d.sign_key as string).sort(), webs: devs(sub, "web").map((d) => d.id as string).sort(),
  }]));
  return { on: "on", settings: f.settings ? canonical(f.settings) : "-", members, stations: [...f.f.stations.keys()].sort() };
}

const stood = new WeakMap<World4, Map<string, Stood>>();
const words = new WeakMap<World4, Map<string, string>>();

/// Every device keeper of `w` that goes by a root, compared at `at`; `extra`, bodies offered there that no keeper keeps
/// (M2's); `last`, the world's last look, where a keeper is also stood for anew and given the same in another order.
export function devices4(o: Out, w: World4, at: string, r: Rng, extra: Body[] = [], last = false) {
  const mine = stood.get(w) ?? stood.set(w, new Map()).get(w)!;
  for (const h of w.holders) {
    if (!w.devOf.has(h)) continue;
    const pins = w.pinsOf(h);
    for (const [ws, root] of pins) {
      if (!root) continue;
      // (a keeper nothing came to since it was last compared, by the same clock: compared already)
      const word = `${h.ver}|${root}|${w.clock(h)}|${w.x.order.length}|${extra.length}|${w.x.old.get(h)?.active.length ?? -1}`;
      const seen = words.get(w) ?? words.set(w, new Map()).get(w)!;
      if (!last && seen.get(`${h.name}|${ws}`) === word) continue;
      seen.set(`${h.name}|${ws}`, word);
      o.keepers++;
      const where = `${at}, ${h.name}, ${ws === WS ? "W1" : "W2"}`;
      const kept = w.keptOf(h);
      const refusedBy = new Map<string, string>();
      const offered: Body[] = [];
      for (const b of [...w.x.order.map((hb) => w.x.bodies.get(hb)!), ...extra]) {
        if (typeof b?.ws === "string" && b.ws !== ws && pins.has(b.ws)) continue;
        const hb = modelBodyHash(b);
        if (kept.has(hb)) offered.push(b);
        else {
          const why = w.bodyRefusal(h, b);
          if (why !== null) {
            offered.push(b);
            refusedBy.set(hb, why);
          }
        }
      }
      o.bodiesOffered += offered.length;
      const id = `${h.name}|${ws}`;
      const s = stand(w, h, ws, offered, mine.get(id));
      mine.set(id, s);
      compare(o, where, w, h, ws, root, s, kept, refusedBy, offered);
      if (last) compare(o, `${where}, in another order`, w, h, ws, root, stand(w, h, ws, shuffled(offered, r)), kept, refusedBy, offered);
    }
  }
}

function compare(o: Out, where: string, w: World4, h: Holder, ws: string, root: string, s: Stood, kept: Map<string, Body>, refusedBy: Map<string, string>, offered: Body[]) {
  const say = (what: string, a: string, b: string) => {
    if (a !== b) o.differ.push(`${where}: ${what}: the core ${a || "none"}, the model ${b || "none"}`);
  };
  for (const [g, k] of h.logs) {
    o.logs++;
    say(`log #${g.slice(0, 6)}`, (s.logs.get(g)?.entries ?? []).map(hashOf).join(","), k.active.join(","));
  }
  say("bodies kept", sorted([...s.bodies].filter(([, b]) => (b as Body).ws === ws).map(([hb]) => hb)), sorted([...kept].filter(([, b]) => b.ws === ws).map(([hb]) => hb)));
  for (const b of offered) {
    const want = refusedBy.get(modelBodyHash(b));
    if (want === undefined) continue;
    o.refused[want] = (o.refused[want] ?? 0) + 1;
    say(`refusal of ${modelBodyHash(b).slice(0, 8)}`, take(s, ws, b) ?? "taken", want);
  }
  const chains = new Map([...s.logs].map(([g, k]) => [g, k.entries] as const));
  const lack = w.lacking(h, ws).map((x) => w.entry(x).body.h as string);
  o.lacking += lack.length;
  say("lacking", sorted(lackingOf(ws, chains, (hb) => s.bodies.has(hb))), sorted(new Set(lack)));
  const chain = chainFor(w, h, ws, root);
  const f = inForce(ws, chain, chains, [...s.bodies.values()], w.clock(h) * 1000);
  if (f.root !== null) o.moved++;
  const want = w.d4(h, ws);
  const got = d4Of(f);
  const waits = want === "no root" || (typeof want !== "string" && want.on === "not on");
  if (got === "waiting") o.waiting++;
  if (got === "off") o.off++;
  if (waits) {
    say("state", typeof got === "string" ? got : "on", "waiting");
    if (typeof want !== "string") o.stricter++;
    // (waiting names nobody and nothing)
    if (f.f.members.size + f.f.devices.size + f.f.stations.size > 0) o.differ.push(`${where}: waiting names someone`);
  } else if (typeof want === "string" || typeof got === "string") say("state", d4Said(got), d4Said(want));
  else {
    o.on++;
    for (const m of want.members.values()) o.webs += m.webs.length;
    const diff = d4Diff(got, want);
    if (diff.length > 0) o.differ.push(`${where}: state differs in ${diff.join(", ")}: the core ${d4Said(got)}; the model ${d4Said(want)}`);
  }
}

const drawnOptions = (seed: number) => (seed % 3 === 1 ? { holdBack: { station: seed % 3, nth: 1 + ((seed * 7) % 5) } } : seed % 3 === 2 ? { two: true } : {});

export function drawnWorlds(v: V3v, family: Family, from: number, to: number, steps: number): Out {
  const o = fresh();
  for (let seed = from; seed <= to; seed++) {
    const w = new World4(seed, v, family, drawnOptions(seed));
    const r = new Rng(seed ^ 0x5a7e);
    const st = drawSteps3(seed, steps);
    const at = (q: string) => `seed ${seed} ${family} ${JSON.stringify(drawnOptions(seed))} ${q}`;
    for (let q = 0; q < 4; q++) {
      w.run(st.slice(Math.floor((q * st.length) / 4), Math.floor(((q + 1) * st.length) / 4)));
      devices4(o, w, at(`quarter ${q + 1}`), r);
    }
    w.finish();
    devices4(o, w, at("end"), r, [], true);
    o.worlds++;
  }
  return o;
}

export function scriptedWorlds(from: number, to: number): Out {
  const o = fresh();
  const r = new Rng(from ^ 0x5a7f);
  look4.at = (w, where, offered) => devices4(o, w, where, r, offered ?? []);
  try {
    for (let seed = from; seed <= to; seed++) {
      m2(seed);
      if (seed === from) for (const skew of [0, 300, 3600]) m5Clock(seed, skew, false);
      for (const kind of ["web", "off"] as const) for (const parent of ["same", "any"] as const) revoked(seed, kind, parent);
      m6(seed);
      for (const m of [{}, { away: true }, { attack: "same" as const }, { attack: "any" as const }]) m7(seed, m);
      for (const m of [{}, { away: true }]) m8(seed, m);
      o.worlds++;
    }
  } finally {
    look4.at = null;
  }
  return o;
}

export type Job = { t: "drawn"; v: number; family: Family; from: number; to: number; steps: number } | { t: "scripted"; from: number; to: number };
export const runJob = (j: Job): Out => (j.t === "drawn" ? drawnWorlds(V3[j.v]!, j.family, j.from, j.to, j.steps) : scriptedWorlds(j.from, j.to));

if (!isMainThread && (workerData as { movedCore?: boolean } | null)?.movedCore === true) {
  parentPort!.on("message", (m: { id: number; job: Job }) => {
    parentPort!.postMessage({ id: m.id, out: runJob(m.job) });
  });
}
