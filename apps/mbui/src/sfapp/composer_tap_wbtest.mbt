// Android's composer taken by a tap (Composer.kt, Compose's tap on a field: the focus as the finger lifts), however long
// the finger stayed down without moving.

///|
fn composer_tap_tester() -> @ui.Tester {
  reset()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  t.run_for(@ui.nav_push_ms)
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
