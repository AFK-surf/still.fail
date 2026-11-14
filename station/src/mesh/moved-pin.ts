// A station that keeps no lock of a workspace it joined (enrolled by its token alone, `leftOut` "unpinned") comes to keep
// it once that workspace's chain moved and its people said it a station of theirs (`station {key}` in an owner's or an
// admin's log, the app's 「保护」 after a move). The plane's chain is only offered then (cloud/presence.ts
// `takeFromPlane`, `Cloud.movedOffered`): the chain never names a station added after its move, so the plane's word
// alone pins nothing, as before a move a chain not naming it pinned nothing. Of a station of the workspace this one
// asks the logs heard there (`lock.person.heads`, `lock.person.get`) and the bodies it is given (`lock.bodies.kept`,
// `lock.bodies.get`: a station gives every body only to a station its list names, person-sync.ts `bodiesGiven`, Cloud
// `givenTo`), works out the state in force with them (`state4Moved`, by this station's clock), and only where that state
// names this station's key pins the chain and keeps the logs and bodies; else it changes nothing (2026-11-14, the
// lead's: no wider than before a move. Such a station, its enrollment naming no lock, is unprotected: it lets in whoever
// the plane's credentials say, so its first pin is the plane's word either way, trust on first use, before a move by a
// chain naming it and after by a state naming it; what is never by the plane's word is a lock pinned, or named at
// enrollment, let go or replaced, which this does not touch). Never where it pins a lock of
// that workspace already: one pinned is let go or replaced only by its own entry or on the machine (station/AGENTS.md).
import { nowSecs } from "../ops/files.ts";
import type { Cloud } from "../cloud/state.ts";
import { type Entry, admit, state4Moved } from "../cloud/lock.ts";
import { hashOf } from "../cloud/log-keep.ts";
import type { PeerCall } from "./bus.ts";
import { subOf } from "./person-chains.ts";
import { personChainsOf } from "./serve.ts";

/// The logs and bodies of workspace `ws` as station `peer` gives them to this one: each log heard there whole, and the
/// bodies it gives (all, where its list names this station).
async function fetched(call: PeerCall, peer: string, ws: string): Promise<{ logs: unknown[][]; bodies: unknown[] }> {
  const heads: any = await call(peer, ws, { method: "lock.person.heads" });
  const logs: unknown[][] = [];
  for (const genesis of Object.keys(heads?.heads ?? {})) {
    const got: any = await call(peer, ws, { method: "lock.person.get", genesis });
    if (Array.isArray(got?.chain) && got.chain.length > 0) logs.push(got.chain);
  }
  const kept: any = await call(peer, ws, { method: "lock.bodies.kept" });
  const hashes = (Array.isArray(kept?.hashes) ? kept.hashes : []).filter((h: unknown) => typeof h === "string");
  const got: any = hashes.length === 0 ? { bodies: [] } : await call(peer, ws, { method: "lock.bodies.get", hashes });
  return { logs, bodies: Array.isArray(got?.bodies) ? got.bodies : [] };
}

/// Workspace `ws`'s offered chain pinned here if the state in force, made of the logs and bodies a station of it in
/// `peers` gives, names this station (`me`): whether it was. Nothing where a lock of `ws` is pinned here already, where
/// the chain did not move, or where no station gave what makes a state naming this one.
export async function pinMoved(cloud: Cloud, call: PeerCall, ws: string, peers: readonly string[], me: string): Promise<boolean> {
  const entries = cloud.movedOffered?.get(ws);
  if (entries === undefined || cloud.chain(ws) !== null || cloud.leftOut(ws) !== "unpinned") return false;
  if (!entries.some((e: Entry) => e.kind === "moved")) return false;
  for (const peer of peers) {
    if (peer === me) continue;
    let got: { logs: unknown[][]; bodies: unknown[] };
    try {
      got = await fetched(call, peer, ws);
    } catch {
      continue;
    }
    let names = false;
    try {
      names = state4Moved(ws, entries, got.logs, got.bodies, nowSecs()).state.stations.has(me);
    } catch {
      names = false;
    }
    if (!names) continue;
    // (what changed while it was asked: pinned meanwhile, or the offer let go, changes nothing here)
    if (cloud.chain(ws) !== null || cloud.movedOffered?.get(ws) !== entries) return false;
    keep(cloud, ws, ws, entries, got.logs, got.bodies);
    cloud.movedOffered?.delete(ws);
    return true;
  }
  return false;
}

/// The moved chain pinned (`w` the name the store keeps it by, null for the home workspace; `ws` the workspace's id), and
/// the logs and bodies its state was made of kept with it.
function keep(cloud: Cloud, w: string | null, ws: string, entries: Entry[], logs: unknown[][], bodies: unknown[]): void {
  cloud.takeLock(entries, w);
  const chains = personChainsOf(cloud);
  for (const log of logs) {
    const sub = subOf(log);
    if (sub !== null) chains.take(hashOf(log[0] as Entry), sub, log as Entry[], ws, true);
  }
  cloud.takeBodies(w, bodies);
}

/// A moved chain an owner's device brings a station that pins no lock of workspace `ws` (POST /lock, mesh/serve.ts
/// `lockRoute`, `w` as there), with the logs and bodies its state is made of: the door a chain not moved comes in by,
/// on the same condition read on the state in force (2026-11-14, the lead's: no wider than before a move). Before a
/// move the station pins a chain its owner brings on a device that chain names as an owner's (the credential's role
/// owner too, said before this is asked); after, the state those logs and bodies make with the chain, each checked
/// here, must let that device in as an owner's and name this station (`station {key}` in an owner's or an admin's
/// log), else nothing is pinned. Throws a LockRefusal or an Error saying why not.
export function pinBrought(cloud: Cloud, w: string | null, ws: string, entries: Entry[], logs: unknown, bodies: unknown, who: { sub: string; endpoint: string; base?: string; proof?: string }, me: string): void {
  if (!Array.isArray(logs) || !logs.every((l) => Array.isArray(l) && l.length > 0) || !Array.isArray(bodies)) throw new Error("a moved lock is brought with the logs and bodies its state is made of");
  const now = nowSecs();
  const state = state4Moved(ws, entries, logs, bodies, now).state;
  admit(state, who, now);
  if (state.members.get(who.sub)?.role !== "owner") throw new Error("the lock is brought by its owner");
  if (!state.stations.has(me)) throw new Error("the lock does not name this station");
  keep(cloud, w, ws, entries, logs as unknown[][], bodies);
}
