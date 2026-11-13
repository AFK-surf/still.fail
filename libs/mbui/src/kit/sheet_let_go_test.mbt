///|
test "where a sheet let go goes is where it lands on from its speed, or a flick's way: either side of its line, either side of a flick" {
  let flick = @ui.flung_away
  let stop = @ui.move_stop_points(0.3)
  // (without detents, its line 80 down)
  assert_false(@kit.sheet_drag_closes(70.0, 0.0, 80.0))
  assert_true(@kit.sheet_drag_closes(90.0, 0.0, 80.0))
  assert_false(@kit.sheet_drag_closes(79.0 - stop, 0.3, 80.0))
  assert_true(@kit.sheet_drag_closes(81.0 - stop, 0.3, 80.0))
  assert_false(@kit.sheet_drag_closes(10.0, flick - 0.01, 80.0))
  assert_true(@kit.sheet_drag_closes(10.0, flick, 80.0))
  // (with detents 55% and 94% of a window 1000 tall, closing under 30%)
  let shares = [0.55, 0.94]
  let goes = fn(at, v) { @kit.sheet_goes_to(shares, at, v, 1000.0, 0.3) }
  assert_eq(goes(310.0 + stop, 0.3), Some(0.55))
  assert_eq(goes(290.0 + stop, 0.3), None)
  assert_eq(goes(400.0, flick - 0.01), Some(0.55))
  assert_eq(goes(400.0, flick), None)
  assert_eq(goes(800.0, flick), Some(0.55))
  assert_eq(goes(600.0, -flick), Some(0.94))
  assert_eq(goes(980.0, -flick), Some(0.94))
  assert_eq(goes(760.0, -(flick - 0.01)), Some(0.94))
  assert_eq(goes(740.0, 0.0), Some(0.55))
}

///|
test "lands_past: where what is let go lands on from its speed, past a line on its side of rest" {
  let s = @ui.move_stop_points(1.0)
  assert_eq(@ui.lands_at(10.0, 1.0), 10.0 + s)
  assert_eq(@ui.lands_at(10.0, -1.0), 10.0 - s)
  assert_eq(@ui.lands_at(10.0, 0.0), 10.0)
  assert_true(@ui.lands_past(101.0 - s, 1.0, 100.0))
  assert_false(@ui.lands_past(99.0 - s, 1.0, 100.0))
  assert_true(@ui.lands_past(-101.0 + s, -1.0, -100.0))
  assert_false(@ui.lands_past(-99.0 + s, -1.0, -100.0))
}
