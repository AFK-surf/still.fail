// A pill made once follows its contents and theme, stays a single line, and leaves input to its enclosing control.

///|
test "a pill as a node: words, tone, icon and theme change on the same node" {
  set_dark(Some(false))
  let words = @signals.signal("Waiting")
  let tone : @signals.Signal[PillTone] = @signals.signal(Amber)
  let icon = @signals.signal("check")
  let id : Ref[@view.NodeId?] = Ref(None)
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=400.0, h=200.0, platform=0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.lines_up(Is(Some(Start))) |> ignore
    id.val = Some(pill_node(root, fn() { words.get() }, tone=fn() { tone.get() }, icon=fn() { icon.get() }).id())
  })
  t.draw()
  let tree = @ui.view_tree().unwrap()
  let node = id.val.unwrap()
  let old_icon = tree.drawn().filter(fn(d) { d.w == 14.0 && d.h == 14.0 && !d.shapes.is_empty() })[0].shapes
  for dark in [false, true] {
    set_dark(Some(dark))
    let p = palette_of(dark)
    for colors in [
      (Neutral, p.neutral_bg, p.muted), (Green, p.green_bg, p.green_ink), (Blue, p.blue_bg, p.blue),
      (Amber, p.amber_bg, p.warn_ink), (Red, p.red_bg, p.red), (Accented, p.accent_bg, p.accent_text),
    ] {
      tone.set(colors.0)
      t.draw()
      let d = tree.drawn_of(node).unwrap()
      assert_eq((d.h, d.ground), (22.0, colors.1))
      let text = tree.drawn().filter(fn(d) { d.words == words.get() })
      assert_eq(text.length(), 1)
      assert_eq(text[0].ink, colors.2)
      assert_false(text[0].words_look.wrap)
      let mark = tree.drawn().filter(fn(d) { d.w == 14.0 && d.h == 14.0 && !d.shapes.is_empty() })
      assert_eq(mark.length(), 1)
      assert_eq(mark[0].tint, colors.2)
      assert_eq(id.val, Some(node))
    }
  }
  words.set("Failed")
  icon.set("wait")
  t.draw()
  assert_true(t.query(Text, label="Failed") is Some(_))
  assert_true(t.query(Text, label="Waiting") is None)
  let mark = tree.drawn().filter(fn(d) { d.w == 14.0 && d.h == 14.0 && !d.shapes.is_empty() })
  assert_eq(mark.length(), 1)
  assert_true(mark[0].shapes != old_icon, msg="a new icon changes its drawing")
  icon.set("")
  words.set("")
  t.draw()
  assert_eq(tree.drawn().filter(fn(d) { d.w == 14.0 && d.h == 14.0 && !d.shapes.is_empty() }).length(), 0)
  assert_true(t.query(Text, label="Failed") is None)
  words.set("Again")
  icon.set("check")
  t.draw()
  assert_eq(id.val, Some(node))
  assert_true(t.query(Text, label="Again") is Some(_))
  set_dark(None)
}

///|
test "a pill as a node: long words end in an ellipsis in a narrow column, with the icon kept" {
  let words = @signals.signal("A very long status that does not fit in the row")
  let id : Ref[@view.NodeId?] = Ref(None)
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=400.0, h=200.0, platform=0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.box(fn(b) {
      b.width(Is(Some(120.0))) |> ignore
      id.val = Some(pill_node(b, fn() { words.get() }, icon=fn() { "check" }).id())
    }) |> ignore
  })
  t.draw()
  let lines = t.lines_of(words.get())
  assert_eq(lines.length(), 1)
  assert_true(lines[0].has_suffix("…"), msg="\{lines}")
  assert_true(t.query(Text, label=words.get()) is Some(_), msg="the full words remain available to a screen reader")
  let tree = @ui.view_tree().unwrap()
  let box = tree.drawn_of(id.val.unwrap()).unwrap()
  assert_eq((box.w, box.h), (120.0, 22.0))
  assert_eq(tree.drawn().filter(fn(d) { d.w == 14.0 && d.h == 14.0 && !d.shapes.is_empty() }).length(), 1)
  words.set("OK")
  t.draw()
  assert_eq(t.lines_of("OK"), ["OK"])
}

///|
test "a pill as a node: a long title gives way before its short badge" {
  let title = "A station with a very long name"
  let badge : Ref[@view.NodeId?] = Ref(None)
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=400.0, h=200.0, platform=0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.box(fn(row) {
      row.row(Is(true)).width(Is(Some(180.0))).gap(Is(8.0)).lines_up(Is(Some(Middle))) |> ignore
      words_node(row, fn() { title }, fn() { @ui.text_style(size=Body, wrap=false) })
      .cuts(Is(true)).min_width(Is(Some(0.0))).allow_ellipsis(Is(true)) |> ignore
      badge.val = Some(pill_node(row, fn() { "Pending" }, tone=fn() { Amber }).id())
    }) |> ignore
  })
  t.draw()
  let title_lines = t.lines_of(title)
  assert_eq(title_lines.length(), 1)
  assert_true(title_lines[0].has_suffix("…"), msg="\{title_lines}")
  assert_eq(t.lines_of("Pending"), ["Pending"])
  let d = @ui.view_tree().unwrap().drawn_of(badge.val.unwrap()).unwrap()
  assert_true(d.x + d.w <= 180.0)
}

///|
test "a pill as a node: a parent row takes touch, mouse, keyboard and accessibility presses" {
  for platform in [0, 2] {
    let pressed = Ref(0)
    let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=400.0, h=200.0, platform~)
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(ui_theme_now)
      root.box(fn(row) {
        row.row(Is(true)).width(Is(Some(180.0))).height(Is(Some(44.0))).lines_up(Is(Some(Middle)))
        .says(Is(Some(@view.said(Button, label="Open")))) |> ignore
        presses_node(row, fn() { pressed.val = pressed.val + 1 })
        pill_node(row, fn() { "Pending" }, tone=fn() { Amber }) |> ignore
      }) |> ignore
    })
    t.draw()
    t.tab()
    assert_eq(t.focused().map(fn(s) { s.label }), Some("Open"))
    t.enter()
    assert_eq(pressed.val, 1)
    t.key(@ui.key_space)
    assert_eq(pressed.val, 2)
    let (x, y, w, h) = t.rect_of("Pending").unwrap()
    t.tap(x + w / 2.0, y + h / 2.0)
    assert_eq(pressed.val, 3)
    t.act(Button, Activate, label="Open")
    assert_eq(pressed.val, 4)
    assert_eq(t.semantics().filter(fn(s) { s.role == Button }).length(), 1)
  }
}

///|
test "a pill as a node: removed with its parent and rebuilt with current contents" {
  let shown = @signals.signal(true)
  let words = @signals.signal("First")
  let id : Ref[@view.NodeId?] = Ref(None)
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=400.0, h=200.0, platform=0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.show(fn() { shown.get() }, fn(p) { id.val = Some(pill_node(p, fn() { words.get() }).id()) })
  })
  t.draw()
  let tree = @ui.view_tree().unwrap()
  let first = id.val.unwrap()
  shown.set(false)
  words.set("Second")
  t.draw()
  assert_false(tree.lives(first))
  assert_true(t.query(Text, label="First") is None)
  shown.set(true)
  t.draw()
  assert_true(tree.lives(id.val.unwrap()))
  assert_true(id.val.unwrap() != first)
  assert_true(t.query(Text, label="Second") is Some(_))
}
