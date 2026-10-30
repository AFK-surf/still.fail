// What the window's tree routes and keeps ends where it should (the review of 9eff822ff): a press called off or of the
// secondary button presses nothing; what a node let go drew is let go with it.

///|
test "window tree: a press on the badge called off presses nothing, nor does the secondary button" {
  let w = island(@signals.signal("bar"))
  w.t.check_looks(false)
  on_pointer(0, 50.0, 150.0, 0)
  on_pointer(3, 50.0, 150.0, 0)
  on_pointer(2, 50.0, 150.0, 0)
  w.t.drawn_now()
  assert_eq(w.badge_taps.val, 0)
  on_pointer(0, 50.0, 150.0, 2)
  on_pointer(2, 50.0, 150.0, 2)
  w.t.drawn_now()
  assert_eq(w.badge_taps.val, 0)
  // (and a press after them presses it)
  tree_tap(w.t, 50.0, 150.0)
  assert_eq(w.badge_taps.val, 1)
}


///|
test "window tree: shown and let go again and again: what each drew let go with it" {
  let on = @signals.signal(false, same=fn(a, b) { a == b })
  let view = fn(c : Ctx) { c.text("old", size=12.0) |> ignore }
  let t = Tester::new(view)
  set_view_app(fn(root) {
    root.show(fn() { on.get() }, fn(v) { v.height(Is(Some(20.0))).ground(Is(island_red)) |> ignore })
    old(root, view).grow(Is(1.0)) |> ignore
  })
  t.draw()
  let base = view_blocks.length()
  let seen : Array[@view.NodeId] = []
  for _ in 0..<5 {
    on.set(true)
    t.drawn_now()
    for id in view_blocks.keys() {
      if !seen.contains(id) {
        seen.push(id)
      }
    }
    on.set(false)
    t.drawn_now()
  }
  assert_eq(view_blocks.length(), base)
  assert_true(seen.length() >= 5)
  assert_false(seen.iter().any(fn(id) { view_blocks.contains(id) && view_tree().unwrap().drawn_of(id) is None }))
}


///|
/// A part leaving for 300 as `on` stops, its own effect counting the runs of what reads `s`; a node pressed (at the
/// top, 40 high) that sets `s`; the old view beneath.
fn settling(on : @signals.Signal[Bool], s : @signals.Signal[Int], runs : Ref[Int]) -> Tester {
  let view = fn(c : Ctx) { c.text("old", size=12.0) |> ignore }
  let t = Tester::new(view)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(b) { b.height(Is(Some(40.0))).ground(Is(0x336699FFL)).on_press(fn() { s.set(s.get() + 1) }) |> ignore })
    |> ignore
    root.show(
      fn() { on.get() },
      fn(v) {
        v.height(Is(Some(40.0))) |> ignore
        @signals.effect(fn() {
          s.get() |> ignore
          runs.val = runs.val + 1
        })
        |> ignore
      },
      leave=300.0,
    )
    old(root, view).grow(Is(1.0)) |> ignore
  })
  t.draw()
  t
}

///|
test "window tree: a part whose leaving ended at 300, a press at 350 with no frame between: it runs nothing for it" {
  let run = fn(frame_at_300 : Bool) {
    let on = @signals.signal(true, same=fn(a, b) { a == b })
    let s = @signals.signal(0)
    let runs = Ref(0)
    let t = settling(on, s, runs)
    let t0 = t.fake.time
    on.set(false)
    if frame_at_300 {
      t.frame_at(t0 + 300.0)
    }
    t.fake.time = t0 + 350.0
    let before = runs.val
    on_pointer(0, 100.0, 20.0, 0)
    on_pointer(2, 100.0, 20.0, 0)
    (s.get(), runs.val - before)
  }
  assert_eq(run(false), (1, 0))
  assert_eq(run(true), (1, 0))
}
