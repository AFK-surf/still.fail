// Data outflow's own socket (docs/data-outflow.md): <data>/run/outflow.sock, on this machine alone, HTTP. A program
// here asks for some kinds of the station's data (POST /v1/request): the station says who it is by the other end of the
// socket (never by what it says of itself), the person at this machine answers in a window, and the program gets a
// token. With it, that program alone reads what it was granted (GET /v1/usage, GET /v1/chats), in the shape of `/v1`.
import { createHash } from "node:crypto";
import { chmodSync, createReadStream, rmSync, statSync } from "node:fs";
import { type IncomingMessage, type Server, type ServerResponse, createServer } from "node:http";
import { join } from "node:path";
import type { Socket } from "node:net";
import { log } from "../ops/log.ts";
import { type Lang, tr } from "../ops/i18n.ts";
import { type Identity, type OutflowGrants, SCOPES, type Scope, identityKey } from "./grants.ts";

/// A read of the station's (read/ops.ts), its answer as JSON text.
export type Reads = (op: string, args: unknown, lang: Lang) => Promise<string>;

/// The window that asks the person here (still.fail Helper's `outflow.ask`): the kinds they left, or null (refused,
/// closed, not answered). `busy` when another is up. `left`: the program hung up; the window goes.
export type Ask = (request: { words: Record<string, string>; identity: Identity; scopes: { id: Scope; name: string; why: string }[]; ms: number; left: AbortSignal }) => Promise<Scope[] | null | "busy">;

/// Who is at the other end of a connection, as the system says it; null when it cannot say.
export type Identify = (socket: Socket) => Promise<Identity | null>;

export type OutflowOptions = {
  path: string;
  grants: OutflowGrants;
  reads: Reads;
  identify: Identify;
  /// Null where no window can ask (no still.fail Helper: not macOS).
  ask: Ask | null;
  lang: () => Lang;
};

/// How long the window waits for an answer.
export const ASK_MS = 10 * 60_000;
/// A span of usage read at once, at most.
const SPAN_MAX_MS = 31 * 24 * 60 * 60_000;
const BODY_MAX = 16 * 1024;
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
  /// The requests being answered, waited for as it closes (a window asking is called off: their sockets close).
  readonly #answering = new Set<Promise<void>>();

  constructor(options: OutflowOptions) {
    this.#o = options;
  }

  /// Listening, the socket only this user may open.
  listen(): Promise<void> {
    rmSync(this.#o.path, { force: true });
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
      server.listen(this.#o.path, () => {
        server.off("error", reject);
        chmodSync(this.#o.path, 0o600);
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
    await Promise.allSettled([...this.#answering]);
  }

  async #answer(req: IncomingMessage, res: ServerResponse) {
    const url = new URL(req.url ?? "/", "http://outflow");
    if (req.method === "POST" && url.pathname === "/v1/request") return this.#request(req, res);
    if (req.method === "GET" && (url.pathname === "/v1/usage" || url.pathname === "/v1/chats")) return this.#read(req, res, url);
    throw new Refused(404, "no such request");
  }

  async #caller(req: IncomingMessage): Promise<Identity> {
    const identity = await this.#o.identify(req.socket);
    if (identity === null) throw new Refused(403, "the station cannot tell which program this is");
    return identity;
  }

  async #request(req: IncomingMessage, res: ServerResponse) {
    const ask = this.#o.ask;
    if (ask === null) throw new Refused(501, "unsupported: no window can ask on this machine");
    const given = await body(req);
    const asked = Array.isArray(given?.scopes) ? [...new Set(given.scopes)] : [];
    if (asked.length === 0 || !asked.every((s): s is Scope => SCOPES.includes(s as Scope))) throw new Refused(400, `scopes are some of ${SCOPES.join(", ")}`);
    const caller = await this.#caller(req);
    const self = { name: said(given?.name), purpose: said(given?.purpose) };
    // Gone while it waits: the window goes, and nothing is given.
    const left = new AbortController();
    req.socket.once("close", () => left.abort());
    const lang = this.#o.lang();
    const scopesAsked = asked.map((id) => ({ id, name: tr(lang, `station.outflow.scope.${id}`), why: tr(lang, `station.outflow.scope.${id}Why`) }));
    const answer = await ask({ words: words(lang, caller, self, asked), identity: caller, scopes: scopesAsked, ms: ASK_MS, left: left.signal });
    if (answer === "busy") throw new Refused(409, "another request is being answered");
    if (answer === null || answer.length === 0) throw new Refused(403, "refused");
    const scopes = answer.filter((s) => asked.includes(s));
    if (left.signal.aborted) {
      log.info("outflow", "a program left before it was answered; nothing granted", { app: caller.app, path: caller.path });
      return;
    }
    const { grant, token } = this.#o.grants.add(caller, self, scopes);
    log.info("outflow", "granted", { grant: grant.id, app: caller.app, team: caller.teamId, identifier: caller.identifier, scopes });
    send(res, 200, { token, grant: grant.id, scopes });
  }

  async #read(req: IncomingMessage, res: ServerResponse, url: URL) {
    const token = /^Bearer (\S+)$/i.exec(req.headers.authorization ?? "")?.[1] ?? "";
    const grant = this.#o.grants.byToken(token);
    if (grant === null) throw new Refused(401, "revoked");
    const caller = await this.#caller(req);
    if (identityKey(caller) !== identityKey(grant.identity)) throw new Refused(401, "this token was given to another program");
    const scope: Scope = url.pathname === "/v1/usage" ? "usage" : "chats";
    if (!grant.scopes.includes(scope)) throw new Refused(403, `not granted: ${scope}`);
    const lang = this.#o.lang();
    let text: string;
    if (scope === "usage") {
      const from = int(url, "from");
      const to = int(url, "to");
      const tz = int(url, "tz") ?? 0;
      if (from === null || to === null || from >= to) throw new Refused(400, "from and to are ms, from before to");
      if (to - from > SPAN_MAX_MS) throw new Refused(400, "a span is at most 31 days");
      if (Math.abs(tz) > 1440) throw new Refused(400, "tz is minutes east of UTC, at most 1440");
      text = await this.#o.reads("outflowUsage", { from, to, tz, lang }, lang);
    } else {
      text = await this.#o.reads("outflowChats", { since: int(url, "since") ?? 0 }, lang);
    }
    const read = JSON.parse(text);
    this.#o.grants.read(grant.id, scope, (scope === "usage" ? read.rows : read.chats)?.length ?? 0);
    send(res, 200, read);
  }
}

/// The window's words in `lang`: who asks, as the system says it and as it says itself, and the summary confirmed.
export function words(lang: Lang, who: Identity, self: { name: string; purpose: string }, scopes: Scope[]): Record<string, string> {
  const w = (key: string, args: Record<string, unknown> = {}) => tr(lang, `station.outflow.window.${key}`, args);
  const program = who.app ?? who.identifier ?? who.path.split("/").at(-1) ?? who.path;
  const signer = who.valid && who.teamId !== null ? (who.signer ?? who.teamId) : w("unsignedShort");
  const kinds = scopes.map((s) => w("kind", { kind: tr(lang, `station.outflow.scope.${s}`) })).join(w("and"));
  return {
    title: w("title"),
    heading: w("heading", { program }),
    signedBy: w("signedBy"),
    unsigned: w("unsigned"),
    program: w("program"),
    identifier: w("identifier"),
    path: w("path"),
    saidHeading: w("saidHeading"),
    said: [self.name, self.purpose].filter((s) => s !== "").join(" — "),
    scopesHeading: w("scopesHeading"),
    until: w("until"),
    refuse: w("refuse"),
    allow: w("allow"),
    confirmTitle: w("confirmTitle"),
    summary: w("summary", { kinds, program, signer }),
    back: w("back"),
    confirm: w("confirm"),
    cancel: w("cancel"),
    reason: w("reason", { program }),
  };
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

/// The socket's path under the data directory.
export const socketPath = (data: string) => join(data, "run", "outflow.sock");
