// A long chat flung from its end comes to rest as many rows from it as a chat of its last 30 does: where it is counted to
// be among all its rows (each counted as tall as those measured are, a chat of 3000 counted otherwise as each is) is no
// end the hand's fling is held to as it rests (a jump of 636 rows as it came to rest, 2026-11-05).

///|
/// How many rows from its end chat `mode` rests, flung from its end on a phone as host_frames_wbtest's walk flings it.
fn rows_from_end_flung(mode : String) -> Int {
  let t = wide_tester([], mode~, w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  let n = t.visible().1
  let (lx, ly) = (195.0, 844.0 * 0.3)
  t.touch_at(0, lx, ly, t.time())
  for i in 1..=12 {
    t.run_for(host_finger_ms)
    t.touch_at(1, lx, ly + 15.0 * i.to_double(), t.time())
  }
  t.touch_at(2, lx, ly + 180.0, t.time())
  // (looked at as it goes, a frame a tenth of a second: as host_frames_wbtest's walk draws it)
  for _ in 0..<20 {
    t.run_for(100.0)
    t.draw()
  }
  n - t.visible().1
}

///|
test "a chat of 3000 flung from its end rests as many rows from it as one of its last 30, its fling's end no other" {
  assert_eq(rows_from_end_flung("chat-long"), rows_from_end_flung("chat-long-30"))
}
