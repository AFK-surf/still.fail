// The filter over 连接's list on 大屏 (sfpages' connects.mbt mine_filter: all of them or the viewer's) dismissed by the
// hand: Escape, a press on the page, at that input's moment; its button pressed again with it open, then Escape at
// once, closed and staying closed.

///|
/// 大屏, a mouse's, 连接 open (its settings page).
fn connects_tester() -> @ui.Tester {
  let t = wide_tester([])
  t.host_says_finger(Some(false))
  open_setting("connects")
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// The filter's button as it is read out now (its words: what it shows).
fn connects_filter_label() -> String {
  @sf.t("web-main.filter.connects.named", args=[("named", @sf.t("web-main.filter.all"))])
}

///|
/// The filter's menu opened from its button, dismissed by `how` (as the host hands it on, no frame after it): whether
/// it is open then, once a frame is drawn, as the button opens it again and a frame after.
fn filter_dismissed(how : (@ui.Tester) -> Unit) -> Array[Bool] raise {
  let t = connects_tester()
  guard t.query(Button, label=connects_filter_label()) is Some(s) else {
    fail("no filter: \{t.semantics().map(fn(s) { s.label }).filter(fn(l) { l != "" }).join("|")}")
  }
  let (x, y) = (s.rect.0 + s.rect.2 / 2.0, s.rect.1 + s.rect.3 / 2.0)
  let open = fn() { @sfpages.mine_filter_shown("connects-filter") }
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
test "大屏: 连接's filter dismissed by Escape: closed as the key is taken; the frame after closes nothing more, opened again its own" {
  assert_eq(filter_dismissed(fn(t) { t.key_told(@ui.key_escape, 0, t.time()) }), [true, false, false, true, true])
}

///|
test "大屏: 连接's filter dismissed by a press on the page: closed as it goes down; the frame after closes nothing more, opened again its own" {
  let down : Array[Bool] = []
  let seen = filter_dismissed(fn(t) {
    t.touch_at(0, 1200.0, 760.0, t.time())
    down.push(@sfpages.mine_filter_shown("connects-filter"))
    t.touch_at(2, 1200.0, 760.0, t.time())
  })
  assert_eq((down, seen), ([false], [true, false, false, true, true]))
}

///|
test "大屏: 连接's filter pressed again with its menu open, then Escape at once: closed as it is let go, and stays closed, a frame between or none" {
  let run = fn(frames : Bool) raise {
    button_then_escape(connects_tester(), connects_filter_label(), fn() { @sfpages.mine_filter_shown("connects-filter") }, frames)
  }
  assert_eq((run(false), run(true)), ([false, false, false], [false, false, false]))
}
