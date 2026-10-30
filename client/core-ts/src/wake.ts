// The UI coming back after being away, or the network changing under it: what is under way is suspect (wake.rs).
//
// - a request still unanswered that has waited a while (QUIET_MS) fails, for its caller to ask again;
// - a stream that heard nothing for a while ends, and is opened again;
// - what waits to reconnect stops waiting (`Wakes.next`);
// - the host lets its connections go (`Host.resetConnections`).
// When the network changed, everything under way fails. A person asking to try again (`retry`) is taken as the
// connections suspect, not gone. WakingHost does the first two for everything that goes through the host.
import { Deferred, Effect, Scope } from "effect";
import { HostError } from "./error.ts";
import type { Host, HttpRequest, HttpResponse, Pull, StreamResponse } from "./host.ts";
import type { ClientId, CoreMessage } from "./protocol.ts";
import { DROPPED, GONE, NETWORK } from "./wake-words.ts";

export { DROPPED, GONE, NETWORK };

export const REQUEST_AWAY_MS = 10_000;
export const QUIET_MS = 3_000;
export const STREAM_AWAY_MS = 30_000;

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

/// Tells whoever waits that the UI is back.
export class Wakes {
  readonly #waiting = new Set<Deferred.Deferred<Wake>>();

  wake(wake: Wake): void {
    const waiting = [...this.#waiting];
    this.#waiting.clear();
    for (const d of waiting) Deferred.doneUnsafe(d, Effect.succeed(wake));
  }

  /// The next time the UI comes back.
  get next(): Effect.Effect<Wake> {
    return Effect.suspend(() => {
      const d = Deferred.makeUnsafe<Wake>();
      this.#waiting.add(d);
      return Deferred.await(d).pipe(Effect.ensuring(Effect.sync(() => this.#waiting.delete(d))));
    });
  }

  /// The first wake `drops` says is the end of something.
  until(drops: (wake: Wake) => boolean): Effect.Effect<Wake> {
    const loop: Effect.Effect<Wake> = Effect.flatMap(this.next, (w) => (drops(w) ? Effect.succeed(w) : loop));
    return loop;
  }
}

/// What a request says to be one that may be asked twice though it is not a read. Taken off before it goes.
export const HEDGE = "x-stillfail-hedge";

export function hedgeable(request: HttpRequest): boolean {
  const m = request.method.toUpperCase();
  return m === "GET" || m === "HEAD" || request.headers.some(([k]) => k.toLowerCase() === HEDGE);
}

const HEDGES = 3;

/// `pending`, unless a wake says it went out before the UI was away: then an error.
export function unlessDropped<A, R>(wakes: Wakes, sent: number, pending: Effect.Effect<A, HostError, R>): Effect.Effect<A, HostError, R> {
  const dropped = wakes.until((w) => w.dropsRequest(sent)).pipe(Effect.flatMap((w) => Effect.fail(new HostError(w.network ? NETWORK : DROPPED))));
  return Effect.raceFirst(pending, dropped);
}

/// A request that may be asked twice: asked again at each wake that suspects what it went on (up to HEDGES at once),
/// the first answer its answer; one that fails leaves it to the others.
export function hedged<A>(wakes: Wakes, host: Host, ask: Effect.Effect<A, HostError>): Effect.Effect<A, HostError> {
  return Effect.scoped(
    Effect.gen(function* () {
      const done = yield* Deferred.make<A, HostError>();
      let open = 0;
      let sent = host.nowMs();
      const attempt = Effect.gen(function* () {
        open++;
        const result = yield* Effect.result(ask);
        open--;
        if (result._tag === "Success") yield* Deferred.succeed(done, result.success);
        else if (open === 0) yield* Deferred.fail(done, result.failure);
      });
      yield* Effect.forkScoped(attempt);
      const again: Effect.Effect<never> = Effect.flatMap(
        wakes.until((w) => w.hedgesRequest(sent)),
        (w) =>
          Effect.suspend(() => {
            sent = w.at;
            return open < HEDGES ? Effect.forkScoped(attempt).pipe(Effect.andThen(again)) : again;
          }),
      ) as Effect.Effect<never>;
      yield* Effect.forkScoped(again);
      return yield* Deferred.await(done);
    }),
  );
}

/// A pull that ends with an error at a wake when it heard nothing while the UI was away.
export function quietEnds<A>(host: Host, wakes: Wakes, pull: Pull<A>): Pull<A> {
  let heard = host.nowMs();
  const gone = Effect.suspend(() => wakes.until((w) => w.dropsStream(heard))).pipe(Effect.flatMap((w) => Effect.fail(new HostError(w.reason()))));
  return {
    take: Effect.raceFirst(
      pull.take.pipe(
        Effect.tap(() =>
          Effect.sync(() => {
            heard = host.nowMs();
          }),
        ),
      ),
      gone,
    ),
  };
}

/// The host the core runs on, with the rules above for its requests and streams.
export class WakingHost implements Host {
  readonly inner: Host;
  readonly wakes: Wakes;

  /// The inner host's record, as it is now (a test sets its own after the core starts).
  get recorder(): Host["recorder"] {
    return this.inner.recorder;
  }
  readonly tcp?: Host["tcp"];
  readonly appKeys?: boolean;
  readonly openDb?: Host["openDb"];
  readonly memoryDb?: Host["memoryDb"];
  readonly deleteDb?: Host["deleteDb"];
  readonly report?: Host["report"];
  readonly legacyRead?: Host["legacyRead"];
  readonly secureGet?: Host["secureGet"];
  readonly secureSet?: Host["secureSet"];
  readonly secureDelete?: Host["secureDelete"];
  readonly secureAsk?: Host["secureAsk"];
  readonly savedRead?: Host["savedRead"];
  readonly unzstd?: Host["unzstd"];
  readonly ed25519Sign?: Host["ed25519Sign"];

  constructor(inner: Host, wakes: Wakes) {
    this.inner = inner;
    this.wakes = wakes;
    if (inner.tcp) this.tcp = (port) => inner.tcp!(port);
    this.appKeys = inner.appKeys;
    // The databases are the device's: nothing of them waits on a UI coming back.
    if (inner.openDb) this.openDb = (name) => inner.openDb!(name);
    if (inner.memoryDb) this.memoryDb = () => inner.memoryDb!();
    if (inner.deleteDb) this.deleteDb = (name) => inner.deleteDb!(name);
    if (inner.report) this.report = (error) => inner.report!(error);
    if (inner.legacyRead) this.legacyRead = (range) => inner.legacyRead!(range);
    // So is what the system keeps sealed; a read may wait on the person, never on a UI coming back.
    if (inner.secureGet) this.secureGet = (key, opts) => inner.secureGet!(key, opts);
    if (inner.secureSet) this.secureSet = (key, value, opts) => inner.secureSet!(key, value, opts);
    if (inner.secureDelete) this.secureDelete = (key) => inner.secureDelete!(key);
    if (inner.secureAsk) this.secureAsk = (reason) => inner.secureAsk!(reason);
    // A file the app saved on the device, read back: the device's too.
    if (inner.savedRead) this.savedRead = (at, start, end) => inner.savedRead!(at, start, end);
    // A reply taken apart: on the device, as it comes.
    if (inner.unzstd) this.unzstd = () => inner.unzstd!();
    // A signature: the device's, at once.
    if (inner.ed25519Sign) this.ed25519Sign = (seed, message) => inner.ed25519Sign!(seed, message);
  }

  /// Names in the order people read them: the system's, at once (the files page's: drive-browse.ts).
  collate(names: readonly string[]): number[] | null {
    return this.inner.collate?.(names) ?? null;
  }

  /// Where a value is kept as a file: the device's, at once.
  storagePath(key: string): string | null {
    return this.inner.storagePath?.(key) ?? null;
  }

  /// A loopback listener (a login's callback): the device's, nothing of a UI's to wait on.
  get listen(): Host["listen"] {
    const inner = this.inner;
    return inner.listen ? (port, host) => inner.listen!(port, host) : undefined;
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

  fetch(request: HttpRequest): Effect.Effect<HttpResponse, HostError> {
    if (hedgeable(request)) {
      const r = { ...request, headers: request.headers.filter(([k]) => k.toLowerCase() !== HEDGE) };
      return hedged(this.wakes, this.inner, Effect.suspend(() => this.inner.fetch(r)));
    }
    return Effect.suspend(() => unlessDropped(this.wakes, this.inner.nowMs(), this.inner.fetch(request)));
  }

  fetchStream(request: HttpRequest): Effect.Effect<StreamResponse, HostError, Scope.Scope> {
    const opening = Effect.suspend(() => unlessDropped(this.wakes, this.inner.nowMs(), this.inner.fetchStream(request)));
    return Effect.map(opening, (response) => ({ ...response, body: quietEnds(this.inner, this.wakes, response.body) }));
  }

  /// Its frames are left to the core (account_state.ts `followSocket`); only its opening is given up.
  websocket(url: string, protocols: string[]): Effect.Effect<Pull<string>, HostError, Scope.Scope> {
    return Effect.suspend(() => unlessDropped(this.wakes, this.inner.nowMs(), this.inner.websocket(url, protocols)));
  }

  storageGet(key: string) {
    return this.inner.storageGet(key);
  }
  storageSet(key: string, value: Uint8Array) {
    return this.inner.storageSet(key, value);
  }
  storageDelete(key: string) {
    return this.inner.storageDelete(key);
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
