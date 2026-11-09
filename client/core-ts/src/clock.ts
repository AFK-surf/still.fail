// Time as the core's computeds read it. What a moment changes (a wait shown once it is slow, a job an hour up, the next
// second of a countdown) is read as `reached(at)`: false until then, and whatever read it is made again as it comes,
// by one timer for that moment while anything reads it, let go with its last reader. Times in words change by the
// minute or the local day (present.ts `clockAt`), which the store moves on (store.ts `setClock`).
import { Effect, type Fiber } from "effect";
import { signal, tracking, untracked, type Source } from "./reactive.ts";
import { laterSleep, type Runner } from "./runtime.ts";

/// The clock times in words are read by, at the grain they change at: the minute, and the local day (each with the
/// offset from UTC). Words made in a computed (output.ts, each item of a list) read the one they change by, and are
/// made again only when it moves: a chat of days ago says its day (11月3日 18:12) until local midnight. Now read in a
/// computed (wake.ts `WakingHost.nowMs`) reads the minute.
export const minute = signal("");
export const day = signal("");

export class Moments {
  readonly #now: () => number;
  readonly #runner: Runner;
  readonly #at = new Map<string, { node: Source<boolean>; fiber: Fiber.Fiber<unknown, unknown> | null }>();

  constructor(now: () => number, runner: Runner) {
    this.#now = now;
    this.#runner = runner;
  }

  /// Whether moment `at` (ms) has come; a computed reading it is made again when it does. `later`: nothing shown
  /// waits for it (a shown clock's next second: runtime.ts `laterSleep`).
  reached(at: number, later = false): boolean {
    const now = untracked(this.#now);
    if (now >= at) return true;
    if (!tracking()) return false;
    const key = `${at}${later ? "/later" : ""}`;
    let m = this.#at.get(key);
    if (!m) {
      const made: { node: Source<boolean>; fiber: Fiber.Fiber<unknown, unknown> | null } = {
        node: signal(false, () => {
          this.#at.delete(key);
          if (made.fiber) this.#runner.interrupt(made.fiber);
        }),
        fiber: null,
      };
      m = made;
      this.#at.set(key, m);
      made.fiber = this.#runner.fork(
        Effect.suspend(() => { const ms = Math.max(at - this.#now(), 0); return later ? laterSleep(ms) : Effect.sleep(ms); }).pipe(
          Effect.andThen(Effect.sync(() => {
            made.fiber = null;
            this.#at.delete(key);
            made.node.set(true);
          })),
        ),
      ) as Fiber.Fiber<unknown, unknown>;
    }
    m.node.get();
    return false;
  }
}
