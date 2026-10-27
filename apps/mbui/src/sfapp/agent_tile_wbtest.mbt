// A chat's agent and the station it runs on in the wide frame's bar (sfdesk's chat_page.mbt agent_tile): with keyboard
// and mouse each half pressed for its own; with touch one tile pressed whole, the agent's card whole over it (as a
// phone's chat bar opens it: AgentSheet.kt), the station it runs on and its history among where to go on.

///|
/// The fixture's chat open in a tablet's wide frame (touch), and its agent's tile: the one button whose name ends in
/// its station's.
fn tile_on_tablet() -> (@ui.Tester, @ui.SemNode) raise {
  reset()
  let src = fixture("chat-info")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=900.0, platform=2)
  t.run_for(@ui.nav_push_ms)
  t.frame()
  let tiles = t.all(Button).filter(fn(s) { s.label.has_suffix(" · Studio") })
  assert_true(tiles.length() == 1, msg="one tile, pressed whole")
  (t, tiles[0])
}

///|
test "a tablet's agent tile: pressed whole, the agent's card whole beside it, its station and history among its rows" {
  let (t, tile) = tile_on_tablet()
  // (no half of it pressed for its own)
  assert_true(t.all(Button).filter(fn(s) { s.label.has_suffix("的执行历史") }).length() == 0)
  let (x, y, w, h) = tile.rect
  t.tap(x + w / 2.0, y + h / 2.0)
  t.frame()
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  assert_true(@sf.presenting(), msg="its card")
  assert_true(t.find("Station") is Some(_), msg="the station it runs on")
  assert_true(t.find("历史") is Some(_), msg="its history")
  // its station: the station's card in its place
  t.tap_text("Station")
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  assert_true(@sf.presenting(), msg="the station's card")
  assert_true(t.find("机器详情") is Some(_))
}

///|
test "a tablet's agent tile: its card's 历史 opens the agent's history beside the chat" {
  let (t, tile) = tile_on_tablet()
  let (x, y, w, h) = tile.rect
  t.tap(x + w / 2.0, y + h / 2.0)
  t.frame()
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  t.tap_text("历史")
  t.frame()
  t.frame()
  assert_true(!@sf.presenting(), msg="its card gone")
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  assert_true(app.nav.top() == Chat(r), msg="the chat")
  assert_true(side_now(r).1 == "s-c1", msg="its history in front beside it")
}
