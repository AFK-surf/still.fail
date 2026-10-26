// 安全 and 开启安全模式 (security.mbt) alone, at each width, with a finger and with a mouse: the devices waiting, each checked by its code (asked first), its people and their devices, its
// stations; turning it off asked first; what turning it on would sign, and back.

///|
test "安全, at each width and with either hand: a device waiting with its code, checked in a dialog; its people, devices and stations" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(Security, w, platform~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("Ana的新设备") is Some(_), msg=at)
    assert_true(t.find("482 917") is Some(_), msg=at)
    assert_false(@sf.presenting(), msg=at)
    tap_words(t, "验证")
    t.frame()
    assert_true(@sf.presenting(), msg=at)
    assert_true(t.find("一致，批准") is Some(_), msg=at)
    assert_true(t.find("不一致，拒绝") is Some(_), msg=at)
    @sf.close_presented()
    t.frame()
    scrolled_to(t, w, "MacBook")
    assert_true(t.find("MacBook") is Some(_), msg=at)
    scrolled_to(t, w, "受保护")
    assert_true(t.find("受保护") is Some(_), msg=at)
  }
}

///|
test "安全, at each width and with either hand: 关闭安全模式 asks first, the workspace's name typed" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(Security, w, platform~)
    let at = "\{w} platform \{platform}"
    scrolled_to(t, w, "关闭安全模式")
    tap_words(t, "关闭安全模式")
    t.frame()
    assert_true(@sf.presenting(), msg=at)
    assert_true(t.find("关闭安全模式？") is Some(_), msg=at)
  }
}

///|
test "开启安全模式, at each width and with either hand: its people, the devices and stations it would sign; 取消 goes back" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(SecurityOpen, w, platform~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("Ana · MacBook") is Some(_), msg=at)
    assert_true(t.find("林 · 此设备") is Some(_), msg=at)
    scrolled_to(t, w, "批准并开启")
    assert_true(t.find("Studio") is Some(_), msg=at)
    assert_true(t.find("批准并开启") is Some(_), msg=at)
    tap_words(t, "取消")
    t.draw()
    assert_false(app.nav.pages().contains(Setting(SecurityOpen)), msg=at)
  }
}
