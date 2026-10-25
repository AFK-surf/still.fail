// The layout by the screen alone (@sf.layout), and laid out Medium the wide frame's tape (sfdesk's frame.mbt): the
// rail and the sidebar beside the page, the one in use whole, what shows of the other untinted; a press there brings it
// over and goes to nothing it holds, a drag across there brings it with the finger.

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
test "the layout by the window's width alone, on every screen: what a phone's or a tablet's system says of it not read" {
  // (platform, the window, the size classes its host says ("": none), the layout)
  for p in [
    (0, 500.0, 800.0, "", "", @sf.Layout::Small),
    (0, 720.0, 800.0, "", "", Medium),
    (0, 1024.0, 768.0, "", "", Large),
    (3, 720.0, 800.0, "", "", Medium),
    // a phone upright; an opened fold's inner screen upright; a tablet
    (2, 390.0, 844.0, "compact", "medium", Small),
    (2, 690.0, 840.0, "medium", "medium", Medium),
    (2, 1024.0, 768.0, "expanded", "medium", Large),
    // an iPhone upright; an iPad upright (820 wide: its system says regular), a large one upright
    (1, 390.0, 844.0, "compact", "regular", Small),
    (1, 820.0, 1180.0, "regular", "regular", Medium),
    (1, 1024.0, 1366.0, "regular", "regular", Large),
  ] {
    let (platform, w, h, width, height, layout) = p
    let t = tape_chat(platform, w, h, width~, height~)
    let said = "platform \{platform} \{w}x\{h} \{width} \{height}"
    assert_eq(@sf.layout(w), layout, msg=said)
    assert_eq(@sfdesk.is_wide(t.ctx()), layout != Small, msg=said)
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
test "on the tape the sidebar at first, the page showing beside it: a click there brings it over, nothing under it pressed" {
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
test "on the tape a finger dragging across the one in use moves no tape: the tape stays where it is" {
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
  assert_false(@sfdesk.is_wide(t.ctx()))
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
  assert_false(@sfdesk.is_wide(t.ctx()))
  assert_true(app.nav.top() is DrivePlay(_))
  assert_true(said_at(t, "全屏") is Some(_))
}

///|
/// How far apart a slow drag's moves come (ms): 10 px each, 200 px/s, well short of a fling.
let slow_drag_ms : Double = 50.0

///|
/// A finger down at (`x`, `y`) dragged across by `by`, 10 at a time, slow_drag_ms apart (no fling); `up`: let go at
/// the end.
fn drag_slowly(t : @ui.Tester, x : Double, y : Double, by : Double, up? : Bool = true) -> Unit {
  t.press_at(x, y)
  let steps = (by.abs() / 10.0).ceil().to_int()
  let step = by / steps.to_double()
  for i in 1..=steps {
    t.run_for(slow_drag_ms)
    t.move(x + step * i.to_double(), y)
  }
  if up {
    t.release(x + by, y)
  }
}

///|
test "on the tape what shows of the page dragged across comes with the finger; let go past a third of the way, it comes over" {
  let t = tape_chat(2, 690.0, 840.0, width="medium", height="medium")
  let words = "做完了：列表、跳到最新的按钮"
  let (side_x, _) = t.find(words).unwrap()
  // where the chat's message is with the page in use, and back to the sidebar
  page_over(t, 690.0)
  let (page_x, _) = t.find(words).unwrap()
  t.back()
  t.run_for(@sfdesk.side_move_ms)
  assert_eq(@sfdesk.wide.tape_at, @sfdesk.TapePane::Side)
  assert_eq(t.find(words).unwrap().0, side_x)
  // half the way across, held: the page with the finger, between where it rests either way, the sidebar still in use
  let way = side_x - page_x
  drag_slowly(t, 650.0, 400.0, -way / 2.0, up=false)
  let (held_x, _) = t.find(words).unwrap()
  assert_true(held_x < side_x - way / 4.0 && held_x > page_x, msg="held at \{held_x}: \{page_x}..\{side_x}")
  assert_eq(@sfdesk.wide.tape_at, @sfdesk.TapePane::Side)
  // let go: the page comes over, nothing in it pressed
  t.release(650.0 - way / 2.0, 400.0)
  assert_eq(@sfdesk.wide.tape_at, @sfdesk.TapePane::Page)
  t.run_for(@sfdesk.side_move_ms)
  assert_eq(t.find(words).unwrap().0, page_x)
  assert_true(on_first_chat())
}

///|
test "on the tape what shows of the page dragged a little and let go: the tape back where it was, the sidebar in use" {
  let t = tape_chat(2, 690.0, 840.0, width="medium", height="medium")
  let words = "做完了：列表、跳到最新的按钮"
  let (side_x, _) = t.find(words).unwrap()
  drag_slowly(t, 650.0, 400.0, -40.0)
  assert_eq(@sfdesk.wide.tape_at, @sfdesk.TapePane::Side)
  t.run_for(@sfdesk.side_move_ms)
  assert_eq(t.find(words).unwrap().0, side_x)
  // the page in use: what shows of the sidebar dragged right past a third of the way brings it over
  page_over(t, 690.0)
  let (page_x, _) = t.find(words).unwrap()
  drag_slowly(t, 40.0, 400.0, (side_x - page_x) * 0.6)
  assert_eq(@sfdesk.wide.tape_at, @sfdesk.TapePane::Side)
}

///|
/// Where the composer's field is drawn from the left and the bottom of the panel it is in (as drawn: a panel's move
/// and any of the field's own); None when it is drawn out of every panel.
fn composer_in_panel(t : @ui.Tester) -> (Double, Double)? {
  let bs = t.boxes()
  guard bs.search_by(fn(b) { b.kind == "editor" }) is Some(e) else { return None }
  let ed = bs[e]
  for b in bs {
    if b.radius == @sf.pane_corner && b.x <= ed.x && ed.x + ed.w <= b.x + b.w {
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

///|
/// The composer's box as drawn (the glass round its field) and its send button (the last grounded round control in
/// it, the theme's): their corners.
fn composer_corners(t : @ui.Tester) -> (Double, Double, Double)? {
  let bs = t.boxes()
  guard bs.search_by(fn(b) { b.kind == "editor" }) is Some(e) else { return None }
  let ed = bs[e]
  let mut box : @ui.Laid? = None
  for b in bs {
    if b.glass && b.x <= ed.x && ed.x + ed.w <= b.x + b.w && b.y <= ed.y && ed.y + ed.h <= b.y + b.h {
      box = Some(b)
    }
  }
  guard box is Some(k) else { return None }
  let side = @sf.theme().round.side
  let mut send = 0.0
  for b in bs {
    if b.w == side && b.h == side && b.bg != 0L && b.x >= k.x && b.x + b.w <= k.x + k.w && b.y >= k.y &&
      b.y + b.h <= k.y + k.h {
      send = dmin(b.radius, side / 2.0)
    }
  }
  Some((dmin(k.radius, k.h / 2.0), send, k.h))
}

///|
test "on the tape the page panel's corner is its own: the composer and its buttons in its corners follow it, one line or more" {
  let t = tape_chat(2, 690.0, 840.0, width="medium", height="medium")
  t.tap(650.0, 400.0)
  t.run_for(@sfdesk.side_move_ms * 2.0)
  // (a square window: the panels' corners all the ladder's)
  assert_eq(@sf.tape_edge.radius(), @sf.pane_corner)
  let panel = @sf.pane_corner
  // one line: a capsule (its half: a pill in the panel's corner keeps its own, as round as the panel's less the inset
  // where its buttons are a computer's 32), its buttons round in its ends; the screen's buttons (a touch screen's
  // larger), the same shape
  let side = @sf.theme().round.side
  guard composer_corners(t) is Some((k, s, h)) else { fail("no composer") }
  assert_eq(k, h / 2.0)
  assert_eq(s, side / 2.0)
  assert_eq(t.corner_faults(), [])
  // lines more: the box concentric with the panel, the send button with the box, 12 in
  t.tap_text("发消息")
  t.type_text("第一行\n第二行\n第三行")
  t.run_for(@sfpages.morph_ms)
  guard composer_corners(t) is Some((k, s, _)) else { fail("no composer") }
  // (the ladder's: the panel's corner a step in, a card's; its buttons round in its corners, the inset in)
  assert_eq(k, @ui.concentric(panel, @sfpages.composer_side()))
  assert_eq(k, @sf.card_corner)
  assert_eq(s, side / 2.0)
  assert_eq(t.corner_faults(), [])
}

///|
/// The panel of the tape the composer's field is in (the smallest box round it as round as a pane), and the
/// composer's box (the glass round the field): as laid out.
fn composer_and_panel(t : @ui.Tester) -> (@ui.Laid, @ui.Laid)? {
  let bs = t.boxes()
  guard bs.search_by(fn(b) { b.kind == "editor" }) is Some(e) else { return None }
  let ed = bs[e]
  let round = fn(b : @ui.Laid) { b.x <= ed.x && ed.x + ed.w <= b.x + b.w && b.y <= ed.y && ed.y + ed.h <= b.y + b.h }
  let mut panel : @ui.Laid? = None
  let mut box : @ui.Laid? = None
  for b in bs {
    if round(b) && b.radius == @sf.pane_corner {
      panel = Some(b)
    }
    if round(b) && b.glass {
      box = Some(b)
    }
  }
  match (box, panel) {
    (Some(k), Some(p)) => Some((k, p))
    _ => None
  }
}

///|
test "on a Mac's tape each panel's corners follow the window's where it stands at its edge, the others the ladder's" {
  reset()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=690.0, h=840.0, platform=0, window_corner=16.0)
  t.run_for(@ui.nav_push_ms)
  // the window's 16, 6 in: 11.2
  let edge = @ui.concentric(16.0, 6.0)
  assert_eq(@sf.tape_edge.radius(), edge)
  let pane = @sf.pane_corner
  // the sidebar in use: its left corners at the window's, the page's right ones past its right edge as they will be
  // there
  guard composer_and_panel(t) is Some((_, page)) else { fail("no composer in a panel") }
  assert_true(near4(page.radii, (pane, edge, edge, pane)), msg="the page's panel: \{page.radii}")
  assert_true(
    t.boxes().iter().any(fn(b) { near4(b.radii, (edge, pane, pane, edge)) && b.x < 10.0 }),
    msg="no sidebar's panel with its left corners the window's",
  )
  assert_eq(t.corner_faults(), [])
  // the page brought over, its composer taking the cursor (a computer's): a box, where both its foot corners follow
  // the panel's (6.5 in), its foot's concentric with each, its top's its own
  t.tap(650.0, 400.0)
  t.run_for(@sfdesk.side_move_ms * 2.0)
  guard composer_and_panel(t) is Some((k, p)) else { fail("no composer in a panel") }
  let d = @sf.foot_fit(pane, edge, @sf.corner_inset)
  assert_true((d - 6.5).abs() < 0.01, msg="the box's place: \{d}")
  let at = (k.x - p.x, p.x + p.w - (k.x + k.w), p.y + p.h - (k.y + k.h))
  assert_true(near4((at.0, at.1, at.2, 0.0), (d, d, d, 0.0)), msg="the box from the panel's edges: \{at}")
  assert_true(
    near4(k.radii, (@sf.card_corner, @sf.card_corner, @ui.concentric(edge, d), @ui.concentric(pane, d))),
    msg="the box's corners: \{k.radii}",
  )
  assert_eq(t.corner_faults(), [])
  // let go of: a capsule, its left end concentric with the panel's 34 (10 in), its right in the window's 11.2, too
  // square for it, the ladder's 10 in as alone; the box's place to the capsule's in the one change of shape
  t.ctx().blur()
  // (let go of from the next frame on; its change of shape over by twice its length after that)
  t.run_for(@sfpages.let_go_ms + 2.0 * @sfpages.morph_ms)
  guard composer_and_panel(t) is Some((k, p)) else { fail("no composer in a panel") }
  let ten = @sf.corner_inset
  let at = (k.x - p.x, p.x + p.w - (k.x + k.w), p.y + p.h - (k.y + k.h))
  assert_true(near4((at.0, at.1, at.2, 0.0), (ten, ten, ten, 0.0)), msg="the capsule from the panel's edges: \{at}")
  assert_eq(t.corner_faults(), [])
}

///|
/// Whether four numbers are each within a hundredth of the other four's.
fn near4(a : (Double, Double, Double, Double), b : (Double, Double, Double, Double)) -> Bool {
  (a.0 - b.0).abs() < 0.01 && (a.1 - b.1).abs() < 0.01 && (a.2 - b.2).abs() < 0.01 && (a.3 - b.3).abs() < 0.01
}

///|
/// The page's panel on the tape (the rightmost box as round as a pane, as wide as a page), and where the topmost words
/// `words` in it stand from its left and top, and how big they are.
fn words_in_page(t : @ui.Tester, words : String) -> (Double, Double, Double)? {
  let bs = t.boxes()
  let mut page : @ui.Laid? = None
  for b in bs {
    if b.radius >= 11.0 && b.w >= 300.0 && b.h >= 300.0 && (page is None || b.x > page.unwrap().x) {
      page = Some(b)
    }
  }
  guard page is Some(p) else { return None }
  let mut found : (Double, Double, Double)? = None
  for b in bs {
    if (b.kind == "text" || b.kind == "rich") &&
      b.text == words &&
      b.x >= p.x &&
      b.x < p.x + p.w &&
      b.y >= p.y &&
      b.y < p.y + p.h &&
      (found is None || b.y - p.y < found.unwrap().1) {
      found = Some((b.x - p.x, b.y - p.y, b.font_size))
    }
  }
  found
}

///|
/// The middle of the first words `words` drawn, across (their line's).
fn words_middle(t : @ui.Tester, words : String) -> Double? {
  for b in t.boxes() {
    if (b.kind == "text" || b.kind == "rich") && b.text == words {
      return Some(b.y + b.h / 2.0)
    }
  }
  None
}

///|
test "on the tape a page's head is a chat's bar: its title where a chat's stands, the sidebar's first row on its line" {
  // a finger's Medium (the panels' corners the ladder's 34) and a Mac's (those at the window's edge its 16's less 6)
  for win in [("touch", 600.0, 900.0, 2, "medium"), ("desk", 600.0, 760.0, 0, "")] {
    let chat = screen_in("chat", win, "zh")
    guard words_in_page(chat, "整理发布清单") is Some((cx, cy, cs)) else { fail("\{win.0}: no chat's title") }
    // the sidebar's first row and the page's bar on the tape's one line (@sf.tape_bar_over)
    match (words_middle(chat, "新建对话"), words_middle(chat, "整理发布清单")) {
      (Some(a), Some(b)) => assert_true((a - b).abs() < 1.0, msg="\{win.0}: 新建对话's line \{a}, the chat's title's \{b}")
      _ => fail("\{win.0}: no 新建对话 or chat's title")
    }
    for page in [
      ("settings-appearance", "外观"),
      ("settings-changelog", "更新日志"),
      // (a head of its own its name: the bar says what it is of)
      ("settings-station", "Station"),
      ("settings-profile", "Profile"),
    ] {
      let t = screen_in(page.0, win, "zh")
      guard words_in_page(t, page.1) is Some((x, y, size)) else { fail("\{win.0} \{page.0}: no title") }
      assert_true(
        (x - cx).abs() < 0.5 && (y - cy).abs() < 0.5 && size == cs,
        msg="\{win.0} \{page.0}: its title at \{x}, \{y}, \{size}; a chat's at \{cx}, \{cy}, \{cs}",
      )
      assert_eq(t.corner_faults(), [])
    }
  }
}

///|
test "on the tape 新建对话 in the sidebar brings its page over, as ⌘N does" {
  // an opened fold's inner screen upright, a finger
  let t = tape_chat(2, 690.0, 840.0, width="medium", height="medium")
  assert_eq(@sfdesk.wide.tape_at, @sfdesk.TapePane::Side)
  t.tap_text("新建对话")
  assert_true(app.nav.top() is NewChat)
  t.run_for(@sfdesk.side_move_ms)
  assert_eq(@sfdesk.wide.tape_at, @sfdesk.TapePane::Page)
  // back: the sidebar again
  t.back()
  t.run_for(@sfdesk.side_move_ms)
  assert_eq(@sfdesk.wide.tape_at, @sfdesk.TapePane::Side)
  @sfdesk.new_chat()
  t.run_for(@sfdesk.side_move_ms)
  assert_eq(@sfdesk.wide.tape_at, @sfdesk.TapePane::Page)
}

///|
test "on the tape a finger's search at the lists' top: tucked under the band at first, pulled down whole under it" {
  // an opened fold's inner screen upright, its system bars over it
  let t = tape_chat(2, 750.0, 830.0, width="medium", height="medium")
  t.post(@hostapi.system_channel, "{\"bars\":{\"top\":36,\"bottom\":24,\"left\":0,\"right\":0}}")
  t.run_for(@sfdesk.side_move_ms)
  // the band's foot: 新建对话's row and the 2 under it
  let band_foot = fn() {
    let (_, y, _, h) = said_at(t, "新建对话").unwrap()
    y + h + 2.0
  }
  let (_, y, _, h) = said_at(t, "搜索全部内容").unwrap()
  assert_true(y + h <= band_foot(), msg="the search at \{y}..\{y + h}, the band to \{band_foot()}")
  let (rx, ry) = t.find("首页的列表改成按天分组").unwrap()
  t.drag(rx, ry, rx, ry + 400.0)
  t.run_for(t.rest_of("a list") - t.time())
  let (_, y, _, _) = said_at(t, "搜索全部内容").unwrap()
  assert_true(y >= band_foot(), msg="the search from \{y}, the band to \{band_foot()}")
}

///|
test "on the tape a passage held in the page beside the sidebar brings the page over, and its 引用 quotes it" {
  let t = tape_chat(2, 750.0, 830.0, width="medium", height="medium")
  assert_eq(@sfdesk.wide.tape_at, @sfdesk.TapePane::Side)
  hold_on(t, "做完了：列表、跳到最新的按钮") |> ignore
  t.draw()
  assert_true(pk.ts != "")
  assert_eq(@sfdesk.wide.tape_at, @sfdesk.TapePane::Page)
  t.run_for(@sfdesk.side_move_ms)
  // still picked, its bar over it where the page is now
  assert_true(pk.ts != "")
  t.tap_text("引用")
  t.draw()
  assert_true(pk.ts == "")
  assert_true(t.find("添加说明（可选）") is Some(_))
  assert_eq(@sfdesk.wide.tape_at, @sfdesk.TapePane::Page)
}

///|
/// The grounds drawn under point (x, y), as drawn rects, top first.
fn grounds_at(t : @ui.Tester, x : Double, y : Double) -> Array[Int64] {
  t.drawn_rects().filter(fn(r) { x >= r.0 && x < r.0 + r.2 && y >= r.1 && y < r.1 + r.3 }).map(fn(r) { r.4 }).rev()
}

///|
test "on the tape the panels behind the one in use stand on a ground a step darker, their words as they are" {
  for dark in [false, true] {
    let t = tape_chat(2, 750.0, 830.0, width="medium", height="medium")
    t.set_dark(dark)
    t.draw()
    let behind = @sf.behind_ground()
    let bg = @sf.theme().p.bg
    assert_true(behind != bg)
    // the sidebar in use: the page behind, on the darker ground, its words drawn as before
    let (mx, my) = t.find("做完了：列表、跳到最新的按钮").unwrap()
    assert_true(grounds_at(t, mx - 4.0, my).contains(behind), msg="dark \{dark}: the page's grounds \{grounds_at(t, mx - 4.0, my)}")
    let (rx, ry) = t.find("首页的列表改成按天分组").unwrap()
    assert_false(grounds_at(t, rx, ry).contains(behind), msg="dark \{dark}: the sidebar's grounds")
    // the page brought over: the sidebar behind now, the page on its own ground
    page_over(t, 750.0)
    let (mx, my) = t.find("做完了：列表、跳到最新的按钮").unwrap()
    assert_false(grounds_at(t, mx - 4.0, my).contains(behind), msg="dark \{dark}: the page in use")
    let (rx, ry) = t.find("首页的列表改成按天分组").unwrap()
    assert_true(grounds_at(t, rx, ry).contains(behind), msg="dark \{dark}: the sidebar behind")
  }
}

///|
test "on the tape a panel's ground goes behind or comes in front with the tape's move, not at once" {
  let t = tape_chat(2, 750.0, 830.0, width="medium", height="medium")
  let behind = @sf.behind_ground()
  let bg = @sf.theme().p.bg
  let (mx, my) = t.find("做完了：列表、跳到最新的按钮").unwrap()
  assert_true(grounds_at(t, mx - 4.0, my).contains(behind))
  // what shows of the page pressed: half way over, its ground half way back to the page's
  t.tap(750.0 - 40.0, 400.0)
  t.run_for(@sfdesk.side_move_ms / 2.0)
  let (mx, my) = t.find("做完了：列表、跳到最新的按钮").unwrap()
  // (the ground on top there: the page's panel's, its message's own drawn on it clear)
  let half = grounds_at(t, mx - 4.0, my).filter(fn(g) { g != 0L })[0]
  assert_true(half != behind && half != bg, msg="\{half}")
  t.run_for(@sfdesk.side_move_ms)
  let (mx, my) = t.find("做完了：列表、跳到最新的按钮").unwrap()
  assert_false(grounds_at(t, mx - 4.0, my).contains(behind))
}

///|
test "on the tape the sidebar's rows stand 16 in from its left, as from its right; a phone's 22 from the screen's edge" {
  let t = tape_chat(2, 750.0, 830.0, width="medium", height="medium")
  // the sidebar's panel 6 from the window's edge, its list from 8 into the rail inside its line (1): a row's words
  // without a mark before them 16 in from there
  let (x, _, _, _) = t.rect_of("Slack 里问的报销流程").unwrap()
  assert_eq(x, @sfdesk.closed_bar_in + @sfdesk.rail_w - 8.0 + 1.0 + 16.0)
  let p = tape_chat(2, 390.0, 844.0, width="compact", height="medium")
  p.run_for(@ui.nav_push_ms)
  p.back()
  p.run_for(@ui.nav_push_ms)
  let (x, _, _, _) = p.rect_of("Slack 里问的报销流程").unwrap()
  assert_eq(x, 22.0)
}

///|
test "on the tape 新建对话 is in line with the chats' rows under it: its icon over their marks, its words where their titles start" {
  let t = tape_chat(2, 750.0, 830.0, width="medium", height="medium")
  let (wx, _, _, _) = t.rect_of("新建对话").unwrap()
  let (tx, _, _, _) = t.rect_of("首页的列表改成按天分组").unwrap()
  assert_eq(wx, tx)
  // the icon's middle and the row's mark's (its status dot, 10 across) within a point
  let marks = t.boxes().filter(fn(b) { b.label == "工作中" && b.w == 10.0 })
  let icons = t.boxes().filter(fn(b) { b.w == 16.0 && b.h == 16.0 && b.y < 100.0 && b.x > 60.0 && b.x < 90.0 })
  assert_true(marks.length() > 0 && icons.length() > 0, msg="marks \{marks.length()}, icons \{icons.length()}")
  let mc = marks[0].x + marks[0].w / 2.0
  let ic = icons[0].x + icons[0].w / 2.0
  assert_true((mc - ic).abs() <= 1.0, msg="mark's middle \{mc}, icon's \{ic}")
}
