// A node of the window's tree asking for the focus (View::ask_focus): the one focus, the old frame's and the tree's
// alike (what is read out has it, Tab goes on from it, it is given back as from any); a press on an old view's field
// after, the focus that field's on either side.

///|
test "a node of the tree's asking for the focus, shown: what is read out as focused and the tree's own focus both on it; a field of an old view pressed after: both on that field" {
  let asks : Ref[@view.View?] = Ref(None)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  set_view_app(fn(root) {
    old(root, fn(c) { c.editor("ask/field", placeholder="旧字段") |> ignore }).height(Is(Some(60.0))) |> ignore
    for label in ["甲", "乙"] {
      let b = root.box(fn(b) {
        b
        .width(Is(Some(80.0)))
        .height(Is(Some(40.0)))
        .presses(Is(true))
        .focusable(Is(true))
        .says(Is(Some(@view.said(Button, label~))))
        .on_press(fn() {  })
        |> ignore
      })
      if label == "乙" {
        asks.val = Some(b)
      }
    }
  })
  t.draw()
  let b = asks.val.unwrap()
  let took = b.ask_focus(visible=true)
  t.draw()
  let asked = (took, t.focused().map(fn(s) { s.label }), b.focused(), b.focus_shown())
  t.tap_text("旧字段")
  t.draw()
  let pressed = (t.focused().map(fn(s) { s.role }), b.focused())
  assert_eq((asked, pressed), ((true, Some("乙"), true, true), (Some(TextField), false)))
}
