// The bottom bar, the sheets and a new chat over the fixture (newchat_fixture.mbt), 390 × 844.

///|
/// The bar's places' middles in the window with the notch open (the chats' pages), and its middle's height.
fn bar_places_at() -> (Array[Double], Double) {
  (bar_centres(390.0 - 44.0, 1.0, 4).map(fn(x) { x + 22.0 }), 844.0 - 22.0 - 28.0)
}

///|
test "the bar: a finger held still on it a moment has the ball a lens of liquid glass; a tap none; let go, the ball" {
  let t = tester("home")
  let (xs, y) = bar_places_at()
  let lensed = fn() { t.drawn_glass().iter().any(fn(g) { g.4 == 6 }) }
  t.tap(xs[0], y)
  t.run_for(bar_hold_ms)
  assert_false(lensed())
  t.press_at(xs[0], y)
  t.run_for(bar_hold_ms)
  // (the frame at its time takes the ball; its lens grows from there)
  t.frame()
  to_bar_rest(t)
  assert_true(lensed())
  t.release(xs[0], y)
  to_bar_rest(t)
  assert_false(lensed())
  assert_true(t.find("整理发布清单") is Some(_))
}

///|
test "the bar: 文件 tapped is its page in place of the chats', back is the chats again" {
  let t = tester("home")
  let (xs, y) = bar_places_at()
  t.tap(xs[1], y)
  assert_eq(app.nav.depth(), 1)
  assert_true(app.nav.top() == Files)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("文件") is Some(_))
  assert_true(t.find("整理发布清单") is None)
  // back goes to the chats, in place
  t.back()
  assert_true(app.nav.top() == Home)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("整理发布清单") is Some(_))
}

///|
/// Where the words `title` are drawn in the top bar's band, the rightmost (a page's own title, the page beside it to its
/// left).
fn bar_title_x(t : @ui.Tester, title : String) -> Double {
  t
  .words()
  .fold(init=-1.0e9, fn(a, w) { if w.0 == title && w.2 < status_top() + top_bar_h() && w.1 > a { w.1 } else { a } })
}

///|
/// The words drawn in the top bar's band from `from` on, as (words, x − from, y): the page's there, not the one beside
/// it to its left.
fn bar_words(t : @ui.Tester, from : Double) -> Array[(String, Double, Double)] {
  t
  .words()
  .filter(fn(w) { w.2 < status_top() + top_bar_h() && w.1 >= from - 0.5 })
  .map(fn(w) { (w.0, (w.1 - from).round(), w.2.round()) })
}

///|
test "文件 and 用量 at the bar's top, their gear tapped: as 设置 comes in beside them they keep their place's top bar, no back on it" {
  for place in ["files", "usage"] {
    let title = place_label(place)
    let t = tester("home")
    @sfbase.go_place(place) |> ignore
    t.run_for(@ui.move_most_ms)
    let rest_x = bar_title_x(t, title)
    let at_rest = bar_words(t, 0.0)
    let gear = t.locate("icon:settings")
    assert_eq(gear.length(), 1, msg=place)
    t.tap(gear[0].0, gear[0].1)
    assert_true(app.nav.top() == Settings, msg=place)
    // halfway through 设置's slide in from the left: the place's page going out to the right beside it is drawn as it
    // was at rest, moved (the stack two deep, it is still its root: its gear, not a way back to 设置)
    t.run_for(@ui.move_most_ms / 2.0)
    let from = bar_title_x(t, title) - rest_x
    assert_true(from > 0.0, msg=place)
    assert_eq(bar_words(t, from), at_rest, msg=place)
  }
}

///|
test "the bar: drawn up, the panel of the other bar; let go on its first place, that bar and 用量" {
  let t = tester("home")
  let (xs, y) = bar_places_at()
  t.drag(xs[0], y, xs[0], y - 64.0, steps=20)
  // the panel on its way open, to where it rests
  t.run_for(bar.o.end() - t.time())
  // let go over the rows before the panel was all the way open: it stays open
  if app.nav.top() == Home {
    assert_true(bar.mode.get())
    // the row of the other bar: its first place
    t.tap(xs[0], 844.0 - 22.0 - 132.0 + 20.0 + 28.0)
  }
  assert_true(app.nav.top() == Place("usage"))
  assert_true(t.find("用量") is Some(_))
  match bars_picked.get() {
    Some((_, cur)) => assert_eq(cur, 1)
    None => fail("no bar picked")
  }
}

///|
test "the bar: hidden under a page pushed, back as it comes back" {
  let t = tester("home")
  assert_true(bar.vis.value > 0.99)
  t.tap_text("夜里的构建又失败了")
  t.run_for(bar_hide_ms)
  assert_true(bar.vis.value < 0.01)
  t.back()
  t.run_for(@ui.move_most_ms)
  assert_true(bar.vis.value > 0.99)
}

///|
test "the workspaces' sheet: drawn up to 94%, dragged down past 30% it closes" {
  let t = tester("home")
  t.tap_text("星火工作室")
  sheet_rested(t, "sf-present")
  assert_true((t.get(@ui.Role::Dialog).rect.3 - 844.0 * 0.7).abs() < 1.0)
  let (x, y) = t.find("切换 workspace").unwrap()
  t.drag(x, y, x, y - 200.0)
  sheet_rested(t, "sf-present")
  assert_true((t.get(@ui.Role::Dialog).rect.3 - 844.0 * 0.94).abs() < 1.0)
  // a tap on the grabber: half
  let (x, y) = t.find("切换 workspace").unwrap()
  t.tap(x, y - 30.0)
  sheet_rested(t, "sf-present")
  assert_true((t.get(@ui.Role::Dialog).rect.3 - 844.0 * 0.55).abs() < 1.0)
  let (x, y) = t.find("切换 workspace").unwrap()
  t.drag(x, y, x, y + 300.0)
  sheet_rested(t, "sf-present")
  assert_true(t.find("切换 workspace") is None)
  assert_true(!sheet_open())
}

///|
test "a sheet takes the drags on it: the list under it does not scroll" {
  let t = tester("home")
  let before = t.list_offset()
  t.tap_text("星火工作室")
  sheet_rested(t, "sf-present")
  t.drag(195.0, 700.0, 195.0, 400.0)
  assert_eq(t.list_offset(), before)
  assert_true(@sf.presenting())
}

///|
test "a new chat: 令 raises it; the first message makes the chat and the page becomes it" {
  let t = tester("home")
  let (_, y) = bar_places_at()
  // 令 stands over the bar's middle
  t.tap(195.0, y - 28.0 - 4.0)
  assert_eq(app.nav.depth(), 2)
  assert_true(app.nav.risen())
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("想让 agent 做什么？") is Some(_))
  assert_true(t.find("Opus 5.5") is Some(_))
  t.tap_text("做任何事")
  t.type_text("把发布说明写一下")
  tap_send(t)
  // the page is the chat now, in place: no new page pushed, sideways back from it
  assert_eq(app.nav.depth(), 2)
  assert_true(!app.nav.risen())
  match app.nav.top() {
    Chat(r) => assert_eq(r.session, "new:1")
    _ => fail("not the chat")
  }
  t.run_for(new_leave_ms)
  assert_true(t.find("想让 agent 做什么？") is None)
  assert_true(t.find("把发布说明写一下") is Some(_))
}

///|
test "a new chat with the keyboard up: the scene scrolls in what is left, the choices and the composer over the keyboard" {
  let t = tester("home")
  let (_, y) = bar_places_at()
  t.tap(195.0, y - 28.0 - 4.0)
  t.run_for(@ui.move_most_ms)
  t.tap_text("做任何事")
  // the window laid out over the keyboard, as Android's host has it (adjustResize)
  let over = 844.0 - kbd_h
  t.resize(390.0, over)
  t.frame()
  let (_, fy, _, fh) = t.rect_of("做任何事").unwrap()
  assert_true(fy + fh <= over)
  assert_true(t.find("Opus 5.5") is Some(_))
}

///|
/// A phone's keyboard, as tall as most are.
let kbd_h : Double = 336.0

///|
/// On the frames' clock to where the sheet rests, as it says (@kit.sheet_rest: its springs and its scrim's fade):
/// risen from below, a row is tapped where it is.
fn run_to_sheet_rest(t : @ui.Tester) -> Unit raise {
  let end = @kit.sheet_rest("sf-present")
  if end < 0.0 || end > 1.0e300 {
    fail("the sheet does not move (its rest: \{end})")
  }
  t.run_for(end - t.time())
}

///|
test "a new chat: its station picked in the sheet, its model in the model's panel" {
  let t = tester("newchat")
  open_mode("newchat")
  // (the page opened drawn at its moment, its rise from there)
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("它会在 Studio 上") is Some(_))
  // the station's control, beside the model's
  let (_, cy) = t.find("Opus 5.5").unwrap()
  t.tap(50.0, cy)
  assert_true(t.find("选择运行的 station") is Some(_))
  run_to_sheet_rest(t)
  let (mx, my) = t.find_last("MBA").unwrap()
  t.tap(mx, my)
  assert_true(!@sf.presented_open_of(@sf.last_presented()))
  assert_eq(new_fix.station, "st2")
  assert_true(t.find("它会在 MBA 上") is Some(_))
  t.tap_text("Opus 5.5")
  assert_true(t.find("思考深度") is Some(_))
  run_to_sheet_rest(t)
  let (gx, gy) = t.find_last("GPT-6").unwrap()
  t.tap(gx, gy)
  assert_true(t.find("确定") is Some(_))
  let (ox, oy) = t.find_last("确定").unwrap()
  t.tap(ox, oy)
  assert_true(!@sf.presented_open_of(@sf.last_presented()))
  assert_true(t.find("GPT-6") is Some(_))
  // cancelled, it sinks back down
  t.tap_text("取消")
  assert_eq(app.nav.depth(), 1)
}

///|
test "the bar is glass of one capture: the bar with its notch, 令 and the ball frosting the page under them" {
  let t = tester("home")
  let gs = t.drawn_glass().filter(fn(g) { g.1 > 844.0 - 22.0 - 56.0 - 40.0 })
  assert_true(gs.length() >= 3)
  let (_, _, _, _, _, run) = gs[0]
  assert_true(gs.iter().all(fn(g) { g.5 == run }))
  // the notch cut into the bar's glass: 令's 28 and 6 round it, 4 over the edge
  assert_true(t.drawn_notches().iter().any(fn(n) { n.0 == 5 && n.2 == -4.0 && n.3 == 34.0 && n.4 == 8.0 }))
}

///|
test "the notch's icon swaps with a short scale and fade while it stays open; closed, at once" {
  let plus = bar_place_with("plus")
  let none = bar_place_with("")
  let (t, _) = bar_at_rest()
  assert_eq(m_face.val, "ling")
  // to a place whose action is another, the notch open throughout: the icon swaps
  ignore(@sfbase.go_place(plus))
  t.frame()
  t.frame()
  t.frame()
  assert_eq((m_face.val, bar.icon_was), ("plus", "ling"))
  let p = bar.icon_swap.value
  assert_true(p > 0.0 && p < 1.0, msg="\{p}")
  t.run_for(icon_swap_ms)
  assert_true(bar.icon_swap.value == 1.0)
  // the notch closed (a place with no action), then another action: nothing to see, at once
  ignore(@sfbase.go_place(none))
  t.run_for(bar_rest() - t.time())
  ignore(@sfbase.go_place("chats"))
  t.frame()
  assert_eq((m_face.val, bar.icon_swap.value), ("ling", 1.0))
  t.run_for(bar_rest() - t.time())
  t.assert_idle()
}

///|
test "the bar chosen in the panel slides down into the bar's place, its places laid out there from the first" {
  let t = tester("home")
  let (xs, y) = bar_places_at()
  t.drag(xs[0], y, xs[0], y - 64.0, steps=20)
  // let go over the rows before the panel was all the way open, it stays open: its row tapped
  if bar.swap_at(t.time()) is None {
    t.run_for(bar.o.end() - t.time())
    t.tap_once(xs[0], 844.0 - 22.0 - 132.0 + 20.0 + 28.0)
  }
  // chosen: the bar in view at once, the stack sliding down, a frame at a time to where it lands
  assert_true(app.nav.top() == Place("usage"))
  let mut seen = false
  let mut last = -1.0
  let lands = bar.o.end()
  while t.time() < lands {
    t.frame()
    match bar.swap_at(t.time()) {
      Some(s) => {
        let k = s.t(bar.o.x)
        assert_true(k >= last)
        last = k
        if k > 0.05 && k < 0.95 {
          seen = true
        }
      }
      None => ()
    }
  }
  assert_true(seen)
  assert_true(bar.swap_at(t.time()) is None)
  match bars_picked.get() {
    Some((_, cur)) => assert_eq(cur, 1)
    None => fail("no bar picked")
  }
}

///|
/// The bar's panel drawn up and the other bar's row tapped (its first place), on to 50 ms after that bar has landed: a
/// frame drawn at the moment it lands (`at_landing`), or none between the tap's and that one.
fn bar_chosen_landed(t : @ui.Tester, at_landing : Bool) -> Unit {
  let (xs, y) = bar_places_at()
  t.drag(xs[0], y, xs[0], y - 64.0, steps=20)
  if bar.swap_at(t.time()) is None {
    t.run_for(bar.o.end() - t.time())
    t.tap_once(xs[0], 844.0 - 22.0 - 132.0 + 20.0 + 28.0)
  }
  // (each frame said: run_for would draw one at the landing by itself, its springs saying they rest then)
  let lands = bar.o.end()
  if at_landing {
    t.frame_at(lands)
  }
  t.frame_at(lands + 50.0)
}

///|
test "the bar chosen and landed, the panel drawn up again: no bar landing then; the other chosen lands as the first did, a frame at its landing or none" {
  let seen = fn(at_landing : Bool) {
    let t = tester("home")
    bar_chosen_landed(t, at_landing)
    let first = (app.nav.top() == Place("usage"), bar.swap_at(t.time()) is None)
    // drawn up again: the panel the finger's, nothing landing, the ball riding nothing
    let (xs, y) = bar_places_at()
    t.drag(xs[0], y, xs[0], y - 64.0, steps=20)
    let again = (bar.swap_at(t.time()) is None, bar.ball_x.ride is None, bar.mode.get())
    // the other bar's row tapped on its first place (four of them across, no notch in a row): it lands
    t.run_for(bar.o.end() - t.time())
    t.tap_once(bar_centres(390.0 - 44.0, 0.0, 4)[0] + 22.0, 844.0 - 22.0 - 132.0 + 20.0 + 28.0)
    t.run_for(bar.o.end() + 50.0 - t.time())
    let second = (place_of(app.nav.top()) == Some("chats"), bar.swap_at(t.time()) is None, bars_picked.get().map(fn(b) { b.1 }))
    (first, again, second)
  }
  let want = ((true, true), (true, true, true), (true, true, Some(0)))
  assert_eq((seen(true), seen(false)), (want, want))
}
