// Back while the app takes none: the system's own, as every host hands back on only while it is told the app takes it
// (Android's closes the app's window); while it takes it, the app's.

///|
test "back with a page to go back to the app's; with none, the system's own, the app given nothing" {
  let nav = Nav::new("a")
  let t = Tester::new(fn(_c) {  }, platform=2)
  t.check_looks(false)
  set_view_app(fn(root) {
    nav_view(root, nav, fn(c, p) { c.text(p, size=12.0) |> ignore }, bg=fn() { 0xFFFFFFFFL }) |> ignore
  })
  t.draw()
  // (none to go back to: the system's)
  t.back()
  assert_eq(t.backs_out(), 1)
  t.back_gesture(200.0, true)
  assert_eq(t.backs_out(), 2)
  t.back_raw(2, 0.0, t.time())
  assert_eq(t.backs_out(), 3)
  assert_eq(nav.depth(), 1)
  // (a page to go back to: the app's)
  told_at(t, t.time() + 10.0, fn() { nav.push("b") })
  t.run_for(nav.rest() - t.time() + 16.0)
  t.back()
  t.run_for(nav.rest() - t.time() + 16.0)
  assert_eq(nav.depth(), 1)
  assert_eq(t.backs_out(), 3)
}

///|
test "back told between frames, the app taking none: the system's own" {
  let t = Tester::new(fn(_c) {  }, platform=2)
  t.draw()
  t.back_told(t.time())
  assert_eq(t.backs_out(), 1)
}
