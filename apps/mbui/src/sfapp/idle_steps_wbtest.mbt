// A window left alone with its message field focused while an agent works: the working marks step on the resident
// clock (10 a second), each step drawn as their looks alone. The field's focus is no reason to build anything again:
// a focused field built the whole window (an island of ~600 nodes) at every step, 5-7 ms of a Mac's main thread ten
// times a second for as long as an agent worked (2026-11-01, MBUI_PROBE on a person's Mac).

///|
/// What the frames a host draws over `ms` were built for (each frame's built_why, "" for one built nothing), and how
/// many there were.
fn steps_built(t : @ui.Tester, ms : Double) -> (Int, Array[String]) {
  let until = t.time() + ms
  let built : Array[String] = []
  let mut frames = 0
  while t.time() < until {
    let w = t.wanted_after()
    if w == @double.infinity {
      break
    }
    let at = if w <= t.time() { t.next_frame_time() } else { t.display_frame(w) }
    if at > until {
      break
    }
    t.frame_at(at)
    frames += 1
    if t.built_why() != "" {
      built.push(t.built_why())
    }
  }
  (frames, built)
}

///|
test "a wide window left alone, its field focused, an agent at work: each step of the marks builds nothing" {
  for mode in ["home", "chat"] {
    let calls : Array[Made] = []
    let t = wide_tester(calls, mode~)
    t.keep_parts(true)
    t.check_looks(false)
    ignore(host_frames_till(t, t.time() + 4000.0))
    assert_true(t.ime().0, msg="\{mode}: the message field focused")
    let (frames, built) = steps_built(t, 2000.0)
    // (the marks still step: frames come, a step each)
    assert_true(frames >= 10, msg="\{mode}: \{frames} frames")
    assert_eq(built, [], msg="\{mode}: \{built.length()} of \{frames} frames built")
  }
}

///|
test "a wide window not shown while an agent works: its marks draw no steps till it is shown again" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="home")
  t.keep_parts(true)
  t.check_looks(false)
  // (past the field's caret blinking: it rests shown after caret_blinks_for_ms)
  ignore(host_frames_till(t, t.time() + @ui.caret_blinks_for_ms + 1000.0))
  t.app_state(false, false)
  let (hidden, _) = steps_built(t, 2000.0)
  assert_true(hidden <= 1, msg="\{hidden} frames drawn while not shown")
  t.app_state(true, true)
  let (shown, _) = steps_built(t, 2000.0)
  assert_true(shown >= 10, msg="\{shown} frames once shown again")
}
