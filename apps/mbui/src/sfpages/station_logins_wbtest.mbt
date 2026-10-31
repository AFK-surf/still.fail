// A station page's 登录 (station_cards.mbt station_logins, in its 设置) over the settings' fixture: Studio's
// codex login under way as its card, gh's done yesterday as its program's row, its try under it once opened.

///|
test "a station's 登录: the login under way its card, those done a row per program, who last logged in, its tries" {
  let t = station_tester("ws1/st1", part="settings")
  assert_true(t.find("登录") is Some(_))
  // under way: its card
  assert_true(t.find("在 Studio 上登录 codex") is Some(_))
  // done: its program, not its command line; who last logged in to it, when, from which chat; how many tries
  assert_true(t.words().any(fn(w) { w.0 == "gh" }), msg=t.words().map(fn(w) { w.0 }).join("|"))
  assert_true(t.find("gh auth login") is None)
  assert_true(t.find("林 登录 · 昨天 · 「整理发布清单」") is Some(_))
  assert_true(t.find("1 次") is Some(_))
  // its tries folded until it is pressed: then each, how it ended
  assert_true(t.find("林 完成") is None)
  t.tap_text("gh")
  assert_true(t.find("林 完成") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  t.tap_text("gh")
  assert_true(t.find("林 完成") is None)
}

///|
test "a station with no logins says nothing of them" {
  let t = station_tester("ws1/st2", part="settings")
  assert_false(t.words().any(fn(w) { w.0 == "gh" }))
  assert_true(t.find("在 Studio 上登录 codex") is None)
}
