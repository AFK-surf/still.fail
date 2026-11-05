// A chat pushed from the list on a phone whose frames are drawn for its next vsync, ahead of its now (as a device's
// are): each frame laid out in a few passes, its page sliding in at the frame's moment in every one of them (a phone's
// came to 512 passes, the page's place told at the change's moment and the frame's, one pass after the other).

///|
/// The most layout passes a frame takes as a chat is pushed from the list, frames drawn `ahead` of the host's now.
fn passes_pushed(ahead : Double) -> Int {
  let t = wide_tester([], mode="home", w=390.0, h=844.0, platform=2)
  t.set_frame_period(host_phone_period)
  t.frames_shown_ahead(ahead)
  t.run_as_host(@ui.move_most_ms)
  t.record_host()
  let (x, y) = t.find("整理发布清单").unwrap()
  t.touch_at(0, x, y, t.time())
  t.touch_at(2, x, y, t.time())
  t.run_as_host(@ui.move_most_ms)
  t.host_frames().fold(init=0, fn(m, f) { if f.passes > m { f.passes } else { m } })
}

///|
test "a chat pushed on a phone whose frames are drawn ahead of its now: each frame laid out in a few passes" {
  let vsync_ahead = host_phone_period
  assert_true(passes_pushed(vsync_ahead) <= 4)
}
