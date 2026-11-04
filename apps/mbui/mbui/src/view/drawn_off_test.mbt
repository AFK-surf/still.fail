// A layout motion is drawn off its destination but found there (View::drawn_off). Its hit, semantics and direct
// geometry must agree even before the motion ends; ordinary offsets and scales still move them together.

///|
test "a layout motion's drawing leaves its button's hit at the same place as its semantics and geometry" {
  let clicked = Ref(0)
  let at : Ref[@view.View?] = Ref(None)
  let off = @signals.signal((120.0, 60.0))
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(holder) {
      holder.width(Is(Some(100.0))).height(Is(Some(60.0))).offset(Is((20.0, 30.0)))
      .drawn_off(By(fn() { off.get() })).scale(Is(0.5), about=@view.At(0.0, 0.0)) |> ignore
      at.val = Some(holder.box(fn(button) {
        button.width(Is(Some(80.0))).height(Is(Some(40.0))).drawn_off(Is((20.0, 10.0)))
        .says(Is(Some(@view.said(Button, label="send")))).on_press(fn() { clicked.val += 1 }) |> ignore
      }))
    }) |> ignore
  })
  tree.frame(400.0, 300.0) |> ignore
  let button = at.val.unwrap()
  let (x, y, w, h) = button.rect()
  assert_eq((x, y, w, h), (20.0, 30.0, 40.0, 20.0))
  assert_eq(tree.said_order()[0].rect, button.rect())
  assert_eq(tree.target_at(x + w / 2.0, y + h / 2.0), @view.Pressed(button.id()))
  assert_true(tree.press(x + w / 2.0, y + h / 2.0))
  assert_eq(clicked.val, 1)
  let drawn = tree.drawn().filter(fn(d) { d.id == button.id() })[0]
  assert_eq(tree.drawn_of(button.id()), Some(drawn))
  assert_eq(tree.target_at(drawn.x + drawn.w / 2.0, drawn.y + drawn.h / 2.0), @view.Nothing)
  off.set((0.0, 0.0))
  tree.frame(400.0, 300.0) |> ignore
  assert_eq(tree.target_at(x + w / 2.0, y + h / 2.0), @view.Pressed(button.id()))
}
