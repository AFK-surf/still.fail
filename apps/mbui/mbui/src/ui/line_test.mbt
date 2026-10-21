///|
/// A box at (`x`, `y`) of the window, 100 by 100, drawing `lines` (its look `look` when given).
fn lines_at(x : Double, y : Double, lines : Array[@ui.Line], look? : @ui.Look) -> @ui.Tester {
  let t = @ui.Tester::new(
    fn(c) {
      c.box(pl=x, pt=y, align=AStart, fn() {
        let i = c.lines(lines, w=Px(100.0), h=Px(100.0))
        match look {
          Some(l) => c.look(i, l)
          None => ()
        }
      })
      |> ignore
    },
    w=300.0,
    h=300.0,
  )
  t.draw()
  t
}

///|
test "a line is drawn in its box, a piece between each two of its points, as wide and in the colour it says" {
  let blue = 0x1559C4FFL
  let t = lines_at(20.0, 30.0, [@ui.line([(10.0, 10.0), (60.0, 10.0), (60.0, 40.0)], width=2.0, color=blue)])
  assert_eq(t.drawn_lines(), [
    (30.0, 40.0, 80.0, 40.0, 2.0, blue),
    (80.0, 40.0, 80.0, 70.0, 2.0, blue),
  ])
}

///|
test "a line drawn part of the way: as far along its whole length as it says, the piece it ends in cut there" {
  let ink = 0x24272BFFL
  // 50 across then 30 down: 80 long, 0.75 of it 60, 10 into the second piece
  let t = lines_at(0.0, 0.0, [@ui.line([(0.0, 0.0), (50.0, 0.0), (50.0, 30.0)], width=4.0, color=ink, upto=0.75)])
  assert_eq(t.drawn_lines(), [(0.0, 0.0, 50.0, 0.0, 4.0, ink), (50.0, 0.0, 50.0, 10.0, 4.0, ink)])
  // none of it: nothing; a point: a dot
  let none = lines_at(0.0, 0.0, [@ui.line([(0.0, 0.0), (50.0, 0.0)], width=4.0, color=ink, upto=0.0)])
  assert_eq(none.drawn_lines(), [])
  let dot = lines_at(0.0, 0.0, [@ui.line([(5.0, 6.0)], width=4.0, color=ink)])
  assert_eq(dot.drawn_lines(), [(5.0, 6.0, 5.0, 6.0, 4.0, ink)])
}

///|
test "an arc's points lie on its circle, its pieces close enough to it that the line is round" {
  let r = 6.0
  let pts = @ui.arc(7.0, 7.0, r, from=0.0, sweep=3.141592653589793 / 2.0)
  assert_true(pts.length() > 2)
  // from 3 o'clock round to 6 o'clock (the screen's y down)
  let (x0, y0) = pts[0]
  let (x1, y1) = pts[pts.length() - 1]
  assert_true((x0 - 13.0).abs() < 1.0e-9 && (y0 - 7.0).abs() < 1.0e-9)
  assert_true((x1 - 7.0).abs() < 1.0e-9 && (y1 - 13.0).abs() < 1.0e-9)
  for k in 1..<pts.length() {
    let (ax, ay) = pts[k - 1]
    let (bx, by) = pts[k]
    let mx = (ax + bx) / 2.0 - 7.0
    let my = (ay + by) / 2.0 - 7.0
    assert_true(r - (mx * mx + my * my).sqrt() <= 0.05)
  }
}

///|
test "a line in a box drawn with a look moves and scales with it, its width as its corners' would" {
  let ink = 0x24272BFFL
  // the box at (0, 0), 100 by 100, scaled 2 about its middle (50, 50): (10, 50) to (90, 50) goes to (-30, 50) to
  // (130, 50), 2 wide to 4
  let t = lines_at(0.0, 0.0, [@ui.line([(10.0, 50.0), (90.0, 50.0)], width=2.0, color=ink)], look=@ui.look(scale=2.0))
  let got = t.drawn_lines()
  assert_eq(got.length(), 1)
  let (x0, y0, x1, y1, w, _) = got[0]
  assert_true((x0 - -30.0).abs() < 1.0e-9 && (y0 - 50.0).abs() < 1.0e-9)
  assert_true((x1 - 130.0).abs() < 1.0e-9 && (y1 - 50.0).abs() < 1.0e-9)
  assert_true((w - 4.0).abs() < 1.0e-9)
}
