// What a windowed list tells seen (View::scrolls_window's `seen`): the blocks that came in sight, as it was laid out
// or as it went across them by itself; not those a move at once went past, which it made only to measure them. So what
// a page keeps for a block (a draft) is started for what was shown, whether the frames between were many or one.

///|
priv struct SeenCase {
  tree : @view.Tree
  seen : Array[Int]
  made : Array[Int]
  live : Map[Int, @view.View]
  mut now : Double
}

///|
/// Blocks `0..<400` in a column 300 by 100 (from its top), 40 and 80 tall in turn, counted 80 till laid out: what it
/// told seen (in the order told, each frame's once it is painted), what it made, what of it is made now; its first
/// frame drawn.
fn seen_case() -> SeenCase {
  let scroll = @view.Scroll::list()
  let seen = []
  let made = []
  let live : Map[Int, @view.View] = {}
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
      o.scrolls_window(scroll, fn() { Array::makei(400, fn(i) { i }) }, est=80.0, seen=fn(came) { seen.append(came) }, fn(
        b,
        k,
      ) {
        made.push(k)
        live[k] = b
        b.owns(fn() { live.remove(k) }) |> ignore
        b.height(Is(Some(if k % 2 == 0 { 40.0 } else { 80.0 }))) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  let c : SeenCase = { tree, seen, made, live, now: 0.0 }
  c.frame(0.0)
  c
}

///|
/// The frame `dt` on, what it said to tell once it is painted told.
fn SeenCase::frame(self : SeenCase, dt : Double) -> Unit {
  self.now = self.now + dt
  self.tree.frame(300.0, 100.0, now=self.now) |> ignore
  for f in self.tree.take_after_paint() {
    f()
  }
}

///|
/// The blocks in sight, from the top: each its key and where its top is.
fn SeenCase::in_sight(self : SeenCase) -> Array[(Int, Double)] {
  let out = []
  for k, v in self.live {
    let (_, y, _, h) = v.rect()
    if y + h > 0.0 && y < 100.0 {
      out.push((k, y))
    }
  }
  out.sort_by(fn(a, b) { a.0.compare(b.0) })
  out
}

///|
/// What it told seen, each once, by key.
fn SeenCase::told(self : SeenCase) -> Array[Int] {
  let once : Set[Int] = Set::new()
  for k in self.seen {
    once.add(k)
  }
  let out = once.iter().collect()
  out.sort()
  out
}

///|
/// `steps` wheels of `dy` each (down), a frame after each, then the frame 5 s on: the blocks told seen, those in sight,
/// and the case.
fn wheeled_seen(steps : Int, dy : Double) -> (Array[Int], Array[(Int, Double)], SeenCase) {
  let c = seen_case()
  for _ in 0..<steps {
    c.tree.wheel_at(150.0, 50.0, 0.0, dy, 0, c.now + 1.0) |> ignore
    c.frame(16.0)
  }
  c.frame(5000.0)
  (c.told(), c.in_sight(), c)
}

///|
test "scrolls_window: a wheel of 3000 tells seen what showed before it and where it stops, none of the blocks it went past (made only to be measured); three hundred of 10 tell every block they showed; both stop on the same blocks, where they are" {
  let (one, one_sight, c) = wheeled_seen(1, 3000.0)
  let (many, many_sight, _) = wheeled_seen(300, 10.0)
  // (3000 down, 120 a pair: block 50 at the top)
  assert_eq((one_sight, many_sight), ([(50, 0.0), (51, 40.0)], [(50, 0.0), (51, 40.0)]))
  assert_eq(one, [0, 1, 50, 51])
  assert_eq(many, Array::makei(52, fn(i) { i }))
  // (those it went past made, each to be measured, none of them told)
  let went_past = Array::makei(48, fn(i) { i + 2 })
  assert_eq(went_past.filter(fn(k) { !c.made.contains(k) }), [])
}

///|
/// A finger up 80 in 10 ms, let go as it moves, then a frame every `dt` till 6 s: the blocks told seen and those in
/// sight.
fn flung_seen(dt : Double) -> (Array[Int], Array[(Int, Double)]) {
  let c = seen_case()
  guard c.tree.claimer_of(c.tree.claimers_at(150.0, 90.0), 0.0, -80.0) is Some(id) else {
    abort("nothing takes the finger")
  }
  let t = c.now + 1.0
  c.tree.drag_at(id, Down, 150.0, 90.0, t) |> ignore
  c.tree.drag_at(id, Moved, 150.0, 50.0, t + 5.0) |> ignore
  c.tree.drag_at(id, Moved, 150.0, 10.0, t + 10.0) |> ignore
  c.tree.drag_at(id, Up, 150.0, 10.0, t + 10.0) |> ignore
  while c.now < 6000.0 {
    c.frame(dt)
  }
  (c.told(), c.in_sight())
}

///|
test "scrolls_window flung: every block it glides across told seen (each in sight at a moment of the way), drawn every 16 ms or in one frame at its end" {
  let often = flung_seen(16.0)
  let once = flung_seen(6000.0)
  assert_eq(once, often)
  // (all from the first to where it stops, each once)
  let (told, sight) = often
  let last = sight.last().map(fn(r) { r.0 }).unwrap_or(-1)
  assert_eq(told, Array::makei(last + 1, fn(i) { i }))
  assert_true(last > 10, msg="glided on: \{sight}")
}

///|
/// A column 300 by 100 holding, while `there` says so, a list of `0..<400` 40 tall from its top: windowed (what it told
/// seen pushed to `told`) or anchored (what it told sighted as come, there): its tree, and its frame `at` drawn with what
/// it said to tell once it is painted told.
fn gone_case(windowed : Bool, there : @signals.Signal[Bool], told : Array[Int]) -> (@view.Tree, (Double) -> Unit) {
  let scroll = @view.Scroll::list()
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
      o.show(fn() { there.get() }, fn(p) {
        p.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
        let keys = fn() { Array::makei(400, fn(i) { i }) }
        let row = fn(b : @view.View, _k : Int) { b.height(Is(Some(40.0))) |> ignore }
        if windowed {
          p.scrolls_window(scroll, keys, est=40.0, seen=fn(came) { told.append(came) }, row) |> ignore
        } else {
          p.scrolls_anchored(scroll, keys, est=40.0, ahead=0.0, from_end=false, sighted=fn(s) { told.append(s.came) }, row)
          |> ignore
        }
      })
    })
    |> ignore
  })
  let frame = fn(at : Double) {
    tree.frame(300.0, 100.0, now=at) |> ignore
    for f in tree.take_after_paint() {
      f()
    }
  }
  (tree, frame)
}

///|
test "scrolls_window, scrolls_anchored: a list let go after it was laid out at an input's moment, before the frame is painted, tells nothing of what came in sight then; one still there tells it as the frame is painted" {
  for windowed in [true, false] {
    for let_go in [false, true] {
      let there = @signals.signal(true)
      let told : Array[Int] = []
      let (tree, frame) = gone_case(windowed, there, told)
      frame(0.0)
      let first = told.length()
      // (a wheel down 400, then another: laid out at the second's moment, rows 10 to 12 in sight then)
      tree.wheel_at(150.0, 50.0, 0.0, 400.0, 0, 1.0) |> ignore
      tree.wheel_at(150.0, 50.0, 0.0, 40.0, 0, 2.0) |> ignore
      if let_go {
        there.set(false)
      }
      frame(16.0)
      let after = told[first:].to_array()
      if let_go {
        assert_eq(after, [], msg="windowed \{windowed}")
      } else {
        assert_true(after.contains(10), msg="windowed \{windowed}: \{after}")
      }
      tree.dispose()
    }
  }
}
