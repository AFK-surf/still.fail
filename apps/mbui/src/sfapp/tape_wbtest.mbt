// The layout by the screen alone (@sf.layout), and laid out Medium the wide frame's tape (sfdesk's frame.mbt): the
// rail and the sidebar beside the page, the one in use as wide as the window leaves, a strip of each beside it showing
// untinted (tape_shows); a press there brings it over and goes to nothing it holds, a drag across there brings it with
// the finger, as the system's back gesture brings the one before.

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
  new_run()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~)
  if width != "" {
    say_room(t, width, height)
  }
  t.run_for(@ui.move_most_ms)
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
  t.tap(w - @sfdesk.tape_shows / 2.0, 400.0)
  t.run_for(@ui.move_most_ms)
}

///|
/// Whether `a` is `b` as laid out (within a billionth: worked out through a capsule's place, smooth.mbt round_like).
fn near_at(a : Double?, b : Double) -> Bool {
  match a {
    Some(x) => (x - b).abs() < 1.0e-9
    None => false
  }
}

///|
/// Where the panel not in use said as `label` is drawn (its cover, the widest said so: tape_covers), from its left to
/// its right edge.
fn covered(t : @ui.Tester, label : String) -> (Double, Double)? {
  let mut found : (Double, Double)? = None
  for s in t.semantics() {
    let (x, _, w, _) = s.rect
    if s.label == label && !s.hidden && (found is None || w > found.unwrap().1 - found.unwrap().0) {
      found = Some((x, x + w))
    }
  }
  found
}

///|
test "on the tape with the window's buttons in the app's top row (a Mac's) what shows at the window's left holds them, as much room past them as before them from the window's edge; the strip at the right as before" {
  // (the host's buttons: 16 from the window's left, 54 across: mbui's mac_app.m)
  let (buttons_in, buttons_w) = (16.0, 54.0)
  for w in [600.0, 720.0, 839.0] {
    let at = "\{w}"
    let t = tape_chat(0, w, 840.0)
    t.set_window_inset(true)
    t.run_for(@ui.move_most_ms)
    let left = @sfdesk.tape_shows_left()
    assert_eq(left - (buttons_in + buttons_w), buttons_in, msg=at)
    // the page in use: the sidebar's strip at the left holds them, the page past it
    page_over(t, w)
    assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page, msg=at)
    assert_true(near_at(covered(t, "展开侧边栏").map(fn(e) { e.1 }), left), msg=at)
    // its side panel in use: the page's strip at the left holds them; at the right as before
    tap_said(t, "打开侧栏")
    // (the pointer gone: no tip shown under it as the panel comes, which back would close first)
    t.leave()
    t.run_for(@ui.move_most_ms)
    assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Panel, msg=at)
    assert_true(near_at(covered(t, "收起侧边栏").map(fn(e) { e.1 }), left), msg=at)
    t.back()
    t.run_for(@ui.move_most_ms)
    assert_true(near_at(covered(t, "打开侧栏").map(fn(e) { e.0 }), w - @sfdesk.tape_shows), msg=at)
  }
}

///|
test "on the tape the page or the side panel in use has the window but a strip of each beside it; the sidebar its own width" {
  let shows = @sfdesk.tape_shows
  let (inside, apart) = (@sfdesk.closed_bar_in, 8.0)
  // an opened fold's inner screen upright, the least and the most of Medium; a computer's window
  for win in [(2, 600.0), (2, 690.0), (2, 839.0), (0, 720.0)] {
    let (platform, w) = win
    let at = "platform \{platform} \{w}"
    let room = if platform == 2 { "medium" } else { "" }
    let t = tape_chat(platform, w, 840.0, width=room, height=room)
    // the sidebar in use: its own width (the person's, 240 at first), the page beside it the rest of the window
    assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side, msg=at)
    guard covered(t, "收起侧边栏") is Some((px, _)) else { fail("\{at}: no page beside the sidebar") }
    assert_true(px > @sfdesk.rail_w + 240.0 && px < @sfdesk.rail_w + 240.0 + 4.0 * apart, msg="\{at}: the page from \{px}")
    let (rx, _, rw, _) = t.rect_of("首页的列表改成按天分组").unwrap()
    assert_true(rx > inside && rx + rw < px - apart, msg="\{at}: the row's words at \{rx}, \{rw}")
    // the page in use: the sidebar a strip at the left, the page to 6 from the window's right
    page_over(t, w)
    assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page, msg=at)
    assert_true(near_at(covered(t, "展开侧边栏").map(fn(e) { e.1 }), shows), msg=at)
    // its side panel open: a strip at the right too, the page between the two; the panel in use, the page a strip
    tap_said(t, "打开侧栏")
    // (the pointer gone: no tip shown under it as the panel comes, which back would close first)
    t.leave()
    t.run_for(@ui.move_most_ms)
    assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Panel, msg=at)
    assert_true(near_at(covered(t, "收起侧边栏").map(fn(e) { e.1 }), shows), msg=at)
    t.back()
    t.run_for(@ui.move_most_ms)
    assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page, msg=at)
    assert_true(near_at(covered(t, "展开侧边栏").map(fn(e) { e.1 }), shows), msg=at)
    assert_true(near_at(covered(t, "打开侧栏").map(fn(e) { e.0 }), w - shows), msg=at)
  }
}

///|
test "on the tape the sidebar left wide on a larger screen opens at the tape's most, its width kept; dragged, no wider" {
  let apart = 8.0
  for platform in [2, 0] {
    let room = if platform == 2 { "medium" } else { "" }
    let at = "platform \{platform}"
    let t = tape_chat(platform, 840.0 - 1.0, 840.0, width=room, height=room)
    // the person's width the wide frame's most (dragged so on a larger screen): the page beside the tape's most
    @sfdesk.wide.side_w.set(@sfdesk.side_max)
    t.frame()
    let most = @sfdesk.rail_w + @sfdesk.tape_side_max
    let page_at = fn() raise { said_at(t, "收起侧边栏").unwrap().0 }
    assert_true(page_at() > most && page_at() < most + 4.0 * apart, msg="\{at}: the page from \{page_at()}")
    assert_eq(@sfdesk.wide.side_w.get(), @sfdesk.side_max, msg=at)
    // dragged wider from there: no further than the tape's most; narrower, from where it shows
    let (ex, ey) = edge_middle(t, "调整侧边栏宽度")
    drag_slowly(t, ex, ey, 60.0, hold=true)
    t.frame()
    assert_eq(@sfdesk.wide.side_w.get(), @sfdesk.tape_side_max, msg=at)
    drag_slowly(t, ex, ey, -40.0, hold=true)
    t.frame()
    assert_eq(@sfdesk.wide.side_w.get(), @sfdesk.tape_side_max - 40.0, msg=at)
  }
}

///|
/// The middle of the edge said as `label` (tape_edge: in the gap beside the page and what it takes past it).
fn edge_middle(t : @ui.Tester, label : String) -> (Double, Double) raise {
  guard said_at(t, label) is Some((x, y, w, h)) else { fail("no \{label}") }
  (x + w / 2.0, y + h / 2.0)
}

///|
test "on the tape the edge beside the page, the sidebar's or the side panel's in use, dragged: its width as it goes, the page the rest" {
  for platform in [2, 0] {
    let room = if platform == 2 { "medium" } else { "" }
    let at = "platform \{platform}"
    let t = tape_chat(platform, 720.0, 840.0, width=room, height=room)
    // the sidebar in use, its own 240: held a while first (a finger's hold on an edge is to drag it, no long press:
    // no words of it; a finger drags it only so, @sf.handle_drag), then dragged 60 wider, the page beside it as much further on as it goes; let go, the width kept
    let page_at = fn() raise { said_at(t, "收起侧边栏").unwrap().0 }
    let before = page_at()
    let (ex, ey) = edge_middle(t, "调整侧边栏宽度")
    t.press_at(ex, ey)
    t.run_for(@ui.long_press_ms * 2.0)
    for i in 1..=6 {
      t.move(ex + 10.0 * i.to_double(), ey)
      t.run_for(slow_drag_ms)
    }
    assert_eq(@sfdesk.wide.side_w.get(), 300.0, msg=at)
    assert_true((page_at() - (before + 60.0)).abs() < 1.0e-9, msg=at)
    assert_true(t.find("调整侧边栏宽度") is None, msg=at)
    t.release(ex + 60.0, ey)
    t.frame()
    assert_eq(@sfdesk.wide.side_w.get(), 300.0, msg=at)
    assert_true((page_at() - (before + 60.0)).abs() < 1.0e-9, msg=at)
    assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side, msg=at)
    // the page in use: no edge (the page as wide as the window leaves past the strips)
    page_over(t, 720.0)
    assert_true(said_at(t, "调整侧边栏宽度") is None, msg=at)
    // the side panel in use, as wide as the window leaves past a strip of the page at first: dragged 200 narrower over
    // a second, the page beside it showing as much more as it goes
    tap_said(t, "打开侧栏")
    // (the pointer gone: no tip shown under it as the panel comes, which back would close first)
    t.leave()
    t.run_for(@ui.move_most_ms)
    assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Panel, msg=at)
    let page_end = fn() raise { covered(t, "收起侧边栏").unwrap().1 }
    let shown = page_end()
    let (px, py) = edge_middle(t, "调整侧栏宽度")
    drag_slowly(t, px, py, 200.0, up=false, hold=true)
    assert_true((page_end() - (shown + 200.0)).abs() < 1.0e-9, msg=at)
    t.release(px + 200.0, py)
    t.frame()
    assert_true((page_end() - (shown + 200.0)).abs() < 1.0e-9, msg=at)
    assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Panel, msg=at)
  }
}

///|
test "on the tape a finger swiped across the edge at once, not held first, leaves its width as it was" {
  let t = tape_chat(2, 720.0, 840.0, width="medium", height="medium")
  let (ex, ey) = edge_middle(t, "调整侧边栏宽度")
  drag_slowly(t, ex, ey, 60.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.wide.side_w.get(), 240.0)
  drag_slowly(t, ex, ey, 60.0, hold=true)
  t.frame()
  assert_eq(@sfdesk.wide.side_w.get(), 300.0)
}

///|
test "on the tape the edge beside the page pressed where it lies over the page: the page comes over; in the gap twice, its own width again" {
  for platform in [2, 0] {
    let room = if platform == 2 { "medium" } else { "" }
    let at = "platform \{platform}"
    let t = tape_chat(platform, 720.0, 840.0, width=room, height=room)
    let page_from = fn() raise { covered(t, "收起侧边栏").unwrap().0 }
    let (ex, ey) = edge_middle(t, "调整侧边栏宽度")
    drag_slowly(t, ex, ey, 60.0, hold=true)
    t.frame()
    assert_eq(@sfdesk.wide.side_w.get(), 300.0, msg=at)
    // in the gap before the page: pressed once, nothing; twice, its own width, the sidebar still in use
    let gap = page_from() - 4.0
    t.tap(gap, ey)
    t.frame()
    assert_eq(@sfdesk.wide.side_w.get(), 300.0, msg=at)
    t.tap(gap, ey)
    t.frame()
    assert_eq(@sfdesk.wide.side_w.get(), 240.0, msg=at)
    assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side, msg=at)
    // just past the gap, on what shows of the page (the edge there as well): the page comes over
    t.tap(page_from() + 1.0, ey)
    t.run_for(@ui.move_most_ms)
    assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page, msg=at)
  }
}

///|
test "on the tape the sidebar at first, the page showing beside it: a click there brings it over, nothing under it pressed" {
  let t = tape_chat(0, 720.0, 800.0)
  assert_true(@sfdesk.wide.tape)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  // what shows of the page clicked: it comes over, what was under the click not pressed
  page_over(t, 720.0)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
  assert_true(on_first_chat())
  // the page past what shows of the sidebar, the row past the window's left edge
  let shows = @sfdesk.tape_shows
  let (mx, _, _, _) = t.rect_of("做完了：列表、跳到最新的按钮").unwrap()
  assert_true(mx > shows, msg="the chat's message at \{mx}")
  let (rx, ry) = t.find("首页的列表改成按天分组").unwrap()
  assert_true(rx < shows, msg="the row's words at \{rx}")
  // clicked where the sidebar shows: it comes over, the row's chat not opened
  t.tap(shows / 2.0, ry)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  assert_true(on_first_chat())
}

///|
test "on the tape a chat chosen in the sidebar shows beside it, the sidebar still in use; the page pressed comes over; ⌘\\ puts nothing away" {
  let t = tape_chat(0, 720.0, 800.0)
  t.tap_text("首页的列表改成按天分组")
  match app.nav.top() {
    Chat(r) => assert_eq(r.title, "首页的列表改成按天分组")
    _ => fail("no chat open")
  }
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  // another chosen: shown in its place, the sidebar where it is
  t.tap_text("整理发布清单")
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() is Chat({ session: "s-c1", .. }))
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  // what shows of the page pressed: it comes over
  page_over(t, 720.0)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
  assert_true(app.nav.top() is Chat({ session: "s-c1", .. }))
  // the sidebar's toggle (⌘\, its place pressed again, ⌘K's command): nothing folds, nothing moves
  @sfdesk.sidebar_toggle()
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
  assert_false(@sfdesk.side_folded())
  t.back()
  t.run_for(@ui.move_most_ms)
  @sfdesk.sidebar_toggle()
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  assert_false(@sfdesk.side_folded())
}

///|
/// How late the core gives each topic's first value in the test below (round_trip): within what a page waits for
/// (LOCAL_MS).
let tape_core_late_ms : Double = 50.0

///|
test "on the tape a chat brought over while its view is on its way: the page comes over once it shows it, not sliding with the chat before on it" {
  new_run()
  let src = round_trip(fixture("chat"), tape_core_late_ms)
  let read = fn(session : String) { readings.contains("ws1/st1\u{1}" + session) }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=720.0, h=800.0, platform=0)
  t.draw()
  // the workspace, its list and the chat, their topics one after another
  t.run_for(tape_core_late_ms * 6.0 + @ui.move_most_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  assert_true(read("s-c1"))
  // (where the tape is: the sidebar's first row)
  let (nx, _) = t.find("新建对话").unwrap()
  // opened and brought over (as 新建对话 is) while its view is on its way: the chat before stays on the page, the tape
  // where it is
  open_chat({ station: "ws1/st1", session: "s-c2", title: "首页的列表改成按天分组", station_name: "Studio" })
  @sfdesk.bring_page()
  t.run_for(tape_core_late_ms / 2.0)
  assert_true(app.nav.top() is Chat({ session: "s-c2", .. }), msg="the stack has it")
  assert_true(read("s-c1") && !read("s-c2"), msg="the chat before stays")
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  assert_eq(t.find("新建对话").unwrap().0, nx)
  // its view come: the page shows it, and comes over
  t.run_for(tape_core_late_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
  assert_true(read("s-c2") && !read("s-c1"), msg="the chat chosen shown, the one before left")
  t.run_for(@ui.move_most_ms)
  let (x, _) = t.find("新建对话").unwrap()
  assert_true(x < nx - 100.0, msg="the sidebar's first row at \{x}, from \{nx}")
}

///|
/// What the last frame drew from `left` across on (its instances, as Tester::drawn_text says them).
fn drawn_from(t : @ui.Tester, left : Double) -> Array[String] {
  let out = []
  for line in t.drawn_text().split("\n") {
    if line.has_prefix("inst ") {
      // (its first number: where it is across, in 1/64 px)
      let mut x = 0
      let mut sign = 1
      for ch in line.view(start_offset=5) {
        if ch == '-' {
          sign = -1
        } else if ch >= '0' && ch <= '9' {
          x = x * 10 + (ch.to_int() - 48)
        } else {
          break
        }
      }
      if (sign * x).to_double() / 64.0 >= left {
        out.push(line.to_string())
      }
    }
  }
  out
}

///|
test "on the tape the sidebar's list scrolled with a finger: the page beside drawn again as it was, none of it built" {
  let t = tape_chat(2, 690.0, 840.0, width="medium", height="medium")
  t.keep_parts(true)
  // (drawn as parts and rows are drawn when kept, built: what drawing them again is held to)
  t.draw()
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  let left = match covered(t, @sf.t("web-main.sidebar.close")) {
    Some((l, _)) => l
    None => fail("no page beside the sidebar")
  }
  let page = drawn_from(t, left)
  assert_true(page.length() > 20, msg="the page beside draws \{page.length()}")
  // the list dragged: the page beside drawn again, as it was
  t.press_at(150.0, 600.0)
  for i in 1..=12 {
    t.move(150.0, 600.0 - 15.0 * i.to_double())
  }
  assert_eq(drawn_from(t, left), page)
  // let go: built anew (an event from outside), still as it was
  t.release(150.0, 420.0)
  assert_eq(drawn_from(t, left), page)
}

///|
/// How far apart the moments are that a flung list is looked at in the test below.
let tape_fling_step_ms : Double = 150.0

///|
/// The sidebar's list flung and the page brought over while it flings on: what is drawn as the tape has moved, and at
/// moments after, the sidebar kept where it can be (`keep`) or built every frame (its drawing taken as when it is
/// kept).
fn tape_flung(keep : Bool) -> Array[String] {
  // (many weeks of chats in the sidebar: far to fling)
  new_run()
  let src = fixture("long")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=690.0, h=840.0, platform=2)
  say_room(t, "medium", "medium")
  t.run_for(@ui.move_most_ms)
  t.keep_parts(true)
  t.drawn_again(keep)
  t.drag(150.0, 760.0, 150.0, 260.0, steps=6)
  t.tap(690.0 - @sfdesk.tape_shows / 2.0, 400.0)
  let out = []
  t.run_for(@ui.move_most_ms)
  out.push(drawn_from(t, -1000.0).join("\n"))
  t.run_for(tape_fling_step_ms)
  out.push(drawn_from(t, -1000.0).join("\n"))
  t.run_for(tape_fling_step_ms)
  out.push(drawn_from(t, -1000.0).join("\n"))
  out
}

///|
test "on the tape the sidebar's list flung, the page brought over: the sidebar flings on behind it as it would built" {
  let kept = tape_flung(true)
  let built = tape_flung(false)
  // (it still flings as it is looked at)
  assert_true(built[1] != built[2])
  assert_eq(kept, built)
}

///|
test "on the tape a chat's side panel is a panel of its own after the page's: opened it comes over, back the page" {
  let t = tape_chat(0, 720.0, 800.0)
  page_over(t, 720.0)
  tap_said(t, "打开侧栏")
  // (the pointer gone: no tip shown under it as the panel comes, which back would close first)
  t.leave()
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Panel)
  // the panel whole at the window's right, the page's edge showing at its left
  match said_at(t, "收起侧栏") {
    Some((x, _, w, _)) => assert_true(x + w <= 720.0 && x + w > 600.0, msg="its switch at \{x} \{w}")
    None => fail("no panel: \{t.drawn_text()}")
  }
  // back: the page comes over, the panel's edge showing at its right
  t.back()
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
  // what shows of the panel tapped: it comes over again, nothing in it pressed
  t.tap(720.0 - @sfdesk.tape_shows / 2.0, 400.0)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Panel)
  t.run_for(@ui.move_most_ms)
  // closed with its switch: the page comes over
  tap_said(t, "收起侧栏")
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
  assert_true(said_at(t, "收起侧栏") is None)
}

///|
test "on the tape back brings the sidebar over from the chat, and with the chats' sidebar in use is the system's" {
  // an opened fold's inner screen upright, a finger
  let t = tape_chat(2, 690.0, 840.0, width="medium", height="medium")
  assert_true(@sfdesk.wide.tape)
  page_over(t, 690.0)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
  t.back()
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  assert_true(on_first_chat())
  t.run_for(@ui.move_most_ms)
  t.back()
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  assert_true(on_first_chat())
}

///|
test "off the tape to 用量, the sidebar's panel closes to the bar holding the settings' list, never the chats'; back to the settings, theirs as it opens" {
  let t = tape_chat(2, 690.0, 840.0, width="medium", height="medium")
  tap_said(t, "设置")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("返回会话") is Some(_))
  tap_said(t, "用量")
  t.run_for(@ui.move_most_ms / 2.0)
  assert_false(@sfdesk.wide.tape)
  assert_true(t.find("返回会话") is Some(_), msg="the settings' list as it closes")
  assert_true(t.find("新建对话") is None, msg="not the chats' list")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("返回会话") is None && t.find("新建对话") is None)
  tap_said(t, "设置")
  t.frame()
  assert_true(@sfdesk.wide.tape)
  assert_true(t.find("返回会话") is Some(_), msg="the settings' list as it opens")
  assert_true(t.find("新建对话") is None)
}

///|
test "on the tape the system's back gesture brings the sidebar over as it goes, on or back from where it ended" {
  // an opened fold's inner screen upright, a finger
  let t = tape_chat(2, 690.0, 840.0, width="medium", height="medium")
  let words = "做完了：列表、跳到最新的按钮"
  page_over(t, 690.0)
  let (page_x, _, _, _) = t.rect_of(words).unwrap()
  // called off 200 along: the tape had come with it, and goes back from there, the page still in use
  t.back_gesture(200.0, false)
  let (x, _, _, _) = t.rect_of(words).unwrap()
  assert_true(x > page_x + 150.0, msg="called off at \{x}, the page at rest at \{page_x}")
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
  t.run_for(@ui.move_most_ms)
  assert_eq(t.rect_of(words).unwrap().0, page_x)
  // gone through 200 along: on from there, the sidebar over
  t.back_gesture(200.0, true)
  let (x, _, _, _) = t.rect_of(words).unwrap()
  assert_true(x > page_x + 150.0, msg="gone through at \{x}, the page at rest at \{page_x}")
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  t.run_for(@ui.move_most_ms)
  // (the page beside the sidebar, past its own width)
  assert_true(t.rect_of(words).unwrap().0 > @sfdesk.rail_w + 240.0)
  assert_true(on_first_chat())
  // the chats' sidebar in use: back the system's, the app takes none
  assert_false(t.takes_back())
}

///|
test "on the tape back from another place's sidebar goes to the chats', as a phone's place goes back to them" {
  let t = tape_chat(2, 690.0, 840.0, width="medium", height="medium")
  @sfdesk.open_settings()
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.lit_place(), "settings")
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  assert_true(t.takes_back())
  t.back()
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.lit_place(), "chats")
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  assert_false(t.takes_back())
}

///|
test "on the tape a chat opened from the page in use goes over it, as on a phone: back takes it off, then brings the sidebar" {
  let t = tape_chat(2, 690.0, 840.0, width="medium", height="medium")
  page_over(t, 690.0)
  // a chat opened from the page in use (a link in a message, ⌘K there): over it, sliding in
  let other : ChatRef = { station: "ws1/st1", session: "s-c2", title: "首页的列表改成按天分组", station_name: "Studio" }
  @sfbase.open_page(Chat(other))
  t.run_for(page_local_ms + @ui.move_most_ms)
  assert_eq(app.nav.depth(), 3)
  assert_true(app.nav.top_over())
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
  let (rest_x, _, _, _) = t.rect_of("好的，我来处理。").unwrap()
  // the system's back gesture called off: it went with the finger, and comes back
  t.back_gesture(200.0, false)
  let (x, _, _, _) = t.rect_of("好的，我来处理。").unwrap()
  assert_true(x > rest_x + 150.0, msg="called off at \{x}, at rest at \{rest_x}")
  t.run_for(@ui.move_most_ms)
  assert_eq(app.nav.depth(), 3)
  // its side panel in use: back brings the page over first, the chat opened still over the other
  tap_said(t, "打开侧栏")
  // (the pointer gone: no tip shown under it as the panel comes, which back would close first)
  t.leave()
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Panel)
  t.back()
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
  assert_eq(app.nav.depth(), 3)
  // back: the chat it was opened from, the page still in use
  t.back()
  t.run_for(@ui.move_most_ms)
  assert_eq(app.nav.depth(), 2)
  assert_true(on_first_chat())
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
  // back again: the sidebar, the chat chosen there kept
  t.back()
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  assert_true(on_first_chat())
  // chosen in the sidebar: in its place, nothing over it, beside the sidebar still in use
  t.tap_text("首页的列表改成按天分组")
  t.run_for(@ui.move_most_ms)
  assert_eq(app.nav.depth(), 2)
  assert_false(app.nav.top_over())
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
}

///|
test "on the tape a finger dragging across the one in use moves no tape: the tape stays where it is" {
  let t = tape_chat(2, 690.0, 840.0, width="medium", height="medium")
  page_over(t, 690.0)
  let (mx, my) = t.find("做完了：列表、跳到最新的按钮").unwrap()
  t.drag(mx, my, mx + 300.0, my)
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
  let (again, _) = t.find("做完了：列表、跳到最新的按钮").unwrap()
  assert_eq(again, mx)
}

///|
test "a phone turned sideways for a film: the layout it had (the player the whole screen, no rail nor list beside it)" {
  new_run()
  let src = fixture("player-video")
  open_drive_fixture("player-video")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
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
fn drag_slowly(
  t : @ui.Tester,
  x : Double,
  y : Double,
  by : Double,
  up? : Bool = true,
  hold? : Bool = false,
) -> Unit {
  t.press_at(x, y)
  // (an edge: a finger's held on it first, @sf.handle_drag)
  if hold {
    t.run_for(@ui.long_press_ms)
  }
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
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  assert_eq(t.find(words).unwrap().0, side_x)
  // half the way across, held: the page with the finger, between where it rests either way, the sidebar still in use
  let way = side_x - page_x
  drag_slowly(t, 650.0, 400.0, -way / 2.0, up=false)
  let (held_x, _) = t.find(words).unwrap()
  assert_true(held_x < side_x - way / 4.0 && held_x > page_x, msg="held at \{held_x}: \{page_x}..\{side_x}")
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  // let go: the page comes over, nothing in it pressed
  t.release(650.0 - way / 2.0, 400.0)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
  t.run_for(@ui.move_most_ms)
  assert_eq(t.find(words).unwrap().0, page_x)
  assert_true(on_first_chat())
}

///|
test "on the tape what shows of the page dragged a little and let go: the tape back where it was, the sidebar in use" {
  let t = tape_chat(2, 690.0, 840.0, width="medium", height="medium")
  let words = "做完了：列表、跳到最新的按钮"
  let (side_x, _) = t.find(words).unwrap()
  drag_slowly(t, 650.0, 400.0, -40.0)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  t.run_for(@ui.move_most_ms)
  assert_eq(t.find(words).unwrap().0, side_x)
  // the page in use: what shows of the sidebar dragged right past a third of the way brings it over
  page_over(t, 690.0)
  let (page_x, _) = t.find(words).unwrap()
  drag_slowly(t, 40.0, 400.0, (side_x - page_x) * 0.6)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
}

///|
/// Where the composer's field is drawn from the left and the bottom of the panel it is in (as drawn: a panel's move
/// and any of the field's own); None when it is drawn out of every panel.
fn composer_in_panel(t : @ui.Tester) -> (Double, Double)? {
  let bs = t.boxes()
  guard bs.search_by(fn(b) { b.kind == "editor" }) is Some(e) else { return None }
  let ed = bs[e]
  for b in bs {
    if b.radius == @sf.tape_corner && b.x <= ed.x && ed.x + ed.w <= b.x + b.w {
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
    t.run_for(@ui.move_most_ms / 8.0)
    same("bringing the page, step \{k}")
  }
  t.run_for(@ui.move_most_ms)
  same("the page over")
  t.back()
  for k in 1..=6 {
    t.run_for(@ui.move_most_ms / 8.0)
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
  t.run_for(@ui.move_most_ms * 2.0)
  // (a square window: the panels' corners all the tape's)
  assert_eq(@sf.tape_edge.radius(@ui.corner_roots()), @sf.tape_corner)
  let panel = @sf.tape_corner
  // one line: a capsule (its half: a pill in the panel's corner keeps its own, the panel's less how far in it stands),
  // its buttons round in its ends; the screen's buttons (a touch screen's larger), the same shape
  let side = @sf.theme().round.side
  guard composer_corners(t) is Some((k, s, h)) else { fail("no composer") }
  assert_eq(k, h / 2.0)
  assert_eq(s, side / 2.0)
  // its ends concentric with the panel's foot corners as high as it is: as far in from its sides and foot as the
  // panel's corner less its half (the user, 2026-10-26: a finger's, 52 high, stood where keyboard and mouse's 48 would)
  guard composer_and_panel(t) is Some((b, p)) else { fail("no composer in a panel") }
  let at = (b.x - p.x, p.x + p.w - (b.x + b.w), p.y + p.h - (b.y + b.h), 0.0)
  let concentric = @sf.capsule_in(panel, h)
  assert_true(near4(at, (concentric, concentric, concentric, 0.0)), msg="the capsule from the panel's edges: \{at}")
  // (the tape's 28, as a circle reads it (@ui.round_like: 26.78): a capsule standing concentric 6 in, as the panel
  // stands from the window's edge, is 41.56 high; a finger's 36 buttons 4 in its ends need 44: 44, 4.78 in)
  let r = @ui.round_like(panel)
  assert_true((h - (side + 2.0 * @sf.corner_fit.near)).abs() < 1.0e-9, msg="\{h}")
  assert_true(2.0 * (r - @sf.window_in) < h && h < 2.0 * (r - @sf.corner_fit.near), msg="\{h}")
  assert_eq(t.corner_faults(), [])
  // lines more: the box concentric with the panel, the send button with the box, 12 in
  t.tap_text("发消息")
  t.type_text("第一行\n第二行\n第三行")
  t.run_for(@ui.move_most_ms)
  guard composer_corners(t) is Some((k, s, _)) else { fail("no composer") }
  // (a card's corner would stand 2.5 in, nearer than corner_fit lets: as near as it does, 4, less round than a card's
  // there, 24.8; its buttons round in its corners)
  let d = @sf.foot_fit(panel, panel, 0.0, least=@sf.holds_least(side))
  assert_eq(d, @sf.corner_fit.near)
  guard composer_and_panel(t) is Some((b, p)) else { fail("no composer in a panel") }
  let at = (b.x - p.x, p.x + p.w - (b.x + b.w), p.y + p.h - (b.y + b.h), 0.0)
  assert_true(near4(at, (d, d, d, 0.0)), msg="the box from the panel's edges: \{at}")
  assert_true((k - @ui.concentric(panel, d)).abs() < 0.01, msg="the box's corner: \{k}")
  assert_true(k < @sf.card_corner)
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
    if round(b) && b.radius == @sf.tape_corner {
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
  new_run()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=690.0, h=840.0, platform=0, window_corner=16.0)
  t.run_for(@ui.move_most_ms)
  // the window's 16, 6 in: 11.2
  let edge = @ui.concentric(16.0, 6.0)
  assert_eq(@sf.tape_edge.radius(@ui.corner_roots()), edge)
  let pane = @sf.tape_corner
  // the sidebar in use: its left corners at the window's, the page's right ones past its right edge as they will be
  // there
  guard composer_and_panel(t) is Some((_, page)) else { fail("no composer in a panel") }
  assert_true(near4(page.radii, (pane, edge, edge, pane)), msg="the page's panel: \{page.radii}")
  assert_true(
    t.boxes().iter().any(fn(b) { near4(b.radii, (edge, pane, pane, edge)) && b.x < 10.0 }),
    msg="no sidebar's panel with its left corners the window's",
  )
  assert_eq(t.corner_faults(), [])
  // the page brought over, its composer taking the cursor (keyboard and mouse's): a box, its foot's left corner
  // following the panel's 28 (4 in, as near as corner_fit lets: 24.8, its ＋ in it concentric with it); its right not
  // the window's 11.2, which its send could not follow in turn (the user, 2026-10-25: the corner followed, the send did
  // not), as round as its left there, the send in it as in its other corners
  t.tap(650.0, 400.0)
  t.run_for(@ui.move_most_ms * 2.0)
  guard composer_and_panel(t) is Some((k, p)) else { fail("no composer in a panel") }
  let d = @sf.foot_fit(pane, edge, 0.0, least=@sf.holds_least(32.0))
  assert_true((d - @sf.corner_fit.near).abs() < 0.01, msg="the box's place: \{d}")
  let at = (k.x - p.x, p.x + p.w - (k.x + k.w), p.y + p.h - (k.y + k.h))
  assert_true(near4((at.0, at.1, at.2, 0.0), (d, d, d, 0.0)), msg="the box from the panel's edges: \{at}")
  let round = @ui.concentric(pane, d)
  assert_true(near4(k.radii, (round, round, round, round)), msg="the box's corners: \{k.radii}")
  assert_eq(t.corner_faults(), [])
  // let go of: a capsule, its left end concentric with the panel's 28 (4 in), its right in the window's 11.2, too
  // square for it, as far in as the left; the box's place to the capsule's in the one change of shape
  t.ctx().blur()
  // (let go of from the next frame on; its change of shape over by twice its length after that)
  t.run_for(@sfpages.let_go_ms + 2.0 * @ui.move_most_ms)
  guard composer_and_panel(t) is Some((k, p)) else { fail("no composer in a panel") }
  let six = @sf.capsule_in(pane, k.h)
  let at = (k.x - p.x, p.x + p.w - (k.x + k.w), p.y + p.h - (k.y + k.h))
  assert_true(near4((at.0, at.1, at.2, 0.0), (six, six, six, 0.0)), msg="the capsule from the panel's edges: \{at}")
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
  // (a panel: rounded, large, from the window's top; a card as large on the page stands lower, in the page's panel)
  let mut page : @ui.Laid? = None
  for b in bs {
    if b.radius >= 11.0 && b.w >= 300.0 && b.h >= 300.0 && b.y < 50.0 && (page is None || b.x > page.unwrap().x) {
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
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  t.tap_text("新建对话")
  assert_true(app.nav.top() is NewChat)
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
  // back: the sidebar again
  t.back()
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  @sfdesk.new_chat()
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
}

///|
test "on the tape a finger's search at the lists' top: tucked under the band at first, pulled down whole under it" {
  // an opened fold's inner screen upright, its system bars over it
  let t = tape_chat(2, 750.0, 830.0, width="medium", height="medium")
  t.post(@hostapi.system_channel, "{\"bars\":{\"top\":36,\"bottom\":24,\"left\":0,\"right\":0}}")
  t.run_for(@ui.move_most_ms)
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
  // (the page beside kept as it was drawn while nothing changes it, as on a device: held, built)
  t.keep_parts(true)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  hold_on(t, "做完了：列表、跳到最新的按钮") |> ignore
  t.draw()
  assert_true(pk.ts != "")
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
  t.run_for(@ui.move_most_ms)
  // still picked, its bar over it where the page is now
  assert_true(pk.ts != "")
  t.tap_text("引用")
  t.draw()
  assert_true(pk.ts == "")
  assert_true(t.find("添加说明（可选）") is Some(_))
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
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
    // the sidebar in use: the page behind (what shows of it at the right), on the darker ground, its words drawn as
    // before
    let (mx, my, _, _) = t.rect_of("做完了：列表、跳到最新的按钮").unwrap()
    assert_true(grounds_at(t, mx + 4.0, my).contains(behind), msg="dark \{dark}: the page's grounds \{grounds_at(t, mx + 4.0, my)}")
    let (rx, ry) = t.find("首页的列表改成按天分组").unwrap()
    assert_false(grounds_at(t, rx, ry).contains(behind), msg="dark \{dark}: the sidebar's grounds")
    // the page brought over: the sidebar behind now (what shows of it at the left), the page on its own ground
    page_over(t, 750.0)
    let (mx, my) = t.find("做完了：列表、跳到最新的按钮").unwrap()
    assert_false(grounds_at(t, mx - 4.0, my).contains(behind), msg="dark \{dark}: the page in use")
    let (_, ry) = t.find("首页的列表改成按天分组").unwrap()
    assert_true(grounds_at(t, @sfdesk.tape_shows / 2.0, ry).contains(behind), msg="dark \{dark}: the sidebar behind")
  }
}

///|
test "on the tape a panel's ground goes behind or comes in front with the tape's move, not at once" {
  let t = tape_chat(2, 750.0, 830.0, width="medium", height="medium")
  let behind = @sf.behind_ground()
  let bg = @sf.theme().p.bg
  let (mx, my, _, _) = t.rect_of("做完了：列表、跳到最新的按钮").unwrap()
  assert_true(grounds_at(t, mx + 4.0, my).contains(behind))
  // what shows of the page pressed: half way over, its ground half way back to the page's
  t.tap(750.0 - @sfdesk.tape_shows / 2.0, 400.0)
  // (well on its way: no way takes less than a Move of nothing far)
  t.run_for(@ui.move_least_ms / 2.0)
  let (mx, my) = t.find("做完了：列表、跳到最新的按钮").unwrap()
  // (the ground on top there: the page's panel's, its message's own drawn on it clear)
  let half = grounds_at(t, mx - 4.0, my).filter(fn(g) { g != 0L })[0]
  assert_true(half != behind && half != bg, msg="\{half}")
  t.run_for(@ui.move_most_ms)
  let (mx, my) = t.find("做完了：列表、跳到最新的按钮").unwrap()
  assert_false(grounds_at(t, mx - 4.0, my).contains(behind))
}

///|
test "on the tape the sidebar's rows stand in a side column's line, their words as 新建对话's; a phone's 22 from the screen's edge" {
  let t = tape_chat(2, 750.0, 830.0, width="medium", height="medium")
  // the sidebar's panel 6 from the window's edge, its list from 8 into the rail, the rail as much wider as its places
  // stand further in than its 8 (concentric with the panel's corner): a row's ground as far in as 新建对话's (band_in),
  // its words without a mark before them as far from it (band_pad)
  let l = @sf.theme().chat_list
  let (x, _, _, _) = t.rect_of("Slack 里问的报销流程").unwrap()
  assert_eq(x, @sfdesk.closed_bar_in + @sfdesk.rail_w - 8.0 + (@sf.rail_in_tape() - 8.0) + l.band_in + l.band_pad)
  let p = tape_chat(2, 390.0, 844.0, width="compact", height="medium")
  p.run_for(@ui.move_most_ms)
  p.back()
  p.run_for(@ui.move_most_ms)
  let (x, _, _, _) = p.rect_of("Slack 里问的报销流程").unwrap()
  assert_eq(x, 22.0)
}

///|
test "on the tape the rail's first place stands on the line of the sidebar's first row, 新建对话's" {
  let t = tape_chat(2, 750.0, 830.0, width="medium", height="medium")
  t.post(@hostapi.system_channel, "{\"bars\":{\"top\":36,\"bottom\":24,\"left\":0,\"right\":0}}")
  t.run_for(@ui.move_most_ms)
  let (_, by, _, bh) = said_at(t, "待处理").unwrap()
  let (_, ny, _, nh) = said_at(t, "新建对话").unwrap()
  assert_true((by + bh / 2.0 - (ny + nh / 2.0)).abs() <= 0.5, msg="待处理's middle \{by + bh / 2.0}, 新建对话's \{ny + nh / 2.0}")
}

///|
test "on the tape 新建对话 lit stands over the search's field: its ground's edge, its icon and its words on the field's" {
  let t = tape_chat(2, 750.0, 830.0, width="medium", height="medium")
  @sfdesk.new_chat()
  t.run_for(@ui.move_most_ms)
  t.tap(30.0, 400.0)
  t.run_for(@ui.move_most_ms)
  let (sx, _, _, _) = said_at(t, "搜索全部内容").unwrap()
  let (nx, _, _, _) = said_at(t, "新建对话").unwrap()
  assert_eq(nx, sx)
  let (wx, _, _, _) = t.rect_of("新建对话").unwrap()
  let (px, _, _, _) = t.rect_of("搜索全部内容").unwrap()
  assert_eq(wx, px)
}

///|
test "新建对话 pressed on a touch device: the cursor in the new chat's composer, its keyboard up" {
  let t = tape_chat(2, 750.0, 830.0, width="medium", height="medium")
  let (before, _, _, _) = t.ime()
  assert_false(before)
  t.tap_text("新建对话")
  t.run_for(@ui.move_most_ms)
  let (after, _, _, _) = t.ime()
  assert_true(after)
}


///|
test "on the tape 重启更新 is in the sidebar's first row before the filter, as large as it: the sidebar where it is without one" {
  let t = tape_chat(2, 750.0, 830.0, width="medium", height="medium")
  t.post(@hostapi.system_channel, "{\"bars\":{\"top\":36,\"bottom\":24,\"left\":0,\"right\":0}}")
  t.run_for(@ui.move_most_ms)
  let (_, ny, _, _) = t.rect_of("新建对话").unwrap()
  @sffixture.fixture_update("0.1.9999")
  @sffixture.fixture_update_goes("0.1.9999", "ready", away=false)
  t.run_for(@ui.move_most_ms)
  let (_, ny2, _, _) = t.rect_of("新建对话").unwrap()
  assert_eq(ny2, ny)
  let (ux, uy, uw, uh) = said_at(t, "重启更新").unwrap()
  let (fx, fy, _, fh) = said_at(t, "筛选会话：全部").unwrap()
  assert_eq(uh, fh)
  assert_eq(uy, fy)
  assert_true(ux + uw <= fx, msg="重启更新 to \{ux + uw}, the filter from \{fx}")
  update.available.set(None)
}

///|
test "on the tape a passage left picked keeps nothing from coming over: the sidebar pulled over comes and stays" {
  let t = tape_chat(2, 750.0, 830.0, width="medium", height="medium")
  hold_on(t, "做完了：列表、跳到最新的按钮") |> ignore
  t.draw()
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
  t.run_for(@ui.move_most_ms)
  assert_true(pk.ts != "")
  // what shows of the sidebar pulled across, the passage still picked: the sidebar comes over, and stays
  t.drag(30.0, 400.0, 500.0, 400.0)
  assert_true(pk.ts != "")
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
}

///|
/// The settings in a window `w` × 760 of a Mac's, a page of theirs opened by `open` as the app begins or after its
/// first frame, the tape's move over.
fn tape_settings(w : Double, open : () -> Unit, first? : Bool = false) -> @ui.Tester {
  new_run()
  let src = fixture("settings")
  if first {
    open()
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h=760.0, platform=0)
  t.draw()
  if !first {
    open()
  }
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// Whether the settings page holding `words` is the one in use, whole in the window `w` wide: its words past what shows
/// of the sidebar at its left, and their end in the window.
fn settings_page_whole(t : @ui.Tester, words : String, w : Double) -> Bool {
  match t.rect_of(words) {
    Some((x, _, tw, _)) => x >= @sfdesk.tape_shows && x + tw <= w && @sfdesk.wide.tape_at.get() == @sfdesk.TapePane::Page
    None => false
  }
}

///|
test "on the tape a settings page opened at one of its own (⌘K's, the bell's 通知设置, 快捷键 from its dialog) shows beside their list, pressed whole in the window" {
  let t = tape_settings(600.0, fn() { @sfdesk.open_settings_at(@settings.Route::LocalStation) })
  assert_true(@sfdesk.wide.tape)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  page_over(t, 600.0)
  assert_true(settings_page_whole(t, local_none, 600.0), msg="\{@sfdesk.wide.tape_at.get()} \{t.rect_of(local_none)}")
}

///|
test "on the tape a settings page a fixture opens as the app begins (a scripted run's, a picture's) is the one in use, as a row of their list opens it: whole in the window" {
  let t = tape_settings(600.0, fn() { open_fixture_mode("settings-local-station") }, first=true)
  assert_true(@sfdesk.wide.tape)
  assert_true(settings_page_whole(t, local_none, 600.0), msg="\{@sfdesk.wide.tape_at.get()} \{t.rect_of(local_none)}")
}

///|
test "on the tape the gear's settings: their list in use, its first row's page showing beside it" {
  let t = tape_settings(600.0, fn() { open_page(Settings) })
  assert_true(@sfdesk.wide.tape)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
}

///|
/// 本机 Station's words where this machine has none (the Tester's host says none).
let local_none : String = "本机没有单独安装的 station"

///|
test "on the tape a settings page chosen in their list shows beside it, pressed is the one in use; from a page of theirs a level further in, it stays in use: whole in the window" {
  let t = tape_settings(600.0, fn() { open_page(Settings) })
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  // a row of their list: 记忆, beside it; what shows of it pressed, over
  t.click(Link, label="记忆")
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
  page_over(t, 600.0)
  assert_true(settings_page_whole(t, "全局记忆 · 项目记忆", 600.0), msg="\{@sfdesk.wide.tape_at.get()} \{t.rect_of("全局记忆 · 项目记忆")}")
  // a level further in from the page in use: a station's memory, then one of its pages
  t.tap_text("Studio")
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  assert_true(settings_page_whole(t, "发布流程", 600.0), msg="\{@sfdesk.wide.tape_at.get()} \{t.rect_of("发布流程")}")
  t.tap_text("发布流程")
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  assert_true(settings_page_whole(t, "checklist", 600.0), msg="\{@sfdesk.wide.tape_at.get()} \{t.rect_of("checklist")}")
}

///|
test "on the tape, a chat's service opened from the chat in use: its side panel comes over with it, the chat beside" {
  new_run()
  let src = fixture("chat-jobs")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=720.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  assert_true(@sfdesk.wide.tape)
  // (the chat in use, the sidebar beside it)
  @sfdesk.bring_page()
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
  // (as its link in a message opens it: a page, which the frame lays beside its chat)
  open_page(Service("ws1/st1", "j-web"))
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "", station_name: "" }
  assert_eq(@sfdesk.side_now(src, r).1, "service:j-web")
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Panel)
}
