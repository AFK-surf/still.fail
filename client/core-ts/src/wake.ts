// The UI coming back after being away, or the network changing under it: what is under way is suspect (wake.rs).
//
// - a request still unanswered that has waited a while (QUIET_MS) fails, for its caller to ask again;
// - a stream that heard nothing for a while ends, and is opened again;
// - what waits to reconnect stops waiting (`Host.woken`);
// - the host lets its connections go (`Host.resetConnections`).
// When the network changed, everything under way fails. A person asking to try again (`retry`) is taken as the
// connections suspect, not gone. WakingHost does the first two for everything that goes through the host.
import { HostError } from "./error.ts";
import type { DbOp, DbRange, Host, HttpRequest, HttpResponse, SocketFrames, StreamResponse, Chunks } from "./host.ts";
import type { ClientId, CoreMessage } from "./protocol.ts";
import { DROPPED, GONE, NETWORK } from "./wake-words.ts";

export { DROPPED, GONE, NETWORK };

/// Away at least this long: a request waiting since before is given up.
export const REQUEST_AWAY_MS = 10_000;
/// A request unanswered this long when the UI comes back is taken for one on a dead connection.
export const QUIET_MS = 3_000;
/// Away at least this long: a stream that heard nothing for as long is taken for gone.
export const STREAM_AWAY_MS = 30_000;

/// The UI came back at `at` after `away` ms, or the network changed, or a person asked to try again.
export class Wake {
  readonly at: number;
  readonly away: number;
  readonly network: boolean;
  readonly retry: boolean;
  constructor(at: number, away: number, network: boolean, retry: boolean) {
    this.at = at;
    this.away = away;
    this.network = network;
    this.retry = retry;
  }

  left(): number {
    return this.at - this.away;
  }

  /// A request that may be asked twice, sent at `sent` and not answered yet, is asked again beside it.
  hedgesRequest(sent: number): boolean {
    return (this.network || this.retry || this.away >= REQUEST_AWAY_MS) && sent <= this.at;
  }

  /// A request sent at `sent` and not answered yet is given up.
  dropsRequest(sent: number): boolean {
    return this.network || (this.away >= REQUEST_AWAY_MS && this.at - sent >= QUIET_MS);
  }

  /// A stream that last heard something at `heard` is taken for gone.
  dropsStream(heard: number): boolean {
    return this.network || (this.away >= STREAM_AWAY_MS && this.at - heard >= STREAM_AWAY_MS);
  }

  /// Long enough away that the connections under the core are taken for gone.
  suspectsConnections(): boolean {
    return this.network || this.retry || this.away >= STREAM_AWAY_MS;
  }

  reason(): string {
    return this.network ? NETWORK : GONE;
  }
}

/// A wait for the next wake: `cancel` when it is no longer wanted.
export type Waiter = { wake: Promise<Wake>; cancel(): void };

/// Tells whoever waits that the UI is back.
export class Wakes {
  #waiting = new Set<(wake: Wake) => void>();

  wake(wake: Wake): void {
    const waiting = [...this.#waiting];
    this.#waiting.clear();
    for (const w of waiting) w(wake);
  }

  /// The next time the UI comes back.
  next(): Waiter {
    let resolve!: (wake: Wake) => void;
    const wake = new Promise<Wake>((r) => (resolve = r));
    this.#waiting.add(resolve);
    return { wake, cancel: () => this.#waiting.delete(resolve) };
  }

  /// The first wake `drops` says is the end of something.
  dropped(drops: (wake: Wake) => boolean): Waiter {
    let cancelled = false;
    let current: Waiter | null = null;
    const wake = (async () => {
      for (;;) {
        current = this.next();
        const w = await current.wake;
        if (cancelled) return new Promise<Wake>(() => {});
        if (drops(w)) return w;
      }
    })();
    return {
      wake,
      cancel: () => {
        cancelled = true;
        current?.cancel();
      },
    };
  }
}

/// The first wake `drops` says is the end of something, from the host's wakes (`Host.woken`).
export async function wokenFor(host: Host, drops: (wake: Wake) => boolean): Promise<Wake> {
  for (;;) {
    const wake = await host.woken();
    if (drops(wake)) return wake;
  }
}

/// What a request says to be one that may be asked twice though it is not a read. Taken off before it goes.
export const HEDGE = "x-stillfail-hedge";

function hedgeable(request: HttpRequest): boolean {
  const m = request.method.toUpperCase();
  return m === "GET" || m === "HEAD" || request.headers.some(([k]) => k.toLowerCase() === HEDGE);
}

/// At most this many of one request under way at once.
const HEDGES = 3;

/// `pending`, unless a wake says it went out before the UI was away: then an error.
async function unlessDropped<T>(wakes: Wakes, sent: number, pending: Promise<T>): Promise<T> {
  const dropped = wakes.dropped((w) => w.dropsRequest(sent));
  try {
    return await Promise.race([
      pending,
      dropped.wake.then((w) => {
        throw new HostError(w.network ? NETWORK : DROPPED);
      }),
    ]);
  } finally {
    dropped.cancel();
  }
}

/// A request that may be asked twice: asked again at each wake that suspects what it went on (up to HEDGES at once),
/// and the first answer is its answer; one that fails leaves it to the others.
async function hedged<T>(wakes: Wakes, host: Host, request: HttpRequest, ask: (r: HttpRequest) => Promise<T>): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    let open = 0;
    let settled = false;
    let sent = host.nowMs();
    let waiter: Waiter | null = null;
    const finish = () => {
      settled = true;
      waiter?.cancel();
    };
    const attempt = () => {
      open++;
      ask(request).then(
        (answer) => {
          open--;
          if (settled) return;
          finish();
          resolve(answer);
        },
        (error) => {
          open--;
          if (settled) return;
          if (open === 0) {
            finish();
            reject(error);
          }
        },
      );
    };
    const listen = () => {
      waiter = wakes.dropped((w) => w.hedgesRequest(sent));
      void waiter.wake.then((w) => {
        if (settled) return;
        sent = w.at;
        if (open < HEDGES) attempt();
        listen();
      });
    };
    attempt();
    listen();
  });
}

/// A stream's chunks that end with an error at a wake when it heard nothing while the UI was away.
function quietEnds(host: Host, wakes: Wakes, body: Chunks): Chunks {
  let heard = host.nowMs();
  let ended = false;
  return {
    async next() {
      if (ended) return null;
      const gone = wakes.dropped((w) => w.dropsStream(heard));
      try {
        const out = await Promise.race([body.next(), gone.wake.then((w) => ({ wake: w }) as const)]);
        if (out !== null && typeof out === "object" && "wake" in out) {
          ended = true;
          body.close();
          throw new HostError(out.wake.reason());
        }
        if (out === null) ended = true;
        else heard = host.nowMs();
        return out;
      } finally {
        gone.cancel();
      }
    },
    close() {
      ended = true;
      body.close();
    },
  };
}

/// The host the core runs on, with the rules above for its requests and streams.
export class WakingHost implements Host {
  readonly inner: Host;
  readonly wakes: Wakes;

  constructor(inner: Host, wakes: Wakes) {
    this.inner = inner;
    this.wakes = wakes;
  }

  cloudOrigin(): string {
    return this.inner.cloudOrigin();
  }
  beta(): boolean {
    return this.inner.beta();
  }
  testChannel(): boolean {
    return this.inner.testChannel();
  }

  fetch(request: HttpRequest): Promise<HttpResponse> {
    if (hedgeable(request)) {
      const r = { ...request, headers: request.headers.filter(([k]) => k.toLowerCase() !== HEDGE) };
      return hedged(this.wakes, this.inner, r, (x) => this.inner.fetch(x));
    }
    return unlessDropped(this.wakes, this.inner.nowMs(), this.inner.fetch(request));
  }

  async fetchStream(request: HttpRequest): Promise<StreamResponse> {
    let opening: Promise<StreamResponse>;
    if (hedgeable(request)) {
      const r = { ...request, headers: request.headers.filter(([k]) => k.toLowerCase() !== HEDGE) };
      opening = hedged(this.wakes, this.inner, r, (x) => this.inner.fetchStream(x));
    } else opening = unlessDropped(this.wakes, this.inner.nowMs(), this.inner.fetchStream(request));
    const response = await opening;
    return { ...response, body: quietEnds(this.inner, this.wakes, response.body) };
  }

  /// Its frames are left to the core (core.ts `followSocket`); only its opening is given up.
  websocket(url: string, protocols: string[]): Promise<SocketFrames> {
    return unlessDropped(this.wakes, this.inner.nowMs(), this.inner.websocket(url, protocols));
  }

  storageGet(key: string): Promise<Uint8Array | null> {
    return this.inner.storageGet(key);
  }
  storageSet(key: string, value: Uint8Array): Promise<void> {
    return this.inner.storageSet(key, value);
  }
  storageDelete(key: string): Promise<void> {
    return this.inner.storageDelete(key);
  }
  dbRead(range: DbRange): Promise<[string, Uint8Array][]> {
    return this.inner.dbRead(range);
  }
  dbWrite(ops: DbOp[]): Promise<void> {
    return this.inner.dbWrite(ops);
  }
  nowMs(): number {
    return this.inner.nowMs();
  }
  monotonicMs(): number {
    return this.inner.monotonicMs();
  }
  utcOffsetMin(atMs: number): number {
    return this.inner.utcOffsetMin(atMs);
  }
  woken(): Promise<Wake> {
    return this.wakes.next().wake;
  }
  resetConnections(): void {
    this.inner.resetConnections();
  }
  randomBytes(buf: Uint8Array): void {
    this.inner.randomBytes(buf);
  }
  emit(client: ClientId, message: CoreMessage): void {
    this.inner.emit(client, message);
  }
}
