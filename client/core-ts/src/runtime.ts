// Where the core's work runs: fibers on Effect's runtime, in scopes, every timer on its Clock — the live one, or a
// TestClock in tests. What arrives from outside (a UI's message, a host callback) is synchronous; it starts fibers
// here. Nothing in the core calls setTimeout itself.
import { Cause, Clock, Effect, Exit, Fiber, FiberSet, Scope } from "effect";

/// A scope and the fibers forked in it: closing it interrupts them, and anything else that was opened in it.
export type Scoped = { readonly scope: Scope.Closeable; readonly fibers: FiberSet.FiberSet<unknown, unknown> };

export class Runner {
  readonly clock: Clock.Clock | null;
  /// The core's own: closing it ends everything.
  readonly root: Scoped;
  #closed = false;
  /// Told of a fiber that failed with a bug: a native host starts the core anew.
  onDefect: (error: unknown) => void = (error) => {
    console.error("core fiber failed", error);
  };

  constructor(clock?: Clock.Clock) {
    this.clock = clock ?? null;
    const scope = Effect.runSync(Scope.make());
    this.root = { scope, fibers: Effect.runSync(Scope.provide(FiberSet.make(), scope)) };
  }

  /// The effect with the core's clock.
  provide<A, E, R>(effect: Effect.Effect<A, E, R>): Effect.Effect<A, E, R> {
    return this.clock ? effect.pipe(Effect.provideService(Clock.Clock, this.clock)) : effect;
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
