// 通知 (notifications.mbt) alone, at each width, with a finger and with a mouse: its preview, the ways it tells, each
// kind and what tells of it, the rest; a kind opened, its ways.
///|
test "通知, at each width and with either hand: the ways, each kind with what tells of it (the core's kinds and badge's), a kind opened" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(Notifications, w, platform~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("提醒方式") is Some(_), msg=at)
    assert_true(t.find("通知类别") is Some(_), msg=at)
    assert_true(t.find("待你决定") is Some(_), msg=at)
    // a done turn: its banner while away (the core's `done`), not counted in the badge (the core's badgeKinds)
    assert_true(t.find("横幅（离开时）") is Some(_), msg=at)
    // (the kind's head, not the preview's banner that says it too)
    t.click(Button, label="待你决定")
    t.draw()
    // the badge a way where the system shows the app's number (a Mac's Dock), none on Android (its dot the system's)
    assert_eq(t.find("计入红点") is Some(_), platform == 0, msg=at)
    assert_eq(t.words().iter().any(fn(w) { w.0 == "红点" }), platform == 0, msg=at)
  }
}

///|
test "通知, the system having refused them: the banner's way to allow them opens the system's settings of the app's notifications" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(Notifications, w, platform~, mode="settings-notify-denied")
    let at = "\{w} platform \{platform}"
    t.tap_text("在系统设置中开启")
    t.draw()
    assert_eq(t.notice_settings_opened(), 1, msg=at)
  }
}
