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
| the `layout` prop (FLIP through projection) | `animate_layout(c, node, key, spec, by=…)`: set off by its cause, not by any change of its box (below) |
| still.fail's `moveState(moves, change)` (web/ui/src/motion.ts: a state changed, the listed properties of the listed elements moved from what they showed to what the rules now say, on one clock) | `c.move_state([(name, [css property…])…])` as the state changes, the boxes named with `moves=name` (below) |
| `useReducedMotion` | `Ctx::still()`: under reduced motion and in screenshots every value goes straight to its end |

## Timing

An animation started from a handler in the frame at time T starts at T. Its first frame is the next one, and that frame shows the transition 16 ms in. Motion behaves the same way: its start time is the frame time at which `animate` was called.

So the value the view reads in frame *n* after the start is exactly the generator's value at *n* × 16 ms. The tests check that frame by frame.

Once the value arrives, the fiber ends and the window stops asking for frames.

### The logical clock (what is made once: src/view)

What a view does is advanced by its logical time, never by how many frames are drawn (the user, 2026-10-30: 「按逻辑时钟来」).
The host only wakes the tree and gives it the time; inputs, messages and frames each advance it to their own moment
(Tree::advance) and no further. On that one timeline, in the order of their moments (those due together in the order
told): a node's leaving ending, a step of what goes by steps, an input. A motion that is a function of the time (start,
target, curve) needs no step: its value at a moment is worked out where it is read. One that adds up step after step
(each value from the one before) says so once, with its step and how many (View::steps: a 60th of a second, 60 steps):
every step is taken in its turn, an input coming among them handled between the steps before it and after it, none
skipped and none run as one larger step, however few frames are drawn; drawing only looks at the state as it is.
Nothing else goes by steps (a colour changed starts none), and what owns the steps stops them as it goes.
There is one clock (the user, 2026-10-30: 「时钟还是统一的，只是各自累积」): saying steps starts no clock of its own;
it asks the one clock to stop at its ticks for the stretch said (its rate's ticks from the clock's 0, the first after
its cause: what steps at one rate steps at the same moments, whenever each began), and keeps only what it adds up and
how many it took. A tick's moment is its number alone (60 a second end at the second exactly, no step's length added
up); each step is given its moment. One stopped stops nothing else, and moves no tick. At one moment: what is due by it is done first (a step or an ending due then, before an
input of that moment), and what is due together in the order it was told; an input's handlers all see the moment it
came at, taken once. Drawing may look between steps; it never writes into them, and no step is dropped to catch up.


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

A layout motion is set off by its cause, never by a difference found between frames (docs/determinism.md, "Motion is data"): `by` names what the node moves for (its words, its page, the row over it). After layout, when its box has changed and `by` changed with it:

1. The node's starting box is the box it is drawn in right now, which may be partway through an earlier animation.
2. A progress value restarts at 0, and a fiber animates it to 1.
3. Each frame, the node is drawn in the box that is the progress-mix of the start and the new box. The look that takes the laid-out box onto it (translate, plus scale about the centre) comes from Motion's projection: `calc_box_delta`.

When its box changed and `by` did not (a window resized, a keyboard, a pane made narrower: what holds it moved it), it is in its new box at once; a move of its own going on carries on from there. The look only changes how the node is drawn. Taps still go where the node is laid out. Rows of a list use the older `layout` and `list_keys` in `layer.mbt`, which also handle rows entering, leaving and being scrolled: `layout` takes the same `by`, and a row that names none moves for its list's change.

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

## A state moved to (move_state)

The web moves some changes of state as one: `moveState` (still.fail web/ui/src/motion.ts) reads the listed properties
of the listed elements, makes the change, and moves each property from what it showed to what the rules now give, all
on one clock and curve (380 ms, ease-out by default). `Ctx::move_state` (src/ui/move_state.mbt) is the same, for the
boxes named to be moved (`c.box(moves="dock", …)`, the web's selector):

```moonbit
// brand.tsx moveSidebar
c.move_state([
  ("dock", ["margin-top", "margin-right", "margin-bottom", "margin-left", "border-radius", "background-color", "box-shadow", "--dock-line"]),
  ("sidebar", ["margin-inline-start", "width"]),
])
wide.folded = !wide.folded
```

From that frame the view builds the new state as it always does; each box so named is shown from what it showed as the
move set out to what it is built as now, so what the view builds stays the truth and nothing is held once the move
ends. Properties go by their CSS names (`margin` for its four, `box-shadow` for its blur, fall and colour, `transform`
for `tx` and `ty`); a size moves between two of the same kind (points, or a share: `Pct`); colours mix as Motion's
`mixColor` does. A value of the view's own goes with them where a box lists it by its `--` name, read with
`c.moved("--dock-line", target)`. Said again over a move going on, it goes on from wherever that had got to; boxes of a
name are told apart by their `id`, else by the order they are built in. A move is said once, as data (its start, its
time, its curve): a moment of it is the same stepped frame by frame or jumped to (`src/ui/move_state_wbtest.mbt`).

