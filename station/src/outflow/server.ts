// Data outflow's own socket (docs/data-outflow.md): <data>/run/outflow.sock, on this machine alone, HTTP. A program
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
import type { Lang } from "../ops/i18n.ts";
import { type Identity, type OutflowGrants, type Reach, SCOPES, type Scope, type Taken } from "./grants.ts";

/// A read of the station's (read/ops.ts), its answer as JSON text.
export type Reads = (op: string, args: unknown, lang: Lang) => Promise<string>;

/// Who is at the other end of a connection, as the system says it; null when it cannot say.
export type Identify = (socket: Socket) => Promise<Identity | null>;

/// A station of the workspace as a program granted it is told it: `here` is this one.
export type StationEntry = { id: string; name: string; here: boolean };

/// The stations of the home workspace: this one, which there are (this one among them), and a read of another's (the
/// same ops, asked over the station transport), its answer as JSON text.
export type Workspace = {
  here: () => StationEntry;
  stations: () => Promise<StationEntry[]>;
  read: (station: string, op: string, args: unknown) => Promise<string>;
};

export type OutflowOptions = {
  path: string;
  grants: OutflowGrants;
  reads: Reads;
  identify: Identify;
  workspace: Workspace;
  lang: () => Lang;
  /// The station's clock: how a request waits for its answer.
  sleep: (ms: number) => Promise<void>;
};

/// How long a request waits for an admin's answer before it is told to ask again (`202`).
export const ASK_MS = 10 * 60_000;
/// A span of usage read at once, at most.
const SPAN_MAX_MS = 31 * 24 * 60 * 60_000;
const BODY_MAX = 16 * 1024;
/// Messages read at once: by default and at most.
const MESSAGES_PAGE = 100;
const MESSAGES_PAGE_MAX = 500;
const SAID_MAX = 200;

class Refused extends Error {
  readonly status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

const send = (res: ServerResponse, status: number, body: unknown) => {
  if (res.writableEnded || res.destroyed) return;
  res.writeHead(status, { "content-type": "application/json; charset=utf-8" }).end(JSON.stringify(body));
};

async function body(req: IncomingMessage): Promise<any> {
  let text = "";
  for await (const chunk of req) {
    text += chunk;
    if (text.length > BODY_MAX) throw new Refused(413, "the request is too long");
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
    const server = createServer((req, res) => {
      const answering = this.#answer(req, res)
        .catch((e) => {
          if (e instanceof Refused) send(res, e.status, { error: e.message });
          else {
            log.warn("outflow", "a request was not answered", { error: (e as Error).message });
            send(res, 500, { error: "the station could not answer" });
          }
        })
        .finally(() => this.#answering.delete(answering));
      this.#answering.add(answering);
    });
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

  /// Closed, once what it was answering is answered.
  async close(): Promise<void> {
    const server = this.#server;
    this.#server = null;
    if (server) {
      server.closeAllConnections();
      await new Promise<void>((resolve) => server.close(() => resolve()));
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

  async #answer(req: IncomingMessage, res: ServerResponse) {
    const url = new URL(req.url ?? "/", "http://outflow");
    if (req.method === "POST" && url.pathname === "/v1/request") return this.#request(req, res);
    if (req.method === "GET" && ["/v1/stations", "/v1/usage", "/v1/chats", "/v1/messages"].includes(url.pathname)) return this.#read(req, res, url);
    throw new Refused(404, "no such request");
  }

  async #caller(req: IncomingMessage): Promise<Identity> {
    const identity = await this.#o.identify(req.socket);
    if (identity === null) throw new Refused(403, "the station cannot tell which program this is");
    return identity;
  }

  async #request(req: IncomingMessage, res: ServerResponse) {
    const given = await body(req);
    const asked = Array.isArray(given?.scopes) ? [...new Set(given.scopes)] : [];
    if (asked.length === 0 || !asked.every((s): s is Scope => SCOPES.includes(s as Scope))) throw new Refused(400, `scopes are some of ${SCOPES.join(", ")}`);
    const reach: Reach = given?.workspace === true ? "workspace" : "station";
    const caller = await this.#caller(req);
    const self = { name: said(given?.name), purpose: said(given?.purpose) };
    const request = this.#o.grants.ask(caller, self, asked, reach, said(given?.key));
    // Gone while it waits: nothing is taken, and the request stays for when it asks again.
    const left = new AbortController();
    req.socket.once("close", () => left.abort());
    const taken = await this.#answered(request.id, left.signal);
    if (left.signal.aborted) return;
    if (taken === null) return send(res, 202, { request: request.id, state: "asking" });
    if (taken === "refused") throw new Refused(403, "refused");
    log.info("outflow", "granted", { grant: taken.grant.id, app: caller.app, team: caller.teamId, identifier: caller.identifier, scopes: taken.grant.scopes, reach: taken.grant.reach });
    send(res, 200, { token: taken.token, grant: taken.grant.id, scopes: taken.grant.scopes, reach: taken.grant.reach });
  }

  /// Request `id`'s answer, taken as soon as an admin gave it; null when none came in ASK_MS, or the program left.
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
      void this.#o.sleep(ASK_MS).then(() => end(null));
      look();
    });
  }

  async #read(req: IncomingMessage, res: ServerResponse, url: URL) {
    const token = /^Bearer (\S+)$/i.exec(req.headers.authorization ?? "")?.[1] ?? "";
    const grant = this.#o.grants.byToken(token);
    if (grant === null) throw new Refused(401, "revoked");
    const whole = grant.reach === "workspace";
    if (url.pathname === "/v1/stations") {
      const here = this.#o.workspace.here();
      const stations = whole ? await this.#o.workspace.stations().catch(() => null) : [];
      if (stations === null) throw new Refused(503, "the workspace's stations are not known right now");
      return send(res, 200, { stations: [here, ...stations.filter((s) => s.id !== here.id)] });
    }
    // Another station of the workspace, named by its id as /v1/stations says it.
    const named = url.searchParams.get("station") ?? "";
    const station = named === "" || named === this.#o.workspace.here().id ? null : named;
    if (station !== null) {
      if (!whole) throw new Refused(403, "not granted: other stations");
      const stations = await this.#o.workspace.stations().catch(() => null);
      if (stations === null) throw new Refused(503, "the workspace's stations are not known right now");
      if (!stations.some((s) => s.id === station)) throw new Refused(404, "no such station in the workspace");
    }
    const scope: Scope = url.pathname === "/v1/usage" ? "usage" : url.pathname === "/v1/messages" ? "messages" : "chats";
    if (!grant.scopes.includes(scope)) throw new Refused(403, `not granted: ${scope}`);
    const lang = this.#o.lang();
    const reads = async (op: string, args: unknown) => {
      if (station === null) return this.#o.reads(op, args, lang);
      try {
        return await this.#o.workspace.read(station, op, args);
      } catch (e) {
        throw new Refused(502, `that station did not answer: ${(e as Error).message}`);
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
      const thread = int(url, "thread");
      if (thread === null) throw new Refused(400, "thread is the chat's, as /v1/chats names it");
      const after = Math.max(0, int(url, "after") ?? 0);
      const limit = Math.min(Math.max(int(url, "limit") ?? MESSAGES_PAGE, 1), MESSAGES_PAGE_MAX);
      text = await reads("outflowMessages", { thread, after, limit });
      if (text === "null") throw new Refused(404, "no such chat");
    } else {
      text = await reads("outflowChats", { since: int(url, "since") ?? 0 });
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
