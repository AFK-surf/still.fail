// The chats' list on a phone flung, its frames as their host gets them (Tester::run_as_host): rows come into the
// window and go out of it, and no frame of it that builds nothing again is drawn again whole: each put together from
// the layers' blocks, what changed of them drawn again where its reference is (a phone's list flung was painted
// whole, the old frame and all of the tree gone through, 1885 frames of 2310, 2026-11-05; docs/retained.md rule 16).

///|
test "the chats' list flung on a phone: no frame of it drawn again whole, rows coming and going" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="long", w=390.0, h=844.0, platform=2)
  t.set_frame_period(1000.0 / 120.0)
  t.run_for(@ui.move_most_ms)
  t.record_host()
  t.host_frames() |> ignore
  let (x, y0) = (195.0, 700.0)
  t.touch_at(0, x, y0, t.time())
  t.run_as_host(1000.0 / 240.0)
  for i in 1..=12 {
    t.touch_at(1, x, y0 - 37.5 * i.to_double(), t.time())
    t.run_as_host(1000.0 / 240.0)
  }
  t.touch_at(2, x, y0 - 450.0, t.time())
  t.run_as_host(2000.0)
  let frames = t.host_frames()
  let out : Array[String] = []
  for f in frames {
    if f.changed && !f.old_built && f.whole_why != 0 {
      out.push("at \{f.at}: drawn again whole (\{f.whole_why})")
    }
  }
  assert_true(frames.length() > 100, msg="\{frames.length()} frames")
  assert_eq(out, [])
}
