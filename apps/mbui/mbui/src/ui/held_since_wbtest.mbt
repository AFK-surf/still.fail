///|
/// How long the test's wait is (ms).
let held_since_wait_ms : Double = 300.0

///|
/// How long the test stays before its wait comes on (ms, a whole number of frames at 60 and at 120 a second).
let held_since_before_ms : Double = 100.0

///|
/// The wait's wake, `on` turned on between frames and the frames drawn every `period`: when the wait will have held.
fn held_since_wake(period : Double) -> Double {
  let on = @signals.signal(false)
  let t = Tester::new(fn(c) { c.held("held-since", on.get(), held_since_wait_ms) |> ignore }, w=200.0, h=100.0)
  t.set_frame_period(period)
  t.draw()
  t.run_for(held_since_before_ms)
  let told = t.fake.time
  // (between frames, at the test's moment: the first frame that builds it is the display's next, a period on)
  on.set(true)
  t.frame()
  let wake = match t.next_wake() {
    Some((at, _)) => at
    None => -1.0
  }
  wake - told
}

///|
test "a wait without its own since counts from the moment of what its build was told by, not the frame that first saw it: the same wake whatever frames are drawn" {
  let at_60 = held_since_wake(1000.0 / 60.0)
  let at_120 = held_since_wake(1000.0 / 120.0)
  assert_true((at_60 - held_since_wait_ms).abs() < 1.0e-6, msg="at 60 a second: held \{at_60} after it came on")
  assert_true((at_120 - held_since_wait_ms).abs() < 1.0e-6, msg="at 120 a second: held \{at_120} after it came on")
}

///|
/// How long after the first change the one that turns the wait on comes (ms: between two of the display's frames at
/// 60 a second, with one of them between at 120).
let held_since_gap_ms : Double = 10.0

///|
/// A change A told the build's watch, then B turned the wait on `held_since_gap_ms` later, nothing drawn between them
/// but what the display draws at `period`: how long after B the wait held, and what the Tester was told of it.
fn held_since_two(period : Double) -> (Double, Array[String]) {
  let on = @signals.signal(false)
  let other = @signals.signal(0)
  let t = Tester::new(
    fn(c) {
      ignore(other.get())
      c.held("held-since-two", on.get(), held_since_wait_ms) |> ignore
    },
    w=200.0,
    h=100.0,
  )
  let said : Array[String] = []
  wait_look.val = Some(fn(kind, _, _) { said.push(kind) })
  t.set_frame_period(period)
  t.draw()
  t.run_for(held_since_before_ms)
  // (A: told the watch the build reads)
  other.set(1)
  let b_at = t.fake.time + held_since_gap_ms
  // (the display's frame between them, where it has one)
  if t.next_frame_time() < b_at {
    t.frame()
  }
  t.fake.time = b_at
  // (B: turns the wait on)
  on.set(true)
  t.frame()
  let wake = match t.next_wake() {
    Some((at, _)) => at
    None => -1.0
  }
  (wake - b_at, said)
}

///|
test "two changes told one watch before a build, the second turning the wait on: it counts from the first, early by their distance, and says so; a frame between them, from the second" {
  let (at_60, said_60) = held_since_two(1000.0 / 60.0)
  let (at_120, said_120) = held_since_two(1000.0 / 120.0)
  // (no frame between them at 60: from A, early by the gap, said)
  assert_true(
    (at_60 - (held_since_wait_ms - held_since_gap_ms)).abs() < 1.0e-6,
    msg="at 60 a second: held \{at_60} after B",
  )
  assert_true(said_60.contains("held_causes"), msg="at 60 a second: \{Repr(said_60)}")
  // (a frame between them at 120: B told alone, from B)
  assert_true((at_120 - held_since_wait_ms).abs() < 1.0e-6, msg="at 120 a second: held \{at_120} after B")
  assert_true(!said_120.contains("held_causes"), msg="at 120 a second: \{Repr(said_120)}")
}
