// Members' connections over the mesh (the Rust station's main.rs `serve`, `relay_request`). Wire format, on ALPN
// `stillfail/admin/1` (and `ember/admin/1`, as clients from before the rename ask): the first bidirectional stream
// carries credentials, one JSON line each, answered with one JSON line (a later line renews); every other stream is
// one request: a JSON head line `{method, path, headers}`, then the body until the stream finishes, answered by a
// JSON head line `{status, headers}` and the response body.
import type { Admin } from "../api/admin.ts";
import { type Answer, langOfCore, queryPairs } from "../api/request.ts";
import type { Cloud } from "../cloud/state.ts";
import { log } from "../ops/log.ts";
import { wall } from "../ops/fibers.ts";
import { nowSecs } from "../ops/files.ts";
import type { Accepted } from "../cloud/provider.ts";
import { type Admitted, readOnly, revoked, verifyMemberOf } from "./credential.ts";
import { type Entry, LockRefusal, admit, asEntry, genesis, lowerRole } from "../cloud/lock.ts";
import type { Connection, Stream } from "./native.ts";
import { answerScreen } from "./screens.ts";
import type { ScreenHub } from "../screens/hub.ts";
import type { MemberAsk } from "../parts.ts";
import { compressed } from "./compress.ts";
import { Traces, parseParent, route } from "./traces.ts";
import { FrameReader, SocketRefused, openSocket, previewTarget, pumpSocket } from "../jobs/preview.ts";
import { isModulePath } from "../modules/modules.ts";

export const ALPN = Buffer.from("stillfail/admin/1");
export const FORMER_ALPN = Buffer.from("ember/admin/1");
// Keep old clients admitted until protocol-2 clients have reached the stable channel.
const MIN_CLIENT_PROTOCOL = 1;
const MAX_HEAD = 16 * 1024;
// Files sent to a session go through here: in parts of 16 MB at most, or whole up to 50 MB (clients before parts).
const MAX_BODY = 64 * 1024 * 1024;
/// A reply this long or longer whose bytes took more than SLOW_REPLY_MS to be taken in whole is said on the log (slowly).
const SLOW_REPLY_BYTES = 256 * 1024;
const SLOW_REPLY_MS = 5_000;
/// Headers of one hop, not of what is relayed.
const HOP = ["connection", "keep-alive", "proxy-connection", "transfer-encoding", "upgrade", "te", "trailer", "host", "content-length"];

/// One JSON line at a time from a stream, then the rest of it.
export class Reader {
  carry: Buffer = Buffer.alloc(0);
  stream: Stream;
  /// How long a line may be: the admin API's heads are small; the device tools' carry their bodies in it.
  private maxLine: number;
  constructor(stream: Stream, maxLine = MAX_HEAD) {
    this.stream = stream;
    this.maxLine = maxLine;
  }

  async line(): Promise<any | null> {
    // A long line (the device tools') comes in many pieces: kept as they come, each looked through once.
    let at = this.carry.indexOf(10);
    if (at < 0) {
      const parts = [this.carry];
      let size = this.carry.length;
      while (at < 0) {
        if (size > this.maxLine) throw new Error("head too large");
        const more = await this.stream.read();
        if (more === null) {
          if (size === 0) return null;
          throw new Error("stream ended mid-line");
        }
        const found = more.indexOf(10);
        if (found >= 0) at = size + found;
        parts.push(more);
        size += more.length;
      }
      this.carry = Buffer.concat(parts, size);
    }
    if (at > this.maxLine) throw new Error("head too large");
    const line = this.carry.subarray(0, at);
    this.carry = this.carry.subarray(at + 1);
    return JSON.parse(line.toString());
  }

  async rest(): Promise<Buffer> {
    const parts = [this.carry];
    let size = this.carry.length;
    for (let more = await this.stream.read(); more; more = await this.stream.read()) {
      parts.push(more);
      size += more.length;
      if (size > MAX_BODY) throw new Error("request body too large");
    }
    return Buffer.concat(parts);
  }

  /// The rest as it comes, however long (a request passed on as it is: a module's).
  async *chunks(): AsyncGenerator<Buffer> {
    if (this.carry.length > 0) {
      const first = this.carry;
      this.carry = Buffer.alloc(0);
      yield first;
    }
    for (let more = await this.stream.read(); more; more = await this.stream.read()) yield more;
  }
}

export const writeLine = (stream: Stream, value: unknown) => stream.write(Buffer.from(JSON.stringify(value) + "\n"));

/// A hello's `lock: {device, proof}`: the device's base key, and its signature saying this endpoint is its own.
function lockProof(v: any): { base: string; proof: string } | undefined {
  return typeof v?.device === "string" && typeof v?.proof === "string" && v.device.length === 64 && v.proof.length === 128 ? { base: v.device, proof: v.proof } : undefined;
}

/// How many entries a hello may bring (they come in its first line, MAX_HEAD at most).
const BROUGHT_MOST = 64;

/// The entries a device brings with its hello (`lock.entries`, docs/workspace-lock.md): what put it in the lock, which
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
  const state = cloud.locked(ws)?.state;
  if (!state) return false;
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
export function refusalOf(cloud: Cloud, hello: any, device: string, e: unknown, accepted?: Accepted): Record<string, unknown> {
  if (e instanceof LockRefusal) return { error: e.message, code: e.code, lock: lockHead(cloud, joinedOf(cloud, claimed(hello))) };
  const left = leftOutFor(cloud, hello, device, accepted);
  if (left !== null) return { error: LEFT_OUT[left], code: "lock_station", why: left };
  return { error: (e as Error).message };
}

/// The workspace a hello's credential names, as it says (checked by verifyMember: only to say which lock refused it).
function claimed(hello: any): string {
  try {
    const ws = JSON.parse(Buffer.from(String(hello?.credential ?? "").split(".")[1] ?? "", "base64url").toString())?.ws;
    return typeof ws === "string" ? ws : "";
  } catch {
    return "";
  }
}

/// How far this station's lock goes in `ws` (the home workspace when null), for the device to bring it what it has
/// more (null: no lock pinned there).
export function lockHead(cloud: Cloud, ws: string | null = null): { seq: number; hash: string; genesis: string } | null {
  const s = cloud.locked(ws)?.state;
  return s ? { seq: s.seq, hash: s.head, genesis: s.genesis } : null;
}

/// GET /lock?after=<seq>: how far this station's lock goes and its entries after `after` (any member). POST /lock
/// {entries}: more of the pinned lock, checked entry by entry; or, unpinned, a lock to pin, from its genesis: brought by
/// its owner, on a device the genesis names (until then the control plane's word is what this station goes by, and the
/// owner it names is who may turn the lock on).
/// The lock is the asker's workspace's (each workspace the station is in has its own, docs/multi-workspace.md).
export function lockRoute(cloud: Cloud, method: string, query: [string, string][], body: Buffer, viewer: Admitted["viewer"]): [number, unknown] {
  const ws = viewer.workspace && viewer.workspace !== cloud.home() ? viewer.workspace : null;
  if (method === "GET") {
    const after = Number(query.find(([k]) => k === "after")?.[1] ?? -1);
    return [200, { head: lockHead(cloud, ws), entries: cloud.lockAfter(Number.isSafeInteger(after) ? after : -1, ws) }];
  }
  if (method !== "POST") return [405, { error: "GET or POST" }];
  let entries: (Entry | null)[];
  try {
    const raw = JSON.parse(body.toString("utf8") || "{}")?.entries;
    entries = Array.isArray(raw) ? raw.map(asEntry) : [];
  } catch {
    return [400, { error: "invalid JSON" }];
  }
  if (entries.length === 0 || entries.some((e) => e === null)) return [400, { error: "entries: lock entries" }];
  try {
    if (cloud.locked(ws) === null) {
      if (viewer.role !== "owner") return [403, { error: "only the workspace's owner turns its lock on" }];
      const first = genesis(entries[0]!);
      admit(first, { sub: viewer.sub, endpoint: viewer.device, base: viewer.lockDevice?.base, proof: viewer.lockDevice?.proof }, nowSecs());
      if (first.members.get(viewer.sub)?.role !== "owner") return [403, { error: "the lock is brought by its owner" }];
    }
    const taken = cloud.takeLock(entries as Entry[], ws);
    return [200, { taken, head: lockHead(cloud, ws) }];
  } catch (e) {
    return [409, { error: (e as Error).message, head: lockHead(cloud, ws) }];
  }
}

/// With a lock pinned: the member admitted only on a device the lock names, with the lower of the lock's role and the
/// credential's (`named`). Without one, as the credential says. Throws a LockRefusal why not.
export function inLock(cloud: Cloud, admitted: Admitted, named: string, endpoint: string): Admitted {
  // The lock of the workspace the member is in.
  const ws = admitted.viewer.workspace && admitted.viewer.workspace !== cloud.home() ? admitted.viewer.workspace : null;
  const locked = cloud.locked(ws);
  if (locked === null) return { ...admitted, viewer: { ...admitted.viewer, role: named } };
  if (locked.state === null) throw new LockRefusal("this station's workspace lock is broken; run `stillfail lock reset` on it");
  const v = admitted.viewer;
  const { role } = admit(locked.state, { sub: v.sub, endpoint, base: v.lockDevice?.base, proof: v.lockDevice?.proof }, nowSecs());
  return { ...admitted, viewer: { ...v, role: lowerRole(role, named) } };
}

/// inLock, for a hello that may bring what put the device in the lock (`lock.entries`): not in the lock as this station
/// has it, the entries it brought are taken (checked as any) and it is asked again.
export function inLockBringing(cloud: Cloud, admitted: Admitted, named: string, endpoint: string, hello: unknown): Admitted {
  try {
    return inLock(cloud, admitted, named, endpoint);
  } catch (e) {
    if (!(e instanceof LockRefusal) || !brought(hello, cloud, admitted.viewer.workspace, admitted.viewer.lockDevice?.base)) throw e;
    return inLock(cloud, admitted, named, endpoint);
  }
}

export type Members = {
  cloud: Cloud;
  admin: Admin;
  /// Whether the station answers now (its parts started; not handing over).
  up(): boolean;
  /// The part that answers a kind of request on a member's link itself (parts.ts `streams`: a phone lent over it).
  streams?: (head: any) => ((ask: MemberAsk) => Promise<void>) | undefined;
  /// The screens members see and drive (docs/remote-screens.md); none: no view is answered.
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

/// One member's connection: the credential first, nothing served before it checks out; then a request a stream.
export async function serve(m: Members, conn: Connection) {
  if (m.cloud.removed()) {
    conn.close(2, "station_removed");
    throw new Error("station removed");
  }
  const device = conn.remoteId();
  const first = await conn.acceptBi();
  if (!first) return;
  const credentials = new Reader(first);
  const state = () => m.cloud.state!;
  const hello = await credentials.line();
  if (hello === null) throw new Error("no credential");
  // Which device this is in the workspace's lock: its base key's proof for this endpoint, said once (cloud/lock.ts).
  const proof = lockProof(hello?.lock);
  // The role the credential names: the control plane's word, which the lock may lower but not raise.
  let named = "";
  const check = (line: any) => {
    // Of any workspace the station is in: the viewer's is the one its requests are answered for.
    const admitted = verifyMemberOf(typeof line?.credential === "string" ? line.credential : "", (ws: string) => m.cloud.grantKeys(ws === m.cloud.home() ? null : ws), m.cloud.memberships(), device, m.accepted?.());
    named = admitted.viewer.role;
    if (proof) admitted.viewer.lockDevice = proof;
    return inLockBringing(m.cloud, admitted, named, device, line);
  };
  let current: Admitted;
  try {
    current = check(hello);
  } catch (e) {
    await writeLine(first, refusalOf(m.cloud, hello, device, e, m.accepted?.())).catch(() => {});
    await first.finish().catch(() => {});
    wall.after(200, () => conn.close(1, e instanceof LockRefusal ? "lock_unconfirmed" : "credential_refused"));
    throw e;
  }
  // How far its lock goes, when it has one (a device that has more brings it, docs/workspace-lock.md).
  const head = lockHead(m.cloud, joinedOf(m.cloud, current.viewer.workspace));
  const lan = m.lan?.() ?? [];
  const tailnet = m.tailnet?.() ?? [];
  await writeLine(first, { ok: true, station: m.cloud.membership(current.viewer.workspace)?.name ?? state().name, expires_at: current.exp, ...(head ? { lock: head } : {}), ...(lan.length > 0 ? { lan } : {}), ...(tailnet.length > 0 ? { tailnet } : {}) });
  // The dial's trace (the device's `mesh.connect`), said on both lines of the connection so the device's record of it
  // and the station's are found together; and the way it came, then the ways it had when it ended (2026-10-30: a
  // phone's handshake with dev-prod went through and nothing came after, and nothing here said what the station saw).
  const trace = parseParent(typeof hello?.traceparent === "string" ? hello.traceparent : undefined)?.trace;
  const opened = wall.now();
  log.info("mesh", "client connected", { email: current.viewer.email, device: device.slice(0, 12), trace, via: conn.via() ?? "direct", ways: waysOf(conn) });
  m.connected?.();
  let lastWays = waysOf(conn);
  void conn.closed().then((why) => {
    const ways = waysOf(conn);
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
        current = inLock(m.cloud, current, named, device);
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
  watchExpiry();
  const unlisten = m.cloud.listen(gone);
  // Renewals on the credential stream.
  (async () => {
    for (let line = await credentials.line().catch(() => null); line !== null; line = await credentials.line().catch(() => null)) {
      let reply;
      try {
        current = check(line);
        watchExpiry();
        reply = { ok: true, expires_at: current.exp };
      } catch (e) {
        reply = { error: (e as Error).message };
      }
      await writeLine(first, reply).catch(() => {});
    }
  })();

  try {
    for (let stream = await conn.acceptBi(); stream; stream = await conn.acceptBi()) {
      if (gone()) return;
      lastWays = waysOf(conn);
      const viewer = { ...current.viewer, home: m.cloud.home() === current.viewer.workspace };
      request(m, stream, viewer, conn).catch((e) => log.info("mesh", "request failed", { error: (e as Error).message }));
    }
  } finally {
    expiry?.();
    unlisten();
  }
}

/// One request: to the admin API in this process.
async function request(m: Members, raw: Stream, viewer: Admitted["viewer"], conn: Connection) {
  const accepted = { wall: wall.now(), at: process.hrtime.bigint() };
  const firstReader = new Reader(raw);
  const head = await firstReader.line();
  if (head === null) return;
  const method: string = typeof head.method === "string" ? head.method.toUpperCase() : "GET";
  const path: string = typeof head.path === "string" ? head.path : "";
  // A span of the caller's trace when it records one: from the stream's acceptance to its answer's last byte (an
  // event stream's, a socket's, a screen's view or a phone's offer: to its head). The admin API's goes under ours.
  const traced = tracing(m.traces, head, method, path, conn.via(), accepted, raw, firstReader.carry.length);
  const stream = traced.stream;
  const reader = firstReader;
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
  // A module's request goes on to it as it comes (modules/forward.ts): a video uploaded is not held here whole, nor
  // bound by MAX_BODY.
  const streamed = isModulePath(path.slice("/admin/api".length));
  const body = streamed ? Buffer.alloc(0) : await reader.rest();
  // The caller's headers go on, but not those of the hop, nor any of the station's own: who is asking is only what
  // the credential says.
  const headers: Record<string, string> = {};
  for (const [name, value] of Object.entries(head.headers ?? {})) {
    const lower = name.toLowerCase();
    if (HOP.includes(lower) || lower.startsWith("x-stillfail-") || lower.startsWith("x-ember-") || lower === "traceparent" || lower === "tracestate") continue;
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
  const handled = await m.admin.handle({
    method,
    path: at < 0 ? rest : rest.slice(0, at),
    query: at < 0 ? [] : queryPairs(rest.slice(at + 1)),
    search: at < 0 ? "" : rest.slice(at),
    headers,
    body,
    ...(streamed ? { upload: reader.chunks() } : {}),
    viewer,
    lang: langOfCore(headers),
  });
  // Compressed, for a client that asks so (compress.ts).
  const sent = await compressed(handled, headers, rest);
  const ready = wall.now();
  await send(stream, sent);
  await stream.finish();
  if (Buffer.isBuffer(sent.body) && sent.body.length >= SLOW_REPLY_BYTES) slowly(stream, conn, method, rest, sent.body.length, ready - asked, ready);
}

/// A large reply's bytes, once the device has taken them all in (acknowledged): said on the log when that took over
/// SLOW_REPLY_MS, with how long it was made in (`made`) and the way it went (a relay or an address, its round trip, the
/// packets sent and lost on it, and how much the station may send on it unacknowledged now and how often that was cut
/// for loss), so a part of a video slow to come is seen here, the station's time apart from the way's. (Its stream told
/// nothing as it was acknowledged until 2026-10-28, which this took for the device having stopped it: nothing was ever
/// said, and a desktop app's images coming at 30 KB/s from ccvm for an hour left no word of how.) `ways` says every
/// way the connection has, `*` the chosen one, with the packets sent on each while the reply went: a connection has a
/// way through every relay (#2580), and with none chosen noq sends on all of them (2026-10-30: attachments at 11–50
/// KB/s on a way of 70 ms, `way=?` on half of them, the chosen way alone not saying where the bytes went).
function slowly(stream: Stream, conn: Connection, method: string, path: string, bytes: number, made: number, from: number) {
  const before = sentOn(conn);
  void stream.stopped().then((code) => {
    const ms = wall.now() - from;
    if (typeof code === "number" || ms < SLOW_REPLY_MS) return;
    const paths = conn.paths?.() ?? [];
    const way = paths.find((p) => p.selected);
    const after = sentOn(conn);
    const ways = paths.map((p, i) => {
      const [key, sent] = after[i]!;
      const was = before.find(([k]) => k === key)?.[1] ?? 0;
      return `${p.selected ? "*" : ""}${key} ${Math.round(p.rttMs)}ms +${sent - was}/${p.lostPackets} cwnd=${p.cwnd ?? "?"}`;
    });
    log.info("mesh", "a reply went slowly", {
      route: `${method} ${route(path.split("?")[0] ?? path)}`,
      bytes,
      made,
      ms,
      bytesPerSecond: Math.round((bytes / ms) * 1000),
      device: conn.remoteId(),
      way: way ? (way.relay ?? way.ip ?? "?") : "?",
      rtt: way ? Math.round(way.rttMs) : null,
      sent: way?.txPackets ?? null,
      lost: way?.lostPackets ?? null,
      cwnd: way?.cwnd ?? null,
      cuts: way?.congestionEvents ?? null,
      ways: ways.join(", "),
    });
  }, () => {});
}

/// Every way a connection has now, as a reply that went slowly says them: `*` the chosen one, its relay or address, round
/// trip, packets sent and lost.
function waysOf(conn: Connection): string {
  return (conn.paths?.() ?? []).map((p) => `${p.selected ? "*" : ""}${p.relay ?? p.ip ?? "?"} ${Math.round(p.rttMs)}ms ${p.txPackets}/${p.lostPackets}`).join(", ");
}

/// The packets sent so far on each of a connection's ways, by a key unique among them (its relay or address, `#n` for
/// its n-th way there).
function sentOn(conn: Connection): [string, number][] {
  const seen = new Map<string, number>();
  return (conn.paths?.() ?? []).map((p) => {
    const at = p.relay ?? p.ip ?? "?";
    const n = seen.get(at) ?? 0;
    seen.set(at, n + 1);
    return [n ? `${at}#${n}` : at, p.txPackets];
  });
}

/// An answer onto its stream: its head line, then its body. A body that is a stream (GET /events) ends when the caller
/// stops reading or goes, even while nothing is being written to it, and is let go of however the writing ends: one
/// whose head could not be written (the caller gone while its answer was being made) stayed a follower of the events
/// for good, told everything into a queue nobody read. A whole body says its length, unless compressed (compress.ts: a
/// client counts what it has read once decompressed): a chat's picture shows how far it has come by it
/// (pengxiao, 2026-10-28: without it, one under the core's step for an unknown length showed 0 B until it was here).
export async function send(stream: Stream, response: Answer) {
  const head = { status: response.status, headers: response.headers };
  if (Buffer.isBuffer(response.body)) {
    const said = Object.keys(response.headers).some((k) => ["content-length", "content-encoding"].includes(k.toLowerCase()));
    if (!said) head.headers = { ...response.headers, "content-length": String(response.body.length) };
    await writeLine(stream, head);
    await stream.write(response.body);
    return;
  }
  const chunks = response.body[Symbol.asyncIterator]();
  const end = () => void chunks.return?.();
  stream.stopped().then(end, end);
  try {
    await writeLine(stream, head);
    for (;;) {
      const next = await chunks.next();
      if (next.done) break;
      await stream.write(next.value);
    }
  } finally {
    end();
  }
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
