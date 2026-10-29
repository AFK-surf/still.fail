// The workspace's stations calling each other (the Rust station's peer.rs): their own ALPN, and the peer's iroh key for
// who it is, not a member's credential. Who belongs is only what still.fail cloud's presence socket said last
// (`peers`, current while the socket holds): until a fresh roster comes, calls fail closed. One request a stream. On
// `stillfail/station/2`: a JSON head line `{workspace, request, bytes?}` and, with `bytes: true`, the request's bytes
// until the stream finishes; answered by a JSON head line `{result, bytes?}` or `{error}` and, with `bytes: true`, the
// answer's bytes (a file, as it is read). On `stillfail/station/1` (stations from before 2026-10-29): a JSON
// `{workspace, request}` the caller finishes, a JSON `{result}` or `{error}` back, and nothing else: files went in
// chunks of base64 inside it, one request each.
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import type { Cloud } from "../cloud/state.ts";
import { BYTES, type Bytes, NoBytes, type PeerBus, type PeerCall, Refused, bytesOf } from "./bus.ts";
import type { Addr, Connection, Endpoint, Stream } from "./native.ts";
import { answerLock } from "./lock-sync.ts";
import { Reader } from "./serve.ts";

export const PEER_ALPN = Buffer.from("stillfail/station/1");
/// The station transport with bytes after a head: offered first, and listed before `/1` by a station, which picks by its
/// own order; one from before answers in `/1`.
export const PEER_BYTES_ALPN = Buffer.from("stillfail/station/2");
/// A head at most (on `/1`: a whole request or answer).
const MAX_MESSAGE = 1024 * 1024;
/// How long bytes may not move on before their stream is given up: the other end gone, or not taking them.
const IDLE_MS = 30_000;
/// The codes a stream is reset with: its reader stopped reading what was left; its bytes failed on the way.
const STOPPED = 1;
const FAILED = 2;
/// A request answered later than this is said in the log (a caller gives up at 30 s).
const SLOW_MS = 10_000;

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

/// What follows a head on `reader`'s stream, as it comes, each piece within IDLE_MS: to its end, or until its reader
/// stops (`return`, as a `for await` left early does) or it fails, when the stream is reset so its sender stops too.
class Incoming implements AsyncIterableIterator<Buffer> {
  /// All of it came.
  ended = false;
  #over = false;
  readonly #reader: Reader;
  constructor(reader: Reader) {
    this.#reader = reader;
  }
  [Symbol.asyncIterator]() {
    return this;
  }
  async next(): Promise<IteratorResult<Buffer>> {
    if (this.#over) return { done: true, value: undefined };
    const reader = this.#reader;
    if (reader.carry.length > 0) {
      const first = reader.carry;
      reader.carry = Buffer.alloc(0);
      return { done: false, value: first };
    }
    let more: Buffer | null;
    try {
      more = await within(IDLE_MS, reader.stream.read(), "the other station sent nothing for 30 s");
    } catch (error) {
      await this.return();
      throw error;
    }
    if (more === null) {
      this.ended = this.#over = true;
      return { done: true, value: undefined };
    }
    return { done: false, value: more };
  }
  async return(): Promise<IteratorResult<Buffer>> {
    if (!this.#over) {
      this.#over = true;
      await this.#reader.stream.reset(STOPPED).catch(() => {});
    }
    return { done: true, value: undefined };
  }
}

/// `bytes` written to `stream` as they come, each piece taken within IDLE_MS, and the stream finished; reset when they
/// fail on the way (a file that changed while it was read, the other end gone).
async function sendBytes(stream: Stream, bytes: Bytes): Promise<void> {
  try {
    for await (const piece of bytes) await within(IDLE_MS, stream.write(piece), "the other station took nothing for 30 s");
    await stream.finish();
  } catch (error) {
    await stream.reset(FAILED).catch(() => {});
    throw error;
  }
}

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

/// How long a request's answer is waited for.
const ANSWER_MS = 30_000;
/// A connection whose request was not answered in time is kept when its peer is heard within this (the answer is
/// late, the connection fine), closed when not.
const HEARD_MS = 3_000;

/// How this station asks the others: one connection kept per peer, dialed once however many requests wait for it, and
/// let go when it fails or its peer is no longer heard. `addr`: where a peer is (its id and still.fail's relays, found
/// by them; tests give its sockets). `answerMs`: how long an answer is waited for (tests shorten it).
export function peerCall(
  endpoint: Endpoint, cloud: Cloud, addr: (id: string) => Addr = (id) => ({ id, relays: cloud.relays() }), outside?: Outside, answerMs = ANSWER_MS,
): PeerCall {
  const connections = new Map<string, Connection>();
  // Each request dialed its own while none was open, and one that timed out dropped its connection for the next to
  // dial another, the old one left open with its requests still run: a station following dozens of tasks on a loaded
  // one dialed dozens at once, again after each timeout, and the loaded one answered all of them (2026-10-21, ccvm to
  // Studio).
  const dialing = new Map<string, Promise<Connection>>();
  const connected = (target: string): Promise<Connection> => {
    const open = connections.get(target);
    if (open !== undefined && !open.isClosed()) return Promise.resolve(open);
    let dial = dialing.get(target);
    if (dial === undefined) {
      dial = endpoint.connect(addr(target), PEER_BYTES_ALPN, [PEER_ALPN]).then(
        (conn) => {
          connections.set(target, conn);
          return conn;
        },
        (error) => {
          throw new Error(`peer unavailable or does not support station RPC: ${(error as Error).message}`);
        },
      );
      const settled = () => {
        if (dialing.get(target) === dial) dialing.delete(target);
      };
      dial.then(settled, settled);
      dialing.set(target, dial);
    }
    return dial;
  };
  /// After a request failed on `conn`: closed, or its peer not heard, it goes (the next request dials again).
  const letGo = async (target: string, conn: Connection) => {
    if (connections.get(target) !== conn) return;
    const heard = !conn.isClosed() && conn.answers !== undefined && (await conn.answers(HEARD_MS).catch(() => false));
    if (heard || connections.get(target) !== conn) return;
    connections.delete(target);
    conn.close(0, "not answering");
  };
  return async (target, workspace, request) => {
    if (target === "" && request?.method === "peers") {
      const of = workspace === null ? (cloud.memberships()[0] ?? null) : cloud.membership(workspace);
      return { workspace: of?.workspace ?? "", stations: of?.peers ?? [], current: cloud.peersCurrent };
    }
    const ws = workspaceFor(cloud, target, workspace, outside);
    let conn: Connection | null = null;
    let dial: Promise<Connection> | null = null;
    const late = "peer request timed out; execution may have happened — query the same task key";
    // What goes after the request (a file): sent as the other end takes it, however long that is; the answer is
    // waited for answerMs once they all went.
    const body = bytesOf(request);
    // Requests are bounded and retriable by their task key: a timeout is never "not run" (ask again by the key).
    const call = async () => {
      dial = connected(target);
      conn = body === null ? await dial : await within(answerMs, dial, late);
      if (!conn.alpn().equals(PEER_BYTES_ALPN)) {
        if (body !== null) throw new NoBytes("that station takes files only in chunks (it is not updated yet)");
        const stream = await conn.openBi();
        const bytes = Buffer.from(JSON.stringify({ workspace: ws, request }));
        if (bytes.length > MAX_MESSAGE) throw new Error("peer request too large");
        await stream.write(bytes);
        await stream.finish();
        const answer = JSON.parse((await readAll(stream, MAX_MESSAGE)).toString("utf8"));
        if (typeof answer?.error === "string") throw new Refused(answer.error);
        return answer?.result ?? null;
      }
      const stream = await conn.openBi();
      const head = Buffer.from(JSON.stringify({ workspace: ws, request, ...(body === null ? {} : { bytes: true }) }) + "\n");
      if (head.length > MAX_MESSAGE) throw new Error("peer request too large");
      const reader = new Reader(stream, MAX_MESSAGE);
      let answer: any;
      if (body === null) {
        await stream.write(head);
        await stream.finish();
        answer = await reader.line();
      } else {
        await within(IDLE_MS, stream.write(head), late);
        // A refusal can come before they all went (the other end read none of them): the rest is not sent.
        const answered = reader.line();
        answered.catch(() => {});
        let sent = false;
        const sending = sendBytes(stream, body).then(() => void (sent = true));
        await Promise.race([sending, answered]);
        answer = await within(answerMs, answered, late);
        if (!sent) {
          await stream.reset(STOPPED).catch(() => {});
          sending.catch(() => {});
        }
      }
      if (answer === null) throw new Error("the other station answered nothing");
      if (typeof answer?.error === "string") throw new Refused(answer.error);
      const result = answer?.result ?? null;
      if (answer?.bytes !== true) return result;
      if (result === null || typeof result !== "object") throw new Error("bytes after an answer that is no object");
      return Object.assign(result, { [BYTES]: new Incoming(reader) });
    };
    try {
      return await (body === null ? within(answerMs, call(), late) : call());
    } catch (error) {
      // Set inside `call` (which TypeScript does not follow).
      const failed = conn as Connection | null;
      const dialed = dial as Promise<Connection> | null;
      if (!(error instanceof Refused) && !(error instanceof NoBytes) && failed !== null) void letGo(target, failed);
      // Not connected in time: the next request dials again rather than wait on this dial.
      if (failed === null && dialed !== null && dialing.get(target) === dialed) dialing.delete(target);
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
    const bytes = conn.alpn().equals(PEER_BYTES_ALPN);
    const reader = new Reader(stream, MAX_MESSAGE);
    let answer: { result?: unknown; error?: string; bytes?: true };
    let asked: unknown = null;
    // The request's bytes, and the answer's.
    let incoming: Incoming | null = null;
    let outgoing: Bytes | null = null;
    const begun = performance.now();
    try {
      const envelope = bytes
        ? await within(15_000, reader.line(), "peer request timed out")
        : JSON.parse((await within(15_000, readAll(stream, MAX_MESSAGE), "peer request timed out")).toString("utf8"));
      if (typeof envelope?.workspace !== "string") throw new Error("workspace missing");
      asked = envelope.request;
      // A file asked for whole (`whole`, bus.ts) on the transport of before: answered as then, a chunk.
      if (!bytes && envelope.request !== null && typeof envelope.request === "object") delete envelope.request.whole;
      if (bytes && envelope.bytes === true) {
        if (envelope.request === null || typeof envelope.request !== "object") throw new Error("bytes after a request that is no object");
        incoming = new Incoming(reader);
        envelope.request[BYTES] = incoming;
      }
      const ours = inside();
      const there = ours && cloud.membership(envelope.workspace)?.peers.some((p) => p?.id === peer) === true;
      let result: unknown;
      if (there || (ours && !remote.hearsOutside?.())) {
        member(cloud, peer, envelope.workspace);
        const method = envelope.request?.method;
        result = typeof method === "string" && method.startsWith("lock.") ? answerLock(cloud, envelope.request, envelope.workspace) : await remote.handle(envelope.workspace, peer, envelope.request ?? null);
      } else {
        if (cloud.membership(envelope.workspace) === null) throw new Error("station is outside this workspace");
        result = await remote.handleOutside(peer, envelope.request ?? null, envelope.workspace);
      }
      outgoing = bytesOf(result);
      if (outgoing !== null && !bytes) throw new Error("this answer has bytes the caller's transport cannot take");
      answer = outgoing === null ? { result } : { result, bytes: true };
    } catch (error) {
      answer = { error: (error as Error).message };
      outgoing = null;
    }
    // A request this slow has callers giving up at 30 s: said, so who held the station up is found (2026-10-20: nothing
    // in Studio's log said which of ccvm's requests took it twenty minutes).
    const ms = Math.round(performance.now() - begun);
    if (ms >= SLOW_MS) {
      const r = asked as { method?: unknown; session?: unknown; key?: unknown } | null;
      log.warn("mesh", "peer request answered slowly", { peer: peer.slice(0, 12), method: String(r?.method ?? ""), session: String(r?.session ?? ""), key: String(r?.key ?? ""), ms });
    }
    try {
      await stream.write(Buffer.from(JSON.stringify(answer) + (bytes ? "\n" : "")));
      if (outgoing !== null) await sendBytes(stream, outgoing);
      else await stream.finish();
    } catch (error) {
      // The caller gone (it gave up, the connection closed, it stopped reading), or the answer's bytes failed on the way.
      log.info("mesh", "peer answer not sent", { error: (error as Error).message });
      void incoming?.return();
      return;
    }
    // Bytes of the request not read (refused before): once the answer is through, the caller is stopped sending them.
    void within(10_000, stream.stopped(), "")
      .catch(() => {})
      .finally(() => void (incoming !== null && !incoming.ended && incoming.return()));
  }
}
