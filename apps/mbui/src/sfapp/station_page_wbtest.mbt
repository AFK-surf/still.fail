// A station's page in its three parts (settings/stations.mbt station_page; Stations.kt StationScreen, as the web's
// StationPage.tsx Body) over the settings' fixture: Studio (ws1/st1), online.

///|
/// The page's part `words` chosen (its segmented choice: the last words of them drawn, the page's own over what is under
/// it, 设置's title among them), and the frame after, which shows it.
fn station_part(t : @ui.Tester, words : String) -> Unit {
  match t.find_last(words) {
    Some((x, y)) => t.tap(x, y)
    None => abort("no \"\{words}\" on screen")
  }
  t.draw()
}

///|
/// The page wheeled back to its top, where its parts are chosen.
fn page_top(t : @ui.Tester) -> Unit {
  t.move(195.0, 400.0)
  for _ in 0..<10 {
    t.wheel(195.0, 400.0, -600.0)
  }
}

///|
test "a station's page in three parts: 概览 the machine and what runs on it, 设置 what it is let do, 软件与设备 its versions and the machine" {
  let t = settings_tester("station:ws1/st1")
  // 概览: what is left of it, what runs on it; nothing of the other two
  assert_true(t.find("在此 station 上") is Some(_))
  assert_true(t.find("编辑变量") is None)
  assert_true(t.find("设备信息") is None)
  // 设置: what macOS lets it do first; its variables further down
  station_part(t, "设置")
  assert_true(t.find("在此 station 上") is None, msg="the overview gone")
  assert_true(t.find("屏幕录制") is Some(_), msg="its grants first")
  shown_on_page(t, "编辑变量")
  assert_true(t.find("编辑变量") is Some(_), msg="its variables")
  page_top(t)
  // 软件与设备: its versions, then what the machine is, a row each
  station_part(t, "软件与设备")
  assert_true(t.find("屏幕录制") is None, msg="the settings gone")
  shown_on_page(t, "设备信息")
  assert_true(t.find("主机名") is Some(_), msg="the machine's rows")
  page_top(t)
  // and back
  station_part(t, "概览")
  assert_true(t.find("在此 station 上") is Some(_))
}

///|
test "a login's link opens its station's page at 设置, where its card is" {
  reset()
  let src = fixture("settings")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  @settings.mark_login("ws1/st1", "login-2")
  open_setting("station:ws1/st1")
  t.draw()
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("在此 station 上") is None, msg="not the overview")
  shown_on_page(t, "agent 在这台 station 上做的登录")
  assert_true(t.find("在 Studio 上登录 codex") is Some(_))
}

///|
test "a station's page opened again begins at its overview" {
  let t = settings_tester("station:ws1/st1")
  station_part(t, "软件与设备")
  @settings.left(@settings.Route::Station("ws1/st1"))
  t.draw()
  assert_true(t.find("在此 station 上") is Some(_))
}
