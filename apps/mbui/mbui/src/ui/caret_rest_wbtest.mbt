///|
test "a focused field's caret blinks till caret_blinks_for_ms after it last moved, then rests shown and asks nothing" {
  let field = Field::new()
  let t = Tester::new(fn(c) { c.editor("field", field~, font_size=10.0) |> ignore }, w=300.0, h=100.0)
  t.tap(50.0, 20.0)
  t.type_text("hi")
  t.draw()
  let shown = t.frame_hash()
  // blinking: hidden half a blink later, its next change waited for
  t.run_for(caret_blink_ms * 1.5)
  assert_true(t.frame_hash() != shown)
  assert_true(g().wake_at > 0.0)
  // past caret_blinks_for_ms: shown and staying so, nothing waited for
  t.run_for(caret_blinks_for_ms)
  assert_eq(t.frame_hash(), shown)
  assert_true(g().wake_at < 0.0)
  t.run_for(caret_blink_ms * 1.5)
  assert_eq(t.frame_hash(), shown)
  // a letter typed: it blinks again
  t.type_text("!")
  t.draw()
  assert_true(g().wake_at > 0.0)
  assert_eq(field.text(), "hi!")
}

///|
test "a frame on a blink's start a hair short of it by the division is in that blink: the next wake is after it, never at it" {
  // (1546.67 − 1016.67 comes out 529.999…: a wake asked at the moment already drawn wakes nothing, and hides every
  // later one, a hover card's opening among them)
  let now = 1546.6666666666665
  let from = 1016.6666666666666
  assert_true(now - from < caret_blink_ms)
  let (n, next) = periods_at(now, from, caret_blink_ms)
  assert_eq(n, 1)
  assert_true(next > now)
  // between two starts, as ever
  assert_eq(periods_at(1300.0, 1000.0, 530.0), (0, 1530.0))
}

///|
test "a frame before a blink's scheduled start stays in the previous blink" {
  // Subtraction rounds this frame's elapsed time up to exactly 17 periods, although it precedes the wake made from
  // the same origin. The paint must not change until that wake, or a retained frame misses the caret's change.
  let from = 2716.666666666667
  let now = 11216.666666666666
  let period = 500.0
  let start = from + 17.0 * period
  assert_true(now < start)
  assert_eq(now - from, 17.0 * period)
  assert_eq(periods_at(now, from, period), (16, start))
  assert_eq(periods_at(start, from, period), (17, from + 18.0 * period))
}
