// A Tester over mac_capture_disclosure's kept text and frames (textrec_mac_capture_disclosure.mbt), made by scripts/chk textrec.

///|
test "the disclosure page under a Tester over mac_capture_disclosure's kept text draws, frame for frame, what it drew" {
  reset()
  let t = @ui.Tester::new(fn(c) { gallery(c, "disclosure") }, w=960.0, h=720.0, text=run_mac_capture_disclosure, run=run_mac_capture_disclosure, scale=1.0, time=0.0 - 16.0, stable=true)
  let frames = t.replay_frames(run_mac_capture_disclosure)
  let apart = frames.filter(fn(f) { f.1 != f.2 })
  println("frames \{frames.length()}, apart \{apart.length()}, text missing \{Repr(t.text_missing())}")
  if apart.length() > 0 {
    println("first apart: frame \{apart[0].0}")
    for line in t.drawn_text().split("\n") {
      println("TDUMP " + line.to_owned())
    }
    for f in frames {
      println("REHASH mac_capture_disclosure \{f.0} \{f.2}")
    }
  }
  assert_true(frames.length() > 0)
  assert_eq(t.text_missing(), [])
  assert_eq(apart.length(), 0)
}
