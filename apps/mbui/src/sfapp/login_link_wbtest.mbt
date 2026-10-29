// A link to a login an agent started on a station (links.mbt open_target `login`; AppState.open's Screen.Station(address,
// login)): the station's page opened, its card marked and brought into view; a link to a station's 共享调试 its page.

///|
test "a login's link: the station's page, its card brought into view" {
  reset()
  @settings.reset()
  let src = fixture("settings")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  t.draw()
  let target = link_target({ "opens": "login", "workspace": "ws1", "station": "st1", "login": "login-2" })
  assert_true(open_target(src, target, false, None))
  t.draw()
  t.run_for(@ui.move_most_ms)
  // the page under it, scrolled to the card: well inside the window
  match t.find("在 Studio 上登录 codex") {
    Some((_, y)) => assert_true(y > 0.0 && y < 844.0, msg="the card in view at \{y}")
    None => fail("no login card on the station's page")
  }
}

///|
test "a station's 共享调试 link: its page" {
  reset()
  @settings.reset()
  let src = fixture("settings")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  t.draw()
  assert_true(open_target(src, link_target({ "opens": "adbShare", "workspace": "ws1", "station": "st1" }), false, None))
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() == Setting(AdbShare("ws1/st1")))
}
