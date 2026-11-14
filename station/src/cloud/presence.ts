// The presence socket to the control plane (the Rust station's main.rs `presence`, `connect`, `apply_state`): open while
// the station answers is the station online; the cloud pushes on it where the station is, its relays and roster, and
// what it takes back. Signed at connect like enrollment. Reconnects with backoff; once removed from its workspace, asks
// again only now and then, or at once when enrolled anew meanwhile. Which control plane, and how it is spoken to, is
// the provider's (provider.ts), read anew at every connect.
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { Clock, Effect, Stream, SubscriptionRef } from "effect";
import WebSocket from "ws";
import { log } from "../ops/log.ts";
import { nowSecs } from "../ops/files.ts";
import { version } from "../ops/version.ts";
import { type Cloud as CloudState, MODE_PENDING_S, isRevocation, joinedOf, joinedPendingPath, pendingLockPath, rigGrantsPath, rigsOf, waysSaidOf } from "./state.ts";
import { type Entry, asEntry, entryHash, fold } from "./lock.ts";
import { hashOf } from "./log-keep.ts";
import type { StationKey } from "./key.ts";
import type { CloudSaid } from "./plane.ts";
import { type ProviderSpec, signedHeaders } from "./provider.ts";
import { wall } from "../ops/fibers.ts";

/// The cloud expects a "ping" this often and drops a station silent for three of them.
const PING_MS = 30_000;
/// How the cloud closes the socket of a station removed from its workspace.
const CLOSE_REMOVED = 4004;
const CONNECT_TIMEOUT_MS = 20_000;
/// How long the roster the cloud said last counts as reached once its socket ended. A socket the cloud closes is back
/// within seconds (one station's about every 20 minutes, 2026-10-29): those seconds are not shown as cut off. The roster itself
/// is taken on past this (cloud/state.ts `peersCurrent`), until the station is removed.
export const ROSTER_GRACE_MS = 60_000;


/// Whether the station is online at still.fail cloud, and since when or why not: <data>/run/presence.json, for
/// `stillfail status`.
function writePresence(data: string, online: boolean, error: string | null) {
  mkdirSync(join(data, "run"), { recursive: true });
  writeFileSync(join(data, "run", "presence.json"), JSON.stringify({ online, at: nowSecs(), error }) + "\n");
}

/// What the presence socket is given: cloud.json and its changes, the key, whether the station answers, and the
/// provider it is enrolled with.
export type PresenceParts = {
  cloud: { state: CloudState; changes: Stream.Stream<void> };
  key: StationKey;
  up: SubscriptionRef.SubscriptionRef<boolean>;
  spec: () => ProviderSpec;
  /// What the cloud tells the station of besides its state (plane.ts `told`).
  said?: (event: CloudSaid) => void;
};

/// Keeps the socket for good (until interrupted): open while the station is up.
export const presence = ({ cloud, key, up, spec, said }: PresenceParts) => Effect.gen(function* () {
  const until = (wanted: boolean) => SubscriptionRef.changes(up).pipe(Stream.filter((now) => now === wanted), Stream.runHead);
  let backoff = 1000;
  for (;;) {
    if (!(yield* SubscriptionRef.get(up))) {
      yield* until(true);
      backoff = 1000;
    }
    const s = cloud.state;
    s.reload();
    if (s.removed()) {
      // The cloud forgot the station as it removed it: only enrolling it again (by the station, which changes
      // cloud.json) brings it back, and nothing else is asked until then.
      writePresence(s.data, false, "removed from its workspace; enroll it again to bring it back");
      yield* cloud.changes.pipe(Stream.filter(() => !s.removed()), Stream.runHead);
      continue;
    }
    const started = yield* Clock.currentTimeMillis;
    const plane = spec();
    // The socket, until it ends or the station stops answering (then it is closed: offline at the cloud).
    const ended = yield* Effect.result(Effect.raceFirst(connect(s, key, plane, said), Effect.as(until(false), `station not answering; went offline at ${plane.name}`)));
    lapse(s);
    const why = ended._tag === "Success" ? ended.success : failureText(ended.failure);
    writePresence(s.data, false, why);
    if (ended._tag === "Success") log.info("presence", why);
    else log.warn("presence", `no presence socket to ${plane.name}`, { error: why });
    // A socket that held a while starts over quickly; failing again and again backs off to a minute.
    if ((yield* Clock.currentTimeMillis) - started > 60_000) backoff = 1000;
    yield* Effect.sleep(backoff);
    backoff = Math.min(backoff * 2, 60_000);
  }
});

/// What a failed socket says: every address's own error when they all failed (Node's AggregateError, whose message is
/// empty: the log said only `error=`).
export function failureText(error: Error): string {
  const each = error instanceof AggregateError ? error.errors.map((e) => (e instanceof Error ? e.message : String(e))).filter((m) => m.length > 0) : [];
  return each.length > 0 ? each.join("; ") : error.message || error.name;
}

/// The roster said last, no longer reached once ROSTER_GRACE_MS passed with no fresh one; not taken at all at once when
/// the station was removed.
export function lapse(s: CloudState, after: (ms: number, f: () => void) => unknown = wall.after) {
  if (s.removed()) {
    s.lapsed();
    return;
  }
  const said = s.rostersSaid;
  after(ROSTER_GRACE_MS, () => {
    if (s.rostersSaid === said) s.lapsed();
  });
}

/// Whether `event` is something the cloud tells of besides the station's state (a release out, the models' catalog
/// changed), told to `said`.
function cloudSaid(event: unknown, said?: (event: CloudSaid) => void): boolean {
  const type = (event as { type?: unknown } | null)?.type;
  if (type === "release") said?.({ type });
  else if (type === "models") {
    const etag = (event as { etag?: unknown }).etag;
    said?.(typeof etag === "string" ? { type, etag } : { type });
  } else return false;
  return true;
}

/// One socket, signed at connect like enrollment: succeeds with why it ended when the cloud closes it, fails when it
/// can't be had or breaks; closed when interrupted.
const connect = (s: CloudState, key: StationKey, plane: ProviderSpec, said?: (event: CloudSaid) => void) =>
  Effect.callback<string, Error>((resume) => {
    const state = s.state!;
    const ts = nowSecs();
    // New clouds read the canonical proof; old clouds their original one.
    const headers = signedHeaders(plane.connectPrefixes, state.station, ts, (prefix) => key.sign(`${prefix}-station-connect-v1:${state.origin}:${state.station}:${ts}`), { version: version() });
    const socket = new WebSocket(`${state.origin.replace("http", "ws")}${plane.connectPath}`, { headers, handshakeTimeout: CONNECT_TIMEOUT_MS });
    let ping: (() => void) | undefined;
    let answered = true;
    const { tell, askPending } = planeTeller(s, (frame) => socket.send(JSON.stringify(frame)), () => socket.readyState === WebSocket.OPEN);
    tell();
    const unlisten = s.listen(tell);
    let failed: Error | null = null;
    socket.on("unexpected-response", (_, response) => {
      if (response.statusCode === 404) {
        removed(s, 404);
        failed = new Error("station removed");
      } else {
        failed = new Error(`${plane.name} answered ${response.statusCode}`);
      }
      socket.terminate();
    });
    socket.on("error", (error) => (failed ??= error));
    socket.on("open", () => {
      takenBack(s, plane);
      writePresence(s.data, true, null);
      log.info("presence", `online at ${plane.name}`);
      // The cloud's answering is in the machine's time.
      ping = wall.every(PING_MS, () => {
        // No pong since the last ping: gone even if the socket has not noticed.
        if (!answered) {
          failed = new Error(`${plane.name} stopped answering`);
          socket.terminate();
          return;
        }
        answered = false;
        socket.send("ping");
        askPending();
      });
    });
    socket.on("message", (data, binary) => {
      if (binary) return;
      const text = data.toString();
      if (text === "pong") {
        answered = true;
        return;
      }
      // Each frame is told by its parsed `type`, never by where that field sits in the text: a provider's encoder may
      // put it anywhere (Comma's map encoder puts it last).
      let body: any;
      try {
        body = JSON.parse(text);
      } catch {
        return;
      }
      if (cloudSaid(body, said)) return;
      if (body?.type === "tool") tool(s, plane, socket, body);
      else applyFrame(s, body, (frame) => socket.readyState === WebSocket.OPEN && socket.send(JSON.stringify(frame)));
    });
    socket.on("close", (code, reason) => {
      ping?.();
      unlisten();
      if (code === CLOSE_REMOVED) removed(s, CLOSE_REMOVED);
      // With its code and reason: replaced by another socket of this station's (4000), silent (4008), the cloud restarting (1001, 1012)…
      const why = reason.length > 0 ? `${code} ${reason.toString("utf8")}` : String(code);
      resume(failed ? Effect.fail(failed) : Effect.succeed(`${plane.name} closed the presence socket (${why})`));
    });
    return Effect.sync(() => {
      ping?.();
      unlisten();
      socket.close();
    });
  });

/// What a station tells the plane of its locks on one socket (`send`, while `open`): the entries it took from devices
/// and other stations since the socket opened (the plane keeps the lock for whoever asks it next): the home
/// workspace's, and each joined one's (`workspace` says which); and the locks joining named, asked for (pendingAsks).
/// `tell` as cloud.json changes, `askPending` as the station hears it joined and at each ping.
export function planeTeller(s: CloudState, send: (frame: unknown) => void, open: () => boolean) {
  const told = new Map<string, number>();
  const asked = new Set<string>();
  const askPending = () => {
    if (!open()) return;
    for (const ws of pendingAsks(s, asked)) send({ type: "lock.get", after: -1, workspace: ws });
  };
  const tell = () => {
    for (const m of s.memberships()) {
      const ws = m.home ? null : m.workspace;
      const seq = s.chain(ws)?.state?.seq;
      const plane = ws === null ? s.planeLockSeq : (s.planeLockSeqs.get(ws) ?? null);
      const was = told.get(m.workspace) ?? (s.chain(ws)?.state?.seq ?? -1);
      if (!told.has(m.workspace)) told.set(m.workspace, was);
      if (seq === undefined || !open() || plane === null) continue;
      // (a plane whose chain parted from the one gone by here, this station's having moved to another branch since the
      // plane said its head, at the same place too: given what it goes by from where they part, planeParted)
      if (!planeOnChain(s, ws, plane)) {
        planeParted(s, ws, send);
        continue;
      }
      if (seq <= was) continue;
      const entries = s.lockAfter(Math.max(plane, -1), ws);
      if (entries.length > 0) send({ type: "lock.put", entries, ...(ws === null ? {} : { workspace: ws }) });
      told.set(m.workspace, seq);
    }
    askPending();
  };
  return { tell, askPending };
}

/// A device tool request pushed on the socket (`{type: "tool", id, request}`, contract §8 presence transport): run
/// by the mesh's tools and answered `{type: "tool_result", id, response}`. Only a provider with device tools pushes
/// them.
function tool(s: CloudState, plane: ProviderSpec, socket: WebSocket, body: any) {
  if (typeof body.id !== "string") return;
  // Locked, the control plane pushes no tools: a gateway the lock names calls them itself (mesh/tools.ts).
  const run = plane.tools && s.locked() === null ? s.toolCalls : null;
  const reply = (response: unknown) => {
    if (socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify({ type: "tool_result", id: body.id, response }));
  };
  if (run === null) reply({ ok: false, error: { code: "unavailable", message: "this station takes no device tools now" } });
  else run(body.request).then(reply, (e) => reply({ ok: false, error: { code: "invalid_request", message: (e as Error).message } }));
}

/// The cloud says the station is out of its workspace: marked in cloud.json, kept through restarts.
function removed(s: CloudState, code: number) {
  if (s.removed()) return;
  log.warn("presence", "this station was removed from its workspace; it stops its work and refuses connections", { code });
  s.update((st) => {
    st.removed_at = nowSecs();
    st.removed_code = code;
  });
}

/// The cloud took the socket: a station it had removed is in its workspace again.
function takenBack(s: CloudState, plane: ProviderSpec) {
  if (!s.removed()) return;
  log.info("presence", `${plane.name} takes this station again; back to work`);
  s.update((st) => {
    delete st.removed_at;
    delete st.removed_code;
  });
}

/// What the cloud pushes: where the station is and what it is called, its relays, roster and grant keys, what it
/// takes back; the workspace lock's head, and its entries when asked (`send` answers on the socket). Once a lock is
/// pinned, the station stays in its workspace and at its origin whatever the frame says, and the roster and gateways
/// are only those the lock names too (cloud/state.ts `filtered`).
export function applyState(s: CloudState, text: string, send: (frame: unknown) => unknown = () => {}) {
  let body: any;
  try {
    body = JSON.parse(text);
  } catch {
    return;
  }
  applyFrame(s, body, send);
}

function applyFrame(s: CloudState, body: any, send: (frame: unknown) => unknown) {
  if (body?.type === "state") {
    // A workspace it joined taking over from a home it was taken out of: its lock goes along (cloud/state.ts `succeed`).
    // So too, its home not locked (which the plane moves at its word), any workspace this station keeps a lock for, or
    // one joining named, listed now or not, its old home gone or not: else that lock, joined workspaces' only, would
    // be left behind and the workspace taken as the plane says.
    const was = s.state;
    const moved = was !== null && typeof body.workspace === "string" && body.workspace !== was.workspace;
    const keptThere = moved && s.chain() === null && (s.chain(body.workspace) !== null || s.pendingLock(body.workspace) !== null);
    const took = moved
      && (keptThere || ((was.joined ?? []).some((j) => j.workspace === body.workspace) && !joinedOf(body.workspaces).some((j) => j.workspace === was.workspace)))
      && s.succeed(body.workspace);
    const locked = s.chain() !== null;
    if (locked && s.state && ((typeof body.workspace === "string" && body.workspace !== s.state.workspace && !took) || (typeof body.origin === "string" && body.origin !== s.state.origin))) {
      log.warn("lock", "the control plane moves this station; the workspace lock keeps it where it is", { workspace: body.workspace, origin: body.origin });
    }
    s.setPlaneLists(Array.isArray(body.peers) ? body.peers : [], Array.isArray(body.gateway_keys) ? body.gateway_keys.filter((k: unknown): k is string => typeof k === "string") : undefined);
    // Current before it is told, so whoever hears of the new roster reads it as current.
    s.peersCurrent = Array.isArray(body.peers);
    s.reached = s.peersCurrent;
    s.rostersSaid = (s.rostersSaid ?? 0) + 1;
    s.update((st) => {
      for (const k of ["workspace", "workspace_name", "name", "origin", "relay_url"] as const) {
        if (locked && (k === "origin" || (k === "workspace" && !took))) continue;
        if (typeof body[k] === "string") st[k] = body[k];
      }
      if (Array.isArray(body.relay_urls)) st.relay_urls = body.relay_urls.filter((u: unknown) => typeof u === "string");
      // The home workspace's own relays and ways turned off as the plane kept them: what mesh/ways.ts takes first.
      const ways = waysSaidOf(body.ways);
      if (ways !== null) st.ways = ways;
      else delete st.ways;
      // Kept as said; once locked, credentials are checked with the lock's keys instead (cloud/state.ts `grantKeys`).
      if (body.grant_keys && typeof body.grant_keys === "object" && !Array.isArray(body.grant_keys)) st.grant_keys = body.grant_keys;
      if (Array.isArray(body.revocations) && body.revocations.every(isRevocation)) st.revocations = body.revocations;
      // The workspaces it joined besides its home one: none from planes of before them. One it is no longer in: not
      // served, its lock kept (the plane's word alone undoes no lock: cloud/state.ts `leftJoined`).
      const joined = joinedOf(body.workspaces);
      for (const was of st.joined ?? []) if (!joined.some((j) => j.workspace === was.workspace)) s.leftJoined(was.workspace);
      if (joined.length > 0) st.joined = joined;
      else delete st.joined;
      // Missing roster means an old cloud: never keep peers from another binding. Who may call the device tools
      // (Comma's gateways): only from a control plane that names them.
      const { peers, gateways } = s.filtered(st);
      st.peers = Array.isArray(body.peers) ? peers : [];
      if (Array.isArray(body.gateway_keys)) st.gateway_keys = gateways;
      // The home workspace's rigs (a plane from before them names none). Whether this machine is one is what
      // `enroll --rig` wrote, never the plane's to change: a rig made a station by its word would take every
      // station's requests with no grant, a station made a rig would stop serving its chats.
      const rigs = rigsOf(body.rigs);
      if (rigs.length > 0 && st.rig === undefined) st.rigs = rigs;
      else delete st.rigs;
      // A change of what this machine is, asked of it over a way the plane has no part in (a device of whose it will be
      // that reached it; its person's signature) and waiting here: done once the plane lists it so. The plane's word alone
      // changes nothing, and what waited too long is forgotten.
      const listedRig = body.rig !== null && typeof body.rig === "object" && typeof body.rig.owner === "string" ? (body.rig.owner as string) : null;
      const fresh = (at: number) => nowSecs() - at <= MODE_PENDING_S;
      if (st.rig_pending !== undefined && !fresh(st.rig_pending.at)) delete st.rig_pending;
      if (st.full_pending !== undefined && !fresh(st.full_pending.at)) delete st.full_pending;
      if (st.rig === undefined && st.rig_pending !== undefined && listedRig === st.rig_pending.owner && joined.length === 0) st.rig_due = true;
      if (st.rig !== undefined && st.full_pending !== undefined && listedRig === null) {
        log.warn("presence", "this rig is listed as a whole station, as its person signed: it becomes one");
        delete st.rig;
        delete st.full_pending;
        rmSync(rigGrantsPath(s.data), { force: true });
      }
    });
    syncLock(s, body.lock, send);
    // Each joined workspace's lock too, level with the plane's.
    if (Array.isArray(body.workspaces)) {
      for (const j of body.workspaces) if (typeof j?.workspace === "string" && s.state?.joined?.some((x) => x.workspace === j.workspace)) syncLock(s, j.lock, send, j.workspace);
    }
  } else if (body?.type === "revoke" && isRevocation(body)) {
    // Of the workspace it names (planes of before say none: the home one's).
    const named: unknown = (body as any).workspace;
    s.update((st) => {
      const elsewhere = typeof named === "string" && named !== st.workspace;
      const joined = elsewhere ? st.joined?.find((j) => j.workspace === named) : undefined;
      if (elsewhere && joined === undefined) return;
      const of = joined ?? st;
      of.revocations = of.revocations.filter((r) => !(r.kind === body.kind && r.id === body.id));
      of.revocations.push({ kind: body.kind, id: body.id, at: body.at });
    });
  } else if (body?.type === "lock" && Array.isArray(body.entries)) {
    takeFromPlane(s, body.entries, typeof body.workspace === "string" && body.workspace !== s.state?.workspace ? body.workspace : null, send);
  }
}

/// The joined workspaces whose lock, named by joining, is to be asked for now: not pinned yet, the plane having one
/// there, not asked for on this connection (`asked`, kept by it). The plane tells the station it joined (a `state`
/// frame) before it answers the join, so that frame came before joining wrote which lock to pin and asked for nothing:
/// the station took none of that workspace's members until a later frame, which may not come for days (2026-10-23).
export function pendingAsks(s: CloudState, asked: Set<string>): string[] {
  const out: string[] = [];
  for (const j of s.state?.joined ?? []) {
    if (s.leftOut(j.workspace) !== "pending" || (s.planeLockSeqs.get(j.workspace) ?? -1) < 0) continue;
    const key = `${j.workspace}/${s.pendingLock(j.workspace)}`;
    if (asked.has(key)) continue;
    asked.add(key);
    out.push(j.workspace);
  }
  return out;
}

/// The control plane's lock head against this station's, in `ws` (the home workspace when null): asks for what it
/// lacks, gives what the plane lacks (the plane only keeps and carries the lock: a station brings it back what it
/// lost). Where none is pinned, it asks only for a lock `enroll --lock` (or joining) named. Its entries are taken only
/// where they go on from the head (cloud/state.ts `keepLock` says why); it is given what follows its head where that is
/// on the chain this station goes by, and where its chain parted from it (it kept an entry that lost, or that no
/// station took) what this station goes by from there, as another keeper's (`planeParted`): a plane of today keeps it
/// by the rules' fork choice and comes to the stations' chain (cloud/src/lock.ts `keepLockAt`), one from before
/// refuses it as before.
function syncLock(s: CloudState, head: any, send: (frame: unknown) => unknown, ws: string | null = null) {
  const theirs = head !== null && typeof head === "object" && Number.isSafeInteger(head.seq) ? (head.seq as number) : -1;
  const which = ws === null ? {} : { workspace: ws };
  // A cloud from before locks says nothing of one: nothing is given to it.
  if (ws === null) s.planeLockSeq = head === undefined ? null : theirs;
  else s.planeLockSeqs.set(ws, head === undefined ? null : theirs);
  const hashes = (s.planeLockHashes ??= new Map());
  if (theirs >= 0 && typeof head?.hash === "string") hashes.set(ws ?? "", head.hash);
  else hashes.delete(ws ?? "");
  const mine = s.chain(ws)?.state?.seq;
  if (mine === undefined) {
    const pending = ws === null ? pendingLock(s.data) : s.pendingLock(ws);
    // (a joined workspace that turned its lock on after this station joined it, this station not in it then: its lock,
    // pinned once it names this station, takeFromPlane)
    if (theirs >= 0 && (pending !== null || (ws !== null && s.leftOut(ws) === "unpinned"))) send({ type: "lock.get", after: -1, ...which });
    return;
  }
  // The plane's lock another than the one pinned here: turned off and on again while this station was not there to hear
  // it. Asked for the rest of its own (the plane keeps a chain turned off): its `disable` lets it go.
  const genesis = s.chain(ws)?.state?.genesis;
  if (head !== null && typeof head === "object" && typeof head.genesis === "string" && genesis !== undefined && head.genesis !== genesis) send({ type: "lock.get", after: mine, genesis, ...which });
  else if (!planeOnChain(s, ws, theirs)) planeParted(s, ws, send);
  else if (theirs > mine) send({ type: "lock.get", after: mine, ...which });
  else if (theirs < mine) send({ type: "lock.put", entries: s.lockAfter(theirs, ws), ...which });
}

/// Whether the control plane's head of `ws`'s lock (`seq`, its hash as its frame said) is on the chain this station goes
/// by, or may be: further than it goes (what it lacks is asked for), none, or a plane that says no hash.
function planeOnChain(s: CloudState, ws: string | null, seq: number): boolean {
  const hash = s.planeLockHashes?.get(ws ?? "");
  if (seq < 0 || hash === undefined) return true;
  const at = s.lockAfter(seq - 1, ws)[0];
  if (at !== undefined && at.seq === seq) return hashOf(at) === hash;
  // Further: unless it is an entry kept here off the chain.
  return !s.lockKept(ws).some((e) => hashOf(e) === hash);
}

/// At most this many entries a `lock.put` brings the plane (cloud/src/directory.ts takes no more at once).
const PUT_MOST = 256;

/// The control plane's chain of `ws`'s lock parted from the one gone by here: given, once for each head of the plane's
/// and of this station's (found as the plane says its head, or as this station's chain moves), what this station
/// goes by from where the plane's parts from it (that head's nearest entry on this chain, where this station keeps the
/// head aside; else the last PUT_MOST of its chain), with `keep`, as what another keeper took: a plane of today keeps it
/// by the rules' fork choice, so it moves to this chain where that wins, and the entries after it are taken there again
/// (a plane that kept the entry that lost refused every one after the chain that won, 2026-11-12). A plane from before
/// refuses it and says its head again, which is said here already. Nothing is taken from it that would not be before:
/// what it brings is taken only where it goes on from the head (`takeFromPlane`).
function planeParted(s: CloudState, ws: string | null, send: (frame: unknown) => unknown) {
  const key = ws ?? "";
  const hash = s.planeLockHashes?.get(key) ?? "";
  const which = ws === null ? {} : { workspace: ws };
  const said = (s.planeParted ??= new Map());
  const chain = s.lockAfter(-1, ws);
  const both = `${hash}>${chain.length === 0 ? "" : hashOf(chain.at(-1)!)}`;
  if (said.get(key) === both) return;
  said.set(key, both);
  const on = new Set(chain.map(hashOf));
  const kept = new Map(s.lockKept(ws).map((e) => [hashOf(e), e] as const));
  let at = kept.get(hash);
  while (at !== undefined && !on.has(hashOf(at))) at = at.prev === null ? undefined : kept.get(at.prev);
  const entries = at !== undefined ? chain.filter((e) => e.seq > at!.seq).slice(0, PUT_MOST) : chain.slice(-PUT_MOST);
  log.warn("lock", "the control plane's copy of the lock parted from the chain this station goes by; it is given this station's", { plane: hash.slice(0, 12), seq: s.chain(ws)?.state?.seq, from: entries[0]?.seq, ...which });
  if (entries.length > 0) send({ type: "lock.put", entries, keep: true, ...which });
}

/// Entries the control plane brought, of `ws`'s lock (the home workspace's when null): more of the pinned lock, or the
/// lock `enroll --lock` (or joining) named (pinned only when its chain holds that entry).
function takeFromPlane(s: CloudState, raw: unknown[], ws: string | null = null, send: (frame: unknown) => unknown = () => {}) {
  const entries = raw.map(asEntry);
  if (entries.some((e) => e === null)) return log.warn("lock", "the control plane sent a malformed lock entry");
  try {
    if (s.chain(ws) === null) {
      const pending = ws === null ? pendingLock(s.data) : s.pendingLock(ws);
      // A joined workspace that turned its lock on after this station joined it: it takes none of its members (leftOut
      // `unpinned`) until it pins a lock, which no device of it can bring (it refuses them all). Its lock as the plane
      // has it, once that names this station (its owner put it in, `lock.joinStation`): pinned, as it was the plane's
      // word it took for that workspace before (2026-11-04: a workspace's members turned away for two hours, then the
      // station removed from it and added again).
      if (pending === null && ws !== null && s.leftOut(ws) === "unpinned") {
        let named = false;
        try {
          named = fold(entries as Entry[], null).stations.has(s.state?.station ?? "");
        } catch {
          named = false;
        }
        if (named) s.takeLock(entries as Entry[], ws);
        // (moved, its stations a statement adds are said in its people's logs, which the chain never names: offered,
        // pinned once the state its logs and bodies make names this station, fetched of a station of it, mesh/moved-pin.ts;
        // 2026-11-14, the locks' end to end, round 17: 「保护」 after a move left the station unprotected for good)
        else if ((entries as Entry[]).some((e) => e.kind === "moved")) s.offerMoved(ws, entries as Entry[]);
        return;
      }
      if (pending === null) return;
      if (!entries.some((e) => entryHash(e!) === pending)) return log.warn("lock", "the control plane's lock is not the one this station was enrolled with", ws === null ? {} : { workspace: ws });
      s.takeLock(entries as Entry[], ws);
      rmSync(ws === null ? pendingLockPath(s.data) : joinedPendingPath(s.data, ws), { force: true });
    } else {
      try {
        s.takeLock(entries as Entry[], ws);
      } finally {
        // What it brought did not bring its head here: its chain parted below the one gone by here.
        const hash = s.planeLockHashes?.get(ws ?? "");
        if (hash !== undefined && s.chain(ws) !== null && !s.lockKept(ws).some((e) => hashOf(e) === hash)) planeParted(s, ws, send);
      }
    }
  } catch (e) {
    log.warn("lock", "the control plane's lock entries were refused", { error: (e as Error).message });
  }
}

/// The lock hash `enroll --lock` left to pin, if any.
export function pendingLock(data: string): string | null {
  try {
    const hash = JSON.parse(readFileSync(pendingLockPath(data), "utf8"))?.hash;
    return typeof hash === "string" && /^[0-9a-f]{64}$/.test(hash) ? hash : null;
  } catch {
    return null;
  }
}
