// An iPhone Duo's frame (sfdesk's rail_native.mbt, the library's native_bars.mbt): where the system lays out the app's
// tabs and its actions itself, the app hands them over and draws none of its own (no rail, no bottom bar), its cards
// across in every width; everywhere else nothing of it, the frame as it was.

///|
/// The fixture's chat (or `mode`'s) open in a window `w` × `h` of iOS (platform 1), the system's own bars or not (`able`), its column
/// down the window's trailing edge `side` wide (0: upright, across).
fn native_chat(w : Double, h : Double, able : Bool, side? : Double = 0.0, mode? : String = "chat") -> @ui.Tester {
  reset()
  let src = fixture(mode)
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w~, h~, platform=1)
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
