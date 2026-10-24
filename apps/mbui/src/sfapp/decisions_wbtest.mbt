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
