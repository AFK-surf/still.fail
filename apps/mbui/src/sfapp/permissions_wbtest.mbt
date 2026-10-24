// 权限 and 版本, one page each in every frame (src/sfdesk permissions.mbt, local_station.mbt): at a width of each tier,
// with a finger and with a mouse.

///|
test "权限, at each width and with either hand: notifications, what they are for and whether they are allowed, on a card" {
  for case in one_page_cases {
    let (w, platform, regular, _) = case
    let t = one_page_tester(@settings.Route::Permissions, w, platform~, regular~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("通知") is Some(_), msg=at)
    assert_true(t.find("已允许") is Some(_), msg=at)
  }
}

///|
test "版本, at each width and with either hand: this build and 检查更新" {
  for case in one_page_cases {
    let (w, platform, regular, _) = case
    let t = one_page_tester(@settings.Route::Version, w, platform~, regular~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("still.fail mbui 0.1") is Some(_), msg=at)
    assert_true(t.find("still.fail 桌面版") is Some(_), msg=at)
    assert_true(t.query(Button, label="检查更新") is Some(_), msg=at)
  }
}
