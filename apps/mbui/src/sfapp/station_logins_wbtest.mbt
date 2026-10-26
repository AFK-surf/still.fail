// A station page's 登录 (src/sfdesk station_cards.mbt station_logins, in its 设置) over the settings' fixture: Studio's
// codex login under way as its card, gh's done yesterday as a row.

///|
test "a station's 登录: the login under way its card, the one done a row saying who started it and how it ended" {
  let t = station_tester("ws1/st1", part="settings")
  assert_true(t.find("登录") is Some(_))
  // under way: its card
  assert_true(t.find("在 Studio 上登录 codex") is Some(_))
  // done: its program, not its command line; who started it, how it ended, then when
  assert_true(t.words().any(fn(w) { w.0 == "gh" }), msg=t.words().map(fn(w) { w.0 }).join("|"))
  assert_true(t.find("gh auth login") is None)
  assert_true(t.find("「整理发布清单」的 agent 发起 · 已登录 · 昨天") is Some(_))
}

///|
test "a station with no logins says nothing of them" {
  let t = station_tester("ws1/st2", part="settings")
  assert_false(t.words().any(fn(w) { w.0 == "gh" }))
  assert_true(t.find("在 Studio 上登录 codex") is None)
}
