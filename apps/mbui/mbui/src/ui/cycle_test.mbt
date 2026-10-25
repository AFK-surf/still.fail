// What never ends while shown (Ctx::cycle) steps on one clock, a frame a step; a moving picture's loop a frame as its
// next frame comes (Ctx::loop_at).

///|
test "a cycle steps on one clock: its phase at the step it is at, a frame at each step, none between" {
  let phases : Array[Double] = []
  let t = @ui.Tester::new(fn(c) {
    phases.push(c.cycle(1000.0))
    c.text("go") |> ignore
  })
  // nothing asked for at once: the next step's frame comes as its time does
  assert_true(!t.ctx().wants_frame)
  phases.clear()
  t.run_for(@ui.cycle_step_ms * 3.5)
  // each phase drawn the start of a step (on the clock's steps: 0.1 of a second each), three steps come by
  let steps : Array[Int] = []
  for p in phases {
    let at = p * 1000.0 / @ui.cycle_step_ms
    assert_true((at - at.round()).abs() < 1.0e-9, msg="\{p}")
    if !steps.contains(at.round().to_int()) {
      steps.push(at.round().to_int())
    }
  }
  assert_eq(steps.length(), 3)
  assert_eq(t.cycles().length(), 1)
  t.assert_idle()
}
