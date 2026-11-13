// The station held to the fourth round's model (lock-roster4-model.ts, its defaults), as rules-fork-check.ts holds the
// rules to it: at each quarter of a drawn world and at its end, and at each look of the scripted ones (`look4.at`), every
// keeper of the model's world (each station, and each device, which keeps a workspace as a station does) is stood for by a real station (`Cloud` with its `PersonChains` and `LockBodies`) given
// what the model's keeper stores then: every entry of every log it stores, as another keeper's; the workspace chain
// with its `moved` (the model's old chain where the world has one, M7; else a genesis and a `moved {root}` by the root's
// own app); and the bodies the world offered it, in the order made and again in a drawn other order. Its clock is the
// keeper's. Compared, field for field: each log's chain gone by; the bodies kept, and each refusal's reason; `lacking`;
// `Cloud.locked` against the model's `d4`; and what it gives every other holder against the model's `bodiesFor`.
//
// Offered: the bodies the keeper keeps, and every body the world made that the model's keeper would refuse (so taking
// is the station's own decision); a body the keeper would take but has not been given yet (in flight, held back) is
// not offered: the model does not record what a keeper was offered and turned down otherwise.
//
// Where the station is stricter on purpose: a state the model calls "not on" (no `open` or `off` in force) or "no
// root" (the root's log not kept) is one the station waits in (`waiting`): it names nobody and gives nobody a body
// (the model's keeper lists whom the statements in force name). Compared there: the station waits, gives none.
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { isMainThread, parentPort, workerData } from "node:worker_threads";
import { type Entry, canonical, entryHash, signedBytes } from "../src/cloud/lock.ts";
import { Cloud, personChainsOf, writeState } from "../src/cloud/state.ts";
import { wall } from "../src/ops/fibers.ts";
import { bodiesGiven } from "../src/mesh/person-sync.ts";
import { hashOf } from "./lock-fork-choice-model.ts";
import { type Body, type D4, type D4Member, type W4Options, WS2, World4, bodyHash, d4Diff, d4Said, look4, m2, m5Clock, m6, m7, revoked } from "./lock-roster4-model.ts";
import { type Family, type Holder, V3, type V3v, drawSteps3, spec } from "./lock-roster-model.ts";
import { Rng, WS } from "./lock-world-sim.ts";

let clock = 0;
wall.now = () => clock * 1000;

export type Out = {
  worlds: number; stations: number; differ: string[];
  logs: number; bodiesOffered: number; refused: Record<string, number>; lacking: number;
  on: number; off: number; waiting: number; webs: number; moved: number; given: number; toldOut: number; stricter: number;
};
export const fresh = (): Out => ({ worlds: 0, stations: 0, differ: [], logs: 0, bodiesOffered: 0, refused: {}, lacking: 0, on: 0, off: 0, waiting: 0, webs: 0, moved: 0, given: 0, toldOut: 0, stricter: 0 });

function shuffled<T>(xs: T[], r: Rng): T[] {
  const out = [...xs];
  for (let i = out.length - 1; i > 0; i--) {
    const j = r.int(i + 1);
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}
const sorted = (xs: Iterable<string>) => [...xs].sort().join(",");

/// The workspace chain of `ws` a station under test pins: the model keeper's old chain where it keeps one (M7), else a
/// genesis whose owner is the root's person with the root's app, and its `moved {root}`.
const made = new Map<string, Entry[]>();
function chainFor(w: World4, h: Holder, ws: string, root: string): Entry[] {
  const old = w.x.old.get(h);
  if (old !== undefined && ws === WS) return old.active.map((x) => old.store.get(x)!);
  const id = `${ws}|${root}`;
  const had = made.get(id);
  if (had) return had;
  const app = spec("alice's app");
  const sign = (e: Omit<Entry, "sig">): Entry => ({ ...e, sig: { key: app.signer.id, alg: "Ed25519", sig: app.signer.sign(signedBytes(entryHash(e as Entry))) } }) as Entry;
  const g = sign({ v: 1, ws, seq: 0, prev: null, at: 1000, kind: "genesis", body: {
    owner: "alice", origins: [], rp_id: "", cloud_keys: { keys: [] }, members: [{ sub: "alice", email: "alice@x", role: "owner" }],
    devices: [{ id: app.base.hex, sub: "alice", kind: "app", label: app.name, sign_key: app.signer.id }], passkeys: [], stations: [], gateways: [],
  } });
  const moved = sign({ v: 1, ws, seq: 1, prev: entryHash(g), at: 1000, kind: "moved", body: { root } });
  made.set(id, [g, moved]);
  return [g, moved];
}

/// A station under test standing for keeper `h` in `ws`: made once a world (and anew for a drawn other order), given
/// at each look what came since: the entries the keeper stores (as another keeper's), its chain, the bodies offered.
type Stood = { c: Cloud; given: Set<string> };
function stand(w: World4, h: Holder, ws: string, root: string, offered: Body[], was?: Stood): Stood {
  let s = was;
  if (s === undefined) {
    const data = mkdtempSync(join(tmpdir(), "lmm-"));
    writeState(data, {
      origin: "https://app.still.fail", station: w.keyOfHolder(h), workspace: ws, workspace_name: "W", name: h.name, relay_url: "", relay_urls: [],
      grant_keys: { keys: [] }, peers: [], revocations: [],
    });
    s = { c: new Cloud(data, false), given: new Set() };
  }
  const c = s.c;
  const chain = chainFor(w, h, ws, root);
  if (c.chain() === null) c.takeLock(chain.slice(0, 1));
  c.takeLock(chain, null, true);
  const chains = personChainsOf(c);
  for (const [g, k] of h.logs) {
    const fresh = [...k.store.values()].filter((e) => !s!.given.has(hashOf(e)));
    if (fresh.length === 0) continue;
    chains.keep(g, [k.store.get(g)!, ...fresh.filter((e) => hashOf(e) !== g)], ws, true);
    for (const e of fresh) s.given.add(hashOf(e));
  }
  const mine = c.bodies(null);
  const left = offered.filter((b) => !mine.has(bodyHash(b)));
  if (left.length > 0) c.takeBodies(null, left);
  return s;
}

/// The model's `bodiesFor` without what `to` has or was never to be given (who is given what, not what is new to it).
function modelGives(w: World4, h: Holder, to: Holder, ws: string): Set<string> {
  const out = new Set<string>();
  const kept = w.keptOf(h);
  if (!w.pinsOf(to).has(ws)) return out;
  const all = w.admits(h, to, ws);
  for (const [hb, b] of kept) {
    if (b.ws !== ws) continue;
    if (all) out.add(hb);
    else if ((b.kind === "member.remove" || b.kind === "station.remove") && w.admitsBefore(h, to, b)) {
      out.add(hb);
      for (let p = b.prev, n = 0; p !== null && n < 10_000; n++) {
        const q = kept.get(p);
        if (q === undefined) break;
        out.add(p);
        p = q.prev;
      }
    }
  }
  return out;
}

/// The station's state as the model's D4 has one (its members by the person log each is bound by).
function d4Of(c: Cloud): D4 | string {
  const l = c.locked();
  if (l === null) return "off";
  if (l.waiting === true) return "waiting";
  const s = l.state!;
  const devs = (sub: string, kind: string) => [...s.devices.values()].filter((d) => d.sub === sub && d.kind === kind);
  const members = new Map<string, D4Member>([...s.members].map(([sub, m]) => [sub, {
    role: m.role, email: m.email === "" ? "-" : m.email, lock: s.persons.get(sub) ?? "none",
    apps: devs(sub, "app").map((d) => d.sign_key!).sort(), webs: devs(sub, "web").map((d) => d.id).sort(),
  }]));
  return { on: "on", settings: canonical({ origins: s.origins, rp_id: s.rp_id, cloud_keys: s.cloud_keys }), members, stations: [...s.stations.keys()].sort() };
}

const stood = new WeakMap<World4, Map<string, Stood>>();

/// Every keeper of `w` that goes by a root, compared at `at`: each station, and each device too, stood for by a station
/// given what it keeps (a device keeps a workspace as a station does: the model's keepers are both); `extra`, bodies
/// offered there that no keeper keeps (M2's); `last`, the world's last look, where a station is also made anew and given
/// the same in a drawn other order. A keeper of two workspaces is a station under test in each, offered the bodies of
/// that one (and of none it keeps); a body of the other is that one's to judge.
export function stations4(o: Out, w: World4, at: string, r: Rng, extra: Body[] = [], last = false) {
  const mine = stood.get(w) ?? stood.set(w, new Map()).get(w)!;
  for (const h of w.holders) {
    const pins = w.pinsOf(h);
    for (const [ws, root] of pins) {
      if (!root) continue;
      o.stations++;
      o.moved++;
      const where = `${at}, ${h.name}, ${ws === WS ? "W1" : "W2"}`;
      clock = w.clock(h);
      const kept = w.keptOf(h);
      const refusedBy = new Map<string, string>();
      const offered: Body[] = [];
      for (const b of [...w.x.order.map((hb) => w.x.bodies.get(hb)!), ...extra]) {
        if (typeof b?.ws === "string" && b.ws !== ws && pins.has(b.ws)) continue;
        const hb = bodyHash(b);
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
      const s = stand(w, h, ws, root, offered, mine.get(id));
      mine.set(id, s);
      compare(o, where, w, h, ws, s.c, kept, refusedBy, offered);
      if (!last) continue;
      const again = stand(w, h, ws, root, shuffled(offered, r));
      try {
        compare(o, `${where}, in another order`, w, h, ws, again.c, kept, refusedBy, offered);
      } finally {
        rmSync(again.c.data, { recursive: true, force: true });
      }
    }
  }
}

/// The stations stood up for `w`, let go.
function done(w: World4) {
  for (const s of stood.get(w)?.values() ?? []) rmSync(s.c.data, { recursive: true, force: true });
  stood.delete(w);
}

function compare(o: Out, where: string, w: World4, h: Holder, ws: string, c: Cloud, kept: Map<string, Body>, refusedBy: Map<string, string>, offered: Body[]) {
  const say = (what: string, a: string, b: string) => {
    if (a !== b) o.differ.push(`${where}: ${what}: the station ${a || "none"}, the model ${b || "none"}`);
  };
  // each log's chain gone by
  const chains = personChainsOf(c);
  for (const [g, k] of h.logs) {
    o.logs++;
    say(`log #${g.slice(0, 6)}`, (chains.kept(g) as Entry[] | null ?? []).map(hashOf).join(","), k.active.join(","));
  }
  // the bodies kept, and why each other offered was not
  const mine = c.bodies(null).all();
  say("bodies kept", sorted([...mine.keys()].filter((hb) => (mine.get(hb) as Body).ws === ws)), sorted([...kept].filter(([, b]) => b.ws === ws).map(([hb]) => hb)));
  for (const b of offered) {
    const hb = bodyHash(b);
    const want = refusedBy.get(hb);
    if (want === undefined) continue;
    const got = c.takeBodies(null, [b]).refused[0]?.why ?? "taken";
    o.refused[want] = (o.refused[want] ?? 0) + 1;
    say(`refusal of ${hb.slice(0, 8)}`, got, want);
  }
  // lacking (the station's by body hash, the model's by entry)
  const lack = w.lacking(h, ws).map((x) => w.entry(x).body.h as string);
  o.lacking += lack.length;
  say("lacking", sorted(new Set(c.lacking(null))), sorted(new Set(lack)));
  // the state
  const want = w.d4(h, ws);
  const got = d4Of(c);
  const waits = want === "no root" || (typeof want !== "string" && want.on === "not on");
  if (got === "waiting") o.waiting++;
  if (got === "off") o.off++;
  if (waits) {
    say("state", typeof got === "string" ? got : "on", "waiting");
    if (typeof want !== "string") o.stricter++;
  } else if (typeof want === "string" || typeof got === "string") say("state", d4Said(got), d4Said(want));
  else {
    o.on++;
    for (const m of want.members.values()) o.webs += m.webs.length;
    const diff = d4Diff(got, want);
    if (diff.length > 0) o.differ.push(`${where}: state differs in ${diff.join(", ")}: the station ${d4Said(got)}; the model ${d4Said(want)}`);
  }
  // who is given what
  for (const to of w.holders) {
    if (to === h) continue;
    const key = w.keyOfHolder(to);
    const given = new Set([...bodiesGiven(c, ws, key).keys()].filter((hb) => (mine.get(hb) as Body | undefined)?.ws === ws));
    if (waits) {
      say(`given to ${to.name} while it waits`, sorted(given), "");
      continue;
    }
    const wanted = modelGives(w, h, to, ws);
    if (!w.pinsOf(to).has(ws)) continue;
    o.given++;
    if (!w.admits(h, to, ws) && wanted.size > 0) o.toldOut++;
    say(`given to ${to.name}`, sorted(given), sorted(wanted));
  }
}

const drawnOptions = (seed: number): W4Options => (seed % 3 === 1 ? { holdBack: { station: seed % 3, nth: 1 + ((seed * 7) % 5) } } : seed % 3 === 2 ? { two: true } : {});

export function drawnWorlds(v: V3v, family: Family, from: number, to: number, steps: number): Out {
  const o = fresh();
  for (let seed = from; seed <= to; seed++) {
    const w = new World4(seed, v, family, drawnOptions(seed));
    const r = new Rng(seed ^ 0x5a7e);
    const st = drawSteps3(seed, steps);
    const at = (q: string) => `seed ${seed} ${family} ${JSON.stringify(drawnOptions(seed))} ${q}`;
    for (let q = 0; q < 4; q++) {
      w.run(st.slice(Math.floor((q * st.length) / 4), Math.floor(((q + 1) * st.length) / 4)));
      stations4(o, w, at(`quarter ${q + 1}`), r);
    }
    w.finish();
    stations4(o, w, at("end"), r, [], true);
    done(w);
    o.worlds++;
  }
  return o;
}

export function scriptedWorlds(from: number, to: number): Out {
  const o = fresh();
  const r = new Rng(from ^ 0x5a7f);
  look4.at = (w, where, offered) => stations4(o, w, where, r, offered ?? [], true);
  try {
    for (let seed = from; seed <= to; seed++) {
      m2(seed);
      if (seed === from) for (const skew of [0, 300, 3600]) m5Clock(seed, skew, false);
      for (const kind of ["web", "off"] as const) for (const parent of ["same", "any"] as const) revoked(seed, kind, parent);
      m6(seed);
      for (const m of [{}, { away: true }, { attack: "same" as const }, { attack: "any" as const }]) m7(seed, m);
      o.worlds++;
    }
  } finally {
    look4.at = null;
  }
  return o;
}

export type Job = { t: "drawn"; v: number; family: Family; from: number; to: number; steps: number } | { t: "scripted"; from: number; to: number };
export const runJob = (j: Job): Out => (j.t === "drawn" ? drawnWorlds(V3[j.v]!, j.family, j.from, j.to, j.steps) : scriptedWorlds(j.from, j.to));

if (!isMainThread && (workerData as { movedModel?: boolean } | null)?.movedModel === true) {
  parentPort!.on("message", (m: { id: number; job: Job }) => {
    parentPort!.postMessage({ id: m.id, out: runJob(m.job) });
  });
}
void WS2;
