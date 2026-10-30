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

