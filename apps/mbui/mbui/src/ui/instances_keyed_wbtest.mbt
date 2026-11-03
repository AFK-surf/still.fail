// What drawn_instances_keyed says a shape's band is: its pieces by what they are (in 64ths), not where they stand among
// the frame's. The same shape reads the same though another drew before it; a shape changed in itself, in the same
// box, does not.

///|
/// A row: a box 100 by 100 drawing `before` (nothing, or another shape), then one drawing `shape` (where it is the same
/// whatever the first draws); each frame's keyed and raw instances of the second's bands (kind 11, from 100 across).
fn keyed_bands(before : Array[Shape], shape : Shape) -> (Array[Array[Double]], Array[Array[Double]]) {
  let t = Tester::new(
    fn(c) {
      c.row(align=AStart, fn() {
        c.shapes(before, w=Px(100.0), h=Px(100.0)) |> ignore
        c.shapes([shape], w=Px(100.0), h=Px(100.0)) |> ignore
      })
      |> ignore
    },
    w=300.0,
    h=200.0,
  )
  t.draw()
  let theirs = fn(a : Array[Double]) { a[5] == 11.0 && a[0] >= 100.0 }
  (t.drawn_instances_keyed().filter(theirs), t.drawn_instances().filter(theirs))
}

///|
test "a shape's bands, keyed: the same though another shape drew its pieces first, not where its own pieces changed" {
  let ink = 0x24272BFFL
  let sq = fn(pts : Array[Double]) { shape_of([(pts, true)], fill=ink) }
  let square = sq([10.0, 10.0, 50.0, 10.0, 50.0, 50.0, 10.0, 50.0])
  let other = sq([20.0, 20.0, 80.0, 20.0, 80.0, 80.0, 20.0, 80.0])
  let (alone, alone_raw) = keyed_bands([], square)
  let (after, after_raw) = keyed_bands([other], square)
  assert_true(alone.length() > 1)
  // (its pieces stand elsewhere among the frame's, the other's before them: the raw instances differ, the keyed not)
  assert_true(alone_raw != after_raw)
  assert_eq(alone, after)
  // (its right side dented in, in the same box, as wide and as high: a band's pieces differ, and only they)
  let dented = sq([10.0, 10.0, 50.0, 10.0, 46.0, 30.0, 50.0, 50.0, 10.0, 50.0])
  let (bent, _) = keyed_bands([], dented)
  assert_true(bent != alone)
  assert_eq(bent.length(), alone.length())
  let only_pieces = fn(a : Array[Double]) { a.mapi(fn(j, x) { if j == 12 { 0.0 } else { x } }) }
  assert_eq(bent.map(only_pieces), alone.map(only_pieces))
}
