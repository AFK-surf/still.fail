// The workspace's stations calling each other (the Rust station's peer.rs): their own ALPN, and the peer's iroh key for
// who it is, not a member's credential. Who belongs is only what still.fail cloud's presence socket said last
// (`peers`, current while the socket holds): until a fresh roster comes, calls fail closed. One request a stream: a
// JSON `{workspace, request}` the caller finishes, a JSON `{result}` or `{error}` back.
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import type { Cloud } from "../cloud/state.ts";
import { type PeerCall, Refused, type Remote } from "../jobs/remote.ts";
import type { Addr, Connection, Endpoint, Stream } from "./native.ts";

export const PEER_ALPN = Buffer.from("stillfail/station/1");
const MAX_MESSAGE = 1024 * 1024;

/// The workspace a peer is asked or heard in, if it is another station of it now; throws why not.
export function member(cloud: Cloud, peer: string, workspace: string | null): string {
  if (!cloud.peersCurrent) throw new Error("workspace peer roster is not current; waiting for the control plane");
  const s = cloud.state;
  if (s === null || cloud.removed() || (workspace !== null && workspace !== s.workspace)) throw new Error("station is outside this workspace");
  if (!s.peers.some((p) => p?.id === peer) || peer === s.station) throw new Error("peer is not another station in this workspace");
  return s.workspace;
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

/// How this station asks the others: a connection kept per peer, dropped when a call fails other than by refusal.
/// `addr`: where a peer is (its id and still.fail's relays, found by them; tests give its sockets).
export function peerCall(endpoint: Endpoint, cloud: Cloud, addr: (id: string) => Addr = (id) => ({ id, relays: cloud.relays() })): PeerCall {
  const connections = new Map<string, Connection>();
  return async (target, workspace, request) => {
    if (target === "" && request?.method === "peers") {
      const s = cloud.state;
      return { workspace: s?.workspace ?? "", stations: s?.peers ?? [], current: cloud.peersCurrent };
    }
    const ws = member(cloud, target, workspace);
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
export async function servePeer(conn: Connection, cloud: Cloud, remote: Remote) {
  const peer = conn.remoteId();
  member(cloud, peer, null);
  for (;;) {
    const stream = await within(60_000, conn.acceptBi(), "peer idle");
    if (stream === null) return;
    let answer: unknown;
    try {
      const envelope = JSON.parse((await within(15_000, readAll(stream, MAX_MESSAGE), "peer request timed out")).toString("utf8"));
      if (typeof envelope?.workspace !== "string") throw new Error("workspace missing");
      member(cloud, peer, envelope.workspace);
      answer = { result: await remote.handle(envelope.workspace, peer, envelope.request ?? null) };
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
    const s = cloud.state;
    void remote
      .revoke(s?.workspace ?? "", (s?.peers ?? []).flatMap((p) => (typeof p?.id === "string" ? [p.id] : [])), cloud.peersCurrent)
      .catch((error) => log.warn("peer", "revoking tasks failed", { error: (error as Error).message }));
  };
  look();
  const unlisten = cloud.listen(look);
  const unconfig = config.listen(look);
  return () => (unlisten(), unconfig());
}
