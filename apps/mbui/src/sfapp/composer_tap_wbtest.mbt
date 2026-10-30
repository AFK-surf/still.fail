// Android's composer taken by a tap (Composer.kt, Compose's tap on a field: the focus as the finger lifts), however long
// the finger stayed down without moving.

///|
fn composer_tap_tester() -> @ui.Tester {
  reset()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "Android composer: a quick tap takes it" {
  let t = composer_tap_tester()
  t.tap_text("发消息")
  assert_true(t.ime().0)
}

///|
test "Android composer: a tap held a while takes it too" {
  let t = composer_tap_tester()
  let (x, y) = t.find("发消息").unwrap()
  t.touch(0, x, y)
  t.run_for(@ui.long_press_ms * 2.0)
  t.touch(2, x, y)
  t.draw()
  assert_true(t.ime().0)
}

///|
test "Android composer: a tap that wobbles a little takes it" {
  let t = composer_tap_tester()
  let (x, y) = t.find("发消息").unwrap()
  t.touch(0, x, y)
  t.run_for(@ui.tap_indication_ms)
  t.touch(1, x + 2.0, y + 2.0)
  t.run_for(@ui.tap_indication_ms)
  t.touch(2, x + 2.0, y + 2.0)
  t.draw()
  assert_true(t.ime().0)
}

///|
test "Android composer: a tap on the capsule beside the words takes it" {
  let t = composer_tap_tester()
  let (_, y) = t.find("发消息").unwrap()
  t.tap(250.0, y)
  assert_true(t.ime().0)
}

///|
test "Android composer: a tap anywhere on the capsule nothing in it takes puts the caret in the field (ChatHost.kt)" {
  let probe = composer_tap_tester()
  let (px, py, pw, ph) = probe.query(Button, label=@sf.t("web-main.composer.attach")).unwrap().rect
  let (wx, wy, ww, wh) = probe.rect_of("发消息").unwrap()
  // in the bar's row over the words' line and under it (the room of what the capsule holds, which no part of it
  // takes). (Round ＋, within a fingertip of it, is ＋'s, the gap between it and the words too: a finger reaches what
  // is smaller than it from round it, @ui.pointing)
  ignore((px, pw))
  let points = [(wx + ww / 2.0, (py + wy) / 2.0), (wx + ww / 2.0, (wy + wh + py + ph) / 2.0)]
  for at in points {
    let t = composer_tap_tester()
    t.tap(at.0, at.1)
    assert_true(t.ime().0, msg="a tap at \{at.0}, \{at.1}")
  }
}

