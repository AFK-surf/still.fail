// The focus in what is laid out nowhere waits for it (Tree::outs_told's focus_parked): laid out again, nothing having
// taken the focus meanwhile, it has it again (a sidebar hidden while the device waits in the lock, its 新建对话);
// the focus come meanwhile to an old view's field, it stays there as that comes back.

///|
/// A tree's button 树的按钮 in a box laid out nowhere while `hidden`, beside an old view's field 旧字段.
fn parked_tester(hidden : @signals.Signal[Bool]) -> Tester {
  let field = Field::new()
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  set_view_app(fn(root) {
    old(root, fn(c) { c.editor("parked/field", placeholder="旧字段", field~) |> ignore }).height(Is(Some(60.0))) |> ignore
    root.box(fn(side) {
      side.laid_nowhere(By(fn() { hidden.get() })) |> ignore
      side.box(fn(x) {
        x
        .width(Is(Some(80.0)))
        .height(Is(Some(40.0)))
        .presses(Is(true))
        .focusable(Is(true))
        .says(Is(Some(@view.said(Button, label="树的按钮"))))
        .on_press(fn() {  })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
fn focus_named(t : Tester) -> String {
  t.focused().map(fn(s) { "\{s.role} \{s.label}" }).unwrap_or("none")
}

///|
test "the focus in what is laid out nowhere: back on it as it is laid out again, nothing having taken it meanwhile" {
  let hidden = @signals.signal(false)
  let t = parked_tester(hidden)
  t.key(key_tab)
  t.key(key_tab)
  t.draw()
  let was = focus_named(t)
  assert_eq(was, "Button 树的按钮")
  hidden.set(true)
  t.draw()
  let gone = focus_named(t)
  hidden.set(false)
  t.draw()
  assert_eq((gone, focus_named(t)), ("none", "Button 树的按钮"))
}

///|
test "the focus in what is laid out nowhere, come meanwhile to an old view's field: on the field still as that is laid out again" {
  let hidden = @signals.signal(false)
  let t = parked_tester(hidden)
  t.key(key_tab)
  t.key(key_tab)
  t.draw()
  assert_eq(focus_named(t), "Button 树的按钮")
  hidden.set(true)
  t.draw()
  t.tap_text("旧字段")
  t.draw()
  let on_field = focus_named(t)
  hidden.set(false)
  t.draw()
  assert_eq((on_field, focus_named(t)), ("TextField 旧字段", "TextField 旧字段"))
}
