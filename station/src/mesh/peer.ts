// The workspace's stations calling each other (the Rust station's peer.rs): their own ALPN, and the peer's iroh key for
// who it is, not a member's credential. Who belongs is only what still.fail cloud's presence socket said last
// (`peers`, current while the socket holds): until a fresh roster comes, calls fail closed. One request a stream: a
// JSON `{workspace, request}` the caller finishes, a JSON `{result}` or `{error}` back.
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import type { Cloud } from "../cloud/state.ts";
import { type PeerCall, Refused, type Remote } from "../jobs/remote.ts";
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
export async function servePeer(conn: Connection, cloud: Cloud, remote: Remote) {
  const peer = conn.remoteId();
  let inside = true;
  try {
    member(cloud, peer, null);
  } catch (error) {
    if (!remote.hearsOutside?.() || !cloud.state || cloud.home() === null || peer === cloud.state.station) throw error;
    inside = false;
  }
  for (;;) {
    const stream = await within(60_000, conn.acceptBi(), "peer idle");
    if (stream === null) return;
    let answer: unknown;
    try {
      const envelope = JSON.parse((await within(15_000, readAll(stream, MAX_MESSAGE), "peer request timed out")).toString("utf8"));
      if (typeof envelope?.workspace !== "string") throw new Error("workspace missing");
      const there = inside && cloud.membership(envelope.workspace)?.peers.some((p) => p?.id === peer) === true;
      if (there || (inside && !remote.hearsOutside?.())) {
        member(cloud, peer, envelope.workspace);
        const method = envelope.request?.method;
        answer = { result: typeof method === "string" && method.startsWith("lock.") ? answerLock(cloud, envelope.request) : await remote.handle(envelope.workspace, peer, envelope.request ?? null) };
      } else {
        if (cloud.membership(envelope.workspace) === null) throw new Error("station is outside this workspace");
        answer = { result: await remote.handleOutside(peer, envelope.request ?? null, envelope.workspace) };
      }
    } catch (error) {
      answer = { error: (error as Error).message };
    }
    await stream.write(Buffer.from(JSON.stringify(answer)));
    await stream.finish();
    void within(10_000, stream.stopped(), "").catch(() => {});
  }
}

/// Tasks of peers no longer in the workspace, or no longer allowed, stop: looked at whenever the roster or the config
/// changes.
export function followRoster(cloud: Cloud, remote: Remote, config: { listen(f: () => void): () => void }): () => void {
  const look = () => {
    const rosters = cloud.memberships().map((m) => ({ workspace: m.workspace, peers: m.peers.flatMap((p) => (typeof p?.id === "string" ? [p.id as string] : [])) }));
    void remote
      .revoke(rosters, cloud.peersCurrent)
      .catch((error) => log.warn("peer", "revoking tasks failed", { error: (error as Error).message }));
  };
  look();
  const unlisten = cloud.listen(look);
  const unconfig = config.listen(look);
  return () => (unlisten(), unconfig());
}
