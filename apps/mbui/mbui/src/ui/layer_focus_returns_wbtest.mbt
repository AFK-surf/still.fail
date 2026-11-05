// A layer of the tree's that gives the focus nothing as it opens, giving back what had it as it goes
// (View::focus_returns: a menu a finger opens beside a field), opened in one change with one that gives the focus to
// its button over it: the focus on that button; that one closed, back on the field it was in, not on the layer under
// it; that closed too, on the field still.

///|
test "an old view's field with the focus; in one change a layer giving the focus nothing as it opens, and one over it giving the focus to its button: the focus on the button; the upper closed, back on the field; the lower closed, on the field" {
  let field = Field::new()
  let (low, up) = (@signals.signal(false), @signals.signal(false))
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  set_view_app(fn(root) {
    old(root, fn(c) { c.editor("returns/field", placeholder="旧字段", field~) |> ignore }).height(Is(Some(60.0))) |> ignore
    root.show(fn() { low.get() }, fn(l) {
      l.over(Is(true)).stacked(Is(2)).modal(Is(true)).leaves_typing().focus_returns() |> ignore
    })
    root.show(fn() { up.get() }, fn(l) {
      l.over(Is(true)).stacked(Is(3)).modal(Is(true)) |> ignore
      let b = l.box(fn(x) {
        x
        .width(Is(Some(80.0)))
        .height(Is(Some(40.0)))
        .presses(Is(true))
        .focusable(Is(true))
        .says(Is(Some(@view.said(Button, label="上的按钮"))))
        .on_press(fn() {  })
        |> ignore
      })
      l.focus_opens(b) |> ignore
    })
  })
  t.draw()
  t.tap_text("旧字段")
  t.draw()
  let said = fn() { t.focused().map(fn(s) { "\{s.role} \{s.label}" }).unwrap_or("none") }
  let before = said()
  @signals.start_batch()
  low.set(true)
  up.set(true)
  @signals.end_batch()
  t.draw()
  let opened = said()
  up.set(false)
  t.draw()
  let upper_closed = said()
  low.set(false)
  t.draw()
  assert_eq((before, opened, upper_closed, said()), ("TextField 旧字段", "Button 上的按钮", "TextField 旧字段", "TextField 旧字段"))
}

///|
test "a kept page laid nowhere while a gate shows gets its node's focus back as the gate goes; a node removed meanwhile does not" {
  let gated = @signals.signal(false)
  let kept = @signals.signal(true)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.show(fn() { gated.get() }, fn(g) {
      g.grow(Is(1.0)).focus_returns() |> ignore
    })
    root.box(fn(page) {
      page.laid_nowhere(By(fn() { gated.get() })) |> ignore
      page.show(fn() { kept.get() }, fn(b) {
        b.width(Is(Some(80.0))).height(Is(Some(40.0)))
        .focusable(Is(true)).says(Is(Some(@view.said(Button, label="页内按钮")))) |> ignore
      })
    }) |> ignore
  })
  t.draw()
  t.act(Button, Focus, label="页内按钮")
  let focus = t.ctx().focus
  gated.set(true)
  t.draw()
  assert_eq(t.ctx().focus, 0)
  gated.set(false)
  t.draw()
  assert_eq(t.ctx().focus, focus)
  assert_eq(t.focused().map(fn(n) { n.label }), Some("页内按钮"))
  gated.set(true)
  t.draw()
  kept.set(false)
  gated.set(false)
  t.draw()
  assert_eq(t.ctx().focus, 0)
}

///|
test "a layer said to give the focus back to what opened it: closed, the focus on its opener, not on the field that had it; its opener gone, on that field" {
  let open = @signals.signal(false)
  let opener_on = @signals.signal(true)
  let opener : Ref[@view.NodeId?] = Ref(None)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.box(fn(f) {
      f
      .width(Is(Some(80.0)))
      .height(Is(Some(40.0)))
      .focusable(Is(true))
      .says(Is(Some(@view.said(Button, label="原来的"))))
      |> ignore
    })
    |> ignore
    root.show(fn() { opener_on.get() }, fn(o) {
      opener.val = Some(o.id())
      o
      .width(Is(Some(80.0)))
      .height(Is(Some(40.0)))
      .focusable(Is(true))
      .says(Is(Some(@view.said(Button, label="打开的"))))
      |> ignore
    })
    root.show(fn() { open.get() }, fn(l) {
      l.over(Is(true)).stacked(Is(2)).modal(Is(true)) |> ignore
      let b = l.box(fn(x) {
        x
        .width(Is(Some(80.0)))
        .height(Is(Some(40.0)))
        .focusable(Is(true))
        .says(Is(Some(@view.said(Button, label="层里的"))))
        |> ignore
      })
      l.focus_opens(b).returns_focus_to(opener.val.unwrap()) |> ignore
    })
  })
  t.draw()
  let said = fn() { t.focused().map(fn(s) { s.label }).unwrap_or("none") }
  t.act(Button, Focus, label="原来的")
  open.set(true)
  t.draw()
  let opened = said()
  open.set(false)
  t.draw()
  let closed = said()
  t.act(Button, Focus, label="原来的")
  open.set(true)
  t.draw()
  @signals.start_batch()
  opener_on.set(false)
  open.set(false)
  @signals.end_batch()
  t.draw()
  assert_eq((opened, closed, said()), ("层里的", "打开的", "原来的"))
}

///|
test "an old view's field with the focus, its old view let go: a field of nothing, the focus let go of, a key to the tree from its root" {
  let field = Field::new()
  let shown = @signals.signal(true)
  let took : Array[Int] = []
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.on_key(fn(k) {
      took.push(k.code)
      true
    })
    |> ignore
    root.show(fn() { shown.get() }, fn(b) {
      old(b, fn(c) { c.editor("gone/field", placeholder="旧字段", field~) |> ignore }).height(Is(Some(60.0))) |> ignore
    })
  })
  t.draw()
  t.tap_text("旧字段")
  t.draw()
  let field_id = t.ctx().focus
  shown.set(false)
  t.draw()
  // (its field no field of anything now: nothing has the focus, no field's place told for the keyboard or its caret)
  let after = (t.ctx().focus, t.ctx().editors.contains(field_id), focused_field_in() is None)
  t.key(key_code_up, mods=mod_alt)
  assert_eq((after, took), ((0, false, true), [key_code_up]))
}

///|
test "a key a field takes, said to go on in a field: told the tree's node that said so as well; one not said, the field's alone" {
  let field = Field::new()
  let took : Array[Int] = []
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root
    .keys_in_fields([(key_code_up, mod_alt)])
    .on_key(fn(k) {
      took.push(k.code)
      true
    })
    |> ignore
    old(root, fn(c) { c.editor("in/field", placeholder="字段", field~) |> ignore }).height(Is(Some(60.0))) |> ignore
  })
  t.draw()
  t.tap_text("字段")
  t.draw()
  t.key(key_code_up, mods=mod_alt)
  t.key(key_code_down, mods=mod_alt)
  assert_eq(took, [key_code_up])
}

///|
test "an old view's field with the focus: its old view let go, the focus let go of at that moment, before any frame" {
  let field = Field::new()
  let shown = @signals.signal(true)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.show(fn() { shown.get() }, fn(b) {
      old(b, fn(c) { c.editor("now/field", placeholder="旧字段", field~) |> ignore }).height(Is(Some(60.0))) |> ignore
    })
  })
  t.draw()
  t.tap_text("旧字段")
  t.draw()
  let field_id = t.ctx().focus
  // (let go as a change ends, no frame drawn after it)
  shown.set(false)
  assert_eq((field_id != 0, t.ctx().focus, t.ctx().editors.contains(field_id)), (true, 0, false))
}
