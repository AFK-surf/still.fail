// The long-lived work of a part of the accounts (timers, a run of checks, a sign-in's command): fibers in the part's
// own scope, so they end when the part closes (docs/station-ts.md, 写法).
import { Effect, Exit, Fiber, FiberSet, Scope } from "effect";
import { log } from "../ops/log.ts";

export class Background {
  private scope: Scope.Closeable;
  private fork: (effect: Effect.Effect<unknown, unknown, never>) => Fiber.Fiber<unknown, unknown>;
  private closed = false;
  private what: string;

  constructor(what: string) {
    this.what = what;
    this.scope = Effect.runSync(Scope.make());
    this.fork = Effect.runSync(Scope.provide(FiberSet.makeRuntime<never, unknown, unknown>(), this.scope));
  }

  /// Runs `f` as a fiber of this part's; what it throws is logged.
  spawn(f: () => Promise<unknown>): void {
    if (this.closed) return;
    this.fork(Effect.promise(() => f().catch((e) => log.warn(this.what, "background work failed", { error: (e as Error)?.message ?? String(e) }))));
  }

  /// Runs `f` after `ms`, unless cancelled (the function returned) or the part closed first.
  later(ms: number, f: () => unknown): () => void {
    if (this.closed) return () => {};
    const fiber = this.fork(
      Effect.sleep(Math.max(0, ms)).pipe(
        Effect.andThen(
          Effect.promise(async () => {
            try {
              await f();
            } catch (e) {
              log.warn(this.what, "background work failed", { error: (e as Error)?.message ?? String(e) });
            }
          }),
        ),
      ),
    );
    return () => void Effect.runFork(Fiber.interrupt(fiber));
  }

  /// Runs `f` every `ms` (the first after `ms`) until the part closes.
  every(ms: number, f: () => unknown): void {
    if (this.closed) return;
    this.fork(
      Effect.forever(
        Effect.sleep(ms).pipe(
          Effect.andThen(
            Effect.promise(async () => {
              try {
                await f();
              } catch (e) {
                log.warn(this.what, "background work failed", { error: (e as Error)?.message ?? String(e) });
              }
            }),
          ),
        ),
      ),
    );
  }

  async close(): Promise<void> {
    if (this.closed) return;
    this.closed = true;
    await Effect.runPromise(Scope.close(this.scope, Exit.void));
  }
}
