///|
test "a terminal is opened as many cells as the window holds under its bar" {
  // (the code face measured as a host measures it: a Tester's)
  @ui.Tester::new(fn(_) { () }, w=390.0, h=844.0) |> ignore
  let (cols, rows) = terminal_cells(390.0, 844.0, 0.0)
  assert_true(cols >= 40 && cols <= 60, msg="\{cols} across a phone")
  assert_true(rows >= 30, msg="\{rows} down a phone")
  let (wide, _) = terminal_cells(1280.0, 800.0, 0.0)
  assert_true(wide > 2 * cols, msg="\{wide} across a wide window, \{cols} a phone's")
  // (at least 20 × 6, however small)
  assert_eq(terminal_cells(100.0, 100.0, 0.0), (20, 6))
}
