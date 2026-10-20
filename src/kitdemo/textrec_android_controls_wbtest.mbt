// A Tester over android_controls's kept text and frames (textrec_android_controls.mbt), made by scripts/textrec_test.py.

///|
test "the controls page under a Tester over android_controls's kept text draws, frame for frame, what it drew" {
  reset()
  let t = @ui.Tester::new(fn(c) { gallery(c, "controls") }, w=411.4285583496094, h=838.4761962890625, text=run_android_controls, run=run_android_controls, scale=2.625, time=41502.944815 - 16.0, stable=true, platform=2)
  let frames = t.replay_frames(run_android_controls)
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
