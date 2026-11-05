// A window bar can cover words from the conversation. Walking the pointer as in the page comparison must still report
// the text cursor over those words.

///|
fn chat_toprow_shapes(t : @ui.Tester, w : Double, h : Double, points : Array[(Double, Double)]) -> Array[String] {
  let found = Array::make(points.length(), "")
  let mut y = 24.0
  while y < h {
    let mut x = 24.0
    while x < w {
      t.probe_at(x, y) |> ignore
      for i, point in points {
        if point == (x, y) { found[i] = "\{t.cursor()}" }
      }
      x += 48.0
    }
    y += 48.0
  }
  found
}

///|
test "words under a wide chat's window bar say the text cursor" {
  let t = wide_tester([], mode="chat-cards", w=1280.0, h=800.0, platform=0)
  t.export_frames()
  t.set_frame_period(1000.0 / 60.0)
  t.run_for(@ui.move_most_ms * 2.0)
  assert_eq(chat_toprow_shapes(t, 1280.0, 800.0, [(408.0, 24.0)]), ["IBeam"])
}

///|
test "words under a chat brought to the front say the text cursor" {
  let t = wide_tester([], mode="chat-long", w=740.0, h=1000.0, platform=0)
  t.export_frames()
  t.set_frame_period(1000.0 / 60.0)
  t.run_for(@ui.move_most_ms * 2.0)
  chat_toprow_shapes(t, 740.0, 1000.0, []) |> ignore
  t.move(790.0, 1050.0)
  t.touch_at(0, 712.0, 500.0, t.time())
  t.run_for(80.0)
  t.touch_at(2, 712.0, 500.0, t.time())
  t.run_for(@ui.move_most_ms * 2.0)
  assert_eq(chat_toprow_shapes(t, 740.0, 1000.0, [(120.0, 24.0), (168.0, 24.0)]), ["IBeam", "IBeam"])
}
