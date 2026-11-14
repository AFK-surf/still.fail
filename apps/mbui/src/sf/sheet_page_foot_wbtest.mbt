// A panel's foot on a phone's sheet as a step further in comes in its place, taller (a page of the same sheet,
// sheet_node: a preset's dialog and its 添加目录): the page going goes with the sheet's top as it slides off, its foot
// with it from where it stood, never drawn back at once by the way the sheet's height goes for the page coming (it was:
// 784 to 572 in the frame 添加目录 came in, mbui's sizes_steady, 「动画执行到一半突变也算突变」); the page coming has its
// foot at the window's foot all the way. At 60 and 120 a second the Tester judges every frame of it.

///|
/// A panel of nodes of `lines` lines with 完成 at its foot, whose 往里 opens one of `next` lines a share of the window
/// tall, 好 at its foot, a step further in.
fn foot_pages(lines : Int, next : Int) -> (Anchor) -> Unit {
  fn(_) {
    panel_nodes(
      "第一",
      fn(v, close) {
        for i in 0..<lines {
          words_node(v, fn() { "第一的第\{i + 1}行" }, fn() { panel_note_words }) |> ignore
        }
        button_node(v, fn() { "往里" }, fn() {
          close()
          panel_nodes(
            "第二",
            fn(w, _) {
              for i in 0..<next {
                words_node(w, fn() { "第二的第\{i + 1}行" }, fn() { panel_note_words }) |> ignore
              }
            },
            from=Unanchored,
            tall=0.86,
            foot=fn(f, close) { button_node(f, fn() { "好" }, close) |> ignore },
          )
        })
        |> ignore
      },
      from=Unanchored,
      foot=fn(f, close) { button_node(f, fn() { "完成" }, close) |> ignore },
    )
  }
}

///|
test "a step further in taller than the page it comes in the place of: the page going takes its foot with it from where it stood, the one coming has its at the window's foot" {
  let t = presenting_tester(phone, foot_pages(2, 3))
  open_it(t)
  let went : Array[Double] = []
  let came : Array[Double] = []
  let (_, stood) = t.drawn_of("完成").unwrap()
  t.tap_text("往里")
  for _ in 0..<way_frames {
    match t.drawn_of("完成") {
      Some((_, y)) => went.push((y * 10.0).round() / 10.0)
      None => ()
    }
    match t.drawn_of("好") {
      Some((_, y)) => came.push((y * 10.0).round() / 10.0)
      None => ()
    }
    t.run_for(@ui.frame_period_default)
  }
  // (from where it stood, in the frame it was pressed in too; on its way up with the sheet's top after, never down)
  assert_true(went.length() > 1 && (went[0] - (stood * 10.0).round() / 10.0).abs() < 0.5, msg="完成 \{stood} \{Repr(went)}")
  for i in 1..<went.length() {
    assert_true(went[i] <= went[i - 1], msg="完成 \{Repr(went)}")
  }
  assert_true(came.length() > 1 && came.iter().all(fn(y) { y == came[came.length() - 1] }), msg="好 \{Repr(came)}")
}
