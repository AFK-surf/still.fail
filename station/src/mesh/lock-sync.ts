// The workspace lock between the workspace's stations: so that a control plane holding back
// entries (a member removed, a device taken away) holds them back from nobody. Over `stillfail/station/1`, only with
// stations the lock names: `lock.head` says how far one is, `lock.get {after}` gives its entries after that, `lock.put
// {entries}` offers some. Each station checks every entry itself (cloud/state.ts `takeLock`). A station in several
// workspaces does this for each of their locks, with each one's stations, asked in it.
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import type { Cloud } from "../cloud/state.ts";
import { asEntry, type Entry } from "../cloud/lock.ts";
import type { PeerCall } from "./bus.ts";
import { answerPerson } from "./person-sync.ts";
import { personChainsOf } from "./serve.ts";

/// A lock request of another station of the workspace (the transport checked it is in the roster, so in the lock), of
/// the lock of the workspace it was asked in (`workspace`).
export function answerLock(cloud: Cloud, request: any, workspace: string | null = null): unknown {
  // A person's own lock, as heard in the workspace (person-sync.ts).
  if (typeof request?.method === "string" && request.method.startsWith("lock.person.")) return answerPerson(personChainsOf(cloud), request, workspace ?? cloud.home() ?? "");
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

/// How long a station waits before it tries a peer again that it could not bring level, at first; each failure after
/// doubles it, up to RETRY_MOST_MS.
export const RETRY_MS = 5_000;
export const RETRY_MOST_MS = 10 * 60_000;

/// Whenever this station's lock grows, or a roster comes, each station of the lock is brought level with it; one that
/// could not be (offline, the line between them down) is tried again, sooner at first, until it is: nothing else may
/// bring it level when the control plane holds entries back from it.
export function followLock(cloud: Cloud, call: PeerCall, after: (ms: number, f: () => void) => () => void = wall.after): () => void {
  // Each peer of each workspace: how far this station's lock went when last brought level with it; one being brought
  // level now; one that failed, how long it waits and whether that wait is over.
  const level = new Map<string, number>();
  const going = new Set<string>();
  const retries = new Map<string, { wait: number; due: boolean; cancel: () => void }>();
  let stopped = false;
  const bring = (peer: string, ws: string | null, workspace: string, seq: number) => {
    const key = `${workspace}|${peer}`;
    const retry = retries.get(key);
    if (level.get(key) === seq || going.has(key) || (retry !== undefined && !retry.due)) return;
    going.add(key);
    syncWith(cloud, call, peer, ws).then(
      () => {
        level.set(key, seq);
        retries.delete(key);
      },
      (e) => {
        log.info("lock", "a station's lock was not brought level", { peer: peer.slice(0, 12), error: (e as Error).message, ...(ws === null ? {} : { workspace: ws }) });
        if (stopped) return;
        const wait = retry === undefined ? RETRY_MS : Math.min(retry.wait * 2, RETRY_MOST_MS);
        const r = { wait, due: false, cancel: () => {} };
        r.cancel = after(wait, () => {
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
      const ws = m.home ? null : m.workspace;
      const s = cloud.locked(ws)?.state;
      // Taken out of the lock itself: the others take nothing from it (their mesh refuses it), however long it tries.
      if (!s || !s.stations.has(st.station)) continue;
      for (const p of m.peers) if (typeof p?.id === "string" && p.id !== st.station) bring(p.id, ws, m.workspace, s.seq);
    }
  };
  look();
  const unlisten = cloud.listen(look);
  return () => {
    stopped = true;
    unlisten();
    for (const r of retries.values()) r.cancel();
    retries.clear();
  };
}
