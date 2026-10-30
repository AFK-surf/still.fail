// The station's parts that are modules of it, in its own process (docs/station-modules.md, 「进程内的模块」): each a
// layer the composition root (main.ts) lists, made after the platform and the agents' side, saying here what it adds to
// what the station answers: its routes of the admin API, the writes a read-only member may make of them, its own kinds
// of request on a member's link, its fields of the overview and its tools for the agents. Nothing registers itself: a part is in the station because main.ts names
// it, and says what it adds as it is made. What is said here is read as it is asked for (a request, an agent's tool
// list), so the admin API and the agents, made before the parts, take what they add.
import type { IncomingMessage, ServerResponse } from "node:http";
import type { Duplex } from "node:stream";
import type { Route, Tools } from "./api/admin.ts";
import type { Connection, Stream } from "./mesh/native.ts";
import type { Reader } from "./mesh/serve.ts";
import type { Lang } from "./ops/i18n.ts";
import { log } from "./ops/log.ts";
import type { Viewer } from "./mesh/credential.ts";
import type { Tool } from "./tools/mcp.ts";

/// A part's place on the agents' door (tools/http.ts): the requests under `/<prefix>/` and their WebSockets, from
/// programs on this machine only (the door refuses the rest before they come here).
export type DoorRoute = {
  prefix: string;
  request(req: IncomingMessage, res: ServerResponse): Promise<void>;
  upgrade(req: IncomingMessage, socket: Duplex, head: Buffer): Promise<void>;
};

/// A request on a member's link a part answers itself (mesh/serve.ts): its stream, the head line it came with (already
/// read, the rest of the stream's bytes in `reader`), the member and their connection.
export type MemberAsk = { conn: Connection; viewer: Viewer; head: any; stream: Stream; reader: Reader };

export class StationParts {
  readonly #routes: (Route[] | ((tools: Tools) => Route[]))[] = [];
  /// The routes as made for an admin API's tools, and how many parts' routes they were made of.
  readonly #made = new WeakMap<Tools, { of: number; routes: Route[] }>();
  readonly #alpns: { alpn: Buffer; serve: (conn: Connection) => Promise<void> }[] = [];
  readonly #viewerMay: ((r: { method: string; path: string }) => boolean)[] = [];
  readonly #overview = new Map<string, (viewer: Viewer, lang: Lang) => unknown>();
  readonly #tools: Tool[] = [];
  readonly #door: DoorRoute[] = [];
  readonly #ended: ((session: string) => void)[] = [];
  readonly #streams = new Map<string, (ask: MemberAsk) => Promise<void>>();
  readonly #connected: (() => void)[] = [];
  readonly #carries = new Map<string, { give: () => unknown; take: (what: any) => void }>();
  /// What the process before carried over, for a part not made yet when it came.
  readonly #came = new Map<string, unknown>();
  #doorUrl: string | null = null;

  /// A part's routes of the admin API (after the platform's own); made with what the admin API's routes are given
  /// (its readers, the store, the events), where they need it.
  routes(routes: Route[] | ((tools: Tools) => Route[])): void {
    this.#routes.push(routes);
  }

  /// A protocol of the station's mesh endpoint a part answers itself (a published chat's visitors, say): its
  /// connections, whoever makes them; it checks what it lets them have.
  alpn(alpn: Buffer, serve: (conn: Connection) => Promise<void>): void {
    this.#alpns.push({ alpn, serve });
  }

  /// A kind of request on a member's link a part answers itself (a phone lent over it, say): one whose head line has an
  /// object under `key` (`{"adb": {…}}`), whatever its path. The part says what the member may.
  streams(key: string, answer: (ask: MemberAsk) => Promise<void>): void {
    if (this.#streams.has(key)) throw new Error(`a member's ${key} requests are answered twice`);
    this.#streams.set(key, answer);
  }

  /// Which of a part's requests besides reads a read-only member may make (their own marks, say).
  viewerMay(may: (r: { method: string; path: string }) => boolean): void {
    this.#viewerMay.push(may);
  }

  /// A field of the overview (GET /overview), as `viewer` sees it; none of the platform's or another part's.
  overview(field: string, view: (viewer: Viewer, lang: Lang) => unknown): void {
    if (this.#overview.has(field)) throw new Error(`the overview's ${field} is said twice`);
    this.#overview.set(field, view);
  }

  /// A part's tools for the agents (their MCP door, tools/mcp.ts).
  tools(tools: Tool[]): void {
    this.#tools.push(...tools);
  }

  /// A part's routes on the agents' door.
  door(route: DoorRoute): void {
    this.#door.push(route);
  }

  /// What a part does when a session is archived or deleted (its chat's things closed with it).
  sessionEnded(ended: (session: string) => void): void {
    this.#ended.push(ended);
  }

  /// What a part does when a member's device connects (an app starting, say).
  memberConnected(connected: () => void): void {
    this.#connected.push(connected);
  }

  /// What a part holds only in memory and carries over to the next process at a handover (an update), never written
  /// down: `give` it as this process hands over, `take` what the process before gave.
  carry<T>(name: string, give: () => T, take: (what: T) => void): void {
    if (this.#carries.has(name)) throw new Error(`${name} is carried over twice`);
    this.#carries.set(name, { give, take });
    if (this.#came.has(name)) {
      const what = this.#came.get(name);
      this.#came.delete(name);
      take(what as T);
    }
  }

  // ── what is asked of them ──

  /// What the parts carry over to the next process, by part.
  carried(): Record<string, unknown> {
    const out: Record<string, unknown> = {};
    for (const [name, { give }] of this.#carries) {
      try {
        out[name] = give();
      } catch (error) {
        log.warn("station", "a part's memory is not carried over", { part: name, error: (error as Error).message });
      }
    }
    return out;
  }

  /// What the process before carried over (`carried`), to its parts.
  takeUp(what: Record<string, unknown>): void {
    for (const [name, value] of Object.entries(what ?? {})) {
      const part = this.#carries.get(name);
      if (part === undefined) this.#came.set(name, value);
      else {
        try {
          part.take(value);
        } catch (error) {
          log.warn("station", "what a part carried over is not taken up", { part: name, error: (error as Error).message });
        }
      }
    }
  }

  /// A member's device connected (mesh/serve.ts).
  connected(): void {
    for (const connected of this.#connected) connected();
  }

  doorRoutes(): readonly DoorRoute[] {
    return this.#door;
  }

  /// Where agents reach the door now (`http://127.0.0.1:<port>/mcp`), once it is open: told by the agents' side.
  doorUrl(): string | null {
    return this.#doorUrl;
  }
  doorOpen(url: string): void {
    this.#doorUrl = url;
  }

  /// A session was archived or deleted.
  endSession(session: string): void {
    for (const ended of this.#ended) ended(session);
  }

  allRoutes(tools: Tools): readonly Route[] {
    let made = this.#made.get(tools);
    if (!made || made.of !== this.#routes.length) {
      made = { of: this.#routes.length, routes: this.#routes.flatMap((r) => (typeof r === "function" ? r(tools) : r)) };
      this.#made.set(tools, made);
    }
    return made.routes;
  }

  /// The part that answers a request whose head line is `head`, if one does.
  streamOf(head: any): ((ask: MemberAsk) => Promise<void>) | undefined {
    for (const [key, answer] of this.#streams) {
      const v = head?.[key];
      if (v !== null && typeof v === "object" && !Array.isArray(v)) return answer;
    }
    return undefined;
  }

  allAlpns(): readonly { alpn: Buffer; serve: (conn: Connection) => Promise<void> }[] {
    return this.#alpns;
  }

  mayView(r: { method: string; path: string }): boolean {
    return this.#viewerMay.some((may) => may(r));
  }

  async overviewOf(viewer: Viewer, lang: Lang): Promise<Record<string, unknown>> {
    const out: Record<string, unknown> = {};
    for (const [field, view] of this.#overview) out[field] = await view(viewer, lang);
    return out;
  }

  allTools(): readonly Tool[] {
    return this.#tools;
  }
}
