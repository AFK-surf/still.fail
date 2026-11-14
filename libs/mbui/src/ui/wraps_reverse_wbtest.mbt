// A row of the window's tree that wraps the other way (View::wraps `reverse`) laid out as an old view's box that says
// `flow_reverse` is: the same boxes, the same widths, each drawn where the old one draws it.

///|
/// Boxes as wide and tall as `sizes` say, each its own ground, in a row `width` wide, 10 apart along it, its lines 4
/// apart, each line over the one before it: drawn by an old view's box (`old`) or a node of the window's tree; what is
/// drawn.
fn reverse_drawn(sizes : Array[(Double, Double)], width : Double, old : Bool) -> Array[(Double, Double, Double, Double, Int64)] {
  let ground = fn(k : Int) { 0x10203000L + (k.to_int64() << 8) + 0xFFL }
  let t = if old {
    Tester::new(
      fn(c) {
        c.box(dir=Row, w=Px(width), gap=10.0, flow_reverse=true, line_gap=4.0, fn() {
          for k, s in sizes {
            c.box(w=Px(s.0), h=Px(s.1), bg=ground(k), fn() {  }) |> ignore
          }
        })
        |> ignore
      },
      w=300.0,
      h=200.0,
    )
  } else {
    Tester::new(
      fn(_c) {  },
      tree=fn(root) {
        root.lines_up(Is(Some(Start))) |> ignore
        root.box(fn(r) {
          r.width(Is(Some(width))).row(Is(true)).gap(Is(10.0)).wraps(Is(Some(4.0)), reverse=true) |> ignore
          for k, s in sizes {
            r.box(fn(b) { b.width(Is(Some(s.0))).height(Is(Some(s.1))).ground(Is(ground(k))) |> ignore }) |> ignore
          }
        })
        |> ignore
      },
      w=300.0,
      h=200.0,
    )
  }
  t.run_for(move_most_ms)
  t.drawn_rects()
}

///|
test "wraps the other way, made once: each box drawn where an old view's flow_reverse draws it, one line, two, three, lines of other heights" {
  let even = [(40.0, 20.0), (40.0, 20.0), (40.0, 20.0)]
  let uneven = [(60.0, 20.0), (40.0, 30.0), (30.0, 20.0), (70.0, 24.0)]
  for c in [(even, 200.0), (even, 100.0), (even, 45.0), (uneven, 100.0), (uneven, 160.0), (uneven, 300.0)] {
    let was = reverse_drawn(c.0, c.1, true)
    let now = reverse_drawn(c.0, c.1, false)
    assert_eq(now.length(), c.0.length(), msg="\{c.1}")
    assert_eq(now, was, msg="\{c.1}")
  }
}
