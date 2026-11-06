// The settings' wide button as a node: its states, foot placement, input and lifetime.

///|
priv struct WideButtonTestState {
  label : String
  primary : Bool
  busy : Bool
  enabled : Bool
  danger : Bool
} derive(Eq)

///|
fn wide_button_test(
  state : @signals.Signal[WideButtonTestState],
  panel : @signals.Signal[Bool],
  there : @signals.Signal[Bool],
  pressed : Ref[Int],
  native? : @ui.Pointing = Mouse,
) -> @ui.Tester {
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=200.0, platform=0, native~, pointing=native)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    root.box(fn(column) {
      column.width(Is(Some(360.0))) |> ignore
      column.show(fn() { there.get() }, fn(place) {
        place.width_share(Is(1.0)) |> ignore
        wide_button_foot_node(
          place,
          fn() { if panel.get() { Some([34.0, 34.0, 34.0, 34.0]) } else { None } },
          fn(foot) {
            wide_button_node(
              foot,
              fn() { state.get().label },
              fn() { state.get().primary },
              fn() { pressed.val += 1 },
              busy=fn() { state.get().busy },
              enabled=fn() { state.get().enabled },
              danger=fn() { state.get().danger },
            )
            |> ignore
          },
        )
        |> ignore
      })
    })
    |> ignore
  })
  t.draw()
  t
}

///|
fn wide_button_state() -> WideButtonTestState {
  { label: "Save", primary: false, busy: false, enabled: true, danger: false }
}

///|
test "wide button node follows its label, look and busy state without losing its identity" {
  let first = wide_button_state()
  let state = @signals.signal(first, same=fn(a, b) { a == b })
  let t = wide_button_test(state, @signals.signal(false), @signals.signal(true), Ref(0))
  let id = t.get(Button, label="Save").id
  let p = theme().p
  let cases = [
    (first, alpha(p.text, 0.08), p.text, false),
    ({ ..first, label: "Changed", primary: true }, p.text, p.bg, false),
    ({ ..first, label: "Working", primary: true, busy: true }, p.text, p.bg, true),
    ({ ..first, label: "Disabled", primary: true, enabled: false }, p.line, p.bg, true),
    ({ ..first, label: "Delete", primary: true, danger: true }, p.red, 0xFFFFFFFFL, false),
    ({ ..first, label: "Cannot delete", primary: true, danger: true, enabled: false }, alpha(p.red, 0.4), 0xFFFFFFFFL, true),
    ({ ..first, label: "Quiet", enabled: false, danger: true }, alpha(p.text, 0.08), p.text, true),
  ]
  for (next, ground, ink, disabled) in cases {
    state.set(next)
    t.draw()
    let button = t.get(Button, label=next.label)
    let rects = t.drawn_rect_corners()
    assert_eq(button.id, id, msg=next.label)
    assert_eq(button.disabled, disabled, msg=next.label)
    assert_true(rects.iter().any(fn(r) { r.2 == button.rect.2 && r.3 == 46.0 && r.4 == ground && r.5 == (23.0, 23.0, 23.0, 23.0) }), msg=next.label)
    assert_true(t.drawn_glyphs().iter().all(fn(g) { g.2 == ink }), msg=next.label)
    assert_eq(t.drawn_instances().iter().any(fn(i) { i[5] == 10.0 }), next.busy, msg=next.label)
  }
}

///|
test "wide button foot follows the panel's corners and keeps twelve above the 46-high capsule" {
  let panel = @signals.signal(false, same=fn(a, b) { a == b })
  let t = wide_button_test(@signals.signal(wide_button_state()), panel, @signals.signal(true), Ref(0))
  let alone = t.get(Button, label="Save").rect
  let alone_in = foot_capsule_of(None, 46.0, 12.0, 12.0)
  assert_eq(alone, (alone_in.0, 12.0, 360.0 - alone_in.0 - alone_in.1, 46.0))
  panel.set(true)
  t.draw()
  let in_panel = t.get(Button, label="Save").rect
  let insets = foot_capsule_of(Some([34.0, 34.0, 34.0, 34.0]), 46.0, 12.0, 12.0)
  assert_eq(in_panel, (insets.0, 12.0, 360.0 - insets.0 - insets.1, 46.0))
  assert_true(insets.0 == insets.1 && insets.0 == insets.2 && insets.0 != alone_in.0)
}

///|
test "wide button node answers mouse, touch, keyboard and accessibility only while enabled and idle" {
  let first = wide_button_state()
  let state = @signals.signal(first, same=fn(a, b) { a == b })
  let pressed = Ref(0)
  let t = wide_button_test(state, @signals.signal(false), @signals.signal(true), pressed)
  let button = t.get(Button, label="Save")
  let (x, y) = (button.rect.0 + button.rect.2 / 2.0, button.rect.1 + 23.0)
  t.touch(0, x, y)
  t.touch(2, x, y)
  t.touch_raw(0, 1, x, y, t.time())
  t.touch_raw(2, 1, x, y, t.time())
  t.key_told(@ui.key_tab, 0, t.time())
  t.key_told(enter_code, 0, t.time())
  t.key_told(space_code, 0, t.time())
  t.ctx().ask_action(button.id, Activate)
  assert_eq(pressed.val, 5)
  for next in [{ ..first, busy: true }, { ..first, enabled: false }] {
    state.set(next)
    assert_eq(t.focused().map(fn(s) { s.label }), None)
    t.key_told(enter_code, 0, t.time())
    t.key_told(space_code, 0, t.time())
    t.ctx().ask_action(button.id, Activate)
    t.touch(0, x, y)
    t.touch(2, x, y)
    t.touch_raw(0, 1, x, y, t.time())
    t.touch_raw(2, 1, x, y, t.time())
    assert_eq(pressed.val, 5)
  }
  state.set(first)
  t.touch(0, x, y)
  state.set({ ..first, busy: true })
  t.touch(2, x, y)
  assert_eq(pressed.val, 5, msg="became busy under the hand")
}

///|
test "wide button's spinner and press are released when the button leaves the tree" {
  let first = wide_button_state()
  let state = @signals.signal(first, same=fn(a, b) { a == b })
  let there = @signals.signal(true, same=fn(a, b) { a == b })
  let t = wide_button_test(state, @signals.signal(false), there, Ref(0), native=Finger)
  let tree = @ui.view_tree().unwrap()
  let button = t.get(Button, label="Save")
  t.touch(0, button.rect.0 + 20.0, button.rect.1 + 20.0)
  state.set({ ..first, busy: true })
  t.draw()
  assert_true(tree.cycle_read())
  there.set(false)
  t.draw()
  assert_false(tree.cycle_read())
  assert_true(t.query(Button, label="Save") is None)
}
