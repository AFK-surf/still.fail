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
