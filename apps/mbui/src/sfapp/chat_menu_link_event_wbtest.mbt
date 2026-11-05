// A message link's menu choice opens or copies its address.

///|
fn link_menu_event_tester() -> @ui.Tester {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  scroll_run_clear(t, "example.com/bench/list") |> ignore
  let (x, y, w, h) = t.run_rects("example.com/bench/list")[0]
  t.press_at(x + w / 2.0, y + h / 2.0)
  t.run_for(long_press_ms)
  t.release(x + w / 2.0, y + h / 2.0)
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  t
}

///|
fn link_menu_event_choice(t : @ui.Tester, label : String) -> Unit raise {
  let (x, y) = match t.find(label) {
    Some(point) => point
    None => fail("the link menu offers \{label}")
  }
  t.touch_at(0, x, y, t.time())
  t.touch_at(2, x, y, t.time())
  // The small-screen sheet dispatches the choice in the next frame.
  t.frame()
}

///|
test "copying a message link from its menu copies the address" {
  let t = link_menu_event_tester()
  link_menu_event_choice(t, "复制链接")
  assert_eq(t.clipboard(), "https://example.com/bench/list")
  assert_true(t.opened().is_empty())
}

///|
test "opening a message link from its menu hands the address to the host" {
  let t = link_menu_event_tester()
  link_menu_event_choice(t, "打开链接")
  assert_eq(t.opened(), ["https://example.com/bench/list"])
}
