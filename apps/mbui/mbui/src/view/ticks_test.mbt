// The one clock's ticks for what goes by steps (View::steps), worked out exactly wherever the host's clock is (a
// monotonic clock from the device's start, hours on), and always after what said them.

///|
test "steps said at 50,000,000 ms of the host's clock: the next tick worked out exactly, the step taken" {
  let now = Ref(50_000_000.0)
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let at : Array[Double] = []
  let t = @view.Tree::new(
    fn(root) { root.show(fn() { on.get() }, fn(b) { b.steps(60, 1, fn(_, m) { at.push(m) }) |> ignore }) },
    time=fn() { now.val },
  )
  t.at(now.val)
  t.frame(390.0, 844.0) |> ignore
  on.set(true)
  now.val = 50_000_100.0
  t.at(now.val)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(at, [3_000_001_000.0 / 60.0])
}

///|
test "steps at one rate said in a step at that rate: from the tick after it, not again at the tick it is said at" {
  let now = Ref(0.0)
  let on_b = @signals.signal(false, same=fn(a, b) { a == b })
  let a_at : Array[Double] = []
  let b_at : Array[Double] = []
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(a) {
        a.steps(60, 31, fn(k, m) {
          a_at.push(m)
          if k == 30 {
            on_b.set(true)
          }
        })
        |> ignore
      })
      |> ignore
      root.show(fn() { on_b.get() }, fn(b) { b.steps(60, 1, fn(_, m) { b_at.push(m) }) |> ignore })
    },
    time=fn() { now.val },
  )
  t.frame(390.0, 844.0) |> ignore
  now.val = 2000.0
  t.at(now.val)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(a_at[30], 31000.0 / 60.0)
  assert_eq(b_at, [32000.0 / 60.0])
}

///|
test "a tree made at 5000 of the host's clock: steps said as it is made start at the tick after 5000" {
  let at : Array[Double] = []
  let t = @view.Tree::new(fn(root) { root.steps(60, 1, fn(_, m) { at.push(m) }) |> ignore }, time=fn() { 5000.0 })
  t.at(6000.0)
  t.frame(390.0, 844.0) |> ignore
  assert_eq(at, [301000.0 / 60.0])
}

///|
test "what a step reads as now is its own moment, frames drawn at each step or once long after" {
  let run = fn(frames : Array[Double]) {
    let now = Ref(0.0)
    let seen : Array[(Double, Double)] = []
    let t = @view.Tree::new(
      fn(root) {
        root.box(fn(v) { v.steps(60, 5, fn(_, m) { seen.push((m, v.now())) }) |> ignore }) |> ignore
      },
      time=fn() { now.val },
    )
    for f in frames {
      now.val = f
      t.at(f)
      t.frame(390.0, 844.0) |> ignore
    }
    seen
  }
  let each = run([0.0, 1000.0 / 60.0, 2000.0 / 60.0, 3000.0 / 60.0, 4000.0 / 60.0, 5000.0 / 60.0, 2000.0])
  let once = run([0.0, 2000.0])
  assert_eq(once, each)
  assert_true(once.iter().all(fn(p) { p.0 == p.1 }))
}

///|
test "the tree's logic advanced to 5000 with nothing due, then steps said: from the tick after 5000, none before" {
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let at : Array[Double] = []
  let t = @view.Tree::new(fn(root) { root.show(fn() { on.get() }, fn(b) { b.steps(60, 1, fn(_, m) { at.push(m) }) |> ignore }) })
  t.frame(390.0, 844.0) |> ignore
  t.advance(5000.0)
  on.set(true)
  t.advance(6000.0)
  assert_eq(at, [301000.0 / 60.0])
}

///|
test "a frame to be shown at 100 drawn at 90: a step due at 100 not taken before an input at 95 that stops it" {
  let run = fn(ahead : Bool) {
    let now = Ref(0.0)
    let on = @signals.signal(true, same=fn(a, b) { a == b })
    let log : Array[Double] = []
    let t = @view.Tree::new(
      fn(root) { root.show(fn() { on.get() }, fn(a) { a.steps(10, 1, fn(_, m) { log.push(m) }) |> ignore }) },
      time=fn() { now.val },
    )
    t.frame(390.0, 844.0, now=0.0) |> ignore
    if ahead {
      // (the host at 90, the frame for when it is shown, 100)
      now.val = 90.0
      t.at(100.0)
      t.frame(390.0, 844.0, now=90.0) |> ignore
    }
    now.val = 95.0
    t.event(95.0, fn() { on.set(false) })
    now.val = 200.0
    t.at(200.0)
    t.frame(390.0, 844.0, now=200.0) |> ignore
    log
  }
  assert_eq(run(true), [])
  assert_eq(run(false), [])
}

///|
test "a look by the time made by an event at 10: it goes on with the clock, and follows it no more once let go" {
  let now = Ref(0.0)
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let card : Ref[@view.View?] = Ref(None)
  let t = @view.Tree::new(
    fn(root) {
      root.show(fn() { on.get() }, fn(v) {
        card.val = Some(v)
        v.height(Is(Some(10.0))).alpha(By(fn() { v.drawn_at() / 100.0 })) |> ignore
      })
    },
    time=fn() { now.val },
  )
  t.frame(390.0, 844.0, now=0.0) |> ignore
  now.val = 10.0
  t.event(10.0, fn() { on.set(true) })
  for at in [20.0, 30.0] {
    now.val = at
    t.at(at)
    t.frame(390.0, 844.0, now=at) |> ignore
    assert_eq(t.drawn_of(card.val.unwrap().id()).unwrap().alpha, at / 100.0)
  }
  assert_true(t.animating())
  now.val = 40.0
  t.event(40.0, fn() { on.set(false) })
  assert_false(t.animating())
}

///|
test "a frame to be shown at 100 drawn at 90: a button placed by the time is pressed at 95 where it is at 95" {
  let run = fn(ahead : Bool) {
    let now = Ref(0.0)
    let pressed = Ref(0)
    let t = @view.Tree::new(
      fn(root) {
        root.box(fn(b) {
          b
          .width(Is(Some(10.0)))
          .height(Is(Some(10.0)))
          .offset(By(fn() { (b.drawn_at(), 0.0) }))
          .on_press(fn() { pressed.val = pressed.val + 1 })
          |> ignore
        })
        |> ignore
      },
      time=fn() { now.val },
    )
    t.frame(390.0, 844.0, now=0.0) |> ignore
    if ahead {
      now.val = 90.0
      t.at(100.0)
      t.frame(390.0, 844.0, now=90.0) |> ignore
    }
    now.val = 95.0
    // (at 95 it is at 95..105: 97 is on it; at 100 it would be at 100..110, 97 not)
    t.press(97.0, 5.0) |> ignore
    pressed.val
  }
  assert_eq(run(true), 1)
  assert_eq(run(false), 1)
}

///|
/// What is said to show at 100 (and, as it shows, steps at 10 a second, its one step logged): frames at `frames`, the
/// host's now each as the frame says, a frame to be shown at 100 drawn at 90 first where `ahead`.
fn shown_at_100(frames : Array[Double], ahead : Bool) -> (Array[Double], Int) raise {
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let log : Array[Double] = []
  let made = Ref(0)
  let t = @view.Tree::new(fn(root) {
    root.at_moment(100.0, fn() { on.set(true) }) |> ignore
    root.show(fn() { on.get() }, fn(v) {
      made.val = made.val + 1
      v.steps(10, 1, fn(_, m) { log.push(m) }) |> ignore
    })
  })
  t.frame(390.0, 844.0, now=0.0) |> ignore
  if ahead {
    t.at(100.0)
    t.frame(390.0, 844.0, now=90.0) |> ignore
    assert_eq(made.val, 0)
  }
  for f in frames {
    t.at(f)
    t.frame(390.0, 844.0, now=f) |> ignore
  }
  (log, made.val)
}

///|
test "what is said to show at 100, stepping as it shows: the same at frames 100, 200, 500 or 500 alone; not made by a frame drawn at 90 for 100" {
  let each = shown_at_100([100.0, 200.0, 500.0], false)
  assert_eq(shown_at_100([500.0], false), each)
  assert_eq(shown_at_100([500.0], true), each)
  assert_eq(each, ([200.0], 1))
}
