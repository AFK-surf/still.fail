# Motion the Effect way

In mbui an animation is a fiber of the window's runtime (docs/effect.md). The fiber steps its value once a frame on the frames' clock. At the start of each frame the runtime runs first, so every value is already where it should be at the frame's time when the view reads it. The view reads values synchronously (`Value::get`), like any other state in immediate-mode code.

Because an animation is a fiber, it composes the way Effect code does: one after another, together, staggered, interrupted, and scoped. A test can step it frame by frame on the Tester's clock.

The code is in `src/motion/fx.mbt`, with tests in `src/motion/fx_test.mbt`. The transitions come from the same package: Motion's generators (`generators.mbt`, `transition.mbt`) and Compose's specs (`spec.mbt`).

## Motion → mbui

| Motion (motion.dev) | mbui |
|---|---|
| `useMotionValue(0)` | `@motion.value(c, "x", 0.0)`, a `Value` kept by key |
| `mv.get()`, `mv.getVelocity()` | `v.get()`, `v.velocity()` (per second) |
| `animate(mv, 100, { type: "spring", … })` | `v.start(100.0, spring_to(…))` returns the animation's `Fiber[Bool]`. Inside a fiber, `v.animate(100.0, spring_to(…))` waits until the value arrives; it returns true when the animation finished and false when another animation took the value over |
| `mv.set(x)` / `mv.jump(x)`, `mv.stop()` | `v.set(x)`, `v.stop()` |
| the `animate` prop: animate whenever the target changes | `v.follow(target, spec)`: does nothing while the target stays the same |
| transitions: `spring` (physics, or duration/visual duration and bounce), `tween`, keyframes, `inertia`, `delay` | `spring_to`, `tween_to`, `keyframes_to`, `inertia_to` (each with `delay=`); also Compose's `spring` and `tween` |
| a new animation interrupts the old one, and the value keeps its velocity | the same. The new animation samples the old one *at that instant*, so the result does not depend on which fiber ran first in that frame (tested over 30 seeds) |
| sequences, `await animate(…)` | lines that run one after another in a fiber |
| animating several values at once | `@effect.all([() => x.animate(…), () => y.animate(…)])` |
| `stagger(0.05, { from })` | `stagger(n, 50, from=First / Last / Center / Index(i), i => …)` |
| `AnimatePresence` with an `exit` | `animate_presence(c, key, shown, enter=…, exit=…, body)` (see below) |
| `whileHover`, `whileTap` | `while_hover(c, id, v, rest=…, to=…)`, `while_press(…)` |
| `drag`, `dragConstraints`, `dragElastic`, drag momentum | `drag_value(c, id, v, min=, max=, elastic=0.5)` on a `Ctx::drag_area`. When released it continues with Motion's drag inertia: power 0.8, time constant 750 ms, and a spring at the bounds |
| the `layout` prop (FLIP through projection) | `animate_layout(c, node, key, spec)` |
| `useReducedMotion` | `Ctx::still()`: under reduced motion and in screenshots every value goes straight to its end |

## Timing

An animation started from a handler in the frame at time T starts at T. Its first frame is the next one, and that frame shows the transition 16 ms in. Motion behaves the same way: its start time is the frame time at which `animate` was called.

So the value the view reads in frame *n* after the start is exactly the generator's value at *n* × 16 ms. The tests check that frame by frame.

Once the value arrives, the fiber ends and the window stops asking for frames.

## Presence

Each time the content is shown, it gets its own scope, and `enter` runs as a fiber of that scope. When `shown` turns false:

- the scope closes, which interrupts `enter`;
- `exit` runs as the scope's finalizer, while `body` is still drawn, but draw-only (it takes no taps and nothing finds it on screen);
- when the finalizer finishes, `body` is no longer built.

If the content is shown again during the exit, it comes back immediately. Its `enter` interrupts what `exit` was animating, so it starts from wherever the exit had got to.

If the code that calls `animate_presence` is not built in some frame, its scopes close at once and no exit is drawn. This matches Motion's `AnimatePresence` being unmounted.

```moonbit
let o = @motion.value(c, "sheet/o", 0.0)
let y = @motion.value(c, "sheet/y", 40.0)
@motion.animate_presence(c, "sheet", open,
  enter=async fn() {
    ignore(@effect.all([
      () => o.animate(1.0, @motion.tween_to(duration=150.0)),
      () => y.animate(0.0, @motion.spring_to(bounce=0.2)),
    ]))
  },
  exit=async fn() { ignore(o.animate(0.0, @motion.tween_to(duration=120.0))) },
  fn() {
    let i = c.box(fn() { sheet_body(c) })
    c.look(i, @ui.look(alpha=o.get(), dy=y.get()))
  },
) |> ignore
```

## Layout

Every frame, after layout, `animate_layout` compares the node's laid-out box with its box from the last layout. When the box has changed:

1. The node's starting box is the box it is drawn in right now, which may be partway through an earlier animation.
2. A progress value restarts at 0, and a fiber animates it to 1.
3. Each frame, the node is drawn in the box that is the progress-mix of the start and the new box. The look that takes the laid-out box onto it (translate, plus scale about the centre) comes from Motion's projection: `calc_box_delta`.

The look only changes how the node is drawn. Taps still go where the node is laid out. Rows of a list use the older `layout` and `list_keys` in `layer.mbt`, which also handle rows entering, leaving and being scrolled.

## Tests

- `src/motion/fx_test.mbt`, on the Tester's clock:
  - the value at each frame equals the generator's value;
  - sequences, `all` and `stagger` start at the expected times;
  - interruption carries velocity, with identical frames across 30 seeds;
  - a superseded `animate` returns false;
  - interrupting the waiting fiber stops the animation;
  - presence: enter, exit while still drawn, then gone; shown again during the exit;
  - hover; drag with momentum and bounds;
  - a layout move at 20 px a frame.
- Run them with `moon test --target js src/motion/fx_test.mbt`, or as part of `scripts/test.sh`.
