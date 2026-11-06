// An icon button in the tree beside the old icon_button: its changing state, ink and ways in.

///|
fn icon_button_case(
  on : @signals.Signal[Bool],
  off : @signals.Signal[Bool],
  accent : @signals.Signal[Bool],
  there : @signals.Signal[Bool],
  count : Ref[Int],
) -> @ui.Tester {
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=200.0, platform=0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    root.row(Is(true)) |> ignore
    root.box(fn(g) { g.width(Is(Some(60.0))) |> ignore }) |> ignore
    root.box(fn(h) {
      h.width(Is(Some(100.0))).height(Is(Some(100.0))) |> ignore
      @ui.old(h, fn(c) {
        let ink = if accent.get() { Some(theme().p.accent) } else { None }
        icon_button(c, "panel-open", key="old", round=true, label="old", on=on.get(), disabled=off.get(), ink?=ink, quiet?=ink) |> ignore
      }).grow(Is(1.0)) |> ignore
    }) |> ignore
    let layer : Ref[@view.View?] = Ref(None)
    let tips = TipLayer::new(fn() { layer.val })
    root.box(fn(h) {
      h.width(Is(Some(100.0))).height(Is(Some(100.0))) |> ignore
      h.show(fn() { there.get() }, fn(p) {
        icon_button_node(
          p,
          "panel-open",
          fn() { "new" },
          fn() { count.val += 1 },
          tips~,
          on=fn() { on.get() },
          disabled=fn() { off.get() },
          ink=fn() { if accent.get() { theme().p.accent } else { theme().p.text } },
          quiet=fn() { if accent.get() { theme().p.accent } else { theme().p.muted } },
        ) |> ignore
      }) |> ignore
    }) |> ignore
    layer.val = Some(root.box(fn(l) { l.over(Is(true)) |> ignore }))
  })
  t.draw()
  t
}

///|
test "an icon button node's changing chosen, disabled and ink states draw as the old round button, including the preview's accent without a chosen ground" {
  let (on, off, accent, there) = (@signals.signal(false), @signals.signal(false), @signals.signal(false), @signals.signal(true))
  let t = icon_button_case(on, off, accent, there, Ref(0))
  for state in [(false, false, false), (false, false, true), (true, false, true), (true, true, true), (false, true, false), (false, false, false)] {
    let (selected, disabled, custom) = state
    on.set(selected)
    off.set(disabled)
    accent.set(custom)
    t.leave()
    t.draw()
    let old = t.get(Button, label="old")
    let node = t.get(Button, label="new")
    assert_eq((node.rect.2, node.rect.3), (old.rect.2, old.rect.3))
    let old_drawn = drawn_within(t, old.rect)
    let node_drawn = drawn_within(t, node.rect)
    assert_eq(node_drawn, old_drawn, msg="on=\{selected}, disabled=\{disabled}, accent=\{custom}; old=\{old_drawn}; node=\{node_drawn}")
    assert_eq((node.pressed, node.disabled), (Some(selected), disabled))
  }
  // (the old preview changes the ink and quiet ink together, without an on ground)
  accent.set(true)
  t.draw()
  let node = t.get(Button, label="new")
  let preview = drawn_within(t, node.rect)
  on.set(true)
  t.draw()
  assert_true(drawn_within(t, node.rect) != preview, msg="on has its own ground")
}

///|
test "an icon button node takes mouse, finger, keyboard and accessibility presses once; disabling it between events removes focus and all ways in immediately" {
  let (on, off, accent, there) = (@signals.signal(false), @signals.signal(false), @signals.signal(false), @signals.signal(true))
  let count = Ref(0)
  let t = icon_button_case(on, off, accent, there, count)
  let n = t.get(Button, label="new")
  let (x, y) = (n.rect.0 + n.rect.2 / 2.0, n.rect.1 + n.rect.3 / 2.0)
  t.touch(0, x, y)
  t.touch(2, x, y)
  t.touch_raw(0, 1, x, y, t.time())
  t.touch_raw(2, 1, x, y, t.time())
  t.act(Button, Focus, label="new")
  t.key_told(enter_code, 0, t.time())
  t.key_told(space_code, 0, t.time())
  t.ctx().ask_action(n.id, Activate)
  assert_eq(count.val, 5)
  t.touch_raw(0, 1, x, y, t.time())
  off.set(true)
  assert_true(t.focused() is None)
  t.touch_raw(2, 1, x, y, t.time())
  t.touch(0, x, y)
  t.touch(2, x, y)
  t.key_told(enter_code, 0, t.time())
  t.key_told(space_code, 0, t.time())
  t.ctx().ask_action(n.id, Activate)
  let disabled = t.get(Button, label="new")
  assert_eq((count.val, disabled.disabled, disabled.actions), (5, true, []))
  off.set(false)
  t.ctx().ask_action(n.id, Activate)
  assert_eq(count.val, 6, msg="enabled again without a frame")
}

///|
test "an icon button node lights for a mouse or keyboard focus and stops lighting when disabled" {
  let (on, off, accent, there) = (@signals.signal(false), @signals.signal(false), @signals.signal(false), @signals.signal(true))
  let t = icon_button_case(on, off, accent, there, Ref(0))
  let n = t.get(Button, label="new")
  let (x, y) = (n.rect.0 + n.rect.2 / 2.0, n.rect.1 + n.rect.3 / 2.0)
  let rest = drawn_within(t, n.rect)
  t.move(x, y)
  t.run_for(dur_ms)
  let hovered = drawn_within(t, n.rect)
  assert_true(hovered != rest)
  t.leave()
  t.run_for(dur_ms)
  t.tab()
  t.run_for(dur_ms)
  assert_eq(t.focused().map(fn(s) { s.label }), Some("new"))
  assert_eq(drawn_within(t, n.rect), hovered)
  off.set(true)
  t.run_for(dur_ms)
  assert_true(t.focused() is None)
  let unable = drawn_within(t, n.rect)
  t.move(x, y)
  t.run_for(dur_ms)
  assert_eq(drawn_within(t, n.rect), unable)
}

///|
test "an ordinary icon button remains an ordinary button; its tip and focus leave with it" {
  let present = @signals.signal(true)
  let t = @ui.Tester::new(fn(_c) {  }, w=300.0, h=200.0, platform=0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    let layer : Ref[@view.View?] = Ref(None)
    let tips = TipLayer::new(fn() { layer.val })
    root.show(fn() { present.get() }, fn(p) {
      icon_button_node(p, "copy", fn() { "Copy" }, fn() {  }, tips~) |> ignore
    }) |> ignore
    layer.val = Some(root.box(fn(l) { l.over(Is(true)) |> ignore }))
  })
  t.draw()
  let button = t.get(Button, label="Copy")
  assert_eq((button.pressed, button.disabled), (None, false))
  t.tab()
  assert_true(t.semantics().any(fn(s) { s.role == Tooltip && s.label == "Copy" }))
  present.set(false)
  assert_true(t.focused() is None)
  assert_false(t.semantics().any(fn(s) { s.role == Tooltip && s.label == "Copy" }))
}

///|
test "an icon button's shown tip follows its shortcut action" {
  let before = shortcut_keys_of.val
  set_shortcuts(fn(action) {
    match action {
      "files.preview" => "Ctrl+P"
      "files.next" => "Alt+N"
      _ => ""
    }
  })
  let action = @signals.signal("files.preview")
  let t = @ui.Tester::new(fn(_c) {  }, w=300.0, h=200.0, platform=0, keyboard=true)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    let layer : Ref[@view.View?] = Ref(None)
    let tips = TipLayer::new(fn() { layer.val })
    icon_button_node(root, "panel-open", fn() { "Preview" }, fn() {  }, tips~, shortcut=fn() { action.get() }) |> ignore
    layer.val = Some(root.box(fn(l) { l.over(Is(true)) |> ignore }))
  })
  t.draw()
  t.tab()
  t.run_for(tip_settled_ms)
  assert_true(t.find("Ctrl+P") is Some(_))
  action.set("files.next")
  t.draw()
  assert_true(t.find("Ctrl+P") is None)
  assert_true(t.find("Alt+N") is Some(_))
  set_shortcuts(before)
}

///|
test "a draggable icon button leaves a tap to the button and a move to the area under it" {
  for platform in [0, 2] {
    let presses = Ref(0)
    let dragged : Array[@view.DragIs] = []
    let t = @ui.Tester::new(fn(_c) {  }, w=200.0, h=100.0, platform~)
    t.check_looks(false)
    @ui.set_view_app(fn(root) {
      root.box(fn(area) {
        area
        .width(Is(Some(120.0)))
        .height(Is(Some(80.0)))
        .gesture(@ui.touch_slop(), drag=fn(d) { dragged.push(d.kind) })
        |> ignore
        icon_button_node(area, "more", fn() { "Tools" }, fn() { presses.val += 1 }, size=40.0, icon_size=20.0, drag_through=true)
        |> ignore
      }) |> ignore
    })
    t.draw()
    let (x, y, _, _) = t.get(Button, label="Tools").rect
    let (x, y) = (x + 20.0, y + 20.0)
    let input = fn(kind : Int, px : Double, py : Double) {
      if platform == 0 { t.touch(kind, px, py) } else { t.touch_raw(kind, 1, px, py, t.time()) }
    }
    input(0, x, y)
    input(2, x, y)
    assert_eq(presses.val, 1)
    assert_true(dragged.is_empty())
    input(0, x, y)
    input(1, x + 30.0, y)
    input(2, x + 30.0, y)
    assert_eq(presses.val, 1, msg="a drag is not a button press")
    assert_eq(dragged, [Down, Up], msg="platform \{platform}")
  }
}

///|
test "a draggable Screen icon button's long press shows its changing tip without clicking" {
  let label = @signals.signal("Open tools")
  let count = Ref(0)
  let t = @ui.Tester::new(fn(_c) {  }, w=200.0, h=140.0, platform=2)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    let layer : Ref[@view.View?] = Ref(None)
    let tips = TipLayer::new(fn() { layer.val })
    icon_button_node(root, "more", fn() { label.get() }, fn() { count.val += 1 }, tips~, size=40.0, icon_size=20.0, drag_through=true)
    |> ignore
    layer.val = Some(root.box(fn(v) { v.over(Is(true)) |> ignore }))
  })
  t.draw()
  let (x, y, _, _) = t.get(Button, label="Open tools").rect
  t.touch_raw(0, 1, x + 20.0, y + 20.0, t.time())
  t.run_for(@ui.long_press_ms + tip_settled_ms)
  assert_true(t.semantics().any(fn(s) { s.role == Tooltip && s.label == "Open tools" }))
  label.set("Close tools")
  t.draw()
  assert_true(t.semantics().any(fn(s) { s.role == Tooltip && s.label == "Close tools" }))
  t.touch_raw(2, 1, x + 20.0, y + 20.0, t.time())
  assert_eq(count.val, 0)
}

///|
test "an icon button keeps its finger reach outside the drawn circle" {
  for size in [32.0, 40.0] {
    let count = Ref(0)
    let t = @ui.Tester::new(fn(_c) {  }, w=200.0, h=120.0, platform=2)
    t.check_looks(false)
    @ui.set_view_app(fn(root) {
      root.padding(Is((20.0, 20.0, 20.0, 20.0))) |> ignore
      icon_button_node(root, "copy", fn() { "Copy" }, fn() { count.val += 1 }, size~) |> ignore
    })
    t.draw()
    let (x, y, _, _) = t.get(Button, label="Copy").rect
    let (px, py) = (x - 1.0, y + size / 2.0)
    assert_eq(t.press_target_at(px, py).map(fn(s) { s.label }), Some("Copy"))
    t.touch_raw(0, 1, px, py, t.time())
    t.touch_raw(2, 1, px, py, t.time())
    assert_eq(count.val, 1, msg="size \{size}")
  }
}
