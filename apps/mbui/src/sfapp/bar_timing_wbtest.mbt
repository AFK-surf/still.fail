// The bar's switches as the host is told them (bar_timing.mbt, Android's BarTiming): a place put on the stack, from the
// place left, then its page built, once, after the frame that built it; back to the chats the same.

///|
/// The app over the fixture's chats, the host's timing a list of what it was told.
fn timing_tester() -> (@ui.Tester, Array[String]) {
  let t = tester("home")
  let told : Array[String] = []
  bar_timing.val = Some({
    placed: fn(from, to) { told.push("placed \{from} → \{to}") },
    built: fn(p) { told.push("built \{p}") },
  })
  (t, told)
}

///|
/// Run on to where the bar's own motions rest (bar_rest: its springs, the ball, the icons' swap and tints), past the
/// page's switch.
fn to_bar_rest(t : @ui.Tester) -> Unit {
  let rest = bar_rest()
  if rest > t.time() {
    t.run_for(rest - t.time())
  }
}

///|
test "bar timing: 文件 tapped is told placed from the chats, then built once" {
  let (t, told) = timing_tester()
  let (xs, y) = bar_places_at()
  t.tap(xs[1], y)
  t.run_for(@ui.move_most_ms)
  assert_eq(told, ["placed chats → files", "built files"])
  to_bar_rest(t)
  t.assert_idle()
}

///|
test "bar timing: back to the chats is a switch too; the same place again is none" {
  let (t, told) = timing_tester()
  let (xs, y) = bar_places_at()
  t.tap(xs[1], y)
  t.run_for(@ui.move_most_ms)
  t.tap(xs[1], y)
  t.run_for(@ui.move_most_ms)
  t.back()
  t.run_for(@ui.move_most_ms)
  assert_eq(told, ["placed chats → files", "built files", "placed files → chats", "built chats"])
  to_bar_rest(t)
  t.assert_idle()
}

///|
test "bar timing: none set (a Tester's, the web's), a switch tells nothing and waits for nothing" {
  let t = tester("home")
  let (xs, y) = bar_places_at()
  t.tap(xs[1], y)
  t.run_for(@ui.move_most_ms)
  assert_true(bar_timed.val is None)
  to_bar_rest(t)
  t.assert_idle()
}
