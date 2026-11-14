// The workspace lock between the workspace's stations: so that a control plane holding back
// entries (a member removed, a device taken away) holds them back from nobody. Over `stillfail/station/1`, only with
// stations the lock names: `lock.kept` says how far one's chain goes and the hash of every entry it keeps (its chain and
// those off it, cloud/log-keep.ts), `lock.get {hashes}` gives those, `lock.offer {entries}` offers some, kept as the
// rules take them: two stations that give each other what the other lacks keep the same entries, so go by the same
// chain. A station from before knows only `lock.head` (how far it goes), `lock.get {after}` (its chain after that) and
// `lock.put {entries}`: answered as before, and asked as before where the other is one of them. Each station checks
// every entry itself (cloud/state.ts `keepLock`). A station in several workspaces does this for each of their locks,
// with each one's stations, asked in it.
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import type { Cloud } from "../cloud/state.ts";
import { asEntry, type Entry, fold } from "../cloud/lock.ts";
import { type Kept, hashOf } from "../cloud/log-keep.ts";
import type { PeerCall } from "./bus.ts";
import { pinMoved } from "./moved-pin.ts";
import { answerBodies, answerPerson } from "./person-sync.ts";
import { personChainsOf } from "./serve.ts";

/// Whether a peer refused a request as one from before that does not know its method.
export function unknownMethod(e: unknown): boolean {
  return e instanceof Error && e.message.includes("unknown lock method");
}

const entriesOf = (raw: unknown): Entry[] => {
  const entries = (Array.isArray(raw) ? raw : []).map(asEntry);
  if (entries.some((e: Entry | null) => e === null)) throw new Error("a malformed lock entry");
  return entries as Entry[];
};

/// A lock request of another station of the workspace (the transport checked it is in the roster, so in the lock), of
/// the lock of the workspace it was asked in (`workspace`).
export function answerLock(cloud: Cloud, request: any, workspace: string | null = null, peer: string | null = null): unknown {
  // A person's own lock, as heard in the workspace (person-sync.ts); the workspace's statements' bodies, to the station
  // asking (`peer`: none said, none given).
  if (typeof request?.method === "string" && request.method.startsWith("lock.person.")) return answerPerson(personChainsOf(cloud), request, workspace ?? cloud.home() ?? "");
  if (typeof request?.method === "string" && request.method.startsWith("lock.bodies.")) return answerBodies(cloud, request, workspace ?? cloud.home() ?? "", peer);
  const ws = workspace && workspace !== cloud.home() ? workspace : null;
  const locked = cloud.chain(ws);
  const seq = locked?.state?.seq ?? -1;
  switch (request?.method) {
    case "lock.head":
      return { seq, hash: locked?.state?.head ?? null };
    case "lock.kept":
      return { seq, hash: locked?.state?.head ?? null, genesis: locked?.state?.genesis ?? null, hashes: locked === null ? [] : cloud.lockKept(ws).map(hashOf) };
    case "lock.get": {
      if (Array.isArray(request.hashes)) {
        const want = new Set(request.hashes.filter((h: unknown) => typeof h === "string"));
        return { entries: locked === null ? [] : cloud.lockKept(ws).filter((e) => want.has(hashOf(e))) };
      }
      return { entries: cloud.lockAfter(Number.isSafeInteger(request.after) ? request.after : -1, ws) };
    }
    case "lock.put": {
      // Only more of the lock this station pinned: a peer never pins one here.
      if (locked === null) throw new Error("this station has no workspace lock");
      return { taken: cloud.takeLock(entriesOf(request.entries), ws, true), seq: cloud.chain(ws)?.state?.seq ?? seq };
    }
    case "lock.offer": {
      // (none pinned: only one turned off here, whose `disable` may have lost its place, Cloud.keepLock)
      if (locked === null) {
        const off = cloud.lockOff(ws);
        const entries = entriesOf(request.entries);
        if (off === null || entries.length === 0 || entries[0]!.prev === null) throw new Error("this station has no workspace lock");
        try {
          const t = cloud.keepLock([off.entries[0]!, ...entries], ws, true);
          return { taken: t.taken, seq: cloud.chain(ws)?.state?.seq ?? -1, hash: cloud.chain(ws)?.state?.head ?? null };
        } catch {
          return { taken: 0, seq: -1, hash: null };
        }
      }
      // What the rules refuse of them is left out, and says nothing to the one offering: it gave what it keeps.
      const t = cloud.keepLock(entriesOf(request.entries), ws, true);
      const s = cloud.chain(ws)?.state;
      return { taken: t.taken, seq: s?.seq ?? seq, hash: s?.head ?? null };
    }
  }
  throw new Error("unknown lock method");
}

/// Brings one peer and this station level in workspace `ws` (null: the home one): gives it every entry it lacks, takes
/// every one it has more; with a station from before, gives it what follows its head and takes what goes further.
export async function syncWith(cloud: Cloud, call: PeerCall, peer: string, ws: string | null = null): Promise<void> {
  const mine = cloud.chain(ws)?.state;
  if (!mine) return;
  let kept: any;
  try {
    kept = await call(peer, ws, { method: "lock.kept" });
  } catch (e) {
    if (!unknownMethod(e)) throw e;
    return asBefore(cloud, call, peer, ws);
  }
  // A peer with no lock (pinned none, turned off): nothing is given or taken, as before.
  if (!Number.isSafeInteger(kept?.seq) || kept.seq < 0) return;
  if (!Array.isArray(kept.hashes)) return asBefore(cloud, call, peer, ws);
  const theirs = new Set((Array.isArray(kept?.hashes) ? kept.hashes : []).filter((h: unknown) => typeof h === "string"));
  const lacks = cloud.lockKept(ws).filter((e) => !theirs.has(hashOf(e)));
  if (lacks.length > 0) await call(peer, ws, { method: "lock.offer", entries: lacks });
  const have = new Set(cloud.lockKept(ws).map(hashOf));
  const want = [...theirs].filter((h) => !have.has(h as string));
  if (want.length === 0) return;
  const got: any = await call(peer, ws, { method: "lock.get", hashes: want });
  if (cloud.chain(ws)?.state) cloud.keepLock(entriesOf(got?.entries), ws, true);
}

/// A lock turned off here (`off`, what was kept of it) and a peer that keeps it on: gives it what it lacks (the
/// `disable` among it) and takes what it has more (an entry that beats the `disable`, which puts it on again here).
async function offerOff(cloud: Cloud, call: PeerCall, peer: string, ws: string | null, off: Kept): Promise<void> {
  let kept: any;
  try {
    kept = await call(peer, ws, { method: "lock.kept" });
  } catch (e) {
    if (unknownMethod(e)) return;
    throw e;
  }
  const genesis = hashOf(off.entries[0]!);
  if (!Array.isArray(kept?.hashes) || !Number.isSafeInteger(kept?.seq) || kept.seq < 0 || kept.genesis !== genesis) return;
  const theirs = new Set(kept.hashes.filter((h: unknown) => typeof h === "string"));
  const mine = [...off.entries, ...off.aside];
  const lacks = mine.filter((e) => !theirs.has(hashOf(e)));
  if (lacks.length > 0) await call(peer, ws, { method: "lock.offer", entries: lacks });
  const have = new Set(mine.map(hashOf));
  const want = [...theirs].filter((h) => !have.has(h as string));
  if (want.length === 0) return;
  const got: any = await call(peer, ws, { method: "lock.get", hashes: want });
  try {
    cloud.keepLock([off.entries[0]!, ...entriesOf(got?.entries)], ws, true);
  } catch {
    // (the `disable` still goes first: off it stays)
  }
}

/// As stations brought each other level before every entry was kept (a peer that knows none of the methods above).
async function asBefore(cloud: Cloud, call: PeerCall, peer: string, ws: string | null): Promise<void> {
  const mine = cloud.chain(ws)?.state;
  if (!mine) return;
  const head: any = await call(peer, ws, { method: "lock.head" });
  const theirs = Number.isSafeInteger(head?.seq) ? head.seq : -1;
  if (theirs < 0) return;
  if (theirs < mine.seq) await call(peer, ws, { method: "lock.put", entries: cloud.lockAfter(theirs, ws) });
  else if (theirs > mine.seq) {
    const got: any = await call(peer, ws, { method: "lock.get", after: mine.seq });
    cloud.takeLock(entriesOf(got?.entries), ws, true);
  }
}

/// How long a station waits before it tries a peer again that it could not bring level, at first; each failure after
/// doubles it, up to RETRY_MOST_MS.
export const RETRY_MS = 5_000;
export const RETRY_MOST_MS = 10 * 60_000;

/// Whenever what this station keeps of its lock changes, or a roster comes, each station of the lock is brought level
/// with it; one that could not be (offline, the line between them down) is tried again, sooner at first, until it is:
/// nothing else may bring it level when the control plane holds entries back from it.
export function followLock(cloud: Cloud, call: PeerCall, after: (ms: number, f: () => void) => () => void = wall.after): () => void {
  // Each peer of each workspace: what this station kept of its lock when last brought level with it; one being brought
  // level now; one that failed, how long it waits and whether that wait is over.
  const level = new Map<string, string>();
  const going = new Set<string>();
  const retries = new Map<string, { wait: number; due: boolean; cancel: () => void }>();
  let stopped = false;
  const bring = (peer: string, ws: string | null, workspace: string, kept: string, off: Kept | null = null) => {
    const key = `${workspace}|${peer}`;
    const retry = retries.get(key);
    if (level.get(key) === kept || going.has(key) || (retry !== undefined && !retry.due)) return;
    going.add(key);
    (off === null ? syncWith(cloud, call, peer, ws) : offerOff(cloud, call, peer, ws, off)).then(
      () => {
        // (what it kept as this began: what it took meanwhile, from a device or this very peer, brings it again)
        level.set(key, kept);
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
    const listed = cloud.memberships();
    // A joined workspace whose lock was turned off here is none it takes members of (Cloud.leftOut) but is one whose
    // stations are told the `disable` all the same.
    const offJoined = (st.joined ?? []).filter((j) => j.workspace !== st.workspace && !listed.some((m) => m.workspace === j.workspace) && cloud.lockOff(j.workspace) !== null);
    for (const m of [...listed, ...offJoined.map((j) => ({ ...j, home: false }))]) {
      const ws = m.home ? null : m.workspace;
      const s = cloud.chain(ws)?.state;
      const off = s === undefined ? cloud.lockOff(ws) : null;
      if (off !== null) {
        // Turned off here: the stations it named hear the `disable`, or bring the entry that beat it.
        const named = stationsOf(off);
        if (!named.has(st.station)) continue;
        const word = `off:${hashOf(off.entries.at(-1)!)}:${off.aside.length}`;
        for (const p of m.peers) if (typeof p?.id === "string" && p.id !== st.station && named.has(p.id)) bring(p.id, ws, m.workspace, word, off);
        continue;
      }
      // Taken out of the lock itself: the others take nothing from it (their mesh refuses it), however long it tries.
      if (!s || !s.stations.has(st.station)) continue;
      const kept = keptWord(cloud, ws);
      for (const p of m.peers) if (typeof p?.id === "string" && p.id !== st.station) bring(p.id, ws, m.workspace, kept);
      // The workspace's rigs too (a station that only runs tasks): each pinned the lock as it joined, to know which stations may ask it, and
      // no station is in the lock's roster for it to ask.
      for (const r of cloud.rigs(m.workspace)) bring(r.id, ws, m.workspace, kept);
    }
    // A joined workspace this station pins no lock of, whose chain the plane brought moved: pinned once a station of it
    // gives what makes a state naming this one (mesh/moved-pin.ts), tried again as a failure is, till it does.
    for (const j of st.joined ?? []) if (cloud.movedOffered?.has(j.workspace)) pin(j.workspace, (j.peers ?? []).map((p: any) => p?.id).filter((id: unknown): id is string => typeof id === "string"));
  };
  const pin = (workspace: string, peers: string[]) => {
    const key = `${workspace}|moved`;
    const retry = retries.get(key);
    if (going.has(key) || (retry !== undefined && !retry.due) || cloud.leftOut(workspace) !== "unpinned") return;
    going.add(key);
    void pinMoved(cloud, call, workspace, peers, cloud.state?.station ?? "").then((done) => {
      going.delete(key);
      if (done) {
        retries.delete(key);
        return;
      }
      if (stopped) return;
      const wait = retry === undefined ? RETRY_MS : Math.min(retry.wait * 2, RETRY_MOST_MS);
      const r = { wait, due: false, cancel: () => {} };
      r.cancel = after(wait, () => { // timer: a retry after a failure, with a backoff (RETRY_MS doubling to RETRY_MOST_MS)
        r.due = true;
        look();
      });
      retries.set(key, r);
    });
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

/// The stations a lock turned off named last (as its chain before the `disable` says).
const named = new WeakMap<Kept, Set<string>>();
function stationsOf(off: Kept): Set<string> {
  let s = named.get(off);
  if (s === undefined) {
    try {
      s = new Set(fold(off.entries.slice(0, -1), null).stations.keys());
    } catch {
      s = new Set();
    }
    named.set(off, s);
  }
  return s;
}

/// What this station keeps of the lock in `ws`, as a word that changes when any of it does: its head, and how many it
/// keeps aside and the last kept so (kept aside in the order they came, the oldest going first).
function keptWord(cloud: Cloud, ws: string | null): string {
  const s = cloud.chain(ws)?.state;
  if (!s) return "";
  const aside = cloud.lockKept(ws).slice(s.seq + 1);
  return `${s.seq}:${s.head}:${aside.length}:${aside.length === 0 ? "" : hashOf(aside.at(-1)!)}`;
}
