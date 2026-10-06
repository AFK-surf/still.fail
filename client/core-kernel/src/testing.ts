// Time for tests: a TestClock the test moves (`pass`), with every sleep asked of it noted, and the wall clock read
// from it. A core given `time.clock` (Runner) sleeps on it: what a test waits for happens when it says, however fast
// or slow the machine is.
import { Duration, Effect, Scope, type Clock } from "effect";
import { TestClock } from "effect/testing";

export class TestTime {
  readonly clock: Clock.Clock;
  readonly #test: TestClock.TestClock;
  /// Every sleep asked for (ms), in order: timers show here.
  readonly sleeps: number[] = [];
  /// What the clock read at its zero: the TestClock starts at 0, and the wall clock is this from there.
  readonly #base: number;

  constructor(start = Date.UTC(2026, 0, 1)) {
    const scope = Effect.runSync(Scope.make());
    this.#test = Effect.runSync(Scope.provide(TestClock.make(), scope)) as TestClock.TestClock;
    this.#base = start;
    const test = this.#test;
    const base = start;
    const sleeps = this.sleeps;
    this.clock = {
      ...test,
      currentTimeMillisUnsafe: () => base + test.currentTimeMillisUnsafe(),
      currentTimeMillis: Effect.sync(() => base + test.currentTimeMillisUnsafe()),
      sleep(duration: Duration.Duration) {
        sleeps.push(Duration.toMillis(duration));
        return test.sleep(duration);
      },
    } as Clock.Clock;
  }

  now(): number {
    return this.#base + this.#test.currentTimeMillisUnsafe();
  }

  /// Lets `ms` of the core's time pass, in small steps, so what each step wakes runs (and sleeps again) before the next.
  async pass(ms: number, step = 10): Promise<void> {
    await flush();
    let left = ms;
    while (left > 0) {
      const d = Math.min(step, left);
      await Effect.runPromise(this.#test.adjust(d));
      left -= d;
      await flush();
    }
    await flush();
  }
}

/// Lets what is ready run: promise continuations and the runtime's scheduled fibers.
export async function flush(rounds = 6): Promise<void> {
  const turn = typeof setImmediate === "function" ? (r: () => void) => setImmediate(r) : (r: () => void) => setTimeout(r, 0);
  for (let i = 0; i < rounds; i++) await new Promise<void>(turn);
}
