// A question (@sf.ask) on 大屏 through the app's tree: its field the keyboard's as it opens; its action not to be
// pressed while the line, trimmed, is as it was given or empty (unless an empty one says something, `empty`), able as
// soon as one change makes it so; said by Enter or its action once, trimmed, after it has closed, what that opens open;
// closed, the focus back where it was. Its title, words and buttons the window's tree's; its field an old view's
// editor hosted in it (the way there: no editor of the tree's yet). What the test types, presses and acts on draws
// frames of its own (Tester::type_text, key_named, act): what is asserted is after them, not with no frame between.

///|
test "大屏: a question, its line given at first: its field has the focus as it opens; as it was, its action does nothing, Enter says nothing; one change, its action says it" {
  let t = confirm_wide()
  let said : Array[String] = []
  @sf.ask("重命名", "保存", fn(l) { said.push(l) }, value="旧名")
  t.draw()
  let focused = t.focused().map(fn(s) { s.role })
  t.act(Button, Activate, label="保存")
  t.key_named("enter") |> ignore
  let as_it_was = (said.copy(), @sf.presenting())
  t.type_text("字")
  t.act(Button, Activate, label="保存")
  assert_eq((focused, as_it_was, said, @sf.presenting()), (Some(TextField), ([], true), ["旧名字"], false))
}

///|
test "大屏: a question said by Enter: its line trimmed, said once, after it has closed; Enter again, nothing more" {
  let t = confirm_wide()
  let said : Array[String] = []
  @sf.ask("重命名", "保存", fn(l) { said.push(l) })
  t.draw()
  t.type_text("  新名  ")
  t.key_named("enter") |> ignore
  let once = (said.copy(), @sf.presenting())
  t.key_named("enter") |> ignore
  t.run_for(@ui.move_most_ms)
  assert_eq((once, said), ((["新名"], false), ["新名"]))
}

///|
test "大屏: a question an empty line says something in (empty), its line cleared: its action able, said empty" {
  let t = confirm_wide()
  let said : Array[String] = []
  @sf.ask("重命名", "保存", fn(l) { said.push(l) }, value="旧名", empty=true)
  t.draw()
  t.key_named("backspace") |> ignore
  t.key_named("backspace") |> ignore
  t.act(Button, Activate, label="保存")
  assert_eq((said, @sf.presenting()), ([""], false))
}

///|
test "大屏: a question whose saying asks a confirm: said once, the confirm open after it" {
  let t = confirm_wide()
  let said : Array[String] = []
  @sf.ask("重命名", "保存", fn(l) {
    said.push(l)
    @sf.confirm("覆盖", "已有同名的对话。", "覆盖", fn() {  })
  })
  t.draw()
  t.type_text("新名")
  t.act(Button, Activate, label="保存")
  t.run_for(@ui.move_most_ms)
  assert_eq((said, t.all(Button, label="覆盖").length(), @sf.presenting()), (["新名"], 1, true))
}

///|
test "大屏: a question closed by Escape: the focus back on what had it as it opened" {
  let t = confirm_wide()
  t.act(Button, Focus, label="新建对话")
  let before = t.focused().map(fn(s) { s.label })
  @sf.ask("重命名", "保存", fn(_) {  })
  t.draw()
  let inside = t.focused().map(fn(s) { s.role })
  t.key_named("escape") |> ignore
  t.run_for(@ui.move_most_ms)
  assert_eq((before, inside, @sf.presenting(), t.focused().map(fn(s) { s.label })), (Some("新建对话"), Some(TextField), false, Some("新建对话")))
}

///|
test "大屏: a question cancelled before a frame drew it, a confirm asked then: the confirm's own ground has the focus, the question's field none of it; Enter does nothing" {
  let t = confirm_wide()
  @sf.ask("重命名", "保存", fn(_) {  })
  @sf.close_presented()
  @sf.confirm("删除", "删除这个对话？", "删除", fn() {  })
  t.draw()
  t.draw()
  let at = (t.focused().map(fn(s) { s.role }), @ui.current().focus != 0)
  t.enter()
  assert_eq((at, @sf.presenting(), t.all(Button, label="删除").length()), ((None, true), true, 1))
}

///|
/// Where to press outside the dialog titled `title`, over the sidebar's 新建对话 (what a press there opens, were it to
/// land), and a blank of the dialog's own (its top left corner, inside its padding).
fn dialog_points(t : @ui.Tester, title : String) -> ((Double, Double), (Double, Double)) {
  let (ox, oy) = t.find("新建对话").unwrap()
  let (dx, dy, _, _) = t.query(Dialog, label=title).unwrap().rect
  ((ox, oy), (dx + 10.0, dy + 10.0))
}

///|
test "大屏: a question, a press outside it held down: closed as it goes down, nothing under it taken; let go there, still nothing" {
  let t = confirm_wide()
  let said : Array[String] = []
  @sf.ask("重命名", "保存", fn(l) { said.push(l) })
  t.run_for(@ui.move_most_ms)
  let top = top_session()
  let ((ox, oy), _) = dialog_points(t, "重命名")
  t.press_at(ox, oy)
  let at_down = @sf.presenting()
  t.release(ox, oy)
  t.run_for(@ui.move_most_ms)
  assert_eq((at_down, @sf.presenting(), said, top_session() == top), (false, false, [], true))
}

///|
test "大屏: a question, a press outside it moved onto it and let go there: closed as it went down, nothing of it pressed" {
  let t = confirm_wide()
  let said : Array[String] = []
  @sf.ask("重命名", "保存", fn(l) { said.push(l) }, value="")
  t.run_for(@ui.move_most_ms)
  t.type_text("新名")
  let ((ox, oy), _) = dialog_points(t, "重命名")
  let (bx, by, bw, bh) = t.query(Button, label="保存").unwrap().rect
  t.press_at(ox, oy)
  let at_down = @sf.presenting()
  t.move(bx + bw / 2.0, by + bh / 2.0)
  t.release(bx + bw / 2.0, by + bh / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq((at_down, @sf.presenting(), said), (false, false, []))
}

///|
test "大屏: a question and a confirm, a press on a blank of their own: each open still; a press outside the confirm: open still" {
  let t = confirm_wide()
  @sf.ask("重命名", "保存", fn(_) {  })
  t.run_for(@ui.move_most_ms)
  let (_, (ax, ay)) = dialog_points(t, "重命名")
  t.tap(ax, ay)
  let ask_open = @sf.presenting()
  @sf.close_presented()
  t.run_for(@ui.move_most_ms)
  @sf.confirm("删除", "删除这个对话？", "删除", fn() {  })
  t.run_for(@ui.move_most_ms)
  let ((ox, oy), (cx, cy)) = dialog_points(t, "删除")
  t.tap(cx, cy)
  let confirm_open = @sf.presenting()
  t.tap(ox, oy)
  t.run_for(@ui.move_most_ms)
  assert_eq((ask_open, confirm_open, @sf.presenting()), (true, true, true))
}
