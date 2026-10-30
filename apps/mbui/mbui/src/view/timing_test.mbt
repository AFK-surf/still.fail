// What comes and goes is decided by when its cause was told, whatever frames come after (the review of 8dd0573a4): a
// frame only takes what was told, in the order of its moments, and shows the state at its own.

///|
/// A card shown while `on` holds, leaving for 300 (faded by how far it is gone), its changes told at `now`.
fn timed(on : @signals.Signal[Bool], now : Ref[Double], card : Ref[@view.View?]) -> @view.Tree {
  @view.Tree::new(
    fn(root) {
      root.show(
        fn() { on.get() },
        fn(v) {
          card.val = Some(v)
          v.height(Is(Some(40.0))).ground(Is(0x336699FFL)).alpha(By(fn() { 1.0 - v.going() })) |> ignore
        },
        leave=300.0,
      )
    },
    time=fn() { now.val },
  )
}

///|
/// A frame at `at` (the host's now there too).
fn frame_at(t : @view.Tree, now : Ref[Double], at : Double) -> Unit {
  now.val = at
  t.at(at)
  t.frame(390.0, 844.0) |> ignore
}

///|
/// What `t` shows and what it has: what is drawn, how many nodes live, what it is to wake for.
fn state(t : @view.Tree) -> (Array[String], Int, Double?) {
  (shown(t.drawn()), t.alive(), t.wake())
}

///|
test "hidden at 0, its first frame past its leaving's end: let go in that frame, as frames along the way have it" {
  let run = fn(frames : Array[Double]) {
    let now = Ref(0.0)
    let on = @signals.signal(true, same=fn(a, b) { a == b })
    let t = timed(on, now, Ref(None))
    frame_at(t, now, 0.0)
    t.take_removed() |> ignore
    on.set(false)
    for at in frames {
      frame_at(t, now, at)
    }
    let out = (state(t), t.take_removed().length())
    t.dispose()
    out
  }
  let jumped = run([350.0])
  assert_eq(jumped, run([100.0, 200.0, 300.0, 350.0]))
  // (let go, said once, nothing to wake for)
  assert_eq(jumped.0.2, None)
  assert_eq(jumped.1, 1)
}

///|
test "hidden at 0, shown again at 150, the first frame at 350: the same node came back, as frames along the way have it" {
  let run = fn(frames : Array[Double]) {
    let now = Ref(0.0)
    let on = @signals.signal(true, same=fn(a, b) { a == b })
    let card : Ref[@view.View?] = Ref(None)
    let t = timed(on, now, card)
    frame_at(t, now, 0.0)
    let first = card.val.unwrap().id()
    on.set(false)
    let mut back = false
    for at in frames {
      if at > 150.0 && !back {
        back = true
        now.val = 150.0
        on.set(true)
      }
      frame_at(t, now, at)
    }
    let out = (state(t), card.val.unwrap().id() == first)
    t.dispose()
    out
  }
  let jumped = run([350.0])
  assert_eq(jumped, run([100.0, 200.0, 300.0, 350.0]))
  assert_true(jumped.1)
}

///|
test "hidden at 0, shown again at 320, after its leaving ended at 300: a node of its own, the one before let go" {
  let now = Ref(0.0)
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let card : Ref[@view.View?] = Ref(None)
  let t = timed(on, now, card)
  frame_at(t, now, 0.0)
  let first = card.val.unwrap()
  on.set(false)
  now.val = 320.0
  on.set(true)
  frame_at(t, now, 350.0)
  assert_false(first.alive())
  assert_true(card.val.unwrap().alive())
  assert_true(card.val.unwrap().id() != first.id())
  // (one card drawn, wholly here)
  let cards = t.drawn().filter(fn(d) { d.ground == 0x336699FFL })
  assert_eq(cards.map(fn(d) { d.alpha }), [1.0])
}

///|
test "two rows gone at 10 and at 150, the first frame at 200: each leaving from its own moment" {
  let now = Ref(0.0)
  let items = @signals.signal([
    { key: "a", words: "甲" },
    { key: "b", words: "乙" },
    { key: "c", words: "丙" },
  ])
  let t = @view.Tree::new(
    fn(root) {
      root.each(
        fn() { items.get() },
        fn(it) { it.key },
        fn(row, item) {
          row.height(Is(Some(20.0))).alpha(By(fn() { 1.0 - row.going() })).words(By(fn() { item.get().words }))
          |> ignore
        },
        leave=300.0,
      )
    },
    time=fn() { now.val },
  )
  frame_at(t, now, 0.0)
  now.val = 10.0
  items.set([{ key: "b", words: "乙" }, { key: "c", words: "丙" }])
  now.val = 150.0
  items.set([{ key: "c", words: "丙" }])
  frame_at(t, now, 200.0)
  let alpha = fn(w : String) { t.drawn().filter(fn(d) { d.words == w }).map(fn(d) { d.alpha }) }
  assert_eq(alpha("甲"), [1.0 - 190.0 / 300.0])
  assert_eq(alpha("乙"), [1.0 - 50.0 / 300.0])
  assert_eq(alpha("丙"), [1.0])
}

///|
test "what reads the clock keeps the frames coming; a leaving nothing draws by only waits for its end" {
  let now = Ref(0.0)
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  // (a look by the clock alone, nothing leaving)
  let ticking = @view.Tree::new(fn(root) {
    root.box(fn(b) { b.height(Is(Some(10.0))).alpha(By(fn() { b.now() / 1000.0 })) |> ignore }) |> ignore
  })
  ticking.frame(390.0, 844.0) |> ignore
  assert_true(ticking.animating())
  assert_eq(ticking.wake(), None)
  // (a card leaving with no look by how far it is gone)
  let plain = @view.Tree::new(
    fn(root) { root.show(fn() { on.get() }, fn(v) { v.height(Is(Some(10.0))) |> ignore }, leave=300.0) },
    time=fn() { now.val },
  )
  frame_at(plain, now, 0.0)
  on.set(false)
  frame_at(plain, now, 16.0)
  assert_false(plain.animating())
  assert_eq(plain.wake(), Some(300.0))
}

///|
test "a part shown at 10 holding a card hidden at 150, the first frame at 200: the card was made and is leaving, as with a frame at 10" {
  let run = fn(frames : Array[Double]) {
    let now = Ref(0.0)
    let outer = @signals.signal(false, same=fn(a, b) { a == b })
    let inner = @signals.signal(true, same=fn(a, b) { a == b })
    let t = @view.Tree::new(
      fn(root) {
        root.show(fn() { outer.get() }, fn(part) {
          part.show(
            fn() { inner.get() },
            fn(card) {
              card.height(Is(Some(40.0))).ground(Is(0x336699FFL)).alpha(By(fn() { 1.0 - card.going() })) |> ignore
            },
            leave=300.0,
          )
        })
      },
      time=fn() { now.val },
    )
    frame_at(t, now, 0.0)
    let told = [(10.0, fn() { outer.set(true) }), (150.0, fn() { inner.set(false) })]
    let mut next = 0
    for at in frames {
      while next < told.length() && told[next].0 <= at {
        now.val = told[next].0
        (told[next].1)()
        next = next + 1
      }
      frame_at(t, now, at)
    }
    let out = state(t)
    t.dispose()
    out
  }
  let jumped = run([200.0])
  assert_eq(jumped, run([10.0, 100.0, 200.0]))
  assert_eq(jumped.0.filter(fn(s) { s.contains("0.8333") }).length(), 1, msg="\{jumped.0}")
}

///|
test "a button moved at 10, pressed at 20 where it went: pressed, with a frame at 15 or none" {
  let run = fn(frame_at_15 : Bool) {
    let now = Ref(0.0)
    let off = @signals.signal((0.0, 0.0), same=fn(a, b) { a == b })
    let pressed = Ref(0)
    let t = @view.Tree::new(
      fn(root) {
        root.box(fn(b) {
          b
          .width(Is(Some(40.0)))
          .height(Is(Some(20.0)))
          .offset(By(fn() { off.get() }))
          .on_press(fn() { pressed.val = pressed.val + 1 })
          |> ignore
        })
        |> ignore
      },
      time=fn() { now.val },
    )
    frame_at(t, now, 0.0)
    now.val = 10.0
    off.set((100.0, 0.0))
    if frame_at_15 {
      frame_at(t, now, 15.0)
    }
    now.val = 20.0
    t.press(110.0, 10.0) |> ignore
    t.press(10.0, 10.0) |> ignore
    pressed.val
  }
  assert_eq(run(true), 1)
  assert_eq(run(false), 1)
}

///|
test "a button shown at 10, pressed at 20: pressed, with a frame between or none" {
  let run = fn(frame_between : Bool) {
    let now = Ref(0.0)
    let on = @signals.signal(false, same=fn(a, b) { a == b })
    let pressed = Ref(0)
    let t = @view.Tree::new(
      fn(root) {
        root.show(fn() { on.get() }, fn(b) {
          b.width(Is(Some(40.0))).height(Is(Some(20.0))).on_press(fn() { pressed.val = pressed.val + 1 }) |> ignore
        })
      },
      time=fn() { now.val },
    )
    frame_at(t, now, 0.0)
    now.val = 10.0
    on.set(true)
    if frame_between {
      frame_at(t, now, 15.0)
    }
    now.val = 20.0
    t.press(10.0, 10.0) |> ignore
    pressed.val
  }
  assert_eq(run(true), 1)
  assert_eq(run(false), 1)
}

///|
/// Cards A (leaving 500) and B (leaving 50), and C (leaving 100) hidden as A goes; each as it is let go says so in
/// `result` and `gone`.
fn ends(
  now : Ref[Double],
  a : @signals.Signal[Bool],
  b : @signals.Signal[Bool],
  c : @signals.Signal[Bool],
  result : Ref[String],
  gone : Array[String],
) -> @view.Tree {
  let card = fn(name : String, on : @signals.Signal[Bool], leave : Double, also : () -> Unit) {
    fn(root : @view.View) {
      root.show(
        fn() { on.get() },
        fn(v) {
          v.height(Is(Some(10.0))).words(Is(name)) |> ignore
          v.owns(fn() {
            result.val = name
            gone.push(name)
            also()
          })
          |> ignore
        },
        leave~,
      )
    }
  }
  @view.Tree::new(
    fn(root) {
      card("A", a, 500.0, fn() { c.set(false) })(root)
      card("B", b, 50.0, fn() {  })(root)
      card("C", c, 100.0, fn() {  })(root)
    },
    time=fn() { now.val },
  )
}

///|
test "two leavings ended between frames: let go in the order they ended, as frames at each end would" {
  let run = fn(frames : Array[Double]) {
    let now = Ref(0.0)
    let (a, b, c) = (
      @signals.signal(true, same=fn(x, y) { x == y }),
      @signals.signal(true, same=fn(x, y) { x == y }),
      @signals.signal(true, same=fn(x, y) { x == y }),
    )
    let result = Ref("")
    let gone : Array[String] = []
    let t = ends(now, a, b, c, result, gone)
    frame_at(t, now, 0.0)
    a.set(false)
    now.val = 100.0
    b.set(false)
    for at in frames {
      frame_at(t, now, at)
    }
    let out = (gone.copy(), state(t))
    t.dispose()
    out
  }
  let jumped = run([1000.0])
  assert_eq(jumped, run([150.0, 500.0, 600.0, 1000.0]))
  // (B at 150, A at 500, C (hidden as A went, leaving 100) at 600)
  assert_eq(jumped.0, ["B", "A", "C"])
}

///|
/// A box whose width adds up step by step towards `target` (a tenth of the way each step), 60 steps a 60th of a second
/// apart from its making, each step said in a log; the target set to 50 by an input at 500; frames at `frames`.
fn stepped(frames : Array[Double]) -> (Array[(Int, Double)], Array[String]) {
  let now = Ref(0.0)
  let target = @signals.signal(100.0)
  let v = @signals.signal(0.0)
  let log : Array[(Int, Double)] = []
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(b) {
        b.height(Is(Some(10.0))).width(By(fn() { Some(v.get()) })) |> ignore
        b.steps(60, 60, fn(k, _) {
          let next = v.get() + (target.get() - v.get()) * 0.1
          v.set(next)
          log.push((k, next))
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { now.val },
  )
  frame_at(t, now, 0.0)
  let mut told = false
  for at in frames {
    if !told && at > 500.0 {
      told = true
      now.val = 500.0
      t.event(500.0, fn() { target.set(50.0) })
    }
    frame_at(t, now, at)
  }
  let out = (log.copy(), shown(t.drawn()))
  t.dispose()
  out
}

///|
test "60 steps adding up, an input among them: the same steps and the same end at 60 Hz, at 120 Hz, or after no frame for long" {
  let at_hz = fn(hz : Double) { Array::makei((2000.0 * hz / 1000.0).to_int(), fn(i) { (i + 1).to_double() * 1000.0 / hz }) }
  let late = stepped([2000.0])
  assert_eq(late.0.length(), 60)
  assert_eq(stepped(at_hz(60.0)), late)
  assert_eq(stepped(at_hz(120.0)), late)
  // (a frame at 100, none till long after the input: the steps between taken in their turn, the input among them)
  assert_eq(stepped([100.0, 2000.0]), late)
  // (the input in the middle of them: rising toward 100 before it, falling toward 50 after it)
  assert_true(late.0[29].1 > late.0[10].1)
  assert_true(late.0[59].1 < late.0[29].1 && late.0[59].1 > 50.0)
}

///|
test "more frames drawn than steps, the same moment drawn again: no step more" {
  let once = stepped([500.0, 2000.0])
  let again = stepped([500.0, 500.0, 500.0, 2000.0, 2000.0, 2500.0])
  assert_eq(again.0, once.0)
}

///|
test "60 steps a second from 0: the 60th at 1000 exactly, each given its own moment" {
  let now = Ref(0.0)
  let at : Array[Double] = []
  let t = @view.Tree::new(
    fn(root) { root.box(fn(b) { b.steps(60, 60, fn(_, m) { at.push(m) }) |> ignore }) |> ignore },
    time=fn() { now.val },
  )
  frame_at(t, now, 0.0)
  frame_at(t, now, 999.0)
  assert_eq(at.length(), 59)
  frame_at(t, now, 1000.0)
  assert_eq(at.length(), 60)
  assert_eq(at[29], 500.0)
  assert_eq(at[59], 1000.0)
}

///|
test "an input at the moment a step is due: the step first, then the input; due together: in the order told" {
  let (log, _) = stepped([2000.0])
  // (step 29 is due at 500, the input's moment: it still rises toward 100, the step after falls toward 50)
  assert_true(log[29].1 > log[28].1)
  assert_true(log[30].1 < log[29].1)
}

///|
test "steps said for a stretch: none before it or after it, 60 within it, none after they are stopped; endings between in their turn" {
  let now = Ref(0.0)
  let going = @signals.signal(false, same=fn(a, b) { a == b })
  let card = @signals.signal(true, same=fn(a, b) { a == b })
  let at : Array[Double] = []
  let order : Array[String] = []
  let stop : Ref[() -> Unit] = Ref(fn() {  })
  let t = @view.Tree::new(
    fn(root) {
      root.show(fn() { going.get() }, fn(b) {
        stop.val = b.steps(60, 60, fn(_, m) {
          at.push(m)
          order.push("step")
        })
      })
      root.show(
        fn() { card.get() },
        fn(c) {
          c.height(Is(Some(10.0))) |> ignore
          c.owns(fn() { order.push("card gone") }) |> ignore
        },
        leave=100.0,
      )
    },
    time=fn() { now.val },
  )
  frame_at(t, now, 0.0)
  // (a long stretch with nothing said to go by steps: one jump, nothing stepped)
  frame_at(t, now, 5000.0)
  assert_eq(at.length(), 0)
  // (said at 5000; a card hidden at 5005 ends at 5105, among the steps)
  going.set(true)
  now.val = 5005.0
  card.set(false)
  frame_at(t, now, 20000.0)
  assert_eq(at.length(), 60)
  assert_eq(at[0], 5000.0 + 1000.0 / 60.0)
  assert_eq(at[59], 6000.0)
  // (the card's end at 5105 came between the steps at 5100 and 5116.67)
  assert_eq(order.search("card gone"), Some(6))
  // (stopped steps go no further: said again, stopped after 10)
  going.set(false)
  frame_at(t, now, 20001.0)
  going.set(true)
  frame_at(t, now, 20001.0 + 10000.0 / 60.0)
  (stop.val)()
  frame_at(t, now, 40000.0)
  assert_eq(at.length(), 70)
  assert_true(!t.animating())
}
