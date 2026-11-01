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

///|
test "a node grown about the middle of what it draws, its ground of no opacity, then of some, then of none again: about the middle of what it holds of colour, then of all of it, then of what it holds again (an old view's held_look, its box's grounded)" {
  let ground = @signals.signal(0x3366CC00L, same=fn(a, b) { a == b })
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  let node : Ref[@view.View?] = Ref(None)
  set_view_app(fn(root) {
    node.val = Some(
      root.box(fn(p) {
        p
        .row(Is(true))
        .width(Is(Some(200.0)))
        .height(Is(Some(20.0)))
        .ground(By(fn() { ground.get() }))
        .scale(Is(0.5), about=Drawn)
        |> ignore
        p.box(fn(a) { a.width(Is(Some(40.0))).ground(Is(0xCC3333FFL)) |> ignore }) |> ignore
      }),
    )
  })
  t.draw()
  let clear = node.val.unwrap().rect().0
  ground.set(0x3366CCFFL)
  t.frame()
  let whole = node.val.unwrap().rect().0
  ground.set(0x3366CC00L)
  t.frame()
  // (half as big about 20 in, its left drawn 10 in; about 100 in, 50 in)
  assert_eq((clear, whole, node.val.unwrap().rect().0), (10.0, 50.0, 10.0))
}

///|
/// The red box 40 wide at the left of a box 200 by 20 of `ground`, that grown half as big about the middle of what it
/// draws: an old view's (Ctx::held_look's, its box's grounded) or the tree's (View::scale's Drawn). Where the red box
/// is drawn and how big.
fn clear_ground_drawn(node : Bool, ground : Int64) -> Array[Double] raise {
  let red = 0xCC3333FFL
  let t = Tester::new(
    fn(c) {
      if !node {
        let b = c.box(w=Px(200.0), h=Px(20.0), dir=Row, bg=ground, align=AStart, fn() {
          c.box(w=Px(40.0), h=Px(20.0), bg=red, fn() {  }) |> ignore
        })
        // (held_look's scale about its point; drawn whole, as the tree's is: its row_held_look's alpha at half open is
        // none)
        c.look_by(b, fn() { { ..c.held_look(b, 0.5), alpha: 1.0 } })
      }
    },
    w=400.0,
    h=300.0,
  )
  if node {
    set_view_app(fn(root) {
      root.box(fn(p) {
        p.row(Is(true)).width(Is(Some(200.0))).height(Is(Some(20.0))).ground(Is(ground)).scale(Is(0.5), about=Drawn) |> ignore
        p.box(fn(a) { a.width(Is(Some(40.0))).ground(Is(red)) |> ignore }) |> ignore
      })
      |> ignore
    })
  }
  t.draw()
  rect_of_color(red)[0:4].to_array()
}

///|
test "a box grown about the middle of what it draws, its ground of no opacity or of some: its red box drawn where an old view's held_look draws it, as big" {
  let seen = [0x3366CC00L, 0x3366CCFFL].map(fn(g) {
    (clear_ground_drawn(false, g) catch { _ => [] }, clear_ground_drawn(true, g) catch { _ => [] })
  })
  assert_eq(seen.map(fn(p) { p.0 == p.1 && p.0.length() == 4 }), [true, true], msg="\{seen}")
}
