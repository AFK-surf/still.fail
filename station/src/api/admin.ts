// The admin API (the Rust station's admin/mod.rs `route`): a table of routes, each a method, a path pattern and what answers
// it, gathered from src/api/routes (one module a part of the API). Reads go to the readers (off the main thread); what
// is not here answers 404 as an unknown route does.
import type { Readers } from "../read/pool.ts";
import { HttpError } from "../read/views.ts";
import { type Answer, type Request, error, json, queryPairs } from "./request.ts";
import { routes as chats } from "./routes/chats.ts";
import { routes as usage } from "./routes/usage.ts";
import { routes as sessions } from "./routes/sessions.ts";
import { routes as events } from "./routes/events.ts";
import { routes as marks } from "./routes/marks.ts";
import { routes as updates } from "./routes/updates.ts";
import { routes as accounts } from "./routes/accounts.ts";
import { routes as slack } from "./routes/slack.ts";
import { routes as hub } from "./routes/hub.ts";
import { routes as deviceTools } from "./routes/tools.ts";
import { routes as links } from "./routes/links.ts";
import type { AgentsParts } from "../sessions/agents.ts";
import type { Store } from "../store/store.ts";
import type { Events } from "./events.ts";
import { Host } from "./host.ts";
import { previewTarget, proxyPreview } from "../jobs/preview.ts";
import type { Clock } from "effect";
import { liveClock } from "../ops/fibers.ts";
import { readOnly } from "../mesh/credential.ts";

/// What a read-only member (a viewer, contract §4) may still ask besides reads: marks of their own (read, kept,
/// dismissed), which change nothing anyone else sees.
const OWN_MARKS = /^\/*threads\/+[^/]+\/+(read|dismissed|closed-card)(?:\/.*)?$/;
/// Reads that send what the client holds (routes/changed.ts), and several reads in one (`batch`).
const READS = /^\/*(changed\/+(chats|threads|sessions)|batch)$/;
/// What a batch may read (POST /batch): the history a client brings onto its device in the background, each a read
/// whose answer is JSON. At most BATCH_MOST of them, BATCH_AT_ONCE at a time.
const BATCHED = [/^\/threads\/\d+\/entries$/, /^\/threads\/\d+$/, /^\/sessions\/[^/]+$/, /^\/sessions\/[^/]+\/timeline$/];
const BATCH_MOST = 64;
const BATCH_AT_ONCE = 4;

/// Whether `r` is one a read-only member may make: reads (GET, HEAD, and a list's changes), and their own marks.
export function readOnlyMay(r: { method: string; path: string }): boolean {
  return r.method === "GET" || r.method === "HEAD" || (r.method === "PUT" && OWN_MARKS.test(r.path)) || (r.method === "POST" && READS.test(r.path));
}

export type Handler = (r: Request, args: string[]) => Promise<Answer>;
export type Route = { method: string; pattern: RegExp; handle: Handler };
/// What a route has to answer with.
export type Tools = {
  /// A read in a reader thread (src/read/ops.ts), answered as JSON; its error as `{error}` with its status.
  read(r: Request, op: string, args: unknown): Promise<Answer>;
  /// The machine's state, shared by GET /host and the events.
  host: Host;
  /// The event streams, once the station's store is open (the write side).
  events?: Events;
  /// Whether that session is there.
  sessionExists(key: string): boolean;
  /// The station's store, for what is written (on this thread); none while the station starts.
  store?: Store;
  /// The hub, the jobs and the rest of the agents' side, for what needs a session run, stopped or changed; none where
  /// there are no agents (tests of reads).
  agents?: AgentsParts;
};

/// What the admin API answers with besides the readers: the write side, once there.
export type AdminDeps = { events?: Events; store?: Store; host?: Host; agents?: AgentsParts; clock?: Clock.Clock };

/// The header a write's key comes in, and how long an answer is kept (once.rs).
const ONCE_KEY = "idempotency-key";
const ONCE_KEEP_MS = 10 * 60_000;
type Kept = { status: number; headers: Record<string, string>; body: Buffer };
/// A key's first write: its answer once there (none: not kept), and when it was kept.
type Slot = { at: number | null; answer: Promise<Kept | null> };

export class Admin {
  private slots = new Map<string, Slot>();
  private routes: Route[];
  private readers: Readers;

  readonly host: Host;

  private deps: AdminDeps;

  constructor(readers: Readers, deps: AdminDeps = {}) {
    this.deps = deps;
    this.readers = readers;
    this.host = deps.host ?? new Host(readers);
    const tools: Tools = {
      read: async (r, op, args) => {
        try {
          return json(200, await this.readers.read(op, args, r.lang));
        } catch (e) {
          return error(e instanceof HttpError ? e.status : 500, (e as Error).message);
        }
      },
      host: this.host,
      events: deps.events,
      sessionExists: (key) => deps.store?.getSession(key) != null,
      store: deps.store,
      agents: deps.agents,
    };
    this.routes = [...chats(tools), ...usage(tools), ...sessions(tools), ...events(tools), ...marks(tools), ...hub(tools), ...links(), ...(deps.agents?.updates ? updates({ updates: deps.agents.updates }) : []),
      ...(deps.agents?.slack && deps.store
        ? slack({
            slack: deps.agents.slack,
            config: deps.agents.config,
            data: deps.agents.config.data,
            store: deps.store,
            hub: () => deps.agents!.hub,
            overview: (viewer, lang) => deps.agents!.overview(viewer, lang),
            place: () => deps.agents!.place(),
            overviewChanged: () => deps.events?.overviewChanged(),
          })
        : []),
      ...(deps.agents?.config ? deviceTools({ config: deps.agents.config, changed: () => deps.events?.overviewChanged() }) : []),
      ...(deps.agents?.accounts ? accounts({ accounts: deps.agents.accounts, sharing: deps.agents.sharing, overview: (r) => deps.agents!.overview(r.viewer, r.lang) }) : []),
      // The station as its settings pages show it.
      ...(deps.agents?.overview ? [{ method: "GET", pattern: /^\/overview$/, handle: async (r: Request) => json(200, JSON.stringify(await deps.agents!.overview(r.viewer, r.lang))) }] : []),
    ];
  }

  async handle(r: Request): Promise<Answer> {
    // Who asks is remembered by name, as the cloud's names (`deps.names`): what chats show of people who wrote.
    if (r.viewer.name !== "") this.readers.names.set(r.viewer.email, r.viewer.name);
    // Someone uses the station: an automatic update waits for a quiet moment.
    this.deps.agents?.updates?.used();
    // A write with a key is done once, however often it is asked (once.rs); the key is the viewer's own.
    const key = Object.entries(r.headers).find(([k]) => k.toLowerCase() === ONCE_KEY)?.[1];
    const keyed = key !== undefined && key !== "" && key.length <= 200 && r.method !== "GET" && r.method !== "HEAD";
    const answer = keyed ? await this.once(`${r.viewer.email}\0${r.path}\0${key}`, () => this.answer(r)) : await this.answer(r);
    // Every answer says this station keeps writes to once.
    answer.headers["stillfail-idempotent"] = "1";
    return answer;
  }

  /// `write`'s answer, or the answer the first write under `key` had (once.rs): while the first is under way the
  /// others wait for it; a 5xx is not kept (the write may not have happened: asked again, it is tried again).
  private async once(key: string, write: () => Promise<Answer>): Promise<Answer> {
    const now = (this.deps.clock ?? liveClock).currentTimeMillisUnsafe();
    for (const [k, slot] of this.slots) if (slot.at !== null && now - slot.at >= ONCE_KEEP_MS) this.slots.delete(k);
    for (;;) {
      const slot = this.slots.get(key);
      if (slot === undefined) break;
      const kept = await slot.answer;
      if (kept !== null) return { status: kept.status, headers: { ...kept.headers }, body: kept.body };
      // The first one's was not kept: this one tries, unless another got there first.
      if (this.slots.get(key) === slot) this.slots.delete(key);
    }
    let settle: (kept: Kept | null) => void = () => {};
    const slot: Slot = { at: null, answer: new Promise<Kept | null>((resolve) => (settle = resolve)) };
    this.slots.set(key, slot);
    let kept: Kept;
    try {
      const answer = await write();
      const parts: Buffer[] = [];
      if (Buffer.isBuffer(answer.body)) parts.push(answer.body);
      else for await (const chunk of answer.body) parts.push(Buffer.from(chunk));
      kept = { status: answer.status, headers: answer.headers, body: Buffer.concat(parts) };
    } catch (e) {
      settle(null);
      this.slots.delete(key);
      throw e;
    }
    if (kept.status < 500) {
      slot.at = (this.deps.clock ?? liveClock).currentTimeMillisUnsafe();
      settle(kept);
    } else {
      settle(null);
      this.slots.delete(key);
    }
    return { status: kept.status, headers: { ...kept.headers }, body: kept.body };
  }

  private async answer(r: Request): Promise<Answer> {
    // A viewer reads: no message sent, nothing changed (previews included).
    if (readOnly(r.viewer) && !readOnlyMay(r)) return error(403, "read-only members cannot change this station");
    if (r.method === "POST" && /^\/*batch$/.test(r.path)) return this.batch(r);
    // A web service on this machine, through its preview's path: any method, its answer as it comes.
    const preview = previewTarget(r.path);
    if (preview !== null) {
      const [port, target] = preview;
      const headers = Object.entries(r.headers).map(([k, v]): [string, string] => [k.toLowerCase(), v]);
      const answer = await proxyPreview(r.method, headers, r.body.length > 0 ? r.body : null, port, target + (r.search ?? ""), r.lang);
      const joined: Record<string, string> = {};
      for (const [name, value] of answer.headers) joined[name] = name in joined ? `${joined[name]}, ${value}` : value;
      return { status: answer.status, headers: joined, body: answer.body };
    }
    for (const route of this.routes) {
      const found = r.method === route.method ? route.pattern.exec(r.path) : null;
      if (found) return route.handle(r, found.slice(1));
    }
    return error(404, `no route ${r.method} ${r.path}`);
  }

  /// Several reads in one (POST /batch `{ gets }`, each a path with its query): each answered as its GET is, all in one
  /// answer, `{ answers: [{ status, body }] }` in their order, and compressed as one. A client brings a station's history
  /// onto its device so in the background: a read a request, a new device made some 500 of them for one station, each
  /// compressed on its own (and not at all under 512 bytes). Only the reads in BATCHED.
  private async batch(r: Request): Promise<Answer> {
    if (r.body.length > 1_000_000) return error(413, "request too large");
    let gets: unknown;
    try {
      gets = (JSON.parse(r.body.toString("utf8")) as { gets?: unknown }).gets;
    } catch {
      gets = undefined;
    }
    if (!Array.isArray(gets) || gets.length > BATCH_MOST || gets.some((g) => typeof g !== "string")) return error(400, `gets: at most ${BATCH_MOST} paths to read`);
    const paths = gets as string[];
    const answers: string[] = [];
    let next = 0;
    const work = async () => {
      for (let i = next++; i < paths.length; i = next++) {
        const at = paths[i]!.indexOf("?");
        const path = at < 0 ? paths[i]! : paths[i]!.slice(0, at);
        const a = BATCHED.some((p) => p.test(path))
          ? await this.answer({ ...r, method: "GET", path, query: at < 0 ? [] : queryPairs(paths[i]!.slice(at + 1)), search: at < 0 ? "" : paths[i]!.slice(at), body: Buffer.alloc(0) })
          : error(400, `not read in a batch: ${path}`);
        const text = Buffer.isBuffer(a.body) ? a.body.toString("utf8") : "";
        const isJson = Buffer.isBuffer(a.body) && (a.headers["content-type"] ?? "").startsWith("application/json") && text !== "";
        answers[i] = `{"status":${a.status},"body":${isJson ? text : JSON.stringify(text)}}`;
      }
    };
    await Promise.all(Array.from({ length: Math.min(BATCH_AT_ONCE, paths.length) }, work));
    return json(200, `{"answers":[${answers.join(",")}]}`);
  }
}
