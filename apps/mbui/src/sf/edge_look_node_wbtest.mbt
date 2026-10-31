// A column's edge's look as nodes (edge_look_node): each of what it moves on its own way from the moment its state
// changed, whatever frames are drawn (each moment looked at in a run of its own, frames all along or none before it);
// as the old one (edge_look) is wherever nothing of either moves; made as its state is, still; turned back before its
// end, on from where it was; at once where motion is reduced; asking for no frame once it is let go.

///|
/// An edge's look's state from a moment on: over its column, on it, in hand.
priv struct EdgeState {
  at : Double
  over : Bool
  on : Bool
  active : Bool
}

///|
/// What an edge's look draws, where its column is drawn from: its bar (top, height, ink), and its line's parts (how
/// many, the ink of the one at its middle).
priv struct EdgeDrawn {
  bar : Array[(Double, Double, Int64)]
  parts : Int
  middle : Int64?
} derive(Eq, Show, Debug)

///|
/// What is drawn of the column `handle_w` by 200 at (`x0`, 20).
fn edge_drawn(t : @ui.Tester, x0 : Double) -> EdgeDrawn {
  let within = t.drawn_rects().filter(fn(r) { r.0 >= x0 && r.0 < x0 + handle_w })
  let bar = within.filter(fn(r) { r.2 == edge_bar_w }).map(fn(r) { (r.1 - 20.0, r.3, r.4) })
  // (its line's parts as they show: clear ones none of what is seen, drawn or not)
  let parts = within.filter(fn(r) { r.2 == @ui.Space::px(SPx) && (r.4 & 0xFFL) != 0L })
  let middle = if parts.length() > 0 { Some(parts[parts.length() / 2].4) } else { None }
  { bar, parts: parts.length(), middle }
}

///|
/// The node's look at 140 (and, `old`, the old one at 40, as the same states say), `start` its state as it is made,
/// then `steps` at their moments (events, no frame), frames each 16 all along (`frames`) or none: what each draws at
/// `at` (the node's, the old one's).
fn looks_at(
  start : (Bool, Bool, Bool),
  steps : Array[EdgeState],
  at : Double,
  frames : Bool,
  old? : Bool = false,
) -> (EdgeDrawn, EdgeDrawn?, Double) {
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  let over = @signals.signal(start.0, same=fn(a, b) { a == b })
  let on = @signals.signal(start.1, same=fn(a, b) { a == b })
  let active = @signals.signal(start.2, same=fn(a, b) { a == b })
  @ui.set_view_app(fn(root) {
    if old {
      root.box(fn(o) {
        o.over(Is(true)).offset(Is((40.0, 20.0))).width(Is(Some(handle_w))).height(Is(Some(200.0))) |> ignore
        @ui.old(o, fn(c) { edge_look(c, "test", over=over.get(), on=on.get(), active=active.get()) }).grow(Is(1.0))
        |> ignore
      })
      |> ignore
    }
    root.box(fn(n) {
      n.over(Is(true)).offset(Is((140.0, 20.0))).width(Is(Some(handle_w))).height(Is(Some(200.0))) |> ignore
      edge_look_node(n, fn() { over.get() }, fn() { on.get() }, fn() { active.get() }) |> ignore
    })
    |> ignore
  })
  t.draw()
  let t0 = looks_t0(t)
  let tree = @ui.view_tree().unwrap()
  let to = fn(upto : Double) {
    if frames {
      let mut f = t.time() + 16.0
      while f < upto {
        t.frame_at(f)
        f = f + 16.0
      }
    }
    t.advance(upto - t.time())
  }
  for s in steps {
    if s.at > at {
      break
    }
    to(t0 + s.at)
    tree.event(t0 + s.at, fn() {
      over.set(s.over)
      on.set(s.on)
      active.set(s.active)
    })
  }
  to(t0 + at)
  t.frame_at(t0 + at)
  (edge_drawn(t, 140.0), if old { Some(edge_drawn(t, 40.0)) } else { None }, t0)
}

///|
/// Where a run of looks_at begins: a moment just after its first frame, the same in every run.
fn looks_t0(t : @ui.Tester) -> Double {
  t.time() + 10.0
}

///|
/// Shown at 0, on it at 300, in hand at 600, let go at 900, off it at 1000, gone at 1060; and back on it at 1100, off
/// at 1130, on again at 1160 (before the move set out at 1100 would have ended), still on.
let edge_steps : Array[EdgeState] = [
  { at: 0.0, over: true, on: false, active: false },
  { at: 300.0, over: true, on: true, active: false },
  { at: 600.0, over: true, on: true, active: true },
  { at: 900.0, over: true, on: true, active: false },
  { at: 1000.0, over: true, on: false, active: false },
  { at: 1060.0, over: false, on: false, active: false },
  { at: 1100.0, over: true, on: true, active: false },
  { at: 1130.0, over: true, on: false, active: false },
  { at: 1160.0, over: true, on: true, active: false },
]

///|
test "an edge's look as nodes: at each moment of each of its moves the same, looked at with frames all along or with none before; its line drawn in its parts" {
  let ats = [
    0.0, 60.0, 120.0, 250.0, 360.0, 420.0, 500.0, 660.0, 700.0, 800.0, 960.0, 1030.0, 1080.0, 1120.0, 1150.0, 1200.0, 1270.0,
    1290.0, 1400.0,
  ]
  for at in ats {
    let (stepped, _, _) = looks_at((false, false, false), edge_steps, at, true)
    let (jumped, _, _) = looks_at((false, false, false), edge_steps, at, false)
    assert_eq(jumped, stepped, msg="at \{at}: no frame before \{jumped}, frames all along \{stepped}")
    // (one bar at most; no more of its line than shows of it whole: fading, its faintest parts clear)
    assert_true(stepped.bar.length() <= 1 && stepped.parts <= line_parts_seen(), msg="at \{at}: \{stepped}")
  }
  // (shown and its moves over at 250: its bar, no line; in hand at 800: its bar and the parts of its line that show)
  let (shown, _, _) = looks_at((false, false, false), edge_steps, 250.0, false)
  assert_eq((shown.bar.length(), shown.parts), (1, 0), msg="shown: \{shown}")
  let (held, _, _) = looks_at((false, false, false), edge_steps, 800.0, false)
  assert_eq((held.bar.length(), held.parts), (1, line_parts_seen()), msg="in hand: \{held}")
}

///|
test "an edge's look as nodes, made as each state is (nothing of either moving): drawn as the old one is, hidden, shown, on it, in hand; what shows of each as that state has it" {
  let seen = line_parts_seen()
  for s in [
    ((false, false, false), (0, 0)),
    ((true, false, false), (1, 0)),
    ((true, true, false), (1, seen)),
    ((true, true, true), (1, seen)),
  ] {
    let (start, (bars, parts)) = s
    for at in [0.0, 400.0] {
      let (node, old, _) = looks_at(start, [], at, true, old=true)
      assert_eq(Some(node), old, msg="\{start} at \{at}: node \{node}, old \{old}")
      assert_eq((node.bar.length(), node.parts), (bars, parts), msg="\{start} at \{at}")
    }
  }
}

///|
test "an edge's look as nodes, turned back before a move's end: on from where it was then; the end the first move would have had (at 180) nothing of it" {
  // (from hidden: on it at 0, off it at 30, on it again at 60; its bar's height on the way they say, worked out
  // alongside from the run's own moment)
  let steps : Array[EdgeState] = [
    { at: 0.0, over: true, on: true, active: false },
    { at: 30.0, over: true, on: false, active: false },
    { at: 60.0, over: true, on: true, active: false },
  ]
  let (_, _, t0) = looks_at((false, false, false), [], 0.0, false)
  let w = @motion.Way::new(0.0)
  let spec = @motion.tween(edge_bar_ms, ease=Out)
  w.go(1.0, spec, at=t0)
  w.go(0.0, spec, at=t0 + 30.0)
  w.go(1.0, spec, at=t0 + 60.0)
  let (s6, s12) = (@ui.Space::px(S6), @ui.Space::px(S12))
  // (before the first's end, just after it, before the last's end at 240, past it)
  for at in [100.0, 170.0, 190.0, 230.0, 300.0] {
    let (seen, _, t1) = looks_at((false, false, false), steps, at, false)
    let (stepped, _, _) = looks_at((false, false, false), steps, at, true)
    assert_eq(t1, t0)
    assert_eq(stepped, seen, msg="at \{at}: frames all along \{stepped}, none \{seen}")
    assert_eq(seen.bar.map(fn(b) { b.1 }), [s6 + (s12 - s6) * w.value_at(t0 + at)], msg="at \{at}: \{seen}")
  }
}

///|
test "an edge's look as nodes made on it, or in hand: as it is then, at once, nothing coming in from hidden" {
  for start in [(true, true, false), (true, true, true)] {
    let (made, _, _) = looks_at(start, [], 0.0, false)
    let (later, _, _) = looks_at(start, [], 400.0, true)
    assert_eq(made, later, msg="\{start}")
    assert_eq(made.bar.map(fn(b) { b.1 }), [@ui.Space::px(S12)], msg="\{start}")
  }
}

///|
test "an edge's look as nodes, motion reduced: where it goes at once" {
  @ui.set_motion_chosen(Some(true))
  let (at_once, _, _) = looks_at((false, false, false), [{ at: 0.0, over: true, on: true, active: false }], 1.0, false)
  let (later, _, _) = looks_at((false, false, false), [{ at: 0.0, over: true, on: true, active: false }], 400.0, false)
  @ui.set_motion_chosen(None)
  assert_eq(at_once, later)
}

///|
test "an edge's look as nodes let go as it moves: no frame asked after" {
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let there = @signals.signal(true, same=fn(a, b) { a == b })
  @ui.set_view_app(fn(root) {
    root.box(fn(n) {
      n.over(Is(true)).offset(Is((140.0, 20.0))).width(Is(Some(handle_w))).height(Is(Some(200.0))) |> ignore
      n.show(fn() { there.get() }, fn(e) {
        e.grow(Is(1.0)) |> ignore
        edge_look_node(e, fn() { true }, fn() { on.get() }, fn() { false }) |> ignore
      })
    })
    |> ignore
  })
  t.draw()
  let t0 = looks_t0(t)
  let tree = @ui.view_tree().unwrap()
  t.advance(t0 - t.time())
  tree.event(t0, fn() { on.set(true) })
  t.frame_at(t0 + 30.0)
  assert_true(!t.at_rest(), msg="moving: frames asked")
  tree.event(t0 + 40.0, fn() { there.set(false) })
  t.frame_at(t0 + 50.0)
  assert_true(t.at_rest(), msg="let go: \{t.rest_why()}")
}

///|
/// How many of a line's parts show (edge_look's: clear to 10% and from 90%, the rest some of its grey).
fn line_parts_seen() -> Int {
  let mut n = 0
  for i in 0..<edge_line_steps {
    let y = (i.to_double() + 0.5) / edge_line_steps.to_double()
    if !(y <= 0.1 || y >= 0.9) {
      n = n + 1
    }
  }
  n
}
