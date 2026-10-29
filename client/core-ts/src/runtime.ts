// Where the core's work runs: fibers on Effect's runtime, in scopes, every timer on its Clock — the live one, or a
// TestClock in tests. What arrives from outside (a UI's message, a host callback) is synchronous; it starts fibers
// here. Nothing in the core calls setTimeout itself.
import { Cause, Clock, Effect, Exit, Fiber, FiberSet, Logger, Scope } from "effect";

/// A scope and the fibers forked in it: closing it interrupts them, and anything else that was opened in it.
export type Scoped = { readonly scope: Scope.Closeable; readonly fibers: FiberSet.FiberSet<unknown, unknown> };

/// Waits `ms` as Effect.sleep does, for what nothing shown waits on: what comes again by itself (a keepalive, a
/// measurement's next sample, a shown clock's next second) or does nothing to what is shown (traces sent, a cache let
/// go). A host that keeps the core's timers on an app's own clock (an mbui app in a run on a clock of its own,
/// apps/mbui/core/clock.ts) is told so of the timer it sets: such a run is at rest while only these are set. A wait
/// that may change what is shown (a retry, a request's time running out) is Effect.sleep.
export function laterSleep(ms: number): Effect.Effect<void> {
  return Effect.suspend(() => {
    // (the next timer set for these ms, which this sleep sets at once on the live clock)
    (globalThis as { __stillfail_later?: number }).__stillfail_later = ms;
    return Effect.sleep(ms);
  });
}

export class Runner {
  readonly clock: Clock.Clock | null;
  /// The core's own: closing it ends everything.
  readonly root: Scoped;
  #closed = false;
  /// Told of a fiber that failed with a bug: a native host starts the core anew.
  onDefect: (error: unknown) => void = (error) => {
    console.error("core fiber failed", error);
  };
  /// Told of a failure let go of on purpose (`Effect.ignore(…, { log: "Unhandled", message: what })`): what nothing
  /// waited on still leaves a trace (core.ts records it as a failed span).
  onIgnored: (what: string, error: unknown) => void = (what, error) => {
    console.warn("core let a failure go", what, error);
  };
  /// Where what the core's fibers log goes: only failures let go of are logged.
  readonly #loggers = new Set([
    Logger.make(({ message, cause }) => {
      if (cause.reasons.length === 0) return;
      this.onIgnored((Array.isArray(message) ? message : [message]).join(" "), Cause.squash(cause));
    }),
  ]);

  constructor(clock?: Clock.Clock) {
    this.clock = clock ?? null;
    const scope = Effect.runSync(Scope.make());
    this.root = { scope, fibers: Effect.runSync(Scope.provide(FiberSet.make(), scope)) };
  }

  /// The effect with the core's clock and loggers.
  provide<A, E, R>(effect: Effect.Effect<A, E, R>): Effect.Effect<A, E, R> {
    const logged = effect.pipe(Effect.provideService(Logger.CurrentLoggers, this.#loggers));
    return this.clock ? logged.pipe(Effect.provideService(Clock.Clock, this.clock)) : logged;
  }

  /// Runs an effect as a fiber of `scoped` (the core's by default): interrupted when it closes. A failure that is no
  /// interruption is a bug, told to `onDefect`.
  fork<A, E>(effect: Effect.Effect<A, E>, scoped: Scoped = this.root): Fiber.Fiber<A, E> {
    const fiber = Effect.runFork(this.provide(effect));
    fiber.addObserver((exit) => {
      if (Exit.isFailure(exit) && !Cause.hasInterruptsOnly(exit.cause)) this.onDefect(Cause.squash(exit.cause));
    });
    FiberSet.addUnsafe(scoped.fibers, fiber as Fiber.Fiber<unknown, unknown>);
    return fiber;
  }

  /// An effect's result as a promise (hosts' entries, tests).
  run<A, E>(effect: Effect.Effect<A, E>): Promise<A> {
    return Effect.runPromise(this.provide(effect));
  }

  /// A scope inside `parent` (a topic's, a link's).
  child(parent: Scoped = this.root): Scoped {
    const scope = Effect.runSync(Scope.fork(parent.scope));
    return { scope, fibers: Effect.runSync(Scope.provide(FiberSet.make(), scope)) };
  }

  /// Closes a scope: what runs in it is interrupted.
  close(scoped: Scoped): void {
    Effect.runFork(Scope.close(scoped.scope, Exit.void));
  }

  interrupt(fiber: Fiber.Fiber<unknown, unknown>): void {
    Effect.runFork(Fiber.interrupt(fiber));
  }

  /// Stops everything (the core is let go).
  shutdown(): void {
    if (this.#closed) return;
    this.#closed = true;
    this.close(this.root);
  }

  get closed(): boolean {
    return this.#closed;
  }
}
