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
