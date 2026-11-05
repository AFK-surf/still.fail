///|
test "a chat keeps its editor through notices and copy choices, then sends once from the retained field" {
  @sfbase.reset()
  composing_reset()
  @sf.set_words(@sfbase.fill)
  let r : ChatRef = { station: "ws/st", session: "chat", title: "Chat", station_name: "Studio" }
  let base = @sfbase.chat_view_made({ "thread": { "id": 1 }, "cc": [
    { "thread": 2, "via": "slack", "place": "项目", "on": true },
    { "thread": 3, "via": "feishu", "place": "团队", "on": false },
  ] })
  let state = @signals.signal(base, same=fn(_, _) { false })
  let calls : Array[(String, Json)] = []
  let restore : Ref[((Result[Json, Json]) -> Unit)?] = Ref(None)
  let src = @sfbase.made_source(call=fn(name, params, done) {
    calls.push((name, params))
    if name == "chat.archive" { restore.val = Some(done) }
    else if name == "composer.take" { done(Ok({ "text": "保留草稿", "attachments": [], "quotes": [], "uploads": [] })) }
    else { done(Ok({})) }
  })
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=390.0, h=900.0, platform=2, stable=false)
  let built = Ref(0)
  let made : Ref[ChatComposerNode?] = Ref(None)
  let sent : Array[String] = []
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    built.val += 1
    root.lies_along(Is(End)) |> ignore
    made.val = Some(chat_composer_node(root, src, r, fn() { Some(state.get()) }, fn() { 12.0 }, fn() { 900.0 },
      fn() { 12.0 }, fn() { composer_alone }, fn(row) { sent.push(row) }))
  })
  t.draw()
  let n = made.val.unwrap()
  let w = n.composer.writing
  let id = n.composer.field.id()
  w.field.focus()
  t.type_text("保留草稿")
  t.draw()
  w.field.pick(1, 3)
  t.click(Button, label="抄送 项目")
  let choice = t.get(MenuItemCheckbox, label="团队")
  let tree = @ui.view_tree().unwrap()
  let chosen = tree.said_order().filter(fn(s) { s.said is Some({ label: "团队", .. }) })[0].id
  let (cx, cy, cw, ch) = choice.rect
  assert_eq(tree.target_at(cx + cw / 2.0, cy + ch / 2.0), @view.Pressed(chosen),
    msg="the copy choice is in its popup's input room: \{choice.rect}")
  t.click(MenuItemCheckbox, label="团队")
  assert_true(composer_cc_open())
  assert_eq(calls.filter(fn(c) { c.0 == "chat.cc" }).length(), 1, msg="calls=\{calls}, thread=\{state.get().thread}")
  assert_eq(w.field.selection(), (1, 3))
  t.key(@ui.key_escape)
  state.set({ ..base, archived: true, offline: true })
  // Read the notice at its declared entrance end, not at alpha zero on its cause's frame.
  t.run_for(@sf.waiting_in.fade_spec.duration(0.0, 1.0, 0.0))
  assert_true(t.get(Button, label=@sf.t("web-main.archived.restore")).disabled)
  state.set({ ..base, archived: true })
  t.draw()
  t.click(Button, label=@sf.t("web-main.archived.restore"))
  assert_eq(calls.filter(fn(c) { c.0 == "chat.archive" }).length(), 1)
  assert_true(t.get(Button, label=@sf.t("web-main.archived.restore")).disabled)
  (restore.val.unwrap())(Err({ "message": "暂时不能还原" }))
  t.draw()
  assert_true(t.find("暂时不能还原") is Some(_))
  state.set({ ..base, cache_cold: Some(("agent", "上下文已过期", "重新读取需要一些时间", false)) })
  t.run_for(@sf.waiting_in.fade_spec.duration(0.0, 1.0, 0.0))
  t.click(Button, label=@sf.t("web-main.chat.goOn"))
  let fresh = t.get(MenuItemRadio, label=@sf.t("web-main.chat.afresh"))
  let fresh_id = tree.said_order().filter(fn(s) { s.said is Some({ label, .. }) && label == @sf.t("web-main.chat.afresh") })[0].id
  let (fx, fy, fw, fh) = fresh.rect
  assert_eq(tree.target_at(fx + fw / 2.0, fy + fh / 2.0), @view.Pressed(fresh_id),
    msg="the cache choice is in its popup's input room: \{fresh.rect}")
  t.click(MenuItemRadio, label=@sf.t("web-main.chat.afresh"))
  assert_eq(calls.filter(fn(c) { c.0 == "session.settings" }).length(), 1,
    msg="calls=\{calls}, open=\{composing.cold_open.get()}, all=\{t.semantics_dump()}")
  assert_eq((made.val.unwrap().composer.field.id(), w.text.get(), built.val), (id, "保留草稿", 1))
  state.set(base)
  t.draw()
  let lines = w.field.lines().unwrap()
  t.click(Button, label=@sf.t("web-main.composer.send"))
  assert_eq(calls.filter(fn(c) { c.0 == "chat.send" }).length(), 1)
  assert_eq(sent.length(), 1)
  let flight = @sfbase.send_flight.get().unwrap()
  assert_eq((flight.from_x, flight.from_y, flight.text), (lines.x, lines.y, "保留草稿"))
  assert_eq((made.val.unwrap().composer.field.id(), built.val), (id, 1))
}
