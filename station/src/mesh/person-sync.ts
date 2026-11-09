// Each person's own lock between the stations of the workspaces it was heard in: a device brings its
// person's chain to the stations it reaches, and the others of each of their workspaces have it from them, so a device of
// the person's that reaches another of them reads it there (person-chains.ts). As the workspace lock is
// (lock-sync.ts), over `stillfail/station/1`: `lock.person.heads` says how long each chain heard in the workspace is
// there, `lock.person.get {genesis}` gives one, `lock.person.put {chain}` offers one. Each station checks every chain
// itself (the rules' `personFold`) and keeps it only as it goes on from the one it has.
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import type { Cloud } from "../cloud/state.ts";
import { personFold } from "../cloud/lock.ts";
import type { PeerCall } from "./bus.ts";
import { CHAIN_MOST, type PersonChains, subOf } from "./person-chains.ts";
import { RETRY_MOST_MS, RETRY_MS } from "./lock-sync.ts";

/// A chain as it is brought: checked by the rules for its person, and as going on from the one kept. Its genesis;
/// throws why not.
export function checkChain(chains: PersonChains, chain: unknown, sub: string | null = null): { genesis: string; chain: unknown[] } {
  if (!Array.isArray(chain) || chain.length === 0 || chain.length > CHAIN_MOST) throw new Error("a person's lock: its entries");
  const whose = subOf(chain);
  if (whose === null || (sub !== null && whose !== sub)) throw new Error("a lock of another person's");
  const { genesis } = personFold(chain, whose);
  return { genesis, chain: chains.newest(genesis, whose, chain) };
}

/// A person's lock request of another station of workspace `ws` (the transport checked it is one of its stations).
export function answerPerson(chains: PersonChains, request: any, ws: string): unknown {
  switch (request?.method) {
    case "lock.person.heads":
      return { heads: Object.fromEntries(chains.heardIn(ws).map(([genesis, chain]) => [genesis, chain.length])) };
    case "lock.person.get": {
      const found = chains.heardIn(ws).find(([genesis]) => genesis === request.genesis);
      return { chain: found?.[1] ?? null };
    }
    case "lock.person.put": {
      const { genesis, chain } = checkChain(chains, request.chain);
      chains.keep(genesis, chain, ws);
      return { length: chain.length };
    }
  }
  throw new Error("unknown lock method");
}

/// Brings one peer and this station level in workspace `ws`: gives it the chains it has fewer of, takes those it has
/// more of.
export async function personSyncWith(chains: PersonChains, call: PeerCall, peer: string, ws: string): Promise<void> {
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
    const { genesis: g, chain } = checkChain(chains, got?.chain);
    chains.keep(g, chain, ws);
  }
}

/// Whenever a chain kept here grows, or a roster comes, each station of each workspace this one is in is brought level
/// with it in the chains heard there; one that could not be (offline, the line between them down) is tried again,
/// sooner at first, until it is.
export function followPersons(cloud: Cloud, chains: PersonChains, call: PeerCall, after: (ms: number, f: () => void) => () => void = wall.after): () => void {
  // Each peer of each workspace: what this station had heard there when last brought level with it (each chain's
  // length); one being brought level now; one that failed, how long it waits and whether that wait is over.
  const level = new Map<string, string>();
  const going = new Set<string>();
  const retries = new Map<string, { wait: number; due: boolean; cancel: () => void }>();
  let stopped = false;
  const bring = (peer: string, ws: string, heads: string) => {
    const key = `${ws}|${peer}`;
    const retry = retries.get(key);
    if (level.get(key) === heads || going.has(key) || (retry !== undefined && !retry.due)) return;
    going.add(key);
    personSyncWith(chains, call, peer, ws).then(
      () => {
        level.set(key, headsIn(chains, ws));
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
      const heads = headsIn(chains, m.workspace);
      for (const p of m.peers) if (typeof p?.id === "string" && p.id !== st.station) bring(p.id, m.workspace, heads);
    }
  };
  look();
  const unlistenCloud = cloud.listen(look);
  const unlistenChains = chains.listen(look);
  return () => {
    stopped = true;
    unlistenCloud();
    unlistenChains();
    for (const r of retries.values()) r.cancel();
    retries.clear();
  };
}

/// What this station heard in `ws`, as a word that changes when any of it does.
const headsIn = (chains: PersonChains, ws: string) => chains.heardIn(ws).map(([g, c]) => `${g}:${c.length}`).sort().join(",");
