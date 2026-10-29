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
  // what they were for, the heaviest first, each its work and count
  let whys = lines.filter(fn(l) { l.has_prefix("frames why (the 5 heaviest, ms/frames): ") })
  assert_eq(whys.length(), 1)
  assert_true(lines.any(fn(l) { l.has_prefix("frames heaviest: ") }))
  assert_true(lines.contains("test: said"), msg=lines.to_string())
  // (asked with the summary's span: the record's, to the display's frame)
  assert_eq(asked.length(), 1)
  assert_true(asked[0] >= probe_record_ms && asked[0] < probe_record_ms + first_frame_ms, msg=asked.to_string())
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
