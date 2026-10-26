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
import { type Cloud as CloudState, isRevocation, joinedOf, joinedPendingPath, pendingLockPath } from "./state.ts";
import { type Entry, asEntry, entryHash } from "./lock.ts";
import type { StationKey } from "./key.ts";
import { type ProviderSpec, signedHeaders } from "./provider.ts";
import { wall } from "../ops/fibers.ts";

/// The cloud expects a "ping" this often and drops a station silent for three of them.
const PING_MS = 30_000;
/// How the cloud closes the socket of a station removed from its workspace.
const CLOSE_REMOVED = 4004;
const REMOVED_RETRY_MS = 600_000;
const CONNECT_TIMEOUT_MS = 20_000;

/// REMOVED_RETRY, or STILLFAIL_REMOVED_RETRY_SECS (tests against a dev cloud).
function removedRetry(): number {
  const secs = Number(process.env.STILLFAIL_REMOVED_RETRY_SECS?.trim());
  return Number.isFinite(secs) && secs > 0 ? secs * 1000 : REMOVED_RETRY_MS;
}

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
};

/// Keeps the socket for good (until interrupted): open while the station is up.
export const presence = ({ cloud, key, up, spec }: PresenceParts) => Effect.gen(function* () {
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
      const retry = removedRetry();
      const every = retry === REMOVED_RETRY_MS ? "every 10 minutes" : `every ${retry / 1000} s`;
      writePresence(s.data, false, `removed from its workspace; the cloud is asked again ${every}`);
      // Enrolled again meanwhile (the file changes): ask at once.
      yield* Effect.raceFirst(Effect.sleep(retry), cloud.changes.pipe(Stream.filter(() => !s.removed()), Stream.runHead));
    }
    const started = yield* Clock.currentTimeMillis;
    s.peersCurrent = false;
    const plane = spec();
    // The socket, until it ends or the station stops answering (then it is closed: offline at the cloud).
    const ended = yield* Effect.result(Effect.raceFirst(connect(s, key, plane), Effect.as(until(false), `station not answering; went offline at ${plane.name}`)));
    s.peersCurrent = false;
    const why = ended._tag === "Success" ? ended.success : ended.failure.message;
    writePresence(s.data, false, why);
    if (ended._tag === "Success") log.info("presence", why);
    else log.warn("presence", `no presence socket to ${plane.name}`, { error: why });
    // A socket that held a while starts over quickly; failing again and again backs off to a minute.
    if ((yield* Clock.currentTimeMillis) - started > 60_000) backoff = 1000;
    yield* Effect.sleep(backoff);
    backoff = Math.min(backoff * 2, 60_000);
  }
});

/// One socket, signed at connect like enrollment: succeeds with why it ended when the cloud closes it, fails when it
/// can't be had or breaks; closed when interrupted.
const connect = (s: CloudState, key: StationKey, plane: ProviderSpec) =>
  Effect.callback<string, Error>((resume) => {
    const state = s.state!;
    const ts = nowSecs();
    // New clouds read the canonical proof; old clouds their original one.
    const headers = signedHeaders(plane.connectPrefixes, state.station, ts, (prefix) => key.sign(`${prefix}-station-connect-v1:${state.origin}:${state.station}:${ts}`), { version: version() });
    const socket = new WebSocket(`${state.origin.replace("http", "ws")}${plane.connectPath}`, { headers, handshakeTimeout: CONNECT_TIMEOUT_MS });
    let ping: (() => void) | undefined;
    let answered = true;
    // Entries this station took from devices and other stations, given to the plane too (it keeps the lock for whoever
    // asks it next): the home workspace's, and each joined one's (`workspace` says which).
    const told = new Map<string, number>();
    const tell = () => {
      for (const m of s.memberships()) {
        const ws = m.home ? null : m.workspace;
        const seq = s.locked(ws)?.state?.seq;
        const plane = ws === null ? s.planeLockSeq : (s.planeLockSeqs.get(ws) ?? null);
        const was = told.get(m.workspace) ?? (s.locked(ws)?.state?.seq ?? -1);
        if (!told.has(m.workspace)) told.set(m.workspace, was);
        if (seq === undefined || seq <= was || socket.readyState !== WebSocket.OPEN || plane === null) continue;
        const entries = s.lockAfter(Math.max(plane, -1), ws);
        if (entries.length > 0) socket.send(JSON.stringify({ type: "lock.put", entries, ...(ws === null ? {} : { workspace: ws }) }));
        told.set(m.workspace, seq);
      }
      askPending();
    };
    // The lock joining a workspace named, asked for (pendingAsks) as the station hears it joined and at each ping.
    const asked = new Set<string>();
    const askPending = () => {
      if (socket.readyState !== WebSocket.OPEN) return;
      for (const ws of pendingAsks(s, asked)) socket.send(JSON.stringify({ type: "lock.get", after: -1, workspace: ws }));
    };
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
      if (text === "pong") answered = true;
      else if (!tool(s, plane, socket, text)) applyState(s, text, (frame) => socket.readyState === WebSocket.OPEN && socket.send(JSON.stringify(frame)));
    });
    socket.on("close", (code) => {
      ping?.();
      unlisten();
      if (code === CLOSE_REMOVED) removed(s, CLOSE_REMOVED);
      resume(failed ? Effect.fail(failed) : Effect.succeed(`${plane.name} closed the presence socket`));
    });
    return Effect.sync(() => {
      ping?.();
      unlisten();
      socket.close();
    });
  });

/// A device tool request pushed on the socket (`{type: "tool", id, request}`, contract §8 presence transport): run
/// by the mesh's tools and answered `{type: "tool_result", id, response}`. Only a provider with device tools pushes
/// them; anything else is not a tool frame.
function tool(s: CloudState, plane: ProviderSpec, socket: WebSocket, text: string): boolean {
  if (!text.startsWith('{"type":"tool"')) return false;
  let body: any;
  try {
    body = JSON.parse(text);
  } catch {
    return false;
  }
  if (body?.type !== "tool" || typeof body.id !== "string") return false;
  // Locked, the control plane pushes no tools: a gateway the lock names calls them itself (mesh/tools.ts).
  const run = plane.tools && s.locked() === null ? s.toolCalls : null;
  const reply = (response: unknown) => {
    if (socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify({ type: "tool_result", id: body.id, response }));
  };
  if (run === null) reply({ ok: false, error: { code: "unavailable", message: "this station takes no device tools now" } });
  else run(body.request).then(reply, (e) => reply({ ok: false, error: { code: "invalid_request", message: (e as Error).message } }));
  return true;
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
  if (body?.type === "state") {
    // A workspace it joined taking over from a home it was taken out of: its lock goes along (cloud/state.ts `succeed`).
    const was = s.state;
    const took = was !== null && typeof body.workspace === "string" && body.workspace !== was.workspace
      && (was.joined ?? []).some((j) => j.workspace === body.workspace) && !joinedOf(body.workspaces).some((j) => j.workspace === was.workspace)
      && s.succeed(body.workspace);
    const locked = s.locked() !== null;
    if (locked && s.state && ((typeof body.workspace === "string" && body.workspace !== s.state.workspace && !took) || (typeof body.origin === "string" && body.origin !== s.state.origin))) {
      log.warn("lock", "the control plane moves this station; the workspace lock keeps it where it is", { workspace: body.workspace, origin: body.origin });
    }
    s.setPlaneLists(Array.isArray(body.peers) ? body.peers : [], Array.isArray(body.gateway_keys) ? body.gateway_keys.filter((k: unknown): k is string => typeof k === "string") : undefined);
    // Current before it is told, so whoever hears of the new roster reads it as current.
    s.peersCurrent = Array.isArray(body.peers);
    s.update((st) => {
      for (const k of ["workspace", "workspace_name", "name", "origin", "relay_url"] as const) {
        if (locked && (k === "origin" || (k === "workspace" && !took))) continue;
        if (typeof body[k] === "string") st[k] = body[k];
      }
      if (Array.isArray(body.relay_urls)) st.relay_urls = body.relay_urls.filter((u: unknown) => typeof u === "string");
      // Kept as said; once locked, credentials are checked with the lock's keys instead (cloud/state.ts `grantKeys`).
      if (body.grant_keys && typeof body.grant_keys === "object" && !Array.isArray(body.grant_keys)) st.grant_keys = body.grant_keys;
      if (Array.isArray(body.revocations) && body.revocations.every(isRevocation)) st.revocations = body.revocations;
      // The workspaces it joined besides its home one: none from planes of before them. One it is no longer in: its
      // lock forgotten.
      const joined = joinedOf(body.workspaces);
      for (const was of st.joined ?? []) if (!joined.some((j) => j.workspace === was.workspace)) s.forgetJoined(was.workspace);
      if (joined.length > 0) st.joined = joined;
      else delete st.joined;
      // Missing roster means an old cloud: never keep peers from another binding. Who may call the device tools
      // (Comma's gateways): only from a control plane that names them.
      const { peers, gateways } = s.filtered(st);
      st.peers = Array.isArray(body.peers) ? peers : [];
      if (Array.isArray(body.gateway_keys)) st.gateway_keys = gateways;
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
    takeFromPlane(s, body.entries, typeof body.workspace === "string" && body.workspace !== s.state?.workspace ? body.workspace : null);
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
/// lost). Where none is pinned, it asks only for a lock `enroll --lock` (or joining) named.
function syncLock(s: CloudState, head: any, send: (frame: unknown) => unknown, ws: string | null = null) {
  const theirs = head !== null && typeof head === "object" && Number.isSafeInteger(head.seq) ? (head.seq as number) : -1;
  const which = ws === null ? {} : { workspace: ws };
  // A cloud from before locks says nothing of one: nothing is given to it.
  if (ws === null) s.planeLockSeq = head === undefined ? null : theirs;
  else s.planeLockSeqs.set(ws, head === undefined ? null : theirs);
  const mine = s.locked(ws)?.state?.seq;
  if (mine === undefined) {
    const pending = ws === null ? pendingLock(s.data) : s.pendingLock(ws);
    if (theirs >= 0 && pending !== null) send({ type: "lock.get", after: -1, ...which });
    return;
  }
  if (theirs > mine) send({ type: "lock.get", after: mine, ...which });
  else if (theirs < mine) send({ type: "lock.put", entries: s.lockAfter(theirs, ws), ...which });
}

/// Entries the control plane brought, of `ws`'s lock (the home workspace's when null): more of the pinned lock, or the
/// lock `enroll --lock` (or joining) named (pinned only when its chain holds that entry).
function takeFromPlane(s: CloudState, raw: unknown[], ws: string | null = null) {
  const entries = raw.map(asEntry);
  if (entries.some((e) => e === null)) return log.warn("lock", "the control plane sent a malformed lock entry");
  try {
    if (s.locked(ws) === null) {
      const pending = ws === null ? pendingLock(s.data) : s.pendingLock(ws);
      if (pending === null) return;
      if (!entries.some((e) => entryHash(e!) === pending)) return log.warn("lock", "the control plane's lock is not the one this station was enrolled with", ws === null ? {} : { workspace: ws });
      s.takeLock(entries as Entry[], ws);
      rmSync(ws === null ? pendingLockPath(s.data) : joinedPendingPath(s.data, ws), { force: true });
    } else s.takeLock(entries as Entry[], ws);
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
