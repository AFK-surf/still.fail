// The library's lines to type in as nodes of the window's tree (input_node, textarea_node) as their old ones do
// (input, textarea): what is typed is their Field's, words set on the Field from outside shown; Enter gives a line's
// words up once, a textarea's takes a new line; disabled, no press nor the focus; a secret's words said as none; in a
// layer that gives the focus to it as it opens, closed and opened again with the same Field, the focus back where it
// was each time and the Field another field's then (one held still by one let go would abort: ui's field). The editor
// itself (the input method, what is picked, undo) is ui's field's, tested there (tree_field_wbtest).

///|
/// A node "别处" taking the focus at the window's top, then in a box 300 wide what `make` makes there (with keyboard and
/// mouse, or `platform`).
fn field_node_case(make : (@view.View) -> Unit, platform? : Int = 0) -> @ui.Tester {
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=400.0, h=400.0, platform~)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.box(fn(e) {
      e
      .width(Is(Some(50.0)))
      .height(Is(Some(50.0)))
      .presses(Is(true))
      .focusable(Is(true))
      .says(Is(Some(@view.said(Button, label="别处"))))
      .on_press(fn() {  })
      |> ignore
    })
    |> ignore
    root.box(fn(b) {
      b.width(Is(Some(300.0))) |> ignore
      make(b)
    })
    |> ignore
  })
  t.draw()
  t
}

///|
/// The middle of what says it is a field to type in, labelled `label`.
fn field_middle(t : @ui.Tester, label : String) -> (Double, Double) raise {
  let (x, y, w, h) = t.get(TextField, label~).rect
  (x + w / 2.0, y + h / 2.0)
}

///|
test "input_node, keyboard and mouse or touch: tapped, the focus its; what is typed its Field's; Enter gives it up once, at that key" {
  for platform in [0, 2] {
    let f = @ui.Field::new()
    let said = []
    let t = field_node_case(platform~, fn(b) {
      input_node(b, f, placeholder="名字", submitted=fn(w) { said.push(w) }) |> ignore
    })
    let (x, y) = field_middle(t, "名字")
    t.tap(x, y)
    let focused = t.focused().map(fn(s) { s.label })
    t.type_text("新名")
    t.key_named("enter") |> ignore
    let once = said.copy()
    assert_eq((focused, f.text(), once), (Some("名字"), "新名", ["新名"]), msg="platform \{platform}")
  }
}

///|
test "input_node: words set on its Field from outside shown and said; typed on from there" {
  let f = @ui.Field::new(text="旧")
  let t = field_node_case(fn(b) { input_node(b, f, placeholder="名字") |> ignore })
  let before = (t.get(TextField, label="名字").value, t.drawn_glyphs().length())
  f.set("外面改的")
  t.draw()
  let after = (t.get(TextField, label="名字").value, t.drawn_glyphs().length())
  assert_eq((before, after), (("旧", 1), ("外面改的", 4)))
}

///|
test "input_node, secret: its words said as none, not drawn as written" {
  let f = @ui.Field::new(text="口令123")
  let t = field_node_case(fn(b) { input_node(b, f, placeholder="密码", secret=true) |> ignore })
  assert_eq((t.get(TextField, label="密码").value, t.find("口令123") is None), ("", true))
}

///|
test "input_node disabled: tapped, no focus and nothing typed in; written in and then disabled, the focus let go of at once" {
  let off = @signals.signal(true)
  let f = @ui.Field::new()
  let t = field_node_case(fn(b) { input_node(b, f, placeholder="名字", disabled=fn() { off.get() }) |> ignore })
  let (x, y) = field_middle(t, "名字")
  t.tap(x, y)
  t.type_text("字")
  let while_off = (t.focused().map(fn(s) { s.label }), f.text())
  off.set(false)
  t.draw()
  t.tap(x, y)
  let on = t.focused().map(fn(s) { s.label })
  off.set(true)
  // (at that cause, no frame drawn)
  let lost = t.focused().map(fn(s) { s.label })
  assert_eq((while_off, on, lost), ((None, ""), Some("名字"), None))
}

///|
test "textarea_node: Enter a new line in its words, nothing given up" {
  let f = @ui.Field::new()
  let t = field_node_case(fn(b) { textarea_node(b, f, placeholder="说明") |> ignore })
  let (x, y) = field_middle(t, "说明")
  t.tap(x, y)
  t.type_text("一")
  t.key_named("enter") |> ignore
  t.type_text("二")
  assert_eq(f.text(), "一\n二")
}

///|
test "input_node in a layer that gives it the focus as it opens: opened, its; closed, back on what had it; opened again with the same Field, its again" {
  let open = @signals.signal(false)
  let f = @ui.Field::new()
  let t = field_node_case(fn(b) {
    b.show(fn() { open.get() }, fn(layer) {
      layer.over(Is(true)).modal(Is(true)) |> ignore
      let v = input_node(layer, f, placeholder="名字")
      layer.focus_opens(v) |> ignore
    })
    |> ignore
  })
  t.act(Button, Focus, label="别处")
  let got = []
  for _ in 0..<2 {
    open.set(true)
    t.draw()
    let inside = t.focused().map(fn(s) { s.label })
    t.type_text("字")
    open.set(false)
    t.draw()
    got.push((inside, t.focused().map(fn(s) { s.label })))
  }
  assert_eq((got, f.text()), ([(Some("名字"), Some("别处")), (Some("名字"), Some("别处"))], "字字"))
}
