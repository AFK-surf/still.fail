// The new chat's choices as nodes (new_tools_node): asked from elsewhere (new_chat_ask: a menu's, a dialog's of the
// presets'), what each opens is open in that same event, no frame between, beside its capsule; a copy that only shows
// (asks=false) opens nothing so.

///|
fn tools_tester(asks : Bool) -> @ui.Tester {
  @sfbase.reset()
  new_opens.clear()
  new_chat_state.asked = ""
  @sf.set_words(@sfbase.fill)
  let src = @sfbase.made_source(call=fn(_, _, done) { done(Ok({})) })
  let w : Workspace = { id: "ws", name: "工作区", emoji: "", icon: "", email: "" }
  let v = Json::object({
    "preset": "",
    "presets": [{ "id": "p1", "name": "前端", "station": "ws/st", "stationName": "Willow" }],
    "stations": [{ "station": "ws/st", "name": "Willow" }],
  })
  let station = Json::object({ "station": "ws/st", "name": "Willow", "emoji": "", "icon": "" })
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=1280.0, h=800.0, platform=0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.box(fn(row) {
      row.offset(Is((200.0, 600.0))).width(Is(Some(700.0))).height(Is(Some(36.0))) |> ignore
      new_tools_node(row, src, fn() { Some(w) }, fn() { Some(v) }, fn() { Some(station) }, asks~)
    })
    |> ignore
    @sf.presented_nodes(root)
  })
  t.draw()
  t
}

///|
test "大屏: the presets' menu and the stations' panel asked from elsewhere: open as they are asked, no frame between" {
  let t = tools_tester(true)
  let before = @sf.last_presented()
  new_chat_ask("preset")
  assert_eq(@sf.last_presented() - before, 1, msg="the presets' menu presented as it was asked")
  assert_eq(new_chat_state.asked, "", msg="none of it left for an old view to take")
  t.run_for(@ui.move_most_ms)
  assert_true(t.query(Menu) is Some(_), msg="the menu shown")
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
  let before = @sf.last_presented()
  new_chat_ask("station")
  assert_eq(@sf.last_presented() - before, 1, msg="the stations' panel presented as it was asked")
}

///|
test "大屏: a copy of the choices that only shows: asked, opens nothing (the old view's to take, as ever)" {
  let _ = tools_tester(false)
  let before = @sf.last_presented()
  new_chat_ask("preset")
  assert_eq(@sf.last_presented(), before)
  assert_eq(new_chat_state.asked, "preset")
}
