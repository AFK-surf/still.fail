// 本机 Station's card's ⋯ on 大屏 (sfpages' local_station.mbt: stop, restart, update, its log, its folder) dismissed
// by the hand: Escape, a press on the page, at that input's moment; its ⋯ pressed again with it open, then Escape at
// once, closed and staying closed.

///|
/// 大屏, a mouse's, 本机 Station's page with the station here (a service of launchd's).
fn local_tester() -> @ui.Tester {
  let t = wide_tester([])
  t.host_says_finger(Some(false))
  t.set_local_station(
    #|{"data":"~/.stillfail","runner":"service","version":"0.1.4600","service":{"kind":"launchd","name":"fail.still.station"},"workspace":{"id":"ws1","name":"星火工作室","stationName":"Studio","removed":false}}
    ,
  )
  app.nav.replace(Setting(@settings.Route::LocalStation))
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// Its menu opened from its ⋯, dismissed by `how` (as the host hands it on, no frame after it): whether it is open
/// then, once a frame is drawn, as the ⋯ opens it again and a frame after.
fn local_menu_dismissed(how : (@ui.Tester) -> Unit) -> Array[Bool] raise {
  let t = local_tester()
  guard t.query(Button, label="更多操作") is Some(s) else { fail("no ⋯") }
  let (x, y) = (s.rect.0 + s.rect.2 / 2.0, s.rect.1 + s.rect.3 / 2.0)
  let open = fn() { @sfpages.local_menu_open() }
  t.tap(x, y)
  t.frame()
  let seen = [open()]
  how(t)
  seen.push(open())
  t.draw()
  seen.push(open())
  t.tap(x, y)
  t.frame()
  seen.push(open())
  t.draw()
  seen.push(open())
  seen
}

///|
test "大屏: 本机 Station's menu dismissed by Escape: closed as the key is taken; the frame after closes nothing more, opened again its own" {
  assert_eq(local_menu_dismissed(fn(t) { t.key_told(@ui.key_escape, 0, t.time()) }), [true, false, false, true, true])
}

///|
test "大屏: 本机 Station's menu dismissed by a press on the page: closed as it goes down; the frame after closes nothing more, opened again its own" {
  let down : Array[Bool] = []
  let seen = local_menu_dismissed(fn(t) {
    t.touch_at(0, 1200.0, 760.0, t.time())
    down.push(@sfpages.local_menu_open())
    t.touch_at(2, 1200.0, 760.0, t.time())
  })
  assert_eq((down, seen), ([false], [true, false, false, true, true]))
}

///|
test "大屏: 本机 Station's ⋯ pressed again with its menu open, then Escape at once: closed as it is let go, and stays closed, a frame between or none" {
  let run = fn(frames : Bool) raise {
    button_then_escape(local_tester(), "更多操作", fn() { @sfpages.local_menu_open() }, frames)
  }
  assert_eq((run(false), run(true)), ([false, false, false], [false, false, false]))
}
