// Edge to edge (the host's `bars`, bars.mbt): a chat's bar under the status bar, its composer over the navigation bar;
// with none said, where they were.

///|
/// Where a chat's title and its composer's words are, the bars said as `top` and `bottom` high.
fn chat_with_bars(top : Double, bottom : Double) -> ((Double, Double, Double, Double), (Double, Double, Double, Double)) raise {
  reset()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  if top > 0.0 || bottom > 0.0 {
    t.post(@hostapi.system_channel, "{\"bars\":{\"top\":\{top},\"bottom\":\{bottom},\"left\":0,\"right\":0}}")
  }
  t.frame()
  t.run_for(@ui.move_most_ms)
  match (t.rect_of("整理发布清单"), t.rect_of("发消息")) {
    (Some(a), Some(b)) => (a, b)
    _ => fail("no title or composer")
  }
}

///|
test "bars: a chat's title under the status bar, its composer over the navigation bar" {
  let (title0, words0) = chat_with_bars(0.0, 0.0)
  let (title, words) = chat_with_bars(24.0, 48.0)
  assert_true((title.1 - title0.1 - 24.0).abs() < 1.0e-9)
  assert_true((words.1 - words0.1 + 48.0).abs() < 1.0e-9)
  assert_eq(status_top(), 24.0)
  assert_eq(nav_foot(), 48.0)
}
