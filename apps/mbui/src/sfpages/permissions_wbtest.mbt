// 权限, 归档 and a station's own archiving (permissions.mbt) alone, at each width, with a finger and with a mouse: what
// each station does and each way to choose saves is the core's.

///|
test "权限, at each width and with either hand: notifications, what they are for and whether they are allowed, on a card" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(Permissions, w, platform~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("通知") is Some(_), msg=at)
    assert_true(t.find("已允许") is Some(_), msg=at)
  }
}

///|
test "归档, at each width and with either hand: the hint, its three ways, each station a row saying how it archives; its row opens its page" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(Archiving, w, platform~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("提示归档") is Some(_), msg=at)
    assert_true(t.find("按模型判断") is Some(_), msg=at)
    assert_true(t.find("空闲就归档 · 1 天 · Slack：3 天") is Some(_), msg=at)
    t.tap_text("Studio")
    t.run_for(@ui.move_most_ms)
    assert_true(app.nav.top() == Setting(StationArchiving("ws1/st1")), msg=at)
  }
}

///|
test "a station's archiving, at each width and with either hand: its review, its way, how long idle, Slack's; a way chosen saves what the core says it saves" {
  for case in page_cases {
    let (w, platform) = case
    let saved : Array[Json] = []
    let keep = fn(base : Source) -> Source {
      {
        ..base,
        call: fn(name, params, done) {
          if name == "archiving.save" {
            saved.push(params)
          }
          (base.call)(name, params, done)
        },
      }
    }
    let t = setting_tester(StationArchiving("ws1/st1"), w, platform~, over=keep)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("已开启 · GPT-6 mini") is Some(_), msg=at)
    assert_true(t.find("空闲多久") is Some(_), msg=at)
    assert_true(t.find("只在 Slack 里的对话") is Some(_), msg=at)
    // 按模型判断 chosen: the days kept, reviewed (the core's `modes`)
    t.tap_text("按模型判断")
    t.draw()
    t.draw()
    assert_eq(saved.length(), 1, msg=at)
    assert_eq(field(Some(saved[0]), "reviewed"), Some(Json::boolean(true)), msg=at)
    assert_eq(number(Some(saved[0]), "days"), 1.0, msg=at)
  }
}
