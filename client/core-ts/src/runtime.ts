// Where the core's work runs (host.rs `spawn` and `sleep`): fibers on Effect's runtime, every timer on its Clock — the
// live one, or a TestClock in tests (docs/station-ts.md, 写法：Effect). Nothing in the core calls setTimeout itself.
import { Cause, Clock, Effect, Exit, Fiber } from "effect";

export class Runner {
  readonly clock: Clock.Clock | null;
  readonly #fibers = new Set<Fiber.Fiber<unknown, unknown>>();
  #closed = false;
  /// Told of a task that died (a bug): a native host ends the core, as a panic does.
  onDefect: (error: unknown) => void = (error) => {
    console.error("core task failed", error);
  };

  constructor(clock?: Clock.Clock) {
    this.clock = clock ?? null;
  }

  #provide<A, E>(effect: Effect.Effect<A, E>): Effect.Effect<A, E> {
    return this.clock ? effect.pipe(Effect.provideService(Clock.Clock, this.clock)) : effect;
  }

  /// Runs an effect as a fiber of its own; interrupting it (`Fiber.interrupt`) stops it where it waits.
  fork<A, E>(effect: Effect.Effect<A, E>): Fiber.Fiber<A, E> {
    const fiber = Effect.runFork(this.#provide(effect));
    if (this.#closed) {
      Effect.runFork(Fiber.interrupt(fiber));
      return fiber;
    }
    this.#fibers.add(fiber);
    fiber.addObserver((exit) => {
      this.#fibers.delete(fiber);
      if (Exit.isFailure(exit) && !Cause.hasInterruptsOnly(exit.cause)) this.onDefect(Cause.squash(exit.cause));
    });
    return fiber;
  }

  /// An effect's result as a promise (for the async code around it).
  run<A, E>(effect: Effect.Effect<A, E>): Promise<A> {
    return Effect.runPromise(this.#provide(effect));
  }

  /// Waits `ms` on the core's clock.
  sleep(ms: number): Promise<void> {
    if (ms <= 0) return this.run(Effect.yieldNow);
    return this.run(Effect.sleep(ms));
  }

  /// Runs an async task to its end on the core (host.rs `spawn`): what it throws is a bug, said as such.
  spawn(task: () => Promise<unknown>): void {
    if (this.#closed) return;
    task().catch((error) => this.onDefect(error));
  }

  /// Stops everything still running (the core is let go).
  close(): void {
    this.#closed = true;
    for (const fiber of this.#fibers) Effect.runFork(Fiber.interrupt(fiber));
    this.#fibers.clear();
  }

  interrupt(fiber: Fiber.Fiber<unknown, unknown>): void {
    Effect.runFork(Fiber.interrupt(fiber));
  }
}

/// A sleep that can be called off: `done` resolves after `ms` on the clock, or never once `cancel` is called.
export function timer(runner: Runner, ms: number): { done: Promise<void>; cancel(): void } {
  let resolve!: () => void;
  const done = new Promise<void>((r) => (resolve = r));
  const fiber = runner.fork(Effect.sleep(Math.max(0, ms)).pipe(Effect.andThen(Effect.sync(() => resolve()))));
  return { done, cancel: () => runner.interrupt(fiber) };
}
