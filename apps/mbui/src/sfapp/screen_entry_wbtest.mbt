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

///|
test "screen tabs release hidden streams and survive shell changes with one live stream" {
  new_run()
  let base = fixture("chat-screen-tab")
  let live : Map[Int, Int] = {}
  let serial = Ref(9000)
  let src : Source = {
    ..base,
    stream: fn(name, params, bytes, value, done) {
      let id = (base.stream)(name, params, bytes, value, done)
      if name != "screen.view" { return id }
      serial.val += 1
      live[serial.val] = id
      serial.val
    },
    cancel: fn(id) {
      match live.get(id) {
        Some(base_id) => { live.remove(id); (base.cancel)(base_id) }
        None => (base.cancel)(id)
      }
    },
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=669.0, h=951.0, platform=2)
  t.run_for(@ui.move_most_ms)
  for size in [(669.0, 951.0), (1440.0, 900.0), (669.0, 951.0)] {
    t.resize(size.0, size.1)
    t.run_for(@ui.move_most_ms)
    assert_eq(live.length(), 1, msg="live screen at \{size}")
  }
  let screen = @sfdesk.side_now(src, r).1
  @sfdesk.side_change(src, r, "open", Some("files"))
  t.run_for(@ui.move_most_ms)
  assert_eq(live.length(), 0)
  @sfdesk.side_change(src, r, "front", Some(screen))
  t.run_for(@ui.move_most_ms)
  assert_eq(live.length(), 1)
  @sfdesk.wide.tape_ask.set(Some(@sfdesk.TapePane::Panel))
  t.run_for(@ui.move_most_ms)
  @sfdesk.side_change(src, r, "clear", None)
  t.run_for(@ui.move_most_ms)
  assert_eq(live.length(), 0)
  assert_false(t.awake())
}
