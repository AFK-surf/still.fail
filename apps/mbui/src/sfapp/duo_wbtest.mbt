// An iPhone Duo's frame (sfdesk's rail_native.mbt, the library's native_bars.mbt): where the system lays out the app's
// tabs and its actions itself, the app hands them over and draws none of its own (no rail, no bottom bar), its cards
// across in every width; everywhere else nothing of it, the frame as it was.

///|
/// The fixture's chat (or `mode`'s) open in a window `w` × `h` of iOS (platform 1), the system's own bars or not (`able`), its column
/// down the window's trailing edge `side` wide (0: upright, across), the screen's corners `corner` round.
fn native_chat(
  w : Double,
  h : Double,
  able : Bool,
  side? : Double = 0.0,
  mode? : String = "chat",
  corner? : Double = 0.0,
) -> @ui.Tester {
  reset()
  let src = fixture(mode)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w~, h~, platform=1, window_corner=corner)
  t.set_nav_able(able)
  t.post(@hostapi.system_channel, "{\"bars\":{\"top\":0,\"bottom\":20,\"left\":0,\"right\":\{side}}}")
  t.run_for(@ui.nav_push_ms)
  t
}

///|
test "an iPhone Duo on its side: the places and the chat's actions handed to the system's bars, the app drawing no rail nor tabs of its own, the cards beside the column" {
  let t = native_chat(951.0, 669.0, true, side=84.0)
  // (at rest: what is drawn held to the corner rule, the list's filter concentric with its card's corner)
  t.run_for(@ui.nav_push_ms)
  t.assert_idle()
  let said = t.nav_said()
  for id in ["place/chats", "place/files", "place/stations", "act/attention", "act/workspaces", "\"new\"", "page/info", "page/who/agent/"] {
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
    if !s.hidden && s.role == @ui.Role::Button && s.label != "" && w > 0.0 && x + w > 951.0 - 84.0 + 0.5 {
      fail("\{s.label} under the system's column: \{s.rect}")
    }
  }
}

///|
test "an iPhone Duo upright: the same frame, the actions across the top (the bell at its lead)" {
  let t = native_chat(669.0, 951.0, true)
  let said = t.nav_said()
  assert_true(said.contains("lead/attention"))
  assert_true(said.contains("lead/workspaces"))
  assert_true(@sf.native_on())
  assert_false(@sf.native_side())
  assert_eq(@sf.native_clear(), 0.0)
  assert_false(bar_tabs(t))
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
  t.run_for(fly_open_ms)
  let said = t.nav_said()
  for id in ["\"bare\":true", "\"title\":\"界面草图.png\"", "lead/over/close", "over/mark", "over/copy", "over/download"] {
    if !said.contains(id) {
      fail("the bars handed hold no \{id}: \{said}")
    }
  }
  // (none of the tabs' own buttons while it is up: the chat's, the bell)
  assert_false(said.contains("page/info"))
  // (its name in the system's bar, not in one of its own)
  assert_true(t.find("界面草图.png") is None)
  // (the picture and its ways before and after clear of the system's column)
  for s in t.semantics() {
    let (x, _, w, _) = s.rect
    if !s.hidden && s.role == @ui.Role::Button && s.label != "" && w > 0.0 && x + w > 951.0 - 84.0 + 0.5 {
      fail("\{s.label} under the system's column: \{s.rect}")
    }
  }
  match viewer.val.unwrap().zoom.rect() {
    Some((x, _, w, _)) => assert_true(x + w <= 951.0 - 84.0 + 0.5)
    None => fail("no picture laid out")
  }
  // closed from the system's bar: the tabs back
  t.post(@hostapi.system_channel, "{\"nav\":\"lead/over/close\"}")
  t.run_for(fly_close_ms)
  assert_true(viewer.val is None)
  assert_true(t.nav_said().contains("\"bare\":false"))
}

///|
test "a picture looked at elsewhere: its own bar, as it was" {
  let t = native_chat(951.0, 669.0, false, mode="chat-preview-image")
  t.run_for(fly_open_ms)
  assert_false(@sf.native_over.up)
  assert_true(t.find("界面草图.png") is Some(_))
}

///|
test "an iPhone Duo on its side, the soft keyboard up: the composer whole over it, its send button too" {
  let t = native_chat(951.0, 669.0, true, side=84.0)
  // (the home indicator's room as the Duo's outer screen has it on its side: 34)
  t.post(@hostapi.system_channel, "{\"bars\":{\"top\":0,\"bottom\":34,\"left\":0,\"right\":84}}")
  t.tap_text("发消息")
  // the keyboard up: the window laid out above it plus the bars' foot, as the host lays it out (ios_app.m ime_over)
  let kb = 280.0
  t.set_ime_inset(kb)
  t.resize(951.0, 669.0 - kb)
  t.run_for(@ui.nav_push_ms)
  let keyboard_top = 669.0 - kb - 34.0
  let send = t.semantics().filter(fn(s) { s.label == @sf.t("web-main.composer.send") })
  assert_eq(send.length(), 1)
  let (_, y, _, h) = send[0].rect
  assert_true(y + h <= keyboard_top + 0.5, msg="send at \{y}..\{y + h}, keyboard at \{keyboard_top}")
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
    t.run_for(@ui.nav_push_ms)
    // (folded, the cards across with the list's in view: the page's brought in, as a finger does)
    if size.0 < 600.0 {
      t.drag(400.0, 330.0, 140.0, 330.0)
      t.run_for(@ui.nav_push_ms * 2.0)
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
    t.run_for(@ui.nav_push_ms)
    if w < 600.0 {
      t.drag(400.0, 330.0, 140.0, 330.0)
      t.run_for(@ui.nav_push_ms * 2.0)
    }
    guard composer_and_page(t) is Some((b, p)) else { fail("no composer in a page") }
    let near = fn(x : Double, y : Double) { (x - y).abs() < 0.05 }
    assert_true(near(p.y + p.h, h - @sf.native_in), msg="\{size}: the page's foot at \{p.y + p.h}")
    assert_true(near(b.h, a), msg="\{size}: the composer \{b.h} high")
    assert_true(near(b.y + b.h / 2.0, ay + a / 2.0), msg="\{size}: the composer's middle at \{b.y + b.h / 2.0}")
    let at = (b.x - p.x, p.y + p.h - (b.y + b.h))
    assert_true(near(at.0, at.1), msg="\{size}: the composer \{at} from the page's side and foot")
    assert_true(near(at.1, @sf.capsule_in(p.radii.3, b.h)), msg="\{size}: not concentric with \{p.radii.3}")
    assert_eq(t.corner_faults(), [])
  }
}

///|
test "an iPhone Duo folded, its outer screen: the bell and the workspaces in the system's short column, a page's actions its own" {
  let t = native_chat(466.0, 678.0, true, side=70.0)
  let said = t.nav_said()
  // (one of the app's own in each of the column's bars is all it shows: the bell the toolbar's, the workspaces the
  // navigation bar's)
  assert_true(said.contains("act/attention"))
  assert_true(said.contains("lead/workspaces"))
  assert_false(said.contains("page/"))
}

///|
test "an iPhone Duo: a tab left in one workspace and come back to in another shows the other's, not the chat open in the first" {
  let t = native_chat(951.0, 669.0, true, side=84.0)
  let tap = fn(id : String) {
    t.post(@hostapi.system_channel, "{\"nav\":\"\{id}\"}")
    t.run_for(@ui.nav_push_ms)
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
