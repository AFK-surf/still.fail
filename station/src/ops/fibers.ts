// Time and long-lived work for a part that is a class rather than an Effect itself (a service holds it: services.ts):
// its `now` and its waits from the Clock it was given (a TestClock in its tests; the live one otherwise), each wait or
// piece of background work a fiber in a scope of its own, all interrupted when it closes (docs/station-ts.md, 写法).
// The station reads no Date.now and arms no Node timer of its own: a test moves its time, and nothing escapes it. (A
// deadline on a real socket, AbortSignal.timeout on a fetch, is the network's time, not the station's.)
import { Clock, Duration, Effect, Exit, Fiber, FiberSet, Scope } from "effect";
import { log } from "./log.ts";

/// The live Clock, for a part given none.
export const liveClock: Clock.Clock = Effect.runSync(Clock.clockWith(Effect.succeed));

export class Fibers {
  readonly clock: Clock.Clock;
  readonly #what: string;
  readonly #scope: Scope.Closeable;
  readonly #run: <A, E>(effect: Effect.Effect<A, E>) => Fiber.Fiber<A, E>;
  #closed = false;

  /// `what`: the part, as its log lines name it.
  constructor(what: string, clock?: Clock.Clock) {
    this.#what = what;
    this.clock = clock ?? liveClock;
    this.#scope = Effect.runSync(Scope.make());
    const runtime = Effect.runSync(Scope.provide(FiberSet.makeRuntime<never, unknown, unknown>(), this.#scope));
    const c = this.clock;
    this.#run = (effect) => runtime(effect.pipe(Effect.provideService(Clock.Clock, c))) as never;
  }

  /// Milliseconds since the epoch, on this part's clock.
  now(): number {
    return this.clock.currentTimeMillisUnsafe();
  }

  /// Runs `effect` in this part's scope, on its clock.
  fork<A, E>(effect: Effect.Effect<A, E>): Fiber.Fiber<A, E> {
    return this.#run(effect);
  }

  /// Runs `effect` on this part's clock, outside its scope: what a caller waits for.
  run<A, E>(effect: Effect.Effect<A, E>): Promise<A> {
    return Effect.runPromise(effect.pipe(Effect.provideService(Clock.Clock, this.clock)));
  }

  /// Resolves `ms` from now, by this part's clock.
  sleep(ms: number): Promise<void> {
    return Effect.runPromise(this.clock.sleep(Duration.millis(Math.max(0, ms))));
  }

  /// Runs `f` as a fiber of this part's; what it throws is logged.
  spawn(f: () => Promise<unknown>): void {
    if (this.#closed) return;
    this.#run(this.#guarded(f));
  }

  /// `f` once, `ms` from now, unless called off (the function returned) or the part closed first.
  after(ms: number, f: () => unknown): () => void {
    if (this.#closed) return () => {};
    return this.#cancel(this.#run(Effect.andThen(Effect.sleep(Duration.millis(Math.max(0, ms))), this.#guarded(f))));
  }

  /// `f` every `ms` (the first `ms` from now) until stopped (the function returned) or the part closes.
  every(ms: number, f: () => unknown): () => void {
    if (this.#closed) return () => {};
    return this.#cancel(this.#run(Effect.forever(Effect.andThen(Effect.sleep(Duration.millis(ms)), this.#guarded(f)))));
  }

  /// Stops every wait and piece of work it has going; resolved once they are stopped.
  async close(): Promise<void> {
    if (this.#closed) return;
    this.#closed = true;
    await Effect.runPromise(Scope.close(this.#scope, Exit.void));
  }

  #guarded(f: () => unknown): Effect.Effect<void> {
    return Effect.promise(async () => {
      try {
        await f();
      } catch (e) {
        log.warn(this.#what, "background work failed", { error: (e as Error)?.message ?? String(e) });
      }
    });
  }

  #cancel(fiber: Fiber.Fiber<unknown, unknown>): () => void {
    return () => void Effect.runFork(Fiber.interrupt(fiber));
  }
}

/// `what`, failed with `why` if it is not settled within `ms` on `clock`.
export function within<A>(clock: Clock.Clock, ms: number, what: Promise<A>, why: () => Error): Promise<A> {
  return Effect.runPromise(
    Effect.timeoutOrElse(Effect.tryPromise({ try: () => what, catch: (e) => e }), {
      duration: Duration.millis(ms),
      orElse: () => Effect.fail(why()),
    }).pipe(Effect.provideService(Clock.Clock, clock)),
  );
}

/// The machine's own time, for what the station shares with other programs or waits on them for (a file's mtime they
/// compare, a login's or a credential's expiry they read too, a lock's heartbeat; how long a child process, a socket or
/// a peer is given to answer): on the live Clock whatever clock a part was given, as theirs is.
export const wall = {
  now: (): number => liveClock.currentTimeMillisUnsafe(),
  sleep: (ms: number): Promise<void> => Effect.runPromise(liveClock.sleep(Duration.millis(Math.max(0, ms)))),
  /// `f` once, `ms` from now; the returned function calls it off.
  after(ms: number, f: () => void): () => void {
    const fiber = Effect.runFork(Effect.andThen(liveClock.sleep(Duration.millis(Math.max(0, ms))), Effect.sync(f)));
    return () => void Effect.runFork(Fiber.interrupt(fiber));
  },
  /// `f` every `ms`; the returned function stops it.
  every(ms: number, f: () => void): () => void {
    const fiber = Effect.runFork(Effect.forever(Effect.andThen(liveClock.sleep(Duration.millis(ms)), Effect.sync(f))));
    return () => void Effect.runFork(Fiber.interrupt(fiber));
  },
  /// `what`, failed with an Error saying `why` if it is not settled within `ms`.
  within: <A>(ms: number, what: Promise<A>, why: string): Promise<A> => within(liveClock, ms, what, () => new Error(why)),
};
