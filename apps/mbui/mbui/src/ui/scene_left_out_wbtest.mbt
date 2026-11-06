// A layer left out whole where all it reached as last drawn lies outside what it is drawn in and the window
// (Ctx::scene_layer_left_out), never where something in it changed or moved: a layer below the window, a layer in it
// moved up into the window, drawn there; moved back out, gone; each frame as drawing all of it anew comes to (the
// Tester's check of every frame), and what is under the pointer as drawn.

///|
test "a layer below the window, one in it moved into the window and back: drawn where it comes to, as drawn anew, pressed there" {
  let up = @signals.signal(0.0)
  let pressed = Ref(0)
  let t = Tester::new(fn(_) {  }, w=200.0, h=200.0)
  set_view_app(fn(root) {
    root.width(Is(Some(200.0))).height(Is(Some(200.0))) |> ignore
    // (a layer of its own wholly below the window, clipped to nothing of it but itself)
    root.box(fn(outer) {
      outer.offset(Is((0.0, 260.0))).width(Is(Some(200.0))).height(Is(Some(100.0))).ground(Is(0xDDDDDDFFL)) |> ignore
      // (a layer in it, moved up out of it by `up`)
      outer.box(fn(inner) {
        inner.offset(By(fn() { (20.0, -up.get()) })).width(Is(Some(60.0))).height(Is(Some(40.0)))
        .ground(Is(0x3366CCFFL)).on_press(fn() { pressed.val = pressed.val + 1 }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let blue = fn() {
    let c = g()
    let mut n = 0
    for k in 0..<c.ninst {
      let b = k * inst_size
      if c.inst[b + 5] == 0.0 && c.inst[b + 2] == 60.0 && c.inst[b + 1] < 200.0 {
        n = n + 1
      }
    }
    n
  }
  t.clock_frame()
  t.clock_frame()
  assert_eq(blue(), 0, msg="drawn below the window")
  // (moved up into the window: drawn there, pressed there)
  up.set(150.0)
  t.clock_frame()
  assert_eq(blue(), 1, msg="not drawn once moved into the window")
  t.tap(50.0, 130.0)
  assert_eq(pressed.val, 1)
  // (and back out)
  up.set(0.0)
  t.clock_frame()
  t.clock_frame()
  assert_eq(blue(), 0, msg="drawn once moved out again")
}

///|
test "a layer whose own drawing is its edge alone, drawn as its node closes, reaching into the window: never left out by what it holds" {
  let down = @signals.signal(150.0)
  let t = Tester::new(fn(_) {  }, w=200.0, h=200.0)
  set_view_app(fn(root) {
    root.width(Is(Some(200.0))).height(Is(Some(200.0))) |> ignore
    // (a layer of its own with an edge and no ground, what it holds at its foot below the window)
    root.box(fn(card) {
      card.offset(By(fn() { (10.0, down.get()) })).width(Is(Some(180.0))).height(Is(Some(150.0)))
      .edge(Is((2.0, 0x000000FFL))) |> ignore
      card.box(fn(foot) {
        foot.offset(Is((0.0, 110.0))).width(Is(Some(40.0))).height(Is(Some(30.0))).ground(Is(0x3366CCFFL)) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  let edges = fn() {
    let c = g()
    let mut n = 0
    for k in 0..<c.ninst {
      let b = k * inst_size
      if c.inst[b + 5] == 0.0 && c.inst[b + 6] == 2.0 {
        n = n + 1
      }
    }
    n
  }
  t.draw()
  t.clock_frame()
  t.clock_frame()
  // (its edge's top in the window, all it holds below it: the edge drawn)
  assert_eq(edges(), 1, msg="the edge in the window left out")
  // (moved wholly out, then back)
  down.set(260.0)
  t.clock_frame()
  t.clock_frame()
  assert_eq(edges(), 0, msg="drawn wholly out of the window")
  down.set(150.0)
  t.clock_frame()
  t.clock_frame()
  assert_eq(edges(), 1, msg="not drawn back in the window")
}
