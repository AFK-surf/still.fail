// A panel group keeps its own rows while its heading comes, changes and goes; dynamic rows remain in the group's own
// layout, and controls inside it keep their focus, actions and lifetime.

///|
test "panel group node: rows two apart, heading and lead only with a label, body kept through changes" {
  for width in [160.0, 320.0] {
    let label = @signals.signal("")
    let extra = @signals.signal(false)
    let open = @signals.signal(true)
    let made = Ref(0)
    let gone = Ref(0)
    let leads = Ref(0)
    let lead_gone = Ref(0)
    let pressed = Ref(0)
    let field = @ui.Field::new()
    let field_box : Ref[@view.View?] = Ref(None)
    let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=width, h=400.0, platform=0)
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(ui_theme_now)
      root.show(fn() { open.get() }, fn(slot) {
        panel_group_node(slot, label=fn() { label.get() }, lead=fn(line) {
          leads.val += 1
          line.owns(fn() { lead_gone.val += 1 }) |> ignore
          line.box(fn(mark) { mark.width(Is(Some(12.0))).height(Is(Some(12.0))) |> ignore }) |> ignore
        }, fn(group) {
          made.val += 1
          group.owns(fn() { gone.val += 1 }) |> ignore
          let editor = input_node(group, field, placeholder="Name")
          field_box.val = editor.parent()
          group.show(fn() { extra.get() }, fn(row) {
            button_node(row, fn() { "Extra" }, fn() { pressed.val += 1 }) |> ignore
          })
          button_node(group, fn() { "Apply" }, fn() { pressed.val += 1 }) |> ignore
        })
        |> ignore
      })
    })
    t.draw()
    // The text field's accessibility rectangle is its editor, inset in the input frame. Spacing is between the
    // group's direct children, so measure the frame instead.
    let frame = fn() { field_box.val.unwrap().laid_window_now() }
    let first = frame()
    let apply = t.get(Button, label="Apply").rect
    assert_eq((first.1, apply.1 - first.1 - first.3, made.val, leads.val), (0.0, 2.0, 1, 0))
    t.act(TextField, Focus, label="Name")
    t.type_text("hello")
    label.set("Settings")
    t.draw()
    assert_true(t.find("Settings") is Some(_))
    assert_true(frame().1 > first.1)
    assert_eq((made.val, gone.val, leads.val, t.focused().map(fn(s) { s.label }), field.text()), (1, 0, 1, Some("Name"), "hello"))
    let short_heading = frame().1
    label.set("A long heading that wraps beside its lead when the panel has little room")
    t.draw()
    assert_true(frame().1 > short_heading, msg="the label wraps at width \{width}")
    label.set("Options")
    extra.set(true)
    t.draw()
    let field_at = frame()
    let extra_at = t.get(Button, label="Extra").rect
    let apply_at = t.get(Button, label="Apply").rect
    assert_eq((extra_at.1 - field_at.1 - field_at.3, apply_at.1 - extra_at.1 - extra_at.3), (2.0, 2.0))
    assert_true(t.find("Options") is Some(_))
    assert_eq((made.val, leads.val, lead_gone.val, t.focused().map(fn(s) { s.label })), (1, 1, 0, Some("Name")))
    t.tap(extra_at.0 + extra_at.2 / 2.0, extra_at.1 + extra_at.3 / 2.0)
    assert_eq(pressed.val, 1)
    label.set("")
    extra.set(false)
    t.draw()
    assert_eq((frame().1, made.val, gone.val, lead_gone.val), (0.0, 1, 0, 1))
    t.act(Button, Focus, label="Apply")
    t.draw()
    t.key_named("enter") |> ignore
    assert_eq(pressed.val, 2)
    t.act(Button, Activate, label="Apply")
    assert_eq(pressed.val, 3)
    label.set("Again")
    t.draw()
    assert_eq((leads.val, lead_gone.val, made.val), (2, 1, 1))
    open.set(false)
    t.draw()
    assert_eq((gone.val, lead_gone.val), (1, 2))
  }
}

///|
test "panel group node without a lead updates or removes its label without remaking its body" {
  let label = @signals.signal("Quality")
  let made = Ref(0)
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=240.0, h=240.0)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    panel_group_node(root, label=fn() { label.get() }, fn(body) {
      made.val += 1
      button_node(body, fn() { "Automatic" }, fn() {  }) |> ignore
    }) |> ignore
  })
  t.draw()
  assert_true(t.find("Quality") is Some(_))
  let headed = t.get(Button, label="Automatic").rect.1
  label.set("")
  t.draw()
  assert_eq((t.find("Quality") is None, t.get(Button, label="Automatic").rect.1, made.val), (true, 0.0, 1))
  label.set("Frame rate")
  t.draw()
  assert_eq((t.find("Frame rate") is Some(_), t.get(Button, label="Automatic").rect.1, made.val), (true, headed, 1))
}
