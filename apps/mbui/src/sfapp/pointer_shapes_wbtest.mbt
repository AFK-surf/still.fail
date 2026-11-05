// The pointer's shape where main has the arrow: round the words of a page picked with the pointer (the I-beam over
// those words alone), and over a chat's station in its bar, which a pointer rests on for its card and presses nothing.

///|
fn shape_at(t : @ui.Tester, x : Double, y : Double) -> String {
  let line = t.probe_at(x, y).split("\n").next().unwrap().to_string()
  match line.find("cursor=") {
    Some(i) => line.view(start_offset=i + 7).to_string()
    None => line
  }
}

///|
test "小屏 by mouse: the pointer over Home's list between its rows is the arrow, not the I-beam" {
  let t = wide_tester([], mode="home", w=390.0, h=844.0, platform=0)
  t.run_for(@ui.move_most_ms * 2.0)
  let shapes = [24.0, 120.0, 216.0, 312.0, 360.0].map(fn(x) { shape_at(t, x, 72.0) })
  assert_eq(shapes, ["Arrow", "Arrow", "Arrow", "Arrow", "Arrow"])
}

///|
test "大屏 by mouse: a chat opened from the list, the arrow over its station in the bar and round its messages' words" {
  let t = wide_tester([], mode="home", w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms * 2.0)
  t.tap_text("夜里的构建又失败了")
  t.run_for(@ui.move_most_ms * 3.0)
  // (its station, Maple, in the bar: the arrow; under the bar left of its messages: the arrow)
  assert_eq([shape_at(t, 504.0, 24.0), shape_at(t, 312.0, 72.0), shape_at(t, 360.0, 72.0)], ["Arrow", "Arrow", "Arrow"])
  // (over a message's words still the I-beam)
  let (x, y) = t.find("好的，我来处理。").unwrap()
  assert_eq(shape_at(t, x + 4.0, y + 4.0), "IBeam")
}
