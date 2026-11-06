// A logical page may make its editor directly rather than through page_node.

///|
test "a page focus scope returns a direct field through shell replacements" {
  let shell = @signals.signal(0)
  let previous = Ref(0)
  let captured = Ref(false)
  let scope = PageFocusScope::new()
  let field = @ui.Field::new(text="abcdef")
  let t = @ui.Tester::new(fn(_c) {  }, w=390.0, h=800.0, platform=2)
  @ui.set_view_app(fn(root) {
    root.pick(fn() {
      let now = shell.get()
      if previous.val != now {
        captured.val = scope.capture()
        previous.val = now
      }
      now
    }, fn(page, _) {
      scope.lend(page)
      let input = @ui.field(page, field, placeholder="Composer", max_lines=4)
      page_focus_node(input, "composer") |> ignore
    })
  })
  t.draw()
  t.act(TextField, Focus, label="Composer")
  t.ime_state("abcdef", 2, 5)
  assert_eq(field.selection(), (2, 5))
  for (state, width) in [(1, 700.0), (2, 1280.0), (3, 390.0)] {
    @ui.view_tree().unwrap().event(t.time(), fn() { shell.set(state) })
    t.resize(width, 800.0)
    assert_true(captured.val)
    assert_eq(t.focused().map(fn(s) { s.label }), Some("Composer"))
    assert_eq((field.text(), field.selection()), ("abcdef", (2, 5)))
    assert_true(t.ime().0)
  }
}

///|
test "a direct control returns when made later unless focus has moved" {
  let showing = @signals.signal(true)
  let scope = PageFocusScope::new()
  let t = @ui.Tester::new(fn(_c) {  }, w=700.0, h=800.0, platform=0)
  @ui.set_view_app(fn(root) {
    root.box(fn(outside) {
      outside.height(Is(Some(40.0))).words(Is("Outside"))
      .says(Is(Some(@view.said(Button, label="Outside")))) |> ignore
      presses_node(outside, fn() {  })
    }) |> ignore
    scope.lend(root)
    root.show(fn() { showing.get() }, fn(page) {
      page.box(fn(row) {
        row.height(Is(Some(60.0))).words(Is("Target"))
        .says(Is(Some(@view.said(Button, label="Target")))) |> ignore
        presses_node(row, fn() {  })
        page_focus_node(row, "target") |> ignore
      }) |> ignore
    })
  })
  t.draw()
  t.act(Button, Focus, label="Target")
  assert_true(scope.capture())
  showing.set(false)
  t.draw()
  assert_true(scope.has_pending())
  showing.set(true)
  t.draw()
  assert_eq(t.focused().map(fn(s) { s.label }), Some("Target"))
  assert_false(scope.has_pending())

  assert_true(scope.capture())
  showing.set(false)
  t.draw()
  t.act(Button, Focus, label="Outside")
  showing.set(true)
  t.draw()
  assert_eq(t.focused().map(fn(s) { s.label }), Some("Outside"))
  assert_false(scope.has_pending())
}

///|
test "a direct control returns to an eligible copy and not to a later enabled one" {
  let state = @signals.signal(0)
  let scope = PageFocusScope::new()
  let t = @ui.Tester::new(fn(_c) {  }, w=700.0, h=800.0, platform=0)
  @ui.set_view_app(fn(root) {
    scope.lend(root)
    root.pick(fn() { state.get() }, fn(page, n) {
      let item = fn(label : String, on : Bool) {
        page.box(fn(row) {
          row.height(Is(Some(60.0))).words(Is(label))
          .says(Is(Some(@view.said(Button, label~)))) |> ignore
          presses_node(row, fn() {  }, on=fn() { on })
          page_focus_node(row, "target") |> ignore
        }) |> ignore
      }
      match n {
        0 => item("Original", true)
        1 => { item("Disabled", false); item("Replacement", true) }
        2 => item("Disabled", false)
        _ => item("Later", true)
      }
    })
  })
  t.draw()
  t.act(Button, Focus, label="Original")
  assert_true(scope.capture())
  state.set(1)
  t.draw()
  assert_eq(t.focused().map(fn(s) { s.label }), Some("Replacement"))
  assert_true(scope.capture())
  state.set(2)
  t.draw()
  assert_true(t.focused() is None)
  assert_false(scope.has_pending())
  state.set(3)
  t.draw()
  assert_true(t.focused() is None)
}
