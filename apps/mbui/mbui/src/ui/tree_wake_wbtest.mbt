// What the window's tree has yet to do once (a node leaving, let go as its leaving ends) is what a test waits for, as
// an old view's wake is (Tester::next_wake): not idle before it, run on to it, the node let go then.

///|
test "a node leaving: its leaving's end waited for (next_wake), not idle before it; run on to it, let go, nothing left waited for" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.show(fn() { on.get() }, fn(v) {
      v.width(Is(Some(80.0))).height(Is(Some(40.0))).ground(Is(0xFF7F7FFFL)) |> ignore
    }, leave=wake_leave_ms)
  })
  t.draw()
  // (a moment on: what it leaves at is the clock's then)
  t.run_for(wake_later_ms)
  let shown = view_tree().unwrap().drawn().length()
  on.set(false)
  t.frame()
  let from = t.time()
  let waited = t.next_wake().map(fn(w) { w.0 })
  let ahead = match waited {
    Some(at) => at > from && at <= from + wake_leave_ms
    None => false
  }
  let idle = g().rest_why() == ""
  match waited {
    Some(at) => t.run_for(at - t.time())
    None => ()
  }
  let left = view_tree().unwrap().drawn().length()
  assert_eq((ahead, idle, shown - left, t.next_wake().map(fn(w) { w.0 })), (true, false, 1, None), msg="\{waited} \{from}")
}

///|
test "steps for a stretch: waited for to their last, not idle before it; run on to it, every step done, nothing left waited for; a cycle waited for by none" {
  let done : Array[Int] = []
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(v) {
      v.width(Is(Some(40.0))).height(Is(Some(40.0))) |> ignore
      v.steps(60, 5, fn(k, _) { done.push(k) }) |> ignore
    })
    |> ignore
    // (a wait drawn by a cycle, as long as it shows)
    root.box(fn(w) {
      w.width(Is(Some(40.0))).height(Is(Some(40.0))).alpha(By(fn() { w.cycle(1000.0) })) |> ignore
    })
    |> ignore
  })
  t.draw()
  let waited = t.next_wake().map(fn(w) { w.0 })
  let before = (g().rest_why().contains("a wake"), done.length() < 5)
  match waited {
    Some(at) => t.run_for(at - t.time())
    None => ()
  }
  assert_eq((waited is Some(_), before, done, t.next_wake()), (true, (true, true), [0, 1, 2, 3, 4], None), msg="\{waited} \{done} \{t.next_wake()} \{t.time()} \{g().rest_why()}")
}

///|
/// How long the node leaving takes (tree_wake's), and how long after its first frame it is told to go.
let wake_leave_ms : Double = 100.0

///|
let wake_later_ms : Double = 10.0


///|
/// A node told, as `on` comes, to do something at `due` (worked out of the moment it is made at, its cause's: `when`)
/// then (counted in `done`).
fn due_tester(on : @signals.Signal[Bool], when : (Double) -> Double, due : Ref[Double], done : Ref[Int]) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.show(fn() { on.get() }, fn(v) {
      v.width(Is(Some(40.0))).height(Is(Some(40.0))) |> ignore
      due.val = when(v.cause_at())
      v.at_moment(due.val, fn() { done.val = done.val + 1 }, later=true) |> ignore
    })
  })
  t.draw()
  t
}

///|
test "something due a few ulps past the display's frame the clock is at (its cause's moment and a length): run on to it, there, done once, nothing left due" {
  let (on, due, done) = (@signals.signal(false), Ref(0.0), Ref(0))
  // (at the frame of the display's it is made in, and a few ulps past it, as a sum of its cause's moment and a length
  // may come to)
  let t = due_tester(on, fn(at) { at + at * 4.0e-16 }, due, done)
  t.run_for(wake_later_ms)
  // (made as it is told, at the clock's frame)
  on.set(true)
  let ahead = (due.val > t.time(), done.val)
  t.run_for(due.val - t.time())
  assert_eq((ahead, t.time() == due.val, done.val, view_tree().unwrap().wake()), ((true, 0), true, 1, None), msg="\{due.val} \{t.time()}")
}

///|
test "something due: run on to just before it, not done; on to it, done once; on past it, not again" {
  let (on, due, done) = (@signals.signal(false), Ref(0.0), Ref(0))
  let t = due_tester(on, fn(at) { at + wake_leave_ms }, due, done)
  on.set(true)
  t.frame()
  t.run_for(due.val - t.time() - wake_short_ms)
  let before = done.val
  t.run_for(due.val - t.time())
  let at = done.val
  t.run_for(wake_leave_ms)
  assert_eq((before, at, done.val), (0, 1, 1))
}

///|
/// How far short of what is due a run is stopped (far more than a sum's rounding, less than a frame).
let wake_short_ms : Double = 0.001
