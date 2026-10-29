// A chat's agent and the station it runs on in the wide frame's bar (sfdesk's chat_page.mbt agent_tile): with keyboard
// and mouse each half pressed for its own, each its card under the pointer; with touch one tile, as it is drawn: a tap
// its history's, a hold both cards in one (the user, 2026-10-27: 它们是一体的).

///|
test "the joined maker's hover ground is uncovered and square at the seam" {
  reset()
  let src = fixture("chat-info")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=900.0, platform=0)
  t.run_for(@ui.move_most_ms)
  t.frame()
  let tiles = t.all(Button).filter(fn(s) { s.label.has_suffix("的执行历史") })
  assert_true(tiles.length() == 1)
  let (x, y, w, h) = tiles[0].rect
  t.move(x + w / 2.0, y + h / 2.0)
  t.frame()
  let grounds = t.drawn_rect_corners().filter(fn(r) {
    r.0 == x && r.1 == y && r.2 == w && r.3 == h
  })
  assert_true(grounds.length() == 1, msg="the maker paints no second ground over its hover")
  let (_, _, _, _, _, corners) = grounds[0]
  assert_true(corners.0 > 0.0 && corners.3 > 0.0)
  assert_true(corners.1 == 0.0 && corners.2 == 0.0, msg="both corners at the seam are square")
}

///|
/// The fixture's chat open in a tablet's wide frame (touch), and its agent's tile: the one button saying its history.
fn tile_on_tablet() -> (@ui.Tester, @ui.SemNode) raise {
  reset()
  let src = fixture("chat-info")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=900.0, platform=2)
  t.run_for(@ui.move_most_ms)
  t.frame()
  let tiles = t.all(Button).filter(fn(s) { s.label.has_suffix("的执行历史") })
  assert_true(tiles.length() == 1, msg="one tile, pressed whole")
  (t, tiles[0])
}

///|
test "a tablet's agent tile: pressed whole, a tap opens its history beside the chat" {
  let (t, tile) = tile_on_tablet()
  let (x, y, w, h) = tile.rect
  // (as wide as both halves: the station's no press of its own)
  assert_true(w >= 40.0, msg="the tile whole, \{w} wide")
  t.tap(x + w / 2.0, y + h / 2.0)
  t.frame()
  t.frame()
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  assert_true(side_now(r).1 == "s-c1", msg="its history in front beside the chat")
}

///|
test "a tablet's agent tile: held, its card and its station's as one, under it" {
  let (t, tile) = tile_on_tablet()
  let (x, y, w, h) = tile.rect
  t.press_at(x + w / 2.0, y + h / 2.0)
  t.run_for(@ui.long_press_ms)
  t.release(x + w / 2.0, y + h / 2.0)
  t.frame()
  t.run_for(@sfpages.hover_open_ms)
  // the station's card under the agent's: where to go on from it
  assert_true(t.find("机器详情") is Some(_), msg="the station's card")
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  assert_true(side_now(r).0.length() == 0, msg="a hold is no tap: no history opened")
}
