// The workspace's stations calling each other (the Rust station's peer.rs): their own ALPN, and the peer's iroh key for
// who it is, not a member's credential. Who belongs is only what still.fail cloud's presence socket said last
// (`peers`, current while the socket holds): until a fresh roster comes, calls fail closed. One request a stream: a
// JSON `{workspace, request}` the caller finishes, a JSON `{result}` or `{error}` back.
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import type { Cloud } from "../cloud/state.ts";
import { type PeerBus, type PeerCall, Refused } from "./bus.ts";
import type { Addr, Connection, Endpoint, Stream } from "./native.ts";
import { answerLock } from "./lock-sync.ts";

export const PEER_ALPN = Buffer.from("stillfail/station/1");
const MAX_MESSAGE = 1024 * 1024;

/// The workspace a peer is asked or heard in, if it is another station of it now; throws why not. Without one said,
/// the first workspace of this station's (its home one first) the peer is in too.
export function member(cloud: Cloud, peer: string, workspace: string | null): string {
  if (!cloud.peersCurrent) throw new Error("workspace peer roster is not current; waiting for the control plane");
  const s = cloud.state;
  const all = cloud.memberships();
  const of = workspace === null ? (all.find((m) => m.peers.some((p) => p?.id === peer)) ?? all[0]) : cloud.membership(workspace);
  if (s === null || of === undefined || of === null) throw new Error("station is outside this workspace");
  if (!of.peers.some((p) => p?.id === peer) || peer === s.station) throw new Error("peer is not another station in this workspace");
  return of.workspace;
}

/// All of a stream, at most `limit` bytes.
async function readAll(stream: Stream, limit: number): Promise<Buffer> {
  const parts: Buffer[] = [];
  let size = 0;
  for (let more = await stream.read(); more; more = await stream.read()) {
    size += more.length;
    if (size > limit) throw new Error("peer message too large");
    parts.push(more);
  }
  return Buffer.concat(parts);
}

const within = wall.within;

/// Stations of other workspaces this one shares chats with (xshare/index.ts): whether it may ask one.
export type Outside = { reaches(target: string, workspace: string): boolean };

/// The workspace a request to `target` goes to: this one's, when it is one of its stations; another, when it is a
/// station this one shares chats with (`outside`). Throws why not otherwise.
function workspaceFor(cloud: Cloud, target: string, workspace: string | null, outside: Outside | undefined): string {
  if (workspace === null || cloud.membership(workspace) !== null || outside === undefined) return member(cloud, target, workspace);
  if (cloud.home() === null) throw new Error("station is outside this workspace");
  if (!outside.reaches(target, workspace)) throw new Error("that station is of another workspace that shares no chat with this one");
  return workspace;
}

/// How this station asks the others: a connection kept per peer, dropped when a call fails other than by refusal.
/// `addr`: where a peer is (its id and still.fail's relays, found by them; tests give its sockets).
export function peerCall(endpoint: Endpoint, cloud: Cloud, addr: (id: string) => Addr = (id) => ({ id, relays: cloud.relays() }), outside?: Outside): PeerCall {
  const connections = new Map<string, Connection>();
  return async (target, workspace, request) => {
    if (target === "" && request?.method === "peers") {
      const of = workspace === null ? (cloud.memberships()[0] ?? null) : cloud.membership(workspace);
      return { workspace: of?.workspace ?? "", stations: of?.peers ?? [], current: cloud.peersCurrent };
    }
    const ws = workspaceFor(cloud, target, workspace, outside);
    // Requests are bounded and retriable by their task key: a timeout is never "not run" (ask again by the key).
    const call = async () => {
      let conn = connections.get(target);
      if (conn === undefined || conn.isClosed()) {
        try {
          conn = await endpoint.connect(addr(target), PEER_ALPN);
        } catch (error) {
          throw new Error(`peer unavailable or does not support station RPC: ${(error as Error).message}`);
        }
        connections.set(target, conn);
      }
      const stream = await conn.openBi();
      const bytes = Buffer.from(JSON.stringify({ workspace: ws, request }));
      if (bytes.length > MAX_MESSAGE) throw new Error("peer request too large");
      await stream.write(bytes);
      await stream.finish();
      const answer = JSON.parse((await readAll(stream, MAX_MESSAGE)).toString("utf8"));
      if (typeof answer?.error === "string") throw new Refused(answer.error);
      return answer?.result ?? null;
    };
    try {
      return await within(30_000, call(), "peer request timed out; execution may have happened — query the same task key");
    } catch (error) {
      if (!(error instanceof Refused)) connections.delete(target);
      throw error;
    }
  };
}

/// Another station's connection: each of its requests answered by the remote tasks, while it belongs.
/// A station of another workspace is heard too while chats are shared across workspaces (`remote.hearsOutside`): each
/// of its requests must name this workspace, and only what is shared with its own is answered (xshare/index.ts). One
/// that shares a workspace with this station but asks in another of this station's is heard as such a station there.
/// Which of the two it is, is looked at for each request, as the roster is then: a connection made while the roster
/// was not current yet (this station just started) was taken for an outsider's for its whole life, every request of
/// the workspace's own stations refused as sharing no chat until it idled out (2026-10-17). While the roster is not
/// current a request is refused as that, and the caller asks again.
export async function servePeer(conn: Connection, cloud: Cloud, remote: Pick<PeerBus, "handle" | "handleOutside" | "hearsOutside">) {
  const peer = conn.remoteId();
  const outsider = (error: unknown) =>
    cloud.peersCurrent && remote.hearsOutside?.() === true && cloud.state !== null && cloud.home() !== null && peer !== cloud.state.station ? false : error;
  /// Whether it is one of this station's workspaces' stations now; throws why not when it may not be heard at all.
  const inside = () => {
    try {
      member(cloud, peer, null);
      return true;
    } catch (error) {
      const why = outsider(error);
      if (why !== false) throw why;
      return false;
    }
  };
  // Not to be heard at all: the connection ends. A roster not current yet ends nothing: its requests are refused meanwhile.
  try {
    inside();
  } catch (error) {
    if (cloud.peersCurrent) throw error;
  }
  // Each request answered on its own, as it comes: answered one after another, a slow one (a sync while the station
  // was loaded) held up every other one of the caller's, whose chats all share the connection; each timed out at 30 s,
  // the caller dialed again and its next requests queued behind the same, while those left on the old connection were
  // still run (2026-10-20, ccvm to Studio for hours after Studio's load came down). Idle only with none being answered.
  // The stream being waited for stays the one waited for past each minute: one asked for again would be lost to it.
  let answering = 0;
  let next: Promise<Stream | null> | null = null;
  for (;;) {
    next ??= conn.acceptBi();
    let stream: Stream | null;
    try {
      stream = await within(60_000, next, "peer idle");
    } catch (error) {
      if (answering > 0) continue;
      throw error;
    }
    next = null;
    if (stream === null) return;
    answering++;
    void answerStream(stream).finally(() => answering--);
  }

  async function answerStream(stream: Stream) {
    let answer: unknown;
    try {
      const envelope = JSON.parse((await within(15_000, readAll(stream, MAX_MESSAGE), "peer request timed out")).toString("utf8"));
      if (typeof envelope?.workspace !== "string") throw new Error("workspace missing");
      const ours = inside();
      const there = ours && cloud.membership(envelope.workspace)?.peers.some((p) => p?.id === peer) === true;
      if (there || (ours && !remote.hearsOutside?.())) {
        member(cloud, peer, envelope.workspace);
        const method = envelope.request?.method;
        answer = { result: typeof method === "string" && method.startsWith("lock.") ? answerLock(cloud, envelope.request, envelope.workspace) : await remote.handle(envelope.workspace, peer, envelope.request ?? null) };
      } else {
        if (cloud.membership(envelope.workspace) === null) throw new Error("station is outside this workspace");
        answer = { result: await remote.handleOutside(peer, envelope.request ?? null, envelope.workspace) };
      }
    } catch (error) {
      answer = { error: (error as Error).message };
    }
    try {
      await stream.write(Buffer.from(JSON.stringify(answer)));
      await stream.finish();
    } catch (error) {
      // The caller gone (it gave up, the connection closed): nobody to answer.
      log.info("mesh", "peer answer not sent", { error: (error as Error).message });
      return;
    }
    void within(10_000, stream.stopped(), "").catch(() => {});
  }
}
