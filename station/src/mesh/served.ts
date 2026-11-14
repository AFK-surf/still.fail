// The reads a device asks that the MoonBit program answers itself, not this process (station/mb's reader `--serve`,
// `serve.mbt`): the front hands it each request stream of a route given here (front.ts `route`, client/shell
// `conn.hand`), and it answers as serve.ts and the admin API would, its read in its own snapshot of the database. What
// only this process knows it is told: who each connection's member is, as serve.ts let them in (`viewer`, null once the
// connection is gone or no longer let in), people's names, the words of each language and the floors. It tells this
// process the build each device says (kept as serve.ts keeps it), and gives it what it does not answer itself
// (`fallback`: a read refused for what the pool prepares, a core that does not take every runtime), answered here.
import { sep, join } from "node:path";
import { mkdirSync, rmSync } from "node:fs";
import { tr } from "../ops/i18n.ts";
import { log } from "../ops/log.ts";
import { wall } from "../ops/fibers.ts";
import { MbProcess } from "../read/mb-reader.ts";
import { COUNTED_FROM, OLDEST_CORE, stationBuild } from "../api/oldest.ts";
import { MOVED_FROM_BUILD } from "../api/moved-from.ts";
import { RUNTIME_KINDS } from "../agents/runtime.ts";
import { READS_PENDING } from "../read/pool.ts";

/// The routes answered there (api/routes/chats.ts, sessions.ts), every one a read moved to MoonBit; `*` a segment.
export const SERVED_ROUTES = [
  "GET /admin/api/chats",
  "GET /admin/api/sessions", "GET /admin/api/sessions/*", "GET /admin/api/sessions/*/timeline",
  "GET /admin/api/threads", "GET /admin/api/threads/*", "GET /admin/api/threads/*/entries", "GET /admin/api/threads/*/letters",
  // (several of those in one: admin.ts `batch`, all answered there or the batch given Node)
  "POST /admin/api/batch",
];
/// How many of the program answer at once (each one read at a time, as a reader of the pool's).
const SERVERS = 2;

/// What a request given back is answered with.
export type Handled = { status: number; headers: Record<string, string>; body: Buffer };

type Server = { process: MbProcess; path: string; listening: Promise<void> };

export class Served {
  readonly #binary: string;
  readonly #data: string;
  readonly #answer: (viewer: any, head: any, body: Buffer) => Promise<Handled>;
  readonly #built: (viewer: any, build: number | null) => void;
  #servers: Server[] = [];
  /// What each connection's program is told of it, as said last (said again only as it changes).
  readonly #told = new Map<number, string>();
  readonly #names = new Map<string, string>();
  #closed = false;

  /// `answer`: a request of a connection's member given back, answered as serve.ts answers one; `built`: the build a
  /// connection's device says.
  constructor(binary: string, data: string, answer: (viewer: any, head: any, body: Buffer) => Promise<Handled>, built: (viewer: any, build: number | null) => void) {
    this.#binary = binary;
    this.#data = data;
    this.#answer = answer;
    this.#built = built;
  }

  /// Where the programs listen, once each does.
  async start(): Promise<string[]> {
    for (let i = 0; i < SERVERS; i++) this.#servers.push(this.#start(i));
    await Promise.all(this.#servers.map((s) => s.listening));
    return this.#servers.map((s) => s.path);
  }

  #start(i: number): Server {
    // (this process's own: the next one in a handover has its own, the front giving it the connections it takes)
    const path = join(this.#data, "run", `serve-${process.pid}-${i}.sock`);
    mkdirSync(join(this.#data, "run"), { recursive: true }); // sync: one step before the program listens there
    rmSync(path, { force: true }); // sync: one step before the program listens there
    const child = new MbProcess(this.#binary, ["--data", this.#data, "--sep", sep, "--serve", path]);
    let listened = () => {};
    const listening = new Promise<void>((resolve) => (listened = resolve));
    const server: Server = { process: child, path, listening };
    child.on("message", (said: any) => {
      if (typeof said?.listening === "string") {
        this.#settle(server);
        listened();
      } else if (said?.build !== undefined) {
        const viewer = this.#viewerOf(Number(said.build.conn));
        if (viewer !== null) this.#built(viewer, typeof said.build.build === "number" ? said.build.build : null);
      }
      else if (typeof said?.fallback === "number") void this.#fallback(server, said);
    });
    child.on("error", (error: Error) => log.warn("served", "a serving program failed", { error: error.message }));
    child.on("exit", (code: number) => {
      if (this.#closed) return;
      log.warn("served", "a serving program ended; starting it again", { code });
      const at = this.#servers.indexOf(server);
      // timer: a retry after a failure, with a backoff (one that keeps ending is started again each second at most)
      if (at >= 0) wall.after(1_000, () => { if (!this.#closed) this.#servers[at] = this.#start(i); });
    });
    return server;
  }

  /// A program that listens told all it is to know.
  #settle(server: Server) {
    const words = Object.fromEntries((["zh", "en"] as const).map((lang) => [lang, {
      localPage: tr(lang, "station.creator.localPage"), admin: tr(lang, "station.author.admin"),
      untitled: tr(lang, "station.chat.untitled"), directMessage: tr(lang, "station.chat.directMessage"),
      quotedOnly: tr(lang, "station.chat.quotedOnly"), updateApp: tr(lang, "station.admin.updateApp"),
      notInteger: Object.fromEntries(["after", "before", "from", "to"].map((name) => [name, tr(lang, "station.admin.notInteger", { name })])),
      fromAndTo: tr(lang, "station.admin.fromAndTo"), inScriptOutput: tr(lang, "station.transcript.inScriptOutput"),
    }]));
    server.process.postMessage({
      set: { words, oldestCore: OLDEST_CORE, countedFrom: COUNTED_FROM, movedFromBuild: MOVED_FROM_BUILD, build: stationBuild(), runtimes: RUNTIME_KINDS, pending: READS_PENDING },
      wall: wall.now(),
    });
    if (this.#names.size > 0) server.process.postMessage({ names: [...this.#names] });
    for (const told of this.#told.values()) server.process.postMessage(JSON.parse(told));
  }

  /// Who connection `conn`'s member is now (null: gone, or no longer let in), and whether its workspace's chain moved.
  viewer(conn: number, viewer: { email: string; name?: string } | null, moved = false) {
    if (viewer !== null && viewer.name !== undefined && viewer.name !== "" && this.#names.get(viewer.email) !== viewer.name) {
      this.#names.set(viewer.email, viewer.name);
      this.#tell({ names: [[viewer.email, viewer.name]] });
    }
    const told = JSON.stringify({ viewer: { conn, viewer, moved } });
    if (this.#told.get(conn) === told) return;
    if (viewer === null) this.#told.delete(conn);
    else this.#told.set(conn, told);
    this.#tell({ ...JSON.parse(told), wall: wall.now() });
  }

  /// Connection `conn`'s member as told last; null for none.
  #viewerOf(conn: number): any {
    const told = this.#told.get(conn);
    return told === undefined ? null : JSON.parse(told).viewer.viewer;
  }

  #tell(said: unknown) {
    for (const s of this.#servers) s.process.postMessage(said);
  }

  async #fallback(server: Server, said: { fallback: number; conn: number; head: any; body?: string }) {
    let handled: Handled;
    try {
      const viewer = this.#viewerOf(Number(said.conn));
      handled = viewer === null ? { status: 502, headers: { "content-type": "application/json" }, body: Buffer.from('{"error":"the connection is gone"}') }
        : await this.#answer(viewer, said.head, Buffer.from(said.body ?? ""));
    } catch (e) {
      handled = { status: 500, headers: { "content-type": "application/json" }, body: Buffer.from(JSON.stringify({ error: (e as Error).message })) };
    }
    server.process.postMessage({ answered: said.fallback, status: handled.status, headers: handled.headers, text: handled.body.toString() });
  }

  async close() {
    this.#closed = true;
    await Promise.all(this.#servers.map((s) => s.process.terminate()));
    for (const s of this.#servers) rmSync(s.path, { force: true }); // sync: the station stopping
  }
}
