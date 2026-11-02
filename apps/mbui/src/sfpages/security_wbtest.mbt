// 安全 and 开启安全模式 (security.mbt) alone, at each width, with a finger and with a mouse: its people and their
// devices, its stations; turning it off asked first; what turning it on would sign, and back. A new device is approved
// only by the code typed on it (lock_wait.mbt): nothing here approves one with a press.

///|
test "安全, at each width and with either hand: its people, devices and stations" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(Security, w, platform~)
    let at = "\{w} platform \{platform}"
    // (by app: its name over its devices, which machine each is, the most lately used first)
    scrolled_to(t, w, "Mac Studio")
    let (_, app) = t.find("still.fail 桌面版").unwrap()
    let (_, pro) = t.find("林的 MacBook Pro").unwrap()
    let (_, studio) = t.find("Mac Studio").unwrap()
    assert_true(app < pro && pro < studio, msg=at)
    scrolled_to(t, w, "Ana 的 MacBook Air")
    assert_true(t.find("Ana 的 MacBook Air") is Some(_), msg=at)
    assert_true(t.find("5 天前使用过 · 受信任") is Some(_), msg=at)
    scrolled_to(t, w, "受保护")
    assert_true(t.find("受保护") is Some(_), msg=at)
  }
}

///|
test "安全, at each width and with either hand: another device taken out of the lock, asked first; not this one" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(Security, w, platform~)
    let at = "\{w} platform \{platform}"
    let name = "Ana 的 MacBook Air"
    scrolled_to(t, w, name)
    // (移除 on each but this device's: Ana's MacBook's, the first not above its name, at its end wide, under its
    // words narrow)
    let (_, y) = t.find(name).unwrap()
    let shown = t.words().filter(fn(x) { x.0 == "移除" && x.5 > 0.5 && x.2 + x.4 > y })
    guard shown.length() > 0 else { fail("no 移除 drawn") }
    let mut near = shown[0]
    for x in shown {
      if x.2 < near.2 {
        near = x
      }
    }
    t.tap(near.1 + near.3 / 2.0, near.2 + near.4 / 2.0)
    t.frame()
    assert_true(@sf.presenting(), msg=at)
    assert_true(t.find("移除「Ana 的 MacBook Air · still.fail 桌面版」？") is Some(_), msg=at)
    assert_true(t.find("该设备将无法再访问受保护的 station，重新批准后才能使用") is Some(_), msg=at)
    @sf.close_presented()
    t.frame()
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
