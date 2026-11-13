// What a station tells its members' devices of the locks, on their event streams (GET /events): `lock`, the head of a
// workspace's lock moved (`{workspace, head}`, to that workspace's members), and `person`, a person's own lock's did
// (`{genesis, length}`, to that person's devices): on, or to another branch the fork choice gives
// (cloud/log-keep.ts). Where a workspace's chain moved to its people's logs, `lock` is told also each time the state in
// force there changes (a member's log moved, a body came: Cloud `forceWord`), its head the chain's as before. A device
// reads the lock of the station when told, as it reads anything it is told changed; it does not ask the cloud (the
// root AGENTS.md, The cloud is the account system).
import type { Cloud } from "../cloud/state.ts";
import type { To } from "../api/events.ts";
import type { PersonChains } from "./person-chains.ts";
import { subOf } from "./person-chains.ts";
import { lockHead } from "./serve.ts";

export type Tell = (event: string, data: unknown, of: string, to: To) => void;

/// Tells each change of a lock this station keeps, from now on; returns what stops it.
export function tellLocks(cloud: Cloud, chains: PersonChains, tell: Tell): () => void {
  // How far each workspace's lock went when last looked at.
  const last = new Map<string, string>();
  const look = () => {
    for (const m of cloud.memberships()) {
      const ws = m.home ? null : m.workspace;
      const head = lockHead(cloud, ws);
      const now = head === null ? "" : `${head.seq}:${head.hash}:${cloud.forceWord(ws)}`;
      const was = last.get(m.workspace);
      last.set(m.workspace, now);
      if (was !== undefined && was !== now) tell("lock", { workspace: m.workspace, head }, `lock\0${m.workspace}`, { workspace: m.workspace });
    }
  };
  look();
  const unlistenCloud = cloud.listen(look);
  const unlistenChains = chains.listen((genesis) => {
    const chain = chains.kept(genesis);
    const sub = chain === null ? null : subOf(chain);
    if (chain !== null && sub !== null) tell("person", { genesis, length: chain.length }, `person\0${genesis}`, { subs: [sub] });
  });
  return () => {
    unlistenCloud();
    unlistenChains();
  };
}
