// A station's page in its three parts (src/sfdesk station_page.mbt, one page in every frame; the web's
// StationPage.tsx Body) over the settings' fixture: Studio (ws1/st1), online. At a phone's width with a finger, in a
// window tall enough for all of a part.

///|
/// Station `address`'s page, its part `part` (0 概览, 1 设置, 2 软件与设备) shown.
fn station_tester(address : String, part? : Int = 0) -> @ui.Tester {
  reset()
  let src = fixture("settings")
  @settings.station_parts[address] = part
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=2400.0, platform=2)
  t.draw()
  app.nav.push(Settings)
  app.nav.push(Setting(@settings.Route::Station(address)))
  t.draw()
  t.run_for(@ui.nav_push_ms)
  t
}

///|
test "a station's page in three parts: 概览 what runs on it, 设置 what it is let do, 软件与设备 its software and the machine" {
  let t = station_tester("ws1/st1")
  // 概览: what runs on it, and what else of it has a page (its memory, this phone's adb)
  assert_true(t.find("概览") is Some(_))
  assert_true(t.find("更多") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  assert_true(t.find("设备信息") is None)
  // 设置: what macOS lets it do; its agents' variables
  @settings.station_parts["ws1/st1"] = 1
  t.draw()
  assert_true(t.find("权限") is Some(_), msg="its grants")
  assert_true(t.find("Agent 环境变量") is Some(_), msg="its variables")
  assert_true(t.find("更多") is None, msg="the overview gone")
  // 软件与设备: its software, then what the machine is
  @settings.station_parts["ws1/st1"] = 2
  t.draw()
  assert_true(t.find("软件与更新") is Some(_))
  assert_true(t.find("设备信息") is Some(_), msg="the machine's rows")
}

///|
test "a station's page, its parts chosen by its choice: 设置 pressed shows it" {
  let t = station_tester("ws1/st1")
  match t.find_last("设置") {
    Some((x, y)) => t.tap(x, y)
    None => fail("no 设置")
  }
  t.draw()
  assert_eq(@settings.station_parts.get("ws1/st1"), Some(1))
  assert_true(t.find("Agent 环境变量") is Some(_))
}

///|
test "a login's link opens its station's page at 设置, where its card is" {
  reset()
  let src = fixture("settings")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=2400.0, platform=2)
  @settings.mark_login("ws1/st1", "login-2")
  t.draw()
  app.nav.push(Settings)
  app.nav.push(Setting(@settings.Route::Station("ws1/st1")))
  t.draw()
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("更多") is None, msg="not the overview")
  assert_true(t.find("在 Studio 上登录 codex") is Some(_))
}

///|
test "a station's page opened again begins at its overview" {
  let t = station_tester("ws1/st1", part=2)
  @settings.left(@settings.Route::Station("ws1/st1"))
  t.draw()
  assert_true(t.find("更多") is Some(_))
}
