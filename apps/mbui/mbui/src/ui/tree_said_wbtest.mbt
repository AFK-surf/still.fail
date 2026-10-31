// What is read out of the window where it is a tree (Ctx::semantics_spliced): its nodes that say what they are, in its
// order, each old view's widgets at its node, a node's press done as a screen reader asks it, one taking no presses
// read out and done nothing.

///|
/// A tree button ("前一个") before an old view with a button of its own ("旧的"), a separator, another tree button
/// ("后一个") taking presses as `on` says: how many times each tree button was pressed.
fn said_tester(on : @signals.Signal[Bool], before : Ref[Int], after : Ref[Int]) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  set_view_app(fn(root) {
    root.row(Is(true)) |> ignore
    root.box(fn(b) {
      b
      .width(Is(Some(80.0)))
      .height(Is(Some(40.0)))
      .on_press(fn() { before.val = before.val + 1 })
      .says(Is(Some(@view.said(Button, label="前一个"))))
      |> ignore
    })
    |> ignore
    root.box(fn(v) {
      v.width(Is(Some(120.0))) |> ignore
      old(v, fn(c) {
        let id = c.id("old")
        c.clicked(id) |> ignore
        c.box(w=Px(80.0), h=Px(40.0), id~, label="旧的", fn() {  }) |> ignore
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
    root.box(fn(s) { s.width(Is(Some(1.0))).height(Is(Some(40.0))).says(Is(Some(@view.said(Separator)))) |> ignore })
    |> ignore
    root.box(fn(b) {
      b
      .width(Is(Some(80.0)))
      .height(Is(Some(40.0)))
      .presses(By(fn() { on.get() }))
      .on_press(fn() { after.val = after.val + 1 })
      .says(Is(Some(@view.said(Button, label="后一个"))))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
test "read out of the window's tree: its nodes in its order, an old view's widgets at its node, a separator said so" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let t = said_tester(on, Ref(0), Ref(0))
  let read = t.semantics().filter(fn(s) { !s.hidden }).map(fn(s) { (s.role, s.label) })
  assert_eq(read, [(Button, "前一个"), (Button, "旧的"), (Separator, ""), (Button, "后一个")])
}

///|
test "a node of the tree's pressed as a screen reader asks it: its press, once; taking no presses, read out disabled, done nothing" {
  let on = @signals.signal(true, same=fn(a, b) { a == b })
  let before = Ref(0)
  let after = Ref(0)
  let t = said_tester(on, before, after)
  t.act(Button, Activate, label="前一个")
  assert_eq(before.val, 1)
  on.set(false)
  t.draw()
  let s = t.get(Button, label="后一个")
  assert_eq((s.disabled, s.actions), (true, []))
  t.act(Button, Activate, label="后一个")
  assert_eq(after.val, 0)
  on.set(true)
  t.draw()
  t.act(Button, Activate, label="后一个")
  assert_eq(after.val, 1)
}
