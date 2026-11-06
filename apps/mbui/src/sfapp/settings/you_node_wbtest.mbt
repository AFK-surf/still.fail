// The current-person/device mark keeps its old look while its words and theme change in the retained tree.

///|
test "a current-device mark as a node follows words and theme and is removed with its parent" {
  @sf.set_dark(Some(false))
  let words = @signals.signal("This device")
  let shown = @signals.signal(true)
  let id : Ref[@view.NodeId?] = Ref(None)
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=400.0, h=200.0, platform=0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.lines_up(Is(Some(Start))) |> ignore
    root.show(fn() { shown.get() }, fn(p) { id.val = Some(you_node(p, fn() { words.get() }).id()) })
  })
  t.draw()
  let tree = @ui.view_tree().unwrap()
  let first = id.val.unwrap()
  for dark in [false, true] {
    @sf.set_dark(Some(dark))
    t.draw()
    let mark = tree.drawn_of(first).unwrap()
    let text = tree.drawn().filter(fn(d) { d.words == words.get() })
    assert_eq(text.length(), 1)
    assert_eq((mark.ground, text[0].ink), (@sf.palette_of(dark).accent_bg, @sf.palette_of(dark).accent_text))
    assert_eq(mark.radius, @ui.tree_theme().corner(Md))
    assert_eq((text[0].x - mark.x, mark.w - text[0].w), (6.0, 12.0))
    assert_eq(text[0].words_look.size, @ui.style_words(you_words).size)
    assert_true(text[0].words_look.wrap)
  }
  words.set("Current")
  t.draw()
  assert_eq(id.val, Some(first))
  assert_true(t.query(Text, label="Current") is Some(_))
  assert_true(t.query(Text, label="This device") is None)
  shown.set(false)
  t.draw()
  assert_false(tree.lives(first))
  shown.set(true)
  t.draw()
  assert_true(id.val.unwrap() != first)
  assert_true(t.query(Text, label="Current") is Some(_))
  @sf.set_dark(None)
}

///|
test "a current-device mark as a node wraps and grows for long words" {
  let words = @signals.signal("Here")
  let id : Ref[@view.NodeId?] = Ref(None)
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=400.0, h=250.0, platform=2)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.box(fn(column) {
      column.width(Is(Some(90.0))).lines_up(Is(Some(Start))) |> ignore
      id.val = Some(you_node(column, fn() { words.get() }).width(Is(Some(90.0))).id())
    }) |> ignore
  })
  t.draw()
  let tree = @ui.view_tree().unwrap()
  let short_h = tree.drawn_of(id.val.unwrap()).unwrap().h
  let long = "A device with a long translated name"
  words.set(long)
  t.draw()
  assert_true(t.lines_of(long).length() > 1)
  assert_true(tree.drawn_of(id.val.unwrap()).unwrap().h > short_h)
  assert_true(t.query(Text, label=long) is Some(_))
}

///|
test "a current-device mark as a node leaves its row's input and accessibility intact" {
  for platform in [0, 2] {
    let pressed = Ref(0)
    let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=400.0, h=200.0, platform~)
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(@sf.ui_theme_now)
      root.box(fn(row) {
        row.row(Is(true)).width(Is(Some(180.0))).height(Is(Some(44.0))).lines_up(Is(Some(Middle)))
        .says(Is(Some(@view.said(Button, label="Open")))) |> ignore
        @sf.presses_node(row, fn() { pressed.val += 1 })
        you_node(row, fn() { "Here" }) |> ignore
      }) |> ignore
    })
    t.draw()
    t.tab()
    assert_eq(t.focused().map(fn(s) { s.label }), Some("Open"))
    t.enter()
    t.key(@ui.key_space)
    let (x, y, w, h) = t.rect_of("Here").unwrap()
    t.tap(x + w / 2.0, y + h / 2.0)
    t.act(Button, Activate, label="Open")
    assert_eq(pressed.val, 4)
    assert_eq(t.semantics().filter(fn(s) { s.role == Button }).length(), 1)
  }
}
