// 引用 over words a mouse picked in a message, as a host builds the frames: the page's view kept where nothing it
// read changed, the message's row telling the pick as it is built (sfbase's pick.mbt, pick_pop).

///|
/// A mouse pressed at (x0, y0), dragged to (x1, y1) and let go there, as a host hands it on: each event between the
/// display's frames, the frames the app asks for drawn after it (no Tester::drag, whose draw tells it as from outside).
fn mouse_dragged(t : @ui.Tester, x0 : Double, y0 : Double, x1 : Double, y1 : Double) -> Unit {
  t.touch(0, x0, y0)
  t.frames_owed()
  // (its moves as Tester::drag's: inputs, each drawn as a host draws what it asks)
  let drag_moves = 10
  for i in 1..=drag_moves {
    let f = i.to_double() / drag_moves.to_double()
    t.frame(ms=@ui.input_step_ms)
    t.touch(1, x0 + (x1 - x0) * f, y0 + (y1 - y0) * f)
    t.frames_owed()
  }
  t.frame(ms=@ui.input_step_ms)
  t.touch(2, x1, y1)
  t.frames_owed()
}

///|
/// A mouse's click at (x, y), as a host hands it on.
fn mouse_clicked(t : @ui.Tester, x : Double, y : Double) -> Unit {
  t.touch(0, x, y)
  t.frames_owed()
  t.frame(ms=@ui.input_step_ms)
  t.touch(2, x, y)
  t.frames_owed()
}

///|
/// Where 引用 is drawn over the line `y` is on (within 60 over it), if it is.
fn pill_over(t : @ui.Tester, y : Double) -> (Double, Double)? {
  match t.words().filter(fn(w) { w.0 == "引用" && w.2 < y && w.2 > y - 60.0 }) {
    [w, ..] => Some((w.1, w.2))
    _ => None
  }
}

///|
test "大屏, built as a host builds: words a mouse picked in a message have 引用 over where it let go in the frame it let go in, there after a while and a move, gone after a press" {
  // (this form alone shows it: a default Tester builds the frame again keeping nothing and shows the pill whatever
  // the page's view read, and a run_for(500) after the scroll brings it by a read of its own)
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  t.check_looks(false)
  for _ in 0..<12 {
    match t.run_rects("做了什么") {
      [(_, y, _, _), ..] if y > 100.0 && y < 500.0 => break
      _ => t.wheel(900.0, 400.0, -200.0)
    }
  }
  let (hx, hy, _, hh) = words_rect(t, "做了什么")
  let (ix, iy, iw, ih) = words_rect(t, "滚动位置记成")
  mouse_dragged(t, hx + 1.0, hy + hh / 2.0, ix + iw - 1.0, iy + ih / 2.0)
  assert_true(t.ctx().selected_text().has_suffix("滚动位置记成"), msg=t.ctx().selected_text())
  match pill_over(t, iy) {
    Some((qx, _)) => assert_true((qx - (ix + iw)).abs() < 40.0, msg="引用 at \{qx}")
    None => fail("no 引用 over where the pointer let go, in the frame it let go in")
  }
  t.run_for(@ui.move_most_ms)
  assert_true(pill_over(t, iy) is Some(_), msg="引用 gone once all the let-go set off is over")
  t.touch(1, ix + iw + 30.0, iy + 40.0)
  t.frames_owed()
  assert_true(pill_over(t, iy) is Some(_), msg="引用 gone after the pointer moved")
  // (a click of its own, not a second of the press that picked: a double click's picks a word)
  t.run_for(@ui.double_click_ms)
  mouse_clicked(t, hx + 1.0, hy + hh / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(t.ctx().selected_text(), "")
  assert_true(t.words().filter(fn(w) { w.0 == "引用" }).is_empty(), msg="引用 still there after a press")
}

///|
test "中屏's tape, built as a host builds: words a mouse picked in a message have 引用 over them in the frame it let go in, there after a while and a move, gone after a press" {
  // (this form alone shows it: a default Tester builds the frame again keeping nothing and shows the pill whatever
  // the page's view read)
  let t = tape_chat(0, 690.0, 840.0, width="medium", height="medium")
  t.check_looks(false)
  page_over(t, 690.0)
  let (mx, my) = t.find("做完了：列表、跳到最新的按钮").unwrap()
  mouse_dragged(t, mx, my, mx + 300.0, my)
  assert_true(t.ctx().selected_text() != "")
  assert_true(pill_over(t, my) is Some(_), msg="no 引用 over what is picked, in the frame it let go in")
  t.run_for(@ui.move_most_ms)
  assert_true(pill_over(t, my) is Some(_), msg="引用 gone once all the let-go set off is over")
  t.touch(1, mx + 320.0, my + 40.0)
  t.frames_owed()
  assert_true(pill_over(t, my) is Some(_), msg="引用 gone after the pointer moved")
  // (a click of its own, not a second of the press that picked: a double click's picks a word)
  t.run_for(@ui.double_click_ms)
  mouse_clicked(t, mx, my)
  t.run_for(@ui.move_most_ms)
  assert_eq(t.ctx().selected_text(), "")
  assert_true(t.words().filter(fn(w) { w.0 == "引用" }).is_empty(), msg="引用 still there after a press")
}
