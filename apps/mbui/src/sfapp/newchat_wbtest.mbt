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
test "the bar: holding a place hides 令 or ＋, moving keeps it hidden, and letting go brings it back" {
  let held_frame_ms = 1000.0
  let moved_frame_ms = 100.0
  for action in ["ling", "plus"] {
    let t = tester("home")
    let place = if action == "ling" { "chats" } else { bar_place_with("plus") }
    if action == "plus" {
      assert_true(@sfbase.go_place(place))
      t.run_for(@ui.move_most_ms)
    }
    assert_eq(m_face.val, action)
    let (xs, y) = bar_places_at()
    let told = bar.told.unwrap()
    let j = told.sets[told.cur].search(place).unwrap()
    let x = xs[j]
    // The accent disc under the glass is part of the button, as are its glass and icon.
    let disc_alpha = fn() {
      let theme = @sf.theme()
      let ink = @sf.over(theme.p.bg, @sf.alpha(theme.p.accent, action_ink))
      t.drawn_rects()
      .filter(fn(r) {
        (r.2 - drop).abs() < 0.1 && (r.3 - drop).abs() < 0.1 &&
        (r.0 - (195.0 - drop / 2.0)).abs() < 0.1 && r.1 > 600.0 && r.4 >> 8 == ink >> 8
      })
      .fold(init=0L, fn(a, r) { if (r.4 & 0xFFL) > a { r.4 & 0xFFL } else { a } })
    }
    assert_true(disc_alpha() > 0L, msg="\{action} before holding")
    t.press_at(x, y)
    t.run_for(bar_hold_ms / 2.0)
    assert_true(disc_alpha() > 0L, msg="\{action} before the hold")
    t.run_for(bar_hold_ms / 2.0)
    t.frame()
    t.run_for(held_frame_ms)
    assert_eq(disc_alpha(), 0L, msg="\{action} held")
    t.move_to(x + 12.0, y)
    t.run_for(moved_frame_ms)
    assert_eq(disc_alpha(), 0L, msg="\{action} moved")
    t.release(x + 12.0, y)
    t.run_for(held_frame_ms)
    assert_true(disc_alpha() > 0L, msg="\{action} released")
    if action == "ling" {
      t.tap(195.0, y - 28.0 - 4.0)
      assert_true(app.nav.risen(), msg="令 works after letting go")
    }
  }
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
/// Where the words `title` are drawn in the top bar's band, the leftmost (a page's own title, not the back of the page
/// coming in beside it to its right, which names it too).
fn bar_title_x(t : @ui.Tester, title : String) -> Double {
  t
  .words()
  .fold(init=1.0e9, fn(a, w) { if w.0 == title && w.2 < status_top() + top_bar_h() && w.1 < a { w.1 } else { a } })
}

///|
/// The words drawn in the top bar's band of the page a width wide from `from` on, as (words, x − from, y): the page's
/// there, not the one beside it.
fn bar_words(t : @ui.Tester, from : Double) -> Array[(String, Double, Double)] {
  t
  .words()
  .filter(fn(w) { w.2 < status_top() + top_bar_h() && w.1 >= from - 0.5 && w.1 < from + 390.0 - 0.5 })
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
    // at the bar's right edge, right of the place's name, as Home's is
    assert_true(gear[0].0 > rest_x && gear[0].0 > 390.0 - 16.0 - 34.0, msg="\{place}: \{gear[0].0}")
    t.tap(gear[0].0, gear[0].1)
    assert_true(app.nav.top() == Settings, msg=place)
    // halfway through 设置's slide in from the right: the place's page going out to the left beside it is drawn as it
    // was at rest, moved (the stack two deep, it is still its root: its gear, not a way back to 设置)
    t.run_for(@ui.move_most_ms / 2.0)
    let from = bar_title_x(t, title) - rest_x
    assert_true(from < 0.0, msg=place)
    assert_eq(bar_words(t, from), at_rest, msg=place)
  }
}

///|
test "the panel drawn up by a finger: the bar and the panel drawn up clear of the finger, a finger taken where they are laid out; let go, back down" {
  let t = tester("home")
  let (xs, y) = bar_places_at()
  // the bar's glass (as wide as the bar: not the ball's, nor the lens'): where its foot is drawn
  let foot = fn() {
    t.drawn_glass_corners().fold(init=0.0, fn(a, g) { if g.2 > 300.0 { dmax(a, g.1 + g.3) } else { a } })
  }
  let rest = foot()
  t.press_at(xs[0], y)
  for i in 1..=20 {
    t.move_to(xs[0], y - 64.0 * i.to_double() / 20.0)
  }
  t.run_for(@ui.move_most_ms)
  let held = foot()
  // a finger's place is where the rows are laid out: let go over the other bar's row, that bar
  t.release(xs[0], 844.0 - 22.0 - 132.0 + 20.0 + 28.0)
  // (the test's end: all of the bar at rest, the bar chosen landed)
  t.run_for(bar.rest() - t.time())
  assert_eq(((rest - held).round(), (rest - foot()).round()), (59.0, 0.0))
  assert_true(app.nav.top() == Place("archive"))
}

///|
test "the bar: drawn up, the panel of the other bar; let go on its first place, that bar and 已归档" {
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
  assert_true(app.nav.top() == Place("archive"))
  assert_true(t.find("已归档") is Some(_))
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
  presented_rested(t)
  assert_true((t.get(@ui.Role::Dialog).rect.3 - 844.0 * 0.7).abs() < 1.0)
  let (x, y) = t.find("切换 workspace").unwrap()
  t.drag(x, y, x, y - 200.0)
  presented_rested(t)
  assert_true((t.get(@ui.Role::Dialog).rect.3 - 844.0 * 0.94).abs() < 1.0)
  // a tap on the grabber: half
  let (x, y) = t.find("切换 workspace").unwrap()
  t.tap(x, y - 30.0)
  presented_rested(t)
  assert_true((t.get(@ui.Role::Dialog).rect.3 - 844.0 * 0.55).abs() < 1.0)
  let (x, y) = t.find("切换 workspace").unwrap()
  t.drag(x, y, x, y + 300.0)
  presented_rested(t)
  assert_true(t.find("切换 workspace") is None)
  assert_true(!sheet_open())
}

///|
test "a sheet takes the drags on it: the list under it does not scroll" {
  let t = tester("home")
  // (where the list is, by a row of it)
  let row = fn() { t.locate("=把旧的截图都换成新的").map(fn(p) { p.1 }) }
  let before = row()
  t.tap_text("星火工作室")
  presented_rested(t)
  t.drag(195.0, 700.0, 195.0, 400.0)
  assert_eq(row(), before)
  assert_true(@sf.presenting())
}

///|
/// Frames on to where what the presenters hold up as a sheet said it is at rest, whichever kind it is drawn as
/// (@sf.presented_rest: its motions' ends, from their causes' moments and lengths).
fn presented_rested(t : @ui.Tester) -> Unit {
  t.draw()
  let e = @sf.presented_rest()
  if e > t.time() && e < 1.0e300 {
    t.run_for(e - t.time())
  }
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
  let end = @sf.presented_rest()
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
  assert_true(t.find("它会在 Willow 上") is Some(_))
  // the station's control, after the preset's, beside the model's
  let (sx, sy) = t.find_last("Willow").unwrap()
  t.tap(sx, sy)
  assert_true(t.find("选择运行的 station") is Some(_))
  presented_rested(t)
  let (mx, my) = t.find_last("Maple").unwrap()
  t.tap(mx, my)
  assert_true(!@sf.presented_open_of(@sf.last_presented()))
  assert_eq(new_fix.station, "st2")
  assert_true(t.find("它会在 Maple 上") is Some(_))
  t.tap_text("Opus 5.5")
  assert_true(t.find("思考深度") is Some(_))
  run_to_sheet_rest(t)
  // (picked, made what it runs on: the panel closed, nothing to confirm)
  let (gx, gy) = t.find_last("GPT-6").unwrap()
  t.tap(gx, gy)
  assert_true(!@sf.presented_open_of(@sf.last_presented()))
  assert_true(t.find("GPT-6") is Some(_))
  // cancelled, it sinks back down
  t.tap_text("取消")
  assert_eq(app.nav.depth(), 1)
}

///|
test "a new chat with disabled profiles leads back to enable them" {
  let t = tester("newchat-disabled")
  open_mode("newchat-disabled")
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("Profile 已停用") is Some(_))
  assert_true(t.find("Willow 的可用 Profile 均已停用，请在 Profile 页面重新启用。") is Some(_))
  t.tap_text("查看 Profile")
  assert_true(app.nav.top() is Setting(@settings.Route::Profiles("ws1/st1")))
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
  assert_true(app.nav.top() == Place("archive"))
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
    let first = (app.nav.top() == Place("archive"), bar.swap_at(t.time()) is None)
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

///|
test "the bar drawn up clear of a finger as long as it has it: drawn up, further up and back down onto the bar; sliding along the bar; let go, back down" {
  let t = tester("home")
  let (xs, y) = bar_places_at()
  let foot = fn() {
    t.drawn_glass_corners().fold(init=0.0, fn(a, g) { if g.2 > 300.0 { dmax(a, g.1 + g.3) } else { a } })
  }
  let rest = foot()
  let raised = fn() {
    t.run_for(@ui.move_most_ms)
    (rest - foot()).round()
  }
  t.press_at(xs[0], y)
  for i in 1..=20 {
    t.move_to(xs[0], y - 64.0 * i.to_double() / 20.0)
  }
  let up = raised()
  for i in 1..=30 {
    t.move_to(xs[0], y - 64.0 - 400.0 * i.to_double() / 30.0)
  }
  let further = raised()
  for i in 1..=30 {
    t.move_to(xs[0], y - 464.0 + 464.0 * i.to_double() / 30.0)
  }
  let back = raised()
  for i in 1..=20 {
    t.move_to(xs[0] + (xs[2] - xs[0]) * i.to_double() / 20.0, y)
  }
  let along = raised()
  t.release(xs[2], y)
  t.run_for(bar.rest() - t.time())
  // a finger sliding along the bar alone, never drawing the panel up
  t.press_at(xs[0], y)
  for i in 1..=20 {
    t.move_to(xs[0] + (xs[1] - xs[0]) * i.to_double() / 20.0, y)
  }
  let sliding = raised()
  t.release(xs[1], y)
  t.run_for(bar.rest() - t.time())
  assert_eq((up, further, back, along, sliding, (rest - foot()).round()), (59.0, 59.0, 59.0, 59.0, 59.0, 0.0))
}

///|
test "the bar held: more room above the finger in a taller window, bounded by the top of a short window" {
  let measure = fn(h : Double, open : Bool) {
    new_run()
    let src = fixture("home")
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h~, platform=2)
    // The bar is 346 wide here; the page's full-width top bar is not the panel.
    let glass = fn() { t.drawn_glass_corners().filter(fn(g) { g.2 > 300.0 && g.2 < 360.0 }) }
    let foot = fn() { glass().fold(init=0.0, fn(a, g) { dmax(a, g.1 + g.3) }) }
    let rest = foot()
    let (xs, _) = bar_places_at()
    let y = h - 22.0 - 28.0
    t.press_at(xs[0], y)
    if open {
      for i in 1..=20 {
        t.move_to(xs[0], y - 64.0 * i.to_double() / 20.0)
      }
    } else {
      t.run_for(bar_hold_ms)
      t.frame()
    }
    t.run_for(@ui.move_most_ms)
    let raised = rest - foot()
    let top = glass().fold(init=h, fn(a, g) { dmin(a, g.1) })
    t.release(xs[0], y)
    (raised, top)
  }
  let short = measure(550.0, false).0
  let regular = measure(844.0, false).0
  let tall = measure(1200.0, false).0
  // More than the former 44 points, increasing with available height but never an excessive displacement.
  assert_true(short > 44.0 && short < regular && regular < tall && tall <= 64.1)
  // The panel can still open in a very short window without its glass crossing the top margin.
  let (limited, top) = measure(180.0, true)
  assert_true(limited > 0.0 && limited < short)
  assert_true(top >= 7.5, msg="panel top: \{top}")
}

///|
/// The three screens a new chat's stations open on: a phone's window with touch (a sheet from its foot), with keyboard
/// and mouse, and a wide window with keyboard and mouse (a panel beside its station's control).
// kept across runs: a value (no field of it changes)
let ns_screens : Array[(Int, Bool)] = [(2, false), (0, false), (0, true)]

///|
/// A new chat over the fixture's workspace on a phone's window (390 by 844) started as `platform`, `wide` 1200 by 800;
/// its station's control (Willow) pressed, its stations open and at rest. The calls made go in
/// `calls`.
fn ns_open(calls : Array[String], platform~ : Int, wide~ : Bool) -> @ui.Tester {
  new_run()
  @sf.presenters_reset()
  let base = fixture("newchat")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push(name + " " + params.stringify())
      (base.call)(name, params, done)
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform~)
  if wide {
    t.resize(1200.0, 800.0)
  }
  open_mode("newchat")
  t.draw()
  t.run_for(@ui.move_most_ms)
  guard t.semantics().filter(fn(s) { s.role == @ui.Role::Button && s.label == "Willow" && !s.hidden }).last() is Some(b) else {
    @halt.saying("no Willow to press")
  }
  t.tap(b.rect.0 + b.rect.2 / 2.0, b.rect.1 + b.rect.3 / 2.0)
  presented_rested(t)
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// Whether `words` are drawn (seen at all), the last of them where they are.
fn ns_seen(t : @ui.Tester, words : String) -> (Double, Double, Double, Double)? {
  t.words().filter(fn(w) { w.0 == words && w.5 > 0.0 }).last().map(fn(w) { (w.1, w.2, w.3, w.4) })
}

///|
test "a new chat's stations on every screen: a row each under its title, Willow checked, each's state on its name's line and what is left of it and how it is reached under it; nothing of it has the focus as it opens, no input method" {
  for s in ns_screens {
    let (platform, wide) = s
    let at = "platform \{platform} wide \{wide}"
    let t = ns_open([], platform~, wide~)
    let rows = t.semantics().filter(fn(n) { n.role == @ui.Role::Button && (n.label == "Willow" || n.label == "Maple") && !n.hidden }).filter(fn(n) { n.check is Some(_) })
    assert_eq(rows.map(fn(n) { (n.label, n.check) }), [("Willow", Some(@ui.Check::On)), ("Maple", Some(@ui.Check::Off))], msg=at)
    assert_false(t.focused() is Some(f) && rows.iter().any(fn(r) { r.label == f.label && r.rect == f.rect }), msg="\{at}: \{Repr(t.focused())}")
    assert_false(t.ime().0, msg="\{at}: the input method up")
    guard ns_seen(t, "选择运行的 station") is Some(title) else { fail("\{at}: no title") }
    assert_true(rows[0].rect.1 > title.1 && rows[1].rect.1 > rows[0].rect.1 + rows[0].rect.3 - 0.5, msg="\{at}: \{Repr(rows.map(fn(r) { r.rect }))}")
    // (Willow: 2 at work on its name's line, its figures and 直连 · 38 ms under it; Maple: 未连接)
    for w in ["2 个运行中", "直连 · 38 ms", "未连接", "CPU", "内存", "磁盘"] {
      assert_true(ns_seen(t, w) is Some(_), msg="\{at}: \{w}")
    }
    guard (ns_seen(t, "2 个运行中"), ns_seen(t, "直连 · 38 ms")) is (Some(busy), Some(net)) else { fail(at) }
    assert_true(busy.1 < rows[0].rect.1 + 30.0 && net.1 > busy.1 && net.1 < rows[1].rect.1, msg="\{at}: \{Repr(busy)} \{Repr(net)}")
  }
}

///|
test "a new chat's stations on every screen, Maple pressed: picked (newChat.pick, once), closed, on its way out as high as it was, its rows and Willow's check shown all the way" {
  for s in ns_screens {
    let (platform, wide) = s
    let at = "platform \{platform} wide \{wide}"
    let calls : Array[String] = []
    let t = ns_open(calls, platform~, wide~)
    let size = fn() {
      t.semantics().iter().find_first(fn(s) { s.role == @ui.Role::Dialog }).map(fn(s) { (s.rect.2, s.rect.3) })
    }
    guard size() is Some((was_w, was)) else { fail("\{at}: no panel") }
    let drawn = fn(w : String) { t.words().iter().any(fn(x) { x.0 == w && x.5 > 0.0 }) }
    guard t.semantics().filter(fn(n) { n.role == @ui.Role::Button && n.label == "Maple" && n.check is Some(_) && !n.hidden }).last() is Some(m) else {
      fail("\{at}: no Maple")
    }
    let before = calls.length()
    t.tap(m.rect.0 + m.rect.2 / 2.0, m.rect.1 + m.rect.3 / 2.0)
    let mut n = 0
    while @sf.presenter_visible() && n < 120 {
      match size() {
        Some(s) => {
          let h = s.1 * was_w / s.0
          assert_true((h - was).abs() <= 0.01, msg="\{at}: frame \{n} on its way out: \{h} high, \{was} before")
        }
        None => ()
      }
      for w in ["2 个运行中", "未连接", "直连 · 38 ms"] {
        assert_true(drawn(w) || !drawn("选择运行的 station"), msg="\{at}: frame \{n} on its way out: \{w} not drawn")
      }
      t.frame()
      n += 1
    }
    assert_false(@sf.presenter_visible(), msg="\{at}: gone")
    assert_eq(calls[before:].to_owned().filter(fn(c) { c.has_prefix("newChat.pick") }), ["newChat.pick {\"station\":\"st2\",\"scope\":\"ws1\"}"], msg=at)
  }
}

///|
/// What is wrong with each station's row of where a new chat runs as `t` shows it (`at` says where): its name's line as
/// high as its words, so the row's padding is as much over its name as under its last line (the old panel's), and its
/// machine's chips in the middle of their line, between the name's foot and the line under them, their words inside
/// them; "" where nothing is.
fn ns_rows_wrong(t : @ui.Tester, at : String) -> String {
  let all = t.words().filter(fn(w) { w.5 > 0.0 })
  let title = @sf.t("android-chat.new.station.pick")
  // (the panel's own words, painted after its title over the page's controls underneath)
  let words = match all.search_by(fn(w) { w.0 == title }) {
    Some(i) => all[i + 1:].to_owned()
    None => all
  }
  let wrong : Array[String] = []
  for name in ["Willow", "Maple"] {
    guard t.semantics().filter(fn(n) { n.role == @ui.Role::Button && n.label == name && n.check is Some(_) && !n.hidden }).last() is Some(r) else {
      wrong.push("\{at}: no row of \{name}")
      continue
    }
    let (_, ry, _, rh) = r.rect
    let inside = words.filter(fn(w) { w.2 >= ry - 0.01 && w.2 + w.4 <= ry + rh + 0.01 })
    guard inside.iter().find_first(fn(w) { w.0 == name }) is Some(n) else {
      wrong.push("\{at}: no \{name} in its row")
      continue
    }
    let foot = n.2 + n.4
    let under = inside.filter(fn(w) { w.2 > n.2 + 0.5 })
    guard under.iter().find_first(fn(w) { w.0 == "CPU" }) is Some(chip) else {
      wrong.push("\{at}: no chips under \{name}")
      continue
    }
    let last = under.fold(init=chip, fn(a, w) { if w.2 > a.2 { w } else { a } })
    let over_name = n.2 - ry
    let under_last = ry + rh - (last.2 + last.4)
    if (over_name - under_last).abs() > 0.01 {
      wrong.push("\{at}: \{name}'s row \{over_name} over its name, \{under_last} under 「\{last.0}」")
    }
    let (above, below) = (chip.2 - foot, last.2 - (chip.2 + chip.4))
    if above < -0.01 || (above - below).abs() > 0.01 {
      wrong.push("\{at}: \{name}'s chips \{above} under its name's foot, \{below} over 「\{last.0}」")
    }
    // (its chip: the ground under its words, no taller than a line, the one round them where any is)
    let ground = t
      .drawn_rects()
      .filter(fn(g) { g.3 < 30.0 && g.0 <= chip.1 && chip.1 < g.0 + g.2 && g.1 <= chip.2 + chip.4 && chip.2 < g.1 + g.3 })
    if ground.is_empty() || ground.iter().all(fn(g) { chip.2 < g.1 - 0.01 || chip.2 + chip.4 > g.1 + g.3 + 0.01 }) {
      wrong.push("\{at}: \{name}'s 「CPU」 \{chip.2}..\{chip.2 + chip.4} outside its chip (\{Repr(ground)})")
    }
  }
  wrong.join("\n")
}

///|
test "where a new chat runs, on every screen at the default size of words and on a phone at 1.3: each station's name's line as high as its words, its chips in the middle of their line and their words inside them" {
  for s in ns_screens {
    let (platform, wide) = s
    let calls : Array[String] = []
    let t = ns_open(calls, platform~, wide~)
    assert_eq(ns_rows_wrong(t, "platform \{platform} wide \{wide}"), "")
  }
  guard corner_windows.search_by(w => w.0 == "phone") is Some(i) else { fail("no phone window in corner_windows") }
  for lang in ["zh", "en"] {
    let t = screen_in("newchat-station", corner_windows[i], lang, font_scale=1.3)
    assert_eq(ns_rows_wrong(t, "phone \{lang} at 1.3"), "")
  }
}

///|
test "wide: a new chat's stations under a mouse have concentric corners in the panel and stay lit over a row's meter chips" {
  let t = ns_open([], platform=0, wide=true)
  t.host_says_finger(Some(false))
  let rows = t.semantics().filter(fn(n) { n.role == @ui.Role::Button && (n.label == "Willow" || n.label == "Maple") && n.check is Some(_) && !n.hidden })
  guard rows.length() == 2 else { fail("expected Willow and Maple rows") }
  let same_box = fn(b : @ui.Laid, r : (Double, Double, Double, Double)) {
    (b.x - r.0).abs() < 0.5 && (b.y - r.1).abs() < 0.5 && (b.w - r.2).abs() < 0.5 && (b.h - r.3).abs() < 0.5 && b.bg != 0L
  }
  let (wx, wy, ww, wh) = rows[0].rect
  let (mx, my, mw, mh) = rows[1].rect
  // Pointer on the bottom row (Maple): its hover ground is concentric with the small panel's corners.
  t.move_to(mx + mw / 2.0, my + mh / 2.0)
  t.draw()
  assert_eq(t.corner_faults(), [])
  let lit_maple = t.boxes_held().filter(fn(b) { same_box(b, (mx, my, mw, mh)) })
  assert_true(lit_maple.length() == 1 && (lit_maple[0].radius - @sf.row_corner).abs() < 0.5, msg="\{lit_maple.length()} maple lit")
  // Pointer moved onto the CPU meter chip inside Willow: Willow's own hover ground stays lit across the whole row.
  guard t.words().iter().find_first(fn(w) { w.0 == "CPU" && w.5 > 0.0 && w.2 >= wy && w.2 + w.4 <= wy + wh }) is Some((_, cx, cy, cw, ch, _)) else {
    fail("no CPU chip in Willow")
  }
  t.move_to(cx + cw / 2.0, cy + ch / 2.0)
  t.draw()
  assert_eq(t.corner_faults(), [])
  let lit_willow = t.boxes_held().filter(fn(b) { same_box(b, (wx, wy, ww, wh)) })
  assert_true(lit_willow.length() == 1 && (lit_willow[0].radius - @sf.row_corner).abs() < 0.5, msg="\{lit_willow.length()} willow lit")
}
