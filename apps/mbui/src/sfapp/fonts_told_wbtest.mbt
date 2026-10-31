// 字体's 本机字体 on 大屏 (sfpages' font_setting.mbt: the families installed here, in a popover under its row)
// dismissed by the hand: Escape, a press on the page, at that input's moment; its row pressed again with it open, then
// Escape at once, closed and staying closed.

///|
/// 大屏, a mouse's, 字体's page with three families installed here, scrolled to 本机字体 (the faces' last row).
fn fonts_tester() -> @ui.Tester {
  let t = wide_tester([])
  t.host_says_finger(Some(false))
  t.set_local_fonts("[\"Menlo\",\"Avenir Next\",\"Helvetica\"]")
  app.nav.replace(Setting(@settings.Route::Fonts))
  t.run_for(@ui.move_most_ms)
  t.wheel(900.0, 400.0, 400.0)
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// 本机字体 opened from its row, dismissed by `how` (as the host hands it on, no frame after it): whether it is open
/// then, once a frame is drawn, as its row opens it again and a frame after.
fn fonts_dismissed(how : (@ui.Tester) -> Unit) -> Array[Bool] raise {
  let t = fonts_tester()
  guard t.query(Button, label="本机字体") is Some(s) else { fail("no 本机字体") }
  let (x, y) = (s.rect.0 + s.rect.2 / 2.0, s.rect.1 + s.rect.3 / 2.0)
  let open = fn() { @sfpages.local_open.val }
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
test "大屏: 本机字体 dismissed by Escape: closed as the key is taken; the frame after closes nothing more, opened again its own" {
  assert_eq(fonts_dismissed(fn(t) { t.key_told(@ui.key_escape, 0, t.time()) }), [true, false, false, true, true])
}

///|
test "大屏: 本机字体 dismissed by a press on the page: closed as it goes down; the frame after closes nothing more, opened again its own" {
  let down : Array[Bool] = []
  let seen = fonts_dismissed(fn(t) {
    t.touch_at(0, 1200.0, 100.0, t.time())
    down.push(@sfpages.local_open.val)
    t.touch_at(2, 1200.0, 100.0, t.time())
  })
  assert_eq((down, seen), ([false], [true, false, false, true, true]))
}

///|
test "大屏: 本机字体's row pressed again with it open, then Escape at once: closed as it is let go, and stays closed, a frame between or none" {
  let run = fn(frames : Bool) raise {
    button_then_escape(fonts_tester(), "本机字体", fn() { @sfpages.local_open.val }, frames)
  }
  assert_eq((run(false), run(true)), ([false, false, false], [false, false, false]))
}
