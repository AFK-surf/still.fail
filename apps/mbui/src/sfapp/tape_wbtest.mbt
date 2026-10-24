// The layout by the screen alone (@sf.layout), and laid out Medium the wide frame's tape (sfdesk's frame.mbt): the
// rail and the sidebar beside the page, the one in use whole, what shows of the other veiled; a press there brings it
// over and goes to nothing it holds.

///|
/// Where the widget said as `label` is (x, y, w, h).
fn said_at(t : @ui.Tester, label : String) -> (Double, Double, Double, Double)? {
  for s in t.semantics() {
    if s.label == label && !s.hidden {
      return Some(s.rect)
    }
  }
  None
}

///|
/// The window's size classes as a phone's or a tablet's host says them (@hostapi.system_channel `size_class`): taken at
/// the next frame.
fn say_room(t : @ui.Tester, width : String, height : String) -> Unit {
  t.post(@hostapi.system_channel, "{\"size_class\":{\"width\":\"\{width}\",\"height\":\"\{height}\"}}")
}

///|
/// The widget said as `label` tapped in its middle.
fn tap_said(t : @ui.Tester, label : String) -> Unit raise {
  match said_at(t, label) {
    Some((x, y, w, h)) => t.tap(x + w / 2.0, y + h / 2.0)
    None => fail("nothing said \{label}")
  }
}

///|
/// Whether the bottom bar's places are on the screen.
fn bar_tabs(t : @ui.Tester) -> Bool {
  t.semantics().iter().any(fn(s) { s.role == @ui.Role::Tab && !s.hidden })
}

///|
/// The fixture's chat open in a window `w` × `h` of `platform`, its size classes said as its host says them (`width`
/// "": none, a desktop's).
fn tape_chat(platform : Int, w : Double, h : Double, width? : String = "", height? : String = "") -> @ui.Tester {
  reset()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w~, h~, platform~)
  if width != "" {
    say_room(t, width, height)
  }
  t.run_for(@ui.nav_push_ms)
  t
}

///|
/// The chat open is the fixture's first.
fn on_first_chat() -> Bool {
  app.nav.top() is Chat({ session: "s-c1", .. })
}

///|
test "the layout by the screen alone: a desktop's by its width, a phone's or a tablet's by its size classes" {
  // (platform, the window, the size classes its host says ("": none), the layout)
  for p in [
    (0, 500.0, 800.0, "", "", @sf.Layout::Small),
    (0, 720.0, 800.0, "", "", Medium),
    (0, 1024.0, 768.0, "", "", Large),
    (3, 720.0, 800.0, "", "", Medium),
    // a phone upright, on its side; an opened fold's inner screen upright; a tablet
    (2, 390.0, 844.0, "compact", "medium", Small),
    (2, 844.0, 390.0, "expanded", "compact", Medium),
    (2, 690.0, 840.0, "medium", "medium", Medium),
    (2, 1024.0, 768.0, "expanded", "medium", Large),
    // an iPhone upright, a large one on its side, an iPad
    (1, 390.0, 844.0, "compact", "regular", Small),
    (1, 932.0, 430.0, "regular", "compact", Medium),
    (1, 1024.0, 768.0, "regular", "regular", Large),
  ] {
    let (platform, w, h, width, height, layout) = p
    let t = tape_chat(platform, w, h, width~, height~)
    let said = "platform \{platform} \{w}x\{h} \{width} \{height}"
    assert_eq(@sf.layout(w), layout, msg=said)
    assert_eq(wide_on.val, layout != Small, msg=said)
    assert_eq(@sfdesk.wide.tape, layout == Medium, msg=said)
    ignore(t)
  }
}

///|
/// What shows of the page beside the sidebar in use pressed (the window `w` wide): the page comes over.
fn page_over(t : @ui.Tester, w : Double) -> Unit {
  t.tap(w - 40.0, 400.0)
  t.run_for(@sfdesk.side_move_ms)
}

///|
test "on the tape the sidebar at first, the page beside it veiled: a click there brings it over, nothing under it pressed" {
  let t = tape_chat(0, 720.0, 800.0)
  assert_true(@sfdesk.wide.tape)
  assert_eq(@sfdesk.wide.tape_at, @sfdesk.TapePane::Side)
  // the sidebar whole: another chat's row within it
  let (rx, _) = t.find("首页的列表改成按天分组").unwrap()
  assert_true(rx > @sfdesk.rail_w && rx < @sfdesk.rail_w + 240.0, msg="the row's words at \{rx}")
  // what shows of the page clicked: it comes over, what was under the click not pressed
  let (mx, my) = t.find("做完了：列表、跳到最新的按钮").unwrap()
  assert_true(mx > @sfdesk.rail_w + 240.0, msg="the chat's message at \{mx}")
  t.tap(mx, my)
  assert_eq(@sfdesk.wide.tape_at, @sfdesk.TapePane::Page)
  assert_true(on_first_chat())
  t.run_for(@sfdesk.side_move_ms)
  // the page from what shows of the sidebar (a fifth of the window), the row mostly past the window's left edge
  let peek = 144.0
  let (mx, _) = t.find("做完了：列表、跳到最新的按钮").unwrap()
  assert_true(mx > peek, msg="the chat's message at \{mx}")
  let (rx, ry) = t.find("首页的列表改成按天分组").unwrap()
  assert_true(rx < peek, msg="the row's words at \{rx}")
  // clicked where the row shows: the sidebar comes over, the row's chat not opened
  t.tap(peek / 2.0, ry)
  assert_eq(@sfdesk.wide.tape_at, @sfdesk.TapePane::Side)
  assert_true(on_first_chat())
}

///|
test "on the tape nothing puts the sidebar away by itself: a chat chosen in it shows in the page, ⌘\\ and its place do nothing" {
  let t = tape_chat(0, 720.0, 800.0)
  t.tap_text("首页的列表改成按天分组")
  t.run_for(@sfdesk.side_move_ms)
  match app.nav.top() {
    Chat(r) => assert_eq(r.title, "首页的列表改成按天分组")
    _ => fail("no chat open")
  }
  assert_eq(@sfdesk.wide.tape_at, @sfdesk.TapePane::Side)
  // the sidebar's toggle (⌘\, its place pressed again, ⌘K's command): nothing folds, nothing comes over
  @sfdesk.sidebar_toggle()
  t.run_for(@sfdesk.side_move_ms)
  assert_eq(@sfdesk.wide.tape_at, @sfdesk.TapePane::Side)
  assert_false(@sfdesk.side_folded())
  // with the page in use, the same
  page_over(t, 720.0)
  assert_eq(@sfdesk.wide.tape_at, @sfdesk.TapePane::Page)
  @sfdesk.sidebar_toggle()
  t.run_for(@sfdesk.side_move_ms)
  assert_eq(@sfdesk.wide.tape_at, @sfdesk.TapePane::Page)
}

///|
test "on the tape a chat's side panel is a panel of its own after the page's: opened it comes over, back the page" {
  let t = tape_chat(0, 720.0, 800.0)
  page_over(t, 720.0)
  tap_said(t, "打开侧栏")
  t.run_for(@sfdesk.side_move_ms)
  assert_eq(@sfdesk.wide.tape_at, @sfdesk.TapePane::Panel)
  // the panel whole at the window's right, the page's edge showing at its left
  match said_at(t, "收起侧栏") {
    Some((x, _, w, _)) => assert_true(x + w <= 720.0 && x + w > 600.0, msg="its switch at \{x} \{w}")
    None => fail("no panel: \{t.drawn_text()}")
  }
  // back: the page comes over, the panel's edge showing at its right
  t.back()
  t.run_for(@sfdesk.side_move_ms)
  assert_eq(@sfdesk.wide.tape_at, @sfdesk.TapePane::Page)
  // what shows of the panel tapped: it comes over again, nothing in it pressed
  t.tap(650.0, 400.0)
  assert_eq(@sfdesk.wide.tape_at, @sfdesk.TapePane::Panel)
  t.run_for(@sfdesk.side_move_ms)
  // closed with its switch: the page comes over
  tap_said(t, "收起侧栏")
  t.run_for(@sfdesk.side_move_ms)
  assert_eq(@sfdesk.wide.tape_at, @sfdesk.TapePane::Page)
  assert_true(said_at(t, "收起侧栏") is None)
}

///|
test "on the tape back brings the sidebar over from the chat, and with the sidebar in use is the system's" {
  // an opened fold's inner screen upright, a finger
  let t = tape_chat(2, 690.0, 840.0, width="medium", height="medium")
  assert_true(@sfdesk.wide.tape)
  page_over(t, 690.0)
  assert_eq(@sfdesk.wide.tape_at, @sfdesk.TapePane::Page)
  t.back()
  assert_eq(@sfdesk.wide.tape_at, @sfdesk.TapePane::Side)
  assert_true(on_first_chat())
  t.run_for(@sfdesk.side_move_ms)
  t.back()
  assert_eq(@sfdesk.wide.tape_at, @sfdesk.TapePane::Side)
  assert_true(on_first_chat())
}

///|
test "on the tape a finger drags nothing across: the tape stays where it is" {
  let t = tape_chat(2, 690.0, 840.0, width="medium", height="medium")
  page_over(t, 690.0)
  let (mx, my) = t.find("做完了：列表、跳到最新的按钮").unwrap()
  t.drag(mx, my, mx + 300.0, my)
  t.run_for(@sfdesk.side_move_ms)
  assert_eq(@sfdesk.wide.tape_at, @sfdesk.TapePane::Page)
  let (again, _) = t.find("做完了：列表、跳到最新的按钮").unwrap()
  assert_eq(again, mx)
}

///|
test "a phone turned sideways for a film: the layout it had (the player the whole screen, no rail nor list beside it)" {
  reset()
  let src = fixture("player-video")
  open_drive_fixture("player-video")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  nav_rested(t)
  tap_said(t, "全屏")
  // the host turns the phone for it (Host.setSideways: landscape), its window's classes said as they change
  say_room(t, "expanded", "compact")
  t.resize(844.0, 390.0)
  // the app turned it, not another screen: the phone's pages under the player as before
  assert_true(@sf.layout(844.0) is Small)
  assert_false(wide_on.val)
  assert_true(app.nav.top() is DrivePlay(_))
  // its back key at the screen's own left edge, not beside a rail and a list
  match said_at(t, "返回") {
    Some((bx, _, _, _)) => assert_true(bx < @sfdesk.rail_w, msg="the player's back at \{bx}")
    None => fail("no 返回: \{t.drawn_text()}")
  }
  assert_true(said_at(t, "退出全屏") is Some(_))
  // back turns it upright first (Player.kt BackHandler(sideways)), the host turning the phone back
  t.back()
  say_room(t, "compact", "medium")
  t.resize(390.0, 844.0)
  assert_false(wide_on.val)
  assert_true(app.nav.top() is DrivePlay(_))
  assert_true(said_at(t, "全屏") is Some(_))
}

///|
/// Where the composer's field is drawn from the left and the bottom of the panel it is in (as drawn: a panel's move
/// and any of the field's own); None when it is drawn out of every panel.
fn composer_in_panel(t : @ui.Tester) -> (Double, Double)? {
  let bs = t.boxes()
  guard bs.search_by(fn(b) { b.kind == "editor" }) is Some(e) else { return None }
  let ed = bs[e]
  for b in bs {
    if @ui.Radius::Exact(b.radius) == @sf.page_panel_corner && b.x <= ed.x && ed.x + ed.w <= b.x + b.w {
      return Some((ed.x - b.x, b.y + b.h - ed.y))
    }
  }
  None
}

///|
test "on the tape the composer is drawn with its page as the page moves, never after it" {
  let t = tape_chat(2, 690.0, 840.0, width="medium", height="medium")
  guard composer_in_panel(t) is Some((x0, y0)) else { fail("the composer is out of its panel") }
  let same = fn(at : String) raise {
    guard composer_in_panel(t) is Some((x, y)) else { fail("\{at}: the composer is drawn out of its panel") }
    assert_true((x - x0).abs() < 0.5 && (y - y0).abs() < 0.5, msg="\{at}: \{x},\{y}, at rest \{x0},\{y0}")
  }
  // the page brought over, and back
  t.tap(650.0, 400.0)
  for k in 1..=6 {
    t.run_for(@sfdesk.side_move_ms / 8.0)
    same("bringing the page, step \{k}")
  }
  t.run_for(@sfdesk.side_move_ms)
  same("the page over")
  t.back()
  for k in 1..=6 {
    t.run_for(@sfdesk.side_move_ms / 8.0)
    same("going back, step \{k}")
  }
}
