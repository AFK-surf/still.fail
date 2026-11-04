// A retained view follows the system's appearance before laying out the frame that sees it.

///|
test "a retained view follows the system's dark setting on the frame it changes" {
  let seen : Array[Bool] = []
  let t = Tester::new(fn(_) { }, w=200.0, h=200.0, dark=false)
  set_view_app(fn(root) {
    root.reacts(system_dark, fn(dark) { seen.push(dark) })
  })
  t.frame()
  assert_eq(seen, [false])
  t.set_dark(true)
  t.frame()
  assert_eq(seen, [false, true])
  t.set_dark(false)
  t.frame()
  assert_eq(seen, [false, true, false])
}
