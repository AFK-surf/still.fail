///|
test "a small scroll saves the moved position of the same visible message" {
  let calls : Array[Made] = []
  let t = fake_core(calls, platform=0)
  t.run_for(@sfpages.reveal_ms)
  t.move(195.0, 400.0)
  t.wheel(195.0, 400.0, -500.0)
  t.run_for(@ui.move_most_ms)
  let rd = readings.get("ws1/st1\u{1}s-c1").unwrap()
  let (seq, before) = (rd.top_seq, rd.top_off)
  assert_true(seq >= 0.0 && !rd.at_end, msg="a message is at the top, short of the end")
  t.wheel(195.0, 400.0, -4.0)
  let scrolled_at = t.time()
  t.run_for(@ui.move_most_ms)
  assert_eq(rd.top_seq, seq, msg="the same message is still at the top")
  assert_true((rd.top_off - before).abs() > 1.0, msg="its saved offset follows its movement")
  let told = named(calls, "chat.place")
  assert_true(!told.is_empty(), msg="the reading place was reported")
  let place = told[told.length() - 1].params
  assert_eq(number(Some(place), "seq"), seq)
  assert_eq(number(Some(place), "offset"), (rd.top_off * t.ctx().scale).round())
  // The wheel's scroll bar remains for its declared hold and fade; it should leave no work after that.
  let bar_end = scrolled_at + @ui.scrollbar_hold_ms + @ui.scrollbar_fade_ms
  if bar_end > t.time() {
    t.run_for(bar_end - t.time())
  }
  t.assert_idle()
}
