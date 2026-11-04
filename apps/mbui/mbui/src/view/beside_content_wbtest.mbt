///|
test "a panel's layout knows the side of its scaled anchor as it is placed" {
  let scale = @signals.signal(2.0)
  let content_side = Ref(Bottom)
  let placed_side : Ref[Side?] = Ref(None)
  let t = Tree::new(fn(root) {
    let anchor = root.box(fn(a) {
      a.over(Is(true)).width(Is(Some(40.0))).height(Is(Some(40.0)))
      .offset(Is((100.0, 170.0))).scale(By(fn() { scale.get() }), about=At(0.0, 0.0)) |> ignore
    })
    root.box(fn(panel) {
      panel.width(Is(Some(60.0))).height(Is(Some(70.0))).beside(anchor.id(), side=Bottom) |> ignore
      panel.beside_content(fn(side) { content_side.val = side })
      panel.reacts(fn() { panel.went_told() }, fn(side) { placed_side.val = side })
    }) |> ignore
  })
  t.frame(300.0, 300.0, now=0.0) |> ignore
  assert_eq((content_side.val, placed_side.val), (Top, Some(Top)))
  scale.set(1.0)
  t.frame(300.0, 300.0, now=10.0) |> ignore
  assert_eq((content_side.val, placed_side.val), (Bottom, Some(Bottom)))
  t.dispose()
}

///|
test "a panel's layout follows an anchor inside another panel as it moves" {
  let y = @signals.signal(120.0)
  let content_side = Ref(Bottom)
  let placed_side : Ref[Side?] = Ref(None)
  let t = Tree::new(fn(root) {
    let anchor = root.box(fn(a) {
      a.over(Is(true)).width(Is(Some(10.0))).height(Is(Some(10.0)))
      .offset(By(fn() { (100.0, y.get()) })) |> ignore
    })
    let inner : Ref[View?] = Ref(None)
    root.box(fn(first) {
      first.width(Is(Some(100.0))).height(Is(Some(100.0))).beside(anchor.id(), side=Bottom) |> ignore
      inner.val = Some(first.box(fn(a) {
        a.over(Is(true)).width(Is(Some(20.0))).height(Is(Some(20.0))).offset(Is((0.0, 75.0))) |> ignore
      }))
    }) |> ignore
    root.box(fn(second) {
      second.width(Is(Some(60.0))).height(Is(Some(70.0))).beside(inner.val.unwrap().id(), side=Bottom) |> ignore
      second.beside_content(fn(side) { content_side.val = side })
      second.reacts(fn() { second.went_told() }, fn(side) { placed_side.val = side })
    }) |> ignore
  })
  t.frame(300.0, 300.0, now=0.0) |> ignore
  assert_eq((content_side.val, placed_side.val), (Top, Some(Top)))
  y.set(40.0)
  t.frame(300.0, 300.0, now=10.0) |> ignore
  assert_eq((content_side.val, placed_side.val), (Bottom, Some(Bottom)))
  t.dispose()
}

///|
test "a leaving panel keeps its content on the side where it was placed" {
  let y = @signals.signal(240.0)
  let on = @signals.signal(true)
  let content_side = Ref(Bottom)
  let placed_side : Ref[Side?] = Ref(None)
  let t = Tree::new(fn(root) {
    let anchor = root.box(fn(a) {
      a.over(Is(true)).width(Is(Some(40.0))).height(Is(Some(20.0)))
      .offset(By(fn() { (100.0, y.get()) })) |> ignore
    })
    root.show(fn() { on.get() }, leave=100.0, fn(panel) {
      panel.width(Is(Some(60.0))).height(Is(Some(70.0))).beside(anchor.id(), side=Bottom) |> ignore
      panel.beside_content(fn(side) { content_side.val = side })
      panel.reacts(fn() { panel.went_told() }, fn(side) { placed_side.val = side })
    })
  })
  t.frame(300.0, 300.0, now=0.0) |> ignore
  assert_eq((content_side.val, placed_side.val), (Top, Some(Top)))
  t.event(10.0, fn() { on.set(false) })
  t.event(20.0, fn() { y.set(20.0) })
  t.frame(300.0, 300.0, now=20.0) |> ignore
  assert_eq((content_side.val, placed_side.val), (Top, Some(Top)))
  t.dispose()
}
