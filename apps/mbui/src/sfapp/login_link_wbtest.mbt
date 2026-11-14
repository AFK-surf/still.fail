// A link to a login an agent started on a station (links.mbt open_target `login`): the login's sheet opened over the
// page in view; a link to a station's 共享调试 its page.

///|
test "a login's link: its sheet opened over the page in view" {
  new_run()
  @settings.reset()
  let src = fixture("settings")
  app.nav.push(Settings)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  let target = link_target({ "opens": "login", "workspace": "ws1", "station": "st1", "login": "login-2" })
  assert_true(open_target(src, target, false, None))
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true(sheet_open())
  match t.find("在 Willow 上登录 codex") {
    Some((_, y)) => assert_true(y > 0.0 && y < 844.0, msg="the card in view at \{y}")
    None => fail("no login card in the login sheet")
  }
}

///|
test "a station's 共享调试 link: its page" {
  new_run()
  @settings.reset()
  let src = fixture("settings")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.draw()
  assert_true(open_target(src, link_target({ "opens": "adbShare", "workspace": "ws1", "station": "st1" }), false, None))
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() == Setting(AdbShare("ws1/st1")))
}
