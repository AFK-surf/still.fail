// A sheet and the keyboard's focus: none of what it holds given it as it opens (a field in it would bring the keyboard
// up over it), and none of the page under it left with it (what is typed would go on into a field it hides): its own
// ground has it while it is up, given back as it goes.

///|
test "sheet: a field under it keeps neither the focus, what is typed nor its input method while it is up; one in it is not given them; all of it given back as it goes" {
  for platform in [0, 2] {
    let at = "platform \{platform}"
    let open = Ref(false)
    let page = @ui.Field::new()
    let inner = @ui.Field::new()
    let t = @ui.Tester::new(
      fn(c) {
        c.editor("page", placeholder="Page field", field=page) |> ignore
        open.val = sheet(c, "s", open.val, h=300.0, label="Chat info", fn() {
          c.editor("inner", placeholder="Sheet field", field=inner) |> ignore
          button(c, "Pin") |> ignore
        }).open
      },
      platform~,
    )
    t.tap_text("Page field")
    t.draw()
    assert_eq(t.focused().map(fn(s) { s.label }), Some("Page field"), msg=at)
    assert_true(t.ime().0, msg="\{at}: the page's field told the host")
    // up: the focus on its ground, the host told no field has it, the one in it not given it
    open.val = true
    to_rest(t, "s")
    assert_eq(t.focused().map(fn(s) { s.label }), None, msg=at)
    assert_false(t.ime().0, msg="\{at}: no field while it is up: \{t.ime()}")
    assert_false(t.get(@ui.Role::TextField, label="Sheet field").focused, msg=at)
    t.type_text("a")
    t.draw()
    assert_eq((page.text(), inner.text()), ("", ""), msg="\{at}: typed while it is up")
    // gone: the page's field has the focus and its input method back, what is typed its
    t.press("Escape")
    assert_false(open.val, msg=at)
    to_rest(t, "s")
    assert_eq(t.focused().map(fn(s) { s.label }), Some("Page field"), msg=at)
    assert_true(t.ime().0, msg="\{at}: given back: \{t.ime()}")
    t.type_text("b")
    t.draw()
    assert_eq((page.text(), inner.text()), ("b", ""), msg=at)
  }
}

///|
test "sheet: opened with nothing focused, nothing is (no field in it, none under it); closed, still nothing" {
  let open = Ref(false)
  let page = @ui.Field::new()
  let t = @ui.Tester::new(fn(c) {
    c.editor("page", placeholder="Page field", field=page) |> ignore
    open.val = sheet(c, "s", open.val, h=300.0, label="Chat info", fn() {
      c.editor("inner", placeholder="Sheet field") |> ignore
    }).open
  })
  t.draw()
  open.val = true
  to_rest(t, "s")
  assert_eq(t.focused().map(fn(s) { s.label }), None)
  assert_false(t.ime().0)
  t.press("Escape")
  to_rest(t, "s")
  assert_eq(t.focused().map(fn(s) { s.label }), None)
  assert_eq(t.ctx().focused_id(), 0)
  t.type_text("c")
  t.draw()
  assert_eq(page.text(), "")
}
