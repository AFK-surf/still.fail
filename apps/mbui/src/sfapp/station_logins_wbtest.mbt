// A station page's 登录 (settings/station_logins.mbt; LoginCards.kt StationLogins) over the settings' fixture: Studio's
// codex login under way as its card, gh's done yesterday as a row.

///|
test "a station's 登录: the login under way its card, the one done a row saying who started it and how it ended" {
  let t = settings_tester("station:ws1/st1")
  shown_on_page(t, "agent 在这台 station 上做的登录")
  assert_true(t.find("登录") is Some(_))
  // under way: its card, its step to do
  assert_true(t.find("在 Studio 上登录 codex") is Some(_))
  // done: its command, which chat's agent started it, when, how it ended
  assert_true(t.find("gh auth login") is Some(_))
  assert_true(t.find("「整理发布清单」的 agent 发起 · 昨天 · 已登录") is Some(_))
}

///|
test "a station with no logins says nothing of them" {
  let t = settings_tester("station:ws1/st2")
  shown_on_page(t, "在此 station 上")
  assert_true(t.find("agent 在这台 station 上做的登录") is None)
}
