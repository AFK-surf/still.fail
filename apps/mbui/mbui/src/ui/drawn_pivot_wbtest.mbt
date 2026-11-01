// A node grown or shrunk about the middle of what it draws (View::scale's Drawn), that middle worked out again as what
// it is made of changes and only then: the window made narrower (what it holds laid out otherwise), a node made anew
// where one let go was, grown about another point and back.

///|
test "a node drawn half as big about the middle of what it draws, holding one of colour as wide as it is: the window made narrower, about the middle of it at its new width from the first frame" {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  let node : Ref[@view.View?] = Ref(None)
  set_view_app(fn(root) {
    node.val = Some(
      root.box(fn(p) {
        p.height(Is(Some(20.0))).scale(Is(0.5), about=Drawn) |> ignore
        p.box(fn(a) { a.grow(Is(1.0)).ground(Is(0x3366CCFFL)) |> ignore }) |> ignore
      }),
    )
  })
  t.draw()
  let wide = node.val.unwrap().rect().0
  t.resize(200.0, 300.0)
  let narrow = node.val.unwrap().rect().0
  assert_eq((wide, narrow), (100.0, 50.0))
}

///|
test "a node made where one let go was, its ground and width said before it is grown about the middle of what it draws: about its own middle, nothing of the one before" {
  let first = @signals.signal(true, same=fn(a, b) { a == b })
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  let before : Ref[@view.View?] = Ref(None)
  let after : Ref[@view.View?] = Ref(None)
  set_view_app(fn(root) {
    // (one grown about the middle of what it draws, 200 wide of colour: that middle worked out, 100 in)
    root.show(fn() { first.get() }, fn(p) {
      before.val = Some(p)
      p.width(Is(Some(200.0))).height(Is(Some(20.0))).ground(Is(0x3366CCFFL)).scale(Is(0.5), about=Drawn) |> ignore
    })
    // (made as it goes, where it was: 40 wide of colour, then grown about the middle of what it draws)
    root.show(fn() { !first.get() }, fn(q) {
      after.val = Some(q)
      q.width(Is(Some(40.0))).height(Is(Some(20.0))).ground(Is(0xCC3333FFL)).scale(Is(0.5), about=Drawn) |> ignore
    })
  })
  t.draw()
  let was = before.val.unwrap().id()
  let first_left = before.val.unwrap().rect().0
  first.set(false)
  t.frame()
  let now = after.val.unwrap().id()
  // (40 wide at the left: half as big about 20 in, its left drawn 10 in)
  assert_eq((first_left, now.at == was.at, now.gen != was.gen, after.val.unwrap().rect().0), (50.0, true, true, 10.0))
}

///|
test "a node grown about the middle of what it draws, then about its top left while what it holds changes, then about the middle of what it draws again: the middle of what it draws then" {
  let wide = @signals.signal(60.0, same=fn(a, b) { a == b })
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  let node : Ref[@view.View?] = Ref(None)
  set_view_app(fn(root) {
    node.val = Some(
      root.box(fn(p) {
        p.row(Is(true)).width(Is(Some(200.0))).height(Is(Some(20.0))) |> ignore
        p.box(fn(a) { a.width(By(fn() { Some(wide.get()) })).ground(Is(0x3366CCFFL)) |> ignore }) |> ignore
      }),
    )
  })
  node.val.unwrap().scale(Is(0.5), about=Drawn) |> ignore
  t.draw()
  let at_first = node.val.unwrap().rect().0
  node.val.unwrap().scale(Is(0.5), about=At(0.0, 0.0)) |> ignore
  t.frame()
  let top_left = node.val.unwrap().rect().0
  wide.set(120.0)
  t.frame()
  node.val.unwrap().scale(Is(0.5), about=Drawn) |> ignore
  t.frame()
  assert_eq((at_first, top_left, node.val.unwrap().rect().0), (15.0, 0.0, 30.0))
}

///|
test "a node grown about the middle of what it draws: a block in it faded and then drawn off at one moment, about the middle of where it is drawn off from the first frame; faded alone, nothing worked out again" {
  let fade = @signals.signal(1.0, same=fn(a, b) { a == b })
  let off = @signals.signal(0.0, same=fn(a, b) { a == b })
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  let node : Ref[@view.View?] = Ref(None)
  set_view_app(fn(root) {
    node.val = Some(
      root.box(fn(p) {
        p.row(Is(true)).width(Is(Some(200.0))).height(Is(Some(20.0))).scale(Is(0.5), about=Drawn) |> ignore
        p.box(fn(a) {
          a.width(Is(Some(60.0))).ground(Is(0x3366CCFFL)).alpha(By(fn() { fade.get() })).offset(By(fn() { (off.get(), 0.0) })) |> ignore
        })
        |> ignore
      }),
    )
  })
  t.draw()
  let n = node.val.unwrap()
  let tree = view_tree().unwrap()
  let first = n.rect().0
  // (faded alone: the box round what it draws kept)
  let boxes = tree.work().drawn_boxes
  fade.set(0.5)
  t.frame()
  let kept = tree.work().drawn_boxes == boxes && n.rect().0 == first
  // (faded and drawn off 40 as one change, nothing drawn between)
  tree.event(t.time(), fn() {
    fade.set(0.25)
    off.set(40.0)
  })
  t.frame()
  assert_eq((first, kept, n.rect().0), (15.0, true, 35.0))
}
