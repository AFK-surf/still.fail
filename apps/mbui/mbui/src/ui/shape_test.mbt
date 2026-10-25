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

///|
test "a dashed border (CSS's dashed): dashes three of its widths and gaps two round its box, inside it, no line of one piece" {
  let ink = 0xC1C4C9FFL
  for holds in [false, true] {
    let t = @ui.Tester::new(
      fn(c) {
        c.box(pl=20.0, pt=30.0, align=AStart, fn() {
          c.box(style=@ui.css("w=S24 h=S10 border=B1 dashed"), border_color=ink, fn() {
            // (with something in it its border is drawn over what it holds)
            if holds {
              c.box(w=Px(10.0), h=Px(10.0), fn() {  }) |> ignore
            }
          })
          |> ignore
        })
        |> ignore
      },
      w=300.0,
      h=300.0,
    )
    t.draw()
    // 96 by 40, its line's middle half a point in: 2 × (95 + 39) round in 54 steps, a dash 3/5 of each
    let step = 2.0 * (95.0 + 39.0) / 54.0
    let dash = step * 3.0 / 5.0
    assert_true(t.shape_cover(20.5 + dash / 2.0, 30.5) > 0.5, msg="holds \{holds}: no dash on its top edge")
    assert_eq(t.shape_cover(20.5 + dash + (step - dash) / 2.0, 30.5), 0.0, msg="holds \{holds}: a gap filled")
    // its line inside the box, nothing of it out
    assert_eq(t.shape_cover(20.5 + dash / 2.0, 29.0), 0.0)
    // drawn in its colour as the dashes only: no rect with a border
    assert_true(t.drawn_shapes().iter().all(fn(b) { b.5 == ink }))
    assert_true(t.boxes().iter().any(fn(l) { l.dashed && l.border_w == 1.0 }))
  }
}

///|
test "a dashed frame's dashes lie on it, as many as its length takes at five widths each" {
  let (w, h, r, line) = (60.0, 30.0, 8.0, 1.5)
  let dashes = @ui.dashed_outlines(w, h, r, line)
  let whole = 2.0 * (w - 2.0 * r + h - 2.0 * r) + 2.0 * @math.PI * r
  assert_eq(dashes.length(), (whole / (5.0 * line)).round().to_int())
  for d in dashes {
    let pts = d.0
    for i in 0..<(pts.length() / 2) {
      let (x, y) = (pts[2 * i], pts[2 * i + 1])
      let near = fn(a : Double, b : Double) { (a - b).abs() < 1.0e-9 }
      // in a corner r from its middle, else on a side
      let in_corner = (x < r || x > w - r) && (y < r || y > h - r)
      let on = if in_corner {
        let cx = if x < r { r } else { w - r }
        let cy = if y < r { r } else { h - r }
        near(((x - cx) * (x - cx) + (y - cy) * (y - cy)).sqrt(), r)
      } else {
        near(x, 0.0) || near(x, w) || near(y, 0.0) || near(y, h)
      }
      assert_true(on, msg="(\{x}, \{y}) off the frame")
    }
  }
}
