///|
test "typing into an existing line tells the host to redraw the changed text" {
  let f = Field::new(text="one\ntwo\nthree\nfour\nfive\n")
  let t = Tester::new(fn(_c) { }, w=300.0, h=300.0, platform=2)
  set_view_app(fn(root) {
    root.box(fn(box) {
      box.over(Is(true)).offset(Is((20.0, 20.0))).width(Is(Some(200.0))) |> ignore
      field(box, f, font_size=16.0, line=24.0, min_lines=6, max_lines=6) |> ignore
    }) |> ignore
  })
  t.draw()
  g().focus_field(f)
  t.draw()
  t.measure_as_host()
  t.record_host()
  let at = t.time()
  t.text_told("six", at)
  t.frame_at(at + 1000.0 / 60.0)
  assert_eq(f.text(), "one\ntwo\nthree\nfour\nfive\nsix")
  assert_true(t.text_runs().iter().any(fn(r) { r.text == "six" }), msg="the sixth line is in the draw list")
  let frames = t.host_frames()
  assert_true(frames.length() > 0, msg="the host received a frame")
  assert_true(frames.iter().any(fn(frame) { frame.changed }), msg="the host replaced the frame")
  for frame in frames {
    if frame.changed {
      assert_true(frame.damage.iter().any(fn(p) {
        p.2 < 0.0 || (p.0 <= 20.0 && p.1 <= 140.0 && p.0 + p.2 >= 40.0 && p.1 + p.3 >= 160.0)
      }), msg="the changed sixth line must reach the host's redraw area: \{frame}")
    }
  }
}

///|
test "a retained field's timed caret redraws where it disappears and appears" {
  let f = Field::new()
  let t = Tester::new(fn(_c) { }, w=300.0, h=300.0, platform=2)
  set_view_app(fn(root) {
    root.box(fn(box) {
      box.over(Is(true)).offset(Is((20.0, 20.0))).width(Is(Some(200.0))) |> ignore
      field(box, f, font_size=16.0, line=24.0) |> ignore
    }) |> ignore
  })
  t.draw()
  g().focus_field(f)
  t.draw()
  t.measure_as_host()
  t.record_host()
  let at = t.time()
  let shown = t.frame_hash()
  t.frame_at(at + caret_blink_ms * 1.5)
  assert_true(t.frame_hash() != shown, msg="the caret disappeared")
  t.frame_at(at + caret_blink_ms * 2.5)
  assert_eq(t.frame_hash(), shown, msg="the caret appeared again")
  let frames = t.host_frames()
  assert_eq(frames.length(), 2)
  for frame in frames {
    assert_true(frame.changed && frame.damage.iter().any(fn(p) {
      p.2 < 0.0 || (p.0 <= 20.0 && p.1 <= 20.0 && p.0 + p.2 >= 21.0 && p.1 + p.3 >= 40.0)
    }), msg="the caret's change must reach the host's redraw area: \{frame}")
  }
}
