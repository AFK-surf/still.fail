// A chat's title in the wide frame's bar, as wide as its part of the pane at most (chat_page.mbt chat_title_part):
// laid out by the pane it is in, in the frame the pane changes, nothing of it left to the next.

///|
/// The chat's title drawn now: how wide it is laid out.
fn title_drawn_w(t : @ui.Tester) -> Double? {
  t.words().iter().find_first(fn(w) { w.0.has_prefix("把发布清单") }).map(fn(w) { w.3 })
}

///|
test "wide: a long title cut at its part of the pane, in the frame the window narrows" {
  new_run()
  let src = fixture("chat-long-title")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  let wide = title_drawn_w(t).unwrap()
  // (one frame at the narrower window: the title as the pane it is in now has room for)
  t.resize(1000.0, 800.0)
  let now = title_drawn_w(t).unwrap()
  t.run_for(@ui.move_most_ms)
  let after = title_drawn_w(t).unwrap()
  assert_true(after < wide, msg="cut narrower in a narrower pane: \{wide} then \{after}")
  assert_eq(now, after)
}
