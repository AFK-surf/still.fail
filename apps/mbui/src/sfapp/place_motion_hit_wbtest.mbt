///|
test "a place coming in has its drawing and input in the same place" {
  let t = tester("home")
  bars_picked.set(Some(([["chats", "stations"]], 0)))
  t.frame()
  to_bar_rest(t)
  let xs = bar_centres(390.0 - 44.0, bar.k.at(t.time()).0, 2)
  t.tap_once(xs[1] + 22.0, 844.0 - 22.0 - 28.0)
  let at = t.time()
  t.frame_at(at + @ui.move_ms(switch_slide) / 4.0)
  let label = place_label("stations")
  let words = t.words().filter(fn(w) { w.0 == label })
  assert_true(words.length() == 1, msg="the page's title: \{words}")
  let drawn = words[0]
  let point = t.find(label).unwrap()
  assert_true((point.0 - drawn.1 - drawn.3 / 2.0).abs() < 0.51, msg="the title's drawn and input positions must coincide")
}
