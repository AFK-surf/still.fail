// The device's performance record (@hostapi.perf_state, perf_line): the frame probe's summary into it every 5 s while
// it is kept, none while it is not; turned on while the app runs, without MBUI_PROBE.

///|
fn perf_scene(c : Ctx) -> Unit {
  c.box(w=Fill(1.0), h=Fill(1.0), fn() { c.text("性能", wrap=false) |> ignore }) |> ignore
}

///|
test "the frame probe's summary goes into the performance record every 5 s while it is kept, what the frames were for and what the app adds with it; nothing while it is off" {
  let t = Tester::new(perf_scene)
  let asked : Array[Double] = []
  perf_also("test", fn(span) {
    asked.push(span)
    "said"
  })
  t.set_perf(0)
  t.frame(ms=probe_record_ms)
  t.frame(ms=probe_record_ms)
  assert_eq(t.perf_said().1.length(), 0)
  assert_eq(asked.length(), 0)
  @hostapi.set_perf(true)
  assert_eq(t.perf_said().0, [true])
  // (its first frame begins the sum, said a record's span on)
  t.frame()
  t.frame(ms=probe_record_ms)
  let lines = t.perf_said().1.copy()
  let frames = lines.filter(fn(l) { l.has_prefix("frames: fps=") })
  assert_eq(frames.length(), 1)
  assert_true(frames[0].contains(" main_busy=") && frames[0].contains(" slow="))
  // (the window's tree's part of each frame first among its phases; the memory held, the most of the span's frames
  // too: none on the fake host)
  assert_true(frames[0].contains(" avg tree/msgs/build/layout/paint/present=[") && frames[0].contains(" mem=-1MB mem_peak=-1MB "), msg=frames[0])
  // its seconds' busiest beside its average, its span, what its last frame was for
  assert_true(frames[0].contains(" fps_peak=1 ") && frames[0].contains(" span=5") && frames[0].contains(" (last: "), msg=frames[0])
  // what they were for, the heaviest first, each its work and count
  let whys = lines.filter(fn(l) { l.has_prefix("frames why (the 5 heaviest, ms/frames): ") })
  assert_eq(whys.length(), 1)
  assert_true(lines.any(fn(l) { l.has_prefix("frames heaviest: ") }))
  assert_true(lines.contains("test: said"), msg=Repr(lines).to_string())
  // (asked with the summary's span: the record's, to the display's frame)
  assert_eq(asked.length(), 1)
  assert_true(asked[0] >= probe_record_ms && asked[0] < probe_record_ms + first_frame_ms, msg=Repr(asked).to_string())
  @hostapi.set_perf(false)
  t.frame(ms=probe_record_ms)
  t.frame(ms=probe_record_ms)
  assert_eq(t.perf_said().1, lines)
  probe_also.clear()
}

///|
test "where the device keeps no performance record, it is not turned on and nothing goes into it" {
  let t = Tester::new(perf_scene)
  assert_eq(@hostapi.perf_state(), -1)
  @hostapi.set_perf(true)
  @hostapi.perf_line("app: screen shown")
  assert_eq(t.perf_said(), ([], []))
}

///|
test "the record times an outside event including nested work, once and only while recording" {
  let t = Tester::new(perf_scene)
  t.set_perf(0)
  @hostapi.set_perf(true)
  let clock = Ref(100.0)
  set_work_clock(Some(fn() { clock.val }))
  defer set_work_clock(None)
  view_event_said(fn() {  }, fn() {
    clock.val = 120.0
    view_event_said(fn() {  }, fn() { clock.val = 180.0 }, what="pointer")
  }, what="touch-up")
  let events = t.perf_said().1.filter(fn(s) { s.has_prefix("event: ") })
  assert_eq(events.length(), 1)
  assert_true(events[0].contains("kind=touch-up") && events[0].contains("ms=80"), msg=events[0])
  view_event_said(fn() {  }, fn() { clock.val = 190.0 }, what="touch-up")
  assert_eq(t.perf_said().1.filter(fn(s) { s.has_prefix("event: ") }).length(), 1)
  @hostapi.set_perf(false)
  view_event_said(fn() {  }, fn() { clock.val = 290.0 }, what="touch-up")
  assert_eq(t.perf_said().1.filter(fn(s) { s.has_prefix("event: ") }).length(), 1)
}

///|
test "the record says how long a finger up waited for the next frame to be submitted" {
  let t = Tester::new(perf_scene)
  t.set_perf(0)
  @hostapi.set_perf(true)
  let clock = Ref(100.0)
  set_work_clock(Some(fn() { clock.val }))
  defer set_work_clock(None)
  touch_in(0, 1, 10.0, 10.0)
  touch_in(2, 1, 10.0, 10.0)
  clock.val = 220.0
  t.draw()
  let touches = t.perf_said().1.filter(fn(s) { s.has_prefix("touch: ") })
  assert_eq(touches.length(), 1)
  assert_true(touches[0].contains("to_submit=120"), msg=touches[0])
  t.draw()
  assert_eq(t.perf_said().1.filter(fn(s) { s.has_prefix("touch: ") }).length(), 1)
  // An unrecognised finger up, and a touch followed by the app leaving the foreground, must not time a later frame.
  touch_in(2, 99, 10.0, 10.0)
  clock.val = 320.0
  t.draw()
  touch_in(0, 2, 10.0, 10.0)
  touch_in(2, 2, 10.0, 10.0)
  touches_off()
  clock.val = 420.0
  t.draw()
  assert_eq(t.perf_said().1.filter(fn(s) { s.has_prefix("touch: ") }).length(), 1)
  @hostapi.set_perf(false)
}

///|
test "the performance record's frames: a pause between them is not slow, and a summary is of its own span's frames" {
  let t = Tester::new(perf_scene)
  t.set_perf(0)
  @hostapi.set_perf(true)
  t.draw()
  // a burst of frames, then none for long: said as the first frame after it comes, its span the burst's and the pause's
  t.frame(ms=first_frame_ms)
  t.frame(ms=first_frame_ms)
  t.frame(ms=3.0 * probe_record_ms)
  let frames = t.perf_said().1.filter(fn(l) { l.has_prefix("frames: fps=") })
  assert_eq(frames.length(), 1)
  // (the burst's second at 3 frames, not averaged into the 15 s; the frame after the pause in the next summary)
  assert_true(frames[0].contains(" fps_peak=3 ") && frames[0].contains(" span=15"), msg=frames[0])
  // (no frame's own work was long: the pause before the last is no slow frame)
  assert_true(frames[0].has_suffix(" slow=0"), msg=frames[0])
  @hostapi.set_perf(false)
}

///|
test "the performance record names the motions the frames were built for: what each is, who told it, its frames and work" {
  let who = Mover::new()
  let t = Tester::new(fn(c) {
    c.shows_motion(who, true)
    perf_scene(c)
  })
  t.set_perf(0)
  @hostapi.set_perf(true)
  t.ctx().moving(who, Endless::{  }, what="Anim \"slide\" to 1")
  let at = place_here()
  who.told_as("Anim \"slide\"", at)
  t.frame()
  t.run_for(probe_record_ms + 100.0)
  let lines = t.perf_said().1
  let named = "a motion of Anim \"slide\", told at \{at}"
  let motions = lines.filter(fn(l) { l.has_prefix("frames motions (the 5 heaviest, ms/frames): ") })
  assert_eq(motions.length(), 1, msg=Repr(lines).to_string())
  assert_true(motions[0].has_suffix(" " + named) && !motions[0].contains(" | "), msg=motions[0])
  let whys = lines.filter(fn(l) { l.has_prefix("frames why (the 5 heaviest, ms/frames): ") })
  assert_true(whys[0].contains("built: the clock read at " + named), msg=whys[0])
  @hostapi.set_perf(false)
}
