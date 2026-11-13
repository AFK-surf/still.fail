// Comma's parts as nodes, each as the hand and a screen reader meet it: a button pressed by Activate, by Tab and Enter,
// never while it is disabled; a checkbox and a toggle turned, read out on or off; a tag's ✕ taking it away; and every
// part at rest held to mbui's audit.

///|
/// A Tester of a 900 × 600 window, `make` making its tree in Comma's theme, drawn.
fn cm_case(make : (@view.View) -> Unit, dark? : Bool = false) -> @ui.Tester {
  let t = @ui.Tester::new(fn(_c) {  }, w=900.0, h=600.0, platform=0)
  set_dark(Some(dark))
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme)
    root.box(fn(page) {
      page.grow(Is(1.0)).padding(Is((24.0, 24.0, 24.0, 24.0))).gap(Is(12.0)).ground(By(fn() { colors().bg_primary }))
      |> ignore
      make(page)
    })
    |> ignore
  })
  t.draw()
  t
}

///|
test "a button is pressed by Activate and by Tab then Enter; a disabled one takes neither" {
  let (pressed, off_pressed) = (Ref(0), Ref(0))
  let t = cm_case(fn(p) {
    button_node(p, fn() { "Save" }, fn() { pressed.val += 1 }) |> ignore
    button_node(p, fn() { "Later" }, fn() { off_pressed.val += 1 }, hierarchy=SecondaryGray, disabled=fn() { true })
    |> ignore
  })
  t.act(Button, Activate, label="Save")
  t.tab()
  let focused = t.focused().map(fn(s) { s.label })
  t.enter()
  // (Tab once more: the disabled one is passed over)
  t.tab()
  let after = t.focused().map(fn(s) { s.label })
  assert_eq((pressed.val, focused, after != Some("Later"), off_pressed.val), (2, Some("Save"), true, 0))
}

///|
test "a checkbox and a toggle turn as they are activated, and are read out on and off" {
  let (check, switch) = (@signals.signal(false), @signals.signal(true))
  let t = cm_case(fn(p) {
    check_node(p, fn() { check.get() }, fn(v) { check.set(v) }, fn() { "Remember" }) |> ignore
    toggle_node(p, fn() { switch.get() }, fn(v) { switch.set(v) }, fn() { "Sync" }) |> ignore
  })
  let was = (t.get(Checkbox, label="Remember").check, t.get(Switch, label="Sync").check)
  t.act(Checkbox, Activate, label="Remember")
  t.act(Switch, Activate, label="Sync")
  t.run_for(ms_state_change)
  let now = (t.get(Checkbox, label="Remember").check, t.get(Switch, label="Sync").check)
  assert_eq((was, now, check.get(), switch.get()), ((Some(Off), Some(On)), (Some(On), Some(Off)), true, false))
}

///|
test "a tag's ✕ takes it away" {
  let shown = @signals.signal(true)
  let t = cm_case(fn(p) {
    p.show(fn() { shown.get() }, fn(s) { tag_node(s, fn() { "Design" }, tone=Brand, remove=fn() { shown.set(false) }) |> ignore })
    |> ignore
  })
  t.act(Button, Activate, label="移除 Design")
  t.run_for(ui_move_most)
  assert_eq((shown.get(), t.all(Button, label="移除 Design").length()), (false, 0))
}

///|
/// How long anything a structure makes or lets go takes at most to be there or gone.
let ui_move_most : Double = @ui.move_most_ms

///|
test "every part at rest, light and dark, holds to mbui's audit" {
  let faults = []
  for dark in [false, true] {
    let t = cm_case(dark~, fn(p) {
      p.box(fn(r) {
        r.row(Is(true)).gap(Is(12.0)).wraps(Is(Some(12.0))).lines_up(Is(Some(Middle))) |> ignore
        for h in [Primary, SecondaryColor, SecondaryGray, TertiaryColor, TertiaryGray, LinkColor, LinkGray, Destructive] {
          button_node(r, fn() { "Button" }, fn() {  }, hierarchy=h) |> ignore
        }
      })
      |> ignore
      p.box(fn(r) {
        r.row(Is(true)).gap(Is(12.0)).wraps(Is(Some(12.0))).lines_up(Is(Some(Middle))) |> ignore
        for k in [PillColor, PillOutline, BadgeColor, BadgeModern] {
          badge_node(r, fn() { "Label" }, tone=Success, kind=k, dot=true) |> ignore
        }
        tag_node(r, fn() { "Label" }, remove=fn() {  }) |> ignore
        check_node(r, fn() { true }, fn(_) {  }, fn() { "Checkbox" }) |> ignore
        toggle_node(r, fn() { true }, fn(_) {  }, fn() { "Toggle" }) |> ignore
        avatar_node(r, fn() { "Olivia Rhye" }, online=fn() { Some(true) }) |> ignore
      })
      |> ignore
      p.box(fn(b) {
        b.width(Is(Some(260.0))) |> ignore
        input_node(b, @ui.Field::new(), placeholder="olivia@untitledui.com", label="Email") |> ignore
      })
      |> ignore
    })
    t.run_for(ui_move_most)
    for f in t.audit() {
      faults.push((dark, f))
    }
  }
  assert_eq(faults, [])
}
