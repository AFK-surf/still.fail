///|
test "retained screen entries keep their control panel above each shell and return to the app" {
  for size in [(390.0, 844.0), (900.0, 700.0), (1440.0, 900.0)] {
    new_run()
    let src = fixture("screen-live")
    open_fixture_over("screen-live", src)
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=size.0, h=size.1, platform=2)
    t.draw()
    // This fixture opens one decoder; deliver its named decoded-frame event.
    assert_true(t.stream_fed(1).length() > 0)
    t.stream_shows(1, 1000.0, 1280, 720)
    t.run_for(@ui.move_most_ms)
    assert_true(app.nav.top() is Screen(_))
    assert_true(t.drawn_instances().any(fn(a) { a[5] == 4.0 && a[2] > 100.0 && a[3] > 100.0 }))
    tap_said(t, @sf.t("web-pages.screen.panel"))
    t.run_for(@ui.move_most_ms)
    assert_true(@sf.presenting())
    t.back()
    t.run_for(@ui.move_most_ms)
    assert_false(@sf.presenting())
    assert_true(app.nav.top() is Screen(_))
    t.back()
    t.run_for(@ui.move_most_ms)
    assert_false(app.nav.top() is Screen(_))
  }
}
