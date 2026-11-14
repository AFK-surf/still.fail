// The UI coming back after being away, or the network changing under it: what is under way is suspect.
//
// - a request still unanswered that has waited a while (QUIET_MS) fails, for its caller to ask again;
// - a stream that heard nothing for a while ends, and is opened again;
// - what waits to reconnect stops waiting (`Wakes.next`);
// - the host lets its connections go (`Host.resetConnections`).
// When the network changed, everything under way fails. A person asking to try again (`retry`) is taken as the
// connections suspect, not gone. WakingHost does the first two for everything that goes through the host.
import * as clock from "./clock.ts";
import { Deferred, Effect, Scope } from "effect";
import { HostError } from "./error.ts";
import type { BaseHost, ClientId, HostOf, HttpRequest, HttpResponse, Pull, StreamResponse } from "./host-of.ts";
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

/// Whether a request may be asked twice: a read, or one that says so though it is none, by a header named `mark`
/// (the program's own name for it, in lower case; the still.fail core's: host.ts `HEDGE`), taken off before it goes
/// (`WakingHost.fetch`). No `mark`: reads alone.
export function hedgeable(request: HttpRequest, mark?: string): boolean {
  const m = request.method.toUpperCase();
  return m === "GET" || m === "HEAD" || (mark !== undefined && request.headers.some(([k]) => k.toLowerCase() === mark));
}

const HEDGES = 3;

/// A write sent again changes nothing the first did not, whatever became of the first: one that puts a value (PUT,
/// PATCH: still.fail cloud's set what they are given). Not a DELETE: sent again after the first went through, it is
/// answered "not found". (A read is asked again by what keeps it, the sync, and at a wake beside itself: `hedged`.)
export function resendable(request: HttpRequest, mark?: string): boolean {
  const m = request.method.toUpperCase();
  return !hedgeable(request, mark) && (m === "PUT" || m === "PATCH");
}

/// How long a request that failed with no answer waits for the network to come back before it is sent again.
export const RESEND_MS = 2_000;

/// A request that may be sent again, failed under the core (no answer: its connection broke, the network went or
/// changed as it went out): sent once more as the UI is next back or the network changes, or after RESEND_MS, the
/// second's outcome its own. 2026-11-13: a station's icon taken away on a phone failed with 网络连接失败, the request
/// never reaching still.fail cloud, as the phone's network changed under it; the same asked again went through.
export function resentOnce<A>(wakes: Wakes, ask: Effect.Effect<A, HostError>): Effect.Effect<A, HostError> {
  return Effect.catch(ask, () =>
    Effect.raceFirst(Effect.asVoid(wakes.next), Effect.sleep(RESEND_MS)).pipe(Effect.andThen(ask)), // timer: a retry after a failure
  );
}

/// `pending`, unless a wake says it went out before the UI was away: then an error.
export function unlessDropped<A, R>(wakes: Wakes, sent: number, pending: Effect.Effect<A, HostError, R>): Effect.Effect<A, HostError, R> {
  const dropped = wakes.until((w) => w.dropsRequest(sent)).pipe(Effect.flatMap((w) => Effect.fail(new HostError(w.network ? NETWORK : DROPPED))));
  return Effect.raceFirst(pending, dropped);
}

/// A request that may be asked twice: asked again at each wake that suspects what it went on (up to HEDGES at once),
/// the first answer its answer; one that fails leaves it to the others.
export function hedged<A>(wakes: Wakes, host: Pick<BaseHost, "nowMs">, ask: Effect.Effect<A, HostError>): Effect.Effect<A, HostError> {
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
export function quietEnds<A>(host: Pick<BaseHost, "nowMs">, wakes: Wakes, pull: Pull<A>): Pull<A> {
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

/// The host the core runs on, with the rules above for its requests and streams; its UIs sent what the inner one's
/// are (`Message`). `hedge`: the header a request of its says to be asked twice by (`hedgeable`'s `mark`).
export class WakingHost<Message = never> implements HostOf<Message> {
  readonly inner: HostOf<Message>;
  readonly wakes: Wakes;
  readonly hedge: string | undefined;

  /// The inner host's record, as it is now (a test sets its own after the core starts).
  get recorder(): HostOf<Message>["recorder"] {
    return this.inner.recorder;
  }
  /// This device's own adb session is held independently of any station or UI wake.
  get adb(): HostOf<Message>["adb"] {
    return this.inner.adb;
  }
  readonly tcp?: HostOf<Message>["tcp"];
  readonly appKeys?: boolean;
  readonly handOverByTests?: boolean;
  readonly handOverAuto?: boolean;
  readonly openDb?: HostOf<Message>["openDb"];
  readonly memoryDb?: HostOf<Message>["memoryDb"];
  readonly deleteDb?: HostOf<Message>["deleteDb"];
  readonly report?: HostOf<Message>["report"];
  readonly legacyRead?: HostOf<Message>["legacyRead"];
  readonly secureGet?: HostOf<Message>["secureGet"];
  readonly secureSet?: HostOf<Message>["secureSet"];
  readonly secureDelete?: HostOf<Message>["secureDelete"];
  readonly securePast?: HostOf<Message>["securePast"];
  readonly secureAsk?: HostOf<Message>["secureAsk"];
  readonly savedRead?: HostOf<Message>["savedRead"];
  readonly stage?: HostOf<Message>["stage"];
  readonly unzstd?: HostOf<Message>["unzstd"];
  readonly ed25519Sign?: HostOf<Message>["ed25519Sign"];
  readonly verify?: HostOf<Message>["verify"];

  constructor(inner: HostOf<Message>, wakes: Wakes, hedge?: string) {
    this.inner = inner;
    this.wakes = wakes;
    this.hedge = hedge;
    if (inner.tcp) this.tcp = (port) => inner.tcp!(port);
    this.appKeys = inner.appKeys;
    this.handOverByTests = inner.handOverByTests;
    this.handOverAuto = inner.handOverAuto;
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
    if (inner.securePast) this.securePast = (key) => inner.securePast!(key);
    if (inner.secureAsk) this.secureAsk = (reason) => inner.secureAsk!(reason);
    // A file the app saved on the device, read back: the device's too.
    if (inner.savedRead) this.savedRead = (at, start, end) => inner.savedRead!(at, start, end);
    if (inner.stage) this.stage = (name, offset, bytes) => inner.stage!(name, offset, bytes);
    // A reply taken apart: on the device, as it comes.
    if (inner.unzstd) this.unzstd = () => inner.unzstd!();
    // A signature: the device's, at once.
    if (inner.ed25519Sign) this.ed25519Sign = (seed, message) => inner.ed25519Sign!(seed, message);
    if (inner.verify) this.verify = (alg, key, signature, message) => inner.verify!(alg, key, signature, message);
  }

  /// Names in the order people read them: the system's, at once (the files page's: drive-browse.ts).
  collate(names: readonly string[]): number[] | null {
    return this.inner.collate?.(names) ?? null;
  }

  /// Where a value is kept as a file: the device's, at once.
  storagePath(key: string): string | null {
    return this.inner.storagePath?.(key) ?? null;
  }

  /// Where a picture is fetched from: the device's, at once.
  pictureVia(url: string): string {
    return this.inner.pictureVia?.(url) ?? url;
  }

  /// A loopback listener (a login's callback): the device's, nothing of a UI's to wait on.
  get listen(): HostOf<Message>["listen"] {
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
    if (hedgeable(request, this.hedge)) {
      const r = { ...request, headers: request.headers.filter(([k]) => k.toLowerCase() !== this.hedge) };
      return hedged(this.wakes, this.inner, Effect.suspend(() => this.inner.fetch(r)));
    }
    const once = Effect.suspend(() => unlessDropped(this.wakes, this.inner.nowMs(), this.inner.fetch(request)));
    return resendable(request, this.hedge) ? resentOnce(this.wakes, once) : once;
  }

  fetchStream(request: HttpRequest): Effect.Effect<StreamResponse, HostError, Scope.Scope> {
    const opening = Effect.suspend(() => unlessDropped(this.wakes, this.inner.nowMs(), this.inner.fetchStream(request)));
    return Effect.map(opening, (response) => ({ ...response, body: quietEnds(this.inner, this.wakes, response.body) }));
  }

  /// Its frames are left to the core; only its opening is given up.
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

  /// Now; read in a computed, by the minute (clock.ts): what it made is made again as the minute moves on.
  nowMs(): number {
    clock.minute.get();
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
  emit(client: ClientId, message: Message): void {
    this.inner.emit(client, message);
  }
}
