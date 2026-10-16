// Programs on this machine reaching a web service on another station of the workspace as if it were here
// (docs/station-peers.md "Web services of other stations"): http://127.0.0.1:<agents' door>/peer/<station>/<port>/<path>
// is http://localhost:<port>/<path> there, its WebSockets too. No port is opened anywhere: the requests go over the mesh,
// on an ALPN of their own, admitted as the station transport admits (peer.ts `member`: the workspaces' rosters, failing
// closed while they are not current). One request a stream: a JSON head line `{workspace, port, method, path, headers,
// body}` and its body as it comes, answered with a JSON head line `{status, headers}` (headers as [name, value] pairs)
// and the service's body as it comes; a WebSocket's (`socket: true`) answered 101, then its messages framed both ways as
// a preview's are. The station there reaches its service as a preview's page does (jobs/preview.ts). A forwarded TCP
// connection's (`tcp: true`, peer-forward.ts) is answered 200 once the station there has connected to its localhost port,
// then its bytes go both ways as they are; with `probe: true` it is only said whether it would be taken.
import type { IncomingMessage, ServerResponse } from "node:http";
import type { Socket } from "node:net";
import { Readable, type Duplex } from "node:stream";
import { WebSocketServer } from "ws";
import type { Cloud } from "../cloud/state.ts";
import { FrameReader, ServiceSocket, SocketRefused, openSocket, proxyPreview, pumpSocket } from "../jobs/preview.ts";
import { wall } from "../ops/fibers.ts";
import { stationLang } from "../ops/i18n.ts";
import { log } from "../ops/log.ts";
import { ownPorts } from "../ops/own.ts";
import { type PeerRoute, type PeerTarget, refuseUpgrade } from "../tools/http.ts";
import type { Addr, Connection, Endpoint, Stream } from "./native.ts";
import { PEER_ALPN, member } from "./peer.ts";
import { pipeTcp, reachLocal } from "./peer-forward.ts";
import { Reader, writeLine } from "./serve.ts";

export const PEER_HTTP_ALPN = Buffer.from("stillfail/http/1");

/// A head line, at most (a service's cookies, a token).
const MAX_HEAD = 256 * 1024;
/// How long a station has to take a connection.
const CONNECT_MS = 20_000;
/// How long a request's head has to come once its stream is open.
const HEAD_MS = 15_000;
/// What a refused WebSocket's answer says, at most.
const MAX_REFUSAL = 64 * 1024;
/// Headers of the hop (and of the WebSocket handshake, which each side makes its own; an `Expect` the door answered
/// itself), not passed on.
const HOP = ["connection", "keep-alive", "proxy-connection", "transfer-encoding", "upgrade", "te", "trailer", "host", "expect", "sec-websocket-key", "sec-websocket-version", "sec-websocket-extensions", "sec-websocket-accept"];
const TIMED_OUT = "peer http: no connection in time";

/// Why a request was not passed on: its status and words; `unreachable` when the station itself was not reached (no
/// connection, or none in time), not refused by it.
export class HttpRefusal extends Error {
  readonly status: number;
  readonly unreachable: boolean;
  constructor(status: number, message: string, unreachable = false) {
    super(message);
    this.status = status;
    this.unreachable = unreachable;
  }
}

/// A forwarded TCP connection to a port on another station, taken there: its stream, with what came after the answer.
export type Tunnel = { stream: Stream; carry: Buffer };

/// [name, value] pairs, names lowercase, what is not one left out.
function pairs(raw: unknown): [string, string][] {
  if (!Array.isArray(raw)) return [];
  return raw.flatMap((p): [string, string][] => (Array.isArray(p) && typeof p[0] === "string" && typeof p[1] === "string" ? [[p[0].toLowerCase(), p[1]]] : []));
}

/// A request's headers to pass on: not the hop's, nor those its Connection header names.
function passed(raw: string[]): [string, string][] {
  const named = new Set<string>();
  for (let i = 0; i + 1 < raw.length; i += 2) {
    if (raw[i]!.toLowerCase() === "connection") for (const n of raw[i + 1]!.split(",")) named.add(n.trim().toLowerCase());
  }
  const out: [string, string][] = [];
  for (let i = 0; i + 1 < raw.length; i += 2) {
    const name = raw[i]!.toLowerCase();
    if (!HOP.includes(name) && !named.has(name)) out.push([name, raw[i + 1]!]);
  }
  return out;
}

/// Station `id`'s name in this station's workspaces, or its id when it has none.
export function nameOf(cloud: Cloud, id: string): string {
  const named = cloud.memberships().flatMap((m) => m.peers).find((p) => p?.id === id)?.name;
  return typeof named === "string" && named !== "" ? named : id;
}

/// The station a /peer URL names, by its id or its name (as cased anywhere) among the stations of the workspaces this
/// one is in, and the workspace it is asked in (its first one with this station, the home one first). The door knows no
/// chat, so it does not know whose workspace a request is for: a name more than one station has is refused (the id
/// tells them apart), as is this station itself.
export function peerNamed(cloud: Cloud, given: string): { id: string; workspace: string } {
  if (!cloud.peersCurrent) throw new HttpRefusal(503, "the workspace's stations are not known right now (still.fail cloud not reached); try again shortly");
  const all = cloud.memberships();
  const self = cloud.state?.station;
  const lower = given.toLowerCase();
  const stations = all.flatMap((m) => m.peers.filter((p) => typeof p?.id === "string"));
  let ids = [...new Set(stations.filter((p) => p.id === given).map((p) => p.id as string))];
  if (ids.length === 0) ids = [...new Set(stations.filter((p) => typeof p.name === "string" && p.name.toLowerCase() === lower).map((p) => p.id as string))];
  if (ids.length === 0 && (given === self || all.some((m) => m.name.toLowerCase() === lower))) ids = [self!];
  if (ids.length > 1) throw new HttpRefusal(409, `${given} names ${ids.length} stations (${ids.join(", ")}): give the id of the one meant`);
  if (ids.length === 0) {
    const names = [...new Set(stations.filter((p) => p.id !== self).map((p) => (typeof p.name === "string" && p.name !== "" ? p.name : p.id)))];
    throw new HttpRefusal(404, `no station ${given} in this station's workspaces${names.length > 0 ? `; its stations: ${names.join(", ")}` : ""}`);
  }
  if (ids[0] === self) throw new HttpRefusal(400, `${given} is this station: reach its services at http://localhost:<port>/ directly`);
  try {
    return { id: ids[0]!, workspace: member(cloud, ids[0]!, null) };
  } catch (error) {
    throw new HttpRefusal(403, (error as Error).message);
  }
}

/// Until `res` can take more, or is gone.
function drained(res: ServerResponse): Promise<void> {
  return new Promise((resolve) => {
    const done = () => {
      res.off("drain", done);
      res.off("close", done);
      resolve();
    };
    res.on("drain", done);
    res.on("close", done);
  });
}

function plain(res: ServerResponse, status: number, text: string) {
  res.writeHead(status, { "content-type": "text/plain; charset=utf-8" }).end(text);
}

/// The rest of a stream after its head line, as a body.
function rest(reader: Reader): Readable {
  return Readable.from(
    (async function* () {
      if (reader.carry.length > 0) yield reader.carry;
      for (let more = await reader.stream.read(); more !== null; more = await reader.stream.read()) yield more;
    })(),
    { objectMode: false },
  );
}

/// A request's body onto its stream as it comes (as fast as the stream takes it), then the stream's end. Should the other
/// side stop taking it (its service answered without reading it all), the rest is read and let go, so the program
/// asking still gets its whole answer.
async function upload(req: IncomingMessage, body: boolean, stream: Stream): Promise<void> {
  try {
    if (body) {
      await new Promise<void>((resolve, reject) => {
        const take = (chunk: Buffer) => {
          req.pause();
          stream.write(chunk).then(
            () => req.resume(),
            (error) => {
              req.off("data", take);
              req.resume();
              reject(error);
            },
          );
        };
        req.on("data", take);
        req.on("end", resolve);
        req.on("error", reject);
      });
    }
    await stream.finish();
  } catch {}
}

/// This station's way to the others' web services, for its agents' door: a connection kept per station (dropped when it
/// fails), a stream a request. `addr`: where a station is (its id and still.fail's relays; tests give its sockets).
export class PeerHttp implements PeerRoute {
  private connections = new Map<string, Promise<Connection>>();
  private endpoint: Endpoint;
  private cloud: Cloud;
  private addr: (id: string) => Addr;
  private connectMs: number;
  /// The upgrades answered here (the local program's side of a WebSocket), each with the sub-protocol the service chose.
  private sockets: WebSocketServer;
  private chosen = new WeakMap<IncomingMessage, string | null>();

  constructor(endpoint: Endpoint, cloud: Cloud, addr: (id: string) => Addr = (id) => ({ id, relays: cloud.relays() }), connectMs = CONNECT_MS) {
    this.endpoint = endpoint;
    this.cloud = cloud;
    this.addr = addr;
    this.connectMs = connectMs;
    this.sockets = new WebSocketServer({ noServer: true, perMessageDeflate: false, maxPayload: 16 * 1024 * 1024, handleProtocols: (_offered, req) => this.chosen.get(req) ?? false });
  }

  /// Its connections end (the mesh stops).
  close() {
    for (const made of this.connections.values()) made.then((c) => c.close(0, "station stopping"), () => {});
    this.connections.clear();
  }

  private forget(id: string, made: Promise<Connection>) {
    if (this.connections.get(id) === made) this.connections.delete(id);
  }

  /// A connection to station `id` (`given`: as the URL named it) speaking this protocol. A station from before it is told
  /// by the station transport's protocol, offered after this one: it takes that one instead.
  private async connect(id: string, given: string): Promise<Connection> {
    const connecting = this.endpoint.connect(this.addr(id), PEER_HTTP_ALPN, [PEER_ALPN]);
    let conn: Connection;
    try {
      conn = await wall.within(this.connectMs, connecting, TIMED_OUT);
    } catch (error) {
      if ((error as Error).message !== TIMED_OUT) throw new HttpRefusal(502, `station ${given} cannot be reached: ${(error as Error).message}`, true);
      connecting.then((late) => late.close(0, "too late"), () => {});
      throw new HttpRefusal(504, `station ${given} did not answer within ${Math.round(this.connectMs / 1000)} s: it is offline, or cannot be reached from here`, true);
    }
    if (!conn.alpn().equals(PEER_HTTP_ALPN)) {
      conn.close(0, "web requests unsupported");
      throw new HttpRefusal(502, `station ${given} is from before web requests between stations: it needs an update`);
    }
    return conn;
  }

  /// A new stream to station `id`: on the connection kept, or a new one when that one is gone.
  private async stream(id: string, given: string): Promise<Stream> {
    for (let attempt = 0; ; attempt++) {
      let made = this.connections.get(id);
      if (made === undefined) {
        const connecting = this.connect(id, given);
        made = connecting;
        this.connections.set(id, connecting);
        connecting.catch(() => this.forget(id, connecting));
      }
      const conn = await made;
      try {
        if (conn.isClosed()) throw new Error("connection lost");
        return await conn.openBi();
      } catch (error) {
        this.forget(id, made);
        if (attempt > 0) throw new HttpRefusal(502, `station ${given} cannot be reached: ${(error as Error).message}`, true);
      }
    }
  }

  /// A TCP connection to localhost:`port` on `station` (by its name or id, as /peer has it), for a forward
  /// (peer-forward.ts): once that station has connected to the port, the stream its bytes go on; else an HttpRefusal
  /// saying why. `probe`: only whether that station would take one (it knows forwards, the port is not one it refuses),
  /// nothing connected; resolves with no stream then.
  async tunnel(given: string, port: number, probe = false): Promise<Tunnel | null> {
    const peer = peerNamed(this.cloud, given);
    // Named in what it says by its name (a forward asks by the id).
    const station = nameOf(this.cloud, peer.id);
    const s = await this.stream(peer.id, station);
    try {
      await writeLine(s, { workspace: peer.workspace, port, tcp: true, ...(probe ? { probe: true } : {}) });
      if (probe) await s.finish();
      const reader = new Reader(s, MAX_HEAD);
      const answer = await reader.line();
      if (answer?.status !== 200) {
        let said = reader.carry;
        for (let more = await s.read(); more !== null && said.length < MAX_REFUSAL; more = await s.read()) said = Buffer.concat([said, more]);
        const status = Number.isInteger(answer?.status) ? answer.status : 502;
        throw new HttpRefusal(status, said.length > 0 ? said.subarray(0, MAX_REFUSAL).toString() : `station ${station} ended the connection without an answer`);
      }
      if (!probe) return { stream: s, carry: reader.carry };
      void s.reset(0).catch(() => {});
      return null;
    } catch (error) {
      void s.reset(0).catch(() => {});
      throw error;
    }
  }

  /// A request to the door's /peer: passed on to the service there, its answer back as it comes, both ways at once.
  async request(req: IncomingMessage, res: ServerResponse, target: PeerTarget): Promise<void> {
    let stream: Stream | null = null;
    try {
      const peer = peerNamed(this.cloud, target.station);
      const s = (stream = await this.stream(peer.id, target.station));
      const length = req.headers["content-length"];
      const body = length !== undefined ? length !== "0" : req.headers["transfer-encoding"] !== undefined;
      await writeLine(s, { workspace: peer.workspace, port: target.port, method: req.method ?? "GET", path: target.path, headers: passed(req.rawHeaders), body });
      // The caller gone before the whole answer: so is the request there.
      res.on("close", () => {
        if (!res.writableFinished) void s.reset(0).catch(() => {});
      });
      void upload(req, body, s);
      const reader = new Reader(s, MAX_HEAD);
      const head = await reader.line();
      if (head === null || !Number.isInteger(head.status)) throw new HttpRefusal(502, `station ${target.station} ended the request without an answer`);
      res.writeHead(head.status, this.answerHeaders(head.headers, target));
      // An event stream's head goes now, not with its first event.
      res.flushHeaders();
      if (reader.carry.length > 0 && !res.write(reader.carry)) await drained(res);
      for (let more = await s.read(); more !== null; more = await s.read()) {
        if (res.destroyed) return;
        if (!res.write(more)) await drained(res);
      }
      res.end();
    } catch (error) {
      if (stream !== null) void stream.reset(0).catch(() => {});
      if (res.headersSent) res.destroy();
      else if (error instanceof HttpRefusal) plain(res, error.status, error.message);
      else plain(res, 502, `station ${target.station}: ${(error as Error).message}`);
    }
  }

  /// The service's headers as the door gives them: flat, a redirect to the service itself kept under its /peer path.
  private answerHeaders(raw: unknown, target: PeerTarget): string[] {
    const out: string[] = [];
    for (const [name, value] of pairs(raw)) {
      if (HOP.includes(name)) continue;
      const kept = name === "location" && value.startsWith("/") && !value.startsWith("//") ? `/peer/${target.given}/${target.port}${value}` : value;
      out.push(name, kept);
    }
    return out;
  }

  /// A WebSocket to the door's /peer: opened on the service there first, then taken here with the sub-protocol the
  /// service chose, its messages passed both ways.
  async upgrade(req: IncomingMessage, socket: Duplex, head: Buffer, target: PeerTarget): Promise<void> {
    let stream: Stream | null = null;
    socket.on("error", () => {});
    try {
      if ((req.headers.upgrade ?? "").toLowerCase() !== "websocket") throw new HttpRefusal(400, "only WebSocket upgrades go to other stations");
      const peer = peerNamed(this.cloud, target.station);
      const s = (stream = await this.stream(peer.id, target.station));
      await writeLine(s, { workspace: peer.workspace, port: target.port, method: "GET", path: target.path, headers: passed(req.rawHeaders), socket: true });
      const reader = new Reader(s, MAX_HEAD);
      const answer = await reader.line();
      if (answer?.status !== 101) {
        let said = reader.carry;
        for (let more = await s.read(); more !== null && said.length < MAX_REFUSAL; more = await s.read()) said = Buffer.concat([said, more]);
        const status = Number.isInteger(answer?.status) ? answer.status : 502;
        throw new HttpRefusal(status, said.length > 0 ? said.subarray(0, MAX_REFUSAL).toString() : `station ${target.station} ended the request without an answer`);
      }
      if (socket.destroyed) throw new Error("the caller went");
      this.chosen.set(req, pairs(answer.headers).find(([k]) => k === "sec-websocket-protocol")?.[1] ?? null);
      this.sockets.handleUpgrade(req, socket, head, (ws) => {
        void pumpSocket(new ServiceSocket(ws), new FrameReader(s, reader.carry), s).catch((error) => log.info("mesh", "a WebSocket to another station ended", { error: (error as Error).message }));
      });
    } catch (error) {
      if (stream !== null) void stream.reset(0).catch(() => {});
      if (error instanceof HttpRefusal) refuseUpgrade(socket, error.status, error.message);
      else refuseUpgrade(socket, 502, `station ${target.station}: ${(error as Error).message}`);
    }
  }
}

/// What a station serving others' requests knows of this machine: how a forwarded connection reaches a port here
/// (peer-forward.ts `reachLocal`; tests map ports), and which ports are this station's own forwards (refused: a forward
/// reaching another would carry it on, around in a loop when two stations forward to each other).
export type HereLocal = { reach?: (port: number) => Promise<Socket>; forwarded?: (port: number) => boolean };

/// Another station's connection on this protocol: each stream a request to a web service on this machine, while that
/// station is in a workspace with this one. Out of it, its connection ends; a roster not current ends nothing (losing
/// still.fail cloud alone stops nothing), though new connections wait for one. `local`: this machine as its requests
/// reach it (HereLocal).
export async function serveHttp(conn: Connection, cloud: Cloud, local: HereLocal = {}): Promise<void> {
  const peer = conn.remoteId();
  try {
    member(cloud, peer, null);
  } catch (error) {
    // Nothing served; its first request told why, then the connection ends.
    const stream = await wall.within(HEAD_MS, conn.acceptBi(), "").catch(() => null);
    if (stream !== null) {
      await refusal(stream, (error as Error).message).catch(() => {});
      await wall.within(HEAD_MS, stream.stopped(), "").catch(() => {});
    }
    throw error;
  }
  const unlisten = cloud.listen(() => {
    if (!cloud.peersCurrent) return;
    try {
      member(cloud, peer, null);
    } catch {
      conn.close(3, "not in the workspace");
    }
  });
  try {
    for (let stream = await conn.acceptBi(); stream !== null; stream = await conn.acceptBi()) {
      const s = stream;
      answer(cloud, peer, s, local).catch((error) => {
        log.info("mesh", "a web request of another station failed", { error: (error as Error).message });
        void s.reset(0).catch(() => {});
      });
    }
  } finally {
    unlisten();
  }
}

/// An answer's end. Once it is all there, what is left of the request is not wanted (a service may answer without
/// reading all of it): the stream is stopped, so its sender does not wait to send the rest.
async function ended(stream: Stream) {
  await stream.finish();
  stream.stopped().then(() => stream.reset(0), () => {}).catch(() => {});
}

/// A request refused for who asks (peer.ts `member`): its words, as an answer.
async function refusal(stream: Stream, why: string) {
  await writeLine(stream, { status: /not current/.test(why) ? 503 : 403, headers: [["content-type", "text/plain; charset=utf-8"]] });
  await stream.write(Buffer.from(`that station refused: ${why}`));
  await ended(stream);
}

/// One request: refused, or passed to the service on this machine and its answer sent back as it comes.
async function answer(cloud: Cloud, peer: string, stream: Stream, local: HereLocal): Promise<void> {
  const reader = new Reader(stream, MAX_HEAD);
  const head = await wall.within(HEAD_MS, reader.line(), "no request head in time");
  if (head === null) return;
  const refuse = async (status: number, text: string) => {
    await writeLine(stream, { status, headers: [["content-type", "text/plain; charset=utf-8"]] });
    await stream.write(Buffer.from(text));
    await ended(stream);
  };
  try {
    member(cloud, peer, typeof head.workspace === "string" ? head.workspace : "");
  } catch (error) {
    return refusal(stream, (error as Error).message);
  }
  const port = head.port;
  if (!Number.isInteger(port) || port < 1 || port > 65535) return refuse(400, "port: 1 to 65535");
  // The station's own (its agents' door would carry the request on to a third).
  if (ownPorts.has(port)) return refuse(403, `port ${port} is the station's own there, not a service's`);
  if (local.forwarded?.(port) === true) return refuse(403, `port ${port} there is a port that station forwards from another (peer_forward), not a service's: reach that one directly`);
  // A forwarded connection: its bytes as they are, to the port as a program on this machine reaches it.
  if (head.tcp === true) {
    if (head.probe === true) {
      await writeLine(stream, { status: 200 });
      return ended(stream);
    }
    let socket: Socket;
    try {
      socket = await (local.reach ?? reachLocal)(port);
    } catch (error) {
      return refuse(502, `nothing takes connections on port ${port} there: ${(error as Error).message}`);
    }
    try {
      await writeLine(stream, { status: 200 });
    } catch (error) {
      socket.destroy();
      throw error;
    }
    return pipeTcp(socket, stream, reader.carry);
  }
  if (typeof head.path !== "string" || !head.path.startsWith("/")) return refuse(400, "path: from /");
  const method = typeof head.method === "string" ? head.method : "GET";
  const headers = pairs(head.headers);
  const lang = stationLang();
  if (head.socket === true) {
    let service: ServiceSocket;
    try {
      service = await openSocket(headers, port, head.path, lang, "peer");
    } catch (error) {
      return refuse(error instanceof SocketRefused ? error.status : 502, (error as Error).message);
    }
    await writeLine(stream, { status: 101, headers: service.protocol === null ? [] : [["sec-websocket-protocol", service.protocol]] });
    await pumpSocket(service, new FrameReader(stream, reader.carry), stream);
    return;
  }
  const got = await proxyPreview(method, headers, head.body === true ? rest(reader) : null, port, head.path, lang, "peer");
  // The asker gone (its program went): the service's answer is let go.
  const letGo = () => void got.body.destroy();
  stream.stopped().then(letGo, letGo);
  await writeLine(stream, { status: got.status, headers: got.headers });
  for await (const chunk of got.body) await stream.write(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  await ended(stream);
}
