// Page controls can keep their logical focus when a width change rebuilds the page in another arrangement.

///|
test "a page keeps its focused moving block through a simultaneous arrangement change" {
  let width = @signals.signal(700.0)
  let keys = @signals.signal(["a", "b", "c"])
  let presses = Ref(0)
  let t = @ui.Tester::new(fn(_c) {  }, w=700.0, h=700.0, platform=0)
  @ui.set_view_app(fn(root) {
    page_node(root, fn() { "Page" }, fn() { keys.get() }, fn(b, key) {
      b.box(fn(row) {
        row.height(Is(Some(60.0))).words(Is(key))
        .says(Is(Some(@view.said(Button, label=key)))) |> ignore
        presses_node(row, fn() { presses.val += 1 })
        page_focus_node(row, key) |> ignore
      }) |> ignore
    }, on_back=fn() {  }, frame=fn() { { ..no_frame, named: true } }, width=fn() { width.get() }, moves=true)
  })
  t.draw()
  t.act(Button, Focus, label="b")
  @ui.view_tree().unwrap().event(t.time(), fn() {
    width.set(390.0)
    keys.set(["b", "a", "c"])
  })
  t.resize(390.0, 700.0)
  assert_eq(t.focused().map(fn(s) { s.label }), Some("b"))
  t.key(@ui.key_space)
  assert_eq(presses.val, 1)
}

///|
test "a page keeps a field's input method composition through an arrangement change" {
  let width = @signals.signal(700.0)
  let field = @ui.Field::new(text="hi ")
  let t = @ui.Tester::new(fn(_c) {  }, w=700.0, h=700.0, platform=2)
  @ui.set_view_app(fn(root) {
    page_node(root, fn() { "Page" }, fn() { ["one"] }, fn(b, _) {
      let input = @ui.field(b, field, placeholder="Name", max_lines=1)
      page_focus_node(input, "name") |> ignore
    }, on_back=fn() {  }, frame=fn() { { ..no_frame, named: true } }, width=fn() { width.get() })
  })
  t.draw()
  t.act(TextField, Focus, label="Name")
  t.ime_state("hi wor", 6, 6, ca=3, cb=6)
  assert_eq(field.text(), "hi ")
  assert_eq(field.composed_said(), "hi wor")
  width.set(390.0)
  t.resize(390.0, 700.0)
  assert_eq(t.focused().map(fn(s) { s.label }), Some("Name"))
  assert_true(t.ime().0)
  assert_eq(field.text(), "hi ")
  assert_eq(field.composed_said(), "hi wor")
  t.ime_state("hi world", 8, 8)
  assert_eq(field.text(), "hi world")
}

///|
test "a page keeps its own back control focused through both arrangements" {
  let width = @signals.signal(700.0)
  let backs = Ref(0)
  let t = @ui.Tester::new(fn(_c) {  }, w=700.0, h=700.0, platform=0)
  @ui.set_view_app(fn(root) {
    page_node(root, fn() { "Page" }, fn() { ["one"] }, fn(b, _) {
      b.height(Is(Some(60.0))) |> ignore
    }, on_back=fn() { backs.val += 1 }, frame=fn() { { ..no_frame, back: Some("Settings") } },
      width=fn() { width.get() })
  })
  t.draw()
  t.act(Link, Focus, label="Settings")
  width.set(390.0)
  t.resize(390.0, 700.0)
  assert_eq(t.focused().map(fn(s) { s.label }), Some("Settings"))
  t.key(@ui.key_space)
  assert_eq(backs.val, 1)
  width.set(700.0)
  t.resize(700.0, 700.0)
  assert_eq(t.focused().map(fn(s) { s.label }), Some("Settings"))
  t.key(@ui.key_space)
  assert_eq(backs.val, 2)
}

///|
test "a page restores only its focused control by stable key when its arrangement changes" {
  let width = @signals.signal(700.0)
  let keys = @signals.signal(["first", "second"])
  let enabled = @signals.signal(true)
  let pressed : Array[String] = []
  let t = @ui.Tester::new(fn(_c) {  }, w=700.0, h=700.0, platform=0)
  @ui.set_view_app(fn(root) {
    root.box(fn(outside) {
      outside.height(Is(Some(40.0))).words(Is("Outside"))
      .says(Is(Some(@view.said(Button, label="Outside")))) |> ignore
      presses_node(outside, fn() {  })
    }) |> ignore
    root.box(fn(p) {
      p.height(Is(Some(600.0))).width(By(fn() { Some(width.get()) })) |> ignore
      page_node(p, fn() { "Page" }, fn() { keys.get() }, fn(b, key) {
        b.box(fn(row) {
          row.height(Is(Some(60.0))).words(Is("Same name"))
          .says(Is(Some(@view.said(Button, label="Same name")))) |> ignore
          presses_node(row, fn() { pressed.push(key) }, on=fn() { enabled.get() })
          page_focus_node(row, "device/" + key) |> ignore
        }) |> ignore
      }, on_back=fn() {  }, frame=fn() { { ..no_frame, named: true } }, width=fn() { width.get() })
    }) |> ignore
  })
  t.draw()
  // Display labels need not be unique: the second control is restored by its business key.
  t.act_on(t.all(Button, label="Same name")[1], Focus)
  width.set(390.0)
  t.resize(390.0, 700.0)
  t.key(@ui.key_space)
  assert_eq(pressed, ["second"])
  // A different control holding focus must not have it taken by a page arrangement change.
  t.act(Button, Focus, label="Outside")
  width.set(700.0)
  t.resize(700.0, 700.0)
  assert_eq(t.focused().map(fn(s) { s.label }), Some("Outside"))
  // Once the target is disabled or removed, a later rebuild cannot focus it.
  t.act_on(t.all(Button, label="Same name")[1], Focus)
  enabled.set(false)
  width.set(390.0)
  t.resize(390.0, 700.0)
  assert_true(t.focused() is None)
  enabled.set(true)
  t.draw()
  t.act_on(t.all(Button, label="Same name")[1], Focus)
  keys.set(["first"])
  width.set(700.0)
  t.resize(700.0, 700.0)
  assert_true(t.focused() is None)
}

///|
test "a page does not take focus from a hosted old control as its arrangement is rebuilt" {
  let width = @signals.signal(700.0)
  let outside = Ref(0)
  let focus_outside_on_make = Ref(false)
  let t = @ui.Tester::new(fn(_c) {  }, w=700.0, h=700.0, platform=0)
  @ui.set_view_app(fn(root) {
    @ui.old(root, fn(c) {
      let id = c.id("outside-old")
      outside.val = id
      c.interact(id) |> ignore
      c.box(w=Px(80.0), h=Px(40.0), id~, fn() {  }) |> ignore
    }).height(Is(Some(40.0))) |> ignore
    root.box(fn(p) {
      p.height(Is(Some(600.0))).width(By(fn() { Some(width.get()) })) |> ignore
      page_node(p, fn() { "Page" }, fn() { ["one"] }, fn(b, _) {
        if focus_outside_on_make.val {
          focus_outside_on_make.val = false
          t.ctx().focus_on(outside.val)
        }
        b.box(fn(row) {
          row.height(Is(Some(60.0))).words(Is("Page control"))
          .says(Is(Some(@view.said(Button, label="Page control")))) |> ignore
          presses_node(row, fn() {  })
          page_focus_node(row, "page/control") |> ignore
        }) |> ignore
      }, on_back=fn() {  }, frame=fn() { { ..no_frame, named: true } }, width=fn() { width.get() })
    }) |> ignore
  })
  t.draw()
  t.ctx().focus_on(outside.val)
  width.set(390.0)
  t.resize(390.0, 700.0)
  assert_eq(t.ctx().focused_id(), outside.val)
  t.act(Button, Focus, label="Page control")
  focus_outside_on_make.val = true
  width.set(700.0)
  t.resize(700.0, 700.0)
  assert_eq(t.ctx().focused_id(), outside.val)
}

///|
test "a page does not return focus to a block moved outside the window" {
  let width = @signals.signal(700.0)
  let pressed = Ref(0)
  let scroll = @view.Scroll::list()
  let t = @ui.Tester::new(fn(_c) {  }, w=700.0, h=240.0, platform=0)
  @ui.set_view_app(fn(root) {
    root.box(fn(p) {
      p.height(Is(Some(240.0))).width(By(fn() { Some(width.get()) })) |> ignore
      page_node(p, fn() { "Page" }, fn() { ["spacer", "target"] }, fn(b, key) {
        if key == "spacer" {
          b.height(Is(Some(if look_node(b) is Wide { 20.0 } else { 900.0 }))) |> ignore
        } else {
          b.box(fn(row) {
            row.height(Is(Some(60.0))).words(Is("Target"))
            .says(Is(Some(@view.said(Button, label="Target")))) |> ignore
            presses_node(row, fn() { pressed.val += 1 })
            page_focus_node(row, "target") |> ignore
          }) |> ignore
        }
      }, on_back=fn() {  }, frame=fn() { { ..no_frame, named: true } }, width=fn() { width.get() }, scroll~)
    }) |> ignore
  })
  t.draw()
  t.act(Button, Focus, label="Target")
  width.set(390.0)
  t.resize(390.0, 240.0)
  assert_true(t.focused() is None)
  t.key(@ui.key_space)
  assert_eq(pressed.val, 0)
}

///|
test "a page leaving during an arrangement change never takes focus back" {
  let width = @signals.signal(700.0)
  let showing = @signals.signal(true)
  let t = @ui.Tester::new(fn(_c) {  }, w=700.0, h=700.0, platform=0)
  @ui.set_view_app(fn(root) {
    root.box(fn(outside) {
      outside.height(Is(Some(40.0))).words(Is("Outside"))
      .says(Is(Some(@view.said(Button, label="Outside")))) |> ignore
      presses_node(outside, fn() {  })
    }) |> ignore
    root.show(fn() { showing.get() }, fn(p) {
      p.height(Is(Some(600.0))).width(By(fn() { Some(width.get()) })) |> ignore
      page_node(p, fn() { "Page" }, fn() { ["one"] }, fn(b, _) {
        b.box(fn(row) {
          row.height(Is(Some(60.0))).words(Is("Target"))
          .says(Is(Some(@view.said(Button, label="Target")))) |> ignore
          presses_node(row, fn() {  })
          page_focus_node(row, "target") |> ignore
        }) |> ignore
      }, on_back=fn() {  }, frame=fn() { { ..no_frame, named: true } }, width=fn() { width.get() })
    })
  })
  t.draw()
  t.act(Button, Focus, label="Target")
  @ui.view_tree().unwrap().event(t.time(), fn() { width.set(390.0); showing.set(false) })
  t.draw()
  assert_true(t.focused() is None)
  t.act(Button, Focus, label="Outside")
  t.draw()
  assert_eq(t.focused().map(fn(s) { s.label }), Some("Outside"))
}
