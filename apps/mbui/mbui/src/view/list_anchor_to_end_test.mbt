// A list laid out from its end said to follow its end again while short of it: on its way there by itself, told
// (Scroll::to_end_told), till it is there or the hand takes it away.

///|
test "scrolls_anchored: on its way to its end by itself told till it is there; not while the hand moves it" {
  let c = anchored_case(100)
  assert_false(c.scroll.to_end_told())
  // (wheeled 400 toward its start: following its end no more, nothing sent anywhere)
  c.tree.wheel_at(150.0, 50.0, 0.0, -400.0, 0, 20.0) |> ignore
  c.tree.frame(390.0, 844.0, now=1000.0) |> ignore
  assert_false(c.follows.get())
  assert_false(c.scroll.to_end_told())
  // (said to follow its end again: on its way there)
  c.follows.set(true)
  c.tree.frame(390.0, 844.0, now=1016.0) |> ignore
  assert_true(c.scroll.to_end_told())
  // (there, long after: no more)
  c.tree.frame(390.0, 844.0, now=5000.0) |> ignore
  c.tree.frame(390.0, 844.0, now=5016.0) |> ignore
  assert_eq(c.scroll.end_below_told(), 0.0)
  assert_false(c.scroll.to_end_told())
  // (sent again, the wheel taking it away on its way: no more)
  c.tree.wheel_at(150.0, 50.0, 0.0, -400.0, 0, 5020.0) |> ignore
  c.tree.frame(390.0, 844.0, now=6000.0) |> ignore
  c.follows.set(true)
  c.tree.frame(390.0, 844.0, now=6016.0) |> ignore
  assert_true(c.scroll.to_end_told())
  c.tree.wheel_at(150.0, 50.0, 0.0, -40.0, 0, 6030.0) |> ignore
  c.tree.frame(390.0, 844.0, now=6040.0) |> ignore
  assert_false(c.scroll.to_end_told())
}
