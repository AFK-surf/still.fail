// A node of the window's tree that draws no words but says what it is called (View::says' label): found on screen by
// that, whole, as an old view's box is by its label (Compose's test finding a node by its contentDescription), where a
// finger reaches it, and pressed there; part of its label finds nothing.

///|
test "a node of the window's tree drawing no words, called 完成: found by =完成 and by 完成, where a finger reaches it, pressed there; by 完 nothing" {
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0, platform=0)
  let pressed = Ref(0)
  set_view_app(fn(root) {
    root.box(fn(b) {
      b
      .width(Is(Some(36.0)))
      .height(Is(Some(36.0)))
      .offset(Is((100.0, 50.0)))
      .ground(Is(0x3366CCFFL))
      .presses(Is(true))
      .says(Is(Some(@view.said(Button, label="完成"))))
      .on_press(fn() { pressed.val += 1 })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  assert_eq(t.locate("=完成"), [(118.0, 68.0)], msg="=完成: seen")
  assert_eq(t.locate("完成"), [(118.0, 68.0)], msg="完成: seen")
  assert_eq(t.reachable("=完成"), [(118.0, 68.0)], msg="=完成: where a finger reaches it")
  assert_eq(t.locate("完"), [], msg="part of it: nothing")
  assert_eq(t.locate("=完"), [], msg="=part of it: nothing")
  let (x, y) = t.reachable("=完成")[0]
  t.tap(x, y)
  assert_eq(pressed.val, 1, msg="pressed where it was found")
}
