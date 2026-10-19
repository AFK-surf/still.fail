# effect.mb: logic as Effect has it, on the frames' clock

`src/effect` is a small effect system in the manner of Effect-TS, for MoonBit's `async fn`. It has its own scheduler, built on the language's async primitives (`%async.suspend`, `%async.run` and the cancellation intrinsics; `prim.mbt`). moonbitlang/async's event loop is not used: it has no virtual clock and no seeded order, and it owns the loop, while here the UI does.

Everything an mbui window runs (UI, animation and logic) is on one runtime and one clock, the frames' clock. Under test that is the Tester's clock, and a seed decides the order ready fibers run in. A test can therefore step the whole program frame by frame and replay a failure by its seed.

## Effect-TS → effect.mb

| Effect-TS | effect.mb |
|---|---|
| `Effect<A, E, R>`, `Effect.gen` | `async fn … -> A raise E`, written top to bottom; `R` is a struct of functions passed in (`Net`, `Files`, `host_call`), each with a simulated version |
| `fail`, `catchAll`, `orElse` | `raise`, `catch`, `try … catch … noraise` |
| `Effect.ensuring`, `onExit` | `defer` (it runs on interruption too) |
| `Effect.fork`, `forkScoped`, `FiberSet` | `Runtime::fork`, `Scope::fork`, `Ctx::fork` |
| `Fiber.join`, `await`, `interrupt` | `Fiber::join` (an interruption is raised as `Interrupt`), `wait` (gives back an `Exit`), `interrupt`, `interrupt_and_wait`, `poll` |
| `Scope`, `addFinalizer`, `acquireRelease`, `Effect.scoped` | `Scope`, `add_finalizer`, `acquire_release`, `scoped`. Closing a scope interrupts its fibers and waits for them, then runs its finalizers last to first, uninterruptibly |
| `uninterruptible` | `uninterruptible` |
| `race`, `raceFirst`, `all`, `timeout` | `race`, `race_first`, `all` (failures after the first go to `on_defect`), `timeout` |
| `Deferred`, `Queue`, `Semaphore` | `Deferred`, `Queue` (bounded or unbounded, with shutdown), `Semaphore` |
| `Effect.sleep`, `TestClock.adjust` | `sleep`; virtual time: `advance`, `settle`, `frame` |
| `Effect.yieldNow` | `pause` |
| (a component's lifetime, React's `useEffect`) | `Ctx::lifetime(key)`, `Ctx::effect(key, f)` |
| `Random` with a seed | `Rng`, `rt.rng`; `for_seeds`, `SEED=<n>` |

Some things differ from Effect:
- **Where a fiber can be interrupted.** Effect can interrupt between any two steps. Here a fiber is interrupted only where it suspends (`sleep`, `next_frame`, `pause`, `wait`, `take`, `park`) or where an `uninterruptible` region ends. Code between two suspensions is atomic.
- **Errors.** A function raises one error type, so there are no `E1 | E2` unions. The combinators raise `Error`.
- **No `Cause` tree.** `all` raises the first failure and reports any others to `on_defect`. `race` raises `BothFailed` when both sides fail.

## One clock: the window's runtime (`src/ui/fx.mbt`)

`@ui.runtime()` is the window's runtime. Every frame goes through it in a fixed order:

1. The runtime moves to the frame's time (`Runtime::frame(t)`). Each timer due by then fires at its own time, and what it wakes runs before the next one fires. Then the fibers waiting for a frame (`next_frame()`) resume, all at `t`.
2. The view is built, and it reads synchronously whatever the fibers left. Handlers may fork fibers. A forked fiber first runs at the start of the next frame, before the clock moves: what became ready at a time runs at that time. So a fiber forked by a tap in the frame at 1032 reads `now()` 1032 when it first runs.
3. When the frame ends, lifetimes whose key was not asked for in this frame close. If a fiber is ready or waits for a frame, another frame is requested. Otherwise the host is asked to wake the window at the next timer.

A host callback that completes a fiber's request between frames (`host_call`, `Deferred::succeed`) asks for a frame through `on_wake`. Every host runs this same code, driven by its own frames. No host has a loop or thread of its own for it.

```moonbit
fn view(c : @ui.Ctx) -> Unit {
  // runs once while "feed" is built; interrupted, finalizers run, once it is not
  c.effect("feed", async fn(scope) {
    scope.add_finalizer(async fn() { close_socket() })
    while true {
      let items = fetch_page()                 // a host_call
      model.items = items
      @effect.sleep(30_000)
    }
  })
  if c.button("Refresh") {
    ignore(c.fork(async fn() { model.items = fetch_page() }))
  }
}
```

## Deterministic tests

- `Tester::new(view, seed=n)` gives the window a fresh runtime. Ready fibers run in an order drawn from `n`; with no seed they run in the order they became ready. `rt.rng` is a second random stream from the same seed, for simulations: jitter, packet loss, timing.
- `t.frame(ms)` moves the UI, the animations and the logic together. Nothing waits for real time.
- `@effect.for_seeds(count=n, run)` runs seeds 1 to n. A failure names its seed: `seed 11: … replay: SEED=11`. Setting `SEED=11` replays that run step for step.
- Effect's own tests (`src/effecttest`) use a `Runtime::new(seed?)` of their own and step it with `advance`, `settle`, `run_ready` or `frame`.
- `src/effectdemo` puts a screen, a chat-like core and a backend behind a `SimNet` with seeded jitter on the window's runtime. Over 200 seeds the fixed app always ends on the latest reply. The buggy app's race is found by one seed, and replaying that seed gives the same trace and the same screen.

## Memory (native is reference-counted)

A runtime holds nothing after its fibers have ended:
- A scope's state is kept apart from the `Scope` handle, so the runtime never holds a handle that points back to it.
- A task's continuation and its watchers are dropped when it ends.
- A sleep that is given up clears its timer's closure, and the timer heap drops such timers in bulk.

`Runtime::holding()` counts what is still held: live fibers, ready tasks, timers, the root scope's fibers and finalizers, and fibers waiting for a frame. A test runs a busy runtime over 20 seeds, shuts it down, and checks that all of these are zero.

## Running the tests

`scripts/effect-test.sh` runs effect's tests on native and JS, then the window runtime's tests and the demo on JS.
