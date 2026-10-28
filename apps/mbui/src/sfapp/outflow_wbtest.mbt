// A station page's 数据外流 (sfpages/station_outflow.mbt, docs/data-outflow.md): the programs granted its data, each
// with who signed it and what it may read; 取消授权 asks first.

///|
test "a station's settings list the programs granted its data, and revoking one asks first" {
  reset()
  @settings.reset()
  let src = fixture("settings")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  t.draw()
  // the station's page, at its settings (a login's link opens it there)
  assert_true(open_target(src, link_target({ "opens": "login", "workspace": "ws1", "station": "st1", "login": "login-2" }), false, None))
  t.draw()
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find(tr("web-main.outflow.title")) is Some(_), msg="the section")
  assert_true(t.find("Comma") is Some(_), msg="the program")
  assert_true(t.find("token 用量和金额、chat 和它们的状态") is Some(_), msg="what it may read")
  t.click(Button, label=tr("web-main.outflow.revoke"))
  t.draw()
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find(tr("web-main.outflow.revokeConfirm").replace(old="{program}", new="Comma")) is Some(_), msg="asked first")
}
