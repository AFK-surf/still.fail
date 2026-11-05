// How far a list laid out from its end has its last row below where it shows to (Scroll::end_below_told): what a page's
// "to the latest" shows by.

///|
test "scrolls_anchored: its last row's foot below where it shows, told as it is laid out; as far as can be once laid out nowhere" {
  let c = anchored_case(100)
  assert_eq(c.scroll.end_below_told(), 0.0)
  // (wheeled 60 toward its start: its last row 60 below)
  c.tree.wheel_at(150.0, 50.0, 0.0, -60.0, 0, 20.0) |> ignore
  c.tree.frame(390.0, 844.0, now=1000.0) |> ignore
  assert_eq(c.scroll.end_below_told(), 60.0)
  // (and far from it, its last row laid out nowhere: as far as can be)
  c.put.set(Some((10, 0.0)))
  c.tree.frame(390.0, 844.0, now=2000.0) |> ignore
  assert_eq(c.scroll.end_below_told(), @double.infinity)
}

