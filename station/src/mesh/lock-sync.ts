// The workspace lock between the workspace's stations (docs/workspace-lock.md): so that a control plane holding back
// entries (a member removed, a device taken away) holds them back from nobody. Over `stillfail/station/1`, only with
// stations the lock names: `lock.head` says how far one is, `lock.get {after}` gives its entries after that, `lock.put
// {entries}` offers some. Each station checks every entry itself (cloud/state.ts `takeLock`). A station in several
// workspaces (docs/multi-workspace.md) does this for each of their locks, with each one's stations, asked in it.
import { log } from "../ops/log.ts";
import type { Cloud } from "../cloud/state.ts";
import { asEntry, type Entry } from "../cloud/lock.ts";
import type { PeerCall } from "../jobs/remote.ts";

/// A lock request of another station of the workspace (the transport checked it is in the roster, so in the lock), of
/// the lock of the workspace it was asked in (`workspace`).
export function answerLock(cloud: Cloud, request: any, workspace: string | null = null): unknown {
  const ws = workspace && workspace !== cloud.home() ? workspace : null;
  const locked = cloud.locked(ws);
  const seq = locked?.state?.seq ?? -1;
  switch (request?.method) {
    case "lock.head":
      return { seq, hash: locked?.state?.head ?? null };
    case "lock.get":
      return { entries: cloud.lockAfter(Number.isSafeInteger(request.after) ? request.after : -1, ws) };
    case "lock.put": {
      // Only more of the lock this station pinned: a peer never pins one here.
      if (locked === null) throw new Error("this station has no workspace lock");
      const entries = Array.isArray(request.entries) ? request.entries.map(asEntry) : [];
      if (entries.some((e: Entry | null) => e === null)) throw new Error("a malformed lock entry");
      return { taken: cloud.takeLock(entries, ws), seq: cloud.locked(ws)?.state?.seq ?? seq };
    }
  }
  throw new Error("unknown lock method");
}

/// Brings one peer and this station level in workspace `ws` (null: the home one): gives it what it lacks, takes what it
/// has more.
export async function syncWith(cloud: Cloud, call: PeerCall, peer: string, ws: string | null = null): Promise<void> {
  const mine = cloud.locked(ws)?.state;
  if (!mine) return;
  const head: any = await call(peer, ws, { method: "lock.head" });
  const theirs = Number.isSafeInteger(head?.seq) ? head.seq : -1;
  if (theirs < 0) return;
  if (theirs < mine.seq) await call(peer, ws, { method: "lock.put", entries: cloud.lockAfter(theirs, ws) });
  else if (theirs > mine.seq) {
    const got: any = await call(peer, ws, { method: "lock.get", after: mine.seq });
    const entries = (Array.isArray(got?.entries) ? got.entries : []).map(asEntry);
    if (entries.some((e: Entry | null) => e === null)) throw new Error("a malformed lock entry");
    cloud.takeLock(entries, ws);
  }
}

/// Whenever this station's lock grows, or a roster comes, each station of the lock is brought level with it.
export function followLock(cloud: Cloud, call: PeerCall): () => void {
  // How far each workspace's lock went and its roster, when last brought level.
  const last = new Map<string, string>();
  const look = () => {
    const st = cloud.state;
    if (!st || !cloud.peersCurrent) return;
    for (const m of cloud.memberships()) {
      const ws = m.home ? null : m.workspace;
      const s = cloud.locked(ws)?.state;
      if (!s) continue;
      const peers: string[] = m.peers.flatMap((p: any) => (typeof p?.id === "string" && p.id !== st.station ? [p.id] : []));
      const now = `${s.seq}|${peers.join(",")}`;
      if (last.get(m.workspace) === now) continue;
      last.set(m.workspace, now);
      for (const peer of peers) {
        syncWith(cloud, call, peer, ws).catch((e) => log.info("lock", "a station's lock was not brought level", { peer: peer.slice(0, 12), error: (e as Error).message, ...(ws === null ? {} : { workspace: ws }) }));
      }
    }
  };
  look();
  return cloud.listen(look);
}
