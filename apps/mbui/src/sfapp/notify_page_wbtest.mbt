// 通知, one page in every frame (src/sfdesk notifications.mbt): at a width of each tier, with a finger and with a
// mouse; its preview, the ways it tells, each kind and what tells of it, the rest; a kind opened, its ways.

///|
test "通知, at each width and with either hand: the ways, each kind with what tells of it (the core's kinds and badge's), a kind opened" {
  for case in one_page_cases {
    let (w, platform, regular, _) = case
    let t = one_page_tester(@settings.Route::Notifications, w, platform~, regular~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("提醒方式") is Some(_), msg=at)
    assert_true(t.find("通知类别") is Some(_), msg=at)
    assert_true(t.find("待你决定") is Some(_), msg=at)
    // a done turn: its banner while away (the core's `done`), not counted in the badge (the core's badgeKinds)
    assert_true(t.find("横幅（离开时）") is Some(_), msg=at)
    tap_in_page(t, "待你决定")
    t.draw()
    assert_true(t.find("计入红点") is Some(_), msg=at)
  }
}

///|
test "通知, the system having refused them: the banner's way to allow them opens the system's settings of the app's notifications" {
  for case in one_page_cases {
    let (w, platform, regular, _) = case
    let t = one_page_tester(@settings.Route::Notifications, w, platform~, regular~, mode="settings-notify-denied")
    let at = "\{w} platform \{platform}"
    tap_in_page(t, "在系统设置中开启")
    t.draw()
    assert_eq(t.notice_settings_opened(), 1, msg=at)
  }
}
