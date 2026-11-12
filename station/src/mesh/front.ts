// The station's endpoint kept by the MoonBit front (station/mb's src/front/mesh.mbt) instead of this process: what
// `Mesh.bind` gives is asked of it on its Unix socket, a JSON object a line both ways, and each stream comes as a Unix
// socket of its own to this process's (its first 8 bytes the stream's id), carried by the front's shell between iroh and
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
import type { Addr, Connection, Endpoint, Mesh, Stream, Traffic } from "./native.ts";

/// What frames say besides a length (client/shell's PIPE_END, PIPE_FAILED); the longest a frame written here is.
const END = 0xffff_fffe;
const FAILED = 0xffff_fffd;
const FRAME_MOST = 1 << 20;

type Path = NonNullable<ReturnType<NonNullable<Connection["paths"]>>>[number];
type Seen = { conn: number; remote: string; alpn: string; via: string | null; paths: Path[]; stats: Traffic };

/// `mesh`, its endpoint the front's at `socket`.
export function withFront(mesh: Mesh, socket: string): Mesh {
  return { ...mesh, bind: (options) => bindFront(socket, options) };
}

let opened = 0;

/// One process's link to the front: its asks and answers, and the streams it is given.
class Front {
  readonly #control: Socket;
  readonly #server: Server;
  readonly streamsPath: string;
  #next = 0;
  readonly #asked = new Map<number, { resolve(v: any): void; reject(e: Error): void }>();
  /// Streams whose socket came before what asked for them was answered, and asks answered before their socket came.
  readonly #sockets = new Map<number, { socket: Socket; carry: Buffer }>();
  readonly #wanted = new Map<number, (s: { socket: Socket; carry: Buffer }) => void>();
  /// The streams each connection's other end opened, as they came, till they are taken (`acceptBi`).
  readonly #incoming = new Map<number, Incoming>();
  /// Every stream's socket open: closed with the endpoint (each a stream of a connection closed with it).
  readonly #open = new Set<Socket>();
  #gone: Error | null = null;

  private constructor(control: Socket, server: Server, streamsPath: string) {
    this.#control = control;
    this.#server = server;
    this.streamsPath = streamsPath;
    createInterface({ input: control }).on("line", (line) => {
      let said: { id: number; ok?: unknown; error?: string };
      try { said = JSON.parse(line); }
      catch { return void log.warn("mesh", "the front said what is not JSON", { line: line.slice(0, 200) }); }
      const asked = this.#asked.get(said.id);
      if (!asked) return;
      this.#asked.delete(said.id);
      if (said.error !== undefined) asked.reject(new Error(said.error));
      else asked.resolve(said.ok);
    });
    const end = () => this.#end(new Error("the front is gone"));
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

  /// A connection gone: the streams it had and nobody took with it.
  forget(conn: number) {
    this.#incoming.get(conn)?.end();
    this.#incoming.delete(conn);
  }

  /// The socket of stream `id`, once it came.
  socketOf(id: number): Promise<{ socket: Socket; carry: Buffer }> {
    const came = this.#sockets.get(id);
    if (came) {
      this.#sockets.delete(id);
      return Promise.resolve(came);
    }
    if (this.#gone) return Promise.reject(this.#gone);
    return new Promise((resolve) => this.#wanted.set(id, resolve));
  }

  #took(socket: Socket) {
    this.#open.add(socket);
    socket.once("close", () => this.#open.delete(socket));
    let head = Buffer.alloc(0);
    const first = (data: Buffer) => {
      head = Buffer.concat([head, data]);
      if (head.length < 17) return;
      socket.off("data", first);
      socket.pause();
      const conn = Number(head.readBigUInt64BE(0));
      const id = Number(head.readBigUInt64BE(8));
      const came = { socket, carry: head.subarray(17), id };
      if (head[16] === 0) return void this.incomingOf(conn).give(came);
      const wanted = this.#wanted.get(id);
      if (wanted) {
        this.#wanted.delete(id);
        wanted(came);
      } else this.#sockets.set(id, came);
    };
    socket.on("data", first);
    socket.on("error", () => {});
  }

  #end(error: Error) {
    if (this.#gone) return;
    this.#gone = error;
    for (const a of this.#asked.values()) a.reject(error);
    this.#asked.clear();
    for (const i of this.#incoming.values()) i.end();
    this.#incoming.clear();
    for (const socket of this.#open) socket.destroy();
    this.#open.clear();
    this.#sockets.clear();
    this.#server.close();
    void rm(this.streamsPath, { force: true });
  }

  close() {
    this.#control.end();
    this.#end(new Error("the endpoint is closed"));
  }
}

/// What a connection's other end opened, as it came: taken in turn; none once the connection is gone.
class Incoming {
  readonly #came: { socket: Socket; carry: Buffer; id: number }[] = [];
  #taker: ((s: { socket: Socket; carry: Buffer; id: number } | null) => void) | null = null;
  #ended = false;

  give(s: { socket: Socket; carry: Buffer; id: number }) {
    if (this.#ended) return void s.socket.destroy();
    const taker = this.#taker;
    if (taker) {
      this.#taker = null;
      taker(s);
    } else this.#came.push(s);
  }

  take(): Promise<{ socket: Socket; carry: Buffer; id: number } | null> {
    const next = this.#came.shift();
    if (next) return Promise.resolve(next);
    if (this.#ended) return Promise.resolve(null);
    return new Promise((resolve) => (this.#taker = resolve));
  }

  end() {
    this.#ended = true;
    for (const s of this.#came.splice(0)) s.socket.destroy();
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
  #buffer: Buffer;
  readonly #frames: (Buffer | null | Error)[] = [];
  #reader: ((f: Buffer | null | Error) => void) | null = null;
  #over = false;
  #reset = false;

  constructor(front: Front, id: number, came: { socket: Socket; carry: Buffer }, both: boolean) {
    this.#front = front;
    this.#id = id;
    this.#socket = came.socket;
    this.#both = both;
    this.#buffer = came.carry;
    this.#socket.on("data", (d) => {
      this.#buffer = this.#buffer.length === 0 ? d : Buffer.concat([this.#buffer, d]);
      this.#parse();
    });
    this.#socket.on("end", () => this.#came(new Error("the stream's way to the front ended")));
    this.#socket.on("close", () => this.#came(new Error("the stream's way to the front ended")));
    this.#parse();
    this.#socket.resume();
  }

  #parse() {
    while (!this.#over && this.#buffer.length >= 4) {
      const n = this.#buffer.readUInt32BE(0);
      if (n === END) {
        this.#came(null);
      } else if (n === FAILED) {
        if (this.#buffer.length < 8) return;
        const len = this.#buffer.readUInt32BE(4);
        if (this.#buffer.length < 8 + len) return;
        this.#came(new Error(this.#buffer.toString("utf8", 8, 8 + len)));
      } else {
        if (this.#buffer.length < 4 + n) return;
        const frame = this.#buffer.subarray(4, 4 + n);
        this.#buffer = this.#buffer.subarray(4 + n);
        this.#give(frame);
      }
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
    return new FrontStream(this.#front, id, await this.#front.socketOf(id), op !== "openUni");
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

async function bindFront(socket: string, options: Parameters<Mesh["bind"]>[0]): Promise<Endpoint> {
  const front = await Front.open(socket);
  const hex = (b: Buffer) => Buffer.from(b).toString("hex");
  const said = await front.ask("bind", {
    streams: front.streamsPath,
    key: hex(options.secretKey),
    options: {
      alpns: options.alpns.map(hex),
      relayUrls: options.relayUrls,
      // (the addon finds and is found unless told not to)
      discovery: options.discovery !== false,
      ...(options.bindAddr ? { bindAddr: options.bindAddr } : {}),
      ...(options.relayOnly ? { relayOnly: true } : {}),
      ...(options.congestion ? { congestion: options.congestion } : {}),
    },
  }).catch((e) => {
    front.close();
    throw e;
  });
  let relays: { url: string; connected: boolean }[] = await front.ask("relayStatus").catch(() => []);
  let asking = false;
  const relaysAgain = () => {
    if (asking) return;
    asking = true;
    front.ask("relayStatus").then((r) => { relays = r; }, () => {}).finally(() => (asking = false));
  };
  const endpoint = {
    id: () => said.id as string,
    sockets: () => said.sockets as string[],
    online: () => front.ask("online").then(() => {}),
    home: () => {
      relaysAgain();
      return relays[0]?.url ?? null;
    },
    relayStatus: () => {
      relaysAgain();
      return relays;
    },
    insertRelay: (url: string) => front.ask("insertRelay", { args: { url } }).then(() => {}),
    removeRelay: (url: string) => front.ask("removeRelay", { args: { url } }).then(() => {}),
    publicRelays: (on: boolean) => front.ask("publicRelays", { args: { on } }).then(() => {}),
    keep: (urls: string[]) => void front.ask("keep", { args: { urls } }).catch((e) => log.warn("mesh", "relays not kept", { error: (e as Error).message })),
    setCongestion: (congestion: "cubic" | "bbr") => void front.ask("setCongestion", { args: { congestion } }).catch(() => {}),
    holdIncoming: (n: number) => void front.ask("holdIncoming", { args: { n } }).catch(() => {}),
    addAddr: (addr: Addr) => void front.ask("addAddr", { addr }).catch(() => {}),
    setRelayEntries: (entries: { entry: string; relay: string }[]) => front.ask("setRelayEntries", { args: { entries } }).then(() => {}),
    networkChange: () => front.ask("networkChange").then(() => {}),
    accept: async (): Promise<Connection | null> => {
      const said = await front.ask("accept").catch(() => ({ end: true }));
      return said?.end ? null : new FrontConnection(front, said);
    },
    connect: async (addr: Addr, alpn: Buffer, additional?: Buffer[], givenUp?: Promise<void>): Promise<Connection> => {
      let asked = 0;
      void givenUp?.then(() => front.ask("giveUp", { of: asked }).catch(() => {}));
      const seen = await front.ask("connect", { addr, alpn: hex(alpn), additional: (additional ?? []).map(hex) }, (n) => (asked = n));
      return new FrontConnection(front, seen);
    },
    close: async () => {
      await front.ask("close").catch(() => {});
      front.close();
    },
  };
  return endpoint;
}
