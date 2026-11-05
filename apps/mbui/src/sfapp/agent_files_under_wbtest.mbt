// An agent's files it does not place right under its Markdown (prose_with_files'), not 4 apart as a person's are.

///|
/// How far under its words' last line the first file it does not place starts: the fixture's fifth message,
/// 对比图和构建日志附在下面 and compare.png under it.
fn files_under_words(t : @ui.Tester) -> Double? {
  guard t.words().iter().find_first(fn(w) { w.0.contains("对比图和构建日志附在下面") }) is Some(line) else {
    return None
  }
  let bottom = line.2 + line.4
  let mut top : Double? = None
  // Read the picture itself: the rectangles underneath it are only the portions of its waiting animation.
  for image in t.drawn_images() {
    let (x, y, w, h) = (image[0], image[1], image[2], image[3])
    if (x - line.1).abs() < 0.5 && y >= line.2 && y < bottom + 40.0 && w > 100.0 && h > 100.0 {
      top = Some(match top { Some(v) => if y < v { y } else { v }; None => y })
    }
  }
  top.map(fn(y) { (y - bottom).round() })
}

///|
test "an agent's files it does not place start right under its words, on a phone and a desktop" {
  for case in [(390.0, 2), (1280.0, 0)] {
    let t = wide_tester([], mode="chat", w=case.0, h=2400.0, platform=case.1)
    t.run_for(@ui.move_most_ms * 2.0)
    // (compare.png's picture right at the words' last line's foot, as main has it)
    assert_eq(files_under_words(t), Some(0.0))
  }
}
