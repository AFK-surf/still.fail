// A layer of an old view's anchored to a box of its (its own press in it), the window's tree's own button drawn over
// that press: a press there the tree's button's, outside the anchor, the layer dismissed as it goes down.

///|
test "a layer of an old view's anchored to a box with a press of its own, a button of the tree's over that press: a press there is the button's, outside the anchor, the layer dismissed as it goes down" {
  let told : Array[String] = []
  let inner_pressed = Ref(0)
  let button_pressed = Ref(0)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.show(fn() { true }, fn(b) {
      b.over(Is(true)) |> ignore
      old(b, fn(c) {
        c.box(dir=Row, w=Fill(1.0), h=Fill(1.0), fn() {
          c.box(w=Px(200.0), h=Px(300.0), fn() {  }) |> ignore
          let anchor = c.id("anchor")
          c.box(id=anchor, w=Px(60.0), h=Px(300.0), fn() {
            c.box(w=Px(60.0), h=Px(200.0), fn() {  }) |> ignore
            let inner = c.id("inner")
            c.box(id=inner, w=Px(60.0), h=Px(40.0), fn() {  }) |> ignore
            if c.clicked(inner) {
              inner_pressed.val = inner_pressed.val + 1
            }
          })
          |> ignore
          c.with_dismissed(fn(why) { told.push("\{why}") }, fn() {
            c.overlay("beside", anchor~, fn() { c.box(w=Px(100.0), h=Px(100.0), fn() {  }) |> ignore }) |> ignore
          })
        })
        |> ignore
      }).grow(Is(1.0))
      |> old_takes_own
      |> ignore
    })
    root.box(fn(k) {
      k
      .over(Is(true))
      .offset(Is((200.0, 200.0)))
      .width(Is(Some(60.0)))
      .height(Is(Some(60.0)))
      .on_press(fn() { button_pressed.val = button_pressed.val + 1 })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.host_says_finger(Some(false))
  t.draw()
  // (on the tree's button, over the anchor's own press)
  t.touch_at(0, 230.0, 220.0, t.time())
  let at_down = told.copy()
  t.touch_at(2, 230.0, 220.0, t.time())
  t.draw()
  assert_eq((at_down, button_pressed.val, inner_pressed.val), (["Outside"], 1, 0))
}
