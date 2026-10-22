// What is at work steps round (Spokes.kt): a step every 100 ms, the brightest a step further, the same again after
// eight; nothing drawn between the steps.

///|
fn spokes_tester(f : (@ui.Ctx) -> Unit) -> @ui.Tester {
  @ui.Tester::new(fn(c) { f(c) }, w=100.0, h=100.0)
}

///|
test "spokes and segments: a step every 100 ms, back where they were after eight" {
  for draw in [
    fn(c : @ui.Ctx) { @sf.spokes(c, 10.0, 0xF2B01EFFL) |> ignore },
    fn(c : @ui.Ctx) { @sf.segments(c, 24.0, 1.5, 0xF57E4DFFL, 0xFFFFFFFFL) |> ignore },
  ] {
    let t = spokes_tester(draw)
    t.draw()
    let at = t.drawlist()
    // between two steps, the same
    t.run_for(@sf.spoke_step_ms / 2.0)
    assert_eq(t.drawlist(), at)
    t.run_for(@sf.spoke_step_ms / 2.0)
    assert_true(t.drawlist() != at)
    t.run_for(7.0 * @sf.spoke_step_ms)
    assert_eq(t.drawlist(), at)
  }
}
