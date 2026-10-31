// A picture a node of the window's tree draws (View::picture): drawn as an old view draws the same picture cut for the
// pixels it is built at (Ctx::shapes of vector_shapes at drawn_scale), at the window's pixels and at the zoom it is
// drawn at, from the first frame after either changes, and as its width changes; cut once while they do not, a tint
// changed drawing it again in it, each path's own opacity kept, not cut again.

///|
/// A round picture of curves, 24 across: a solid ring and, inside it, a disc half opaque.
let round_picture : @pixels.Vector = {
  w: 24.0,
  h: 24.0,
  layers: [
    {
      d: "M12,1 C18.1,1 23,5.9 23,12 C23,18.1 18.1,23 12,23 C5.9,23 1,18.1 1,12 C1,5.9 5.9,1 12,1 Z",
      fill: 0L,
      stroke: 0x1B1B1FFFL,
      width: 2.0,
      even_odd: false,
      sx: 1.0,
      sy: 1.0,
      tx: 0.0,
      ty: 0.0,
    },
    {
      d: "M12,6 C15.3,6 18,8.7 18,12 C18,15.3 15.3,18 12,18 C8.7,18 6,15.3 6,12 C6,8.7 8.7,6 12,6 Z",
      fill: 0xE0705080L,
      stroke: 0L,
      width: 0.0,
      even_odd: false,
      sx: 1.0,
      sy: 1.0,
      tx: 0.0,
      ty: 0.0,
    },
  ],
}

///|
/// A while the window is drawn with nothing changed, its frames after one another.
let unchanged_ms : Double = 500.0

///|
/// The shapes drawn in the last frame.
fn shapes_drawn(t : Tester) -> Array[(Double, Double, Double, Double, Double, Int64)] {
  t.drawn_shapes()
}

///|
/// The picture `w` wide at the window's top left as an old view draws it, in a window at `scale` pixels a point drawn at
/// `zoom`: the shapes drawn.
fn old_picture(w : Double, scale : Double, zoom? : Double = 1.0) -> Array[(Double, Double, Double, Double, Double, Int64)] {
  let t = Tester::new(
    fn(c) { c.shapes(vector_shapes(round_picture, w, c.drawn_scale()), w=Px(w), h=Px(w)) |> ignore },
    w=400.0,
    h=300.0,
    scale~,
  )
  if zoom != 1.0 {
    set_window_zoom(zoom)
    t.frame()
  }
  t.draw()
  let out = shapes_drawn(t)
  set_window_zoom(1.0)
  t.frame()
  out
}

///|
/// The picture in a node of the tree at the window's top left, as wide and as tall as `width` says, in `tint` (0: its
/// own colours), in a window at `scale` pixels a point.
fn tree_picture(
  width : @signals.Signal[Double],
  tint : @signals.Signal[Int64],
  scale : Double,
  picture? : @signals.Signal[@pixels.Vector?] = @signals.signal(Some(round_picture)),
  own? : Array[Shape] = [],
) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, scale~)
  set_view_app(fn(root) {
    root.box(fn(v) {
      v
      .width(By(fn() { Some(width.get()) }))
      .height(By(fn() { Some(width.get()) }))
      .shapes(Is(own))
      .picture(By(fn() { picture.get() }))
      .tint(By(fn() { tint.get() }))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
test "a node's picture drawn as an old view draws it, cut for the window's pixels: at 2 and at 3 a point, each cut otherwise" {
  let w = @signals.signal(56.0, same=fn(a, b) { a == b })
  let tint = @signals.signal(0L, same=fn(a, b) { a == b })
  let at2 = shapes_drawn(tree_picture(w, tint, 2.0))
  let at3 = shapes_drawn(tree_picture(w, tint, 3.0))
  let (old2, old3) = (old_picture(56.0, 2.0), old_picture(56.0, 3.0))
  // (the curves cut otherwise at the two: more points for more pixels)
  let points = fn(scale) { vector_shapes(round_picture, 56.0, scale).fold(init=0, fn(n, s) { n + s.outlines.fold(init=0, fn(m, o) { m + o.0.length() }) }) }
  assert_eq(
    (at2 == old2, at3 == old3, old2.length() > 0, points(2.0) != points(3.0)),
    (true, true, true, true),
    msg="tree \{at2.length()}/\{at3.length()}, old \{old2.length()}/\{old3.length()}, points \{points(2.0)} \{points(3.0)}",
  )
}

///|
test "a node's picture, the window come to 3 pixels a point: from the first frame after, cut for them; at rest, cut no more" {
  let w = @signals.signal(56.0, same=fn(a, b) { a == b })
  let tint = @signals.signal(0L, same=fn(a, b) { a == b })
  let t = tree_picture(w, tint, 2.0)
  t.fake.scale = 3.0
  t.fake.wants = true
  t.frame()
  let first = shapes_drawn(t)
  let cut = view_pictures_cut.val
  t.advance(unchanged_ms)
  t.draw()
  t.frame()
  // (all of this Tester's read before the old view's is made: a Tester made lets go of the tree and its counts)
  let still = view_pictures_cut.val - cut
  assert_eq((first == old_picture(56.0, 3.0), still), (true, 0))
}

///|
test "a node's picture, the window drawn at half its points and back: from the first frame after each, drawn as an old view draws it so" {
  let w = @signals.signal(56.0, same=fn(a, b) { a == b })
  let tint = @signals.signal(0L, same=fn(a, b) { a == b })
  let half_old = old_picture(56.0, 2.0, zoom=0.5)
  let whole_old = old_picture(56.0, 2.0)
  let t = tree_picture(w, tint, 2.0)
  set_window_zoom(0.5)
  t.frame()
  let half = shapes_drawn(t)
  set_window_zoom(1.0)
  t.frame()
  let whole = shapes_drawn(t)
  assert_eq((half == half_old, whole == whole_old, half != whole), (true, true, true))
}

///|
test "a node's picture made wider: cut again for its width, drawn as an old view draws it as wide" {
  let w = @signals.signal(56.0, same=fn(a, b) { a == b })
  let tint = @signals.signal(0L, same=fn(a, b) { a == b })
  let t = tree_picture(w, tint, 2.0)
  w.set(80.0)
  t.frame()
  assert_eq(shapes_drawn(t) == old_picture(80.0, 2.0), true)
}

///|
test "a node's picture tinted: drawn again in the tint, each path's own opacity kept, its curves not cut again" {
  let w = @signals.signal(56.0, same=fn(a, b) { a == b })
  let tint = @signals.signal(0L, same=fn(a, b) { a == b })
  let t = tree_picture(w, tint, 2.0)
  let plain = shapes_drawn(t)
  let cut = view_pictures_cut.val
  tint.set(0x3366CCFFL)
  t.frame()
  let tinted = shapes_drawn(t)
  let colours = tinted.fold(init=[], fn(cs : Array[Int64], s) { if cs.contains(s.5) { cs } else { cs + [s.5] } })
  assert_eq(
    (
      view_pictures_cut.val - cut,
      tinted.map(fn(s) { (s.0, s.1, s.2, s.3, s.4) }) == plain.map(fn(s) { (s.0, s.1, s.2, s.3, s.4) }),
      colours.contains(0x3366CCFFL),
      colours.contains(0x3366CC80L),
    ),
    (0, true, true, true),
    msg="\{colours}",
  )
}

///|
/// A square of its own, 10 across, at (2, 2): a shape a node draws before its picture.
let own_square : Array[Shape] = [
  { outlines: [([2.0, 2.0, 12.0, 2.0, 12.0, 12.0, 2.0, 12.0], true)], fill: 0x20A040FFL, even_odd: false, stroke: 0L, width: 0.0 },
]

///|
test "a node's shapes and its picture, tinted: both drawn again in it (the shapes all of it, the picture's paths each their own opacity), nothing of either cut or made into bands again" {
  let w = @signals.signal(56.0, same=fn(a, b) { a == b })
  let tint = @signals.signal(0L, same=fn(a, b) { a == b })
  let t = tree_picture(w, tint, 2.0, own=own_square)
  let plain = shapes_drawn(t)
  let (cut, bands) = (view_pictures_cut.val, view_bands_made.val)
  tint.set(0x3366CCFFL)
  t.frame()
  let tinted = shapes_drawn(t)
  let colours = tinted.fold(init=[], fn(cs : Array[Int64], s) { if cs.contains(s.5) { cs } else { cs + [s.5] } })
  let (recut, rebanded) = (view_pictures_cut.val - cut, view_bands_made.val - bands)
  assert_eq(
    (
      recut,
      rebanded,
      tinted.map(fn(s) { (s.0, s.1, s.2, s.3, s.4) }) == plain.map(fn(s) { (s.0, s.1, s.2, s.3, s.4) }),
      plain.iter().any(fn(s) { s.5 == 0x20A040FFL }),
      colours,
    ),
    (0, 0, true, true, [0x3366CCFFL, 0x3366CC80L]),
  )
}

///|
/// A smaller round picture: one disc, 12 across in a viewport of 24.
let small_picture : @pixels.Vector = {
  w: 24.0,
  h: 24.0,
  layers: [
    {
      d: "M12,6 C15.3,6 18,8.7 18,12 C18,15.3 15.3,18 12,18 C8.7,18 6,15.3 6,12 C6,8.7 8.7,6 12,6 Z",
      fill: 0x1B1B1FFFL,
      stroke: 0L,
      width: 0.0,
      even_odd: false,
      sx: 1.0,
      sy: 1.0,
      tx: 0.0,
      ty: 0.0,
    },
  ],
}

///|
test "a node's picture taken away, then another given: nothing drawn and nothing of the first kept meanwhile (its cut nor its bands); the other drawn as an old view draws it" {
  let w = @signals.signal(56.0, same=fn(a, b) { a == b })
  let tint = @signals.signal(0L, same=fn(a, b) { a == b })
  let picture : @signals.Signal[@pixels.Vector?] = @signals.signal(Some(round_picture))
  let t = tree_picture(w, tint, 2.0, picture~)
  let first = shapes_drawn(t).length()
  picture.set(None)
  t.frame()
  let (gone, kept) = (shapes_drawn(t).length(), (view_pictures.length(), view_shape_bands.length()))
  picture.set(Some(small_picture))
  t.frame()
  let other = shapes_drawn(t)
  let old = Tester::new(
    fn(c) { c.shapes(vector_shapes(small_picture, 56.0, c.drawn_scale()), w=Px(56.0), h=Px(56.0)) |> ignore },
    w=400.0,
    h=300.0,
    scale=2.0,
  )
  old.draw()
  assert_eq((first > 0, gone, kept, other == shapes_drawn(old)), (true, 0, (0, 0), true))
}
