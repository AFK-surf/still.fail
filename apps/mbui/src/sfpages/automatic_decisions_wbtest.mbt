// 自动决策 (automatic_decisions.mbt) alone, at each width, with a finger and with a mouse: its point, what it does, how
// many stations have it on (the core's `settings`), a row to its page.

///|
test "自动决策, at each width and with either hand: 归档建议, what it does, how many stations have it on, its page" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(AutoDecisions, w, platform~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("1 台 station 已启用") is Some(_), msg=at)
    // what it does: a narrow page's short words, a wide one's longer
    if laid_wide(w) {
      assert_true(t.find("异步判断此 chat 是否还有后续事项") is Some(_), msg=at)
    } else {
      assert_true(t.find("标记完成后判断是否推荐归档") is Some(_), msg=at)
    }
    t.tap_text("归档建议")
    t.run_for(@ui.nav_push_ms)
    assert_true(app.nav.top() == Setting(AutoCompletion), msg=at)
  }
}
