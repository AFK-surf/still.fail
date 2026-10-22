///|
/// A box at (`x`, `y`) of the window, 100 by 100, drawing `shapes`.
fn shapes_at(x : Double, y : Double, shapes : Array[@ui.Shape]) -> @ui.Tester {
  let t = @ui.Tester::new(
    fn(c) {
      c.box(pl=x, pt=y, align=AStart, fn() { c.shapes(shapes, w=Px(100.0), h=Px(100.0)) |> ignore }) |> ignore
    },
    w=300.0,
    h=300.0,
  )
  t.draw()
  t
}

///|
/// A square's outline, its sides `s` long from (`x`, `y`), clockwise or (`back`) the other way.
fn square(x : Double, y : Double, s : Double, back? : Bool = false) -> (Array[Double], Bool) {
  if back {
    ([x, y, x, y + s, x + s, y + s, x + s, y], true)
  } else {
    ([x, y, x + s, y, x + s, y + s, x, y + s], true)
  }
}

///|
test "a filled shape covers what is inside its outline, half a pixel on its edge, nothing outside" {
  let ink = 0x24272BFFL
  let t = shapes_at(20.0, 30.0, [@ui.shape_of([square(10.0, 10.0, 40.0)], fill=ink)])
  assert_eq(t.shape_cover(50.0, 60.0), 1.0)
  assert_eq(t.shape_cover(25.0, 60.0), 0.0)
  assert_eq(t.shape_cover(75.0, 60.0), 0.0)
  // on its left and right edges, half of each row of the pixel
  assert_eq(t.shape_cover(30.0, 60.0), 0.5)
  assert_eq(t.shape_cover(70.0, 60.0), 0.5)
  // drawn in its colour, in bands down it, none higher than a band
  let bands = t.drawn_shapes()
  assert_true(bands.length() > 1)
  assert_true(bands.iter().all(fn(b) { b.5 == ink && b.4 == 0.0 && b.3 <= 8.0 }))
}

///|
test "a hole: the nonzero rule fills an outline going the same way, not one going back; even-odd neither" {
  let ink = 0x24272BFFL
  let same = shapes_at(0.0, 0.0, [@ui.shape_of([square(10.0, 10.0, 60.0), square(30.0, 30.0, 20.0)], fill=ink)])
  assert_eq(same.shape_cover(40.0, 40.0), 1.0)
  let back = shapes_at(0.0, 0.0, [
    @ui.shape_of([square(10.0, 10.0, 60.0), square(30.0, 30.0, 20.0, back=true)], fill=ink),
  ])
  assert_eq(back.shape_cover(40.0, 40.0), 0.0)
  assert_eq(back.shape_cover(20.0, 40.0), 1.0)
  let eo = shapes_at(0.0, 0.0, [
    @ui.shape_of([square(10.0, 10.0, 60.0), square(30.0, 30.0, 20.0)], fill=ink, even_odd=true),
  ])
  assert_eq(eo.shape_cover(40.0, 40.0), 0.0)
  assert_eq(eo.shape_cover(20.0, 40.0), 1.0)
}

///|
test "a stroke covers as far as half its width from its line, its ends round" {
  let ink = 0x24272BFFL
  let t = shapes_at(0.0, 0.0, [@ui.shape_of([([10.0, 50.0, 90.0, 50.0], false)], stroke=ink, width=10.0)])
  assert_eq(t.shape_cover(50.0, 50.0), 1.0)
  assert_eq(t.shape_cover(50.0, 54.0), 1.0)
  assert_eq(t.shape_cover(50.0, 55.0), 0.5)
  assert_eq(t.shape_cover(50.0, 58.0), 0.0)
  // round past its end, not square
  assert_eq(t.shape_cover(94.0, 50.0), 1.0)
  assert_eq(t.shape_cover(94.0, 54.0), 0.0)
  // its band as wide as its stroke and a pixel more each way
  assert_true(t.drawn_shapes().iter().all(fn(b) { b.4 == 5.0 }))
}

///|
test "a shape moves with what holds it: drawn again in another place, it covers there" {
  let ink = 0x24272BFFL
  let t = shapes_at(100.0, 100.0, [@ui.shape_of([square(0.0, 0.0, 50.0)], fill=ink)])
  assert_eq(t.shape_cover(125.0, 125.0), 1.0)
  assert_eq(t.shape_cover(25.0, 25.0), 0.0)
}
