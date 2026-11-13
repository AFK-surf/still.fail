// A node of the window's tree drawn as glass (View::glass): its instance made once with its block, its capture told as
// the frame is composed wherever it is then (what is drawn under it, before it); its corner linked to the window's
// worked out again as that changes (corner_of).

///|
let tree_frost : @paint.Glass = Glass::frosted(blur=12.0, tint=0xFFFFFF40L, solid=0xEEEEEEFFL)

///|
/// Two glass nodes side by side, a node's solid ground between them drawn while `between` holds: the captures each
/// glass takes as drawn (in order), and whether the glass nodes' instances were made again.
test "a node's glass: one capture with the glass just before it, its own where something is drawn between; told as composed, its instances kept" {
  let between = @signals.signal(false, same=fn(a, b) { a == b })
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    root.box(fn(b) { b.over(Is(true)).ground(Is(0x3366CCFFL)) |> ignore }) |> ignore
    root.box(fn(n) {
      n.over(Is(true)).offset(Is((10.0, 10.0))).width(Is(Some(60.0))).height(Is(Some(40.0))).radius(Is(20.0)).glass(Is(Some(tree_frost)))
      |> ignore
    })
    |> ignore
    root.show(fn() { between.get() }, fn(b) {
      b.over(Is(true)).offset(Is((100.0, 100.0))).width(Is(Some(20.0))).height(Is(Some(20.0))).ground(Is(0xCC3333FFL))
      |> ignore
    })
    root.box(fn(n) {
      n.over(Is(true)).offset(Is((90.0, 10.0))).width(Is(Some(60.0))).height(Is(Some(40.0))).radius(Is(20.0)).glass(Is(Some(tree_frost)))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let runs = fn() { t.drawn_glass().map(fn(g) { (g.0, g.4, g.5) }) }
  assert_eq(runs(), [(10.0, 5, 1), (90.0, 5, 1)])
  // (made with its radius)
  assert_eq(t.drawn_glass_corners().map(fn(g) { g.4 }), [20.0, 20.0])
  let made = view_painted().made
  between.set(true)
  t.frame_at(t.time() + frame_period_default)
  assert_eq(runs(), [(10.0, 5, 1), (90.0, 5, 2)])
  between.set(false)
  t.frame_at(t.time() + frame_period_default)
  assert_eq(runs(), [(10.0, 5, 1), (90.0, 5, 1)])
  // (the red node's made as it came; the glass nodes' never again)
  assert_eq(view_painted().made, made + 1)
}

///|
test "a node's glass where glass is drawn solid: its solid ground in its corner, no capture" {
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  set_glass_solid(Some(true))
  set_view_app(fn(root) {
    root.box(fn(n) {
      n.over(Is(true)).offset(Is((10.0, 10.0))).width(Is(Some(60.0))).height(Is(Some(40.0))).radius(Is(20.0)).glass(Is(Some(tree_frost)))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let solid = t.drawn_rects().filter(fn(r) { r.4 == 0xEEEEEEFFL })
  set_glass_solid(None)
  assert_eq(t.drawn_glass(), [])
  assert_eq(solid.map(fn(r) { (r.0, r.1, r.2, r.3) }), [(10.0, 10.0, 60.0, 40.0)])
}

///|
test "a node's corner linked to the window's: as the window draws its corner, again as it changes" {
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0, window_corner=16.0)
  set_view_app(fn(root) {
    root.box(fn(n) {
      n
      .over(Is(true))
      .offset(Is((6.0, 6.0)))
      .width(Is(Some(60.0)))
      .height(Is(Some(40.0)))
      .radius(corner_of(Follow(Window, 6.0, 9.0)))
      .ground(Is(0x3366CCFFL))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  // (the radius of each rectangle drawn at its place)
  let corner = fn() {
    let c = g()
    let out = []
    for k in 0..<c.ninst {
      let b = k * inst_size
      if c.inst[b + 5] == 0.0 && c.inst[b] == 6.0 && c.inst[b + 1] == 6.0 {
        out.push(c.inst[b + 4])
      }
    }
    out
  }
  assert_eq(corner(), [concentric(16.0, 6.0)])
  // (filling the screen: the window square, nothing to follow; as it stands alone)
  t.ctx().set_full_screen(true)
  t.frame_at(t.time() + frame_period_default)
  assert_eq(corner(), [9.0])
  t.ctx().set_full_screen(false)
  t.frame_at(t.time() + frame_period_default)
  assert_eq(corner(), [concentric(16.0, 6.0)])
}

///|
/// A window `w` wide whose theme is one of two by its width (narrow below 400: corners any way round; wide: still.fail's
/// ranges), and a node of the tree's corner following the window's 14 in (concentric there 4.8, squarer than the
/// ranges let it be: alone, 9, where they hold).
fn themed_corner_tester(w : Double) -> Tester {
  let wide = { ..Theme::light(), corner_fit: Some({ least: 6.0, most: 34.0, near: 4.0, far: 16.0 }) }
  let narrow = { ..Theme::light(), corner_fit: None }
  let t = Tester::new(fn(c) { c.set_theme(wide, narrow~, narrow_below=themed_below) }, w~, h=200.0, window_corner=16.0)
  // (as the app sets it before its first frame)
  t.ctx().set_theme(wide, narrow~, narrow_below=themed_below)
  set_view_app(fn(root) {
    root.box(fn(n) {
      n
      .over(Is(true))
      .offset(Is((14.0, 14.0)))
      .width(Is(Some(60.0)))
      .height(Is(Some(40.0)))
      .radius(corner_of(Follow(Window, 14.0, 9.0)))
      .ground(Is(0x3366CCFFL))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
let themed_below : Double = 400.0

///|
/// The radius of the rectangle drawn at (14, 14).
fn themed_corner() -> Array[Double] {
  let c = g()
  let out = []
  for k in 0..<c.ninst {
    let b = k * inst_size
    if c.inst[b + 5] == 0.0 && c.inst[b] == 14.0 && c.inst[b + 1] == 14.0 {
      out.push(c.inst[b + 4])
    }
  }
  out
}

///|
test "a node's linked corner across the width a theme is picked by: the first frame at the new width as one made there, both ways" {
  let fresh = fn(w : Double) {
    themed_corner_tester(w) |> ignore
    themed_corner()
  }
  let narrow = fresh(300.0)
  let wide = fresh(500.0)
  assert_eq((narrow, wide), ([concentric(16.0, 14.0)], [9.0]))
  let t = themed_corner_tester(300.0)
  t.resize_next(500.0, 200.0)
  t.frame_at(t.time() + frame_period_default)
  assert_eq(themed_corner(), wide)
  t.resize_next(300.0, 200.0)
  t.frame_at(t.time() + frame_period_default)
  assert_eq(themed_corner(), narrow)
}
