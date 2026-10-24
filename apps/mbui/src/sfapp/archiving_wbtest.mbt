// 归档 and a station's own archiving, one page each in every frame (src/sfdesk permissions.mbt): at a width of each
// tier, with a finger and with a mouse; what each station does and each way to choose saves is the core's.

///|
test "归档, at each width and with either hand: the hint, its three ways, each station a row saying how it archives; its row opens its page" {
  for case in one_page_cases {
    let (w, platform, regular, _) = case
    let t = one_page_tester(@settings.Route::Archiving, w, platform~, regular~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("提示归档") is Some(_), msg=at)
    assert_true(t.find("按模型判断") is Some(_), msg=at)
    assert_true(t.find("空闲就归档 · 1 天 · Slack：3 天") is Some(_), msg=at)
    tap_in_page(t, "Studio")
    t.run_for(@ui.nav_push_ms)
    assert_true(app.nav.top() == Setting(@settings.Route::StationArchiving("ws1/st1")), msg=at)
  }
}

///|
test "a station's archiving, at each width and with either hand: its review, its way, how long idle, Slack's; a way chosen saves what the core says it saves" {
  for case in one_page_cases {
    let (w, platform, regular, _) = case
    let calls : Array[Made] = []
    reset()
    let base = fixture("settings")
    let src : Source = {
      ..base,
      call: fn(name, params, done) {
        calls.push({ name, params, bytes: None, done, heard: None })
        (base.call)(name, params, done)
      },
    }
    let t = @ui.Tester::new(fn(c) { view(c, src) }, w~, h=900.0, platform~)
    if regular {
      let log = t.drive("system {\"size_class\":{\"width\":\"regular\",\"height\":\"regular\"}}\n")
      assert_true(log.contains("EXIT 0"), msg=log.join("\n"))
    }
    t.draw()
    app.nav.push(Settings)
    app.nav.push(Setting(@settings.Route::StationArchiving("ws1/st1")))
    t.draw()
    t.run_for(@ui.nav_push_ms)
    if @sfdesk.wide.tape {
      @sfdesk.wide.tape_ask = Some(@sfdesk.TapePane::Page)
      t.draw()
      t.run_for(@sfdesk.side_move_ms)
    }
    let at = "\{w} platform \{platform}"
    assert_true(t.find("已开启 · GPT-6 mini") is Some(_), msg=at)
    assert_true(t.find("空闲多久") is Some(_), msg=at)
    assert_true(t.find("只在 Slack 里的对话") is Some(_), msg=at)
    // 按模型判断 chosen: the days kept, reviewed (the core's `modes`)
    tap_in_page(t, "按模型判断")
    t.draw()
    t.draw()
    let saved = calls.filter(fn(m) { m.name == "archiving.save" })
    assert_eq(saved.length(), 1, msg=at)
    assert_eq(field(Some(saved[0].params), "reviewed"), Some(Json::boolean(true)), msg=at)
    assert_eq(number(Some(saved[0].params), "days"), 1.0, msg=at)
  }
}
