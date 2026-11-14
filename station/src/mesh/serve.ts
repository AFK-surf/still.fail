// Members' connections over the mesh (the Rust station's main.rs `serve`, `relay_request`). Wire format, on ALPN
// `stillfail/admin/1`: the first bidirectional stream
// carries credentials, one JSON line each, answered with one JSON line (a later line renews); every other stream is
// one request: a JSON head line `{method, path, headers}`, then the body until the stream finishes, answered by a
// JSON head line `{status, headers}` and the response body.
// The lines and the streams themselves are the mesh's wire and door (wire.ts, door.ts), which know nothing of what is
// here: who is let in (the credentials still.fail cloud signs, the locks) and what a request is answered (the routes).
import type { Admin } from "../api/admin.ts";
import { langOfCore, queryPairs } from "../api/request.ts";
import { BUILD_HEADER, buildOf, coreTooOld } from "../api/oldest.ts";
import { deviceBuildsOf } from "./device-builds.ts";
import { tr } from "../ops/i18n.ts";
import type { Cloud } from "../cloud/state.ts";
import { log } from "../ops/log.ts";
import { wall } from "../ops/fibers.ts";
import { nowSecs } from "../ops/files.ts";
import type { Accepted } from "../cloud/provider.ts";
import { type Admitted, managesStation, readOnly, revoked, verifyMemberOf } from "./credential.ts";
import { SeenDevices } from "./seen-devices.ts";
import { foldChain, takeChain } from "./person-sync.ts";
import { AT_ODDS } from "./person-chains.ts";
import { MarkRefusal, stationMarksOf } from "./station-marks.ts";
import { WaysRefusal, setRelays, setWay, waysOf as workspaceWaysOf } from "./ways.ts";
import { join } from "node:path";
import { FORK, NOT_GIVEN, meshDir, personChainsOf } from "../cloud/state.ts";
import { hashOf } from "../cloud/log-keep.ts";
import { type Entry, LockRefusal, admit, admitPerson, asEntry, endpointProof, fold, lowerRole, personFold } from "../cloud/lock.ts";
import type { Connection, Stream } from "./native.ts";
import { answerScreen } from "./screens.ts";
import type { ScreenHub } from "../screens/hub.ts";
import type { MemberAsk } from "../parts.ts";
import { compressed } from "./compress.ts";
import { Traces, parseParent, route } from "./traces.ts";
import { FrameReader, SocketRefused, openSocket, previewTarget, pumpSocket } from "../jobs/preview.ts";
import { type Admit, door } from "./door.ts";
import { SLOW_REPLY_BYTES, pathsOf, slowly } from "./reply-watch.ts";
import { type Asked, HOP, Reader, send, writeLine } from "./wire.ts";

export const ALPN = Buffer.from("stillfail/admin/1");
// Keep old clients admitted until protocol-2 clients have reached the stable channel.
const MIN_CLIENT_PROTOCOL = 1;

/// The streams' framing (wire.ts), as those that speak this protocol have it of here.
export { Reader, send, writeLine };

/// A hello's `lock: {device, proof}`: the device's base key, and its signature saying this endpoint is its own.
function lockProof(v: any): { base: string; proof: string } | undefined {
  return typeof v?.device === "string" && typeof v?.proof === "string" && v.device.length === 64 && v.proof.length === 128 ? { base: v.device, proof: v.proof } : undefined;
}

/// How many entries a hello may bring (they come in its first line, MAX_HEAD at most).
const BROUGHT_MOST = 64;

/// The entries a device brings with its hello (`lock.entries`): what put it in the lock, which
/// this station has not heard of yet (the cloud, or the device that signed them, has not reached it). Taken as any
/// are, entry by entry, only onto a lock this station has pinned (they never pin one); whether any was. Nothing is
/// checked (no signature) unless they could let this very device in: one of them names its base key, and they go on
/// from what the station has, in order. A connection bringing anything else costs the station no more than reading it.
function brought(hello: any, cloud: Cloud, workspace: string, base: string | undefined): boolean {
  const raw = hello?.lock?.entries;
  if (base === undefined || !Array.isArray(raw) || raw.length === 0 || raw.length > BROUGHT_MOST) return false;
  const entries = raw.map(asEntry);
  if (entries.some((e) => e === null)) return false;
  const ws = joinedOf(cloud, workspace);
  // (onto the workspace's own chain, where it has not moved: nothing follows a `moved`)
  const state = cloud.chain(ws)?.state;
  if (!state || state.moved !== undefined) return false;
  const all = entries as Entry[];
  if (all[0]!.seq > state.seq + 1 || all.some((e, i) => i > 0 && e.seq !== all[i - 1]!.seq + 1)) return false;
  if (!all.some((e) => e.seq > state.seq && e.kind === "device" && (e.body as { id?: unknown } | null)?.id === base)) return false;
  try {
    return cloud.takeLock(all, ws) > 0;
  } catch (e) {
    log.info("lock", "a device brought lock entries this station does not take", { error: (e as Error).message });
    return false;
  }
}

/// Where a workspace's chain moved and this station waits for what its state is made of (Cloud `locked`'s `waiting`):
/// what a hello brings of it, the root's log (`lock.person`, its genesis the root) and statements' bodies
/// (`lock.bodies`), taken as any are (the log by its rules, each body only against an entry kept that commits to it),
/// whoever brings them: they let nobody in by themselves. Whether any was.
function broughtForState(hello: any, cloud: Cloud, workspace: string): boolean {
  const ws = joinedOf(cloud, workspace);
  const root = cloud.chain(ws)?.state?.moved;
  if (root === undefined || cloud.locked(ws)?.waiting !== true) return false;
  let any = false;
  const log = hello?.lock?.person;
  if (Array.isArray(log) && log.length > 0 && log.length <= BROUGHT_MOST) {
    try {
      const { genesis, whose } = foldChain(log, null);
      if (genesis === root) any = personChainsOf(cloud).take(genesis, whose, log, workspace, false).taken > 0 || any;
    } catch {
      // (not the root's log, or not one the rules take)
    }
  }
  const bodies = hello?.lock?.bodies;
  if (Array.isArray(bodies) && bodies.length > 0 && bodies.length <= BROUGHT_MOST) any = cloud.takeBodies(ws, bodies).taken > 0 || any;
  return any;
}

/// The longest chain of each person's own lock this station heard, by the lock's genesis (cloud/state.ts, where a
/// moved workspace's state is made of them).
export { personChainsOf };

/// The members' devices that came to this station, by workspace (seen-devices.ts).
const seens = new WeakMap<Cloud, SeenDevices>();
export function seenDevicesOf(cloud: Cloud): SeenDevices {
  let s = seens.get(cloud);
  if (s === undefined) seens.set(cloud, (s = new SeenDevices(join(meshDir(cloud.data), "seen-devices.json"))));
  return s;
}

/// `ws` when it is a workspace the station joined, null for its home one (whose lock is the home's).
const joinedOf = (cloud: Cloud, ws: string) => (ws && ws !== cloud.home() ? ws : null);

/// What a device is told when this station takes none of its workspace's members for a security mode (Cloud.leftOut):
/// a refusal of its own (`lock_station`, `why`), so the device says that rather than the station being down.
const LEFT_OUT = {
  pending: "this station has not pinned this workspace's lock yet: the control plane has not brought the one it joined with",
  unpinned: "this workspace turned its lock on after this station joined it: remove the station from it and add it again",
  home: "this station's own workspace is locked and this one is not: it takes none of this one's members",
} as const;

/// Why a credential for a workspace this station joined is refused, when it is as the control plane signs them and that
/// workspace is left out for a lock (Cloud.leftOut); null otherwise (one that does not check out learns nothing of
/// the workspaces this station is in).
function leftOutFor(cloud: Cloud, hello: any, device: string, accepted?: Accepted): keyof typeof LEFT_OUT | null {
  const ws = claimed(hello);
  const why = ws === "" ? null : cloud.leftOut(ws);
  if (why === null) return null;
  const revocations = cloud.state?.joined?.find((j) => j.workspace === ws)?.revocations ?? [];
  try {
    verifyMemberOf(typeof hello?.credential === "string" ? hello.credential : "", cloud.state?.grant_keys, [{ workspace: ws, revocations }], device, accepted);
    return why;
  } catch {
    return null;
  }
}

/// What a hello this station refused (`e`, why) is answered: a lock's refusal with the code the device asks to be
/// approved by and how far the lock goes here; a workspace left out for a lock, why (`lock_station`); else the reason.
/// `sub`: whose credential checked out, refused for the lock: told the chains of their own lock this station keeps, so a
/// device of theirs not on it yet (a new one) finds the devices that may let it in with no cloud (a few, as fit in a line);
/// and the last entries of the workspace's lock (`entries`), so one taken out of it hears so, with no cloud to read it of.
export function refusalOf(cloud: Cloud, hello: any, device: string, e: unknown, accepted?: Accepted, sub: string | null = null): Record<string, unknown> {
  if (e instanceof LockRefusal) {
    const chains = sub === null ? [] : personChainsOf(cloud).of(sub).map(([genesis, entries]) => ({ genesis, entries }));
    const person = chains.length > 0 && JSON.stringify(chains).length <= REFUSAL_PERSON_BYTES ? { person: chains } : {};
    const ws = joinedOf(cloud, claimed(hello));
    const tail: Entry[] = [];
    let bytes = 0;
    for (const entry of sub === null ? [] : cloud.lockAfter(-1, ws).reverse()) {
      bytes += JSON.stringify(entry).length;
      if (bytes > REFUSAL_ENTRIES_BYTES) break;
      tail.unshift(entry);
    }
    const out = sub === null ? null : toldOut(cloud, ws, device, hello);
    const left = sub === null ? null : leftOf(cloud, ws, device, hello, sub);
    return { error: e.message, code: e.code, lock: lockHead(cloud, ws), ...person, ...(tail.length > 0 ? { entries: tail } : {}), ...(out !== null ? { out } : {}), ...(left !== null ? { left } : {}) };
  }
  const left = leftOutFor(cloud, hello, device, accepted);
  if (left !== null) return { error: LEFT_OUT[left], code: "lock_station", why: left };
  return { error: (e as Error).message };
}

/// How many devices a refusal names to ask at most (a line of a few KB).
const APPROVERS_MOST = 16;

/// What a device refused where `ws`'s chain moved is told when the state in force there does not name it (2026-11-14:
/// such a device was given no logs and read the workspace as waiting for good, nobody to ask): that it is left out, and
/// whom to ask, the base ids of the app devices that may let it in, `APPROVERS_MOST` at most: its person's own where
/// the list names them (on the log that binds them: only those put a device of theirs on it), else the owners' and
/// admins' (they say someone's first device's `member`). Nothing else of the list: a hint the device does not trust,
/// dialling them as before a move, the device dialled checking everything itself (client/core-ts/src/views/pair.ts),
/// so a station that names others only sends it where nobody lets it in. None while the station waits for the root's
/// log or its `open` (it names nobody, so it cannot tell who is left out), while it is off (nobody is refused for it),
/// where the chain did not move, or to a device the list names (refused for another reason). And `apps`, whether the
/// list names an app device of its person's: a web page is approved there by its own person's app alone, so one with
/// none is told to install one rather than ask owners who cannot approve it (client/core-ts/src/views/lock.ts
/// `needsAppIn`; the owner, 2026-11-13: 「开了安全模式那就需要 app」). It says nothing of the list beyond the asking
/// device's own person (whom `approvers` names already where they have one); a core from before reads `approvers` alone.
function leftOf(cloud: Cloud, ws: string | null, device: string, hello: any, sub: string): { approvers: string[]; apps: boolean } | null {
  if (cloud.chain(ws)?.state?.moved === undefined) return null;
  const locked = cloud.locked(ws);
  if (locked === null || locked.waiting === true || locked.state === null) return null;
  const s = locked.state;
  const proof = lockProof(hello?.lock);
  const ids = [device, ...(proof && endpointProof(ws ?? cloud.home() ?? "", proof.base, device, proof.proof) ? [proof.base] : [])];
  if (ids.some((id) => s.devices.has(id))) return null;
  const named = s.members.has(sub);
  const approvers = [...s.devices.values()]
    .filter((d) => d.kind === "app" && (named ? d.sub === sub : ["owner", "admin"].includes(s.members.get(d.sub)?.role ?? "")))
    .map((d) => d.id)
    .slice(0, APPROVERS_MOST);
  const apps = [...s.devices.values()].some((d) => d.kind === "app" && d.sub === sub);
  return { approvers, apps };
}

/// How much of what took a device out a refusal tells at most.
const REFUSAL_OUT_BYTES = 32 * 1024;

/// What a device refused where `ws`'s chain moved is told of what took it out (the model's `admitsBefore`, as
/// `Cloud.givenTo` gives it to a station): the removals whose subject's removals left out make the list name it again,
/// with each one's `prev` chain, and the entries of the person logs that commit to them (each its log from the genesis),
/// so that it can work out who took it out and when by the rules alone; nothing else of the workspace. By its endpoint,
/// the base key its hello proves for it and the keys the logs kept put on with those; none where the list never named
/// it, or names it now (refused for another reason), or where it would not fit a line.
function toldOut(cloud: Cloud, ws: string | null, device: string, hello: any): { bodies: unknown[]; logs: { genesis: string; entries: Entry[] }[] } | null {
  if (cloud.chain(ws)?.state?.moved === undefined) return null;
  const proof = lockProof(hello?.lock);
  const ids = new Set([device, ...(proof && endpointProof(ws ?? cloud.home() ?? "", proof.base, device, proof.proof) ? [proof.base] : [])]);
  // (a removal took out the keys of its subject's log: those the logs kept here put on with these ids)
  const keys = new Set(ids);
  for (const [, entries] of personChainsOf(cloud).every()) {
    for (const e of entries) {
      const d = (e.kind === "genesis" ? (e.body as any)?.device : e.kind === "device" ? e.body : null) as { id?: unknown; key?: unknown } | null;
      if (typeof d?.id === "string" && ids.has(d.id) && typeof d.key === "string") keys.add(d.key);
    }
  }
  const hashes = new Set<string>();
  for (const k of keys) {
    const given = cloud.givenTo(ws, k);
    if (given === "all") return null;
    for (const h of given) hashes.add(h);
  }
  if (hashes.size === 0) return null;
  const kept = cloud.bodies(ws).all();
  const bodies = [...hashes].flatMap((h) => (kept.has(h) ? [kept.get(h)] : []));
  const logs: { genesis: string; entries: Entry[] }[] = [];
  for (const [genesis, entries] of personChainsOf(cloud).every()) {
    let last = -1;
    entries.forEach((e, i) => {
      if (e.kind === "ws" && hashes.has(String((e.body as { h?: unknown } | null)?.h))) last = i;
    });
    if (last >= 0) logs.push({ genesis, entries: entries.slice(0, last + 1) });
  }
  const out = { bodies, logs };
  return JSON.stringify(out).length <= REFUSAL_OUT_BYTES ? out : null;
}

/// Whether a device's connection is given `ws`'s bodies and logs: let in by its lock (while on); while its people's
/// logs say it is off, the connection was let in by the control plane's word alone, so only where the list made of the
/// bodies names that very device as the lock's admission would (its base key's proof of the endpoint, and an app's
/// person's log as kept here). A connection that brought no proof (`lock` on its hello) is given none while off. While
/// the station waits for the root's log or its `open` (`waiting`) nobody is let in, and a connection let in before the
/// chain moved, still open, is given none either.
function givesDevice(cloud: Cloud, ws: string | null, viewer: Admitted["viewer"]): boolean {
  const locked = cloud.locked(ws);
  if (locked !== null) return locked.waiting !== true;
  const li = cloud.list(ws);
  const s = li?.state;
  if (!s || li!.waiting === true || s.moved !== undefined || cloud.chain(ws)?.state?.moved === undefined) return false;
  try {
    const who = { sub: viewer.sub, endpoint: viewer.device, base: viewer.lockDevice?.base, proof: viewer.lockDevice?.proof };
    const { device } = admit(s, who, nowSecs());
    if (device.kind === "app" && s.persons.has(viewer.sub)) {
      const chain = personChainsOf(cloud).kept(s.persons.get(viewer.sub)!);
      if (chain === null) return false;
      admitPerson(s, who, chain);
    }
    return true;
  } catch {
    return false;
  }
}

/// How many bodies one request brings at most.
const BODIES_MOST = 1024;

/// Bodies a device of the viewer's workspace brings, taken as the rules take them (Cloud `takeBodies`): how many, and
/// each not taken with why (as `off` says it of entries). Taken while the workspace is off too (a lock pinned: its
/// chain): the root's next `open` puts it on again, and taking a body gives nobody anything.
function bodiesTaken(cloud: Cloud, viewer: Admitted["viewer"], bodies: unknown[]): { taken: number; refused?: { hash: string | null; why: string }[] } {
  const ws = viewer.workspace && viewer.workspace !== cloud.home() ? viewer.workspace : null;
  if (cloud.chain(ws) === null || bodies.length > BODIES_MOST) return { taken: 0, refused: bodies.slice(0, BODIES_MOST).map(() => ({ hash: null, why: "this workspace keeps no statements here" })) };
  const t = cloud.takeBodies(ws, bodies);
  return { taken: t.taken, ...(t.refused.length > 0 ? { refused: t.refused } : {}) };
}

/// How much of a person's own lock a refusal tells at most (a core reads a line of 64 KiB at most).
const REFUSAL_PERSON_BYTES = 32 * 1024;
/// How much of the workspace's lock (its last entries) a refusal tells at most.
const REFUSAL_ENTRIES_BYTES = 16 * 1024;

/// The workspace a hello's credential names, as it says (checked by verifyMember: only to say which lock refused it).
function claimed(hello: any): string {
  try {
    const ws = JSON.parse(Buffer.from(String(hello?.credential ?? "").split(".")[1] ?? "", "base64url").toString())?.ws;
    return typeof ws === "string" ? ws : "";
  } catch {
    return "";
  }
}

/// The build a request's headers say (api/oldest.ts `buildOf`), null for none.
function buildSaid(headers: Record<string, unknown>): number | null {
  const said = Object.entries(headers).find(([k]) => k.toLowerCase() === BUILD_HEADER)?.[1];
  return buildOf(typeof said === "string" ? said : undefined);
}

/// A request of `viewer` with `headers`: the build it says kept by the device's id in the lock (device-builds.ts),
/// where it has one. The build said (null: none).
export function sawBuild(cloud: Cloud, viewer: Admitted["viewer"], headers: Record<string, unknown>): number | null {
  const build = buildSaid(headers);
  if (viewer.lockId !== undefined) deviceBuildsOf(cloud).saw(viewer.lockId, build, nowSecs());
  return build;
}

/// The ids of the devices workspace `ws`'s lock here names (null: the home one): its chain's, and where it moved the
/// state in force's too.
function lockDeviceIds(cloud: Cloud, ws: string | null): Set<string> {
  return new Set([...(cloud.chain(ws)?.state?.devices.keys() ?? []), ...(cloud.locked(ws)?.state?.devices.keys() ?? [])]);
}

/// The ids of the app devices on `sub`'s own log, as each chain of it kept here says (device-builds.ts).
function personDeviceIds(cloud: Cloud, sub: string): Set<string> {
  const out = new Set<string>();
  for (const [, entries] of personChainsOf(cloud).of(sub)) {
    try {
      for (const d of personFold(entries, sub).devices) out.add(d.id);
    } catch {
      // (a chain that does not fold names none)
    }
  }
  return out;
}

/// How far this station's lock goes in `ws` (the home workspace when null), for the device to bring it what it has
/// more (null: no lock pinned there).
export function lockHead(cloud: Cloud, ws: string | null = null): { seq: number; hash: string; genesis: string } | null {
  // (the chain's own, moved or not: what a device brings it more of)
  const s = cloud.chain(ws)?.state;
  return s ? { seq: s.seq, hash: s.head, genesis: s.genesis } : null;
}

/// GET /lock?after=<seq>: how far this station's lock goes and its entries after `after` (any member): its active chain,
/// with the hash of its entry at `after` (`after_hash`), for a device that holds another there to see it parted. POST
/// /lock {entries}: more of the pinned lock, what goes on from its head; with `keep` (entries a station took already,
/// `serves` says `forks`), each the rules take after a parent kept, also off the chain gone by (cloud/state.ts
/// `keepLock`); or, unpinned, a lock to pin, from its genesis: brought by its owner, on a device the genesis names (until
/// then the control plane's word is what this station goes by, and the owner it names is who may turn the lock on).
/// The lock is the asker's workspace's (each workspace the station is in has its own).
///
/// What a POST is answered (an app from before calls an answer "taken" whose head is as far as its entry): the last entry
/// brought on the active chain once taken, 200 `{taken, head}` as before; not going on from the head (not kept), or kept
/// with `keep` but not on the chain (it lost at its parent, or hangs below one that did), 409 with the words of a fork
/// as before; refused by the rules, as before (200 where others were taken, else 409 with why). `head` is the active
/// chain's; `off`, for the core of next, says of each entry brought not on it why (`why`: `not on the head`, `refused`
/// with the rules' `refusal`, `beaten` by `winner` at `step`, `below` one beaten, `under`, `no parent`), and whether it
/// is kept aside (`kept`).
export function lockRoute(cloud: Cloud, method: string, query: [string, string][], body: Buffer, viewer: Admitted["viewer"]): [number, unknown] {
  const ws = viewer.workspace && viewer.workspace !== cloud.home() ? viewer.workspace : null;
  if (method === "GET") {
    const after = Number(query.find(([k]) => k === "after")?.[1] ?? -1);
    // (`takes`: the entry kinds this station knows beyond the first ones, for a device to ask before it writes one: an
    // entry it did not know, it would refuse, and every entry after)
    // (`serves`: what a device has of this station rather than of the cloud: the person's own lock (/lock/person), the
    // devices that came (/lock/devices), and the locks' changes told on its event stream (lock-events.ts))
    const from = Number.isSafeInteger(after) ? after : -1;
    const at = from >= 0 ? cloud.lockAfter(from - 1, ws)[0] : undefined;
    const atHash = at !== undefined && at.seq === from ? { after_hash: hashOf(at) } : {};
    // (`builds`: what build each device its lock names last ran, as seen here, device-builds.ts; given only to a device the
    // lock let in, as admission let this one, and of a workspace with none, of nobody)
    return [200, { head: lockHead(cloud, ws), entries: cloud.lockAfter(from, ws), ...atHash, takes: ["person"], serves: ["person", "devices", "told", "forks", "bodies", "logs", "builds"], builds: deviceBuildsOf(cloud).of(lockDeviceIds(cloud, ws)) }];
  }
  if (method !== "POST") return [405, { error: "GET or POST" }];
  let entries: (Entry | null)[];
  let keep = false;
  try {
    const said = JSON.parse(body.toString("utf8") || "{}");
    // (`keep`: what is brought was taken by another keeper already, a station the device read it of: kept as a station's
    // would be, also off the chain gone by; else only what goes on from its head, cloud/state.ts `keepLock`)
    keep = said?.keep === true;
    // A person's own lock as it stands now (a device taken off it), told by their device: the longest heard is what a
    // chain brought later is judged by.
    if (Array.isArray(said?.person)) return personTold(cloud, ws, viewer, said.person, keep);
    const raw = said?.entries;
    entries = Array.isArray(raw) ? raw.map(asEntry) : [];
  } catch {
    return [400, { error: "invalid JSON" }];
  }
  if (entries.length === 0 || entries.some((e) => e === null)) return [400, { error: "entries: lock entries" }];
  try {
    if (cloud.chain(ws) === null) {
      if (viewer.role !== "owner") return [403, { error: "only the workspace's owner turns its lock on" }];
      // Brought by one of its owner's devices as the chain brought names them (one approved after the genesis too:
      // the owner takes a station in from the phone they approved since).
      const brought = fold(entries as Entry[], nowSecs());
      admit(brought, { sub: viewer.sub, endpoint: viewer.device, base: viewer.lockDevice?.base, proof: viewer.lockDevice?.proof }, nowSecs());
      if (brought.members.get(viewer.sub)?.role !== "owner") return [403, { error: "the lock is brought by its owner" }];
    }
    const t = cloud.keepLock(entries as Entry[], ws, keep);
    const head = lockHead(cloud, ws);
    const off = t.off.length > 0 ? { off: t.off } : {};
    const h = hashOf(entries.at(-1)!);
    if (cloud.lockAfter(-1, ws).some((e) => hashOf(e) === h)) return [200, { taken: t.taken, head, ...off }];
    const why = t.off.find((o) => o.hash === h)?.why;
    // Kept, or the bound reached (cloud/log-keep.ts), but not on the chain: it lost its place.
    if (why === "beaten" || why === "below" || why === "again") return [409, { error: FORK, head, ...off }];
    if (t.taken > 0) return [200, { taken: t.taken, head, ...off }];
    return [409, { error: t.refusal?.message ?? FORK, head, ...off }];
  } catch (e) {
    return [409, { error: (e as Error).message, head: lockHead(cloud, ws) }];
  }
}

/// GET /ways: the asker's workspace's own relays and the ways turned off, as this station goes by them (`at` 0: as
/// still.fail cloud kept them, none changed here yet). POST /ways: `{relays}` the whole list of its own relays, or
/// `{way, on}` one way turned on or off; any member but a read-only one (mesh/ways.ts: nobody approves a relay).
export function waysRoute(cloud: Cloud, method: string, body: Buffer, viewer: Admitted["viewer"]): [number, unknown] {
  const ways = workspaceWaysOf(cloud);
  const ws = viewer.workspace || cloud.home() || "";
  if (method === "GET") return [200, ways.view(ws)];
  if (method !== "POST") return [405, { error: "GET or POST" }];
  if (readOnly(viewer)) return [403, { error: "read-only members cannot change this workspace's ways" }];
  let said: any;
  try {
    said = JSON.parse(body.toString("utf8") || "{}");
  } catch {
    return [400, { error: "invalid JSON" }];
  }
  try {
    const by = viewer.name || viewer.email || null;
    if (Array.isArray(said?.relays)) return [200, setRelays(ways, ws, said.relays, by)];
    if (typeof said?.way === "string" && typeof said?.on === "boolean") return [200, setWay(ways, ws, said.way, said.on)];
    return [400, { error: "relays: a list of URLs, or way and on" }];
  } catch (e) {
    if (e instanceof WaysRefusal) return [e.message.startsWith("the last relay") ? 409 : 400, { error: e.message }];
    throw e;
  }
}

/// GET /station-marks: the names and marks this station keeps of the asker's workspace's stations, by id (mesh/
/// station-marks.ts; one with none kept is as still.fail cloud lists it). PUT /station-mark: this station's own changed,
/// `{name, emoji, icon}` (each left out stays as it was; "" takes an emoji or an icon away), by an owner or an admin.
export function stationMarksRoute(cloud: Cloud, method: string, body: Buffer, viewer: Admitted["viewer"], own: boolean): [number, unknown] {
  const marks = stationMarksOf(cloud);
  const ws = viewer.workspace || cloud.home() || "";
  if (!own) return method === "GET" ? [200, { marks: marks.of(ws) }] : [405, { error: "GET" }];
  if (method !== "PUT") return [405, { error: "PUT" }];
  if (!managesStation(viewer)) return [403, { error: "only the workspace's owners and admins change a station's name and icon" }];
  let said: any;
  try {
    said = JSON.parse(body.toString("utf8") || "{}");
  } catch {
    return [400, { error: "invalid JSON" }];
  }
  if (said === null || typeof said !== "object") return [400, { error: "name, emoji, icon" }];
  try {
    // (where it keeps none yet, its name as the cloud lists it here; the device sends all three, so its emoji and icon)
    const was = { name: cloud.membership(ws)?.name || cloud.state?.name || "", emoji: "", icon: "" };
    return [200, marks.change({ name: said.name, emoji: said.emoji, icon: said.icon }, was)];
  } catch (e) {
    if (e instanceof MarkRefusal) return [400, { error: e.message }];
    throw e;
  }
}

function personTold(cloud: Cloud, ws: string | null, viewer: Admitted["viewer"], chain: unknown[], keep = false): [number, unknown] {
  const pin = cloud.locked(ws)?.state?.persons.get(viewer.sub);
  if (pin === undefined) return [409, { error: "no lock of their own bound here" }];
  try {
    if (personFold(chain, viewer.sub).genesis !== pin) return [409, { error: "not the lock bound here" }];
    const t = takeChain(personChainsOf(cloud), chain, viewer.sub, viewer.workspace, keep);
    const off = t.off.length > 0 ? { off: t.off } : {};
    if (!t.on) return [409, { error: AT_ODDS, head: personHead(t.chain), ...off }];
    return [200, { ...off }];
  } catch (e) {
    return [409, { error: (e as Error).message }];
  }
}

/// How far a person's chain gone by goes: its last entry's place and hash.
const personHead = (chain: unknown[]) => ({ seq: chain.length - 1, hash: chain.length === 0 ? null : hashOf(chain.at(-1) as Entry) });

/// GET /lock/person: the chains of the asker's own lock this station has (each begun anew, by its genesis, the chain it
/// goes by), for the device to go on from the one it pinned. POST /lock/person {chain}: the chain as it stands now on the
/// device (a device added or taken off), what goes on from the chain gone by (with `keep`, each entry the rules take
/// after a parent kept, as POST /lock), and so told to the person's other devices and stations (person-sync.ts):
/// answered `{genesis, length}` as before where its last entry is on the chain gone by; else 409 with the words of being
/// at odds as before, `head` the chain gone by's and `off` why for each entry not on it (as POST /lock says them). GET /lock/devices: the members' devices that came to this station in the asker's
/// workspace (everyone's for its owners and admins, else their own), as the cloud's GET /devices said them.
export function lockPartRoute(cloud: Cloud, part: string, method: string, body: Buffer, viewer: Admitted["viewer"]): [number, unknown] {
  if (part === "person") {
    const chains = personChainsOf(cloud);
    // (with what this station serves of the person's logs and the builds of the app devices on the asker's own log, as
    // seen here: what their core reads before it writes a kind an older station or app refuses, device-builds.ts)
    if (method === "GET") return [200, { chains: chains.of(viewer.sub).map(([genesis, entries]) => ({ genesis, entries })), serves: ["logs", "builds"], builds: deviceBuildsOf(cloud).of(personDeviceIds(cloud, viewer.sub)) }];
    if (method !== "POST") return [405, { error: "GET or POST" }];
    let said: any;
    try {
      said = JSON.parse(body.toString("utf8") || "{}");
    } catch {
      return [400, { error: "invalid JSON" }];
    }
    try {
      const t = takeChain(chains, said?.chain, viewer.sub, viewer.workspace, said?.keep === true);
      const off = t.off.length > 0 ? { off: t.off } : {};
      // (the entries first, then the bodies of the statements among them: one answer)
      const bodies = Array.isArray(said?.bodies) ? bodiesTaken(cloud, viewer, said.bodies) : {};
      if (!t.on) return [409, { error: AT_ODDS, head: personHead(t.chain), ...off, ...bodies }];
      return [200, { genesis: t.genesis, length: t.chain.length, ...off, ...bodies }];
    } catch (e) {
      return [409, { error: (e as Error).message }];
    }
  }
  const ws = (part === "bodies" || part === "logs") && viewer.workspace && viewer.workspace !== cloud.home() ? viewer.workspace : null;
  if (part === "bodies") {
    // (to a connection let in in this workspace alone: it is in its state, or, before its chain moved, in its chain)
    if (method === "GET") {
      if (!givesDevice(cloud, ws, viewer)) return [200, { bodies: [], lacking: [] }];
      return [200, { bodies: [...cloud.bodies(ws).all().values()], lacking: cloud.lacking(ws) }];
    }
    if (method !== "POST") return [405, { error: "GET or POST" }];
    let said: any;
    try {
      said = JSON.parse(body.toString("utf8") || "{}");
    } catch {
      return [400, { error: "invalid JSON" }];
    }
    if (!Array.isArray(said?.bodies) || said.bodies.length > BODIES_MOST) return [400, { error: "bodies: the statements' bodies" }];
    return [200, bodiesTaken(cloud, viewer, said.bodies)];
  }
  if (part === "logs" && method === "GET") {
    if (!givesDevice(cloud, ws, viewer)) return [200, { chains: [] }];
    const chains = personChainsOf(cloud);
    return [200, { chains: cloud.logsOf(ws).flatMap((genesis) => {
      const entries = chains.kept(genesis);
      return entries === null ? [] : [{ genesis, entries }];
    }) }];
  }
  if (part === "devices" && method === "GET") {
    const manages = viewer.role === "owner" || viewer.role === "admin";
    return [200, { devices: seenDevicesOf(cloud).of(viewer.workspace, nowSecs(), viewer.sub, manages) }];
  }
  return [404, { error: "no such route" }];
}

/// With a lock pinned: the member admitted only on a device the lock names, with the lower of the lock's role and the
/// credential's (`named`). Without one, as the credential says. A member bound to a lock of their own there goes by it
/// alone on an app device: one the workspace's lock names is let in only as it is on the person's lock this station
/// has heard (else one taken off it would still be let in); a web page, which holds no key of that lock, by its entry.
/// Throws a LockRefusal why not.
export function inLock(cloud: Cloud, admitted: Admitted, named: string, endpoint: string, hello: unknown = null): Admitted {
  // The lock of the workspace the member is in.
  const ws = admitted.viewer.workspace && admitted.viewer.workspace !== cloud.home() ? admitted.viewer.workspace : null;
  const locked = cloud.locked(ws);
  if (locked === null) return { ...admitted, viewer: { ...admitted.viewer, role: named } };
  if (locked.state === null) throw new LockRefusal("this station's workspace lock is broken; run `stillfail lock reset` on it");
  // (moved to its people's logs, and the root's log or its `open` not here yet: nobody, until they come)
  if (locked.waiting === true) throw new LockRefusal(NOT_GIVEN);
  const v = admitted.viewer;
  const { device, role } = admit(locked.state, { sub: v.sub, endpoint, base: v.lockDevice?.base, proof: v.lockDevice?.proof }, nowSecs());
  if (device.kind === "app" && locked.state.persons.has(v.sub)) {
    const person = onPersonalLock(cloud, admitted, named, endpoint, hello);
    if (person === null) throw new LockRefusal("this device goes by its person's own lock in this workspace, and it brought none");
    return person;
  }
  return { ...admitted, viewer: { ...v, role: lowerRole(role, named), lockId: device.id } };
}

/// inLock again for a connection already in (its lock or its person's changed): by its person's own lock where it is
/// not a device of the workspace's lock, as it was let in. Throws a LockRefusal why not.
export function stillIn(cloud: Cloud, admitted: Admitted, named: string, endpoint: string): Admitted {
  try {
    return inLock(cloud, admitted, named, endpoint);
  } catch (e) {
    if (!(e instanceof LockRefusal)) throw e;
    const person = onPersonalLock(cloud, admitted, named, endpoint, null);
    if (person === null) throw e;
    return person;
  }
}

/// inLock, for a hello that may bring what put the device in the lock (`lock.entries`): not in the lock as this station
/// has it, the entries it brought are taken (checked as any) and it is asked again.
export function inLockBringing(cloud: Cloud, admitted: Admitted, named: string, endpoint: string, hello: unknown): Admitted {
  try {
    return inLock(cloud, admitted, named, endpoint, hello);
  } catch (e) {
    if (!(e instanceof LockRefusal)) throw e;
    if (broughtForState(hello, cloud, admitted.viewer.workspace)) {
      try {
        return inLock(cloud, admitted, named, endpoint, hello);
      } catch (again) {
        if (!(again instanceof LockRefusal)) throw again;
      }
    }
    if (brought(hello, cloud, admitted.viewer.workspace, admitted.viewer.lockDevice?.base)) {
      try {
        return inLock(cloud, admitted, named, endpoint, hello);
      } catch (again) {
        if (!(again instanceof LockRefusal)) throw again;
      }
    }
    const person = onPersonalLock(cloud, admitted, named, endpoint, hello);
    if (person === null) throw e;
    return person;
  }
}

/// On the person's own lock its member bound there (`lock.person`, the chain a hello brings; none brought, or no hello,
/// the one this station has heard). The chain is checked and kept here as long as it goes on from the one this station
/// has: an older one brought again (a device taken off since) is judged as the longer it has. Null when there is none
/// to go by; throws a LockRefusal why not.
function onPersonalLock(cloud: Cloud, admitted: Admitted, named: string, endpoint: string, hello: any): Admitted | null {
  const raw = hello?.lock?.person;
  if (raw !== undefined && (!Array.isArray(raw) || raw.length === 0 || raw.length > BROUGHT_MOST)) return null;
  const v = admitted.viewer;
  const ws = v.workspace && v.workspace !== cloud.home() ? v.workspace : null;
  const state = cloud.locked(ws)?.state;
  if (!state || !state.persons.has(v.sub)) return null;
  const who = { sub: v.sub, endpoint, base: v.lockDevice?.base, proof: v.lockDevice?.proof };
  const chains = personChainsOf(cloud);
  const pin = state.persons.get(v.sub)!;
  // Let in as the chain the rules choose among what is kept and what it brought says; what it brought is kept once it
  // is in (a chain at odds that lost where it parts from the one kept, aside). A chain the rules find none in (not of
  // the lock bound here) is judged as brought.
  let newest: unknown[] | null = raw === undefined ? chains.kept(pin) : raw;
  if (raw !== undefined) {
    try {
      foldChain(raw, v.sub);
      const chosen = chains.chosen(pin, v.sub, raw);
      if (chosen.length > 0) newest = chosen;
    } catch {
      // (judged as brought)
    }
  }
  if (newest === null) return null;
  const { role, device } = admitPerson(state, who, newest);
  chains.keep(pin, raw ?? newest, v.workspace);
  return { ...admitted, viewer: { ...v, role: lowerRole(role, named), lockId: device } };
}

export type Members = {
  cloud: Cloud;
  admin: Admin;
  /// Whether the station answers now (its parts started; not handing over).
  up(): boolean;
  /// The part that answers a kind of request on a member's link itself (parts.ts `streams`: a phone lent over it).
  streams?: (head: any) => ((ask: MemberAsk) => Promise<void>) | undefined;
  /// The screens members see and drive; none: no view is answered.
  screens?: ScreenHub;
  /// The mesh's spans, when traces are on.
  traces?: Traces;
  /// Which member credentials the control plane signs (still.fail cloud's when not said).
  accepted?: () => Accepted;
  /// Where a device on the station's LAN dials it straight (lan.ts): told with the first credential's answer.
  lan?: () => string[];
  /// Where a device on the station's tailnet dials it straight (lan.ts `tailnetAddrs`): told with it.
  tailnet?: () => string[];
  /// Told each time a member's device has connected (parts.ts `memberConnected`).
  connected?: () => void;
};

/// One member's connection: the credential first, nothing served before it checks out; then a request a stream. The
/// streams are the door's (door.ts); who is let in and what is answered, `admission`'s.
export function serve(m: Members, conn: Connection): Promise<void> {
  if (m.cloud.removed()) {
    conn.close(2, "station_removed");
    return Promise.reject(new Error("station removed"));
  }
  const device = conn.remoteId();
  return door(conn, admission(m, device));
}

/// Who the door lets in here (door.ts `Admit`): a member's device, by the credential its hello brings and the lock; with
/// what its later lines (renewals) and its requests are answered, and what ends the connection meanwhile.
function admission(m: Members, device: string): Admit {
  return (hello, conn) => {
    const state = () => m.cloud.state!;
    // Which device this is in the workspace's lock: its base key's proof for this endpoint, said once (cloud/lock.ts).
    const proof = lockProof(hello?.lock);
    // A credential line checked: the member as the lock lets them in, and the role the credential names (the control
    // plane's word, which the lock may lower but not raise). Nothing of the connection is set here: the two are taken
    // together, once the lock let the member in, so a renewal refused leaves the connection as it was (2026-11-14: the
    // role one named stayed, and a member of a workspace with no lock was its owner by a credential of another
    // workspace of this station whose lock refused the device). `verified`: told whose credential checked out, before
    // the lock is asked.
    const check = (line: any, verified?: (sub: string) => void): { admitted: Admitted; named: string } => {
      // Of any workspace the station is in: the viewer's is the one its requests are answered for.
      const admitted = verifyMemberOf(typeof line?.credential === "string" ? line.credential : "", (ws: string) => m.cloud.grantKeys(ws === m.cloud.home() ? null : ws), m.cloud.memberships(), device, m.accepted?.());
      const named = admitted.viewer.role;
      verified?.(admitted.viewer.sub);
      if (proof) admitted.viewer.lockDevice = proof;
      // Which devices came, for a lock's owner to name (seen-devices.ts): what it says of itself with its lock proof
      // (`lock.kind`, `lock.label`), its base key.
      // Its base key only as its proof for this endpoint holds (as the cloud checked it).
      const base = proof && endpointProof(admitted.viewer.workspace, proof.base, device, proof.proof) ? proof.base : null;
      seenDevicesOf(m.cloud).saw(nowSecs(), admitted.viewer, device, base, line?.lock ?? null);
      const inIt = inLockBringing(m.cloud, admitted, named, device, line);
      // (no lock of its workspace here: its base key, its id on its person's own log, as its proof holds)
      return { admitted: inIt.viewer.lockId === undefined && base !== null ? { ...inIt, viewer: { ...inIt.viewer, lockId: base } } : inIt, named };
    };
    let current: Admitted;
    let named: string;
    // Whose credential checked out (refused then for the lock alone).
    let whose: string | null = null;
    try {
      ({ admitted: current, named } = check(hello, (sub) => (whose = sub)));
    } catch (e) {
      return { refused: { line: refusalOf(m.cloud, hello, device, e, m.accepted?.(), whose), code: 1, reason: e instanceof LockRefusal ? "lock_unconfirmed" : "credential_refused", error: e } };
    }
    // How far its lock goes, when it has one (a device that has more brings it).
    const head = lockHead(m.cloud, joinedOf(m.cloud, current.viewer.workspace));
    const lan = m.lan?.() ?? [];
    const tailnet = m.tailnet?.() ?? [];
    const line = { ok: true, station: m.cloud.membership(current.viewer.workspace)?.name ?? state().name, expires_at: current.exp, ...(head ? { lock: head } : {}), ...(lan.length > 0 ? { lan } : {}), ...(tailnet.length > 0 ? { tailnet } : {}) };
    // The ways it had as its last request came (said when it ends, where it has none left then).
    let lastWays = "";

    // The connection ends when its credential runs out or is revoked, or the station leaves its workspace: checked on
    // every change of the cloud's state, and when the credential runs out.
    // Or the lock takes the device away (or lowers its member's role: the next request goes with the role it has now).
    const gone = () => {
      const of = m.cloud.membership(current.viewer.workspace);
      if (m.cloud.removed() || of === null) conn.close(2, "station_removed");
      else if (revoked(current, of.revocations)) conn.close(3, "credential_revoked");
      else if (current.exp <= nowSecs()) conn.close(3, "credential_expired");
      else {
        try {
          current = stillIn(m.cloud, current, named, device);
          return false;
        } catch {
          conn.close(3, "lock_unconfirmed");
        }
      }
      return true;
    };
    // A credential's expiry is the cloud's word, in the machine's time.
    let expiry: (() => void) | undefined;
    const watchExpiry = () => {
      expiry?.();
      expiry = wall.after(Math.max(0, current.exp * 1000 - wall.now()) + 50, () => void (gone() || watchExpiry()));
    };
    let unlisten = () => {};
    return {
      line,
      opened: () => {
        // The dial's trace (the device's `mesh.connect`), said on both lines of the connection so the device's record of it
        // and the station's are found together; and the way it came, then the ways it had when it ended (2026-10-30: a
        // phone's handshake with dev-prod went through and nothing came after, and nothing here said what the station saw).
        const trace = parseParent(typeof hello?.traceparent === "string" ? hello.traceparent : undefined)?.trace;
        const opened = wall.now();
        log.info("mesh", "client connected", { email: current.viewer.email, device: device.slice(0, 12), trace, via: conn.via() ?? "direct", ways: pathsOf(conn) });
        m.connected?.();
        lastWays = pathsOf(conn);
        void conn.closed().then((why) => {
          const ways = pathsOf(conn);
          const traffic = conn.stats?.();
          log.info("mesh", "a device's connection ended", {
            device: device.slice(0, 12),
            trace,
            why,
            lasted: wall.now() - opened,
            ways: ways === "" ? lastWays : ways,
            ...(traffic ? { rx: traffic.rxBytes, tx: traffic.txBytes } : {}),
          });
        }, () => {});
        watchExpiry();
        const unlistenCloud = m.cloud.listen(gone);
        const unlistenPersons = personChainsOf(m.cloud).listen(gone);
        unlisten = () => {
          unlistenCloud();
          unlistenPersons();
        };
      },
      // Renewals on the credential stream (one that fails is answered why, by the door, and ends nothing).
      renew: (line) => {
        ({ admitted: current, named } = check(line));
        watchExpiry();
        return { ok: true, expires_at: current.exp };
      },
      stream: () => {
        if (gone()) return null;
        lastWays = pathsOf(conn);
        const viewer = { ...current.viewer, home: m.cloud.home() === current.viewer.workspace };
        return (asked) => answerAsked(m, asked, viewer, conn);
      },
      ended: () => {
        expiry?.();
        unlisten();
      },
    };
  };
}

/// One request: to the admin API in this process.
async function answerAsked(m: Members, { head, reader, stream: raw, accepted }: Asked, viewer: Admitted["viewer"], conn: Connection) {
  const method: string = typeof head.method === "string" ? head.method.toUpperCase() : "GET";
  const path: string = typeof head.path === "string" ? head.path : "";
  // A span of the caller's trace when it records one: from the stream's acceptance to its answer's last byte (an
  // event stream's, a socket's, a screen's view or a phone's offer: to its head). The admin API's goes under ours.
  const traced = tracing(m.traces, head, method, path, conn.via(), accepted, raw, reader.carry.length);
  const stream = traced.stream;
  reader.stream = stream;
  try {
    await answerRequest(m, stream, reader, head, method, path, viewer, conn);
    traced.end(null);
  } catch (error) {
    traced.end(error as Error);
    throw error;
  }
}

/// A request's span while it runs, and the stream it is answered on, counted: what the head line said (status, a
/// stream or not), how much came and went.
function tracing(traces: Traces | undefined, head: any, method: string, path: string, via: string | null, accepted: { wall: number; at: bigint }, stream: Stream, carried: number) {
  const theirs = typeof head.headers?.traceparent === "string" ? head.headers.traceparent : undefined;
  let span = traces?.start(parseParent(theirs)) ?? null;
  if (span === null || traces === undefined) return { stream, end: (_: Error | null) => {} };
  // Started when the stream was accepted, not when its head was read.
  span = { ...span, wallNs: BigInt(accepted.wall) * 1_000_000n, started: accepted.at };
  head.headers = { ...(head.headers ?? {}), traceparent: Traces.traceparent(span) };
  const outcome = { status: 0, received: carried, sent: 0, headSeen: false };
  const end = (streamed: boolean, error: Error | null) => {
    if (span === null) return;
    const attributes: [string, unknown][] = [
      ["http.request.method", method],
      ["url.path", route(path)],
      ["http.response.status_code", outcome.status],
      ["http.request.body.size", outcome.received],
    ];
    attributes.push(streamed ? ["stillfail.stream", true] : ["http.response.body.size", outcome.sent]);
    if (via !== null) attributes.push(["stillfail.path", via]);
    if (error !== null) attributes.push(["error.type", error.message]);
    traces.end(span, `${method} ${route(path)}`, attributes, error !== null || outcome.status >= 500);
    span = null;
  };
  const counted: Stream = {
    read: async () => {
      const more = await stream.read();
      if (more) outcome.received += more.length;
      return more;
    },
    write: async (bytes) => {
      await stream.write(bytes);
      if (!outcome.headSeen) {
        outcome.headSeen = true;
        const line = bytes.subarray(0, bytes.indexOf(10) < 0 ? bytes.length : bytes.indexOf(10));
        try {
          const said = JSON.parse(line.toString());
          outcome.status = Number(said.status) || 0;
          const type = String(said.headers?.["content-type"] ?? "");
          if (outcome.status === 101 || type.startsWith("text/event-stream") || type.startsWith("application/x-ndjson") || type.startsWith("application/x-stillfail-screen")) end(true, null);
        } catch {}
        outcome.sent += bytes.length - line.length - 1;
      } else outcome.sent += bytes.length;
    },
    finish: () => stream.finish(),
    stopped: () => stream.stopped(),
    reset: (code) => stream.reset(code),
  };
  return { stream: counted, end: (error: Error | null) => end(false, error) };
}

async function answerRequest(m: Members, stream: Stream, reader: Reader, head: any, method: string, path: string, viewer: Admitted["viewer"], conn: Connection) {
  const asked = wall.now();
  const answer = async (status: number, body: unknown) => {
    await writeLine(stream, { status, headers: { "content-type": "application/json" } });
    await stream.write(Buffer.from(typeof body === "string" ? body : JSON.stringify(body)));
    await stream.finish();
  };
  if (!path.startsWith("/admin/api/") || path.includes("..")) {
    return answer(404, '{"error":"only the admin API is reachable over the mesh"}');
  }
  // A core older than this station answers (api/oldest.ts): told to update, whatever it asks.
  const asking: Record<string, unknown> = head.headers !== null && typeof head.headers === "object" ? head.headers : {};
  if (coreTooOld(asking)) return answer(426, { error: tr(langOfCore(asking as Record<string, string>), "station.admin.updateApp"), update: true });
  // What build the device ran, kept by its id in the lock (device-builds.ts: written only as it rises or the day changes).
  sawBuild(m.cloud, viewer, asking);
  // One a part answers itself (a phone lent to the agents, adb/link.ts): it says what the member may.
  const part = m.streams?.(head);
  if (part !== undefined) return part({ conn, viewer, head, stream, reader });
  // A view of a screen (mesh/screens.ts): frames both ways for as long as it lasts. A read-only member views only.
  if (head.screen !== null && typeof head.screen === "object" && !Array.isArray(head.screen)) {
    if (m.screens === undefined) return answer(404, { error: "no screens on this station" });
    return answerScreen(m.screens, stream, reader.carry, head, viewer, m.up);
  }
  // A preview page's WebSocket (`"socket": true`): no body to wait for, the stream carries its messages both ways.
  if (head.socket === true) {
    // A preview's socket carries whatever its page sends: no viewer's.
    if (readOnly(viewer)) return answer(403, { error: "read-only members cannot change this station" });
    return socket(m, stream, reader, head, path);
  }
  const body = await reader.rest();
  // The caller's headers go on, but not those of the hop, nor any of the station's own: who is asking is only what
  // the credential says.
  const headers: Record<string, string> = {};
  for (const [name, value] of Object.entries(head.headers ?? {})) {
    const lower = name.toLowerCase();
    if (HOP.includes(lower) || lower.startsWith("x-stillfail-") || lower === "traceparent" || lower === "tracestate") continue;
    if (typeof value === "string") headers[name] = value;
  }
  if (!m.up()) return answer(502, { error: "station unreachable: not started" });
  const rest = path.slice("/admin/api".length);
  const at = rest.indexOf("?");
  // The workspace lock (cloud/lock.ts): the station's, here where the device that brings it is known.
  if ((at < 0 ? rest : rest.slice(0, at)) === "/lock") {
    const [status, said] = lockRoute(m.cloud, method, at < 0 ? [] : queryPairs(rest.slice(at + 1)), body, viewer);
    return answer(status, said);
  }
  // The workspace's ways (mesh/ways.ts): read by its members' devices, changed from the app's 连接方式.
  if ((at < 0 ? rest : rest.slice(0, at)) === "/ways") {
    const [status, said] = waysRoute(m.cloud, method, body, viewer);
    return answer(status, said);
  }
  // The stations' names and marks (mesh/station-marks.ts): read by its members' devices, this station's own changed.
  const marksPath = at < 0 ? rest : rest.slice(0, at);
  if (marksPath === "/station-marks" || marksPath === "/station-mark") {
    const [status, said] = stationMarksRoute(m.cloud, method, body, viewer, marksPath === "/station-mark");
    return answer(status, said);
  }
  const lockPart = /^\/lock\/(person|devices|bodies|logs)$/.exec(at < 0 ? rest : rest.slice(0, at));
  if (lockPart) {
    const [status, said] = lockPartRoute(m.cloud, lockPart[1]!, method, body, viewer);
    return answer(status, said);
  }
  // A device that stops reading or loses its connection no longer needs its pending reads. Do not cancel writes: their
  // effects and idempotency answers must be finished even when their caller goes away.
  const reads = method === "GET" || (method === "POST" && /^\/*(batch|changed\/(chats|threads|sessions))$/.test(at < 0 ? rest : rest.slice(0, at)));
  const controller = reads ? new AbortController() : null;
  let handling = true;
  if (controller) void stream.stopped().then(() => { if (handling) controller.abort(); }, () => { if (handling) controller.abort(); });
  const handled = await m.admin.handle({
    method,
    path: at < 0 ? rest : rest.slice(0, at),
    query: at < 0 ? [] : queryPairs(rest.slice(at + 1)),
    search: at < 0 ? "" : rest.slice(at),
    headers,
    body,
    viewer,
    lang: langOfCore(headers),
    ...(controller ? { signal: controller.signal } : {}),
  }).finally(() => { handling = false; });
  // Compressed, for a client that asks so (compress.ts).
  const sent = await compressed(handled, headers, rest);
  const ready = wall.now();
  await send(stream, sent);
  await stream.finish();
  if (Buffer.isBuffer(sent.body) && sent.body.length >= SLOW_REPLY_BYTES) slowly(stream, conn, () => `${method} ${route(rest.split("?")[0] ?? rest)}`, sent.body.length, ready - asked, ready);
}

/// A WebSocket of a web service on this machine, for a preview's page (preview.ts `openSocket`): answered 101 once the
/// service took it, then its messages framed both ways until either side closes. Only a preview's path is opened.
async function socket(m: Members, stream: Stream, reader: Reader, head: any, path: string) {
  const refuse = async (status: number, error: string) => {
    await writeLine(stream, { status, headers: { "content-type": "application/json" } });
    await stream.write(Buffer.from(JSON.stringify({ error })));
    await stream.finish();
  };
  const rest = path.slice("/admin/api".length);
  const at = rest.indexOf("?");
  const target = previewTarget(at < 0 ? rest : rest.slice(0, at));
  if (target === null) return refuse(404, "only a preview's WebSocket is opened over the mesh");
  if (!m.up()) return refuse(502, "station unreachable: not started");
  const headers = Object.entries(head.headers ?? {}).flatMap(([k, v]): [string, string][] => (typeof v === "string" ? [[k.toLowerCase(), v]] : []));
  const lang = langOfCore(Object.fromEntries(headers));
  let service;
  try {
    service = await openSocket(headers, target[0], target[1] + (at < 0 ? "" : rest.slice(at)), lang);
  } catch (error) {
    return refuse(error instanceof SocketRefused ? error.status : 502, (error as Error).message);
  }
  await writeLine(stream, { status: 101, headers: service.protocol === null ? {} : { "sec-websocket-protocol": service.protocol } });
  // What came with the head line is the first of the client's frames.
  await pumpSocket(service, new FrameReader(stream, reader.carry), stream);
}
