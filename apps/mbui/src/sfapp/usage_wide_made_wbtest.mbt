// 用量 and 价目表 made once on a large screen (the pane off the tape) and on the tape at its widths: what each holds the
// tree's own, 用量's days and share where its head or its bar has them, with keyboard and mouse and with a finger.

///|
test "用量 and 价目表 made once wide and on the tape: what each holds the tree's own; 用量's days and share once each, at its head's or bar's line" {
  for case in [(0, 1280.0), (2, 1280.0), (0, 1800.0), (2, 600.0), (0, 700.0), (2, 839.0)] {
    let (platform, w) = case
    let t = large_about_tester(true, platform, w~, mode="settings-usage")
    let at = "用量 at \{case}"
    assert_true(app.nav.top() == Setting(@settings.Route::Usage), msg=at)
    let own = tree_words_drawn()
    for word in ["$118", "最花钱的对话", "各设备的工作量", "7 天", "30 天"] {
      assert_true(own.iter().any(fn(o) { o.contains(word) }), msg="\{word} not the tree's own at \{at}: \{own}")
    }
    let share = t.semantics().filter(fn(s) { s.role == @ui.Role::Button && s.label == @sf.t("web-main.stations.shareCard") && !s.hidden })
    assert_eq(share.length(), 1, msg="its share at \{at}")
    guard t.rect_of("7 天") is Some((_, dy, _, dh)) else { fail("no days at \{at}") }
    assert_true((share[0].rect.1 + share[0].rect.3 / 2.0 - (dy + dh / 2.0)).abs() < 4.0, msg="share and days on one line at \{at}")
    let _ = large_about_tester(true, platform, w~, mode="settings-prices")
    let own = tree_words_drawn()
    assert_true(own.iter().any(fn(o) { o.contains("Studio") }), msg="价目表's card the tree's own at \{case}: \{own}")
  }
}
