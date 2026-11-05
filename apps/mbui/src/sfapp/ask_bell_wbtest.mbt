// The bell to what waits to be decided (ToAsk) shows till every ask is in sight, as main's (asks_in_view): one card in
// sight while another waits further on, the bell still over the way to the end.

///|
test "小屏 by touch: one ask in sight and another further on, the bell shows over the way to the end" {
  let t = wide_tester([], mode="chat", w=390.0, h=844.0, platform=2)
  t.set_frame_period(1000.0 / 120.0)
  t.run_for(@ui.move_most_ms * 2.0)
  // (500 up from the end: the card of the 8th message in sight, the 10th's past the foot)
  t.drag(195.0, 168.8, 195.0, 668.8, steps=30)
  t.run_for(@ui.move_most_ms * 4.0)
  // (the round buttons over the list's foot, drawn whole: the way to the end and the bell over it)
  let round = t.drawn_instances().filter(fn(i) { i[2] == 32.0 && i[3] == 32.0 && i[11] == 1.0 }).map(fn(i) { i[1] })
  assert_eq(round.length(), 2, msg="\{round}")
}
