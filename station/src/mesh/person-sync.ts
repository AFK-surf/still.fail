// Each person's own lock between the stations of the workspaces it was heard in: a device brings its
// person's chain to the stations it reaches, and the others of each of their workspaces have it from them, so a device of
// the person's that reaches another of them reads it there (person-chains.ts). As the workspace lock is
// (lock-sync.ts), over `stillfail/station/1`: `lock.person.kept` says the hashes of every entry each log heard in the
// workspace keeps there (its chain and those off it), `lock.person.get {genesis, hashes}` gives those, and
// `lock.person.offer {genesis, entries}` offers some, kept as the rules take them; two stations that give each other
// what the other lacks keep the same entries, so go by the same chain. A station from before knows only
// `lock.person.heads` (how long each chain is), `lock.person.get {genesis}` (one chain) and `lock.person.put {chain}`:
// answered as before, and asked as before where the other is one of them (it does not answer `lock.person.kept` with
// `logs`). Each station checks every entry itself.
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import type { Cloud } from "../cloud/state.ts";
import { asEntry, type Entry, LockRefusal, personFold } from "../cloud/lock.ts";
import { ASIDE_MOST, hashOf } from "../cloud/log-keep.ts";
import type { PeerCall } from "./bus.ts";
import { AT_ODDS, CHAIN_MOST, type PersonChains, subOf } from "./person-chains.ts";
import { RETRY_MOST_MS, RETRY_MS, unknownMethod } from "./lock-sync.ts";

/// A chain as it is brought: checked by the rules for its person, and as going on from the one kept. Its genesis;
/// throws why not.
export function checkChain(chains: PersonChains, chain: unknown, sub: string | null = null): { genesis: string; chain: unknown[] } {
  const { genesis, whose } = foldChain(chain, sub);
  return { genesis, chain: chains.newest(genesis, whose, chain as unknown[]) };
}

/// A chain as it is brought, checked by the rules for its person: its genesis and whose; throws why not.
export function foldChain(chain: unknown, sub: string | null = null): { genesis: string; whose: string } {
  if (!Array.isArray(chain) || chain.length === 0 || chain.length > CHAIN_MOST) throw new Error("a person's lock: its entries");
  const whose = subOf(chain);
  if (whose === null || (sub !== null && whose !== sub)) throw new Error("a lock of another person's");
  return { genesis: personFold(chain, whose).genesis, whose };
}

/// A chain brought by a device or a station from before, taken (PersonChains.take; `fork`: a station's, or a device's
/// saying another keeper took it): `on`, whether the last brought is on the chain gone by now.
export function takeChain(chains: PersonChains, chain: unknown, sub: string | null, ws: string | null, fork = false) {
  const { genesis, whose } = foldChain(chain, sub);
  const t = chains.take(genesis, whose, chain as unknown[], ws, fork);
  return { genesis, ...t };
}

/// What a person's own lock is told of: its genesis and how far its chain gone by goes.
const headOf = (chain: unknown[]) => ({ seq: chain.length - 1, hash: chain.length === 0 ? null : hashOf(chain.at(-1) as Entry) });

/// A person's lock request of another station of workspace `ws` (the transport checked it is one of its stations).
export function answerPerson(chains: PersonChains, request: any, ws: string): unknown {
  switch (request?.method) {
    case "lock.person.heads":
      return { heads: Object.fromEntries(chains.heardIn(ws).map(([genesis, chain]) => [genesis, chain.length])) };
    case "lock.person.get": {
      const found = chains.heardIn(ws).find(([genesis]) => genesis === request.genesis);
      if (Array.isArray(request.hashes)) {
        const want = new Set(request.hashes.filter((h: unknown) => typeof h === "string"));
        return { entries: found === undefined ? [] : chains.all(found[0]).filter((e) => want.has(hashOf(e))) };
      }
      return { chain: found?.[1] ?? null };
    }
    case "lock.person.put": {
      const t = takeChain(chains, request.chain, null, ws, true);
      if (!t.on) throw new LockRefusal(AT_ODDS);
      return { length: t.chain.length };
    }
    case "lock.person.kept":
      return { logs: Object.fromEntries(chains.heardIn(ws).map(([genesis]) => [genesis, chains.all(genesis).map(hashOf)])) };
    case "lock.person.offer": {
      const genesis = typeof request.genesis === "string" ? request.genesis : "";
      const entries = Array.isArray(request.entries) ? request.entries.map(asEntry) : [];
      if (entries.length === 0 || entries.some((e: Entry | null) => e === null)) throw new Error("a malformed lock entry");
      const sub = subOf(entries);
      if (sub === null || entries.length > CHAIN_MOST + ASIDE_MOST) throw new Error("a person's lock: its entries");
      // A log not kept here yet comes with its genesis, as a chain does.
      const t = chains.take(genesis, sub, entries, ws, true);
      return { taken: t.taken, head: headOf(t.chain) };
    }
  }
  throw new Error("unknown lock method");
}

/// What this station gives station `peer` of workspace `ws`'s bodies (by hash): every one, to a station its own state
/// there names (before the chain moved, its chain's; where it waits for the root, none), whatever the control plane's
/// roster says; to one a removal took out of it, that removal's and its `prev` chain (Cloud `toldOut`); else none.
export function bodiesGiven(cloud: Cloud, ws: string, peer: string): Map<string, unknown> {
  const w = ws === cloud.home() ? null : ws;
  const all = cloud.bodies(w).all();
  const l = cloud.locked(w);
  if (l?.state && l.waiting !== true && l.state.stations.has(peer)) return all;
  const out = new Map<string, unknown>();
  for (const h of cloud.toldOut(w, peer)) if (all.has(h)) out.set(h, all.get(h));
  return out;
}

/// A bodies request of station `peer` of workspace `ws` (the transport checked it is one of its stations):
/// `lock.bodies.kept` the hashes of those this station gives it, `lock.bodies.get {hashes}` those, `lock.bodies.offer
/// {bodies}` some, kept as the rules take them (Cloud `takeBodies`). Nothing of another workspace is said or given.
export function answerBodies(cloud: Cloud, request: any, ws: string, peer: string | null): unknown {
  const w = ws === cloud.home() ? null : ws;
  switch (request?.method) {
    case "lock.bodies.kept":
      return { hashes: peer === null ? [] : [...bodiesGiven(cloud, ws, peer).keys()] };
    case "lock.bodies.get": {
      const given = peer === null ? new Map() : bodiesGiven(cloud, ws, peer);
      const want = Array.isArray(request.hashes) ? request.hashes.filter((h: unknown): h is string => typeof h === "string") : [];
      return { bodies: want.flatMap((h: string) => (given.has(h) ? [given.get(h)] : [])) };
    }
    case "lock.bodies.offer": {
      const bodies = Array.isArray(request.bodies) ? request.bodies : [];
      if (bodies.length > BODIES_OFFERED) throw new Error("too many bodies");
      return { taken: cloud.takeBodies(w, bodies).taken };
    }
  }
  throw new Error("unknown lock method");
}

/// Whether `cloud` keeps bodies (a Cloud of a test's made of a few methods keeps none).
const keepsBodies = (cloud: Cloud) => typeof cloud.chain === "function" && typeof cloud.bodies === "function";

/// How many bodies one offer brings at most.
const BODIES_OFFERED = 4096;

/// Brings one peer and this station level in workspace `ws`'s bodies: gives it those it lacks of what this station
/// gives it, and asks for those it says it has that this station lacks. A station from before answers none.
export async function bodiesSyncWith(cloud: Cloud, call: PeerCall, peer: string, ws: string): Promise<void> {
  if (!keepsBodies(cloud)) return;
  const w = ws === cloud.home() ? null : ws;
  if (cloud.chain(w) === null) return;
  let said: any;
  try {
    said = await call(peer, ws, { method: "lock.bodies.kept" });
  } catch (e) {
    if (unknownMethod(e)) return;
    throw e;
  }
  const theirs = new Set((Array.isArray(said?.hashes) ? said.hashes : []).filter((h: unknown): h is string => typeof h === "string"));
  const given = bodiesGiven(cloud, ws, peer);
  const lacks = [...given].filter(([h]) => !theirs.has(h)).map(([, b]) => b);
  if (lacks.length > 0) await call(peer, ws, { method: "lock.bodies.offer", bodies: lacks.slice(0, BODIES_OFFERED) });
  const have = cloud.bodies(w);
  const want = [...theirs].filter((h) => !have.has(h as string));
  if (want.length === 0) return;
  const got: any = await call(peer, ws, { method: "lock.bodies.get", hashes: want });
  const bodies = Array.isArray(got?.bodies) ? got.bodies : [];
  if (bodies.length > 0 && bodies.length <= BODIES_OFFERED) cloud.takeBodies(w, bodies);
}

/// Brings one peer and this station level in workspace `ws`: gives it the entries of each log it lacks and takes those
/// it has more; with a station from before, gives it the chains it has fewer of and takes those it has more of.
export async function personSyncWith(chains: PersonChains, call: PeerCall, peer: string, ws: string): Promise<void> {
  let said: any;
  try {
    said = await call(peer, ws, { method: "lock.person.kept" });
  } catch (e) {
    if (!unknownMethod(e)) throw e;
    return asBefore(chains, call, peer, ws);
  }
  if (said?.logs === null || typeof said?.logs !== "object") return asBefore(chains, call, peer, ws);
  const theirs: Record<string, unknown> = said.logs;
  const mine = new Map(chains.heardIn(ws));
  for (const [genesis] of mine) {
    const has = new Set(Array.isArray(theirs[genesis]) ? (theirs[genesis] as unknown[]) : []);
    const lacks = chains.all(genesis).filter((e) => !has.has(hashOf(e)));
    if (lacks.length > 0) await call(peer, ws, { method: "lock.person.offer", genesis, entries: lacks });
  }
  for (const [genesis, hs] of Object.entries(theirs)) {
    if (!Array.isArray(hs)) continue;
    const have = new Set(chains.all(genesis).map(hashOf));
    const want = hs.filter((h): h is string => typeof h === "string" && !have.has(h));
    if (want.length === 0) continue;
    const got: any = await call(peer, ws, { method: "lock.person.get", genesis, hashes: want });
    const entries = (Array.isArray(got?.entries) ? got.entries : []).map(asEntry);
    if (entries.some((e: Entry | null) => e === null)) throw new Error("a malformed lock entry");
    const sub = subOf(entries);
    if (entries.length === 0 || sub === null) continue;
    chains.take(genesis, sub, entries, ws, true);
  }
}

/// As stations brought each other level before every entry was kept (a peer that knows none of the methods above).
async function asBefore(chains: PersonChains, call: PeerCall, peer: string, ws: string): Promise<void> {
  const said: any = await call(peer, ws, { method: "lock.person.heads" });
  const theirs: Record<string, unknown> = said?.heads !== null && typeof said?.heads === "object" ? said.heads : {};
  const mine = new Map(chains.heardIn(ws));
  for (const [genesis, chain] of mine) {
    const n = theirs[genesis];
    if (typeof n !== "number" || n < chain.length) await call(peer, ws, { method: "lock.person.put", chain });
  }
  for (const [genesis, n] of Object.entries(theirs)) {
    if (typeof n !== "number" || n <= (mine.get(genesis)?.length ?? 0)) continue;
    const got: any = await call(peer, ws, { method: "lock.person.get", genesis });
    const t = takeChain(chains, got?.chain, null, ws, true);
    if (!t.on) throw new LockRefusal(AT_ODDS);
  }
}

/// Whenever a chain kept here moves, a body comes, or a roster comes, each station of each workspace this one is in is brought level
/// with it in the logs heard there; one that could not be (offline, the line between them down) is tried again,
/// sooner at first, until it is.
export function followPersons(cloud: Cloud, chains: PersonChains, call: PeerCall, after: (ms: number, f: () => void) => () => void = wall.after): () => void {
  // Each peer of each workspace: what this station had heard there when last brought level with it (each log's head
  // and how many it keeps); one being brought level now; one that failed, how long it waits and whether that wait is over.
  const level = new Map<string, string>();
  const going = new Set<string>();
  const retries = new Map<string, { wait: number; due: boolean; cancel: () => void }>();
  let stopped = false;
  const bring = (peer: string, ws: string, heads: string) => {
    const key = `${ws}|${peer}`;
    const retry = retries.get(key);
    if (level.get(key) === heads || going.has(key) || (retry !== undefined && !retry.due)) return;
    going.add(key);
    personSyncWith(chains, call, peer, ws).then(() => bodiesSyncWith(cloud, call, peer, ws)).then(
      () => {
        // (what it had heard as this began: what it took meanwhile brings it again)
        level.set(key, heads);
        retries.delete(key);
      },
      (e) => {
        log.info("lock", "a station's person locks were not brought level", { peer: peer.slice(0, 12), error: (e as Error).message, workspace: ws });
        if (stopped) return;
        const wait = retry === undefined ? RETRY_MS : Math.min(retry.wait * 2, RETRY_MOST_MS);
        const r = { wait, due: false, cancel: () => {} };
        r.cancel = after(wait, () => { // timer: a retry after a failure, with a backoff
          r.due = true;
          look();
        });
        retries.set(key, r);
      },
    ).finally(() => {
      going.delete(key);
      if (!stopped) look();
    });
  };
  const look = () => {
    const st = cloud.state;
    if (stopped || !st || !cloud.peersCurrent) return;
    for (const m of cloud.memberships()) {
      // (and the bodies it keeps there, and what it lacks: a body come or a statement heard brings it again)
      const w = m.home ? null : m.workspace;
      const heads = `${headsIn(chains, m.workspace)}|${!keepsBodies(cloud) || cloud.chain(w) === null ? "" : `${cloud.bodies(w).all().size}:${cloud.lacking(w).length}:${cloud.forceWord(w)}`}`;
      for (const p of m.peers) if (typeof p?.id === "string" && p.id !== st.station) bring(p.id, m.workspace, heads);
    }
  };
  look();
  const unlistenCloud = cloud.listen(look);
  const unlistenChains = chains.watch(look);
  return () => {
    stopped = true;
    unlistenCloud();
    unlistenChains();
    for (const r of retries.values()) r.cancel();
    retries.clear();
  };
}

/// What this station heard in `ws`, as a word that changes when any of it does.
const headsIn = (chains: PersonChains, ws: string) =>
  chains.heardIn(ws).map(([g, c]) => `${g}:${c.length}:${headOf(c).hash}:${chains.asideOf(g)}`).sort().join(",");
