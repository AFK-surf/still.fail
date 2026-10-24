// The step right after a profile is added and a profile's models (src/sfdesk accounts.mbt), one page each in every
// frame: at a width of each tier, with a finger and with a mouse; over ChatGPT 团队.

///|
test "a profile just added, at each width and with either hand: its models to choose; 跳过 goes on to its page in this one's place" {
  for case in one_page_cases {
    let (w, platform, regular, _) = case
    let t = one_page_tester(@settings.Route::PickModels("ws1/st1", "cx"), w, platform~, regular~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("选择模型") is Some(_), msg=at)
    assert_true(t.find("ChatGPT 团队") is Some(_), msg=at)
    // its list, by the core's series
    assert_true(t.find("GPT-6-MINI") is Some(_), msg=at)
    assert_true(t.find("完成") is Some(_), msg=at)
    tap_in_page(t, "跳过")
    t.run_for(@ui.nav_push_ms)
    // (in this one's place: none of it left under its page)
    assert_true(app.nav.top() == Setting(Profile("ws1/st1", "cx")), msg=at)
    assert_false(app.nav.pages().contains(Setting(@settings.Route::PickModels("ws1/st1", "cx"))), msg=at)
  }
}

///|
test "a profile's models, at each width and with either hand: how many are on, each to tick" {
  for case in one_page_cases {
    let (w, platform, regular, _) = case
    let t = one_page_tester(@settings.Route::ProfileModels("ws1/st1", "cx"), w, platform~, regular~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("已选 1 项") is Some(_), msg=at)
    assert_true(t.find("GPT-6-MINI") is Some(_), msg=at)
    assert_true(t.find("GPT-5.5") is Some(_), msg=at)
    // read again, at the title's end
    assert_true(t.find("刷新模型") is Some(_), msg=at)
  }
}
