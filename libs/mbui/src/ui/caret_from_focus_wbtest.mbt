// A field of the window's tree blinks its caret from the moment it is given the focus, however that comes (the app's
// Field::focus, a layer opening with it, Tab, a press on it), as an old view's field, built as it is first shown,
// blinks from then: shown at once, hidden a blink later, shown again a blink after that.

///|
/// The field's caret seen to blink from `at` (the moment the focus came to it, the test's clock there or before it):
/// shown at it, still shown a hair before a blink from it, hidden a hair after, still hidden a hair before two blinks,
/// shown again a hair after.
fn blinks_from(t : Tester, at : Double, how : String) -> Unit raise {
  let to = fn(when : Double) { t.run_for(when - t.fake.time) }
  let p = caret_blink()
  assert_eq(carets_drawn().length(), 1, msg="\{how}: shown as it is given the focus")
  for step in [(p - 1.0, 1), (p + 1.0, 0), (2.0 * p - 1.0, 0), (2.0 * p + 1.0, 1)] {
    let (d, want) = step
    to(at + d)
    assert_eq(carets_drawn().length(), want, msg="\{how}: \{d} ms after it was given the focus")
  }
}

///|
/// A button of the tree's named `label`, 80 by 40, taking the focus.
fn caret_button(parent : @view.View, label : String) -> @view.View {
  parent.box(fn(b) {
    b
    .width(Is(Some(80.0)))
    .height(Is(Some(40.0)))
    .presses(Is(true))
    .focusable(Is(true))
    .says(Is(Some(@view.said(Button, label~))))
    .on_press(fn() {  })
    |> ignore
  })
}

///|
test "a field of the window's tree given the focus by the app shows its caret at once, blinking from then" {
  let f = Field::new(text="abc")
  let t = Tester::new(fn(_) {  }, w=300.0, h=100.0, platform=0)
  set_view_app(fn(root) { field(root, f, label="名字") |> ignore })
  t.draw()
  t.run_for(caret_blink_ms + 100.0)
  let at = t.fake.time
  f.focus()
  t.draw()
  blinks_from(t, at, "Field::focus")
}

///|
test "a field of the window's tree a layer gives the focus as it opens shows its caret at once, blinking from then" {
  let open = @signals.signal(false)
  let f = Field::new(text="abc")
  let t = Tester::new(fn(_) {  }, w=300.0, h=200.0, platform=0)
  set_view_app(fn(root) {
    caret_button(root, "底下") |> ignore
    root.show(fn() { open.get() }, fn(layer) {
      layer.over(Is(true)).modal(Is(true)).width(Is(Some(300.0))).height(Is(Some(200.0))) |> ignore
      let v = field(layer, f, label="名字", max_lines=1)
      layer.focus_opens(v) |> ignore
    })
  })
  t.draw()
  t.run_for(caret_blink_ms + 100.0)
  let at = t.fake.time
  open.set(true)
  t.draw()
  assert_true(f.focused())
  blinks_from(t, at, "focus_opens")
}

///|
test "a field of the window's tree Tab moves the focus to shows its caret at once, blinking from then" {
  let f = Field::new(text="abc")
  let t = Tester::new(fn(_) {  }, w=300.0, h=200.0, platform=0)
  set_view_app(fn(root) {
    caret_button(root, "前面") |> ignore
    field(root, f, label="名字", max_lines=1) |> ignore
  })
  t.draw()
  t.act(Button, Focus, label="前面")
  t.run_for(caret_blink_ms + 100.0)
  let at = t.fake.time
  t.key(key_tab)
  assert_true(f.focused())
  blinks_from(t, at, "Tab")
}

///|
test "a field of the window's tree the focus leaves and comes back to blinks from when it came back" {
  let f = Field::new(text="abc")
  let t = Tester::new(fn(_) {  }, w=300.0, h=200.0, platform=0)
  set_view_app(fn(root) {
    caret_button(root, "前面") |> ignore
    field(root, f, label="名字", max_lines=1) |> ignore
  })
  t.draw()
  t.run_for(caret_blink_ms + 100.0)
  let first = t.fake.time
  f.focus()
  t.draw()
  blinks_from(t, first, "first given it")
  // (away a blink and a half and more: back in the half of the first's beat its caret was hidden in)
  t.act(Button, Focus, label="前面")
  assert_true(!f.focused())
  t.run_for(caret_blink_ms * 1.5 + 100.0)
  assert_eq(carets_drawn().length(), 0, msg="away: no caret")
  let back = t.fake.time
  f.focus()
  t.draw()
  blinks_from(t, back, "given it back")
}

///|
test "a field of the window's tree pressed shows its caret at once, blinking from the press" {
  let f = Field::new(text="abc")
  let t = Tester::new(fn(_) {  }, w=300.0, h=100.0, platform=0)
  set_view_app(fn(root) { field(root, f, label="名字") |> ignore })
  t.draw()
  t.run_for(caret_blink_ms + 100.0)
  let at = t.fake.time
  t.tap(20.0, 10.0)
  assert_true(f.focused())
  blinks_from(t, at, "pressed")
}
