// The resident clock's steps (View::cycle_resident) woken for only while what reads it now is drawn: a mark that turned
// and stopped, still shown, wakes nothing; one turning, laid out nowhere (a page over it), wakes nothing either; one
// turning where it is shown, a frame each step.

///|
/// How long a turn of the marks here takes.
let turn_ms : Double = 800.0

///|
/// A second, frames are counted over.
let second_ms : Double = 1000.0

///|
/// Frames drawn over a second from now (the one at its end, Tester::run_for's, among them: 1, none woken for).
fn frames_in_a_second(t : Tester) -> Int {
  let f0 = t.ctx().frame_no
  t.run_for(second_ms)
  t.ctx().frame_no - f0
}

///|
test "the resident clock: woken for while what reads it now is drawn; not for one that stopped reading it, nor for one laid out nowhere" {
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0, platform=0)
  let a_turns = @signals.signal(true)
  let b_shown = @signals.signal(true)
  set_view_app(fn(root) {
    // A: shown all along, turning while a_turns
    root.box(fn(a) {
      a
      .width(Is(Some(20.0)))
      .height(Is(Some(20.0)))
      .ground(Is(0xFF0000FFL))
      .alpha(By(fn() { if a_turns.get() { 0.5 + 0.5 * a.cycle_resident(turn_ms) } else { 1.0 } }))
      |> ignore
    })
    |> ignore
    // B: turning all along, laid out nowhere once b_shown is not
    root.box(fn(b) {
      b
      .width(Is(Some(20.0)))
      .height(Is(Some(20.0)))
      .ground(Is(0x00FF00FFL))
      .laid_nowhere(By(fn() { !b_shown.get() }))
      .alpha(By(fn() { 0.5 + 0.5 * b.cycle_resident(turn_ms) }))
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.run_for(@view.resident_step_ms * 2.0)
  // both shown, both turning: a frame each step
  assert_true(frames_in_a_second(t) >= 8)
  // A stopped (still shown), B laid out nowhere (still turning): none
  a_turns.set(false)
  b_shown.set(false)
  t.draw()
  t.run_for(@view.resident_step_ms * 2.0)
  assert_eq(frames_in_a_second(t), 1)
  // B shown again: a frame each step again
  b_shown.set(true)
  t.draw()
  assert_true(frames_in_a_second(t) >= 8)
}
