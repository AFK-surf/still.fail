// A page pushed over another on a phone, its frames as the host gets them (Tester::run_as_host, HostFrame): the pages
// slide and fade as nodes of the window's tree, so every frame of it is drawn by the tree alone, its layers moved,
// never the old frame painted again whole (scene_layers.mbt: a layer holding an old view is drawn only as the old frame
// paints; mbui, 2026-11-06: the pages are to host none).

///|
test "a chat pushed from the list on a phone: every frame of the slide drawn by the tree alone, the old frame painted again in none" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat-long", w=351.0, h=805.0, platform=2, wrap=core_lists)
  t.set_frame_period(host_phone_period)
  t.run_for(@ui.move_most_ms * 2.0)
  t.back()
  t.run_for(@ui.move_most_ms * 2.0)
  t.record_host()
  t.host_frames() |> ignore
  // (a row of the list, as a finger taps it: down and up at one moment)
  t.touch_at(0, 138.0, 215.0, t.time())
  t.touch_at(2, 138.0, 215.0, t.time())
  t.run_as_host(@ui.move_most_ms * 2.0)
  let frames = t.host_frames()
  let painted = frames.filter(fn(f) { f.changed && !f.old_built && !f.tree_alone })
  assert_true(frames.iter().any(fn(f) { f.changed }), msg="the slide drew frames")
  assert_eq(painted.map(host_said), [], msg="frames the old frame painted again whole")
}
