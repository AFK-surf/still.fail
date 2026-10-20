// The agents' door (server.rs `serve_mcp`): loopback only. /mcp is the MCP endpoint, /jobs/notify what a job says
// (`stillfail-job notify`), /health that the station answers, /peer/<station>/<port>/… a web service on another station
// of the workspace (mesh/peer-http.ts). Its socket is the launcher's (fd 3), so a handover has no gap: the old station
// stops taking connections and finishes the calls it has; the new one takes the next.
import { type IncomingMessage, type Server, type ServerResponse, STATUS_CODES, createServer } from "node:http";
import type { AddressInfo } from "node:net";
import type { Duplex } from "node:stream";
import { log } from "../ops/log.ts";
import { ownPorts } from "../ops/own.ts";
import type { Tunnels } from "../mesh/peer-forward.ts";
import type { McpEndpoint } from "./mcp.ts";
import { wall } from "../ops/fibers.ts";

/// What /jobs/notify does with a job's words: a status and a body (jobs.ts `notifyEndpoint`).
export type Notified = (authorization: string | undefined, body: Buffer) => { status: number; body: unknown };

/// A job's words: no more than this is read.
const NOTIFY_LIMIT = 64 * 1024;

export type AgentsDoor = {
  /// Where agents reach it: `http://127.0.0.1:<port>/mcp` (the launcher's entrance's port when it has one).
  url: string;
  /// Where it listens.
  port: number;
  /// Stops taking connections; done once the calls it has are answered (or after `graceMs`).
  close(graceMs?: number): Promise<void>;
};

/// A /peer/<station>/<port>/<path> request's parts: the station as named (`given`: as the URL has it), the port, and the
/// path with its query, as asked.
export type PeerTarget = { station: string; given: string; port: number; path: string };

/// Where the door sends /peer requests (mesh/peer-http.ts `PeerHttp`), and forwarded ports their connections
/// (mesh/peer-forward.ts): none until the mesh is up.
export type PeerRoute = Tunnels & {
  request(req: IncomingMessage, res: ServerResponse, target: PeerTarget): Promise<void>;
  upgrade(req: IncomingMessage, socket: Duplex, head: Buffer, target: PeerTarget): Promise<void>;
};

/// Where programs reach the other stations' web services (`STILLFAIL_PEER_HTTP`), from the door's MCP URL.
export const peerHttpBase = (mcpUrl: string) => mcpUrl.replace(/\/mcp$/, "/peer");

/// The parts of a /peer/<station>/<port>/<path> URL; null when it is not one.
export function peerTarget(url: string): PeerTarget | null {
  if (!url.startsWith("/peer/")) return null;
  const rest = url.slice("/peer/".length);
  const slash = rest.indexOf("/");
  if (slash <= 0) return null;
  const given = rest.slice(0, slash);
  let station: string;
  try {
    station = decodeURIComponent(given);
  } catch {
    return null;
  }
  const after = rest.slice(slash + 1);
  const port = /^[0-9]{1,5}(?=$|[/?])/.exec(after)?.[0];
  if (port === undefined || Number(port) < 1 || Number(port) > 65535) return null;
  const tail = after.slice(port.length);
  return { station, given, port: Number(port), path: tail === "" ? "/" : tail.startsWith("?") ? `/${tail}` : tail };
}

/// Why a /peer request is not taken (null: it is). Only programs on this machine: by a loopback name and the door's port
/// (a page of any site, renamed to 127.0.0.1 by DNS rebinding, still says its own Host), and not a web page (one says
/// its Origin; `Origin: null` only from outside a browser: a sandboxed frame's says where it is fetched from too).
export function notFromHere(headers: IncomingMessage["headers"], ports: number[]): string | null {
  const host = /^(?:127\.0\.0\.1|localhost|\[::1\]):([0-9]{1,5})$/i.exec(headers.host ?? "");
  if (host === null || !ports.includes(Number(host[1]))) return `only programs on this machine reach other stations here, by http://127.0.0.1:${ports[0]}/peer/…`;
  const origin = headers.origin;
  const site = headers["sec-fetch-site"];
  if (origin !== undefined && (origin !== "null" || (site !== undefined && site !== "none"))) return "web pages do not reach other stations through this one";
  return null;
}

/// A refusal on a socket that asked to upgrade (no HTTP response object there).
export function refuseUpgrade(socket: Duplex, status: number, text: string) {
  const body = Buffer.from(text);
  const head = `HTTP/1.1 ${status} ${STATUS_CODES[status] ?? ""}\r\ncontent-type: text/plain; charset=utf-8\r\ncontent-length: ${body.length}\r\nconnection: close\r\n\r\n`;
  socket.on("error", () => {});
  socket.end(Buffer.concat([Buffer.from(head), body]));
}

/// A request's body, up to `limit` bytes (null when longer).
function bodyOf(req: IncomingMessage, limit: number): Promise<Buffer | null> {
  return new Promise((resolve, reject) => {
    const parts: Buffer[] = [];
    let size = 0;
    req.on("data", (chunk: Buffer) => {
      size += chunk.length;
      if (size <= limit) parts.push(chunk);
    });
    req.on("end", () => resolve(size > limit ? null : Buffer.concat(parts)));
    req.on("error", reject);
  });
}

/// Opens the door on the launcher's fd, or on `port` at 127.0.0.1 (0: any free one): with no launcher, or behind a
/// launcher's entrance (`shown`, its port, is then the one agents are told: launcher.ts `ports`). `peers`: where /peer
/// requests go, once there is a way (the mesh's).
export function openAgentsDoor(at: { fd: number } | { port: number; shown?: number }, mcp: McpEndpoint, notified: Notified, peers: () => PeerRoute | null = () => null): Promise<AgentsDoor> {
  let busy = 0;
  let idle: (() => void) | null = null;
  // The ports it is reached on (the entrance's first): known once it listens, before any request.
  let ports: number[] = [];
  /// A /peer request's refusal before it goes anywhere, or where it goes.
  const peerOf = (req: IncomingMessage): [number, string] | [PeerRoute, PeerTarget] => {
    const why = notFromHere(req.headers, ports);
    if (why !== null) return [403, why];
    const target = peerTarget(req.url ?? "/");
    if (target === null) return [404, "a web service of another station is /peer/<station name or id>/<port>/<path>"];
    const route = peers();
    if (route === null) return [503, "this station is not on the mesh yet; try again shortly"];
    return [route, target];
  };
  const server: Server = createServer(async (req, res) => {
    // Another station's web service: as long as it streams, not a call the door waits for when it closes.
    if (req.url === "/peer" || req.url?.startsWith("/peer/")) {
      const [route, target] = peerOf(req);
      if (typeof route === "number") res.writeHead(route, { "content-type": "text/plain; charset=utf-8" }).end(target);
      else await route.request(req, res, target as PeerTarget).catch((error) => (log.warn("mcp", "a request to another station failed", { error: (error as Error).message }), res.destroy()));
      return;
    }
    busy++;
    const send = (status: number, body: unknown) => {
      if (body === undefined) res.writeHead(status).end();
      else res.writeHead(status, { "content-type": "application/json" }).end(JSON.stringify(body));
    };
    try {
      const path = new URL(req.url ?? "/", "http://agents").pathname;
      if (path === "/health") send(200, { ok: true });
      else if (path === "/jobs/notify" && req.method === "POST") {
        const body = await bodyOf(req, NOTIFY_LIMIT);
        if (body === null) send(400, { error: "length limit exceeded" });
        else {
          const answer = notified(req.headers.authorization, body);
          send(answer.status, answer.body);
        }
      } else if (path === "/mcp") {
        const body = (await bodyOf(req, Number.MAX_SAFE_INTEGER))!;
        const reply = await mcp.handle(req.method ?? "GET", req.headers.authorization, body);
        send(reply.status, reply.body);
      } else res.writeHead(404, { "content-type": "text/plain" }).end();
    } catch (error) {
      log.warn("mcp", "a request to the agents' door failed", { error: (error as Error).message });
      if (!res.headersSent) send(500, { error: (error as Error).message });
      else res.destroy();
    } finally {
      if (--busy === 0) idle?.();
    }
  });
  // Agents call one after another on a kept connection: an idle one is not kept past the calls.
  server.keepAliveTimeout = 5_000;
  // An upload to another station's service takes as long as it takes.
  server.requestTimeout = 0;
  // Another station's service's WebSocket; nothing else upgrades.
  server.on("upgrade", (req: IncomingMessage, socket: Duplex, head: Buffer) => {
    if (!req.url?.startsWith("/peer/")) return refuseUpgrade(socket, 404, "");
    const [route, target] = peerOf(req);
    if (typeof route === "number") return refuseUpgrade(socket, route, target as string);
    route.upgrade(req, socket, head, target as PeerTarget).catch((error) => {
      log.warn("mcp", "a WebSocket to another station failed", { error: (error as Error).message });
      socket.destroy();
    });
  });
  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.once("listening", () => {
      server.off("error", reject);
      server.on("error", (e) => log.error("mcp", "the agents' door failed", { error: e.message }));
      const port = (server.address() as AddressInfo).port;
      ports = "shown" in at && at.shown !== undefined ? [at.shown, port] : [port];
      for (const p of ports) ownPorts.add(p);
      resolve({
        url: `http://127.0.0.1:${"shown" in at && at.shown !== undefined ? at.shown : port}/mcp`,
        port,
        close: (graceMs = 30_000) =>
          new Promise<void>((done) => {
            server.close();
            server.closeIdleConnections();
            if (busy === 0) return done();
            // How long the agents' calls under way are given: their time, the machine's.
            const timer = wall.after(graceMs, () => {
              server.closeAllConnections();
              done();
            });
            idle = () => {
              timer();
              server.closeAllConnections();
              done();
            };
          }),
      });
    });
    if ("fd" in at) server.listen({ fd: at.fd });
    else server.listen(at.port, "127.0.0.1");
  });
}
