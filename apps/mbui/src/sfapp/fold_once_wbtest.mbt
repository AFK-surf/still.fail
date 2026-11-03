// The block's way between open and folded (sfdesk's pane_view.mbt): each frame built once, the page getting wider or
// narrower telling nothing that reads only how tall its composer is (@motion.measured); the sidebar's rows and the
// chat's kept as they were built, what moves each frame building none of them again.

///|
test "大屏: on the block's way each frame built once, the lists' rows kept" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  t.keep_parts(true)
  t.run_for(kept_rows_still_ms)
  let t0 = t.time()
  t.advance(between_frames_ms)
  @sfdesk.wide.folded.set(true)
  // (its first frames building them once for all of its way)
  t.frame_at(t0 + 40.0)
  t.frame_at(t0 + 60.0)
  let on_way : Array[Int] = []
  for at in [80.0, 100.0, 120.0] {
    t.frame_at(t0 + at)
    let (kept, _) = t.rows_as_nodes()
    assert_true(kept > 0, msg="at \{at}: no rows kept")
    on_way.push(t.frame_perf().passes)
  }
  assert_eq(on_way, [1, 1, 1])
}
