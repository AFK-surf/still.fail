// A Tester over ios_controls's kept text and frames (textrec_ios_controls.mbt), made by scripts/textrec_test.py.

///|
test "the controls page under a Tester over ios_controls's kept text draws, frame for frame, what it drew" {
  reset()
  let t = @ui.Tester::new(fn(c) { gallery(c, "controls") }, w=402.0, h=778.0, text=run_ios_controls, run=run_ios_controls, scale=3.0, time=7973847716.666669 - 16.0, stable=true, platform=1)
  let frames = t.replay_frames(run_ios_controls)
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
