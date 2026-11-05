// How far a list laid out from its end has its last row below where it shows to (Scroll::end_below_told): what a page's
// "to the latest" shows by.

///|
test "scrolls_anchored: its last row's foot below where it shows, told as it is laid out; as far as can be once laid out nowhere" {
  let c = anchored_case(100)
  assert_eq(c.scroll.end_below_told(), 0.0)
  // (wheeled 20 toward its start: its last row partly in sight, 20 below)
  c.tree.wheel_at(150.0, 50.0, 0.0, -20.0, 0, 20.0) |> ignore
  c.tree.frame(390.0, 844.0, now=1000.0) |> ignore
  assert_eq(c.scroll.end_below_told(), 20.0)
  // (40 more: its last row out of sight, laid out nowhere, as far as can be though measured before, 60 below)
  c.tree.wheel_at(150.0, 50.0, 0.0, -40.0, 0, 1020.0) |> ignore
  c.tree.frame(390.0, 844.0, now=2000.0) |> ignore
  assert_eq(c.scroll.end_below_told(), @double.infinity)
  // (and far from it: as far as can be)
  c.put.set(Some((10, 0.0)))
  c.tree.frame(390.0, 844.0, now=3000.0) |> ignore
  assert_eq(c.scroll.end_below_told(), @double.infinity)
}
