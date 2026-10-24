// 开启安全模式 from the wide frame's 安全 (sfdesk security.mbt): its 开启 opens the page that turns the lock on, as the
// phone's does; back from it, 安全 again.

///|
test "wide: 安全's 开启 opens 开启安全模式, its back goes to 安全" {
  let t = wide_tester([], mode="settings")
  t.draw()
  app.nav.push(Setting(@settings.Route::Security))
  t.run_for(@ui.nav_push_ms)
  // (what 开启 says: the fixture's lock is on already, so its button is not shown)
  @settings.opening_lock.val = true
  t.draw()
  assert_true(t.find("开启安全模式") is Some(_), msg=t.drawn_text())
  // (its back over the title: the settings' list beside it says 安全 too)
  tap_in_page(t, "安全")
  t.draw()
  assert_false(@settings.opening_lock.val)
}
