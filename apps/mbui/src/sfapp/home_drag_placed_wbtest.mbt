// Home's list dragged by a finger on a phone for seconds, as instrbench's home scene drags it (scripts/bench/
// scroll-home.drive): every frame drawn on the way as it was laid out (mbui's Tester::hold_placed, held on each). The
// drags are a scripted run's steps, taken as each frame ends after it was presented, as a host takes input between
// frames: what a row changes as the finger moves (its end let go of as it was held) is laid out then, and placed by
// the frame after it.

///|
/// Four drags up the list, each 430 points in a second from where the bench's start, the finger lifted at each end.
let home_drag_script : String =
  #|drag 195 700 0 -430 1000
  #|drag 195 700 0 -430 1000
  #|drag 195 700 0 -430 1000
  #|drag 195 700 0 -430 1000
  #|exit

///|
test "Home's long list dragged by a finger for seconds: every frame on the way drawn as it was laid out" {
  let src = fixture_app("long")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("整理发布清单") is Some(_))
  let log = t.drive(home_drag_script)
  assert_true(log.contains("EXIT 0"), msg=log.join("\n"))
  // (the list scrolled by the drags: its first rows gone up out of sight)
  assert_true(t.find("整理发布清单") is None)
  assert_eq(t.placed_faults(), [])
}
