// The workspace lock between the workspace's stations (docs/workspace-lock.md): so that a control plane holding back
// entries (a member removed, a device taken away) holds them back from nobody. Over `stillfail/station/1`, only with
// stations the lock names: `lock.head` says how far one is, `lock.get {after}` gives its entries after that, `lock.put
// {entries}` offers some. Each station checks every entry itself (cloud/state.ts `takeLock`).
import { log } from "../ops/log.ts";
import type { Cloud } from "../cloud/state.ts";
import { asEntry, type Entry } from "../cloud/lock.ts";
import type { PeerCall } from "../jobs/remote.ts";

/// A lock request of another station of the workspace (the transport checked it is in the roster, so in the lock).
export function answerLock(cloud: Cloud, request: any): unknown {
  const locked = cloud.locked();
  const seq = locked?.state?.seq ?? -1;
  switch (request?.method) {
    case "lock.head":
      return { seq, hash: locked?.state?.head ?? null };
    case "lock.get":
      return { entries: cloud.lockAfter(Number.isSafeInteger(request.after) ? request.after : -1) };
    case "lock.put": {
      // Only more of the lock this station pinned: a peer never pins one here.
      if (locked === null) throw new Error("this station has no workspace lock");
      const entries = Array.isArray(request.entries) ? request.entries.map(asEntry) : [];
      if (entries.some((e: Entry | null) => e === null)) throw new Error("a malformed lock entry");
      return { taken: cloud.takeLock(entries), seq: cloud.locked()?.state?.seq ?? seq };
    }
  }
  throw new Error("unknown lock method");
}

/// Brings one peer and this station level: gives it what it lacks, takes what it has more.
export async function syncWith(cloud: Cloud, call: PeerCall, peer: string): Promise<void> {
  const mine = cloud.locked()?.state;
  if (!mine) return;
  const head: any = await call(peer, null, { method: "lock.head" });
  const theirs = Number.isSafeInteger(head?.seq) ? head.seq : -1;
  if (theirs < 0) return;
  if (theirs < mine.seq) await call(peer, null, { method: "lock.put", entries: cloud.lockAfter(theirs) });
  else if (theirs > mine.seq) {
    const got: any = await call(peer, null, { method: "lock.get", after: mine.seq });
    const entries = (Array.isArray(got?.entries) ? got.entries : []).map(asEntry);
    if (entries.some((e: Entry | null) => e === null)) throw new Error("a malformed lock entry");
    cloud.takeLock(entries);
  }
}

/// Whenever this station's lock grows, or a roster comes, each station of the lock is brought level with it.
export function followLock(cloud: Cloud, call: PeerCall): () => void {
  let seq = -1;
  let roster = "";
  const look = () => {
    const s = cloud.locked()?.state;
    const st = cloud.state;
    if (!s || !st || !cloud.peersCurrent) return;
    const peers: string[] = st.peers.flatMap((p: any) => (typeof p?.id === "string" && p.id !== st.station ? [p.id] : []));
    const now = peers.join(",");
    if (s.seq === seq && now === roster) return;
    seq = s.seq;
    roster = now;
    for (const peer of peers) {
      syncWith(cloud, call, peer).catch((e) => log.info("lock", "a station's lock was not brought level", { peer: peer.slice(0, 12), error: (e as Error).message }));
    }
  };
  look();
  return cloud.listen(look);
}
