// 自动决策, one page in every frame (src/sfdesk automatic_decisions.mbt): at a width of each tier, with a finger and with
// a mouse; its point, what it does, how many stations have it on (the core's `settings`), a row to its page.

///|
test "自动决策, at each width and with either hand: 归档建议, what it does, how many stations have it on, its page" {
  for case in one_page_cases {
    let (w, platform, regular, phone) = case
    let t = one_page_tester(@settings.Route::AutoDecisions, w, platform~, regular~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("1 台 station 已启用") is Some(_), msg=at)
    // what it does: the narrow app's short words, the desktop's longer
    if phone {
      assert_true(t.find("标记完成后判断是否推荐归档") is Some(_), msg=at)
    } else if w >= 1100.0 {
      assert_true(t.find("异步判断此 chat 是否还有后续事项") is Some(_), msg=at)
    }
    tap_in_page(t, "归档建议")
    t.run_for(@ui.nav_push_ms)
    assert_true(app.nav.top() == Setting(@settings.Route::AutoCompletion), msg=at)
  }
}

///|
test "归档策略's fixtures on a desktop put their dialog up, though the frame they open in is built again" {
  // (the dialog asked once the page is built, the ask taken as it is put up: a frame built again, its earlier builds'
  // asks let go, still puts it up)
  for case in [("settings-policy-option", "已完成"), ("settings-policy-text", "归档策略")] {
    let (mode, title) = case
    let t = screen_in(mode, ("wide", 1280.0, 800.0, 0, ""), "zh")
    assert_true(@sf.presenting(), msg="\{mode}: its dialog")
    assert_true(t.find("保存") is Some(_), msg="\{mode}: its 保存")
    assert_true(t.locate(title).length() >= 2, msg="\{mode}: its title over the page's: \{t.locate(title)}")
  }
}
