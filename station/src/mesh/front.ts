// The station's endpoint kept by the MoonBit front (station/mb's src/front/mesh.mbt) instead of this process: what
// `Mesh.bind` gives is asked of it on its Unix socket, a JSON object a line both ways, and each stream comes as a Unix
// socket of its own to this process's (its head the connection's id and the stream's), carried by the front's shell between iroh and
// that socket (client/shell's `istream.pipe`), those the other end opens given as they come: what comes as frames, a length (4 bytes, big-endian) then the bytes, its
// end or what failed it as a frame of its own; what is written the same, its end finishing the stream. The front keeps
// the endpoint across this process's handovers: the next one binds the same, and the devices' connections come to it.
//
// What the addon answers at once of a connection (how it runs, its ways, what went over it) is what the front said
// last, asked again as it is read: a log line or a storm's count a read behind. The rest is as the addon's.
import { rm } from "node:fs/promises";
import { type Server, type Socket, connect, createServer } from "node:net";
import { dirname, join } from "node:path";
import { createInterface } from "node:readline";
import { log } from "../ops/log.ts";
import { wall } from "../ops/fibers.ts";
import type { Addr, Connection, Endpoint, Mesh, Stream, Traffic } from "./native.ts";

/// What frames say besides a length (client/shell's PIPE_END, PIPE_FAILED); the longest a frame written here is.
const END = 0xffff_fffe;
const FAILED = 0xffff_fffd;
const FRAME_MOST = 1 << 20;

type Path = NonNullable<ReturnType<NonNullable<Connection["paths"]>>>[number];
type Seen = { conn: number; remote: string; alpn: string; via: string | null; paths: Path[]; stats: Traffic };

/// `mesh`, its endpoint the front's at `socket`.
export function withFront(mesh: Mesh, socket: string): Mesh {
  return { ...mesh, bind: (options) => FrontEndpoint.bind(socket, options) };
}

let opened = 0;

/// One process's link to the front: its asks and answers, and the streams it is given.
export class Front {
  readonly #control: Socket;
  readonly #server: Server;
  readonly streamsPath: string;
  #next = 0;
  readonly #asked = new Map<number, { resolve(v: any): void; reject(e: Error): void }>();
  /// Streams whose socket came before what asked for them was answered, and asks answered before their socket came.
  readonly #sockets = new Map<number, { conn: number; socket: Socket; carry: Buffer }>();
  readonly #wanted = new Map<number, { conn: number; resolve(s: { socket: Socket; carry: Buffer }): void; reject(e: Error): void }>();
  /// The streams each connection's other end opened, in the order it opened them, till they are taken (`acceptBi`).
  readonly #incoming = new Map<number, Incoming>();
  /// Every stream's socket open: closed with the endpoint, or ended with its connection when `forget` runs.
  readonly #open = new Set<Socket>();
  readonly #connSockets = new Map<number, Set<Socket>>();
  readonly #forgotten = new Set<number>();
  #gone: Error | null = null;
  /// Once the link is gone (the front ended, or it was closed here).
  readonly gone: Promise<void>;
  #wentAway!: () => void;

  private constructor(control: Socket, server: Server, streamsPath: string) {
    this.#control = control;
    this.#server = server;
    this.streamsPath = streamsPath;
    this.gone = new Promise((resolve) => (this.#wentAway = resolve));
    const end = () => this.#end(new Error("the front is gone"));
    createInterface({ input: control })
      .on("error", end)
      .on("line", (line) => {
        let said: { id: number; ok?: unknown; error?: string };
        try { said = JSON.parse(line); }
        catch { return void log.warn("mesh", "the front said what is not JSON", { line: line.slice(0, 200) }); }
        const asked = this.#asked.get(said.id);
        if (!asked) return;
        this.#asked.delete(said.id);
        if (said.error !== undefined) asked.reject(new Error(said.error));
        else asked.resolve(said.ok);
      });
    control.on("close", end);
    control.on("error", end);
    server.on("connection", (s) => this.#took(s));
  }

  static async open(socket: string): Promise<Front> {
    // (one each time this process binds: a test binds as two Nodes would)
    const streamsPath = join(dirname(socket), `mesh-${process.pid}-${++opened}.sock`);
    await rm(streamsPath, { force: true });
    const server = createServer({ allowHalfOpen: true });
    // what the front gives this process its streams on
    await new Promise<void>((resolve, reject) => server.once("error", reject).listen(streamsPath, () => resolve())); // a Unix socket, by its path
    const control = await new Promise<Socket>((resolve, reject) => {
      const s = connect(socket);
      s.once("connect", () => resolve(s)).once("error", reject);
    });
    return new Front(control, server, streamsPath);
  }

  /// An ask; `id` is told its number as it is sent (what gives it up names it).
  ask(op: string, args: Record<string, unknown> = {}, id?: (n: number) => void): Promise<any> {
    if (this.#gone) return Promise.reject(this.#gone);
    const n = ++this.#next;
    id?.(n);
    return new Promise((resolve, reject) => {
      this.#asked.set(n, { resolve, reject });
      this.#control.write(JSON.stringify({ id: n, op, ...args }) + "\n");
    });
  }

  /// The streams the other end of connection `conn` opens.
  incomingOf(conn: number): Incoming {
    let i = this.#incoming.get(conn);
    if (!i) this.#incoming.set(conn, (i = new Incoming()));
    return i;
  }

  /// A connection gone: the streams it had and nobody took with it, plus half-open sockets still on its side.
  forget(conn: number) {
    this.#forgotten.add(conn);
    if (this.#forgotten.size > 1024) this.#forgotten.delete(this.#forgotten.values().next().value!);
    this.#incoming.get(conn)?.end();
    this.#incoming.delete(conn);
    const sockets = this.#connSockets.get(conn);
    if (sockets) {
      this.#connSockets.delete(conn);
      for (const s of sockets) s.end();
    }
    for (const [id, w] of this.#wanted) {
      if (w.conn !== conn) continue;
      this.#wanted.delete(id);
      w.reject(new Error("the connection is closed"));
    }
    for (const [id, s] of this.#sockets) {
      if (s.conn !== conn) continue;
      this.#sockets.delete(id);
      s.socket.destroy();
    }
  }

  /// The socket of stream `id`, once it came.
  socketOf(id: number, conn: number): Promise<{ socket: Socket; carry: Buffer }> {
    const came = this.#sockets.get(id);
    if (came) {
      this.#sockets.delete(id);
      return Promise.resolve({ socket: came.socket, carry: came.carry });
    }
    if (this.#gone) return Promise.reject(this.#gone);
    if (this.#forgotten.has(conn)) return Promise.reject(new Error("the connection is closed"));
    return new Promise((resolve, reject) => this.#wanted.set(id, { conn, resolve, reject }));
  }

  #took(socket: Socket) {
    this.#open.add(socket);
    socket.once("close", () => this.#open.delete(socket));
    let head = Buffer.alloc(0);
    const first = (data: Buffer) => {
      head = Buffer.concat([head, data]);
      // The connection's id and the stream's, then 1 (one this process opened), 0 (the other end's, from a front
      // before the order) or 2 (the other end's, with its index on the connection: 8 more bytes).
      if (head.length < 17 || (head[16] === 2 && head.length < 25)) return;
      socket.off("data", first);
      socket.pause();
      const conn = Number(head.readBigUInt64BE(0));
      const id = Number(head.readBigUInt64BE(8));
      if (this.#forgotten.has(conn)) {
        socket.destroy();
        return;
      }
      let byConn = this.#connSockets.get(conn);
      if (!byConn) this.#connSockets.set(conn, (byConn = new Set()));
      byConn.add(socket);
      socket.once("close", () => {
        byConn.delete(socket);
        if (byConn.size === 0) this.#connSockets.delete(conn);
      });
      if (head[16] === 2) return void this.incomingOf(conn).give({ socket, carry: head.subarray(25), id, index: Number(head.readBigUInt64BE(17)) });
      const came = { socket, carry: head.subarray(17), id };
      if (head[16] === 0) return void this.incomingOf(conn).give(came);
      const wanted = this.#wanted.get(id);
      if (wanted) {
        this.#wanted.delete(id);
        wanted.resolve({ socket: came.socket, carry: came.carry });
      } else this.#sockets.set(id, { conn, socket: came.socket, carry: came.carry });
    };
    socket.on("data", first);
    socket.on("error", () => {});
  }

  #end(error: Error) {
    if (this.#gone) return;
    this.#gone = error;
    this.#wentAway();
    for (const a of this.#asked.values()) a.reject(error);
    this.#asked.clear();
    for (const w of this.#wanted.values()) w.reject(error);
    this.#wanted.clear();
    for (const i of this.#incoming.values()) i.end();
    this.#incoming.clear();
    for (const socket of this.#open) socket.destroy();
    this.#open.clear();
    this.#connSockets.clear();
    this.#forgotten.clear();
    this.#sockets.clear();
    this.#server.close();
    void rm(this.streamsPath, { force: true });
  }

  close() {
    this.#control.end();
    this.#end(new Error("the endpoint is closed"));
  }
}

type Came = { socket: Socket; carry: Buffer; id: number };

/// What a connection's other end opened, taken in turn in the order it opened them; none once the connection is gone.
/// The front hands each stream on a socket of its own, so they come here in any order: one with its index (`index`)
/// waits for those before it (a device opens its credential stream first and its requests at once after it, which
/// taken first were refused as a credential, 2026-11-13). One from a front before the index goes as it came.
export class Incoming {
  readonly #came: Came[] = [];
  /// Those that came before one opened ahead of them, by index; the index the next to be taken has.
  readonly #early = new Map<number, Came>();
  #nextIndex = 0;
  #taker: ((s: Came | null) => void) | null = null;
  #ended = false;

  give(s: Came & { index?: number }) {
    if (this.#ended) return void s.socket.destroy();
    if (s.index === undefined) return this.#put(s);
    if (s.index !== this.#nextIndex) return void this.#early.set(s.index, s);
    this.#put(s);
    for (let next = this.#early.get(++this.#nextIndex); next; next = this.#early.get(++this.#nextIndex)) {
      this.#early.delete(this.#nextIndex);
      this.#put(next);
    }
  }

  #put(s: Came) {
    const taker = this.#taker;
    if (taker) {
      this.#taker = null;
      taker(s);
    } else this.#came.push(s);
  }

  take(): Promise<Came | null> {
    const next = this.#came.shift();
    if (next) return Promise.resolve(next);
    if (this.#ended) return Promise.resolve(null);
    return new Promise((resolve) => (this.#taker = resolve));
  }

  end() {
    this.#ended = true;
    for (const s of this.#came.splice(0)) s.socket.destroy();
    for (const s of this.#early.values()) s.socket.destroy();
    this.#early.clear();
    const taker = this.#taker;
    this.#taker = null;
    taker?.(null);
  }
}

/// A stream the front gave this process: its socket, frames each way.
class FrontStream implements Stream {
  readonly #front: Front;
  readonly #id: number;
  readonly #socket: Socket;
  /// Bi (a stream both ways): `stopped` answers null where the addon's does on a stream gone; one way, it fails.
  readonly #both: boolean;
  /// What came of a frame's head (or of what failed the stream) and is not whole yet; the bytes of the frame coming
  /// still to come, each given as it comes (a frame is not waited for whole: a frame read in pieces was put together
  /// again with every piece).
  #head: Buffer = Buffer.alloc(0);
  #left = 0;
  readonly #frames: (Buffer | null | Error)[] = [];
  #reader: ((f: Buffer | null | Error) => void) | null = null;
  #over = false;
  #reset = false;

  constructor(front: Front, id: number, came: { socket: Socket; carry: Buffer }, both: boolean) {
    this.#front = front;
    this.#id = id;
    this.#socket = came.socket;
    this.#both = both;
    const carry = came.carry;
    this.#socket.on("data", (d) => {
      this.#parse(d);
    });
    this.#socket.on("end", () => {
      // A send-only stream has no read side, so its normal EOF must not close its write side.
      if (this.#both && !this.#over && !this.#socket.writableEnded) this.#socket.end();
      this.#came(new Error("the stream's way to the front ended"));
    });
    this.#socket.on("close", () => this.#came(new Error("the stream's way to the front ended")));
    this.#parse(carry);
    this.#socket.resume();
  }

  #parse(d: Buffer) {
    while (!this.#over && d.length > 0) {
      if (this.#left > 0) {
        const take = Math.min(this.#left, d.length);
        this.#give(d.subarray(0, take));
        this.#left -= take;
        d = d.subarray(take);
        continue;
      }
      const head = this.#head.length === 0 ? d : Buffer.concat([this.#head, d]);
      if (head.length < 4) return void (this.#head = Buffer.from(head));
      const n = head.readUInt32BE(0);
      if (n === END) {
        this.#head = Buffer.alloc(0);
        return this.#came(null);
      }
      if (n === FAILED) {
        if (head.length < 8 || head.length < 8 + head.readUInt32BE(4)) return void (this.#head = Buffer.from(head));
        this.#head = Buffer.alloc(0);
        return this.#came(new Error(head.toString("utf8", 8, 8 + head.readUInt32BE(4))));
      }
      this.#head = Buffer.alloc(0);
      this.#left = n;
      d = head.subarray(4);
    }
  }


  /// Its end (null) or what failed it: the last of what it gives.
  #came(last: null | Error) {
    if (this.#over) return;
    this.#over = true;
    this.#give(last);
  }

  #give(f: Buffer | null | Error) {
    const reader = this.#reader;
    if (reader) {
      this.#reader = null;
      reader(f);
    } else this.#frames.push(f);
  }

  read(): Promise<Buffer | null> {
    if (this.#reset) return Promise.resolve(null);
    const f = this.#frames.length > 0 ? this.#frames.shift()! : undefined;
    const took = (f: Buffer | null | Error) => {
      if (this.#reset) return null;
      if (f instanceof Error) throw f;
      return f;
    };
    if (f !== undefined) return Promise.resolve().then(() => took(f));
    return new Promise<Buffer | null | Error>((resolve) => (this.#reader = resolve)).then(took);
  }

  async write(bytes: Buffer): Promise<void> {
    for (let at = 0; at < bytes.length || (at === 0 && bytes.length === 0); at += FRAME_MOST) {
      const piece = bytes.subarray(at, at + FRAME_MOST);
      if (piece.length === 0) return;
      const head = Buffer.alloc(4);
      head.writeUInt32BE(piece.length);
      await this.#send(Buffer.concat([head, piece]));
    }
  }

  async finish(): Promise<void> {
    const end = Buffer.alloc(4);
    end.writeUInt32BE(END);
    await this.#send(end);
    this.#socket.end();
  }

  #send(bytes: Buffer): Promise<void> {
    return new Promise((resolve, reject) => {
      if (this.#socket.destroyed || this.#socket.writableEnded) return reject(new Error(this.#reset ? "the stream was reset" : "the stream is gone"));
      this.#socket.write(bytes, (error) => (error ? reject(error) : resolve()));
    });
  }

  async stopped(): Promise<number | null> {
    try {
      const said = await this.#front.ask("stopped", { stream: this.#id });
      return typeof said?.code === "number" ? said.code : null;
    } catch (e) {
      if (this.#both) return null;
      throw e;
    }
  }

  async reset(code: number): Promise<void> {
    this.#reset = true;
    const reader = this.#reader;
    this.#reader = null;
    reader?.(null);
    await this.#front.ask("reset", { stream: this.#id, code }).catch(() => {});
    this.#socket.destroy();
  }
}

/// A connection the front has for this process.
class FrontConnection implements Connection {
  readonly #front: Front;
  readonly #id: number;
  readonly #remote: string;
  readonly #alpn: Buffer;
  #seen: Seen;
  #asking = false;
  #closed: { kind: string; reason: string; text?: string } | null = null;
  readonly #ended: Promise<string>;
  /// The streams its other end opens.
  readonly #incoming: Incoming;

  constructor(front: Front, seen: Seen) {
    this.#front = front;
    this.#incoming = front.incomingOf(seen.conn);
    this.#id = seen.conn;
    this.#remote = seen.remote;
    this.#alpn = Buffer.from(seen.alpn, "hex");
    this.#seen = seen;
    this.#ended = front.ask("conn.closed", { conn: this.#id }).then(
      (info) => {
        this.#closed = info;
        front.forget(this.#id);
        return info?.text ?? info?.reason ?? "closed";
      },
      (e: Error) => {
        this.#closed ??= { kind: "other", reason: e.message };
        return e.message;
      },
    );
  }

  /// What the front says of it now, asked as what it said last is read.
  #again() {
    if (this.#asking || this.#closed) return;
    this.#asking = true;
    this.#front.ask("conn.seen", { conn: this.#id }).then(
      (seen: Seen) => { this.#seen = seen; },
      () => {},
    ).finally(() => (this.#asking = false));
  }

  remoteId() { return this.#remote; }
  alpn() { return this.#alpn; }
  via() {
    this.#again();
    return this.#seen.via;
  }
  paths() {
    this.#again();
    return this.#seen.paths;
  }
  stats() {
    this.#again();
    return this.#seen.stats;
  }

  async #stream(op: "openBi" | "openUni"): Promise<FrontStream | null> {
    const said = await this.#front.ask(op, { conn: this.#id });
    if (said?.end) return null;
    const id = Number(said.stream);
    return new FrontStream(this.#front, id, await this.#front.socketOf(id, this.#id), op !== "openUni");
  }

  async acceptBi() {
    const came = await this.#incoming.take();
    return came ? new FrontStream(this.#front, came.id, came, true) : null;
  }
  async openBi() { return (await this.#stream("openBi"))!; }
  async openUni() { return (await this.#stream("openUni"))!; }
  answers(withinMs: number): Promise<boolean> {
    return this.#front.ask("conn.answers", { conn: this.#id, within: withinMs }).then((v) => v === true, () => false);
  }
  close(code: number, reason: string) {
    this.#closed ??= { kind: "local", reason: "" };
    void this.#front.ask("conn.close", { conn: this.#id, code, reason }).catch(() => {});
  }
  isClosed() { return this.#closed !== null; }
  closed() { return this.#ended; }
}

/// The station's endpoint at the front, its link to it made again where it went (the front ended, and the launcher
/// started another: front.rs): bound again as it was, what it accepts from then on the new link's. Connections made on
/// the link that went went with it.
class FrontEndpoint implements Endpoint {
  readonly #socket: string;
  readonly #bind: Record<string, unknown>;
  #front: Front;
  #said: { id: string; sockets: string[] };
  #relays: { url: string; connected: boolean }[] = [];
  #asking = false;
  #closed = false;
  /// The link made again, once it is.
  #again: Promise<void> | null = null;

  private constructor(socket: string, bind: Record<string, unknown>, front: Front, said: { id: string; sockets: string[] }) {
    this.#socket = socket;
    this.#bind = bind;
    this.#front = front;
    this.#said = said;
  }

  static async bind(socket: string, options: Parameters<Mesh["bind"]>[0]): Promise<FrontEndpoint> {
    const bind = {
      key: hex(options.secretKey),
      options: {
        alpns: options.alpns.map(hex),
        relayUrls: options.relayUrls,
        // (the addon finds and is found unless told not to)
        discovery: options.discovery !== false,
        ...(options.dht === false ? { dht: false } : {}),
        ...(options.bindAddr ? { bindAddr: options.bindAddr } : {}),
        ...(options.relayOnly ? { relayOnly: true } : {}),
        ...(options.congestion ? { congestion: options.congestion } : {}),
      },
    };
    const { front, said } = await FrontEndpoint.#link(socket, bind);
    const endpoint = new FrontEndpoint(socket, bind, front, said);
    endpoint.#relays = await front.ask("relayStatus").catch(() => []);
    endpoint.#watch(front);
    return endpoint;
  }

  static async #link(socket: string, bind: Record<string, unknown>) {
    const front = await Front.open(socket);
    try {
      const said = await front.ask("bind", { streams: front.streamsPath, ...bind });
      return { front, said };
    } catch (e) {
      front.close();
      throw e;
    }
  }

  /// The link gone while the endpoint is open: made again, a while after each try that fails.
  #watch(front: Front) {
    void front.gone.then(() => {
      if (this.#closed || this.#front !== front) return;
      log.warn("mesh", "the front is gone; linking to it again");
      this.#again = (async () => {
        for (let wait = 250; !this.#closed; wait = Math.min(wait * 2, 8000)) {
          await wall.sleep(wait); // timer: a retry after a failure, with a backoff
          try {
            const { front: next, said } = await FrontEndpoint.#link(this.#socket, this.#bind);
            if (this.#closed) return next.close();
            this.#front = next;
            this.#said = said;
            this.#watch(next);
            log.info("mesh", "linked to the front again", { station: said.id });
            return;
          } catch (e) {
            log.warn("mesh", "the front not reached", { error: (e as Error).message, again: `${Math.min(wait * 2, 8000)} ms` });
          }
        }
      })().finally(() => (this.#again = null));
    });
  }

  #ask(op: string, args: Record<string, unknown> = {}) {
    return this.#front.ask(op, args);
  }

  id() { return this.#said.id; }
  sockets() { return this.#said.sockets; }
  online() { return this.#ask("online").then(() => {}); }
  home() {
    this.#relaysAgain();
    return this.#relays[0]?.url ?? null;
  }
  relayStatus() {
    this.#relaysAgain();
    return this.#relays;
  }
  #relaysAgain() {
    if (this.#asking) return;
    this.#asking = true;
    this.#ask("relayStatus").then((r) => { this.#relays = r; }, () => {}).finally(() => (this.#asking = false));
  }
  insertRelay(url: string) { return this.#ask("insertRelay", { args: { url } }).then(() => {}); }
  removeRelay(url: string) { return this.#ask("removeRelay", { args: { url } }).then(() => {}); }
  publicRelays(on: boolean) { return this.#ask("publicRelays", { args: { on } }).then(() => {}); }
  keep(urls: string[]) { void this.#ask("keep", { args: { urls } }).catch((e) => log.warn("mesh", "relays not kept", { error: (e as Error).message })); }
  setCongestion(congestion: "cubic" | "bbr") { void this.#ask("setCongestion", { args: { congestion } }).catch(() => {}); }
  holdIncoming(n: number) { void this.#ask("holdIncoming", { args: { n } }).catch(() => {}); }
  addAddr(addr: Addr) { void this.#ask("addAddr", { addr }).catch(() => {}); }
  setRelayEntries(entries: { entry: string; relay: string }[]) { return this.#ask("setRelayEntries", { args: { entries } }).then(() => {}); }
  networkChange() { return this.#ask("networkChange").then(() => {}); }

  async accept(): Promise<Connection | null> {
    for (;;) {
      const front = this.#front;
      const said = await front.ask("accept").catch(() => ({ end: true }));
      if (!said?.end) return new FrontConnection(front, said);
      // its link gone: the next connection comes on the link made again
      if (this.#closed) return null;
      if (this.#again) await this.#again;
      else if (this.#front === front) await front.gone;
      if (this.#closed) return null;
    }
  }

  async connect(addr: Addr, alpn: Buffer, additional?: Buffer[], givenUp?: Promise<void>): Promise<Connection> {
    const front = this.#front;
    let asked = 0;
    void givenUp?.then(() => front.ask("giveUp", { of: asked }).catch(() => {}));
    const seen = await front.ask("connect", { addr, alpn: hex(alpn), additional: (additional ?? []).map(hex) }, (n) => (asked = n));
    return new FrontConnection(front, seen);
  }

  async close() {
    this.#closed = true;
    await this.#front.ask("close").catch(() => {});
    this.#front.close();
  }
}

const hex = (b: Buffer) => Buffer.from(b).toString("hex");
