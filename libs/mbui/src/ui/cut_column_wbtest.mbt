// What is cut short (`w=Cut`) in a column: as wide as what it holds, never grown past that, so a column that stretches
// what it holds keeps it at its start (a track round a choice's options is not drawn across the column); cut to the
// column where it is narrower.

///|
let cut_column_ink : Int64 = 0x34C759FFL

///|
/// A column `pw` wide aligning as `align`, holding a box cut short round a 30-wide one: where that box is.
fn cut_in_column(align : Align, pw? : Double = 100.0) -> (Double, Double, Double, Double) raise {
  let t = Tester::new(fn(c) {
    c.box(align=AStart, fn() {
      c.box(w=Px(pw), h=Px(40.0), align~, fn() {
        c.box(dir=Row, w=Cut, bg=cut_column_ink, fn() {
          c.box(w=Px(30.0), h=Px(10.0), fn() {  }) |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  rect_of_bg(cut_column_ink)
}

///|
test "cut short in a column: as wide as what it holds where the column stretches or starts what it holds" {
  let (x, _, w, _) = cut_in_column(AStretch)
  assert_eq((x, w), (0.0, 30.0))
  let (x, _, w, _) = cut_in_column(AStart)
  assert_eq((x, w), (0.0, 30.0))
}

///|
test "cut short in a column: placed as a centring column places it" {
  let (x, _, w, _) = cut_in_column(ACenter)
  assert_eq((x, w), (35.0, 30.0))
}
