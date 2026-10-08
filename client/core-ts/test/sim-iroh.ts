// A network for the mesh tests, simulated: endpoints, relays and connections as iroh has them (iroh.ts), with what goes
// over them delivered on the test's clock (TestTime), each way after its relay's latency and at its speed. Nothing waits
// for real time and nothing depends on how busy the machine is: a test moves its clock, and the same seed gives the same
// run. What varies is drawn from the seed: each delivery's jitter and how a write is cut into packets. A failure says its
// seed (SIM_SEED replays it) and the network it ran on.
//
// The device side is an Iroh (as a host gives the core: wrapIroh over promises, as the addon's binding is); the station
// side has the addon's own calls (accept, holdIncoming, keep, online, sockets), what test/mesh-station.ts uses.
import { createHash } from "node:crypto";
import { Duration, Effect, type Clock } from "effect";
import { flush, type HostTime } from "../src/testing.ts";
import type { CloseReason, Iroh, IrohAddr } from "../src/iroh.ts";
import { wrapIroh } from "../src/iroh-bindings.ts";

/// One side of a relay: how long a packet takes between it and the endpoint each way, how fast that line is (bytes a
/// second; none: as fast as can be), and what share of the packets on it are lost (none: none are).
export type Leg = { ms: number; bps?: number; loss?: number };
/// A relay as the test sets it: the device's line to it, and the station's.
export type RelaySpec = { device?: Leg; station?: Leg };

/// A seeded random (mulberry32): the same seed, the same draws.
export class Rng {
  #s: number;
  constructor(seed: number) {
    this.#s = seed >>> 0;
  }
  /// In [0, 1).
  next(): number {
    let t = (this.#s += 0x6d2b79f5);
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  }
  /// An integer in [lo, hi].
  int(lo: number, hi: number): number {
    return lo + Math.floor(this.next() * (hi - lo + 1));
  }
}

const href = (url: string) => new URL(url).href;
/// When a simulated run starts.
export const START = Date.UTC(2026, 9, 6, 9, 0, 0);
/// QUIC's idle timeout, as iroh has it.
export const IDLE_MS = 30_000;

/// Time for a simulated run: nothing passes but what it is moved on by, and moving on goes from one timer to the next,
/// each run in order (by when it is due, then by when it was set), what it wakes run before the next. A test's clock
/// (the core's, its host's, the network's): `settle` moves it on until what the test waits for is done.
export class SimTime implements HostTime {
  readonly clock: Clock.Clock;
  readonly sleeps: number[] = [];
  #now: number;
  #seq = 0;
  #timers: { at: number; seq: number; fire: () => void }[] = [];

  constructor(start = START) {
    this.#now = start;
    const self = this;
    const nanos = () => BigInt(Math.round(self.#now)) * 1_000_000n;
    this.clock = {
      currentTimeMillisUnsafe: () => self.#now,
      currentTimeMillis: Effect.sync(() => self.#now),
      currentTimeNanosUnsafe: nanos,
      currentTimeNanos: Effect.sync(nanos),
      monotonicTimeNanosUnsafe: nanos,
      monotonicTimeNanos: Effect.sync(nanos),
      sleep(duration: Duration.Duration) {
        const ms = Duration.toMillis(duration);
        self.sleeps.push(ms);
        return Effect.callback<void>((resume) => {
          const timer = self.#set(self.#now + Math.max(0, ms), () => resume(Effect.void));
          return Effect.sync(() => self.#clear(timer));
        });
      },
    } as Clock.Clock;
  }

  now(): number {
    return this.#now;
  }

  #set(at: number, fire: () => void) {
    const timer = { at, seq: this.#seq++, fire };
    let i = this.#timers.length;
    while (i > 0 && (this.#timers[i - 1]!.at > at || (this.#timers[i - 1]!.at === at && this.#timers[i - 1]!.seq > timer.seq))) i--;
    this.#timers.splice(i, 0, timer);
    return timer;
  }

  #clear(timer: { at: number; seq: number }) {
    const i = this.#timers.indexOf(timer as never);
    if (i >= 0) this.#timers.splice(i, 1);
  }

  /// What is due now and what it sets going, run out.
  async #runDue(): Promise<void> {
    await flush(20);
    while (this.#timers.length > 0 && this.#timers[0]!.at <= this.#now) {
      this.#timers.shift()!.fire();
      await flush(20);
    }
  }

  /// `ms` pass: each timer due by then fires at its time, in order.
  async pass(ms: number): Promise<void> {
    const until = this.#now + ms;
    await this.#runDue();
    while (this.#timers.length > 0 && this.#timers[0]!.at <= until) {
      this.#now = this.#timers[0]!.at;
      await this.#runDue();
    }
    this.#now = until;
    await this.#runDue();
  }

  /// Moves on, timer by timer, until `p` is settled; fails once nothing more is set to happen, or after `limitMs`.
  async settle<A>(p: Promise<A>, limitMs = 30 * 60_000): Promise<A> {
    let done = false;
    p.then(
      () => (done = true),
      () => (done = true),
    );
    await this.until(() => done, limitMs);
    return p;
  }

  /// Moves on, timer by timer, until `cond` holds (looked at after each); fails as `settle` does.
  async until(cond: () => boolean, limitMs = 30 * 60_000): Promise<void> {
    const start = this.#now;
    await this.#runDue();
    while (!cond()) {
      const next = this.#timers[0];
      if (next === undefined) throw new Error("waited on something that will never come: no timer is left");
      if (next.at - start > limitMs) throw new Error(`not done within ${limitMs} ms (simulated)`);
      this.#now = Math.max(this.#now, next.at);
      await this.#runDue();
    }
  }
}
const NEVER = new Promise<never>(() => {});

/// Where a connection goes: through a relay (its two endpoints' legs to it, as they are now) or direct.
class Way {
  readonly net: SimNet;
  readonly relay: string | null;
  readonly sides: ["device" | "station", "device" | "station"];
  constructor(net: SimNet, relay: string | null, sides: ["device" | "station", "device" | "station"]) {
    this.net = net;
    this.relay = relay;
    this.sides = sides;
  }
  #legs(): Leg[] {
    return this.relay === null ? [this.net.direct] : this.sides.map((side) => this.net.leg(this.relay!, side));
  }
  oneWay(): number {
    return this.#legs().reduce((ms, leg) => ms + leg.ms, 0);
  }
  bps(): number | undefined {
    const least = Math.min(...this.#legs().map((leg) => leg.bps ?? Infinity));
    return Number.isFinite(least) ? least : undefined;
  }
  /// The share of packets lost on the way, all its legs together.
  loss(): number {
    return 1 - this.#legs().reduce((kept, leg) => kept * (1 - (leg.loss ?? 0)), 1);
  }
  /// How long a packet lost on it takes to be sent again, the first time (QUIC's probe timeout: some two round trips);
  /// each time again twice as long.
  pto(): number {
    return 4 * this.oneWay() + 25;
  }
  /// Until when it is down (its relay's), or 0.
  downUntil(): number {
    return this.relay === null ? 0 : this.net.downUntil(this.relay);
  }
}

/// One way of a connection: what goes in comes out after the way's latency (and its jitter), at its speed, in order;
/// sent while its relay is down, it goes once the relay is back (QUIC sends it again), unless the connection is gone. A
/// packet lost on the way (drawn from the seed, as the way loses them) comes a probe timeout later, or more: those
/// after it wait for it, as a stream's do.
class Line {
  #free = 0;
  #queue: { at: number; deliver: () => void }[] = [];
  #pumping = false;
  readonly net: SimNet;
  readonly way: Way;
  readonly live: () => boolean;
  readonly lost: () => void;
  constructor(net: SimNet, way: Way, live: () => boolean, lost: () => void = () => {}) {
    this.net = net;
    this.way = way;
    this.live = live;
    this.lost = lost;
  }

  /// `always`: delivered though its connection is gone meanwhile (word of its closing).
  send(size: number, deliver: () => void, always = false): void {
    const now = this.net.now();
    const latency = this.way.oneWay() + this.net.jitter();
    const bps = this.way.bps();
    // A packet leaves once those before it have (and its relay is up), at the line's speed; it never overtakes one sent
    // before it.
    const leaves = Math.max(this.#free, now, this.way.downUntil()) + (bps ? (size / bps) * 1000 : 0);
    this.#free = leaves;
    let again = 0;
    const loss = this.way.loss();
    for (let pto = this.way.pto(); loss > 0 && this.net.rng.next() < loss; pto *= 2) {
      again += pto;
      this.lost();
    }
    const at = Math.max(leaves + latency + again, this.#queue.at(-1)?.at ?? 0);
    this.#queue.push({ at, deliver: always ? deliver : () => this.live() && deliver() });
    if (!this.#pumping) void this.#pump();
  }

  async #pump(): Promise<void> {
    this.#pumping = true;
    while (this.#queue.length > 0) {
      const next = this.#queue[0]!;
      const wait = next.at - this.net.now();
      if (wait > 0) await this.net.sleep(wait);
      this.#queue.shift();
      next.deliver();
    }
    this.#pumping = false;
  }
}

/// What a read waits on: chunks, then the end, or an error.
class Inbox {
  chunks: Uint8Array[] = [];
  ended = false;
  error: Error | null = null;
  #waiter: (() => void) | null = null;
  push(chunk: Uint8Array) {
    this.chunks.push(chunk);
    this.#wake();
  }
  end() {
    this.ended = true;
    this.#wake();
  }
  fail(error: Error) {
    if (this.ended) return;
    this.error = error;
    this.#wake();
  }
  #wake() {
    const w = this.#waiter;
    this.#waiter = null;
    w?.();
  }
  async read(): Promise<Uint8Array | null> {
    for (;;) {
      if (this.chunks.length > 0) return this.chunks.shift()!;
      if (this.ended) return null;
      if (this.error) throw this.error;
      await new Promise<void>((r) => (this.#waiter = r));
    }
  }
}

/// A stream's end on one side: what it reads, and what it writes going to its other end.
export class SimStream {
  readonly inbox = new Inbox();
  peer!: SimStream;
  #finished = false;
  #stopped: Promise<number | null>;
  #resolveStopped!: (code: number | null) => void;
  /// Told once the first of it reaches the other side (a stream the other side opened shows then).
  #shown = false;

  readonly conn: SimConnection;
  readonly onShow: (() => void) | null;

  constructor(conn: SimConnection, onShow: (() => void) | null) {
    this.conn = conn;
    this.onShow = onShow;
    this.#stopped = new Promise((r) => (this.#resolveStopped = r));
  }

  #arrive(): void {
    if (this.peer.#shown) return;
    this.peer.#shown = true;
    this.peer.onShow?.();
  }

  async read(): Promise<Uint8Array | null> {
    return this.inbox.read();
  }

  async write(bytes: Uint8Array): Promise<void> {
    if (this.#finished) throw new Error("stream finished");
    if (this.conn.reason !== null) throw new Error("connection lost");
    const copy = new Uint8Array(bytes);
    // Cut as QUIC sends it, the sizes drawn from the seed.
    for (let at = 0; at < copy.length || at === 0; ) {
      const size = Math.max(1, Math.min(copy.length - at, this.conn.net.rng.int(1024, 32 * 1024)));
      const chunk = copy.subarray(at, at + size);
      this.conn.out.send(chunk.length, () => {
        this.#arrive();
        this.conn.acked();
        this.conn.peer.counts.rxBytes += chunk.length;
        this.peer.inbox.push(chunk);
      });
      this.conn.counts.txBytes += chunk.length;
      this.conn.counts.txPackets++;
      at += size;
      if (copy.length === 0) break;
    }
  }

  async finish(): Promise<void> {
    if (this.#finished) return;
    this.#finished = true;
    this.conn.out.send(0, () => {
      this.#arrive();
      this.peer.inbox.end();
      // Acknowledged: the end has come, and word of it comes back.
      this.conn.peer.out.send(0, () => this.#resolveStopped(null));
    });
  }

  stopped(): Promise<number | null> {
    return this.#stopped;
  }

  /// Ends it both ways, as the addon's reset: what it sends is reset and what it reads stopped, so the other end's reads
  /// fail and what it sends is stopped with `code`.
  reset(code: number): void {
    this.#finished = true;
    this.#resolveStopped(code);
    this.inbox.fail(new Error(`stream reset (${code})`));
    this.conn.out.send(0, () => {
      this.peer.inbox.fail(new Error(`stream reset (${code})`));
      this.peer.#resolveStopped(code);
    });
  }

  /// The connection went: reads fail, and waiting for its other end to stop is over.
  lost(): void {
    this.inbox.fail(new Error("connection lost"));
    this.#resolveStopped(null);
  }
}

/// A connection's end on one side.
export class SimConnection {
  peer!: SimConnection;
  out: Line;
  reason: CloseReason | null = null;
  readonly counts = { rxBytes: 0, txBytes: 0, txPackets: 0, lostPackets: 0 };
  readonly #streams: SimStream[] = [];
  readonly #incoming: SimStream[] = [];
  #accepting: ((s: SimStream | null) => void) | null = null;
  #closed: Promise<CloseReason>;
  #resolveClosed!: (r: CloseReason) => void;

  readonly net: SimNet;
  readonly endpoint: SimEndpoint;
  readonly remote: string;
  readonly spoken: Uint8Array;
  /// Where it goes.
  readonly way: Way;
  /// Its round trip, as QUIC estimates it: from its first sample (the handshake, getting onto the relay included), each
  /// one after moving it an eighth of the way (RFC 9002's smoothed RTT).
  rttMs: number;
  /// When something of it last came (a connection a whole IDLE_MS quiet while a packet is owed is gone, as QUIC's).
  heard: number;

  constructor(net: SimNet, endpoint: SimEndpoint, remote: string, spoken: Uint8Array, way: Way, firstSample: number) {
    this.net = net;
    this.endpoint = endpoint;
    this.remote = remote;
    this.spoken = spoken;
    this.way = way;
    this.rttMs = firstSample;
    this.heard = net.now();
    this.out = new Line(
      net,
      way,
      () => this.reason === null,
      () => this.counts.lostPackets++,
    );
    this.#closed = new Promise((r) => (this.#resolveClosed = r));
  }

  /// A packet of it acknowledged: a sample of its round trip.
  acked(): void {
    this.heard = this.peer.heard = this.net.now();
    this.rttMs = (7 * this.rttMs + 2 * this.way.oneWay() + 2 * this.net.jitter()) / 8;
  }

  /// Gone without a word: its way stayed down past QUIC's idle timeout.
  timedOut(): void {
    this.#gone({ kind: "timeout", reason: "timed out" });
  }

  remoteId(): string {
    return this.remote;
  }
  alpn(): Uint8Array {
    return this.spoken;
  }
  isClosed(): boolean {
    return this.reason !== null;
  }

  #pair(bi: boolean): SimStream {
    const mine = new SimStream(this, null);
    const theirs = new SimStream(this.peer, bi ? () => this.peer.#offer(theirs) : null);
    mine.peer = theirs;
    theirs.peer = mine;
    this.#streams.push(mine);
    this.peer.#streams.push(theirs);
    return mine;
  }

  #offer(stream: SimStream): void {
    if (this.reason !== null) return;
    const take = this.#accepting;
    if (take) {
      this.#accepting = null;
      take(stream);
    } else this.#incoming.push(stream);
  }

  async openBi(): Promise<SimStream> {
    if (this.reason !== null) throw new Error("connection lost");
    return this.#pair(true);
  }
  async openUni(): Promise<SimStream> {
    if (this.reason !== null) throw new Error("connection lost");
    return this.#pair(false);
  }
  async acceptBi(): Promise<SimStream | null> {
    if (this.#incoming.length > 0) return this.#incoming.shift()!;
    if (this.reason !== null) return null;
    return new Promise((r) => (this.#accepting = r));
  }

  #gone(reason: CloseReason): void {
    if (this.reason !== null) return;
    this.reason = reason;
    for (const s of this.#streams) s.lost();
    const take = this.#accepting;
    this.#accepting = null;
    take?.(null);
    this.#resolveClosed(reason);
  }

  close(code: number, reason: string): void {
    if (this.reason !== null) return;
    this.#gone({ kind: "local", reason });
    void code;
    this.out.send(0, () => this.peer.#gone({ kind: "application", reason }), true);
  }

  closeReason(): CloseReason | null {
    return this.reason;
  }
  closedInfo(): Promise<CloseReason> {
    return this.#closed;
  }
  stats(): { rxBytes: number; txBytes: number; txPackets: number; lostPackets: number } {
    return { ...this.counts };
  }
  paths(): { selected: boolean; relay: string | null; rttMs: number }[] {
    return [{ selected: true, relay: this.way.relay, rttMs: this.rttMs }];
  }
}

/// An endpoint: a device's (bound by the core) or a station's (by mesh-station.ts).
export class SimEndpoint {
  readonly conns: SimConnection[] = [];
  readonly #known = new Map<string, IrohAddr>();
  /// When it is on each relay (its home ones from its binding, others once it first went there).
  readonly #on = new Map<string, Promise<void>>();
  readonly #keeps: string[] = [];
  readonly #incoming: SimConnection[] = [];
  #accepting: ((c: SimConnection | null) => void) | null = null;
  #held = 0;
  #closed = false;

  readonly net: SimNet;
  readonly side: "device" | "station";
  readonly key: Uint8Array;
  readonly relays: string[];
  readonly relayOnly: boolean;
  /// It looks other endpoints up (the DHT, mDNS): it finds the relays they are at home on.
  readonly lookup: boolean;
  /// A station's ALPNs, and whether it is at an address on this machine.
  readonly alpns: Uint8Array[];
  readonly direct: boolean;

  constructor(net: SimNet, side: "device" | "station", key: Uint8Array, relays: string[], relayOnly: boolean, alpns: Uint8Array[], direct: boolean, lookup = false) {
    this.net = net;
    this.side = side;
    this.key = key;
    this.relays = relays;
    this.relayOnly = relayOnly;
    this.lookup = lookup;
    this.alpns = alpns;
    this.direct = direct;
    for (const r of relays) this.#goOnto(r);
  }

  id(): string {
    return createHash("sha256").update(this.key).digest("hex");
  }

  /// Getting onto a relay takes a round trip to it (and its handshake, another).
  #goOnto(relay: string): Promise<void> {
    let on = this.#on.get(relay);
    if (!on) {
      this.net.onto(this, relay);
      const leg = this.net.leg(relay, this.side);
      on = this.net.sleep(4 * leg.ms);
      this.#on.set(relay, on);
    }
    return on;
  }

  /// Whether a connection can come to it through `relay` (an entry: through the relay it goes on to).
  reachableOn(relay: string): boolean {
    const to = this.net.server(relay);
    return !this.#closed && [...this.relays, ...this.#keeps].some((r) => this.net.server(r) === to);
  }

  // ── what the core calls (BoundEndpoint) ──

  async connect(addr: IrohAddr, alpn: Uint8Array, additional: Uint8Array[] = []): Promise<SimConnection> {
    const there = this.net.endpoint(addr.id);
    if (!there || this.#closed) return NEVER;
    const known = this.#known.get(addr.id);
    const spoken = [alpn, ...additional].find((a) => there.alpns.some((b) => Buffer.from(a).equals(Buffer.from(b))));
    if (!spoken) throw new Error("no ALPN in common");
    const started = this.net.now();
    let relay: string | null = null;
    if (this.relayOnly || !there.direct || (known?.ips?.length ?? 0) === 0) {
      const told = [...(addr.relays ?? []), ...(known?.relays ?? []), ...this.relays].map(href);
      relay = told.find((r) => there.reachableOn(r)) ?? null;
      if (relay === null) return NEVER;
      // iroh sends its first packets on every path it knows of, going onto each relay of them: those it was told of, and
      // those its lookups found (the relays the other end is at home on).
      for (const r of new Set([...told, ...(this.lookup ? there.relays : [])])) this.net.onto(this, r);
      await this.#goOnto(relay);
    }
    const way = new Way(this.net, relay, [this.side, there.side]);
    // A handshake: a round trip, its packets lost as the way loses them (sent again after QUIC's initial probe timeout,
    // a second, twice as long each time). One the other end holds, or through a relay that is down, is never answered.
    let handshake = 2 * way.oneWay() + this.net.jitter();
    const loss = way.loss();
    for (let pto = 1000; loss > 0 && this.net.rng.next() < 1 - (1 - loss) ** 2; pto *= 2) handshake += pto;
    await this.net.sleep(handshake);
    if (way.downUntil() > this.net.now() || this.#closed || there.#closed) return NEVER;
    if (there.#held > 0) {
      there.#held--;
      return NEVER;
    }
    const first = this.net.now() - started;
    const mine = new SimConnection(this.net, this, there.id(), spoken, way, first);
    const theirs = new SimConnection(this.net, there, this.id(), spoken, new Way(this.net, relay, [there.side, this.side]), 2 * way.oneWay());
    mine.peer = theirs;
    theirs.peer = mine;
    this.net.opened(mine);
    this.conns.push(mine);
    there.#arrived(theirs);
    return mine;
  }

  isClosed(): boolean {
    return this.#closed;
  }

  addAddr(addr: IrohAddr): void {
    this.#known.set(addr.id, { ...this.#known.get(addr.id), ...addr });
  }
  async networkChange(): Promise<void> {}
  relayStatus(): { url: string; connected: boolean }[] {
    return this.relays.map((url) => ({ url, connected: true }));
  }
  async close(): Promise<void> {
    if (this.#closed) return;
    this.#closed = true;
    for (const c of [...this.conns]) c.close(0, "");
    const take = this.#accepting;
    this.#accepting = null;
    take?.(null);
  }

  // ── what a station has besides (the addon's, as mesh-station.ts uses it) ──

  #arrived(conn: SimConnection): void {
    this.conns.push(conn);
    const take = this.#accepting;
    if (take) {
      this.#accepting = null;
      take(conn);
    } else this.#incoming.push(conn);
  }
  async accept(): Promise<SimConnection | null> {
    if (this.#incoming.length > 0) return this.#incoming.shift()!;
    if (this.#closed) return null;
    return new Promise((r) => (this.#accepting = r));
  }
  /// The next `n` connections are never answered (their handshake held).
  holdIncoming(n: number): void {
    this.#held += n;
  }
  /// Held on these relays too (keep.rs).
  keep(relays: string[]): void {
    for (const r of relays.map(href)) {
      this.#keeps.push(r);
      void this.#goOnto(r);
    }
  }
  /// Once it is on its home relays.
  async online(): Promise<void> {
    await Promise.all(this.relays.map((r) => this.#goOnto(r)));
  }
  sockets(): string[] {
    return this.direct ? [`127.0.0.1:${4000 + (parseInt(this.id().slice(0, 4), 16) % 1000)}`] : [];
  }
}

/// The network: its relays, its endpoints, its clock and its seed.
export class SimNet {
  readonly rng: Rng;
  /// A direct way between two endpoints on this machine.
  direct: Leg = { ms: 1 };
  readonly #relays = new Map<string, { device: Leg; station: Leg }>();
  /// Entries (cloud relays.ts RELAY_ENTRIES): a URL on one relay's machine taking what comes to it on to another relay.
  readonly #entries = new Map<string, string>();
  /// Where each endpoint went: by endpoint, then relay (the one an entry goes on to), the URLs it went there through.
  readonly #onto = new Map<SimEndpoint, Map<string, Set<string>>>();
  readonly #down = new Map<string, number>();
  readonly #conns: SimConnection[] = [];
  /// What befell it, as a failure says: the run's events in order (`note`).
  readonly log: string[] = [];
  readonly #endpoints = new Map<string, SimEndpoint>();

  readonly clock: Clock.Clock;
  readonly seed: number;
  /// Each delivery's jitter, up to this many ms (drawn from the seed).
  readonly jitterMs: number;

  constructor(clock: Clock.Clock, seed: number, jitterMs = 3) {
    this.clock = clock;
    this.seed = seed;
    this.jitterMs = jitterMs;
    this.rng = new Rng(seed);
  }

  now(): number {
    return this.clock.currentTimeMillisUnsafe();
  }
  sleep(ms: number): Promise<void> {
    return Effect.runPromise(this.clock.sleep(Duration.millis(Math.max(0, ms))));
  }
  jitter(): number {
    return this.jitterMs > 0 ? this.rng.next() * this.jitterMs : 0;
  }

  /// A relay at `url` (its href), each side's line to it as given (none: next to it). Set again, it changes the
  /// connections already through it as well.
  relay(url: string, spec: RelaySpec = {}): string {
    const at = href(url);
    const was = this.#relays.get(at);
    this.#relays.set(at, { device: spec.device ?? { ms: 0 }, station: spec.station ?? { ms: 0 } });
    if (was) this.note(`${at} now ${this.#legs(at)}`);
    return at;
  }

  /// An entry at `url` into the relay at `to`: who goes onto it is on that relay. Its lines as given: the device's to the
  /// entry's machine, the station's through the relay it goes on to.
  entry(url: string, to: string, spec: RelaySpec = {}): string {
    const at = this.relay(url, spec);
    this.#entries.set(at, href(to));
    return at;
  }

  /// The relay one is on through `url`: the one an entry goes on to, or its own.
  server(url: string): string {
    const at = href(url);
    return this.#entries.get(at) ?? at;
  }

  /// `endpoint` went onto a relay through `url`.
  onto(endpoint: SimEndpoint, url: string): void {
    let on = this.#onto.get(endpoint);
    if (!on) this.#onto.set(endpoint, (on = new Map()));
    const server = this.server(url);
    let urls = on.get(server);
    if (!urls) on.set(server, (urls = new Set()));
    urls.add(href(url));
  }

  /// Each endpoint that went onto one relay through two URLs or more (`open`: of those still open): one key there twice,
  /// which iroh-relay takes as one connection taking the other's place, back and forth.
  twice(open = false): string[] {
    const out: string[] = [];
    for (const [endpoint, on] of this.#onto) {
      if (open && endpoint.isClosed()) continue;
      for (const [server, urls] of on) if (urls.size > 1) out.push(`${endpoint.id().slice(0, 8)} on ${server} through ${[...urls].join(" and ")}`);
    }
    return out;
  }

  /// The relay at `url` answers nothing for `ms`: what is sent through it is lost, and its connections that stay quiet
  /// IDLE_MS meanwhile are gone (QUIC's idle timeout).
  down(url: string, ms: number): void {
    const at = href(url);
    const until = this.now() + ms;
    this.#down.set(at, Math.max(until, this.#down.get(at) ?? 0));
    this.note(`${at} down for ${ms} ms`);
    if (ms >= IDLE_MS)
      void this.sleep(IDLE_MS).then(() => {
        for (const c of this.#conns) if (c.way.relay === at && c.reason === null && this.now() - c.heard >= IDLE_MS) c.timedOut();
      });
    void this.sleep(ms).then(() => this.note(`${at} up`));
  }
  downUntil(relay: string): number {
    const until = this.#down.get(href(relay)) ?? 0;
    return until > this.now() ? until : 0;
  }
  opened(conn: SimConnection): void {
    this.#conns.push(conn, conn.peer);
  }
  /// Every connection either end of which is still open.
  open(): SimConnection[] {
    return this.#conns.filter((c) => c.reason === null);
  }

  note(what: string): void {
    this.log.push(`${((this.now() - START) / 1000).toFixed(3)} s: ${what}`);
  }
  #legs(at: string): string {
    const r = this.#relays.get(at)!;
    const leg = (l: Leg) => `${l.ms} ms${l.bps ? ` ${l.bps} B/s` : ""}${l.loss ? ` ${Math.round(l.loss * 100)}% lost` : ""}`;
    return `device ${leg(r.device)}, station ${leg(r.station)}`;
  }
  leg(relay: string, side: "device" | "station"): Leg {
    return this.#relays.get(href(relay))?.[side] ?? { ms: 0 };
  }
  endpoint(id: string): SimEndpoint | undefined {
    return this.#endpoints.get(id);
  }

  #add(e: SimEndpoint): SimEndpoint {
    this.#endpoints.set(e.id(), e);
    return e;
  }

  /// The device's iroh, as a host gives the core.
  iroh(): Iroh {
    return wrapIroh(
      async (o) => this.#add(new SimEndpoint(this, "device", o.secretKey, o.relayUrls.map(href), o.relayOnly, [], false, o.lookup)) as never,
      (b) => b,
    );
  }

  /// A station's endpoint, bound as the addon binds one (mesh-station.ts): `bindAddr` puts it at an address here.
  bindStation(o: { secretKey: Uint8Array; alpns: Uint8Array[]; relayUrls: string[]; relayOnly?: boolean; bindAddr?: string }): SimEndpoint {
    return this.#add(new SimEndpoint(this, "station", o.secretKey, o.relayUrls.map(href), o.relayOnly === true, o.alpns, o.bindAddr !== undefined));
  }

  /// A secret key drawn from the seed.
  key(): Uint8Array {
    return Uint8Array.from({ length: 32 }, () => this.rng.int(0, 255));
  }

  /// Where a test's stations run (mesh-station.ts World): on this network, on its clock, keys from its seed.
  world(): { bind(options: Record<string, unknown>): Promise<SimEndpoint>; sleep(ms: number): Promise<void> } {
    return {
      bind: async (o) => this.bindStation({ ...o, secretKey: this.key() } as never),
      sleep: (ms) => this.sleep(ms),
    };
  }

  /// What this run's network was, for a failure to say.
  describe(): string {
    const relays = [...this.#relays.keys()].map((url) => `${url} ${this.#legs(url)}`);
    return `seed ${this.seed} (SIM_SEED=${this.seed} replays it), jitter up to ${this.jitterMs} ms; ${relays.length ? relays.join("; ") : "no relays"}; direct ${this.direct.ms} ms`;
  }
}
