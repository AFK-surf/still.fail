// 记忆 and a station's memory (memory.mbt) alone, at each width, with a finger and with a mouse: a row for each
// station opening its memory, on every width; a station's memory by its parts.

///|
test "记忆, at each width and with either hand: a row a station (one offline says so) opening its memory" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(Memories, w, platform~)
    let at = "\{w} platform \{platform}"
    // the same on every width: the stations' rows, no station's memory on the page
    assert_true(t.find("全局记忆 · 项目记忆") is Some(_), msg=at)
    assert_true(t.find("离线，上线后再查看") is Some(_), msg=at)
    assert_true(t.find("发布流程") is None, msg=at)
    t.tap_text("Studio")
    t.run_for(@ui.move_most_ms)
    assert_true(app.nav.top() == Setting(Memory("ws1/st1")), msg=at)
    // back to 记忆 over it
    assert_true(t.find("记忆") is Some(_), msg=at)
    // a station's memory: its global memory by its parts, its projects, the other skills, the station's own folded
    assert_true(t.find("全局记忆") is Some(_), msg=at)
    assert_true(t.find("习惯") is Some(_), msg=at)
    assert_true(t.find("发布流程") is Some(_), msg=at)
    assert_true(t.find("周报") is Some(_), msg=at)
    assert_true(t.find("pdf、xlsx") is Some(_), msg=at)
    t.tap_text("发布流程")
    t.run_for(@ui.move_most_ms)
    assert_true(app.nav.top() == Setting(MemoryDoc("ws1/st1", "发布流程", 0)), msg=at)
  }
}

///|
test "记忆: the station's own skills folded open and shut again" {
  let t = setting_tester(Memory("ws1/st1"), 390.0, platform=2)
  let row = fn() { t.words().any(fn(w) { w.0 == "xlsx" && w.5 > 0.5 }) }
  assert_true(t.find("pdf、xlsx") is Some(_))
  assert_false(row())
  t.tap_text("station 内置")
  t.draw()
  assert_true(row())
  t.tap_text("station 内置")
  t.draw()
  assert_false(row())
}
