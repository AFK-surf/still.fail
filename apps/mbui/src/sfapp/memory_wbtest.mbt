// 记忆 and a station's memory, one page each in every frame (src/sfdesk memory.mbt): at a width of each tier, with a
// finger and with a mouse; a row for each station opening its memory, on every width.

///|
test "记忆, at each width and with either hand: a row a station (one offline says so) opening its memory" {
  for case in one_page_cases {
    let (w, platform, regular, _) = case
    let t = one_page_tester(@settings.Route::Memories, w, platform~, regular~)
    let at = "\{w} platform \{platform}"
    // the same on every width: the stations' rows, no station's memory on the page
    assert_true(t.find("全局记忆 · 项目记忆") is Some(_), msg=at)
    assert_true(t.find("离线，上线后再查看") is Some(_), msg=at)
    assert_true(t.find("发布流程") is None, msg=at)
    tap_in_page(t, "Studio")
    t.run_for(@ui.nav_push_ms)
    assert_true(app.nav.top() == Setting(@settings.Route::Memory("ws1/st1")), msg=at)
    // back to 记忆 over it
    assert_true(t.find("记忆") is Some(_), msg=at)
    // a station's memory: its global memory by its parts, its projects, the other skills, the station's own folded
    assert_true(t.find("全局记忆") is Some(_), msg=at)
    assert_true(t.find("习惯") is Some(_), msg=at)
    assert_true(t.find("发布流程") is Some(_), msg=at)
    assert_true(t.find("周报") is Some(_), msg=at)
    assert_true(t.find("pdf、xlsx") is Some(_), msg=at)
    tap_in_page(t, "发布流程")
    t.run_for(@ui.nav_push_ms)
    assert_true(
      app.nav.top() == Setting(@settings.Route::MemoryDoc("ws1/st1", "发布流程", 0)),
      msg=at,
    )
  }
}

///|
test "记忆: the station's own skills folded open and shut again" {
  let t = one_page_tester(@settings.Route::Memory("ws1/st1"), 390.0, platform=2)
  let row = fn() { t.words().any(fn(w) { w.0 == "xlsx" && w.5 > 0.5 }) }
  assert_true(t.find("pdf、xlsx") is Some(_))
  assert_false(row())
  tap_in_page(t, "station 内置")
  t.draw()
  assert_true(row())
  tap_in_page(t, "station 内置")
  t.draw()
  assert_false(row())
}

///|
test "记忆 as a place of the bottom bar: the top bar names it, no title of its own" {
  reset()
  let src = fixture("settings")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=900.0, platform=2)
  t.draw()
  app.nav.replace(Place("memories"))
  t.draw()
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("全局记忆 · 项目记忆") is Some(_))
  // no large title of its own under the top bar's
  assert_false(t.words().any(fn(w) { w.0 == "记忆" && w.4 > 30.0 && w.5 > 0.5 }), msg=t.drawn_text())
}
