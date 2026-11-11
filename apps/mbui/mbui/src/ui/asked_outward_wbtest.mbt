// What the hand does on a node that does not answer it is asked of the first that holds it and does: a right click on
// a button in a row that has a menu opens the row's menu (Tree::menu_at), never past an old view's host or a modal
// layer.

///|
/// A row 300 by 100 at the window's top left, pressed counted in `pressed`, its menu asked counted in `menus` (where
/// `menu`); in it at its top left a node 120 by 40 that `inner` makes what it is.
fn outward_row(pressed : Ref[Int], menus : Ref[Int], menu : Bool, inner : (@view.View) -> Unit) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  set_view_app(fn(root) {
    root.box(fn(r) {
      r
      .width(Is(Some(300.0)))
      .height(Is(Some(100.0)))
      .says(Is(Some(@view.said(Button, label="Row"))))
      .on_press(fn() { pressed.val = pressed.val + 1 })
      |> ignore
      if menu {
        r.on_menu(fn(_) { menus.val = menus.val + 1 }) |> ignore
      }
      r.box(fn(v) {
        v.width(Is(Some(120.0))).height(Is(Some(40.0))) |> ignore
        inner(v)
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
test "a right click on a button in a row with a menu: the row's menu asked, the button not pressed" {
  let pressed = Ref(0)
  let menus = Ref(0)
  let button = Ref(0)
  let t = outward_row(pressed, menus, true, fn(v) {
    v.says(Is(Some(@view.said(Button, label="More")))).on_press(fn() { button.val = button.val + 1 }) |> ignore
  })
  t.right_click(20.0, 20.0)
  assert_eq((menus.val, button.val, pressed.val), (1, 0, 0))
  // (beside the button, in the row: its menu, as ever)
  t.right_click(200.0, 60.0)
  assert_eq(menus.val, 2)
}

///|
test "a right click in a modal layer in a row with a menu: the row not asked, nothing past the layer" {
  let pressed = Ref(0)
  let menus = Ref(0)
  let button = Ref(0)
  let t = outward_row(pressed, menus, true, fn(v) {
    v.modal(Is(true)) |> ignore
    v.box(fn(b) {
      b
      .width(Is(Some(60.0)))
      .height(Is(Some(30.0)))
      .says(Is(Some(@view.said(Button, label="In the layer"))))
      .on_press(fn() { button.val = button.val + 1 })
      |> ignore
    })
    |> ignore
  })
  t.right_click(20.0, 20.0)
  assert_eq((menus.val, button.val, pressed.val), (0, 0, 0))
}

///|
test "a right click on an old view hosted in a row with a menu: the old view's, the row not asked" {
  let pressed = Ref(0)
  let menus = Ref(0)
  let t = outward_row(pressed, menus, true, fn(v) { v.hosted() |> ignore })
  t.right_click(20.0, 20.0)
  assert_eq(menus.val, 0)
}
