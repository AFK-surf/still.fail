// An iPhone Duo's frame (sfdesk's rail_native.mbt, the library's native_bars.mbt): where the system lays out the app's
// tabs and its actions itself, the app hands them over and draws none of its own (no rail, no bottom bar), its cards
// across in every width; everywhere else nothing of it, the frame as it was.

///|
test "Duo standalone screen replaces app navigation with its own controls and restores it on close" {
  new_run()
  let src = fixture("screen-live")
  open_fixture_over("screen-live", src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=951.0, h=669.0, platform=1)
  t.set_nav_able(true)
  t.post(@hostapi.system_channel, "{\"bars\":{\"top\":0,\"bottom\":20,\"left\":0,\"right\":84}}")
  t.run_for(@ui.move_most_ms)
  assert_true(t.nav_said().contains("\"bare\":true"), msg=t.nav_said())
  assert_true(t.nav_said().contains("lead/over/screen-close"), msg=t.nav_said())
  t.post(@hostapi.system_channel, "{\"nav\":\"lead/over/screen-close\"}")
  t.run_for(@ui.move_most_ms)
  assert_false(app.nav.top() is Screen(_))
  assert_true(t.nav_said().contains("\"bare\":false"), msg=t.nav_said())
}

///|
/// The fixture's chat (or `mode`'s) open in a window `w` × `h` of iOS (platform 1), the system's own bars or not (`able`), its column
/// down the window's trailing edge `side` wide (0: upright, across), the screen's corners `corner` round (`corners`:
/// each its own, top left then round it).
fn native_chat(
  w : Double,
  h : Double,
  able : Bool,
  side? : Double = 0.0,
  mode? : String = "chat",
  corner? : Double = 0.0,
  corners? : FixedArray[Double],
  platform? : Int = 1,
) -> @ui.Tester {
  new_run()
  let src = fixture(mode)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~, window_corner=corner, window_corners?=corners, nav_able=able)
  t.post(@hostapi.system_channel, "{\"bars\":{\"top\":0,\"bottom\":20,\"left\":0,\"right\":\{side}}}")
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "an iPhone Duo on its side: the places and the chat's actions handed to the system's bars, the app drawing no rail nor tabs of its own, the cards beside the column" {
  let t = native_chat(951.0, 669.0, true, side=84.0)
  // (at rest: what is drawn held to the corner rule, the list's filter concentric with its card's corner)
  t.run_for(@ui.move_most_ms)
  t.assert_idle()
  let said = t.nav_said()
  for id in ["place/chats", "place/files", "place/stations", "act/attention", "\"new\"", "page/chat/info", "page/chat/history"] {
    if !said.contains(id) {
      fail("the bars handed hold no \{id}: \{said}")
    }
  }
  assert_true(@sf.native_on())
  assert_true(@sf.native_side())
  assert_eq(@sf.native_clear(), 84.0)
  // (none of the app's own: no bottom bar's tabs, the chat's ⋯ and agents in the system's bars)
  assert_false(bar_tabs(t))
  assert_true(said_at(t, @sf.t("web-pages.chat.info")) is None)
  // (what is pressed in the cards clear of the column; the card itself, pressed to bring it in, goes under it to the
  // screen's edge, its ground there)
  for s in t.semantics() {
    let (x, _, w, _) = s.rect
    // (the card pressed to bring it over: what shows of the page beside the sidebar in use)
    let card = s.label == "收起侧边栏"
    if !s.hidden && !card && s.role == @ui.Role::Button && s.label != "" && w > 0.0 && x + w > 951.0 - 84.0 + 0.5 {
      fail("\{s.label} under the system's column: \{s.rect}")
    }
  }
}

///|
test "an iPhone Duo upright: the same frame, the actions across the top (the bell at its lead)" {
  let t = native_chat(669.0, 951.0, true)
  let said = t.nav_said()
  assert_true(said.contains("lead/attention"))
  assert_false(said.contains("lead/workspaces"))
  assert_true(@sf.native_on())
  assert_false(@sf.native_side())
  assert_eq(@sf.native_clear(), 0.0)
  assert_false(bar_tabs(t))
}

///|
test "an iPhone Duo upright: the system's tabs across its foot in the bars' room, the cards and the composer over them, not under" {
  let t = native_chat(669.0, 951.0, true)
  // (its floating tab bar and the home indicator's line: the safe area's foot)
  t.post(@hostapi.system_channel, "{\"bars\":{\"top\":59,\"bottom\":90,\"left\":0,\"right\":0}}")
  t.run_for(@ui.move_most_ms)
  guard composer_and_page(t) is Some((b, p)) else { fail("no composer in a page") }
  assert_true(p.y + p.h <= 951.0 - 90.0 + 0.5, msg="the page's foot at \{p.y + p.h}")
  assert_true(b.y + b.h <= 951.0 - 90.0, msg="the composer's foot at \{b.y + b.h}")
}

///|
test "an iPhone, a phone or any other device with no bars of the system's for the app: nothing of the Duo's, the frame as it was" {
  for size in [(390.0, 844.0), (951.0, 669.0)] {
    let t = native_chat(size.0, size.1, false)
    assert_false(@sf.native_on())
    assert_false(@sf.native_side())
    assert_eq(@sf.native_clear(), 0.0)
    assert_eq(@sf.native_card_corner(), 0.0)
    // (the chat's ⋯ the page's own, where it has a bar of its own)
    if size.0 > 600.0 {
      assert_true(said_at(t, @sf.t("web-pages.chat.info")) is Some(_))
    }
  }
}

///|
test "a picture looked at on an iPhone Duo: the system's tabs put away, its actions in the system's bars, its own bar none" {
  let t = native_chat(951.0, 669.0, true, side=84.0, mode="chat-preview-image")
  t.run_for(@ui.move_most_ms)
  let said = t.nav_said()
  for id in ["\"bare\":true", "\"title\":\"界面草图.png\"", "lead/over/close", "over/mark", "over/copy", "over/download"] {
    if !said.contains(id) {
      fail("the bars handed hold no \{id}: \{said}")
    }
  }
  // (none of the tabs' own buttons while it is up: the chat's, the bell)
  assert_false(said.contains("page/chat/"))
  // (its name in the system's bar, not in one of its own)
  assert_true(t.find("界面草图.png") is None)
  // (the picture and its ways before and after clear of the system's column)
  for s in t.semantics() {
    let (x, _, w, _) = s.rect
    // (the card pressed to bring it over: what shows of the page beside the sidebar in use)
    let card = s.label == "收起侧边栏"
    if !s.hidden && !card && s.role == @ui.Role::Button && s.label != "" && w > 0.0 && x + w > 951.0 - 84.0 + 0.5 {
      fail("\{s.label} under the system's column: \{s.rect}")
    }
  }
  match viewer.get().unwrap().zoom.rect() {
    Some((x, _, w, _)) => assert_true(x + w <= 951.0 - 84.0 + 0.5)
    None => fail("no picture laid out")
  }
  // closed from the system's bar: the tabs back as it goes, the picture still on its way
  t.post(@hostapi.system_channel, "{\"nav\":\"lead/over/close\"}")
  t.run_for(pv_fade_ms / 4.0)
  assert_true(pv_leaving.get() is Some(_))
  assert_true(t.nav_said().contains("\"bare\":false"), msg=t.nav_said())
  t.run_for(@ui.move_most_ms)
  assert_true(viewer.get() is None)
  assert_true(t.nav_said().contains("\"bare\":false"))
}

///|
test "a picture looked at on an iPhone Duo, its bars' part kept as a host keeps it: the system's bars its own all along, not the tabs back for a frame as the page under it is built again" {
  let t = native_chat(669.0, 951.0, true, side=84.0, mode="chat-preview-image")
  // (parts kept between frames as a host keeps them, frames drawn as the display draws them)
  t.drawn_again(true)
  t.check_looks(false)
  t.finish_all()
  t.run_for(@ui.move_most_ms)
  let bars = viewer_built.bars
  // what the page under it reads changing (the app no longer the one focused), the viewer's bars not built again
  t.app_state(true, false)
  for i in 0..<30 {
    t.frame_at(t.time() + 1000.0 / 60.0)
    let said = t.nav_said()
    assert_true(said.contains("\"bare\":true") && said.contains("lead/over/close"), msg="frame \{i}: \{said}")
    assert_false(said.contains("page/chat/"), msg="frame \{i}")
  }
  assert_true(viewer_built.bars - bars <= 1, msg="the bars built \{viewer_built.bars - bars} times")
}

///|
test "a picture looked at elsewhere: its own bar, as it was" {
  let t = native_chat(951.0, 669.0, false, mode="chat-preview-image")
  t.run_for(@ui.move_most_ms)
  assert_false(@sf.native_over.up)
  assert_true(t.find("界面草图.png") is Some(_))
}

///|
test "an iPhone Duo on its side, the soft keyboard up: the composer whole over it, its send button too" {
  let t = native_chat(951.0, 669.0, true, side=84.0)
  // (the home indicator's room as the Duo's outer screen has it on its side: 34)
  t.post(@hostapi.system_channel, "{\"bars\":{\"top\":0,\"bottom\":34,\"left\":0,\"right\":84}}")
  t.tap_text("发消息")
  // the keyboard up: said from the window's foot down the side, the window laid out above it, as the host lays it out
  // (ios_app.m ime_over)
  let kb = 314.0
  t.set_ime_inset(kb)
  t.resize(951.0, 669.0 - kb)
  t.run_for(@ui.move_most_ms)
  let keyboard_top = 669.0 - kb
  let send = t.semantics().filter(fn(s) { s.label == @sf.t("web-main.composer.send") })
  assert_eq(send.length(), 1)
  let (_, y, _, h) = send[0].rect
  assert_true(y + h <= keyboard_top + 0.5, msg="send at \{y}..\{y + h}, keyboard at \{keyboard_top}")
}

///|
test "an iPhone Duo on its side, the soft keyboard rising: the cards end on it from its first point on, at its own pace" {
  let t = native_chat(951.0, 669.0, true, side=84.0)
  t.post(@hostapi.system_channel, "{\"bars\":{\"top\":0,\"bottom\":34,\"left\":0,\"right\":84}}")
  t.tap_text("发消息")
  t.run_for(@ui.move_most_ms)
  // (the keyboard a little up, then past the home indicator's line: the page's card ending on it each time, not
  // waiting for it to pass the line and then catching up)
  for kb in [10.0, 30.0, 60.0, 120.0] {
    t.set_ime_inset(kb)
    t.resize(951.0, 669.0 - kb)
    t.run_for(@ui.move_most_ms)
    guard composer_and_page(t) is Some((_, p)) else { fail("no composer in a page") }
    assert_true((p.y + p.h - (669.0 - kb - @sf.native_in)).abs() < 0.05, msg="the page's foot at \{p.y + p.h} over a keyboard \{kb} up")
  }
}

///|
/// The composer's box as drawn (the glass round its field) and the page it stands in (the roundest-cornered box round
/// it, its foot left corner its own).
fn composer_and_page(t : @ui.Tester) -> (@ui.Laid, @ui.Laid)? {
  let bs = t.boxes()
  guard bs.search_by(fn(b) { b.kind == "editor" }) is Some(e) else { return None }
  let ed = bs[e]
  let round = fn(b : @ui.Laid) { b.x <= ed.x && ed.x + ed.w <= b.x + b.w && b.y <= ed.y && ed.y + ed.h <= b.y + b.h }
  let mut page : @ui.Laid? = None
  let mut box : @ui.Laid? = None
  for b in bs {
    if round(b) && !b.glass && b.radii.3 > 0.0 && (page is None || page.unwrap().w < b.w) {
      page = Some(b)
    }
    if round(b) && b.glass {
      box = Some(b)
    }
  }
  match (box, page) {
    (Some(k), Some(p)) => Some((k, p))
    _ => None
  }
}

///|
test "an iPhone Duo, folded or on its side: the composer's end concentric with the page's foot corner it is in, the page going on under the column past its other end" {
  for size in [(466.0, 678.0, 70.0), (951.0, 669.0, 84.0)] {
    // (the screen's corners as the Duo's are: 59)
    let t = native_chat(size.0, size.1, true, side=size.2, corner=59.0)
    t.run_for(@ui.move_most_ms)
    // (folded, the cards across with the list's in view: the page's brought in, as a finger does)
    if size.0 < 600.0 {
      t.drag(400.0, 330.0, 140.0, 330.0)
      t.run_for(@ui.move_most_ms * 2.0)
    }
    guard composer_and_page(t) is Some((b, p)) else { fail("no composer in a page") }
    // (the page on under the column, the composer ending before it: where the cards stand across, the list's or the
    // page's in view)
    assert_true(b.x + b.w <= p.x + p.w - size.2 + 0.5, msg="the composer \{b.x}..\{b.x + b.w}, the page \{p.x}..\{p.x + p.w}")
    let concentric = @sf.capsule_in(p.radii.3, b.h)
    let at = (b.x - p.x, p.y + p.h - (b.y + b.h))
    assert_true(
      (at.0 - concentric).abs() < 0.01 && (at.1 - concentric).abs() < 0.01,
      msg="\{size}: the capsule \{at} from the page's left and foot, concentric \{concentric}",
    )
    assert_eq(t.corner_faults(), [])
  }
}

///|
test "an iPhone Duo, folded or on its side: the cards as far from the screen's foot as from its side, the composer one row with the system's action at the column's foot, as high, concentric in the page's foot corner" {
  for size in [(466.0, 678.0, 70.0), (951.0, 669.0, 84.0)] {
    let (w, h, side) = size
    let t = native_chat(w, h, true, side~, corner=59.0)
    // (the system's round action, 24 in from the screen's side and foot, 48.67 across: as the Duo's iOS 27.1 lays it)
    let a = 48.67
    let (ax, ay) = (w - 24.0 - a, h - 24.0 - a)
    t.post(@hostapi.system_channel, "{\"bars\":{\"top\":0,\"bottom\":20,\"left\":0,\"right\":\{side}},\"nav_action\":{\"x\":\{ax},\"y\":\{ay},\"w\":\{a},\"h\":\{a}}}")
    t.run_for(@ui.move_most_ms)
    if w < 600.0 {
      t.drag(400.0, 330.0, 140.0, 330.0)
      t.run_for(@ui.move_most_ms * 2.0)
    }
    guard composer_and_page(t) is Some((b, p)) else { fail("no composer in a page") }
    let near = fn(x : Double, y : Double) { (x - y).abs() < 0.05 }
    assert_true(near(p.y + p.h, h - @sf.native_in), msg="\{size}: the page's foot at \{p.y + p.h}")
    assert_true(near(b.h, a), msg="\{size}: the composer \{b.h} high")
    assert_true(near(b.y + b.h / 2.0, ay + a / 2.0), msg="\{size}: the composer's middle at \{b.y + b.h / 2.0}")
    let at = (b.x - p.x, p.y + p.h - (b.y + b.h))
    assert_true(near(at.0, at.1), msg="\{size}: the composer \{at} from the page's side and foot")
    assert_true(near(at.1, @sf.capsule_in(p.radii.3, b.h)), msg="\{size}: not concentric with \{p.radii.3}")
    // (the list's card beside it as round at its foot, the gap between them even)
    assert_true(near(@sf.tape_side_corners()[2].radius(@ui.corner_roots()), p.radii.3), msg="\{size}: the list's foot corner")
    assert_eq(t.corner_faults(), [])
  }
}

///|
test "an iPhone Duo folded, its outer screen on its side: the cards' corners each the screen's there, square along its hinge, round on the other side" {
  // (the outer screen's corners as the Duo's iOS 27.1 says them: 8 along the hinge, at its left, 59 at its right)
  let t = native_chat(466.0, 678.0, true, side=70.0, corners=[8.0, 59.0, 59.0, 8.0])
  t.run_for(@ui.move_most_ms)
  let side = @sf.corner_radii(@sf.tape_side_corners())
  // (the list's card along the hinge: 4 in from the screen's 8, concentric with it; its corners away from the
  // screen's edge the tape's)
  assert_eq(side[0], @ui.concentric(8.0, @sf.native_in))
  assert_eq(side[3], @ui.concentric(8.0, @sf.native_in))
  // (the page's card along the other side: the screen's 59 less the same)
  let page = @sf.corner_radii(@sf.tape_corners(left=false, right=true))
  assert_eq(page[1], @ui.concentric(59.0, @sf.native_in))
  assert_eq(page[2], @ui.concentric(59.0, @sf.native_in))
  assert_eq(t.corner_faults(), [])
}

///|
test "an iPhone Duo folded: the bell and complete chat menu in the system column, the workspace in the list" {
  let t = native_chat(466.0, 678.0, true, side=70.0)
  let said = t.nav_said()
  // The short column keeps the bell; the workspace switch now belongs to the list heading.
  assert_true(said.contains("act/attention"))
  assert_false(said.contains("lead/workspaces"))
  assert_true(said.contains("page/chat/info"))
  assert_false(said.contains("page/chat/history"))
}

///|
test "an iPhone Duo: a tab left in one workspace and come back to in another shows the other's, not the chat open in the first" {
  let t = native_chat(951.0, 669.0, true, side=84.0)
  let tap = fn(id : String) {
    t.post(@hostapi.system_channel, "{\"nav\":\"\{id}\"}")
    t.run_for(@ui.move_most_ms)
  }
  let first_chat = fn() {
    app.nav.pages().iter().any(fn(p) { p is Chat(r) && r.station == "ws1/st1" && r.session == "s-c1" })
  }
  assert_true(first_chat())
  tap("place/files")
  tap("ws/ws2")
  tap("place/chats")
  if first_chat() {
    fail("ws2's chats show ws1's chat")
  }
  // (back in the first workspace its chats' tab is as it was left)
  tap("place/files")
  tap("ws/ws1")
  tap("place/chats")
  assert_true(first_chat())
}

///|
test "an Android foldable open, its gesture line over the app: the page's card to the screen's foot, not lifted over the line" {
  // (a Galaxy Z Fold's inner screen, Medium: the cards across; its navigation bar the gesture line's 24)
  let t = native_chat(750.0, 832.0, false, platform=2)
  t.post(@hostapi.system_channel, "{\"bars\":{\"top\":32,\"bottom\":24,\"left\":0,\"right\":0}}")
  t.run_for(@ui.move_most_ms)
  guard composer_and_page(t) is Some((b, p)) else { fail("no composer in a page") }
  // (as far from the screen's foot as from its side: not lifted over the line's room)
  assert_true(832.0 - (p.y + p.h) < 24.0, msg="the page's foot at \{p.y + p.h}")
  // (the composer in its foot corner, concentric with it as anywhere: taps go through the line, only its swipe is the
  // system's)
  assert_true(b.y + b.h < p.y + p.h, msg="the composer's foot at \{b.y + b.h}")
}

///|
test "an iPhone Duo on its side or upright, whatever the sidebar's width: the sidebar in use with the page beside it to be brought over, never both in use side by side" {
  for size in [(951.0, 669.0, 84.0), (669.0, 951.0, 0.0)] {
    let (w, h, side) = size
    for own in [@sfdesk.side_min, 240.0, @sfdesk.tape_side_max] {
      let at = "\{w}x\{h} \{own}"
      let t = native_chat(w, h, true, side~)
      @sfdesk.wide.side_w.set(own)
      t.frame()
      // the sidebar in use, what shows of the page beside it a press to bring it over
      assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side, msg=at)
      assert_true(t.nav_said().contains("workspace-switch"), msg=at)
      guard covered(t, "收起侧边栏") is Some((px, _)) else { fail("\{at}: the page beside the sidebar not to be brought over") }
      // pressed: the page in use, the sidebar a strip at the window's left
      t.tap(px + 20.0, 400.0)
      t.run_for(@ui.move_most_ms)
      assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page, msg=at)
      assert_false(t.nav_said().contains("workspace-switch"), msg=at)
      assert_true(near_at(covered(t, "展开侧边栏").map(fn(e) { e.1 }), @sfdesk.tape_shows), msg=at)
    }
  }
}

///|
test "an iPhone Duo on its side: a service alone in the side panel a card in it, its foot corner concentric with the panel's, the page cut to each of its corners" {
  let (w, h, side) = (951.0, 669.0, 84.0)
  let t = native_chat(w, h, true, side~, mode="chat-info", corner=59.0)
  // (the system's round action at the column's foot: the panel's foot left corner made concentric round it)
  let a = 48.67
  t.post(@hostapi.system_channel, "{\"bars\":{\"top\":0,\"bottom\":20,\"left\":0,\"right\":\{side}},\"nav_action\":{\"x\":\{w - 24.0 - a},\"y\":\{h - 24.0 - a},\"w\":\{a},\"h\":\{a}}}")
  t.run_for(@ui.move_most_ms)
  app.nav.push(Service("ws1/st1", "j-web"))
  t.frame()
  t.frame()
  t.run_for(@ui.move_most_ms)
  let holes = t.holes()
  assert_eq(holes.length(), 1, msg="the service's page")
  let (x, y, hw, hh) = holes[0]
  // the panel it is alone in: the roundest at its foot left of those round it
  let mut panel : @ui.Laid? = None
  for b in t.boxes() {
    if b.radii.3 > 0.0 && b.x < x && x + hw <= b.x + b.w && b.y < y && y + hh < b.y + b.h &&
      (panel is None || panel.unwrap().w > b.w) {
      panel = Some(b)
    }
  }
  guard panel is Some(p) else { fail("no panel round the page") }
  // (the page's hole on whole device pixels, the panel's place as laid out: as near as a pixel)
  let near = fn(u : Double, v : Double) { (u - v).abs() < 0.5 }
  let room = p.y + p.h - (y + hh)
  assert_true(near(x - p.x, room), msg="the page \{x - p.x} from the panel's side, \{room} from its foot")
  let (r0, r1, r2, r3) = t.hole_corners()[0]
  assert_true(near(r3, @ui.concentric(p.radii.3, room)), msg="its foot left corner \{r3}, the panel's \{p.radii.3} \{room} out")
  // (the panel's foot corner the system's action's, rounder than the tape's: the page's not one radius all round)
  assert_true(r3 > r0 + 1.0, msg="its corners \{(r0, r1, r2, r3)}")
  assert_true(t.views().iter().any(fn(s) { s.has_prefix("place ") && s.contains(" round \{r0} \{r1} \{r2} \{r3}") }), msg="told the host each")
  assert_eq(t.corner_faults(), [])
}

///|
/// The icon of the item of the bars handed last whose id is `id` (None: no such item).
fn nav_icon_of(t : @ui.Tester, id : String, field? : String = "icon") -> String? {
  let mut found : String? = None
  fn walk(j : Json) -> Unit {
    match j {
      Object(m) => {
        if m.get("id") is Some(String(s)) && s == id && found is None {
          found = match m.get(field) {
            Some(String(i)) => Some(i)
            _ => Some("")
          }
        }
        for _, v in m {
          walk(v)
        }
      }
      Array(a) =>
        for v in a {
          walk(v)
        }
      _ => ()
    }
  }
  walk(@json.parse(t.nav_said()) catch { _ => Json::null() })
  found
}

///|
test "an iPhone Duo: a chat's actions each its own in the system's bars, its history's switch the panel's icon open once that is open beside the chat" {
  let t = native_chat(669.0, 951.0, true)
  let id = "page/chat/history"
  assert_eq(nav_icon_of(t, id), Some(@sf.icon_path("panel-open")))
  assert_eq(nav_icon_of(t, id, field="title"), Some(@sf.t("web-pages.chat.openPanel")))
  assert_eq(nav_icon_of(t, "page/chat/info"), Some(@sf.icon_path("info")))
  t.post(@hostapi.system_channel, "{\"nav\":\"\{id}\"}")
  t.run_for(@ui.move_most_ms)
  assert_eq(nav_icon_of(t, id), Some(@sf.icon_path("panel-close")))
  assert_eq(nav_icon_of(t, id, field="title"), Some(@sf.t("web-pages.chat.closePanel")))
  t.post(@hostapi.system_channel, "{\"nav\":\"\{id}\"}")
  t.run_for(@ui.move_most_ms)
  assert_eq(nav_icon_of(t, id, field="title"), Some(@sf.t("web-pages.chat.openPanel")))
  // (none of the chat's own buttons by its title: its information button)
  assert_true(said_at(t, @sf.t("web-pages.chat.info")) is None)
  t.post(@hostapi.system_channel, "{\"nav\":\"page/chat/info\"}")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find(@sf.t("web-pages.chat.info.created")) is Some(_))
}

///|
test "an iPhone Duo: the chat's info chosen in the system's column opens its popover at the item in the frames that take it, no other input after" {
  let t = native_chat(951.0, 669.0, true, side=84.0)
  assert_true(t.at_rest())
  // (ⓘ chosen where the column has it: the host says where, the app draws only the frames it asks for after, as a
  // device does; the hand does nothing more. Taken by the island under the frame, after the page's was built: the
  // user's Duo, 2026-11-01, showed nothing till a finger moved)
  t.post(@hostapi.system_channel, "{\"nav\":\"page/chat/info\",\"at\":[867,40,84,44]}")
  t.frames_owed()
  assert_true(@sfdesk.chat_pops_open().0)
  assert_true(t.find(@sf.t("web-pages.chat.info.created")) is Some(_))
  // (beside the item chosen, not where the bell was last)
  guard t.semantics().iter().find_first(fn(s) { s.role == @ui.Role::Dialog }) is Some(d) else {
    fail("no popover in the semantics")
  }
  let (dx, dy, dw, _) = d.rect
  assert_true(dy >= 40.0 && dy < 84.0, msg="its top at \{dy}")
  assert_true(dx + dw <= 867.0, msg="its right edge at \{dx + dw}")
  // (its coming over in its own time, then at rest)
  t.run_for(@ui.move_most_ms)
  t.assert_idle()
  // (a phone's room, the user 2026-11-01: no pull request by itself, 全部 N 个 alone; its groups near one another, all
  // of it shorter than the 534 it was)
  let sems = t.semantics()
  guard sems.iter().find_first(fn(s) { s.role == @ui.Role::Dialog }) is Some(d) else { fail("no popover") }
  let (dx, dy, dw, dh) = d.rect
  let inside = sems.filter(fn(s) {
    let (x, y, _, _) = s.rect
    s.role != @ui.Role::Dialog && x >= dx && x < dx + dw && y >= dy && y < dy + dh
  })
  assert_false(inside.iter().any(fn(s) { s.role == @ui.Role::Link }), msg="a pull request's row in it")
  assert_true(inside.iter().any(fn(s) { s.label == @sf.t("web-main.things.pullsAll", args=[("n", "4")]) }))
  let rows = inside.filter(fn(s) { s.role == @ui.Role::Button && s.rect.2 > dw / 2.0 })
  for i in 1..<rows.length() {
    let (_, y0, _, h0) = rows[i - 1].rect
    let gap = rows[i].rect.1 - (y0 + h0)
    assert_true(gap <= 8.0, msg="\{rows[i].label} \{gap} under the row over it")
  }
  assert_true(dh < 534.0, msg="the popover \{dh} tall")
  // (chosen again: closed, in the frames that take it)
  t.post(@hostapi.system_channel, "{\"nav\":\"page/chat/info\",\"at\":[867,40,84,44]}")
  t.frames_owed()
  assert_false(@sfdesk.chat_pops_open().0)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find(@sf.t("web-pages.chat.info.created")) is None)
  t.assert_idle()
}

///|
test "Duo side panel switch closes all tabs even when a job is in front of its history" {
  let t = native_chat(951.0, 669.0, true, side=84.0, mode="chat-tabs-side")
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  assert_eq(side_now(r), (["s-c1", "jobs"], "jobs"))
  assert_eq(nav_icon_of(t, "page/chat/history", field="title"), Some(@sf.t("web-pages.chat.closePanel")))
  t.post(@hostapi.system_channel, "{\"nav\":\"page/chat/history\"}")
  t.run_for(@ui.move_most_ms)
  assert_eq(side_now(r), ([], ""))
  assert_eq(nav_icon_of(t, "page/chat/history", field="title"), Some(@sf.t("web-pages.chat.openPanel")))
  t.post(@hostapi.system_channel, "{\"nav\":\"page/chat/history\"}")
  t.run_for(@ui.move_most_ms)
  assert_eq(side_now(r), (["s-c1"], "s-c1"))
}

///|
/// The single workspace entry retains unread and invitation indicators.
fn workspaces_dot(t : @ui.Tester) -> Bool raise {
  guard @json.parse(t.nav_said()) is Object(bar) else { fail("no bar") }
  guard bar.get("floating") is Some(Array(items)) else { fail("no floating controls") }
  for i in items {
    let item = field(Some(i), "item")
    if text(item, "id") == "workspace-switch" {
      return field(item, "dot") is Some(True)
    }
  }
  fail("no workspace heading")
}

///|
test "an iPhone Duo: the workspace's button has a dot while another workspace has something waiting, none while nothing does" {
  // (the fixture's: ws2's chats unread, the others' mark `done`)
  let t = native_chat(951.0, 669.0, true, side=84.0)
  assert_true(workspaces_dot(t))
  new_run()
  let base = fixture("chat")
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      if name == "workspaceMarks" {
        { value: Some({ "workspaces": { "ws1": {}, "ws2": {} } }), error: None, version: 1 }
      } else {
        (base.topic)(name, params)
      }
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let q = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=951.0, h=669.0, platform=1)
  q.set_nav_able(true)
  q.post(@hostapi.system_channel, "{\"bars\":{\"top\":0,\"bottom\":20,\"left\":0,\"right\":84}}")
  q.run_for(@ui.move_most_ms)
  assert_false(workspaces_dot(q))
}

///|
/// The composer's width in the chat's page (the page's own width less its room), as last drawn.
fn composer_w(t : @ui.Tester) -> Double {
  match t.boxes().search_by(fn(b) { b.kind == "editor" }) {
    Some(i) => t.boxes()[i].w
    None => 0.0
  }
}

///|
test "an iPhone Duo on its side: details come over without taking another strip from chat beside the system column" {
  let (w, h, side) = (951.0, 669.0, 84.0)
  let t = native_chat(w, h, true, side~, mode="chat-info", corner=59.0)
  let src = fixture("chat-info")
  let from = composer_w(t)
  open_link_in(src, "https://still.fail/o/ws1/st1/s-c1?service=j-web")
  // (the move's first frame: the page as wide as it was, near enough, the panel coming in from the window's edge)
  t.run_for(@ui.frame_period_default)
  let first = composer_w(t)
  t.run_for(@ui.move_most_ms)
  let to = composer_w(t)
  assert_true((to - from).abs() < 0.5, msg="chat keeps its width: \{from} to \{to}")
  assert_true((first - from).abs() < 0.5, msg="no intermediate squeeze: \{from} to \{first}")
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Panel)
}

///|
test "an iPhone Duo on its side: the side panel closed while in use slides off as the page comes back, showing what it showed, then goes" {
  let (w, h, side) = (951.0, 669.0, 84.0)
  let t = native_chat(w, h, true, side~, mode="chat-info", corner=59.0)
  let src = fixture("chat-info")
  open_link_in(src, "https://still.fail/o/ws1/st1/s-c1?service=j-web")
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Panel)
  let (x0, _, _, _) = t.holes()[0]
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "", station_name: "" }
  side_change(r, "clear", None)
  t.run_for(@ui.move_most_ms / 2.0)
  // on its way: the page coming back, the panel's page still drawn, further right
  let holes = t.holes()
  assert_eq(holes.length(), 1, msg="the panel's page as it goes (\{@sfdesk.wide.tape_at.get()})")
  assert_true(holes[0].0 > x0 + 100.0 && holes[0].0 < w, msg="from \{x0}, on its way at \{holes[0].0}")
  t.run_for(@ui.move_most_ms * 2.0)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
  // there: gone
  assert_eq(t.holes().length(), 0)
  assert_eq(t.corner_faults(), [])
}

///|
test "an iPhone Duo: switching workspace from an open chat never restores the old workspace's last chat" {
  new_run()
  let base = fixture("chat")
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      if name == "workspaceMarks" {
        topic_as_read(name, params, { value: Some({ "workspaces": {
          "ws1": { "chat": { "station": "ws1/st1", "key": "s-c1" } },
          "ws2": {},
        } }), error: None, version: 1 })
      } else {
        (base.topic)(name, params)
      }
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=951.0, h=669.0, platform=1)
  t.set_nav_able(true)
  t.keep_parts(true)
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() is Chat(r) && r.station == "ws1/st1")
  t.post(@hostapi.system_channel, "{\"nav\":\"ws/ws2\"}")
  t.run_for(@ui.move_most_ms)
  assert_eq(app.picked.get(), "ws2")
  assert_true(app.nav.top() == NewChat, msg="the new workspace has no last chat")
}

///|
test "Duo HTML preview exposes close source and download in native bars" {
  let t = native_chat(951.0, 669.0, true, side=84.0, mode="chat-preview-html")
  t.run_for(@ui.move_most_ms)
  for id in ["lead/over/close", "over/source", "over/download"] {
    assert_true(t.nav_said().contains(id), msg=t.nav_said())
  }
  t.post(@hostapi.system_channel, "{\"nav\":\"over/source\"}")
  t.draw()
  assert_true(viewer.get().unwrap().source)
  t.post(@hostapi.system_channel, "{\"nav\":\"over/source\"}")
  t.draw()
  assert_false(viewer.get().unwrap().source)
  t.post(@hostapi.system_channel, "{\"nav\":\"lead/over/close\"}")
  t.run_for(@ui.move_most_ms)
  assert_true(viewer.get() is None)
}

///|
test "Duo new chat with a long draft and attachment keeps send above the keyboard" {
  new_run()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=951.0, h=669.0, platform=1)
  t.set_nav_able(true)
  t.post(@hostapi.system_channel, "{\"bars\":{\"top\":0,\"bottom\":20,\"left\":0,\"right\":84}}")
  t.run_for(@ui.move_most_ms)
  t.post(@hostapi.system_channel, "{\"nav\":\"new\"}")
  t.run_for(@ui.move_most_ms)
  t.tap_text("做任何事")
  let draft = @sfbase.writing(src, "new:ws1")
  @sfbase.writing_add(src, draft, "ws1/st1", "照片.png", png_head())
  t.type_text("这是一段很长的输入，需要在键盘弹出时仍能看到发送按钮。\n".repeat(20))
  // (said from the window's foot down the side, ios_app.m ime_over: its top at 369)
  t.set_ime_inset(300.0)
  t.resize(951.0, 369.0)
  t.run_for(@ui.move_most_ms + @ui.move_most_ms)
  let send = t.semantics().filter(fn(s) { s.label == @sf.t("web-main.composer.send") })
  assert_eq(send.length(), 1)
  let (_, y, _, h) = send[0].rect
  assert_true(y >= 0.0 && y + h <= 369.5, msg="send at \{y}..\{y + h}")
}


///|
test "Duo inline HTML expanded uses the image viewer native bars and closes back to the chat" {
  let t = native_chat(951.0, 669.0, true, side=84.0, mode="chat-viz")
  viz_open_full("release.html", "ws1/st1", "s-c1", "work/s-c1/release.html", "s-c1")
  t.frame()
  t.frame()
  let said = t.nav_said()
  for id in ["lead/over/close", "over/download", "\"bare\":true"] {
    assert_true(said.contains(id), msg=said)
  }
  assert_false(said.contains("page/chat/"), msg=said)
  assert_true(t.find("返回") is None)
  let opened = opened_views(t, 2)
  let page = opened[opened.length() - 1]
  guard view_rect(t, page) is Some((x, _, w, _)) else { fail("no HTML page") }
  assert_true(x + w <= 951.0 - 84.0, msg="HTML ends at \{x + w}")
  t.post(@hostapi.system_channel, "{\"nav\":\"lead/over/close\"}")
  t.frame()
  t.frame()
  assert_true(@sfbase.viz_full.get() is None)
  assert_true(t.nav_said().contains("\"bare\":false"))
}

///|
test "Duo workspace heading opens the existing panel without a duplicate menu" {
  let t = native_chat(951.0, 669.0, true, side=84.0)
  assert_false(t.nav_said().contains("act/workspaces"))
  assert_true(t.nav_said().contains("workspace-switch"), msg=t.nav_said())
  assert_false(t.nav_said().contains("workspaces/manage"))
  t.frame()
  assert_true(t.nav_said().contains("workspace-switch"), msg=t.nav_said())
  t.post(@hostapi.system_channel, "{\"nav\":\"workspace-switch\"}")
  t.frame()
  assert_true(t.nav_said().contains("workspace-switch"))
  assert_true(t.nav_said().contains("sidebar/search"))
  t.run_for(@kit.pop_ms / 2.0)
  assert_true(t.nav_said().contains("workspace-switch"))
  assert_true(t.nav_said().contains("sidebar/search"))
  t.run_for(@ui.move_most_ms)
  assert_true(@sf.presenting())
  let panels = t.semantics().filter(fn(s) { !s.hidden && s.role == @ui.Role::Dialog })
  assert_true(panels.length() > 0)
  for p in panels {
    assert_true(p.rect.3 < 400.0, msg="short workspace list stretched to \{p.rect.3}")
  }
  assert_true(t.nav_said().contains("workspace-switch"))
  assert_true(t.nav_said().contains("sidebar/search"))
  assert_true(t.nav_said().contains("sidebar/filter/mine"))
  assert_true(t.nav_said().contains("\"blocked\":true"))
  @sf.close_all_presented()
  t.frame()
  t.run_for(@kit.pop_out_ms / 2.0)
  for id in ["workspace-switch", "sidebar/search", "sidebar/filter/mine"] {
    assert_true(t.nav_said().contains(id), msg="missing during panel exit: \{id}")
  }
  assert_true(t.nav_said().contains("\"blocked\":true"))
  t.run_for(@ui.move_most_ms)
  assert_true(t.nav_said().contains("workspace-switch"))
  assert_false(t.nav_said().contains("\"blocked\":true"))
}

///|
test "Duo glass search opens the finder and hides the sidebar's native controls" {
  let t = native_chat(951.0, 669.0, true, side=84.0)
  assert_true(t.nav_said().contains("sidebar/search"))
  assert_true(t.nav_said().contains("sidebar/filter/mine"))
  t.post(@hostapi.system_channel, "{\"nav\":\"sidebar/filter/mine\"}")
  t.run_for(@ui.move_most_ms)
  assert_eq(app.filters.get("ws1"), Some("mine"))
  t.post(@hostapi.system_channel, "{\"nav\":\"sidebar/search\"}")
  t.run_for(@ui.move_most_ms)
  assert_true(@sfdesk.switcher_open())
  assert_false(t.nav_said().contains("sidebar/search"))
  assert_false(t.nav_said().contains("workspace-switch"))
}

///|
test "Duo sidebar glass circles share a baseline and keep their inset with a large outer corner" {
  for size in [(951.0, 669.0, 84.0), (669.0, 951.0, 0.0)] {
    let mut first_x : Double? = None
    for corner in [28.0, 59.0] {
      let t = native_chat(size.0, size.1, true, side=size.2, corners=[corner, corner, corner, corner])
      let spec = @json.parse(t.nav_said())
      let circles = items(Some(spec), "floating")
      assert_eq(circles.length(), 3)
      let x = number(Some(circles[0]), "x")
      guard t.words().filter(fn(word) { word.0 == "今天" }) is [(_, heading_x, _, _, _, _), ..] else {
        fail("day heading not drawn")
      }
      assert_true((x - heading_x).abs() < 0.5, msg="glass edge \{x}, day heading \{heading_x}")
      match first_x {
        Some(was) => assert_true((x - was).abs() < 0.5, msg="workspace shifted from \{was} to \{x}")
        None => first_x = Some(x)
      }
      let y = number(Some(circles[0]), "y")
      for circle in circles {
        assert_true((number(Some(circle), "y") - y).abs() < 0.5)
        if text(field(Some(circle), "item"), "id") != "workspace-switch" {
          assert_eq(number(Some(circle), "w"), number(Some(circle), "h"))
        }
      }
    }
  }
}

///|
test "an iPhone Duo: the system's bars told as the app starts put the sidebar where they have it at once, moving nothing" {
  let t = native_chat(951.0, 669.0, true, side=84.0)
  assert_true(@sf.native_on())
  assert_true(!t.moving().join("\n").contains("a move of"), msg=t.moving().join("\n"))
}

///|
test "Duo files and settings have no legacy workspace switch" {
  let t = native_chat(951.0, 669.0, true, side=84.0)
  for id in ["place/files", "settings"] {
    t.post(@hostapi.system_channel, "{\"nav\":\"\{id}\"}")
    t.run_for(@ui.move_most_ms)
    assert_false(t.nav_said().contains("act/workspaces"))
    assert_false(t.nav_said().contains("lead/workspaces"))
  }
}

///|
test "non-native workspace panels retain their existing tall layout" {
  for platform in [0, 2] {
    let t = native_chat(951.0, 669.0, false, platform~)
    @sfpages.open_workspaces(fixture("chat"), At(32.0, 16.0, 150.0, 38.0))
    t.run_for(@ui.move_most_ms)
    let panels = t.semantics().filter(fn(s) { !s.hidden && s.role == @ui.Role::Dialog })
    assert_true(panels.length() > 0)
    assert_true(panels[0].rect.3 >= 450.0, msg="non-native panel height changed: \{panels[0].rect.3}")
  }
}

///|
test "Duo narrow chat reminder puts dismiss below its words" {
  let t = native_chat(469.0, 681.0, true, side=84.0, mode="chat-need")
  @sfdesk.wide.tape_ask.set(Some(@sfdesk.TapePane::Page))
  t.frame()
  t.run_for(@ui.move_most_ms)
  let (_, y) = t.find_last("忽略").unwrap()
  let (_, sy, _, sh) = t.rect_of(@sffixture.need_state.2).unwrap()
  assert_true(y >= sy + sh, msg="dismiss below the complete reminder text")
}

///|
test "Duo short system column keeps the complete chat menu reachable" {
  let t = native_chat(469.0, 681.0, true, side=84.0)
  @sfdesk.wide.tape_ask.set(Some(@sfdesk.TapePane::Page))
  t.frame()
  t.run_for(@ui.move_most_ms)
  assert_eq(nav_icon_of(t, "page/chat/info"), Some(@sf.icon_path("info")))
  t.post(@hostapi.system_channel, "{\"nav\":\"page/chat/info\"}")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find(@sf.t("web-pages.chat.info.created")) is Some(_))
}

///|
test "Duo chat menu covers sidebar glass until its exit finishes" {
  let t = native_chat(669.0, 951.0, true)
  assert_true(t.nav_said().contains("workspace-switch"))
  t.post(@hostapi.system_channel, "{\"nav\":\"page/chat/info\",\"at\":[270,0,44,44]}")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find(@sf.t("web-pages.chat.info.created")) is Some(_))
  for id in ["workspace-switch", "sidebar/search", "sidebar/filter"] {
    assert_false(t.nav_said().contains(id), msg="covered control: \{id}")
  }
  t.post(@hostapi.system_channel, "{\"nav\":\"page/chat/info\",\"at\":[270,0,44,44]}")
  t.frame()
  t.run_for(@kit.pop_out_ms / 2.0)
  for id in ["workspace-switch", "sidebar/search", "sidebar/filter"] {
    assert_false(t.nav_said().contains(id), msg="control returned during exit: \{id}")
  }
  t.run_for(@ui.move_most_ms)
  assert_true(t.nav_said().contains("workspace-switch"))
}

///|
test "Duo screen panels toggle through native events, switch without stacking and light the active action" {
  new_run()
  let src = fixture("screen-live")
  open_fixture_over("screen-live", src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=951.0, h=669.0, platform=1)
  t.set_nav_able(true)
  t.post(@hostapi.system_channel, "{\"bars\":{\"top\":0,\"bottom\":20,\"left\":0,\"right\":84}}")
  t.run_for(@ui.move_most_ms)
  for id in ["center", "stats", "people"] {
    t.post(@hostapi.system_channel, "{\"nav\":\"over/screen-\{id}\",\"at\":[879,480,48,48]}")
    t.run_for(@ui.move_most_ms)
    let panels = t.semantics().filter(fn(s) { !s.hidden && s.role == @ui.Role::Dialog })
    assert_eq(panels.length(), 1)
    let (x, _, w, _) = panels[0].rect
    assert_true(x + w <= 867.0, msg="\{id}: panel \{x} + \{w}")
    assert_eq(@sf.native_over.active, ["over/screen-\{id}"])
    let bar = @json.parse(t.nav_said())
    let mut lit = false
    for group in items(Some(bar), "groups") {
      for item in items(Some(group), "items") {
        if text(Some(item), "id") == "over/screen-\{id}" { lit = flag(Some(item), "prominent") }
      }
    }
    assert_true(lit)
  }
  t.post(@hostapi.system_channel, "{\"nav\":\"over/screen-people\",\"at\":[879,480,48,48]}")
  t.run_for(@ui.move_most_ms)
  assert_false(@sf.presenter_visible())
  assert_eq(@sf.native_over.active, [])
}

///|
/// How long after it is opened the other chat's view is read (the test's core: past the most a page's coming is held
/// for, the chat then drawn with nothing read a while).
let other_chat_read_ms : Double = 3000.0

///|
test "an iPhone Duo on its side: another chat opened, its view read a while later: the chat's actions stay in the system's bars as they were till its own come, never taken away between" {
  reset()
  let base = fixture("chat")
  // (the other chat's view read other_chat_read_ms after it is asked for: past the most its coming is held for)
  let read = @signals.signal(false)
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      if Json::object(params).stringify().contains("s-c2") && !read.get() {
        return { value: None, error: None, version: 0 }
      }
      (base.topic)(name, params)
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=951.0, h=669.0, platform=1, nav_able=true)
  t.post(@hostapi.system_channel, "{\"bars\":{\"top\":0,\"bottom\":20,\"left\":0,\"right\":84}}")
  t.run_for(@ui.move_most_ms)
  let before = t.nav_said()
  assert_true(nav_icon_of(t, "page/chat/archive") is Some(_), msg=before)
  @sffixture.fix_later(other_chat_read_ms, fn() { read.set(true) })
  t.tap_text("首页的列表改成按天分组")
  // (each frame till it is read: the same bars handed, the system's buttons left as they are)
  while !read.get() {
    t.frame()
    if !read.get() {
      assert_eq(t.nav_said(), before)
    }
  }
  // (read: its own, the archive gone where it has nothing to archive)
  t.run_for(@ui.move_most_ms)
  assert_true(nav_icon_of(t, "page/chat/info") is Some(_), msg=t.nav_said())
  assert_true(nav_icon_of(t, "page/chat/history") is Some(_), msg=t.nav_said())
  assert_true(nav_icon_of(t, "page/chat/archive") is None, msg=t.nav_said())
}

///|
/// A picture looked at on an iPhone Duo (`w` by `h`, its column `side` wide), marking begun from the system's bars (their
/// 标注图片), then its own bar's 取消 tapped (`frames`: the frame after drawn before what is looked at; else none):
/// whether the system's bars were on as it marked, whether 标注图片 was handed them then, how many of the window's
/// tree's own buttons said 取消 there were; whether it was still marking as the finger lifted, and after; whether
/// 标注图片 is handed them again, and how many of the tree's buttons say 取消 then.
fn duo_marking(w : Double, h : Double, side : Double, frames : Bool) -> ((Bool, Bool, Int), (Bool, Bool), (Bool, Int)) raise {
  let t = native_chat(w, h, true, side~, mode="chat-preview-image")
  t.run_for(@ui.move_most_ms)
  assert_true(@sf.native_on(), msg="the system's bars")
  assert_true(t.nav_said().contains("over/mark"), msg=t.nav_said())
  t.post(@hostapi.system_channel, "{\"nav\":\"over/mark\"}")
  t.draw()
  assert_true(marking.on, msg="marking")
  let cancel = pv("common.cancel")
  let cancels = fn() {
    @ui.view_tree().unwrap().said_order().filter(fn(s) {
      match s.said {
        Some(said) => said.role == Button && said.label == cancel
        None => false
      }
    }).length()
  }
  let marked = (@sf.native_on(), t.nav_said().contains("over/mark"), cancels())
  let (x, y, bw, bh) = t.get(Button, label=cancel).rect
  t.touch(0, x + bw / 2.0, y + bh / 2.0)
  t.touch(2, x + bw / 2.0, y + bh / 2.0)
  let let_go = marking.on
  if frames {
    t.draw()
  }
  let left = (let_go, marking.on)
  t.run_for(@ui.move_most_ms)
  (marked, left, (t.nav_said().contains("over/mark"), cancels()))
}

///|
test "a picture marked on an iPhone Duo, upright and on its side: its own bar the window's tree's while it marks beside the system's; 取消 leaves marking as the finger lifts, the frames drawn after or none, 标注图片 handed back to the system's bars, the bar's nodes gone" {
  for duo in [(390.0, 844.0, 0.0), (951.0, 669.0, 84.0)] {
    let (w, h, side) = duo
    for frames in [true, false] {
      let (marked, left, back) = duo_marking(w, h, side, frames)
      let at = "\{w} frames \{frames}"
      assert_eq(left, (false, false), msg="\{at}: marking left as the finger lifts")
      assert_eq(marked, (true, false, 1), msg="\{at}: marking beside the system's bars, its 取消 the tree's")
      assert_eq(back, (true, 0), msg="\{at}: 标注图片 handed back, no 取消 of the tree's")
    }
  }
}

///|
test "a picture looked at and marked on an iPhone Duo on its side: laid out clear of the system's column (its ground under it), the picture in the middle of what is left, what the marking bar's own presses all of it clear of the column" {
  let t = native_chat(951.0, 669.0, true, side=84.0, mode="chat-preview-image")
  t.run_for(@ui.move_most_ms)
  assert_true(@sf.native_on(), msg="the system's bars")
  assert_eq(@sf.native_clear(), 84.0)
  let clear = 951.0 - 84.0
  // (the picture in the middle of what is clear of the column)
  let (x, _, w, _) = viewer.get().unwrap().zoom.rect().unwrap()
  assert_true((x + w / 2.0 - clear / 2.0).abs() < 0.5, msg="its middle \{x + w / 2.0}, what is clear's \{clear / 2.0}")
  t.post(@hostapi.system_channel, "{\"nav\":\"over/mark\"}")
  t.run_for(@ui.move_most_ms)
  assert_true(marking.on && @sf.native_on(), msg="marking beside the system's bars")
  // (each of the bar's own and the tools', whole, clear of the column)
  let pressed = t.semantics().filter(fn(s) { s.role == @ui.Role::Button && !s.hidden && s.rect.2 > 0.0 })
  assert_true(pressed.iter().any(fn(s) { s.label == pv("common.cancel") }), msg="取消 there")
  for s in pressed {
    let (bx, _, bw, _) = s.rect
    assert_true(bx + bw <= clear + 0.5, msg="\{s.label} under the system's column: \{s.rect}")
  }
}

///|
test "an iPhone Duo on its side: the sidebar's edge held by a finger that wanders a little, then dragged; one that wanders off is not" {
  let t = native_chat(951.0, 669.0, true, side=84.0)
  let (x, _, w, _) = t.get(Separator, label="调整侧边栏宽度").rect
  let x = x + w / 2.0
  let from = @sfdesk.wide.side_w.get()
  // (a finger held still is never quite still: 6 across and down while it is held, within @ui.hold_slop; the width
  // goes as far as the finger from where it went down)
  t.press_at(x, 300.0)
  t.run_for(@ui.tap_indication_ms)
  t.move(x + 6.0, 306.0)
  t.run_for(@ui.long_press_ms)
  t.move(x + 40.0, 306.0)
  t.move(x + 60.0, 306.0)
  t.release(x + 60.0, 306.0)
  t.draw()
  assert_eq(@sfdesk.wide.side_w.get(), from + 60.0)
  // past it before it is held: not the edge's
  let x = x + 60.0
  t.press_at(x, 300.0)
  t.run_for(@ui.tap_indication_ms)
  t.move(x + 12.0, 300.0)
  t.run_for(@ui.long_press_ms)
  t.move(x + 60.0, 300.0)
  t.release(x + 60.0, 300.0)
  t.draw()
  assert_eq(@sfdesk.wide.side_w.get(), from + 60.0)
}
