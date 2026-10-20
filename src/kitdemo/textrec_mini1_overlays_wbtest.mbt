// A Tester over mini1_overlays's kept text and frames (textrec_mini1_overlays.mbt), made by scripts/textrec_test.py.

///|
test "the overlays page under a Tester over mini1_overlays's kept text draws, frame for frame, what it drew" {
  reset()
  let t = @ui.Tester::new(fn(c) { gallery(c, "overlays") }, w=960.0, h=720.0, text=run_mini1_overlays, scale=1.0, time=7950002311.804377 - 16.0, stable=true)
  let frames = t.replay_frames(run_mini1_overlays)
  let apart = frames.filter(fn(f) { f.1 != f.2 })
  println("frames \{frames.length()}, apart \{apart.length()}, text missing \{t.text_missing()}")
  if apart.length() > 0 {
    println("first apart: frame \{apart[0].0}")
    for line in t.drawn_text().split("\n") {
      println("TDUMP " + line.to_owned())
    }
  }
  assert_true(frames.length() > 0)
  assert_eq(t.text_missing(), [])
  assert_eq(apart.length(), 0)
}
