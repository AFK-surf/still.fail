// Data outflow's own socket: <data>/run/outflow.sock, on this machine alone, HTTP. A program
// here asks for some kinds of the station's data (POST /v1/request): the station says who it is by the other end of the
// socket (never by what it says of itself), an admin of the workspace answers in still.fail, and the program gets a
// token. With it, it reads what it was granted (GET /v1/stations, /v1/usage, /v1/chats,
// /v1/messages), of this station or, granted the workspace, of any station of it, in the shape of `/v1`.
import { createHash } from "node:crypto";
import { chmodSync, createReadStream, readdirSync, readlinkSync, renameSync, rmSync, statSync, symlinkSync } from "node:fs";
import { type IncomingMessage, type Server, type ServerResponse, createServer } from "node:http";
import { basename, dirname, join } from "node:path";
import { randomBytes } from "node:crypto";
import type { Socket } from "node:net";
import { log } from "../ops/log.ts";
import { wall } from "../ops/fibers.ts";
import type { Lang } from "../ops/i18n.ts";
import { type Identity, type OutflowGrants, type Reach, SCOPES, type Scope, type Taken } from "./grants.ts";

/// A read of the station's (read/ops.ts), its answer as JSON text.
export type Reads = (op: string, args: unknown, lang: Lang) => Promise<string>;

/// Who is at the other end of a connection, as the system says it; null when it cannot say.
export type Identify = (socket: Socket, req?: IncomingMessage) => Promise<Identity | null>;

/// A station of the workspace as a program granted it is told it: `here` is this one.
export type StationEntry = { id: string; name: string; here: boolean };

/// The stations of the home workspace: this one, which there are (this one among them), and a read of another's (the
/// same ops, asked over the station transport), its answer as JSON text.
export type Workspace = {
  here: () => StationEntry;
  stations: () => Promise<StationEntry[]>;
  read: (station: string, op: string, args: unknown) => Promise<string>;
};

/// A request made in the station's admin API as a member, for a program granted `operate`: on this station, or
/// (`station`) on another of the workspace. The answer's body is the API's, as it is.
export type Operate = (call: OperateCall) => Promise<{ status: number; headers: Record<string, string>; body: Buffer }>;
export type OperateCall = { station: string | null; actor: string; role: string; method: string; path: string; query: [string, string][]; headers: Record<string, string>; body: Buffer };

export type OutflowOptions = {
  path: string;
  grants: OutflowGrants;
  reads: Reads;
  identify: Identify;
  workspace: Workspace;
  operate?: Operate;
  lang: () => Lang;
  /// How long another station is given to answer a read (ms); PEER_WAIT_MS unless said.
  peerWaitMs?: number;
};

/// How long another station of the workspace is given to answer a read: one that does not is a 504, not a request
/// left hanging.
const PEER_WAIT_MS = 60_000;

/// A span of usage read at once, at most.
const SPAN_MAX_MS = 31 * 24 * 60 * 60_000;
const BODY_MAX = 16 * 1024;
/// A request `POST /v1/operate` carries, at most: an API request and what it uploads, in base64.
const OPERATE_MAX = 64 * 1024 * 1024;
/// What a program granted `operate` is not given, whoever it acts as: the grants it holds would be its own to answer,
/// and a vault opens only in a person's app.
const NOT_OPERATED = /^\/*(outflow|vault|vault-requests)(\/|$)/;
/// Read as the admin API's routes read a path, slashes repeated and all; one that cannot be read so is refused too.
export function notOperated(path: string): boolean {
  try {
    const bare = decodeURIComponent(path.split("?")[0]!);
    return bare.includes("..") || bare.includes("\\") || NOT_OPERATED.test(bare);
  } catch {
    return true;
  }
}
const OPERATE_METHODS = ["GET", "POST", "PUT", "PATCH", "DELETE"];
/// Messages read at once: by default and at most.
const MESSAGES_PAGE = 100;
const MESSAGES_PAGE_MAX = 500;
/// Chats read at once, at most, when asked a page at a time.
const CHATS_PAGE_MAX = 1000;
const SAID_MAX = 200;

class Refused extends Error {
  readonly status: number;
  /// Said beside `error`.
  readonly more: Record<string, unknown>;
  constructor(status: number, message: string, more: Record<string, unknown> = {}) {
    super(message);
    this.status = status;
    this.more = more;
  }
}

const send = (res: ServerResponse, status: number, body: unknown) => {
  if (res.writableEnded || res.destroyed) return;
  res.writeHead(status, { "content-type": "application/json; charset=utf-8" }).end(JSON.stringify(body));
};

async function body(req: IncomingMessage, max = BODY_MAX): Promise<any> {
  let text = "";
  for await (const chunk of req) {
    text += chunk;
    if (text.length > max) throw new Refused(413, "the request is too long");
  }
  try {
    return JSON.parse(text);
  } catch {
    throw new Refused(400, "the request is not JSON");
  }
}

const said = (v: unknown) => (typeof v === "string" ? v.trim().slice(0, SAID_MAX) : "");

/// A whole number of ms from the query, or null.
function int(url: URL, name: string): number | null {
  const v = url.searchParams.get(name);
  if (v === null || !/^-?\d+$/.test(v)) return null;
  const n = Number(v);
  return Number.isSafeInteger(n) ? n : null;
}

export class OutflowServer {
  readonly #o: OutflowOptions;
  #server: Server | null = null;
  /// The socket this process listens on, which `path` links to (see `listen`).
  #own: string | null = null;
  /// The TCP servers of `listenTcp` open now.
  readonly #tcp = new Set<Server>();
  /// The requests being answered, waited for as it closes (a window asking is called off: their sockets close).
  readonly #answering = new Set<Promise<void>>();

  constructor(options: OutflowOptions) {
    this.#o = options;
  }

  /// Listening, the socket only this user may open. Each process listens on a socket of its own beside `path`
  /// (`outflow-<pid>-<n>.sock`) and `path` links to it: a station's update starts the next process beside the one
  /// serving, and a socket closed takes its file with it, so a shared path was gone once the process before stopped.
  /// The link is moved in one step; a process closing removes its own socket, and the link only while it is its own.
  listen(): Promise<void> {
    const dir = dirname(this.#o.path);
    const stem = basename(this.#o.path).replace(/\.sock$/, "");
    this.#removeLeftovers(dir, stem);
    const own = join(dir, `${stem}-${process.pid}-${randomBytes(4).toString("hex")}.sock`);
    this.#own = own;
    const server = this.#serve(this.#o.identify);
    this.#server = server;
    return new Promise((resolve, reject) => {
      server.once("error", reject);
      server.listen(own, () => {
        server.off("error", reject);
        chmodSync(own, 0o600);
        this.#link();
        resolve();
      });
    });
  }

  /// The same requests answered on a TCP port of this machine's loopback (port 0: one the system picks), each caller
  /// as `identify` says it: the way in a tunnel such as Tailcat forwards to (tailcat.ts). Resolved with the port.
  listenTcp(port: number, identify: Identify): Promise<{ port: number; close: () => Promise<void> }> {
    const server = this.#serve(identify);
    this.#tcp.add(server);
    const close = async () => {
      if (!this.#tcp.delete(server)) return;
      server.closeAllConnections();
      await new Promise<void>((resolve) => server.close(() => resolve()));
    };
    return new Promise((resolve, reject) => {
      server.once("error", (e) => (this.#tcp.delete(server), reject(e)));
      server.listen(port, "127.0.0.1", () => {
        server.removeAllListeners("error");
        const at = server.address();
        resolve({ port: typeof at === "object" && at !== null ? at.port : port, close });
      });
    });
  }

  /// A server answering each request, its caller as `identify` says it.
  #serve(identify: Identify): Server {
    return createServer((req, res) => {
      const answering = this.#answer(req, res, identify)
        .catch((e) => {
          if (e instanceof Refused) send(res, e.status, { error: e.message, ...e.more });
          else {
            log.warn("outflow", "a request was not answered", { error: (e as Error).message });
            send(res, 500, { error: "the station could not answer" });
          }
        })
        .finally(() => this.#answering.delete(answering));
      this.#answering.add(answering);
    });
  }

  /// Closed, once what it was answering is answered.
  async close(): Promise<void> {
    const server = this.#server;
    this.#server = null;
    if (server) {
      server.closeAllConnections();
      await new Promise<void>((resolve) => server.close(() => resolve()));
    }
    for (const tcp of [...this.#tcp]) {
      this.#tcp.delete(tcp);
      tcp.closeAllConnections();
      await new Promise<void>((resolve) => tcp.close(() => resolve()));
    }
    // The link goes only while it is still this process's: the next process's stays.
    const own = this.#own;
    this.#own = null;
    if (own !== null) {
      try {
        if (readlinkSync(this.#o.path) === basename(own)) rmSync(this.#o.path, { force: true });
      } catch {}
      rmSync(own, { force: true });
    }
    await Promise.allSettled([...this.#answering]);
  }

  /// The process before this one is gone: one from before the link removed `path` itself as it stopped; linked again
  /// where it is not there.
  previousGone(): void {
    this.#link(true);
  }

  /// `path` linked to this process's socket, in one step; with `missing`, only when it is not there.
  #link(missing = false) {
    const own = this.#own;
    if (own === null) return;
    if (missing) {
      try {
        statSync(this.#o.path);
        return;
      } catch {}
    }
    const link = `${this.#o.path}.${process.pid}.tmp`;
    try {
      rmSync(link, { force: true });
      symlinkSync(basename(own), link);
      renameSync(link, this.#o.path);
    } catch (e) {
      log.warn("outflow", "the outflow socket is not linked", { error: (e as Error).message });
    }
  }

  /// Sockets of processes that are gone (one that ended without closing) go.
  #removeLeftovers(dir: string, stem: string) {
    let names: string[] = [];
    try {
      names = readdirSync(dir);
    } catch {
      return;
    }
    for (const name of names) {
      const m = new RegExp(`^${stem}-(\\d+)-[0-9a-f]{8}\\.sock$`).exec(name);
      if (m === null || alive(Number(m[1]))) continue;
      rmSync(join(dir, name), { force: true });
    }
  }

  async #answer(req: IncomingMessage, res: ServerResponse, identify: Identify) {
    const url = new URL(req.url ?? "/", "http://outflow");
    if (req.method === "POST" && url.pathname === "/v1/request") return this.#request(req, res, identify);
    if (req.method === "POST" && url.pathname === "/v1/operate") {
      if (identify !== this.#o.identify) await this.#caller(req, identify);
      return this.#operate(req, res);
    }
    if (req.method === "GET" && ["/v1/stations", "/v1/usage", "/v1/chats", "/v1/messages"].includes(url.pathname)) {
      // On a way in other than the socket, a read too comes by that way's own proof (a link's code).
      if (identify !== this.#o.identify) await this.#caller(req, identify);
      return this.#read(req, res, url);
    }
    throw new Refused(404, "no such request");
  }

  async #caller(req: IncomingMessage, identify: Identify): Promise<Identity> {
    const identity = await identify(req.socket, req);
    if (identity === null) throw new Refused(403, "the station cannot tell which program this is");
    return identity;
  }

  async #request(req: IncomingMessage, res: ServerResponse, identify: Identify) {
    const given = await body(req);
    const asked = Array.isArray(given?.scopes) ? [...new Set(given.scopes)] : [];
    if (asked.length === 0 || !asked.every((s): s is Scope => SCOPES.includes(s as Scope))) throw new Refused(400, `scopes are some of ${SCOPES.join(", ")}`);
    const reach: Reach = given?.workspace === true ? "workspace" : "station";
    const caller = await this.#caller(req, identify);
    // What it already holds is given at once: a program asks once, not for each read.
    const held = this.#o.grants.held(caller, asked, reach);
    if (held !== null) return send(res, 200, { token: held.token, grant: held.grant.id, scopes: held.grant.scopes, reach: held.grant.reach });
    const self = { name: said(given?.name), purpose: said(given?.purpose) };
    const request = this.#o.grants.ask(caller, self, asked, reach, said(given?.key));
    // Gone while it waits: nothing is taken, and the request stays for when it asks again.
    const left = new AbortController();
    req.socket.once("close", () => left.abort());
    const taken = await this.#answered(request.id, left.signal);
    if (taken === null) return;
    if (taken === "refused") throw new Refused(403, "refused");
    log.info("outflow", "granted", { grant: taken.grant.id, app: caller.app, team: caller.teamId, identifier: caller.identifier, scopes: taken.grant.scopes, reach: taken.grant.reach });
    send(res, 200, { token: taken.token, grant: taken.grant.id, scopes: taken.grant.scopes, reach: taken.grant.reach });
  }

  /// Request `id`'s answer, taken as soon as an admin gave it, however long that is; null when the program left first.
  #answered(id: string, left: AbortSignal): Promise<Taken | null> {
    const grants = this.#o.grants;
    return new Promise((resolve) => {
      let done = false;
      const end = (taken: Taken | null) => {
        if (done) return;
        done = true;
        stop();
        left.removeEventListener("abort", gone);
        resolve(taken);
      };
      const gone = () => end(null);
      const look = () => {
        if (done || left.aborted) return;
        const taken = grants.take(id);
        if (taken !== null) end(taken);
      };
      const stop = grants.listen(look);
      left.addEventListener("abort", gone, { once: true });
      look();
    });
  }

  /// The grant `req`'s token holds; refused, said apart as `#read` has always said.
  #granted(req: IncomingMessage) {
    const token = /^Bearer (\S+)$/i.exec(req.headers.authorization ?? "")?.[1] ?? "";
    const grant = this.#o.grants.byToken(token);
    if (grant === null) {
      // A token of a grant revoked here, or one this station never gave (another station's, a copy gone stale): told
      // apart, and which station says so, for the program to know where to ask.
      const was = this.#o.grants.revokedOf(token);
      if (was !== null) throw new Refused(401, "revoked", { grant: was.grant, revokedAt: was.at });
      const { id, name } = this.#o.workspace.here();
      throw new Refused(401, "unknown token", { station: { id, name } });
    }
    return grant;
  }

  /// Another station of the workspace named by its id, checked against what `grant` reaches; null for this one.
  async #station(grant: { reach?: Reach }, named: string): Promise<string | null> {
    if (named === "" || named === this.#o.workspace.here().id) return null;
    if (grant.reach !== "workspace") throw new Refused(403, "not granted: other stations");
    const stations = await this.#o.workspace.stations().catch(() => null);
    if (stations === null) throw new Refused(503, "the workspace's stations are not known right now");
    if (!stations.some((s) => s.id === named)) throw new Refused(404, "no such station in the workspace");
    return named;
  }

  /// One request of the admin API, as `actor`: a member of the workspace by their email, as the program says, who has
  /// the role of a member, or the role the person who allowed the grant has when they are that person.
  async #operate(req: IncomingMessage, res: ServerResponse) {
    const grant = this.#granted(req);
    if (!grant.scopes.includes("operate")) throw new Refused(403, "not granted: operate");
    if (this.#o.operate === undefined) throw new Refused(503, "this station does not operate");
    const given = await body(req, OPERATE_MAX);
    const actor = typeof given?.actor === "string" ? given.actor.trim().toLowerCase() : "";
    const method = typeof given?.method === "string" ? given.method.toUpperCase() : "";
    const path = typeof given?.path === "string" ? given.path : "";
    if (actor === "" || !actor.includes("@")) throw new Refused(400, "actor is a member's email");
    if (!OPERATE_METHODS.includes(method) || !path.startsWith("/")) throw new Refused(400, "method and path are the admin API's");
    if (notOperated(path)) throw new Refused(403, "not given to a program");
    const station = await this.#station(grant, typeof given?.station === "string" ? given.station : "");
    const query = (Array.isArray(given?.query) ? given.query : []).filter((p: unknown) => Array.isArray(p) && p.length === 2).map(([k, v]: unknown[]) => [String(k), String(v)] as [string, string]);
    const payload = typeof given?.body === "string" ? Buffer.from(given.body, "base64") : Buffer.alloc(0);
    const headers = { "content-type": typeof given?.contentType === "string" ? given.contentType : "application/json" };
    const role = (grant.allowedBy ?? "").toLowerCase() === actor ? (grant.allowedRole ?? "member") : "member";
    const wait = this.#o.peerWaitMs ?? PEER_WAIT_MS;
    const late = `that station did not answer within ${wait} ms`;
    const call = this.#o.operate({ station, actor, role, method, path, query, headers, body: payload });
    let answer: Awaited<ReturnType<Operate>>;
    try {
      answer = station === null ? await call : await wall.within(wait, call, late);
    } catch (e) {
      const message = (e as Error).message;
      throw message === late ? new Refused(504, late) : new Refused(502, `that station did not answer: ${message}`);
    }
    this.#o.grants.read(grant.id, "operate", 1, station ?? undefined);
    log.info("outflow", "operated", { grant: grant.id, actor, method, path: path.split("?")[0], status: answer.status, station });
    send(res, 200, { status: answer.status, contentType: answer.headers["content-type"] ?? null, body: answer.body.toString("base64") });
  }

  async #read(req: IncomingMessage, res: ServerResponse, url: URL) {
    const grant = this.#granted(req);
    const whole = grant.reach === "workspace";
    if (url.pathname === "/v1/stations") {
      const here = this.#o.workspace.here();
      const stations = whole ? await this.#o.workspace.stations().catch(() => null) : [];
      if (stations === null) throw new Refused(503, "the workspace's stations are not known right now");
      return send(res, 200, { stations: [here, ...stations.filter((s) => s.id !== here.id)] });
    }
    // Another station of the workspace, named by its id as /v1/stations says it.
    const station = await this.#station(grant, url.searchParams.get("station") ?? "");
    const scope: Scope = url.pathname === "/v1/usage" ? "usage" : url.pathname === "/v1/messages" ? "messages" : "chats";
    if (!grant.scopes.includes(scope)) throw new Refused(403, `not granted: ${scope}`);
    const lang = this.#o.lang();
    const reads = async (op: string, args: unknown) => {
      if (station === null) return this.#o.reads(op, args, lang);
      const wait = this.#o.peerWaitMs ?? PEER_WAIT_MS;
      const late = `that station did not answer within ${wait} ms`;
      try {
        return await wall.within(wait, this.#o.workspace.read(station, op, args), late);
      } catch (e) {
        const message = (e as Error).message;
        throw message === late ? new Refused(504, late) : new Refused(502, `that station did not answer: ${message}`);
      }
    };
    let text: string;
    if (scope === "usage") {
      const from = int(url, "from");
      const to = int(url, "to");
      const tz = int(url, "tz") ?? 0;
      if (from === null || to === null || from >= to) throw new Refused(400, "from and to are ms, from before to");
      if (to - from > SPAN_MAX_MS) throw new Refused(400, "a span is at most 31 days");
      if (Math.abs(tz) > 1440) throw new Refused(400, "tz is minutes east of UTC, at most 1440");
      text = await reads("outflowUsage", { from, to, tz, lang });
    } else if (scope === "messages") {
      // The chat by its thread, a session of it (as usage rows name both), or a chat app's channel and thread ts.
      const thread = int(url, "thread");
      const session = url.searchParams.get("session") ?? "";
      const channel = url.searchParams.get("channel") ?? "";
      const ts = url.searchParams.get("ts") ?? "";
      const which = thread !== null ? { thread } : session !== "" ? { session } : channel !== "" && ts !== "" ? { channel, ts } : null;
      if (which === null) throw new Refused(400, "name the chat by thread, session, or channel and ts");
      const after = Math.max(0, int(url, "after") ?? 0);
      const limit = Math.min(Math.max(int(url, "limit") ?? MESSAGES_PAGE, 1), MESSAGES_PAGE_MAX);
      text = await reads("outflowMessages", { ...which, after, limit });
      if (text === "null") throw new Refused(404, "no such chat");
    } else {
      // A page at a time with `limit` (and `before`, the page before's `next`); all at once without.
      const limit = int(url, "limit");
      const before = url.searchParams.get("before");
      text = await reads("outflowChats", { since: int(url, "since") ?? 0, ...(limit === null ? {} : { limit: Math.min(Math.max(limit, 1), CHATS_PAGE_MAX), ...(before ? { before } : {}) }) });
    }
    const read = JSON.parse(text);
    this.#o.grants.read(grant.id, scope, (scope === "usage" ? read.rows : scope === "messages" ? read.messages : read.chats)?.length ?? 0, station ?? undefined);
    send(res, 200, read);
  }
}

/// An unsigned program's executable, as its bytes are: hashed again only when the file changed.
const hashes = new Map<string, { stamp: string; hash: string }>();
export async function fileHash(path: string): Promise<string | null> {
  try {
    const st = statSync(path);
    const stamp = `${st.size}:${st.mtimeMs}:${st.ino}`;
    const had = hashes.get(path);
    if (had?.stamp === stamp) return had.hash;
    const hash = createHash("sha256");
    for await (const chunk of createReadStream(path)) hash.update(chunk as Buffer);
    const out = hash.digest("hex");
    hashes.set(path, { stamp, hash: out });
    return out;
  } catch {
    return null;
  }
}

/// Whether process `pid` is there (one of another user's still counts).
function alive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch (e) {
    return (e as NodeJS.ErrnoException).code === "EPERM";
  }
}

/// The socket's path under the data directory.
export const socketPath = (data: string) => join(data, "run", "outflow.sock");
