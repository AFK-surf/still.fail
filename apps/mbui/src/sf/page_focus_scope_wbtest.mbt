// A page's focus scope can outlive its shell while still respecting later focus decisions.

///|
test "a page focus scope returns its control across shell replacements" {
  let shell = @signals.signal(0)
  let width = @signals.signal(700.0)
  let previous = Ref(0)
  let scope = PageFocusScope::new()
  let presses = Ref(0)
  let t = @ui.Tester::new(fn(_c) {  }, w=700.0, h=700.0, platform=0)
  @ui.set_view_app(fn(root) {
    root.pick(fn() {
      let now = shell.get()
      if previous.val != now {
        scope.capture() |> ignore
        previous.val = now
      }
      now
    }, fn(page, _) {
      scope.lend(page)
      page_node(page, fn() { "Page" }, fn() { ["one"] }, fn(b, _) {
        b.box(fn(row) {
          row.height(Is(Some(60.0))).words(Is("Target"))
          .says(Is(Some(@view.said(Button, label="Target")))) |> ignore
          presses_node(row, fn() { presses.val += 1 })
          page_focus_node(row, "target") |> ignore
        }) |> ignore
      }, on_back=fn() {  }, frame=fn() { { ..no_frame, named: true } }, width=fn() { width.get() })
    })
  })
  t.draw()
  t.act(Button, Focus, label="Target")
  for (state, w) in [(1, 500.0), (2, 390.0), (0, 700.0)] {
    @ui.view_tree().unwrap().event(t.time(), fn() { shell.set(state); width.set(w) })
    t.resize(w, 700.0)
    assert_eq(t.focused().map(fn(s) { s.label }), Some("Target"))
    t.key(@ui.key_space)
  }
  assert_eq(presses.val, 3)
}

///|
test "a page focus scope does not take focus back from an old control during a shell replacement" {
  let shell = @signals.signal(0)
  let previous = Ref(0)
  let scope = PageFocusScope::new()
  let outside = Ref(0)
  let focus_outside_on_make = Ref(false)
  let t = @ui.Tester::new(fn(_c) {  }, w=700.0, h=700.0, platform=0)
  @ui.set_view_app(fn(root) {
    @ui.old(root, fn(c) {
      let id = c.id("outside-old-scope")
      outside.val = id
      c.interact(id) |> ignore
      c.box(w=Px(80.0), h=Px(40.0), id~, fn() {  }) |> ignore
    }).height(Is(Some(40.0))) |> ignore
    root.pick(fn() {
      let now = shell.get()
      if previous.val != now {
        scope.capture() |> ignore
        previous.val = now
      }
      now
    }, fn(page, _) {
      scope.lend(page)
      page_node(page, fn() { "Page" }, fn() { ["one"] }, fn(b, _) {
        if focus_outside_on_make.val {
          focus_outside_on_make.val = false
          t.ctx().focus_on(outside.val)
        }
        b.box(fn(row) {
          row.height(Is(Some(60.0))).words(Is("Target"))
          .says(Is(Some(@view.said(Button, label="Target")))) |> ignore
          presses_node(row, fn() {  })
          page_focus_node(row, "target") |> ignore
        }) |> ignore
      }, on_back=fn() {  }, frame=fn() { { ..no_frame, named: true } }, width=fn() { 700.0 })
    })
  })
  t.draw()
  t.act(Button, Focus, label="Target")
  focus_outside_on_make.val = true
  shell.set(1)
  t.draw()
  assert_eq(t.ctx().focused_id(), outside.val)
}

///|
test "a cancelled page focus scope never restores focus to a later page" {
  let shell = @signals.signal(0)
  let previous = Ref(0)
  let scope = PageFocusScope::new()
  let t = @ui.Tester::new(fn(_c) {  }, w=700.0, h=700.0, platform=0)
  @ui.set_view_app(fn(root) {
    root.pick(fn() {
      let now = shell.get()
      if previous.val != now {
        scope.capture() |> ignore
        scope.cancel()
        previous.val = now
      }
      now
    }, fn(page, _) {
      scope.lend(page)
      page_node(page, fn() { "Page" }, fn() { ["one"] }, fn(b, _) {
        b.box(fn(row) {
          row.height(Is(Some(60.0))).words(Is("Target"))
          .says(Is(Some(@view.said(Button, label="Target")))) |> ignore
          presses_node(row, fn() {  })
          page_focus_node(row, "target") |> ignore
        }) |> ignore
      }, on_back=fn() {  }, frame=fn() { { ..no_frame, named: true } }, width=fn() { 700.0 })
    })
  })
  t.draw()
  t.act(Button, Focus, label="Target")
  shell.set(1)
  t.draw()
  assert_true(t.focused() is None)
}

///|
test "a page focus scope keeps an eligible return through consecutive replacements before layout" {
  let showing = @signals.signal(true)
  let scope = PageFocusScope::new()
  let t = @ui.Tester::new(fn(_c) {  }, w=700.0, h=700.0, platform=0)
  @ui.set_view_app(fn(root) {
    root.show(fn() { showing.get() }, fn(page) {
      scope.lend(page)
      page_node(page, fn() { "Page" }, fn() { ["one"] }, fn(b, _) {
        b.box(fn(row) {
          row.height(Is(Some(60.0))).words(Is("Target"))
          .says(Is(Some(@view.said(Button, label="Target")))) |> ignore
          presses_node(row, fn() {  })
          page_focus_node(row, "target") |> ignore
        }) |> ignore
      }, on_back=fn() {  }, frame=fn() { { ..no_frame, named: true } }, width=fn() { 700.0 })
    })
  })
  t.draw()
  t.act(Button, Focus, label="Target")
  assert_true(scope.capture())
  assert_true(scope.has_pending())
  @ui.view_tree().unwrap().event(t.time(), fn() { showing.set(false) })
  assert_true(scope.has_pending())
  assert_true(scope.capture())
  showing.set(true)
  t.draw()
  assert_eq(t.focused().map(fn(s) { s.label }), Some("Target"))
  assert_false(scope.has_pending())
}

///|
test "a page focus scope reports no eligible return after an explicit focus decision" {
  let showing = @signals.signal(true)
  let scope = PageFocusScope::new()
  let t = @ui.Tester::new(fn(_c) {  }, w=700.0, h=700.0, platform=0)
  @ui.set_view_app(fn(root) {
    root.show(fn() { showing.get() }, fn(page) {
      scope.lend(page)
      page_node(page, fn() { "Page" }, fn() { ["one"] }, fn(b, _) {
        b.box(fn(row) {
          row.height(Is(Some(60.0))).words(Is("Target"))
          .says(Is(Some(@view.said(Button, label="Target")))) |> ignore
          presses_node(row, fn() {  })
          page_focus_node(row, "target") |> ignore
        }) |> ignore
      }, on_back=fn() {  }, frame=fn() { { ..no_frame, named: true } }, width=fn() { 700.0 })
    })
  })
  t.draw()
  t.act(Button, Focus, label="Target")
  assert_true(scope.capture())
  let tree = @ui.view_tree().unwrap()
  tree.event(t.time(), fn() { showing.set(false) })
  assert_true(tree.focus_to(None))
  assert_false(scope.has_pending())
  assert_false(scope.capture())
  showing.set(true)
  t.draw()
  assert_true(t.focused() is None)
}
