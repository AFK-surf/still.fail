// The mesh addon's endpoints (src/mesh/native.ts) connected in memory, for tests of what goes over the mesh rather than
// of the mesh: a connection is a pair of ends, a stream a pair of ordered byte queues, nothing lost and nothing waiting
// on real time (QUIC on 127.0.0.1 can lose a connection on a loaded machine). An endpoint's id is its key's public half,
// as iroh's is; connecting finds the endpoint by id, as an address on this machine would.
import { createPrivateKey, createPublicKey } from "node:crypto";
import type { Addr, Connection, Endpoint, Mesh, Stream } from "../src/mesh/native.ts";

/// The ed25519 public key of a 32-byte secret, hex: iroh's endpoint id.
function idOf(secret: Buffer): string {
  const der = Buffer.concat([Buffer.from("302e020100300506032b657004220420", "hex"), secret]);
  const raw = createPublicKey(createPrivateKey({ key: der, format: "der", type: "pkcs8" })).export({ format: "der", type: "spki" });
  return raw.subarray(-32).toString("hex");
}

/// One end of a stream: what it writes, its `peer` reads. `window`: how many unread bytes its peer may hold before a
/// write waits for it to read (QUIC's flow control); 0: no limit.
class End implements Stream {
  peer!: End;
  readonly window: number;
  #queue: (Buffer | null)[] = [];
  /// Bytes in the queue, unread; and the writes waiting for them to be read.
  #queued = 0;
  #room: (() => void)[] = [];
  #error: Error | null = null;
  /// Reset here: a read gives up (null), as the addon's does.
  #reset = false;
  #waiting: (() => void) | null = null;
  #stopped: Promise<void>;
  #stop!: () => void;
  constructor(window = 0) {
    this.window = window;
    this.#stopped = new Promise((r) => (this.#stop = r));
  }
  /// The writes waiting for room in this end's queue go on (to write, or to find the stream failed).
  #free() {
    for (const go of this.#room.splice(0)) go();
  }
  #wake() {
    const w = this.#waiting;
    this.#waiting = null;
    w?.();
  }
  push(b: Buffer | null) {
    this.#queue.push(b);
    if (b !== null) this.#queued += b.length;
    this.#wake();
  }
  fail(e: Error) {
    this.#error ??= e;
    this.#wake();
    this.#stop();
    this.#free();
    if (this.peer !== undefined) this.peer.#free();
  }
  async read(): Promise<Buffer | null> {
    for (;;) {
      if (this.#reset) return null;
      if (this.#queue.length > 0) {
        const b = this.#queue.shift()!;
        // Its end read: the other side's finish is acknowledged.
        if (b === null) this.peer.#stop();
        else {
          this.#queued -= b.length;
          this.#free();
        }
        return b;
      }
      if (this.#error) throw this.#error;
      await new Promise<void>((r) => (this.#waiting = r));
    }
  }
  async write(bytes: Buffer): Promise<void> {
    if (this.#error) throw this.#error;
    while (this.window > 0 && this.peer.#queued >= this.window && !this.peer.#reset) {
      await new Promise<void>((r) => this.peer.#room.push(r));
      if (this.#error) throw this.#error;
    }
    this.peer.push(Buffer.from(bytes));
  }
  async finish(): Promise<void> {
    this.peer.push(null);
  }
  stopped(): Promise<void> {
    return this.#stopped;
  }
  async reset(code: number): Promise<void> {
    this.#reset = true;
    this.#wake();
    this.#stop();
    this.#free();
    this.peer.fail(new Error(`stream reset (${code})`));
  }
}

class Conn implements Connection {
  peer!: Conn;
  /// Its process is gone without a word (killed): it answers nothing, and nothing tells its peer.
  silent = false;
  #incoming: End[] = [];
  #accepting: ((s: End | null) => void) | null = null;
  #ends: End[] = [];
  #reason: string | null = null;
  #closed: Promise<string>;
  #resolve!: (r: string) => void;
  readonly #remote: string;
  readonly #alpn: Buffer;
  readonly #window: number;
  constructor(remote: string, alpn: Buffer, window = 0) {
    this.#remote = remote;
    this.#alpn = alpn;
    this.#window = window;
    this.#closed = new Promise((r) => (this.#resolve = r));
  }
  remoteId(): string {
    return this.#remote;
  }
  alpn(): Buffer {
    return this.#alpn;
  }
  via(): string | null {
    return null;
  }
  #offer(s: End) {
    const take = this.#accepting;
    this.#accepting = null;
    if (take) take(s);
    else this.#incoming.push(s);
  }
  async acceptBi(): Promise<Stream | null> {
    if (this.#incoming.length > 0) return this.#incoming.shift()!;
    if (this.#reason !== null) return null;
    return new Promise((r) => (this.#accepting = r));
  }
  async openBi(): Promise<Stream> {
    if (this.#reason !== null) throw new Error("connection lost");
    const [mine, theirs] = [new End(this.#window), new End(this.#window)];
    mine.peer = theirs;
    theirs.peer = mine;
    this.#ends.push(mine);
    this.peer.#ends.push(theirs);
    this.peer.#offer(theirs);
    return mine;
  }
  gone(reason: string) {
    if (this.#reason !== null) return;
    this.#reason = reason;
    for (const e of this.#ends) e.fail(new Error("connection lost"));
    const take = this.#accepting;
    this.#accepting = null;
    take?.(null);
    this.#resolve(reason);
  }
  close(_code: number, reason: string): void {
    this.gone(reason);
    if (!this.silent) this.peer.gone(reason);
  }
  /// The addon's: whether the other end is still there, at once (nothing here takes time).
  async answers(_withinMs: number): Promise<boolean> {
    return this.#reason === null && !this.peer.silent;
  }
  isClosed(): boolean {
    return this.#reason !== null;
  }
  closed(): Promise<string> {
    return this.#closed;
  }
}

class MemoryEndpoint implements Endpoint {
  readonly #net: Map<string, MemoryEndpoint>;
  readonly #id: string;
  readonly #alpns: Buffer[];
  readonly #port: number;
  readonly #window: number;
  #incoming: Conn[] = [];
  #accepting: ((c: Conn | null) => void) | null = null;
  #conns: Conn[] = [];
  #closed = false;
  constructor(net: Map<string, MemoryEndpoint>, secret: Buffer, alpns: Buffer[], port: number, window = 0) {
    this.#net = net;
    this.#id = idOf(secret);
    this.#alpns = alpns;
    this.#port = port;
    this.#window = window;
  }
  id(): string {
    return this.#id;
  }
  sockets(): string[] {
    return [`127.0.0.1:${this.#port}`];
  }
  async online(): Promise<void> {}
  home(): string | null {
    return null;
  }
  async insertRelay(_url: string): Promise<void> {}
  async removeRelay(_url: string): Promise<void> {}
  async publicRelays(_on: boolean): Promise<void> {}
  keep(_urls: string[]): void {}
  #arrive(c: Conn) {
    this.#conns.push(c);
    const take = this.#accepting;
    this.#accepting = null;
    if (take) take(c);
    else this.#incoming.push(c);
  }
  async accept(): Promise<Connection | null> {
    if (this.#incoming.length > 0) return this.#incoming.shift()!;
    if (this.#closed) return null;
    return new Promise((r) => (this.#accepting = r));
  }
  async connect(addr: Addr, offered: Buffer, additional: Buffer[] = []): Promise<Connection> {
    const there = this.#net.get(addr.id);
    if (!there || there.#closed || this.#closed) throw new Error(`no endpoint ${addr.id} here`);
    // The other's first protocol that is offered: the accepting side's order decides, as with iroh (rustls).
    const alpn = there.#alpns.find((b) => [offered, ...additional].some((a) => a.equals(b)));
    if (alpn === undefined) throw new Error("peer doesn't support any known protocol");
    const [mine, theirs] = [new Conn(addr.id, alpn, this.#window), new Conn(this.#id, alpn, this.#window)];
    mine.peer = theirs;
    theirs.peer = mine;
    this.#conns.push(mine);
    there.#arrive(theirs);
    return mine;
  }
  /// Its process killed: gone from the mesh, its connections left open on the other side, never answering again.
  vanish() {
    this.#closed = true;
    if (this.#net.get(this.#id) === this) this.#net.delete(this.#id);
    for (const c of this.#conns) c.silent = true;
  }
  async close(): Promise<void> {
    if (this.#closed) return;
    this.#closed = true;
    if (this.#net.get(this.#id) === this) this.#net.delete(this.#id);
    for (const c of this.#conns) c.close(0, "endpoint closed");
    const take = this.#accepting;
    this.#accepting = null;
    take?.(null);
  }
}

/// A mesh of its own: endpoints bound on it reach each other, and only each other. `window`: each stream's flow control
/// (End), none by default.
export function memoryMesh(options: { window?: number } = {}): Pick<Mesh, "bind"> {
  const net = new Map<string, MemoryEndpoint>();
  let port = 40000;
  return {
    bind: async (o) => {
      const e = new MemoryEndpoint(net, o.secretKey, o.alpns, ++port, options.window);
      net.set(e.id(), e);
      return e;
    },
  };
}

/// A device's process killed with its connections open (memoryMesh's endpoints only).
export function vanish(endpoint: Endpoint) {
  (endpoint as MemoryEndpoint).vanish();
}
