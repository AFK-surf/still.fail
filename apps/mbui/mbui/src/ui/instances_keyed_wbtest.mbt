// What drawn_instances_keyed says a shape's band is: its pieces by what they are (in 64ths), not where they stand among
// the frame's. The same shape reads the same though another drew before it; a shape changed in itself, in the same
// box, does not (pieces read in 64ths and hashed: a change smaller than that is none).

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
  // (its right side leaning in 0.9 at its foot, in the same box (49.1 drawn in the pixel 50 is): the same corners, the
  // same bands over the same pixels with as many pieces each; what the pieces are differs, so the keyed bands do)
  let leaning = sq([10.0, 10.0, 50.0, 10.0, 49.1, 50.0, 10.0, 50.0])
  let (leant, _) = keyed_bands([], leaning)
  let but_pieces = fn(a : Array[Double]) { a.mapi(fn(j, x) { if j == 12 { 0.0 } else { x } }) }
  assert_eq(leant.map(but_pieces), alone.map(but_pieces))
  assert_true(leant != alone)
}
